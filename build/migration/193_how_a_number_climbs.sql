-- The roll-up, and the one rule that makes it correct.
--
-- From the v2 design, in its own words:
--
--     "A rate does not add up. Counts and rupees accumulate -- today's
--      number is added to the month, and a split KPI is the sum of its
--      parts. A percentage or a score is a level, not a quantity: today's
--      entry REPLACES the month-to-date figure, and a split one is the
--      average of its parts weighted by their targets, so a big
--      sub-category does not count the same as a small one. Getting this
--      wrong is how 93% and 88% became 286%."
--
-- So every measure is one of two kinds and they behave differently at three
-- separate joins: across days, across a person's own splits, and across a
-- team. All three are here, and all three respect the kind.

-- Which kind a measure is. The catalogue's own accrual enum decides when it
-- says anything; the unit is the fallback, using the design's own test.
create or replace function public.perf_accrual_kind(p_kpi uuid, p_unit text)
returns text language plpgsql stable as $fn$
declare a text; u text;
begin
  if p_kpi is not null then
    select lower(k.accrual::text) into a from kpi_definition k where k.id = p_kpi;
  end if;
  if a is not null then
    if a like '%sum%' or a like '%total%' or a like '%cumul%' or a like '%count%' then
      return 'SUM';
    end if;
    if a like '%avg%' or a like '%aver%' or a like '%level%' or a like '%rate%'
       or a like '%last%' or a like '%latest%' or a like '%replace%' then
      return 'LEVEL';
    end if;
  end if;
  -- the design's fallback: /%|score/i is a level, everything else accumulates
  u := coalesce(p_unit, '');
  if u ~* '%|score|rate|ratio|pct|percent' then return 'LEVEL'; end if;
  return 'SUM';
end $fn$;

-- What a measure currently stands at.
--
-- p_depth guards against a roll-up cycle. The trigger on perf_assignment
-- stops a row pointing at itself or at its own person, but A->B->C->A across
-- three people is still expressible, and a recursive function that meets one
-- does not return.
create or replace function public.perf_value(p_assignment uuid, p_depth int default 0)
returns numeric language plpgsql stable as $fn$
declare
  a perf_assignment; kind text;
  v numeric; wsum numeric := 0; w numeric := 0; cv numeric; cw numeric;
  r record; has_parts boolean;
begin
  if p_depth > 12 then
    raise exception 'the roll-up is a loop: % is above itself', p_assignment;
  end if;
  select * into a from perf_assignment where id = p_assignment;
  if a.id is null then return null; end if;
  kind := perf_accrual_kind(a.kpi_id, a.unit);
  has_parts := exists (select 1 from perf_assignment c where c.part_of_id = a.id);

  if has_parts then
    -- this person's own splits. A parent is never typed into, so there is
    -- nothing of its own to add.
    if kind = 'SUM' then
      select sum(perf_value(c.id, p_depth + 1)) into v
        from perf_assignment c where c.part_of_id = a.id;
    else
      for r in select c.id, coalesce(c.target_value, 1) as t
                 from perf_assignment c where c.part_of_id = a.id loop
        cv := perf_value(r.id, p_depth + 1);
        if cv is not null then wsum := wsum + cv * r.t; w := w + r.t; end if;
      end loop;
      v := case when w = 0 then null else wsum / w end;
    end if;
  else
    -- what this person filed
    if kind = 'SUM' then
      select sum(e.value) into v from perf_entry e where e.assignment_id = a.id;
    else
      select e.value into v from perf_entry e
       where e.assignment_id = a.id order by e.as_of desc, e.filed_at desc limit 1;
    end if;
  end if;

  -- and what the team contributed
  if exists (select 1 from perf_assignment c where c.rolls_into_id = a.id) then
    if kind = 'SUM' then
      select coalesce(v, 0) + coalesce(sum(perf_value(c.id, p_depth + 1)), 0) into v
        from perf_assignment c where c.rolls_into_id = a.id;
    else
      -- the manager's own number counts as one more weighted part
      wsum := 0; w := 0;
      if v is not null then
        wsum := v * coalesce(a.target_value, 1); w := coalesce(a.target_value, 1);
      end if;
      for r in select c.id, coalesce(c.target_value, 1) as t
                 from perf_assignment c where c.rolls_into_id = a.id loop
        cv := perf_value(r.id, p_depth + 1);
        if cv is not null then wsum := wsum + cv * r.t; w := w + r.t; end if;
      end loop;
      v := case when w = 0 then null else wsum / w end;
    end if;
  end if;

  return v;
end $fn$;

-- What is due from somebody on a given day, from the cadence they were given.
-- Weekends and confirmed holidays do not count -- the tool has one clock and
-- this uses it, the same plb_wd_* helpers the dispute window runs on.
create or replace function public.perf_due(p_person uuid, p_on date default current_date)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare out jsonb := '[]'::jsonb; r record; cad text; due boolean;
begin
  for r in
    select a.id, a.name, a.unit, a.target_value, a.cadence::text as cadence, a.cadence_day,
           a.split_label, c.period_start, c.entry_closes,
           (select max(e.as_of) from perf_entry e where e.assignment_id = a.id) as last_filed
      from perf_assignment a
      join perf_cycle c on c.id = a.cycle_id
     where a.person_id = p_person
       and a.state in ('ISSUED','ACKNOWLEDGED')
       and p_on between c.period_start and c.entry_closes
       -- a measure with parts is filed through its parts
       and not exists (select 1 from perf_assignment x where x.part_of_id = a.id)
  loop
    cad := upper(coalesce(r.cadence, 'MONTH_END'));
    due := case
      when cad like 'DAIL%' then true
      when cad like 'WEEK%' then extract(isodow from p_on) = coalesce(r.cadence_day, 5)
      when cad like '%DAY%' or cad like '%DATE%' then extract(day from p_on) = coalesce(r.cadence_day, 10)
      when cad like '%MONTH%' then p_on = r.entry_closes
      else p_on = r.entry_closes end;
    if due then
      out := out || jsonb_build_object(
        'assignmentId', r.id, 'name', r.name,
        'split', r.split_label, 'unit', r.unit, 'target', r.target_value,
        'cadence', r.cadence, 'lastFiled', r.last_filed,
        'alreadyFiled', exists (select 1 from perf_entry e
                                 where e.assignment_id = r.id and e.as_of = p_on));
    end if;
  end loop;
  return out;
end $fn$;

revoke all on function public.perf_accrual_kind(uuid, text) from public, anon, authenticated;
revoke all on function public.perf_value(uuid, int) from public, anon, authenticated;
revoke all on function public.perf_due(uuid, date) from public, anon, authenticated;
