-- =====================================================================
-- Crux baseline | 40_functions_3.sql | functions, part 3 of 4
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- Ordered by name, not by dependency. Load with check_function_bodies off.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.perf_assign_remove(p_actor uuid, p_assignment uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a perf_assignment; c perf_cycle; n_filed int; n_kids int; n_split int;
begin
  select * into a from perf_assignment where id = p_assignment;
  if a.id is null then return jsonb_build_object('error','no_such_assignment'); end if;
  if not perf_may_set(p_actor, a.person_id) then
    return jsonb_build_object('error','not_permitted',
      'reason','A measure is taken back by the person''s own manager or by an administrator -- and never by themselves.');
  end if;
  if a.state = 'WITHDRAWN' then
    return jsonb_build_object('ok', true, 'withdrawn', true, 'changed', false,
      'note','That measure has already been taken back.');
  end if;
  select * into c from perf_cycle where id = a.cycle_id;
  if current_date > c.assign_closes
     and not exists (select 1 from person where id = p_actor and app_role='ADMIN') then
    return jsonb_build_object('error','window_closed',
      'reason','Measures for ' || c.period_start || ' had to be settled by ' || c.assign_closes
            || '. HR or an administrator can reopen the month on the Performance screen, and the reopening is recorded.');
  end if;
  select count(*) into n_kids from perf_assignment x
   where x.rolls_into_id = a.id and x.person_id <> a.person_id
     and x.state is distinct from 'WITHDRAWN';
  if n_kids > 0 then
    return jsonb_build_object('error','feeds_this',
      'reason', n_kids || ' measure(s) below this one climb into it. Move or take those back first, or their numbers have nowhere to add up to.');
  end if;
  select count(*) into n_filed from perf_entry e
   where e.assignment_id = a.id
      or e.assignment_id in (select x.id from perf_assignment x where x.part_of_id = a.id);
  select count(*) into n_split from perf_assignment where part_of_id = a.id;
  update perf_assignment set state='WITHDRAWN' where id = a.id or part_of_id = a.id;
  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor,'PERF_KPI_WITHDRAWN','perf_assignment', a.id::text,
          jsonb_build_object('name',a.name,'unit',a.unit,'target',a.target_value,
                             'person',a.person_id,'state',a.state,'splits',n_split),
          jsonb_build_object('state','WITHDRAWN','filings',n_filed));
  return jsonb_build_object('ok',true,'withdrawn',true,'changed',true,
    'filings',n_filed,'splits',n_split,
    'note','Taken back. It stops being asked for and stops counting'
         || case when n_split>0 then ', and its ' || n_split || ' client share(s) went with it' else '' end
         || case when n_filed>0 then '. The ' || n_filed || ' figure(s) already filed against it still read back, because they are a record of what happened'
                 else '. Nothing had been filed against it' end || '.');
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_assignment_edges()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare p perf_assignment;
begin
  if new.part_of_id is not null then
    select * into p from perf_assignment where id = new.part_of_id;
    if p.person_id <> new.person_id then
      raise exception 'a split belongs to the same person as the measure it splits';
    end if;
    if p.cycle_id <> new.cycle_id then
      raise exception 'a split belongs to the same cycle as the measure it splits';
    end if;
    if p.part_of_id is not null then
      raise exception 'a split cannot itself be split; one level is the whole idea';
    end if;
  end if;

  if new.rolls_into_id is not null then
    select * into p from perf_assignment where id = new.rolls_into_id;
    if p.person_id = new.person_id then
      raise exception 'a measure climbs into somebody else''s; use part_of_id for your own splits';
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_carry_forward(p_actor uuid, p_cycle uuid, p_person uuid, p_keep_targets boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c perf_cycle; prev perf_cycle; n int := 0; r record; v_id uuid;
begin
  if not perf_may_set(p_actor, p_person) then
    return jsonb_build_object('error','not_permitted');
  end if;
  select * into c from perf_cycle where id = p_cycle;
  if c.id is null then return jsonb_build_object('error','no_such_cycle'); end if;
  if current_date > c.assign_closes
     and not exists (select 1 from person where id = p_actor and app_role = 'ADMIN') then
    return jsonb_build_object('error','window_closed',
      'reason','KPIs for ' || c.period_start || ' had to be set by ' || c.assign_closes || '. HR or an administrator can reopen the month.');
  end if;
  select * into prev from perf_cycle
   where period_kind = c.period_kind and period_start < c.period_start
   order by period_start desc limit 1;
  if prev.id is null then
    return jsonb_build_object('ok', true, 'copied', 0,
      'note','There is no earlier cycle to carry forward from.');
  end if;
  for r in select * from perf_assignment
            where cycle_id = prev.id and person_id = p_person and part_of_id is null
              and state is distinct from 'WITHDRAWN'
            order by name loop
    insert into perf_assignment (cycle_id, person_id, kpi_id, name, unit,
        target_value, weight_pct, cadence_day, set_by, carried_from_id, note)
    values (c.id, p_person, r.kpi_id, r.name, r.unit,
            case when p_keep_targets then r.target_value else null end,
            r.weight_pct, r.cadence_day, p_actor, r.id, r.note)
    on conflict do nothing
    returning id into v_id;
    if v_id is not null then
      execute format('update perf_assignment set cadence = (select cadence from perf_assignment where id = %L) where id = %L', r.id, v_id);
      n := n + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'copied', n,
    'note', n || ' measure(s) carried from ' || prev.period_start ||
      case when p_keep_targets then ' with last month''s targets.'
           else '. The targets are blank on purpose -- last month''s number is not this month''s promise.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_cascade(p_assignment uuid, p_depth integer DEFAULT 0)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a perf_assignment; kind text; r record;
  v_pinned numeric := 0; v_free int := 0; v_each numeric; v_n int := 0;
begin
  if p_depth > 12 then return 0; end if;
  select * into a from perf_assignment where id = p_assignment;
  if a.id is null or a.target_value is null then return 0; end if;
  kind := perf_accrual_kind(a.kpi_id, a.unit);

  select coalesce(sum(case when c.target_source = 'MANUAL'
                           then coalesce(c.target_value,0) else 0 end), 0),
         count(*) filter (where c.target_source <> 'MANUAL')
    into v_pinned, v_free
    from perf_assignment c where c.rolls_into_id = a.id;
  if v_free = 0 then return 0; end if;

  if kind = 'SUM' then
    v_each := round((a.target_value - v_pinned) / v_free, 2);
    if v_each < 0 then v_each := 0; end if;
  else
    v_each := a.target_value;
  end if;

  for r in select c.id from perf_assignment c
            where c.rolls_into_id = a.id and c.target_source <> 'MANUAL'
  loop
    update perf_assignment set target_value = v_each, target_source = 'SHARED' where id = r.id;
    v_n := v_n + 1 + perf_cascade(r.id, p_depth + 1);
  end loop;
  return v_n;
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_climb(p_cycle uuid, p_person uuid, p_family text, p_direction text, p_kind text)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_up uuid := p_person; v_hops int := 0; v_into uuid;
begin
  if p_family is null then return null; end if;
  loop
    select manager_id into v_up from person
     where id = v_up and manager_id is not null and manager_id <> id;
    exit when v_up is null or v_hops >= 12;
    v_hops := v_hops + 1;
    select a.id into v_into from perf_assignment a
     where a.cycle_id = p_cycle and a.person_id = v_up and a.part_of_id is null
       and perf_family(a.unit) = p_family
       and perf_direction(a.unit) = p_direction
       and perf_accrual_kind(a.kpi_id, a.unit) = p_kind
     order by a.id limit 1;
    if v_into is not null then return v_into; end if;
  end loop;
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_cycle_extend(p_actor uuid, p_cycle uuid, p_until date, p_why text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a person%rowtype; c perf_cycle; v_was date;
begin
  select * into a from person where id=p_actor and employment_status='ACTIVE' and superseded_by is null;
  if a.id is null or (a.app_role <> 'ADMIN'
                      and coalesce(a.department,'') <> 'Human Resources'
                      and coalesce(a.department,'') <> 'Business Excellence') then
    return jsonb_build_object('error','not_permitted',
      'reason','Reopening a month for KPI setting is HR''s, Business Excellence''s or an administrator''s -- the same three who open it.');
  end if;
  select * into c from perf_cycle where id=p_cycle;
  if c.id is null then return jsonb_build_object('error','no_such_cycle'); end if;
  if p_why is null or btrim(p_why)='' then
    return jsonb_build_object('error','reason_required',
      'reason','Reopening a month changes what a team can still be asked for, so it carries the reason it was reopened.');
  end if;
  if p_until is null then
    return jsonb_build_object('error','no_date','reason','Say the date KPI setting should close instead.');
  end if;
  if p_until < current_date then
    return jsonb_build_object('error','already_past',
      'reason', p_until || ' is in the past, so it would shut the month rather than reopen it.');
  end if;
  if p_until <= c.assign_closes then
    return jsonb_build_object('error','not_later',
      'reason','KPIs for ' || c.period_start || ' can already be set until ' || c.assign_closes || '. This only ever moves that date later.');
  end if;
  if p_until > c.entry_closes then
    return jsonb_build_object('error','after_filing_closes',
      'reason','Filing for ' || c.period_start || ' closes on ' || c.entry_closes || ', so a KPI set after that could never be filed against.');
  end if;
  v_was := c.assign_closes;
  update perf_cycle set assign_closes = p_until where id = c.id;
  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor,'PERF_CYCLE_EXTENDED','perf_cycle', c.id::text,
          jsonb_build_object('assignCloses', v_was),
          jsonb_build_object('assignCloses', p_until, 'why', btrim(p_why), 'by', a.full_name));
  return jsonb_build_object('ok',true,'cycleId',c.id,'period',c.period_start,
    'was',v_was,'assignCloses',p_until,
    'note','KPIs for ' || c.period_start || ' may now be set until ' || p_until || '. Who reopened it and why is recorded.');
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_cycle_open(p_actor uuid, p_period date, p_kind text DEFAULT 'MONTH'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a person%rowtype; s date; e date; c perf_cycle;
begin
  select * into a from person where id = p_actor;
  if a.id is null or (a.app_role <> 'ADMIN'
                      and coalesce(a.department,'') <> 'Human Resources'
                      and coalesce(a.department,'') <> 'Business Excellence') then
    return jsonb_build_object('error','not_permitted',
      'reason','Opening a performance cycle is HR''s, Business Excellence''s or an administrator''s.');
  end if;
  s := date_trunc(case when p_kind = 'QUARTER' then 'quarter' else 'month' end, p_period)::date;
  e := (s + case when p_kind = 'QUARTER' then interval '3 months' else interval '1 month' end)::date - 1;
  select * into c from perf_cycle where period_start = s and period_kind = p_kind;
  if c.id is not null then
    return jsonb_build_object('ok', true, 'cycleId', c.id, 'note','That cycle was already open.');
  end if;
  insert into perf_cycle (period_start, period_kind, assign_opens, assign_closes,
                          entry_closes, opened_by)
  values (s, p_kind, s, plb_wd_after(s, 5, null), plb_wd_after(e, 5, null), p_actor)
  returning * into c;
  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, 'PERF_CYCLE_OPENED', 'perf_cycle', c.id::text, null,
          jsonb_build_object('period', s, 'kind', p_kind,
                             'assignBy', c.assign_closes, 'entriesClose', c.entry_closes));
  return jsonb_build_object('ok', true, 'cycleId', c.id, 'period', s,
    'assignBy', c.assign_closes, 'entriesClose', c.entry_closes,
    'note', 'KPIs may be set until ' || c.assign_closes ||
            '. Numbers may be filed until ' || c.entry_closes || '.');
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_direction(p_unit text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when lower(coalesce(p_unit, ''))
                   ~ 'below|variance|returned|escalat|attrition|error|vacant|dso|days to|cost per|per case'
              then 'CEILING' else 'FLOOR' end
$function$
;

CREATE OR REPLACE FUNCTION public.perf_due(p_person uuid, p_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  out jsonb := '[]'::jsonb; r record; cad text; due boolean;
  centre text; nominal date; eff date;
begin
  centre := person_centre(p_person);
  if not is_working_day(p_on, centre) then return out; end if;

  for r in
    select a.id, a.name, a.unit, a.target_value,
           coalesce(a.cadence, par.cadence)::text as cadence,
           coalesce(a.cadence_day, par.cadence_day) as cadence_day,
           a.split_label, c.period_start, c.entry_closes,
           (select max(e.as_of) from perf_entry e where e.assignment_id = a.id) as last_filed
      from perf_assignment a
      join perf_cycle c on c.id = a.cycle_id
      left join perf_assignment par on par.id = a.part_of_id
     where a.person_id = p_person
       and a.state in ('ISSUED','ACKNOWLEDGED')
       and p_on between c.period_start and c.entry_closes
       and not exists (select 1 from perf_assignment x where x.part_of_id = a.id)
  loop
    cad := upper(coalesce(r.cadence, 'MONTH_END'));

    if cad like 'DAIL%' then
      due := true;
    elsif cad like 'WEEK%' then
      nominal := p_on - (extract(isodow from p_on)::int - coalesce(r.cadence_day, 5));
      eff := perf_roll_forward(nominal, centre);
      due := p_on = eff;
    elsif cad like '%DAY%' or cad like '%DATE%' then
      nominal := least(
        date_trunc('month', p_on)::date + (coalesce(r.cadence_day, 10) - 1),
        (date_trunc('month', p_on) + interval '1 month')::date - 1);
      eff := perf_roll_forward(nominal, centre);
      due := p_on = eff;
    else
      due := p_on = r.entry_closes;
    end if;

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
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_entry_not_on_a_parent()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if exists (select 1 from perf_assignment a
              where a.part_of_id = new.assignment_id) then
    raise exception 'that measure is split into parts; file against the parts and the total follows';
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_family(p_unit text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select nullif(btrim(split_part(coalesce(p_unit, ''), '·', 2)), '')
$function$
;

CREATE OR REPLACE FUNCTION public.perf_file(p_actor uuid, p_assignment uuid, p_as_of date, p_value numeric, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a perf_assignment; c perf_cycle; was numeric;
begin
  select * into a from perf_assignment where id = p_assignment;
  if a.id is null then return jsonb_build_object('error','no_such_assignment'); end if;
  select * into c from perf_cycle where id = a.cycle_id;

  if a.person_id <> p_actor
     and not exists (select 1 from person where id = p_actor and app_role = 'ADMIN') then
    return jsonb_build_object('error','not_yours',
      'reason','Numbers are filed by the person they are about. A manager scores; they do not file on somebody''s behalf.');
  end if;
  if p_as_of < c.period_start or p_as_of > c.entry_closes then
    return jsonb_build_object('error','outside_the_period',
      'reason','That day is not in ' || c.period_start || '.');
  end if;
  if current_date > c.entry_closes then
    return jsonb_build_object('error','entries_closed',
      'reason','Filing for ' || c.period_start || ' closed on ' || c.entry_closes || '.');
  end if;
  if a.state = 'LOCKED' then
    return jsonb_build_object('error','locked','reason','That measure is locked for scoring.');
  end if;
  if exists (select 1 from perf_assignment x where x.part_of_id = a.id) then
    return jsonb_build_object('error','has_parts',
      'reason','That measure is split into parts. File against the parts and the '
               || 'total follows -- a total typed in beside its own parts is how two '
               || 'right numbers make a wrong one.');
  end if;

  select value into was from perf_entry where assignment_id = p_assignment and as_of = p_as_of;

  insert into perf_entry (assignment_id, as_of, value, note, filed_by)
  values (p_assignment, p_as_of, p_value, p_note, p_actor)
  on conflict (assignment_id, as_of) do update
    set value = excluded.value, note = excluded.note,
        filed_by = excluded.filed_by, filed_at = now();

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, case when was is null then 'PERF_FILED' else 'PERF_REFILED' end,
          'perf_assignment', p_assignment::text,
          case when was is null then null else jsonb_build_object('value', was) end,
          jsonb_build_object('asOf', p_as_of, 'value', p_value, 'note', p_note));

  return jsonb_build_object('ok', true, 'value', perf_value(p_assignment),
    'note', case when was is null then 'Filed.'
                 else 'Changed from ' || was || '. The earlier figure is in the trail.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_filed_days(p_person uuid, p_days integer DEFAULT 14, p_to date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with span as (
    select generate_series(p_to - (greatest(p_days, 1) - 1), p_to, interval '1 day')::date as d
  ),
  filed as (
    select distinct e.as_of
      from perf_entry e
      join perf_assignment a on a.id = e.assignment_id
     where a.person_id = p_person
       and e.as_of between p_to - (greatest(p_days, 1) - 1) and p_to
  ),
  mark as (
    select s.d,
           is_working_day(s.d, null) as wd,
           (f.as_of is not null)     as ok
      from span s left join filed f on f.as_of = s.d
  ),
  gap as (select max(d) as d from mark where wd and not ok)
  select jsonb_build_object(
    'from', (select min(d) from mark),
    'to',   (select max(d) from mark),
    'days', (select coalesce(jsonb_agg(jsonb_build_object(
                      'day', m.d, 'dow', to_char(m.d, 'Dy'), 'dd', to_char(m.d, 'FMDD'),
                      'working', m.wd, 'filed', m.ok) order by m.d), '[]'::jsonb)
               from mark m),
    'filedDays',   (select count(*) from mark where ok),
    'workingDays', (select count(*) from mark where wd),
    'run',         (select count(*) from mark m, gap
                     where m.ok and (gap.d is null or m.d > gap.d)));
$function$
;

CREATE OR REPLACE FUNCTION public.perf_gate_probe()
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$ select 1 $function$
;

CREATE OR REPLACE FUNCTION public.perf_handover(p_actor uuid, p_cycle uuid, p_person uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_who uuid; v_rel text;
begin
  v_who := coalesce(p_person, p_actor);
  v_rel := perf_rel(p_actor, v_who);
  if v_rel is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That person is not in your line.');
  end if;

  return jsonb_build_object(
    'rel', v_rel,

    -- The summary first, and it is not a nicety. A Branch Manager with
    -- forty-two executives gets eighty-six numbers handed to them; a list
    -- of eighty-six is not a briefing, it is a wall. Grouped by measure
    -- there are three lines, each saying how the team stands and who is
    -- furthest from the mark -- which is what the person filing their own
    -- number actually needs to know.
    'summary', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', q.name, 'unit', q.unit, 'family', q.family,
               'direction', q.direction, 'kind', q.kind,
               'people', q.people, 'filed', q.filed,
               'target', q.target,
               'team', case when q.kind = 'SUM' then q.total else q.mean end,
               'best', case when q.direction = 'CEILING' then q.lo else q.hi end,
               'worst', case when q.direction = 'CEILING' then q.hi else q.lo end,
               'atOrAbove', q.made,
               'pct', case when coalesce(q.target,0) = 0 then null
                           else round(100.0
                                * (case when q.kind = 'SUM' then q.total else q.mean end)
                                / q.target, 1) end)
             order by q.name)
        from (
          select a.name, a.unit,
                 perf_family(a.unit) as family,
                 perf_direction(a.unit) as direction,
                 perf_accrual_kind(a.kpi_id, a.unit) as kind,
                 count(*) as people,
                 count(perf_value(a.id)) as filed,
                 avg(a.target_value) as target,
                 sum(perf_value(a.id)) as total,
                 avg(perf_value(a.id)) as mean,
                 min(perf_value(a.id)) as lo,
                 max(perf_value(a.id)) as hi,
                 count(*) filter (
                   where perf_value(a.id) is not null and a.target_value is not null
                     and ((perf_direction(a.unit) = 'CEILING'
                           and perf_value(a.id) <= a.target_value)
                       or (perf_direction(a.unit) = 'FLOOR'
                           and perf_value(a.id) >= a.target_value))) as made
            from perf_line(v_who) l
            join perf_assignment a on a.person_id = l.person_id
           where l.depth = 1
             and a.cycle_id = p_cycle
             and a.part_of_id is null
             and a.rolls_into_id is null
           group by a.name, a.unit, perf_family(a.unit),
                    perf_direction(a.unit), perf_accrual_kind(a.kpi_id, a.unit)
        ) q), '[]'::jsonb),

    'from', coalesce((
      select jsonb_agg(x order by x->>'name')
        from (
          select jsonb_build_object(
                   'personId', p.id,
                   'name', p.full_name,
                   'employeeNo', p.employee_no,
                   'chair', (select ch.title from chair_holder h
                              join chair ch on ch.id = h.chair_id
                             where h.person_id = p.id and h.to_date is null
                             order by h.is_primary desc limit 1),
                   'measures', coalesce((
                     select jsonb_agg(jsonb_build_object(
                              'assignmentId', a.id, 'name', a.name,
                              'unit', a.unit, 'family', perf_family(a.unit),
                              'direction', perf_direction(a.unit),
                              'kind', perf_accrual_kind(a.kpi_id, a.unit),
                              'target', a.target_value,
                              'value', perf_value(a.id),
                              'pct', case when coalesce(a.target_value,0) = 0 then null
                                          else round(100.0 * perf_value(a.id)
                                                     / a.target_value, 1) end,
                              'filings', (select count(*) from perf_entry e
                                           where e.assignment_id = a.id),
                              'lastFiled', (select max(e.as_of) from perf_entry e
                                             where e.assignment_id = a.id),
                              'feeders', (select count(*) from perf_assignment g
                                           where g.rolls_into_id = a.id))
                            order by a.name)
                       from perf_assignment a
                      where a.person_id = p.id
                        and a.cycle_id = p_cycle
                        and a.part_of_id is null
                        and a.rolls_into_id is null), '[]'::jsonb)) as x
            from perf_line(v_who) l
            join person p on p.id = l.person_id
           where l.depth = 1
             and exists (select 1 from perf_assignment a
                          where a.person_id = p.id and a.cycle_id = p_cycle
                            and a.part_of_id is null and a.rolls_into_id is null)
        ) q), '[]'::jsonb),
    'note', 'These numbers stop with the person who filed them, because what '
            'they measure is not what you are measured on. Read them, then '
            'file your own.');
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_history(p_person uuid, p_name text, p_kpi uuid DEFAULT NULL::uuid, p_months integer DEFAULT 6)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(x order by x->>'period'), '[]'::jsonb) from (
    select jsonb_build_object(
             'period', c.period_start, 'target', a.target_value,
             'value', perf_value(a.id),
             'pct', case when coalesce(a.target_value,0) = 0 then null
                         else round(100.0 * perf_value(a.id) / a.target_value, 1) end) as x
      from perf_assignment a
      join perf_cycle c on c.id = a.cycle_id
     where a.person_id = p_person
       and a.part_of_id is null
       and ((p_kpi is not null and a.kpi_id = p_kpi)
            or (p_kpi is null and lower(btrim(a.name)) = lower(btrim(p_name))))
       and c.period_kind = 'MONTH'
       and c.period_start >= (date_trunc('month', current_date) - (p_months || ' months')::interval)::date
  ) t;
$function$
;

CREATE OR REPLACE FUNCTION public.perf_history_for(p_actor uuid, p_person uuid, p_name text, p_kpi uuid, p_months integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if perf_rel(p_actor, p_person) is null then
    return jsonb_build_object('error','not_permitted','reason','That person is not in your line.');
  end if;
  return perf_history(p_person, p_name, p_kpi, p_months);
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_kpi_score(p_person uuid, p_cycle uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; wsum numeric := 0; w numeric := 0; n int := 0; skipped int := 0;
        rows jsonb := '[]'::jsonb; ratio numeric; v numeric;
begin
  for r in select a.* from perf_assignment a
            where a.person_id = p_person and a.cycle_id = p_cycle and a.state <> 'WITHDRAWN' and a.part_of_id is null
            order by a.name loop
    v := perf_value(r.id);
    if coalesce(r.target_value, 0) = 0 or v is null then
      skipped := skipped + 1;
      rows := rows || jsonb_build_object('name', r.name, 'value', v,
        'target', r.target_value, 'counted', false,
        'why', array_to_string(array_remove(array[
                 case when coalesce(r.target_value, 0) = 0 then 'no target was set' end,
                 case when v is null then 'nothing filed yet' end], null), ' and '));
    else
      ratio := least(150, round(100.0 * v / r.target_value, 2));
      wsum := wsum + ratio * coalesce(r.weight_pct, 1);
      w := w + coalesce(r.weight_pct, 1);
      n := n + 1;
      rows := rows || jsonb_build_object('name', r.name, 'value', v,
        'target', r.target_value, 'pct', ratio, 'weight', r.weight_pct, 'counted', true);
    end if;
  end loop;

  return jsonb_build_object(
    'measures', rows, 'counted', n, 'skipped', skipped,
    'achievement', case when w = 0 then null else round(wsum / w, 2) end,
    'says', case
      when n = 0 then 'Nothing can be scored yet: no measure has both a target and a number.'
      when skipped > 0 then n || ' of ' || (n + skipped) ||
        ' measures scored. The rest are listed with the reason they are not, rather than counted as zero.'
      else 'All ' || n || ' measures scored.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_kpi_score_for(p_actor uuid, p_person uuid, p_cycle uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if perf_rel(p_actor, p_person) is null then
    return jsonb_build_object('error','not_permitted','reason','That person is not in your line.');
  end if;
  return perf_kpi_score(p_person, p_cycle);
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_line(p_actor uuid)
 RETURNS TABLE(person_id uuid, depth integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with recursive edge as (
    -- the seating tree: this seat, in this place, reports to that one
    select distinct hs.person_id as mgr, hr.person_id as rep
      from chair_seating cs
      join chair_holder hs on hs.seating_id = cs.reports_to_seating_id and hs.to_date is null
      join chair_holder hr on hr.seating_id = cs.id and hr.to_date is null
     where hs.person_id <> hr.person_id
    union
    -- and the reporting line as the person record states it
    select p.manager_id, p.id from person p
     where p.manager_id is not null and p.manager_id <> p.id
       and p.employment_status = 'ACTIVE' and p.superseded_by is null
  ),
  walk as (
    select e.rep as pid, 1 as d, array[p_actor, e.rep] as seen
      from edge e where e.mgr = p_actor
    union all
    select e.rep, w.d + 1, w.seen || e.rep
      from walk w join edge e on e.mgr = w.pid
     where w.d < 12 and not (e.rep = any (w.seen))
  )
  select w.pid, min(w.d)::int
    from walk w join person p on p.id = w.pid
   where p.employment_status = 'ACTIVE' and p.superseded_by is null
     and coalesce(p.employee_type, 'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
     and w.pid <> p_actor
   group by w.pid
$function$
;

CREATE OR REPLACE FUNCTION public.perf_may_see(p_actor uuid, p_person uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select perf_rel(p_actor, p_person) is not null $function$
;

CREATE OR REPLACE FUNCTION public.perf_may_set(p_actor uuid, p_person uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(perf_rel(p_actor, p_person) in ('manage','admin'), false)
$function$
;

CREATE OR REPLACE FUNCTION public.perf_node(p_assignment uuid, p_depth integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a perf_assignment; v numeric; parts jsonb; team jsonb;
begin
  if p_depth > 12 then return jsonb_build_object('error','too_deep'); end if;
  select * into a from perf_assignment where id = p_assignment;
  if a.id is null then return null; end if;
  v := perf_value(a.id);

  select coalesce(jsonb_agg(perf_node(c.id, p_depth + 1) order by c.split_label, c.name), '[]'::jsonb)
    into parts from perf_assignment c where c.part_of_id = a.id;

  select coalesce(jsonb_agg(
           perf_node(c.id, p_depth + 1) ||
           jsonb_build_object('person', jsonb_build_object(
             'personId', p.id, 'name', p.full_name, 'employeeNo', p.employee_no,
             'chair', (select ch.title from chair_holder h join chair ch on ch.id = h.chair_id
                        where h.person_id = p.id and h.to_date is null
                        order by h.is_primary desc limit 1)))
           order by p.full_name), '[]'::jsonb)
    into team
    from perf_assignment c join person p on p.id = c.person_id
   where c.rolls_into_id = a.id;

  return jsonb_build_object(
    'assignmentId', a.id, 'name', a.name, 'unit', a.unit,
    'split', a.split_label, 'splitKind', a.split_kind,
    'target', a.target_value, 'value', v,
    'pct', case when coalesce(a.target_value,0) = 0 then null
                else round(100.0 * v / a.target_value, 1) end,
    'kind', perf_accrual_kind(a.kpi_id, a.unit),
    'cadence', a.cadence::text, 'cadenceDay', a.cadence_day,
    'weight', a.weight_pct, 'state', a.state,
    'rollsInto', a.rolls_into_id,
    'filings', (select count(*) from perf_entry e where e.assignment_id = a.id),
    'lastFiled', (select max(e.as_of) from perf_entry e where e.assignment_id = a.id),
    'parts', parts, 'team', team);
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_org_rollup(p_actor uuid, p_cycle uuid, p_person uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_who uuid; v_rel text;
begin
  v_who := coalesce(p_person, p_actor);
  v_rel := perf_rel(p_actor, v_who);
  if v_rel is null then
    return jsonb_build_object('error','not_permitted','reason','That person is not in your line.');
  end if;
  return jsonb_build_object(
    'rel', v_rel,
    'person', (select jsonb_build_object('personId', p.id, 'name', p.full_name,
                        'employeeNo', p.employee_no, 'department', p.department)
                 from person p where p.id = v_who),
    'teamSize', (select count(*) from perf_line(v_who)),
    'measures', coalesce((
      select jsonb_agg(jsonb_build_object(
               'assignmentId', a.id, 'name', a.name, 'unit', a.unit,
               'family', perf_family(a.unit), 'direction', perf_direction(a.unit),
               'kind', perf_accrual_kind(a.kpi_id, a.unit),
               'target', a.target_value, 'targetSource', a.target_source,
               'value', perf_value(a.id),
               'pct', case when coalesce(a.target_value,0) = 0 then null
                           else round(100.0 * perf_value(a.id) / a.target_value, 1) end,
               'feeders', (select count(*) from perf_assignment c where c.rolls_into_id = a.id),
               'filedToday', exists (select 1 from perf_entry e
                                      where e.assignment_id = a.id and e.as_of = current_date),
               'lastFiled', (select max(e.as_of) from perf_entry e where e.assignment_id = a.id))
             order by a.name)
        from perf_assignment a
       where a.person_id = v_who and a.cycle_id = p_cycle and a.part_of_id is null),
      '[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_quarter_value(p_person uuid, p_kpi uuid, p_quarter date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_kind text; v numeric;
begin
  select perf_accrual_kind(a.kpi_id, a.unit) into v_kind
    from perf_assignment a
   where a.person_id = p_person and a.kpi_id = p_kpi
     and a.cycle_id in (select plb_quarter_cycles(p_quarter))
   limit 1;
  if v_kind is null then return null; end if;

  if v_kind = 'SUM' then
    select sum(perf_value(a.id)) into v
      from perf_assignment a
     where a.person_id = p_person and a.kpi_id = p_kpi
       and a.part_of_id is null
       and a.cycle_id in (select plb_quarter_cycles(p_quarter));
  else
    -- A percentage across three months is the average of the months that
    -- have one, not of three months two of which are silent.
    select avg(x) into v from (
      select perf_value(a.id) as x
        from perf_assignment a
       where a.person_id = p_person and a.kpi_id = p_kpi
         and a.part_of_id is null
         and a.cycle_id in (select plb_quarter_cycles(p_quarter))) q
     where x is not null;
  end if;
  return v;
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_rel(p_actor uuid, p_person uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when p_actor is null or p_person is null then null
    when p_actor = p_person then 'self'
    when exists (select 1 from person a
                  where a.id = p_actor and a.app_role = 'ADMIN'
                    and a.employment_status = 'ACTIVE' and a.superseded_by is null) then 'admin'
    else (select case when l.depth = 1 then 'manage' else 'watch' end
            from perf_line(p_actor) l where l.person_id = p_person)
  end
$function$
;

CREATE OR REPLACE FUNCTION public.perf_relink(p_actor uuid, p_cycle uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role role_kind; r record; m record; v_into uuid;
  v_linked int := 0; v_cleared int := 0; v_top int := 0;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Rebuilding the roll-up is an administrator''s.');
  end if;

  update perf_assignment set rolls_into_id = null
   where cycle_id = p_cycle and rolls_into_id is not null;
  get diagnostics v_cleared = row_count;

  for r in
    select a.id, a.person_id, perf_family(a.unit) as fam,
           perf_direction(a.unit) as dir,
           perf_accrual_kind(a.kpi_id, a.unit) as kind
      from perf_assignment a
     where a.cycle_id = p_cycle and a.part_of_id is null
       and perf_family(a.unit) is not null
  loop
    -- The same family first, always: a code that does not change on the
    -- way up needs no row and must not be sent past its own parent.
    v_into := perf_climb(p_cycle, r.person_id, r.fam, r.dir, r.kind);

    -- Then each mapped parent in turn, until one of them is actually
    -- above this person. A family with three parents is not three
    -- guesses: the reporting line picks, and at most one can be in it.
    if v_into is null then
      for m in select parent_family from perf_rollup_map
                where child_family = r.fam and parent_family <> r.fam
                order by priority, parent_family
      loop
        v_into := perf_climb(p_cycle, r.person_id, m.parent_family, r.dir, r.kind);
        exit when v_into is not null;
      end loop;
    end if;

    if v_into is null then
      v_top := v_top + 1;
    else
      update perf_assignment set rolls_into_id = v_into where id = r.id;
      v_linked := v_linked + 1;
    end if;
  end loop;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'PERF_ROLLUP_REBUILT', 'perf_cycle', p_cycle::text,
          jsonb_build_object('linked', v_linked, 'cleared', v_cleared,
                             'handedOver', v_top));

  return jsonb_build_object('ok', true, 'linked', v_linked, 'cleared', v_cleared,
    'handedOver', v_top,
    'note', v_linked || ' measure(s) climb by arithmetic. ' || v_top ||
            ' stop, and are handed to the chair above to read and answer in '
            'their own number.');
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_reminder_sweep(p_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_run uuid; r record; due jsonb; item jsonb; lines text; body text;
  n_due int := 0; n_unset int := 0; n_skip int := 0; c perf_cycle;
  v_perf text; v_team text;
begin
  insert into job_run (job_key, started_at, state)
  values ('PERF_REMINDERS', now(), 'RUNNING') returning id into v_run;

  -- Asked once for the whole sweep rather than once per person: it is one
  -- setting and a hundred people, and it cannot change mid-sweep.
  v_perf := app_link('#perf');
  v_team := app_link('#people');

  for r in
    select p.id, p.full_name, lower(btrim(p.work_email)) as email
      from person p
     where p.employment_status = 'ACTIVE' and p.superseded_by is null
       and coalesce(btrim(p.work_email), '') <> ''
  loop
    due := perf_due(r.id, p_on);
    lines := '';
    for item in select jsonb_array_elements(due) loop
      if not coalesce((item->>'alreadyFiled')::boolean, false) then
        lines := lines || '  - ' || (item->>'name')
              || case when coalesce(item->>'split','') <> ''
                      then ' (' || (item->>'split') || ')' else '' end
              || case when coalesce(item->>'target','') <> ''
                      then ', target ' || (item->>'target')
                           || coalesce(' ' || perf_unit_plain(item->>'unit'), '')
                      else '' end
              -- The link goes on the activity's own line, which is what
              -- "in front of the activities" asks for: a person scanning
              -- five lines can act on the third without reading the other
              -- four to find out where to go.
              || coalesce(E'\n      File it: ' || v_perf, '')
              || E'\n';
      end if;
    end loop;

    if lines = '' then n_skip := n_skip + 1; continue; end if;

    body := 'Good morning ' || split_part(r.full_name, ' ', 1) || E',\n\n'
         || 'These are due from you today, ' || to_char(p_on, 'FMDD FMMonth YYYY') || E':\n\n'
         || lines || E'\n'
         || coalesce('Open Performance: ' || v_perf || E'\n\n', '')
         || 'The number is for today -- filing it tomorrow does not make it '
         || 'tomorrow''s number.' || E'\n';

    insert into outbox (idempotency_key, template_key, recipient, subject, body,
                        entity_type, entity_id, not_before, state)
    values (md5('PERF_DUE|' || r.email || '|' || p_on), 'PERF_DUE', r.email,
            'Due today in Crux', body, 'person', r.id, now(), 'QUEUED')
    on conflict (idempotency_key) do nothing;
    n_due := n_due + 1;
  end loop;

  select * into c from perf_cycle
   where period_kind = 'MONTH' and period_start = date_trunc('month', p_on)::date;

  if c.id is not null and p_on <= c.assign_closes then
    for r in
      select m.id, m.full_name, lower(btrim(m.work_email)) as email,
             string_agg('  - ' || t.full_name, E'\n' order by t.full_name) as who,
             count(*) as n
        from person m
        join person t on t.manager_id = m.id
       where m.employment_status = 'ACTIVE' and m.superseded_by is null
         and coalesce(btrim(m.work_email), '') <> ''
         and t.employment_status = 'ACTIVE' and t.superseded_by is null
         and not exists (select 1 from perf_assignment a
                          where a.person_id = t.id and a.cycle_id = c.id)
       group by m.id, m.full_name, m.work_email
    loop
      body := 'Good morning ' || split_part(r.full_name, ' ', 1) || E',\n\n'
           || r.n || ' of your team have no KPI for '
           || to_char(c.period_start, 'FMMonth YYYY') || E' yet:\n\n'
           || r.who || E'\n\n'
           || 'The window closes on ' || to_char(c.assign_closes, 'FMDD FMMonth')
           || '. After that an administrator can still change them, and it is recorded.'
           || E'\n\n'
           || coalesce('Set their targets: ' || v_team || E'\n',
                       E'Open Performance in Crux, then My team.\n');

      insert into outbox (idempotency_key, template_key, recipient, subject, body,
                          entity_type, entity_id, not_before, state)
      values (md5('PERF_UNSET|' || r.email || '|' || c.period_start), 'PERF_UNSET', r.email,
              'KPIs not set for ' || to_char(c.period_start, 'FMMonth YYYY'),
              body, 'person', r.id, now(), 'QUEUED')
      on conflict (idempotency_key) do nothing;
      n_unset := n_unset + 1;
    end loop;
  end if;

  update job_run set finished_at = now(), state = 'DONE',
         counts = jsonb_build_object('day', p_on, 'due_reminders', n_due,
                                     'unset_reminders', n_unset,
                                     'nothing_owed', n_skip,
                                     'cycle', c.id,
                                     -- Recorded per run, so "why did today's
                                     -- mail have no links" is answerable
                                     -- from the job row alone.
                                     'linked', v_perf is not null)
   where id = v_run;

  return jsonb_build_object('day', p_on, 'due', n_due, 'unset', n_unset,
    'linked', v_perf is not null,
    'note', case when n_due = 0 and n_unset = 0
      then 'Nothing was owed by anybody today, so nobody was written to.'
      else n_due || ' filing reminder(s) and ' || n_unset || ' setting reminder(s) queued.'
           || case when v_perf is null
                   then ' No app_url is set, so they carry no links -- set it and '
                        'tomorrow''s will.'
                   else '' end end);
exception when others then
  update job_run set finished_at = now(), state = 'FAILED', error = sqlerrm where id = v_run;
  raise;
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_roll_forward(p_day date, p_centre text)
 RETURNS date
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d date := p_day; n int := 0;
begin
  while n < 10 and not is_working_day(d, p_centre) loop
    d := d + 1; n := n + 1;
  end loop;
  return d;
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_seed_from_registry(p_actor uuid, p_cycle uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role role_kind; c perf_cycle; r record;
  v_made int := 0; v_linked int := 0; v_people int := 0; v_skipped int := 0;
  v_noset jsonb := '[]'::jsonb; v_last uuid;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Seeding the whole company from the registry is an administrator''s. A manager sets their own team''s, one at a time.');
  end if;

  select * into c from perf_cycle where id = p_cycle;
  if c.id is null then return jsonb_build_object('error','no_such_cycle'); end if;

  -- pass one: every seated person, every measure their own chair is measured on
  for r in
    select pe.id as person_id, pe.full_name, ch.id as chair_id, ch.code as chair_code,
           k.id as kpi_id, k.name, k.unit, k.cadence,
           round(100.0 / count(*) over (partition by ch.id), 2) as weight
      from chair_holder h
      join person pe on pe.id = h.person_id
      join chair  ch on ch.id = h.chair_id
      join kpi_definition k on k.chair_id = ch.id and k.active and k.position < 100
     where h.to_date is null
       and pe.employment_status = 'ACTIVE' and pe.superseded_by is null
       and coalesce(pe.employee_type, 'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
       and h.id = (select h2.id from chair_holder h2
                    where h2.person_id = pe.id and h2.to_date is null
                    order by h2.is_primary desc nulls last, h2.id limit 1)
     order by pe.full_name, k.position
  loop
    -- No unique key covers (cycle, person, kpi), so the check is explicit
    -- rather than an ON CONFLICT that would quietly do nothing.
    if exists (select 1 from perf_assignment a
                where a.cycle_id = c.id and a.person_id = r.person_id
                  and a.kpi_id = r.kpi_id) then
      v_skipped := v_skipped + 1; continue;
    end if;

    insert into perf_assignment (cycle_id, person_id, kpi_id, name, unit,
        target_value, weight_pct, cadence, set_by, state, note)
    values (c.id, r.person_id, r.kpi_id, r.name, r.unit,
            null,                      -- the target is the manager's to agree
            r.weight, r.cadence, p_actor, 'ISSUED',
            'The standard set for ' || r.chair_code || ', pre-loaded from the '
            || 'chair registry. The target is deliberately blank: it is agreed '
            || 'with the reporting manager, not assumed here.')
    returning id into v_last;
    v_made := v_made + 1;
  end loop;

  select count(distinct person_id) into v_people from perf_assignment where cycle_id = c.id;

  -- pass two: the same measure on my manager is the one mine climbs into.
  -- Matched by NAME and unit, not kpi_id: the registry is per chair, so
  -- "Cases closed" on two chairs is two rows with two ids and matching on
  -- the id links nothing. The unit must agree too, or a percentage climbs
  -- into a count.
  for r in
    select a.id,
           (select m.id from perf_assignment m
             where m.cycle_id = a.cycle_id and m.person_id = pe.manager_id
               and m.name = a.name and m.unit is not distinct from a.unit
               and m.part_of_id is null
             order by m.id limit 1) as into_id
      from perf_assignment a
      join person pe on pe.id = a.person_id
     where a.cycle_id = c.id and a.rolls_into_id is null and a.part_of_id is null
       and pe.manager_id is not null and pe.manager_id <> pe.id
  loop
    continue when r.into_id is null;
    update perf_assignment set rolls_into_id = r.into_id where id = r.id;
    v_linked := v_linked + 1;
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object(
           'person', q.full_name, 'chair', q.chair, 'why', q.why)
         order by q.chair, q.full_name), '[]'::jsonb)
    into v_noset
    from (
      select pe.full_name, coalesce(ch.code, '(no chair)') as chair,
             case when ch.id is null then 'they hold no chair'
                  else 'their chair has no measure set in the registry' end as why
        from person pe
        left join chair_holder h on h.person_id = pe.id and h.to_date is null
        left join chair ch on ch.id = h.chair_id
       where pe.employment_status = 'ACTIVE' and pe.superseded_by is null
         and coalesce(pe.employee_type,'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
         and not exists (select 1 from perf_assignment a
                          where a.cycle_id = c.id and a.person_id = pe.id)
         and exists (select 1 from chair_holder h3
                      where h3.person_id = pe.id and h3.to_date is null)) q;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'PERF_SEEDED_FROM_REGISTRY', 'perf_cycle', c.id::text,
          jsonb_build_object('period', c.period_start, 'made', v_made,
                             'linked', v_linked, 'people', v_people,
                             'alreadyThere', v_skipped));

  return jsonb_build_object(
    'ok', true, 'period', c.period_start,
    'made', v_made, 'linked', v_linked, 'people', v_people,
    'alreadyThere', v_skipped,
    'withoutAMeasureSet', jsonb_array_length(v_noset), 'noSet', v_noset,
    'note', v_made || ' measure(s) given to ' || v_people || ' people for '
            || c.period_start || ', with the targets blank. '
            || v_linked || ' of them climb into a manager''s.');
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_seed_targets(p_actor uuid, p_cycle uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role role_kind; r record;
  v_set int := 0; v_kept int := 0; v_daily int := 0; v_moved int := 0;
  v_target numeric; v_stated numeric; u text;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Seeding the company''s targets is an administrator''s.');
  end if;
  update perf_assignment set cadence = 'DAILY'::kpi_cadence
   where cycle_id = p_cycle and coalesce(cadence::text,'') <> 'DAILY';
  get diagnostics v_daily = row_count;
  for r in
    select a.id, a.unit, a.target_value, a.target_source,
           perf_accrual_kind(a.kpi_id, a.unit) as kind
      from perf_assignment a
     where a.cycle_id = p_cycle and a.part_of_id is null order by a.id
  loop
    if r.target_source = 'MANUAL' or r.target_value is not null then
      v_kept := v_kept + 1; continue;
    end if;
    u := lower(coalesce(r.unit, ''));
    v_stated := nullif(substring(u from 'target (?:below |above )?([0-9]+(?:\.[0-9]+)?)'), '')::numeric;
    if u like '%target zero%' then v_stated := 0; end if;
    if v_stated is not null then v_target := v_stated;
    elsif r.kind = 'LEVEL' then
      if perf_direction(r.unit) = 'CEILING' then v_target := 5; else v_target := 90; end if;
    else v_target := 100; end if;
    update perf_assignment set target_value = v_target, target_source = 'SEEDED' where id = r.id;
    v_set := v_set + 1;
  end loop;
  for r in
    select a.id from perf_assignment a
     where a.cycle_id = p_cycle and a.rolls_into_id is null and a.part_of_id is null
       and exists (select 1 from perf_assignment c where c.rolls_into_id = a.id)
  loop
    v_moved := v_moved + perf_cascade(r.id);
  end loop;
  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'PERF_TARGETS_SEEDED', 'perf_cycle', p_cycle::text,
          jsonb_build_object('set', v_set, 'kept', v_kept, 'madeDaily', v_daily, 'sharesMoved', v_moved));
  return jsonb_build_object('ok', true, 'set', v_set, 'kept', v_kept,
    'madeDaily', v_daily, 'sharesMoved', v_moved);
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_split_of(p_actor uuid, p_assignment uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a perf_assignment;
begin
  select * into a from perf_assignment where id = p_assignment;
  if a.id is null then return jsonb_build_object('error','no_such_assignment'); end if;
  if perf_rel(p_actor, a.person_id) is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That measure is not in your line.');
  end if;

  return jsonb_build_object(
    'assignmentId', a.id,
    'name', a.name,
    'unit', a.unit,
    'target', a.target_value,
    'kind', perf_accrual_kind(a.kpi_id, a.unit),
    'divides', perf_accrual_kind(a.kpi_id, a.unit) = 'SUM',
    'maySet', perf_may_set(p_actor, a.person_id),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'assignmentId', c.id, 'clientId', c.split_ref,
               'client', c.split_label, 'target', c.target_value,
               'pinned', c.target_source = 'MANUAL',
               'value', perf_value(c.id),
               'filings', (select count(*) from perf_entry e
                            where e.assignment_id = c.id))
             order by c.split_label)
        from perf_assignment c where c.part_of_id = a.id), '[]'::jsonb),
    'clients', coalesce((
      select jsonb_agg(jsonb_build_object('id', cl.id, 'name', cl.name,
                                          'code', cl.code) order by cl.name)
        from client cl where cl.status = 'ACTIVE'), '[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_split_set(p_actor uuid, p_assignment uuid, p_in jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a perf_assignment; v_kind text; v_split text;
  r jsonb; v_ref uuid; v_target numeric; v_label text;
  v_named uuid[] := '{}'; v_keep uuid[] := '{}';
  v_given numeric := 0; v_blank int := 0; v_left numeric;
  v_rows jsonb := '[]'::jsonb; v_del int := 0; v_stuck text;
  v_id uuid;
begin
  select * into a from perf_assignment where id = p_assignment;
  if a.id is null then return jsonb_build_object('error','no_such_assignment'); end if;

  if not perf_may_set(p_actor, a.person_id) then
    return jsonb_build_object('error','not_permitted',
      'reason','Splitting a target across clients is the same act as setting '
               'it, and belongs to the person they report to.');
  end if;

  -- One level only. A split of a split is a different feature and would
  -- make perf_value's recursion mean two things at once.
  if a.part_of_id is not null then
    return jsonb_build_object('error','already_a_part',
      'reason','That measure is itself one client''s share. Split the '
               'measure it belongs to, not the share.');
  end if;

  v_split := upper(coalesce(p_in->>'kind','CLIENT'));
  if v_split <> 'CLIENT' then
    return jsonb_build_object('error','unknown_split',
      'reason','Only a split by client is supported.');
  end if;

  v_kind := perf_accrual_kind(a.kpi_id, a.unit);

  -- --------------------------------------------------- read what was asked
  for r in select * from jsonb_array_elements(coalesce(p_in->'parts','[]'::jsonb)) loop
    v_ref := nullif(r->>'ref','')::uuid;
    if v_ref is null then
      return jsonb_build_object('error','missing_client',
        'reason','Every share has to name a client.');
    end if;
    if not exists (select 1 from client where id = v_ref) then
      return jsonb_build_object('error','no_such_client', 'clientId', v_ref);
    end if;
    if v_ref = any(v_named) then
      return jsonb_build_object('error','client_twice',
        'reason', (select name from client where id = v_ref) ||
                  ' appears twice. One share per client.');
    end if;
    v_named := v_named || v_ref;
    if (r->>'target') is not null and r->>'target' <> '' then
      v_given := v_given + (r->>'target')::numeric;
    else
      v_blank := v_blank + 1;
    end if;
  end loop;

  -- Naming nobody removes the split altogether, which is a legitimate act.
  if array_length(v_named,1) is null then
    select string_agg(c.split_label, ', ') into v_stuck
      from perf_assignment c
     where c.part_of_id = a.id
       and exists (select 1 from perf_entry e where e.assignment_id = c.id);
    if v_stuck is not null then
      return jsonb_build_object('error','has_filings',
        'reason','These shares already have numbers filed against them, so '
                 'removing the split would delete them: ' || v_stuck);
    end if;
    delete from perf_assignment where part_of_id = a.id;
    get diagnostics v_del = row_count;
    insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
    values (p_actor,'PERF_SPLIT_CLEARED','perf_assignment', a.id::text,
            jsonb_build_object('removed', v_del));
    return jsonb_build_object('ok', true, 'parts', 0, 'removed', v_del,
      'note','The split is gone. The measure is filed as one number again.');
  end if;

  -- ------------------------------------------------------- the arithmetic
  if v_kind = 'SUM' then
    if a.target_value is not null and v_given > a.target_value then
      return jsonb_build_object('error','over_the_target',
        'reason','The shares add to ' || v_given || ', which is more than the '
                 || a.target_value || ' being divided.');
    end if;
    v_left := case when a.target_value is null then null
                   else a.target_value - v_given end;
  end if;

  -- ------------------------------------------------------------ write them
  for r in select * from jsonb_array_elements(p_in->'parts') loop
    v_ref   := (r->>'ref')::uuid;
    v_label := (select name from client where id = v_ref);

    if v_kind = 'SUM' then
      v_target := case
        when (r->>'target') is not null and r->>'target' <> ''
          then (r->>'target')::numeric
        when v_left is null or v_blank = 0 then null
        else round(v_left / v_blank, 2) end;
    else
      -- A percentage is copied, never divided. perf_value weights a level
      -- by target_value, so equal targets make it a plain mean.
      v_target := a.target_value;
    end if;

    select c.id into v_id from perf_assignment c
      where c.part_of_id = a.id and c.split_ref = v_ref;

    if v_id is null then
      insert into perf_assignment
        (cycle_id, person_id, kpi_id, name, unit, target_value, weight_pct,
         cadence, cadence_day, part_of_id, split_kind, split_ref, split_label,
         set_by, state, target_source)
      values (a.cycle_id, a.person_id, a.kpi_id, a.name, a.unit, v_target,
              a.weight_pct, a.cadence, a.cadence_day, a.id, 'CLIENT', v_ref,
              v_label, p_actor, a.state,
              case when (r->>'target') is not null and r->>'target' <> ''
                   then 'MANUAL' else 'SHARED' end)
      returning id into v_id;
    else
      update perf_assignment
         set target_value = v_target,
             split_label  = v_label,
             target_source = case when (r->>'target') is not null and r->>'target' <> ''
                                  then 'MANUAL' else 'SHARED' end
       where id = v_id;
    end if;

    v_keep := v_keep || v_id;
    v_rows := v_rows || jsonb_build_object(
      'assignmentId', v_id, 'clientId', v_ref, 'client', v_label,
      'target', v_target);
  end loop;

  -- ------------------------------------- anything dropped from the list
  select string_agg(c.split_label, ', ') into v_stuck
    from perf_assignment c
   where c.part_of_id = a.id and not (c.id = any(v_keep))
     and exists (select 1 from perf_entry e where e.assignment_id = c.id);
  if v_stuck is not null then
    return jsonb_build_object('error','has_filings',
      'reason','These shares already have numbers filed against them and were '
               'left out of the new split, so nothing has been changed: ' || v_stuck);
  end if;
  delete from perf_assignment c where c.part_of_id = a.id and not (c.id = any(v_keep));
  get diagnostics v_del = row_count;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor,'PERF_SPLIT_SET','perf_assignment', a.id::text,
          jsonb_build_object('parts', jsonb_array_length(v_rows),
                             'removed', v_del, 'kind', v_kind));

  return jsonb_build_object('ok', true,
    'kind', v_kind,
    'divides', v_kind = 'SUM',
    'parts', v_rows,
    'removed', v_del,
    'note', case when v_kind = 'SUM'
      then 'A count, so the target divides: the shares add to what was being '
           'split, and a share left blank takes an even part of what is left.'
      else 'A percentage, so every client carries the same number. It is not '
           'divided -- 95% across three clients is 95% each.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_target_set(p_actor uuid, p_assignment uuid, p_value numeric, p_manual boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a perf_assignment; v_was numeric; v_moved int;
begin
  select * into a from perf_assignment where id = p_assignment;
  if a.id is null then return jsonb_build_object('error','no_such_assignment'); end if;

  if not perf_may_set(p_actor, a.person_id) then
    return jsonb_build_object('error','not_permitted',
      'reason','A target is set by the person''s own manager. You see the progress of everyone below them; you set only your own team''s.');
  end if;

  v_was := a.target_value;
  update perf_assignment
     set target_value = p_value,
         target_source = case when p_manual then 'MANUAL' else 'SHARED' end
   where id = p_assignment;

  v_moved := perf_cascade(p_assignment);

  -- A hand-typed share changes what is left for the others, so the parent
  -- divides again around it. Not upwards: a manager's own target is not
  -- moved by what they gave somebody.
  if p_manual and a.rolls_into_id is not null then
    v_moved := v_moved + perf_cascade(a.rolls_into_id);
  end if;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, 'PERF_TARGET_SET', 'perf_assignment', p_assignment::text,
          jsonb_build_object('target', v_was, 'source', a.target_source),
          jsonb_build_object('target', p_value,
                             'source', case when p_manual then 'MANUAL' else 'SHARED' end,
                             'sharesMoved', v_moved));

  return jsonb_build_object('ok', true, 'target', p_value, 'sharesMoved', v_moved,
    'note', case when v_moved = 0
      then 'Set. Nobody reports into this measure, so there was nothing to divide.'
      else 'Set, and divided across ' || v_moved || ' measure(s) below it. Anything typed by hand was left alone.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_tree(p_person uuid, p_cycle uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c perf_cycle; p person%rowtype;
begin
  select * into c from perf_cycle where id = p_cycle;
  select * into p from person where id = p_person;
  if c.id is null or p.id is null then
    return jsonb_build_object('error','no_such_cycle_or_person');
  end if;
  return jsonb_build_object(
    'cycle', jsonb_build_object('cycleId', c.id, 'period', c.period_start,
      'kind', c.period_kind, 'assignBy', c.assign_closes,
      'entriesClose', c.entry_closes, 'state', c.state,
      'assignOpen', current_date <= c.assign_closes,
      'entryOpen', current_date <= c.entry_closes),
    'person', jsonb_build_object('personId', p.id, 'name', p.full_name,
      'employeeNo', p.employee_no, 'department', p.department),
    'measures', coalesce((
      select jsonb_agg(perf_node(a.id) order by a.name)
        from perf_assignment a
       where a.person_id = p_person and a.cycle_id = p_cycle and a.state <> 'WITHDRAWN'
         and a.part_of_id is null), '[]'::jsonb),
    'says', case
      when not exists (select 1 from perf_assignment a
                        where a.person_id = p_person and a.cycle_id = p_cycle and a.state <> 'WITHDRAWN')
      then 'Nothing has been set for this period yet. KPIs are set by the reporting manager, by HR, or by an administrator, and the window for '
           || c.period_start || ' ' || case when current_date <= c.assign_closes
              then 'is open until ' || c.assign_closes else 'closed on ' || c.assign_closes end || '.'
      else null end);
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_tree_for(p_actor uuid, p_person uuid, p_cycle uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_rel text; v_out jsonb;
begin
  v_rel := perf_rel(p_actor, p_person);
  if v_rel is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That person is not in your line. You see your own team, and the progress of everyone below them.');
  end if;
  v_out := perf_tree(p_person, p_cycle);
  if jsonb_typeof(v_out) = 'object' then
    v_out := v_out || jsonb_build_object('rel', v_rel, 'maySet', v_rel in ('self','manage','admin'));
  end if;
  return v_out;
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_unit_plain(p_unit text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when p_unit is null then null
    when position('·' in p_unit) = 0 then btrim(p_unit)
    else btrim(left(p_unit, length(p_unit) - position('·' in reverse(p_unit))))
  end;
$function$
;

CREATE OR REPLACE FUNCTION public.perf_value(p_assignment uuid, p_depth integer DEFAULT 0)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
AS $function$
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
    if kind = 'SUM' then
      select sum(e.value) into v from perf_entry e where e.assignment_id = a.id;
    else
      select e.value into v from perf_entry e
       where e.assignment_id = a.id order by e.as_of desc, e.filed_at desc limit 1;
    end if;
  end if;

  if exists (select 1 from perf_assignment c where c.rolls_into_id = a.id) then
    if kind = 'SUM' then
      select coalesce(v, 0) + coalesce(sum(perf_value(c.id, p_depth + 1)), 0) into v
        from perf_assignment c where c.rolls_into_id = a.id;
    else
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
end $function$
;

CREATE OR REPLACE FUNCTION public.person_add(p_actor uuid, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  chk jsonb; v jsonb; v_id uuid; v_seat uuid; v_role text; v_place text;
  v_actor person; v_chair chair; v_held text; v_note text := '';
  v_app text := upper(btrim(coalesce(nullif(p->>'appRole',''), 'VIEWER')));
begin
  select * into v_actor from person where id = p_actor;
  if v_actor.id is null then return jsonb_build_object('error','no_actor'); end if;
  if v_actor.app_role <> 'ADMIN' and coalesce(v_actor.department,'') <> 'Human Resources' then
    return jsonb_build_object('error','not_permitted',
      'reason','Creating a person is HR''s, or an administrator''s. It makes an account.');
  end if;

  if v_app not in ('VIEWER','MANAGER','LOCATION_HEAD','ADMIN') then
    return jsonb_build_object('error','bad_role',
      'reason','A role is viewer, manager, location head or administrator.');
  end if;
  if v_app = 'ADMIN' and v_actor.app_role <> 'ADMIN' then
    return jsonb_build_object('error','not_permitted',
      'reason','Only an administrator can create an administrator. Create them as a viewer '
              'and ask an administrator to raise it, so the raising is somebody''s decision '
              'and is in the audit trail as one.');
  end if;

  chk := person_check(p);
  if not (chk->>'ok')::boolean then
    return jsonb_build_object('error','invalid', 'errors', chk->'errors',
      'warnings', chk->'warnings',
      'reason','The form has ' || jsonb_array_length(chk->'errors') || ' problem(s).');
  end if;
  v := chk->'value';

  insert into person (full_name, work_email, personal_email, employee_no, mobile,
                      employee_type, department, designation_id, manager_id,
                      joined_on, employment_status, app_role, source_ref)
  values (v->>'fullName', v->>'workEmail', v->>'personalEmail', v->>'employeeNo',
          person_mobile(v->>'mobile'), v->>'employeeType', v->>'department',
          nullif(v->>'designationId','')::uuid, nullif(v->>'managerId','')::uuid,
          nullif(v->>'joinedOn','')::date, 'ACTIVE', v_app::role_kind, 'person_add')
  returning id into v_id;

  select * into v_chair from chair where id = (v->>'chairId')::uuid;

  if nullif(v->>'placeId','') is not null then
    select n.name into v_place from op_node n where n.id = (v->>'placeId')::uuid;
    select s.id into v_seat from chair_seating s
     where s.chair_id = v_chair.id and lower(btrim(s.scope_label)) = lower(btrim(v_place));
  end if;

  insert into chair_holder (chair_id, person_id, is_primary, from_date, seating_id)
  values (v_chair.id, v_id, true,
          coalesce(nullif(v->>'joinedOn','')::date, current_date), v_seat);

  if v_place is not null and v_chair.code in ('BRANCH_MANAGER','LOCATION_PARTNER') then
    v_role := case when v_chair.code = 'BRANCH_MANAGER' then 'BRANCH_MANAGER' else 'LOCATION_HEAD' end;
    select string_agg(q.full_name, ', ') into v_held
      from coverage_rule cr join person q on q.id = cr.person_id
     where cr.op_node_id = (v->>'placeId')::uuid and cr.role = v_role
       and cr.effective_to is null;
    if v_held is null then
      insert into coverage_rule (person_id, role, scope_type, op_node_id, effective_from)
      values (v_id, v_role, 'LOCATION', (v->>'placeId')::uuid,
              coalesce(nullif(v->>'joinedOn','')::date, current_date));
      v_note := ' They now cover ' || v_place || '.';
    else
      v_note := ' ' || v_place || ' is already covered by ' || v_held ||
                ', so no coverage rule was made. Set it on the Places screen if it should change hands.';
    end if;
  end if;

  insert into person_event (person_id, kind, note, at)
  values (v_id, 'CREATED',
    'Added by ' || v_actor.full_name || ' into ' || v_chair.title ||
    coalesce(' at ' || v_place, ''), now());

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, 'PERSON_ADDED', 'person', v_id::text, null,
          jsonb_build_object('name', v->>'fullName', 'employeeNo', v->>'employeeNo',
                             'chair', v_chair.title, 'place', v_place, 'appRole', v_app));

  return jsonb_build_object('ok', true, 'personId', v_id,
    'email', v->>'workEmail',
    'warnings', chk->'warnings',
    'note', (v->>'fullName') || ' added as ' || (v->>'employeeNo') ||
            ', seated in ' || v_chair.title || '.' || v_note ||
            case when exists (select 1 from kpi_definition k
                               where k.chair_id = v_chair.id and k.active and k.position < 100)
                 then ' That chair is in the PLB scheme, so they will need a goal sheet this quarter.'
                 else '' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.person_centre(p_person uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when count(*) = 1 then min(city) end
  from (select distinct g.name as city
          from coverage_rule cr
          join branch b on b.id = cr.branch_id
          join geo_node g on g.id = b.geo_node_id
         where cr.person_id = p_person and g.level = 'CITY') q
$function$
;

CREATE OR REPLACE FUNCTION public.person_check(p jsonb, p_person uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  e jsonb := '[]'::jsonb; w jsonb := '[]'::jsonb;
  v_name text := btrim(coalesce(p->>'fullName',''));
  v_mail text := lower(btrim(coalesce(p->>'workEmail','')));
  v_pers text := lower(btrim(coalesce(p->>'personalEmail','')));
  v_no   text := btrim(coalesce(p->>'employeeNo',''));
  v_mob  text := coalesce(person_mobile(p->>'mobile'), '');
  v_type text := upper(btrim(coalesce(nullif(p->>'employeeType',''),'EMPLOYEE')));
  v_dept text := btrim(coalesce(p->>'department',''));
  v_join text := nullif(btrim(coalesce(p->>'joinedOn','')), '');
  v_chair uuid; v_mgr uuid; v_desig uuid; v_place uuid;
  v_d date; hop uuid; n int;
  add_e  constant text := '';
begin
  -- name
  if v_name = '' then
    e := e || jsonb_build_object('field','fullName','says','A person needs a name.');
  elsif length(v_name) < 3 then
    e := e || jsonb_build_object('field','fullName','says','That is too short to be a name.');
  elsif v_name ~ '^[0-9[:punct:][:space:]]+$' then
    e := e || jsonb_build_object('field','fullName','says','That is not a name.');
  end if;

  -- employee type
  if v_type not in ('EMPLOYEE','PARTNER','INTERN','CONTRACT','CLIENT_CONTACT') then
    e := e || jsonb_build_object('field','employeeType',
      'says','Employee, partner, intern, contract or client contact.');
  end if;

  -- work e-mail
  if v_mail = '' then
    if v_type in ('EMPLOYEE','PARTNER','INTERN','CONTRACT') then
      e := e || jsonb_build_object('field','workEmail',
        'says','A work address is how they sign in and how the tool reaches them.');
    end if;
  elsif v_mail !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-zA-Z]{2,}$' then
    e := e || jsonb_build_object('field','workEmail','says','That is not an e-mail address.');
  else
    if exists (select 1 from person q where q.superseded_by is null
                 and (p_person is null or q.id <> p_person)
                 and lower(btrim(q.work_email)) = v_mail) then
      e := e || jsonb_build_object('field','workEmail',
        'says','Somebody already has that address: ' ||
          (select full_name from person q where q.superseded_by is null
             and lower(btrim(q.work_email)) = v_mail limit 1) || '.');
    end if;
    if v_type = 'EMPLOYEE' and v_mail not like '%@cruxindia.co.in' then
      w := w || jsonb_build_object('field','workEmail',
        'says','Not a cruxindia.co.in address. Allowed, but worth a second look for an employee.');
    end if;
  end if;

  if v_pers <> '' and v_pers !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-zA-Z]{2,}$' then
    e := e || jsonb_build_object('field','personalEmail','says','That is not an e-mail address.');
  end if;

  -- employee number: the one that decides whether their performance is ever seen
  if v_no = '' then
    if v_type = 'EMPLOYEE' then
      e := e || jsonb_build_object('field','employeeNo',
        'says','An employee number is required. Every performance upload joins people by it, '
              'so a person without one has their rows dropped and nothing says so. '
              'The next free one is ' || person_next_employee_no() || '.');
    end if;
  elsif v_no !~ '^[A-Za-z0-9][A-Za-z0-9/_-]{0,19}$' then
    e := e || jsonb_build_object('field','employeeNo',
      'says','Letters, digits, dash, slash or underscore, up to twenty, starting with a letter or digit.');
  elsif exists (select 1 from person q where q.superseded_by is null
                  and (p_person is null or q.id <> p_person)
                  and lower(btrim(q.employee_no)) = lower(v_no)) then
    e := e || jsonb_build_object('field','employeeNo',
      'says','That number belongs to ' ||
        (select full_name from person q where q.superseded_by is null
           and lower(btrim(q.employee_no)) = lower(v_no) limit 1) ||
        '. The next free one is ' || person_next_employee_no() || '.');
  end if;

  -- mobile
  if v_mob = '' then
    if v_type = 'EMPLOYEE' then
      e := e || jsonb_build_object('field','mobile',
        'says','A mobile number is required -- it is the second way in when e-mail fails.');
    end if;
  elsif v_mob !~ '^[6-9][0-9]{9}$' then
    e := e || jsonb_build_object('field','mobile',
      'says','Ten digits starting 6, 7, 8 or 9. Country code and spaces are stripped for you.');
  elsif exists (select 1 from person q where q.superseded_by is null
                  and (p_person is null or q.id <> p_person)
                  and person_mobile(q.mobile) = v_mob) then
    w := w || jsonb_build_object('field','mobile',
      'says','That number is already against ' ||
        (select full_name from person q where q.superseded_by is null
           and person_mobile(q.mobile) = v_mob limit 1) ||
        '. Shared handsets happen, so this is a warning, not a refusal.');
  end if;

  -- chair
  if coalesce(p->>'chairId','') = '' then
    e := e || jsonb_build_object('field','chairId',
      'says','A chair decides what they are measured on and who they report to.');
  else
    begin
      v_chair := (p->>'chairId')::uuid;
    exception when others then
      v_chair := null;
    end;
    if v_chair is null or not exists (select 1 from chair where id = v_chair) then
      e := e || jsonb_build_object('field','chairId','says','No such chair.');
    end if;
  end if;

  -- manager
  if coalesce(p->>'managerId','') <> '' then
    begin
      v_mgr := (p->>'managerId')::uuid;
    exception when others then
      v_mgr := null;
    end;
    if v_mgr is null then
      e := e || jsonb_build_object('field','managerId','says','No such manager.');
    elsif v_mgr = p_person then
      e := e || jsonb_build_object('field','managerId','says','Nobody reports to themselves.');
    elsif not exists (select 1 from person q where q.id = v_mgr
                        and q.superseded_by is null and q.employment_status = 'ACTIVE') then
      e := e || jsonb_build_object('field','managerId',
        'says','That manager is not an active person.');
    elsif p_person is not null then
      -- a cycle is only possible when editing; walk up and see
      hop := v_mgr; n := 0;
      while hop is not null and n < 50 loop
        if hop = p_person then
          e := e || jsonb_build_object('field','managerId',
            'says','That would make the reporting line a circle.');
          exit;
        end if;
        select manager_id into hop from person where id = hop;
        n := n + 1;
      end loop;
    end if;
  else
    w := w || jsonb_build_object('field','managerId',
      'says','No manager. Row-level security resolves a manager''s team through this field, '
            'so somebody seated without one sees nobody and nobody sees them.');
  end if;

  -- designation, place
  if coalesce(p->>'designationId','') <> '' then
    begin v_desig := (p->>'designationId')::uuid; exception when others then v_desig := null; end;
    if v_desig is null or not exists (select 1 from designation where id = v_desig) then
      e := e || jsonb_build_object('field','designationId','says','No such designation.');
    end if;
  end if;
  if coalesce(p->>'placeId','') <> '' then
    begin v_place := (p->>'placeId')::uuid; exception when others then v_place := null; end;
    if v_place is null or not exists (select 1 from op_node where id = v_place and active) then
      e := e || jsonb_build_object('field','placeId','says','No such place.');
    end if;
  end if;

  -- joining date
  if v_join is not null then
    begin
      v_d := v_join::date;
    exception when others then
      v_d := null;
      e := e || jsonb_build_object('field','joinedOn','says','That is not a date.');
    end;
    if v_d is not null then
      if v_d < date '1990-01-01' then
        e := e || jsonb_build_object('field','joinedOn','says','Before 1990 is almost certainly a typo.');
      elsif v_d > current_date + 90 then
        e := e || jsonb_build_object('field','joinedOn',
          'says','More than ninety days ahead. If it really is that far off, add them nearer the time.');
      elsif v_d > current_date then
        w := w || jsonb_build_object('field','joinedOn',
          'says','A future joining date. They will be ACTIVE from today, which is usually what is wanted.');
      end if;
    end if;
  elsif v_type = 'EMPLOYEE' then
    w := w || jsonb_build_object('field','joinedOn',
      'says','No joining date. Service length and several reports read it.');
  end if;

  -- department
  if v_dept <> '' and not exists (
       select 1 from person q where q.superseded_by is null
         and lower(btrim(q.department)) = lower(v_dept)) then
    w := w || jsonb_build_object('field','department',
      'says','A department nobody else is in. Allowed, but check the spelling -- '
            'the PLB permission model reads this field by name.');
  end if;

  return jsonb_build_object(
    'ok', jsonb_array_length(e) = 0,
    'errors', e,
    'warnings', w,
    'value', jsonb_build_object(
      'fullName', v_name, 'workEmail', nullif(v_mail,''),
      'personalEmail', nullif(v_pers,''), 'employeeNo', nullif(v_no,''),
      'mobile', nullif(v_mob,''), 'employeeType', v_type,
      'department', nullif(v_dept,''), 'joinedOn', v_d,
      'chairId', v_chair, 'managerId', v_mgr,
      'designationId', v_desig, 'placeId', v_place),
    'nextEmployeeNo', person_next_employee_no());
end $function$
;

CREATE OR REPLACE FUNCTION public.person_conduct(p_actor uuid, p_person uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if perf_rel(p_actor, p_person) is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That person is not in your line.');
  end if;
  return jsonb_build_object(
    'personId', p_person,
    'mayAct', hr_may_discipline(p_actor, p_person),
    'warnings', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', w.id, 'level', w.level, 'subject', w.subject,
               'detail', w.detail, 'issuedAt', w.issued_at,
               'issuedBy', (select full_name from person x where x.id = w.issued_by),
               'acknowledgedAt', w.acknowledged_at)
             order by w.issued_at desc)
        from person_warning w where w.person_id = p_person), '[]'::jsonb),
    'plan', (
      select jsonb_build_object(
               'id', pl.id, 'state', pl.state,
               'startsOn', pl.starts_on, 'endsOn', pl.ends_on,
               'concern', pl.concern, 'expectation', pl.expectation,
               'support', pl.support, 'outcome', pl.outcome_note,
               'reviews', coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'id', rv.id, 'seq', rv.seq, 'dueOn', rv.due_on,
                          'heldAt', rv.held_at, 'judgement', rv.judgement,
                          'note', rv.note,
                          'overdue', rv.held_at is null and rv.due_on < current_date)
                        order by rv.seq)
                   from pip_review rv where rv.plan_id = pl.id), '[]'::jsonb))
        from pip_plan pl
       where pl.person_id = p_person
       order by case when pl.state in ('OPEN','EXTENDED') then 0 else 1 end,
                pl.opened_at desc
       limit 1));
end $function$
;

CREATE OR REPLACE FUNCTION public.person_duplicates()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with live as (
    select p.*, lower(regexp_replace(p.full_name, '[^a-zA-Z]', '', 'g')) as key
      from person p
     where p.superseded_by is null and p.employment_status = 'ACTIVE'
       and coalesce(p.employee_type,'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
       and length(regexp_replace(p.full_name, '[^a-zA-Z]', '', 'g')) >= 4),
  dup as (select key from live group by key having count(*) > 1),
  side as (
    select l.key, jsonb_build_object(
      'personId', l.id, 'name', l.full_name,
      'employeeNo', l.employee_no, 'email', l.work_email, 'mobile', l.mobile,
      'type', l.employee_type, 'role', l.app_role, 'department', l.department,
      'joinedOn', l.joined_on,
      'manager', (select m.full_name from person m where m.id = l.manager_id),
      'chairs', (select coalesce(jsonb_agg(jsonb_build_object(
            'holderId', h.id, 'chair', ch.title, 'primary', h.is_primary,
            'at', s.scope_label,
            'inScheme', exists (select 1 from kpi_definition k
                                 where k.chair_id = ch.id and k.active and k.position < 100))
            order by ch.title), '[]'::jsonb)
          from chair_holder h join chair ch on ch.id = h.chair_id
          left join chair_seating s on s.id = h.seating_id
         where h.person_id = l.id and h.to_date is null),
      'perfRows', (select count(*) from perf_month m where m.person_id = l.id),
      'places', (select count(*) from coverage_rule c
                  where c.person_id = l.id and c.effective_to is null),
      'reports', (select count(*) from person q
                   where q.manager_id = l.id and q.superseded_by is null),
      'sessions', (select count(*) from auth_session s2
                    where s2.person_id = l.id and s2.revoked_at is null),
      'weight', (select count(*) from perf_month m where m.person_id = l.id)
               + (select count(*) from coverage_rule c
                   where c.person_id = l.id and c.effective_to is null)
               + (select count(*) from person q
                   where q.manager_id = l.id and q.superseded_by is null)
      ) as who, l.full_name as nm
      from live l join dup d on d.key = l.key)
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', key, 'name', nm,
    'sides', sides,
    'says', 'Two live records with the same name. Neither is automatically the '
         || 'right one -- merging decides which chair, which employment type and '
         || 'which contact details survive, and the merged record is kept and '
         || 'readable afterwards.') order by nm), '[]'::jsonb)
  from (
    select key, min(nm) as nm, jsonb_agg(who order by (who->>'weight')::int desc) as sides
      from side group by key) g;
$function$
;

CREATE OR REPLACE FUNCTION public.person_is_staff(p_person uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from person p
     where p.id = p_person
       and p.superseded_by is null
       and coalesce(p.employee_type,'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT'))
$function$
;

CREATE OR REPLACE FUNCTION public.person_manager_is_not_a_service_account()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_name text;
begin
  if new.manager_id is null then return new; end if;
  select full_name into v_name from person
   where id = new.manager_id and employee_type = 'SERVICE_ACCOUNT';
  if v_name is not null then
    raise exception using errcode = '23514',
      message = format('%s is the account the tool is administered from, not somebody who works here, so nobody can report to it.', v_name),
      hint = 'Choose the person who actually manages them.';
  end if;
  return new;
end
$function$
;

CREATE OR REPLACE FUNCTION public.person_merge(p_actor uuid, p_loser uuid, p_winner uuid, p_choices jsonb DEFAULT '{}'::jsonb, p_confirm text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a person; l person; w person; plan jsonb; r record;
  q text; n bigint; moved jsonb := '[]'::jsonb; dropped jsonb := '[]'::jsonb;
  side text; keep uuid; closed int := 0; revoked int := 0;
  pick text[]; val text; sets text[] := '{}';
  fields constant text[][] := array[
    ['fullName','full_name'], ['workEmail','work_email'],
    ['personalEmail','personal_email'], ['employeeNo','employee_no'],
    ['mobile','mobile'], ['employeeType','employee_type'],
    ['appRole','app_role'], ['department','department'],
    ['designationId','designation_id'], ['managerId','manager_id'],
    ['joinedOn','joined_on']];
begin
  select * into a from person where id = p_actor;
  if a.id is null then return jsonb_build_object('error','no_actor'); end if;
  if a.app_role <> 'ADMIN' and coalesce(a.department,'') <> 'Human Resources' then
    return jsonb_build_object('error','not_permitted',
      'reason','Merging two people is HR''s, or an administrator''s.');
  end if;

  select * into l from person where id = p_loser;
  select * into w from person where id = p_winner;
  if l.id is null or w.id is null then
    return jsonb_build_object('error','no_such_person');
  end if;
  if coalesce(btrim(p_confirm),'') <> l.full_name then
    return jsonb_build_object('error','not_confirmed',
      'reason','This cannot be undone. To go ahead, type the name of the record being '
              || 'merged away exactly as it appears: ' || l.full_name);
  end if;

  plan := person_merge_plan(p_loser, p_winner);
  if not (plan->>'ok')::boolean then
    return jsonb_build_object('error','blocked', 'blockers', plan->'blockers',
      'reason', (plan->'blockers'->0->>'says'));
  end if;

  keep := nullif(p_choices->>'keepChairHolderId','')::uuid;
  if keep is not null and not exists (
      select 1 from chair_holder h
       where h.id = keep and h.to_date is null
         and h.person_id in (p_loser, p_winner)) then
    return jsonb_build_object('error','no_such_seat',
      'reason','That seat is not an open chair of either person.');
  end if;
  if keep is null and (
      select count(*) from chair_holder h
       where h.to_date is null and h.is_primary
         and h.person_id in (p_loser, p_winner)) > 1 then
    return jsonb_build_object('error','choose_a_seat',
      'reason','Both of them hold a primary chair and one person may hold only one. '
              || 'Say which seat survives; the other is closed with today''s date, not deleted.');
  end if;

  if w.manager_id = p_loser then
    update person set manager_id = case when l.manager_id = p_winner then null
                                        else l.manager_id end
     where id = p_winner;
    select * into w from person where id = p_winner;
  end if;

  -- -------------------------------------------------------- settle the seat
  -- while each row is still on its own owner, or the move below puts two
  -- primary open chairs on one person and the unique index refuses
  if keep is not null then
    update chair_holder
       set to_date = current_date
     where to_date is null and id <> keep and person_id in (p_loser, p_winner);
    get diagnostics closed = row_count;
    update chair_holder set is_primary = true where id = keep;
  end if;

  for r in
    select i.indrelid::regclass as rel,
           (select att.attname from pg_attribute att
             where att.attrelid = i.indrelid and att.attnum = any(i.indkey)
               and exists (select 1 from pg_constraint c
                           join unnest(c.conkey) k(attnum) on true
                            where c.contype='f' and c.confrelid='person'::regclass
                              and c.conrelid = i.indrelid and k.attnum = att.attnum)
             limit 1) as pcol,
           (select array_agg(att.attname order by att.attnum) from pg_attribute att
             where att.attrelid = i.indrelid and att.attnum = any(i.indkey)) as cols,
           pg_get_expr(i.indpred, i.indrelid) as pred
      from pg_index i
     where i.indisunique and i.indrelid <> 'person'::regclass
       and i.indrelid <> 'chair_holder'::regclass
       and exists (select 1 from pg_constraint c
                   join unnest(c.conkey) k(attnum) on true
                   join pg_attribute a2 on a2.attrelid=c.conrelid and a2.attnum=k.attnum
                    where c.contype='f' and c.confrelid='person'::regclass
                      and c.conrelid = i.indrelid and a2.attnum = any(i.indkey))
  loop
    if r.pcol is null then continue; end if;
    side := format('(select t.ctid as _ct, t.* from %s t%s)', r.rel,
              case when r.pred is null then '' else ' where ' || r.pred end);
    q := format(
      'delete from %1$s where ctid in (select l._ct from %2$s l join %2$s w on %3$s '
      || 'where l.%4$I = $1 and w.%4$I = $2)',
      r.rel, side,
      coalesce((select string_agg(format('l.%1$I = w.%1$I', c), ' and ')
                  from unnest(r.cols) c where c <> r.pcol), 'true'),
      r.pcol);
    execute q using p_loser, p_winner;
    get diagnostics n = row_count;
    if n > 0 then
      dropped := dropped || jsonb_build_object('table', r.rel::text, 'rows', n,
        'says','the winner already had the same row');
    end if;
  end loop;

  for r in
    select c.conrelid::regclass as rel, att.attname as col
      from pg_constraint c
      join unnest(c.conkey) k(attnum) on true
      join pg_attribute att on att.attrelid = c.conrelid and att.attnum = k.attnum
     where c.contype = 'f' and c.confrelid = 'person'::regclass
       and not (c.conrelid = 'person'::regclass and att.attname = 'superseded_by')
       and not (c.conrelid = 'auth_session'::regclass and att.attname = 'person_id')
     order by 1, 2
  loop
    execute format('update %s set %I = $2 where %I = $1', r.rel, r.col, r.col)
      using p_loser, p_winner;
    get diagnostics n = row_count;
    if n > 0 then
      moved := moved || jsonb_build_object('table', r.rel::text, 'column', r.col, 'rows', n);
    end if;
  end loop;

  update auth_session set revoked_at = now(), revoked_by = p_actor
   where person_id = p_loser and revoked_at is null;
  get diagnostics revoked = row_count;

  update person
     set superseded_by = p_winner, employment_status = 'INACTIVE',
         left_on = coalesce(left_on, current_date), manager_id = null,
         updated_at = now()
   where id = p_loser;

  foreach pick slice 1 in array fields loop
    val := p_choices->>(pick[1]);
    if val = 'loser' then
      sets := sets || format('%I = $1.%I', pick[2], pick[2]);
    end if;
  end loop;
  if array_length(sets, 1) > 0 then
    execute format('update person set %s, updated_at = now() where id = $2',
                   array_to_string(sets, ', '))
      using l, p_winner;
  end if;


  insert into person_event (person_id, kind, note, at) values
    (p_loser, 'UPDATED', 'Merged into ' || w.full_name ||
      ' by ' || a.full_name || '. This record is superseded and keeps its own '
      || 'history; everything that pointed at it now points at the survivor.', now()),
    (p_winner, 'UPDATED', l.full_name || ' was merged into this record by ' ||
      a.full_name || '.', now());

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, 'PERSON_MERGED', 'person', p_winner::text,
          jsonb_build_object('loser', l.full_name, 'loserId', p_loser,
                             'loserEmployeeNo', l.employee_no),
          jsonb_build_object('winner', w.full_name, 'winnerId', p_winner,
                             'moved', moved, 'dropped', dropped,
                             'seatsClosed', closed, 'sessionsRevoked', revoked,
                             'choices', p_choices));

  select * into w from person where id = p_winner;
  return jsonb_build_object('ok', true,
    'winnerId', p_winner, 'moved', moved, 'dropped', dropped,
    'seatsClosed', closed, 'sessionsRevoked', revoked,
    'note', l.full_name || ' merged into ' || w.full_name ||
      case when w.employee_no is not null then ' (' || w.employee_no || ')' else '' end ||
      '. ' || coalesce((select sum((x->>'rows')::bigint)::text from jsonb_array_elements(moved) x), '0')
      || ' row(s) moved across ' || jsonb_array_length(moved) || ' table(s)' ||
      case when closed > 0 then ', ' || closed || ' other open seat(s) closed' else '' end ||
      case when revoked > 0 then ', ' || revoked || ' session(s) revoked' else '' end ||
      '. The merged record is kept, superseded, and can still be read.');
end $function$
;

CREATE OR REPLACE FUNCTION public.person_merge_plan(p_loser uuid, p_winner uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  l person; w person; r record; n bigint;
  moves jsonb := '[]'::jsonb; clashes jsonb := '[]'::jsonb; stop jsonb := '[]'::jsonb;
  q text; total bigint := 0;
  side text;
begin
  select * into l from person where id = p_loser;
  select * into w from person where id = p_winner;
  if l.id is null or w.id is null then
    return jsonb_build_object('ok', false, 'blockers',
      jsonb_build_array(jsonb_build_object('says','One of those people does not exist.')));
  end if;
  if l.id = w.id then
    return jsonb_build_object('ok', false, 'blockers',
      jsonb_build_array(jsonb_build_object('says','Those are the same person.')));
  end if;
  if l.superseded_by is not null then
    stop := stop || jsonb_build_object('says',
      l.full_name || ' has already been merged into somebody else.');
  end if;
  if w.superseded_by is not null then
    stop := stop || jsonb_build_object('says',
      w.full_name || ' has themselves been merged away. Merge into the survivor instead.');
  end if;
  if w.employment_status <> 'ACTIVE' then
    stop := stop || jsonb_build_object('says',
      w.full_name || ' is not active. The survivor of a merge should be the live record.');
  end if;

  for r in
    select c.conrelid::regclass as rel, a.attname as col
      from pg_constraint c
      join unnest(c.conkey) k(attnum) on true
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
     where c.contype = 'f' and c.confrelid = 'person'::regclass
       and not (c.conrelid = 'person'::regclass and a.attname = 'superseded_by')
     order by 1, 2
  loop
    q := format('select count(*) from %s where %I = $1', r.rel, r.col);
    execute q into n using p_loser;
    if n > 0 then
      total := total + n;
      moves := moves || jsonb_build_object(
        'table', r.rel::text, 'column', r.col, 'rows', n,
        'action', case when r.rel::text = 'auth_session' and r.col = 'person_id'
                       then 'revoked, not moved -- a session is a login'
                       when r.rel::text = 'chair_holder'
                       then 'moved, once the seat below is settled'
                       else 'moved' end);
    end if;
  end loop;

  for r in
    select i.indrelid::regclass as rel,
           (select a.attname from pg_attribute a
             where a.attrelid = i.indrelid and a.attnum = any(i.indkey)
               and exists (select 1 from pg_constraint c
                           join unnest(c.conkey) k(attnum) on true
                            where c.contype='f' and c.confrelid='person'::regclass
                              and c.conrelid = i.indrelid and k.attnum = a.attnum)
             limit 1) as pcol,
           (select array_agg(a.attname order by a.attnum) from pg_attribute a
             where a.attrelid = i.indrelid and a.attnum = any(i.indkey)) as cols,
           pg_get_expr(i.indpred, i.indrelid) as pred,
           i.indexrelid::regclass::text as idx
      from pg_index i
     where i.indisunique and i.indrelid <> 'person'::regclass
       -- the same exclusion person_merge() makes, for the same reason
       and i.indrelid <> 'chair_holder'::regclass
       and exists (select 1 from pg_constraint c
                   join unnest(c.conkey) k(attnum) on true
                   join pg_attribute a2 on a2.attrelid=c.conrelid and a2.attnum=k.attnum
                    where c.contype='f' and c.confrelid='person'::regclass
                      and c.conrelid = i.indrelid
                      and a2.attnum = any(i.indkey))
     order by 1
  loop
    if r.pcol is null then continue; end if;
    -- the predicate goes INSIDE each side, where its bare column names are
    -- unambiguous; nothing about it has to be understood or rewritten
    side := format('(select * from %s%s)', r.rel,
              case when r.pred is null then '' else ' where ' || r.pred end);
    q := format(
      'select count(*) from %1$s l join %1$s w on %2$s where l.%3$I = $1 and w.%3$I = $2',
      side,
      coalesce((select string_agg(format('l.%1$I = w.%1$I', c), ' and ')
                  from unnest(r.cols) c where c <> r.pcol), 'true'),
      r.pcol);
    execute q into n using p_loser, p_winner;
    if n > 0 then
      clashes := clashes || jsonb_build_object(
        'table', r.rel::text, 'uniqueOn', array_to_string(r.cols, ', '),
        'index', r.idx, 'rows', n,
        'says', n || ' row(s) would land on top of a row ' || w.full_name ||
                ' already has. The loser''s copy is dropped and the winner''s kept, '
                || 'because they are two records of one fact.');
    end if;
  end loop;

  return jsonb_build_object(
    'ok', jsonb_array_length(stop) = 0,
    'blockers', stop,
    'loser', person_merge_side(l),
    'winner', person_merge_side(w),
    'rowsToMove', total,
    'moves', moves,
    'collisions', clashes);
end $function$
;

CREATE OR REPLACE FUNCTION public.person_merge_side(p person)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'id', p.id, 'name', p.full_name,
    'employeeNo', p.employee_no, 'email', p.work_email,
    'personalEmail', p.personal_email, 'mobile', p.mobile,
    'type', p.employee_type, 'role', p.app_role, 'department', p.department,
    'joinedOn', p.joined_on, 'status', p.employment_status,
    'designation', (select d.title from designation d where d.id = p.designation_id),
    'manager', (select m.full_name from person m where m.id = p.manager_id),
    'chairs', (select coalesce(jsonb_agg(jsonb_build_object(
          'holderId', h.id, 'chair', ch.title, 'code', ch.code, 'at', s.scope_label,
          'from', h.from_date, 'primary', h.is_primary,
          'inScheme', exists (select 1 from kpi_definition k
                               where k.chair_id = ch.id and k.active and k.position < 100))
          order by ch.title), '[]'::jsonb)
        from chair_holder h join chair ch on ch.id = h.chair_id
        left join chair_seating s on s.id = h.seating_id
       where h.person_id = p.id and h.to_date is null));
$function$
;

CREATE OR REPLACE FUNCTION public.person_mobile(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p is null then null
    -- 12 digits beginning 91, or 11 beginning 0: a country or trunk prefix
    when regexp_replace(p, '[^0-9]', '', 'g') ~ '^91[6-9][0-9]{9}$'
      then substr(regexp_replace(p, '[^0-9]', '', 'g'), 3)
    when regexp_replace(p, '[^0-9]', '', 'g') ~ '^0[6-9][0-9]{9}$'
      then substr(regexp_replace(p, '[^0-9]', '', 'g'), 2)
    else nullif(regexp_replace(p, '[^0-9]', '', 'g'), '')
  end;
$function$
;

CREATE OR REPLACE FUNCTION public.person_next_employee_no()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_max int;
begin
  perform pg_advisory_xact_lock(hashtext('person_employee_no'));
  select coalesce(max((regexp_replace(employee_no, '[^0-9]', '', 'g'))::int), 0)
    into v_max
    from person
   where superseded_by is null and employee_no ~ '^EMP-?[0-9]+$';
  return 'EMP-' || lpad((v_max + 1)::text, 4, '0');
end $function$
;

CREATE OR REPLACE FUNCTION public.person_normalise_email()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_alias text;
begin
  if new.work_email is null or btrim(new.work_email) = '' then
    return new;
  end if;
  new.work_email := lower(btrim(new.work_email));
  select a.correct into v_alias
  from email_domain_alias a
  where lower(a.wrong) = split_part(new.work_email, '@', 2);
  if v_alias is not null then
    new.work_email := split_part(new.work_email, '@', 1) || '@' || lower(v_alias);
  end if;
  if new.personal_email is not null then
    new.personal_email := lower(btrim(new.personal_email));
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.person_options()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'nextEmployeeNo', person_next_employee_no(),
    'chairs', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'title', c.title, 'code', c.code,
        'inScheme', exists (select 1 from kpi_definition k
                             where k.chair_id = c.id and k.active and k.position < 100),
        'seatedNow', (select count(*) from chair_holder h
                       where h.chair_id = c.id and h.to_date is null))
        order by c.title) from chair c), '[]'::jsonb),
    'managers', coalesce((select jsonb_agg(jsonb_build_object(
        'id', q.id, 'name', q.full_name, 'employeeNo', q.employee_no,
        'chair', (select ch.title from chair_holder h join chair ch on ch.id = h.chair_id
                   where h.person_id = q.id and h.to_date is null
                   order by h.is_primary desc nulls last limit 1))
        order by q.full_name)
      from person q
     where q.superseded_by is null and q.employment_status = 'ACTIVE'
       and coalesce(q.employee_type,'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')), '[]'::jsonb),
    'designations', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'title', d.title)
        order by d.seniority, d.title) from designation d), '[]'::jsonb),
    'departments', coalesce((select jsonb_agg(distinct btrim(q.department))
      from person q where q.superseded_by is null and coalesce(btrim(q.department),'') <> ''), '[]'::jsonb),
    'places', coalesce((select jsonb_agg(jsonb_build_object(
        'id', n.id, 'name', n.name, 'zone', z.name) order by z.name, n.name)
      from op_node n join op_node z on z.id = n.parent_id
     where n.level = 'LOCATION' and n.active and z.active), '[]'::jsonb),
    'employeeTypes', jsonb_build_array('EMPLOYEE','PARTNER','INTERN','CONTRACT','CLIENT_CONTACT'));
$function$
;

CREATE OR REPLACE FUNCTION public.person_request_decide(p_actor uuid, p_request uuid, p_decision text, p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor person; r person_request; v_dec text := upper(btrim(coalesce(p_decision,'')));
  v_reason text := nullif(btrim(coalesce(p->>'reason','')),'');
  v_add jsonb; o jsonb;
begin
  select * into v_actor from person where id = p_actor;
  if v_actor.id is null then
    return jsonb_build_object('error','not_permitted','reason','Who is asking?');
  end if;
  if v_actor.app_role <> 'ADMIN'
     and coalesce(v_actor.department,'') <> 'Human Resources' then
    return jsonb_build_object('error','not_permitted',
      'reason','Deciding a joiner request is HR''s, or an administrator''s.');
  end if;

  select * into r from person_request where id = p_request;
  if r.id is null then return jsonb_build_object('error','no_such_request'); end if;
  if r.state not in ('DRAFT','AWAITING_HR','AWAITING_ADMIN') then
    return jsonb_build_object('error','already_decided',
      'reason','That request is already ' || lower(r.state::text) || '.');
  end if;

  if v_dec = 'REJECT' then
    -- The table's own constraint demands a reason. Asking for it here means
    -- the person reading the refusal gets a sentence, not a constraint name.
    if v_reason is null then
      return jsonb_build_object('error','missing_reason',
        'reason','Say why, so the manager who asked knows what to do next.');
    end if;
    update person_request
       set state = 'REJECTED', reject_reason = v_reason,
           hr_by = p_actor, hr_at = now()
     where id = p_request;
    insert into audit_entry (actor_id, action, entity_type, entity_ref,
                             old_value, new_value)
    values (p_actor, 'PERSON_REQUEST_REJECTED', 'person_request', p_request::text,
            jsonb_build_object('state', r.state),
            jsonb_build_object('state','REJECTED','reason', v_reason));
    return jsonb_build_object('ok', true, 'state','REJECTED',
      'note', r.full_name || ' was not taken on: ' || v_reason);
  end if;

  if v_dec <> 'APPROVE' then
    return jsonb_build_object('error','bad_decision',
      'reason','Approve or reject.');
  end if;

  -- The request carries what the MANAGER knew. HR supplies the rest -- the
  -- employee number, the joining date, the department. The request's own
  -- fields win over anything passed in, so approving cannot quietly become
  -- approving a different person than the one that was asked for.
  v_add := coalesce(p, '{}'::jsonb) || jsonb_build_object(
    'fullName', r.full_name,
    'workEmail', r.work_email,
    'chairId', r.chair_id,
    'managerId', r.manager_id,
    'employeeType', r.employee_type);

  -- Every check person_add makes runs again here, under HR's authority.
  -- This is a queue in front of person_add, not a way around it.
  o := person_add(p_actor, v_add);
  if coalesce(o->>'ok','') <> 'true' then
    return o;
  end if;

  update person_request
     set state = 'ACTIVE', person_id = (o->>'personId')::uuid,
         hr_by = p_actor, hr_at = now()
   where id = p_request;

  insert into audit_entry (actor_id, action, entity_type, entity_ref,
                           old_value, new_value)
  values (p_actor, 'PERSON_REQUEST_APPROVED', 'person_request', p_request::text,
          jsonb_build_object('state', r.state),
          jsonb_build_object('state','ACTIVE','personId', o->>'personId'));

  return o || jsonb_build_object('requestId', p_request, 'state','ACTIVE');
end $function$
;

CREATE OR REPLACE FUNCTION public.person_request_list(p_actor uuid, p_state text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_actor person; v_hr boolean;
begin
  select * into v_actor from person where id = p_actor;
  if v_actor.id is null then
    return jsonb_build_object('error','not_permitted','reason','Who is asking?');
  end if;
  v_hr := v_actor.app_role = 'ADMIN'
          or coalesce(v_actor.department,'') = 'Human Resources';

  return jsonb_build_object(
    'isHr', v_hr,
    'requests', coalesce((
      select jsonb_agg(jsonb_build_object(
               'requestId', r.id, 'name', r.full_name, 'email', r.work_email,
               'employeeType', r.employee_type,
               'state', r.state, 'requestedAt', r.requested_at,
               'requestedBy', (select q.full_name from person q where q.id = r.requested_by),
               'managerId', r.manager_id,
               'managerName', (select q.full_name from person q where q.id = r.manager_id),
               'chairId', r.chair_id,
               'chair', (select c.title from chair c where c.id = r.chair_id),
               'rejectReason', r.reject_reason,
               'personId', r.person_id,
               -- Decided here rather than by the screen, for the same
               -- reason as everywhere else: an offered button the server
               -- refuses is a lie told to the user.
               'mayDecide', v_hr and r.state = 'AWAITING_HR')
             order by r.requested_at desc)
      from person_request r
     where (p_state is null or r.state::text = upper(p_state))
       -- HR sees the queue. Everybody else sees what they asked for and
       -- what was asked for their own team, and nothing else at all.
       and (v_hr or r.requested_by = p_actor or org_may_add_under(p_actor, r.manager_id))
    ), '[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.person_request_open(p_actor uuid, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor person; v_mgr uuid; v_chair chair; v_id uuid;
  v_name text := btrim(coalesce(p->>'fullName',''));
  v_mail text := lower(btrim(coalesce(p->>'workEmail','')));
  v_type text := upper(btrim(coalesce(nullif(p->>'employeeType',''),'EMPLOYEE')));
begin
  select * into v_actor from person where id = p_actor;
  if v_actor.id is null then
    return jsonb_build_object('error','not_permitted','reason','Who is asking?');
  end if;

  v_mgr := nullif(p->>'managerId','')::uuid;
  if v_mgr is null then
    return jsonb_build_object('error','missing_manager',
      'reason','A joiner joins somebody''s team. Say whose.');
  end if;
  if not org_may_add_under(p_actor, v_mgr) then
    return jsonb_build_object('error','not_permitted',
      'reason','You can only ask for somebody to join a team you manage.');
  end if;

  if length(v_name) < 3 or v_name !~ '[A-Za-z]' then
    return jsonb_build_object('error','missing_name',
      'reason','A request needs the joiner''s name.');
  end if;
  if v_mail !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$' then
    return jsonb_build_object('error','bad_email',
      'reason','That is not an e-mail address.');
  end if;
  if v_type not in ('EMPLOYEE','PARTNER','INTERN','CONTRACT') then
    return jsonb_build_object('error','bad_type',
      'reason','Employee, partner, intern or contract.');
  end if;

  -- The two ways this is a duplicate, told apart, because "already exists"
  -- and "already asked for" need different answers from the person reading.
  if exists (select 1 from person q
              where lower(q.work_email) = v_mail
                 or lower(coalesce(q.personal_email,'')) = v_mail) then
    return jsonb_build_object('error','already_employed',
      'reason', v_mail || ' already belongs to somebody here. If they are '
                'moving team, move them instead of asking for a new account.');
  end if;
  if exists (select 1 from person_request r
              where lower(r.work_email) = v_mail
                and r.state in ('DRAFT','AWAITING_HR','AWAITING_ADMIN')) then
    return jsonb_build_object('error','already_asked',
      'reason','There is already an open request for that address.');
  end if;

  select * into v_chair from chair where id = nullif(p->>'chairId','')::uuid;
  if v_chair.id is null then
    return jsonb_build_object('error','no_such_chair',
      'reason','A joiner sits in a chair. Pick one.');
  end if;

  insert into person_request (full_name, work_email, chair_id, manager_id,
                              requested_by, state, employee_type)
  values (v_name, v_mail, v_chair.id, v_mgr, p_actor, 'AWAITING_HR', v_type)
  returning id into v_id;

  insert into audit_entry (actor_id, action, entity_type, entity_ref,
                           old_value, new_value)
  values (p_actor, 'PERSON_REQUESTED', 'person_request', v_id::text, null,
          jsonb_build_object('name', v_name, 'email', v_mail,
                             'chair', v_chair.title, 'managerId', v_mgr));

  return jsonb_build_object('ok', true, 'requestId', v_id,
    'note', v_name || ' is with HR. They make the account -- you will see '
            'them on your team the moment they do.');
end $function$
;

CREATE OR REPLACE FUNCTION public.person_warn(p_actor uuid, p_in jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_person uuid; v_id uuid; v_level text;
begin
  v_person := nullif(p_in->>'personId','')::uuid;
  if v_person is null then return jsonb_build_object('error','missing_person'); end if;
  if not hr_may_discipline(p_actor, v_person) then
    return jsonb_build_object('error','not_permitted',
      'reason','A warning is issued by the person they report to, or by HR.');
  end if;
  v_level := upper(coalesce(p_in->>'level','WRITTEN'));
  if v_level not in ('VERBAL','WRITTEN','FINAL') then
    return jsonb_build_object('error','unknown_level',
      'reason','A warning is verbal, written or final.');
  end if;
  if coalesce(trim(p_in->>'subject'),'') = '' then
    return jsonb_build_object('error','missing_subject',
      'reason','A warning has to say what it is about.');
  end if;

  insert into person_warning (person_id, issued_by, level, subject, detail,
                              about_kind, about_ref)
  values (v_person, p_actor, v_level, trim(p_in->>'subject'), p_in->>'detail',
          nullif(upper(coalesce(p_in->>'aboutKind','OTHER')),''),
          nullif(p_in->>'aboutRef','')::uuid)
  returning id into v_id;

  insert into person_event (person_id, kind, note, at)
  values (v_person, 'WARNING_ISSUED', v_level || ': ' || trim(p_in->>'subject'), now());
  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor,'WARNING_ISSUED','person', v_person::text,
          jsonb_build_object('warningId', v_id, 'level', v_level));

  return jsonb_build_object('ok', true, 'warningId', v_id, 'level', v_level,
    'note','Issued and on the record. A warning is not edited afterwards; '
           'if it was wrong, issue the correction as its own record.');
end $function$
;

CREATE OR REPLACE FUNCTION public.person_welcome_all(p_actor uuid, p_domain text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor person; r record; o jsonb;
  n_sent int := 0; n_skip int := 0; v_why jsonb := '[]'::jsonb;
begin
  select * into v_actor from person where id = p_actor;
  if v_actor.id is null
     or (v_actor.app_role <> 'ADMIN'
         and coalesce(v_actor.department,'') <> 'Human Resources') then
    return jsonb_build_object('error','not_permitted',
      'reason','Writing to everybody is HR''s or an administrator''s.');
  end if;

  if app_link() is null then
    return jsonb_build_object('error','no_app_url',
      'reason','Nobody has said where the tool is served from. Set app_url '
              'first, or a hundred people get a link to nowhere.');
  end if;

  for r in
    select p.id, p.full_name, p.work_email
      from person p
     where p.employment_status = 'ACTIVE' and p.superseded_by is null
       and coalesce(btrim(p.work_email),'') <> ''
       -- A chair is the filter that separates the people who work here from
       -- the client contacts sitting in the same table. Without it this
       -- writes to five hundred bank managers.
       and exists (select 1 from chair_holder h
                    where h.person_id = p.id and h.to_date is null)
       and (p_domain is null or lower(p.work_email) like '%' || lower(p_domain))
     order by p.full_name
  loop
    o := person_welcome_send(p_actor, r.id, null);
    if coalesce((o->>'queued')::boolean, false) then
      n_sent := n_sent + 1;
    else
      n_skip := n_skip + 1;
      v_why := v_why || jsonb_build_object('person', r.full_name,
                          'why', coalesce(o->>'reason', o->>'error'));
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'queued', n_sent, 'skipped', n_skip,
    'skippedWhy', v_why,
    'note', n_sent || ' welcome(s) queued. They leave on the next mail drain.');
end $function$
;

CREATE OR REPLACE FUNCTION public.person_welcome_body(p_person uuid, p_sign_in text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  p person; v_chair chair; v_mgr text; v_level text; v_note text;
  v_link text; v_screens text; v_measures text; v_cycle perf_cycle;
  b text;
begin
  select * into p from person where id = p_person;
  if p.id is null then return null; end if;

  v_link := app_link();
  if v_link is null then return null; end if;

  select c.* into v_chair from chair_holder h join chair c on c.id = h.chair_id
   where h.person_id = p_person and h.to_date is null
   order by h.is_primary desc limit 1;

  select m.full_name into v_mgr from person m where m.id = p.manager_id;

  v_level := access_level_of(p_person);
  select label || ' -- ' || note into v_note
    from access_level where level = v_level;

  select string_agg(initcap(replace(s, '-', ' ')), ', ' order by s)
    into v_screens
    from unnest(access_screens(p_person)) s;

  -- The newest cycle this person actually holds measures in, rather than the
  -- newest cycle there is. Those are not the same thing: a person seated
  -- mid-month, or two cycles opened for one month, would otherwise be told
  -- they have nothing to file when they do.
  select c.* into v_cycle from perf_cycle c
   where c.period_kind = 'MONTH'
     and exists (select 1 from perf_assignment a
                  where a.person_id = p_person and a.cycle_id = c.id
                    and a.part_of_id is null)
   order by c.period_start desc limit 1;

  -- What they are actually measured on, with the target and how often it is
  -- owed. This is the part that answers "what am I supposed to do": a list of
  -- screens tells somebody where to click, and this tells them what for.
  select string_agg(
           '  - ' || a.name
           -- FM drops the trailing zeros and leaves the point behind, so a
           -- whole number reads "target 300." with a full stop in the middle
           -- of the sentence. rtrim takes it off.
           || case when a.target_value is not null
                   then ', target '
                        || rtrim(trim(to_char(a.target_value, 'FM999999999.99')), '.')
                        || coalesce(' ' || perf_unit_plain(a.unit), '')
                   else '' end
           || case when upper(coalesce(a.cadence::text,'')) like 'DAIL%'
                        then ' -- every working day'
                   when upper(coalesce(a.cadence::text,'')) like 'WEEK%'
                        then ' -- weekly'
                   else ' -- monthly' end,
           E'\n' order by a.name)
    into v_measures
    from perf_assignment a
   where a.person_id = p_person and a.cycle_id = v_cycle.id
     and a.part_of_id is null;

  b := 'Hello ' || split_part(p.full_name, ' ', 1) || E',\n\n'
    || 'Crux is where your work is recorded and where your performance and '
    || 'bonus are worked out. Everything about how you are measured is on it, '
    || 'including the arithmetic, so nothing about your score should ever be '
    || 'a surprise.' || E'\n\n'

    || 'Open it here: ' || v_link || E'\n\n'

    || 'Signing in' || E'\n'
    || 'Your user name is your work address, ' || p.work_email || '.' || E'\n'
    || coalesce(p_sign_in,
         'Use the Google button and sign in with that address -- there is no '
         || 'separate password to remember.') || E'\n\n'

    || 'Your chair' || E'\n'
    || coalesce(v_chair.title, 'You are not yet seated in a chair, so no '
                || 'measures have reached you. HR will place you.')
    || coalesce(E'\nYou report to ' || v_mgr || '.', '')
    || E'\n\n'

    || case when coalesce(v_measures, '') <> '' then
         'What you file, and how often' || E'\n'
         || v_measures || E'\n\n'
         || 'File these on the Performance and appraisal screen. The number is '
         || 'for the day it belongs to -- filing it late does not make it a '
         || 'later day''s number, and the days you file are themselves one of '
         || 'the things measured.' || E'\n\n'
       else
         'No measures have been set for you yet. Your manager sets them at the '
         || 'start of the month, and until then there is nothing for you to '
         || 'file.' || E'\n\n'
       end

    || 'What you can open' || E'\n'
    || coalesce(v_note, 'Your own work.') || E'\n'
    || coalesce('Screens: ' || v_screens || '.', '') || E'\n\n'

    || case when v_level in ('branch','team','hr','admin','partner') then
         'Because you have people under you, you also set their targets, hold '
         || 'their monthly reviews and score them. Their numbers climb into '
         || 'yours, so their filing is your filing.' || E'\n\n'
       else '' end

    || 'If anything here is wrong -- the chair, the manager, the measures -- '
    || 'tell HR rather than working around it. All of it is what your bonus is '
    || 'calculated from.' || E'\n';

  return b;
end $function$
;

CREATE OR REPLACE FUNCTION public.person_welcome_on_create()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b text; v_key text;
begin
  if new.employment_status <> 'ACTIVE' or new.superseded_by is not null then
    return new;
  end if;
  if coalesce(btrim(new.work_email),'') = '' then return new; end if;

  b := person_welcome_body(new.id, null);
  if b is null then return new; end if;   -- no app_url, so nothing to send

  v_key := md5('WELCOME|' || lower(btrim(new.work_email)) || '|' || current_date);
  insert into outbox (idempotency_key, template_key, recipient, subject, body,
                      entity_type, entity_id, not_before, state)
  values (v_key, 'ACTIVATION', lower(btrim(new.work_email)),
          'Your Crux account, and what your chair is measured on',
          b, 'person', new.id, now(), 'QUEUED')
  on conflict (idempotency_key) do nothing;

  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.person_welcome_send(p_actor uuid, p_person uuid, p_sign_in text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_actor person; p person; b text; v_key text;
begin
  select * into v_actor from person where id = p_actor;
  if v_actor.id is null then
    return jsonb_build_object('error','not_permitted','reason','Who is asking?');
  end if;
  -- HR, an administrator, or the person's own manager. A welcome names a
  -- chair and a manager, so whoever sends it is asserting both.
  if v_actor.app_role <> 'ADMIN'
     and coalesce(v_actor.department,'') <> 'Human Resources'
     and not org_may_add_under(p_actor, p_person) then
    return jsonb_build_object('error','not_permitted',
      'reason','Welcoming somebody is HR''s, an administrator''s, or their '
              'own manager''s.');
  end if;

  select * into p from person where id = p_person;
  if p.id is null then return jsonb_build_object('error','no_such_person'); end if;
  if coalesce(btrim(p.work_email),'') = '' then
    return jsonb_build_object('error','no_address',
      'reason', p.full_name || ' has no work address to write to.');
  end if;
  if p.employment_status <> 'ACTIVE' or p.superseded_by is not null then
    return jsonb_build_object('error','not_active',
      'reason','That person is not active.');
  end if;

  b := person_welcome_body(p_person, p_sign_in);
  if b is null then
    return jsonb_build_object('error','no_app_url',
      'reason','Nobody has said where the tool is served from, so this '
              'message would carry a link to nowhere. Set app_url in '
              'Configuration and send again.');
  end if;

  -- Keyed on the person and the day, so re-running a blast is harmless and a
  -- manager clicking twice does not send twice.
  v_key := md5('WELCOME|' || lower(btrim(p.work_email)) || '|' || current_date);

  insert into outbox (idempotency_key, template_key, recipient, subject, body,
                      entity_type, entity_id, not_before, state)
  values (v_key, 'ACTIVATION', lower(btrim(p.work_email)),
          'Your Crux account, and what your chair is measured on',
          b, 'person', p_person, now(), 'QUEUED')
  on conflict (idempotency_key) do nothing;

  if not found then
    return jsonb_build_object('ok', true, 'queued', false,
      'reason','Already sent to ' || p.work_email || ' today.');
  end if;

  insert into person_event (person_id, kind, note, at)
  values (p_person, 'WELCOMED',
          'Welcome and instructions sent by ' || v_actor.full_name, now());

  return jsonb_build_object('ok', true, 'queued', true,
    'to', p.work_email,
    'withPassword', p_sign_in is not null,
    'note', 'Queued for ' || p.full_name || '.');
end $function$
;

CREATE OR REPLACE FUNCTION public.person_without_number()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(x order by x->>'sort', x->>'person'), '[]'::jsonb) from (
    select jsonb_build_object(
      'personId', p.id, 'person', p.full_name,
      'email', p.work_email, 'type', p.employee_type,
      'chair', (select string_agg(ch.title, ' / ' order by ch.title)
                  from chair_holder h join chair ch on ch.id = h.chair_id
                 where h.person_id = p.id and h.to_date is null),
      'perfRows', (select count(*) from perf_month x where x.person_id = p.id),
      'places', (select count(*) from coverage_rule c
                  where c.person_id = p.id and c.effective_to is null),
      'twin', tw.full_name, 'twinNumber', tw.employee_no,
      'sort', case when tw.id is not null then '1' when z.acct then '3' else '2' end,
      'needs', case
        when tw.id is not null then 'a merge, not a number'
        when z.acct then 'nothing'
        else 'a number' end,
      'why', case
        when tw.id is not null then
          'The same name already holds ' || tw.employee_no ||
          '. Minting a second number would give one person two identities and split '
          || 'their performance between them. Merging decides which chair and which '
          || 'employment type is the real one, which is a decision, not a default.'
        when z.acct then
          'A login rather than a payroll record: ' ||
          (select count(*) from audit_entry a where a.actor_id = p.id) ||
          ' audit entries and ' ||
          (select count(*) from upload_batch b where b.uploaded_by = p.id) ||
          ' uploads under it. An employee number would be a fiction.'
        else
          'The Past performance, KPI targets and Assignments uploads key on employee '
          || 'number with no name fallback, so this person cannot be carried in those '
          || 'files at all.' end
    ) as x
    from person p
    left join lateral (
      select q.id, q.full_name, q.employee_no from person q
       where q.superseded_by is null and q.id <> p.id and q.employee_no is not null
         and lower(regexp_replace(q.full_name,'[^a-zA-Z]','','g'))
           = lower(regexp_replace(p.full_name,'[^a-zA-Z]','','g'))
       limit 1) tw on true
    cross join lateral (select exists (
      select 1 from audit_entry a where a.actor_id = p.id) as acct) z
   where p.superseded_by is null and p.employment_status = 'ACTIVE'
     and p.employee_no is null
     and coalesce(p.employee_type,'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
  ) t;
$function$
;

CREATE OR REPLACE FUNCTION public.pip_close(p_actor uuid, p_plan uuid, p_state text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_plan pip_plan; v_s text; v_open int;
begin
  select * into v_plan from pip_plan where id = p_plan;
  if v_plan.id is null then return jsonb_build_object('error','no_such_plan'); end if;
  if not hr_may_discipline(p_actor, v_plan.person_id) then
    return jsonb_build_object('error','not_permitted',
      'reason','That plan is not yours to close.');
  end if;
  v_s := upper(coalesce(p_state,''));
  if v_s not in ('MET','NOT_MET','WITHDRAWN','EXTENDED') then
    return jsonb_build_object('error','unknown_outcome',
      'reason','A plan is met, not met, withdrawn, or extended.');
  end if;
  if v_s in ('MET','NOT_MET') and coalesce(trim(p_note),'') = '' then
    return jsonb_build_object('error','missing_note',
      'reason','Say why. "Not met" with no reason is not a decision '
               'anybody can stand behind later.');
  end if;

  select count(*) into v_open from pip_review
   where plan_id = p_plan and held_at is null;

  update pip_plan
     set state = v_s, outcome_note = p_note,
         closed_at = case when v_s = 'EXTENDED' then null else now() end,
         closed_by = case when v_s = 'EXTENDED' then null else p_actor end
   where id = p_plan;

  insert into person_event (person_id, kind, note, at)
  values (v_plan.person_id, 'PIP_' || v_s, coalesce(p_note,''), now());
  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor,'PIP_CLOSED','pip_plan', p_plan::text,
          jsonb_build_object('state', v_s, 'reviewsUnheld', v_open));

  return jsonb_build_object('ok', true, 'state', v_s, 'reviewsUnheld', v_open,
    'note', case when v_open > 0
      then 'Closed with ' || v_open || ' review(s) never held. That is on the '
           'record too.'
      else 'Closed, every review held.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.pip_open(p_actor uuid, p_in jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_person uuid; v_id uuid; v_start date; v_end date;
  v_every int; v_n int := 0; d date; i int := 0;
begin
  v_person := nullif(p_in->>'personId','')::uuid;
  if v_person is null then return jsonb_build_object('error','missing_person'); end if;
  if not hr_may_discipline(p_actor, v_person) then
    return jsonb_build_object('error','not_permitted',
      'reason','A PIP is opened by the person they report to, or by HR.');
  end if;
  if coalesce(trim(p_in->>'concern'),'') = ''
     or coalesce(trim(p_in->>'expectation'),'') = '' then
    return jsonb_build_object('error','missing_detail',
      'reason','A PIP has to say what the concern is and what improvement '
               'would look like. A plan without both is not a plan.');
  end if;

  v_start := coalesce(nullif(p_in->>'startsOn','')::date, current_date);
  v_end   := coalesce(nullif(p_in->>'endsOn','')::date, v_start + 60);
  if v_end <= v_start then
    return jsonb_build_object('error','bad_dates',
      'reason','A PIP has to end after it starts.');
  end if;

  if exists (select 1 from pip_plan
              where person_id = v_person and state in ('OPEN','EXTENDED')) then
    return jsonb_build_object('error','already_on_one',
      'reason','That person is already on a plan. Close it before opening '
               'another, or extend the one they are on.');
  end if;

  insert into pip_plan (person_id, opened_by, starts_on, ends_on,
                        concern, expectation, support)
  values (v_person, p_actor, v_start, v_end,
          trim(p_in->>'concern'), trim(p_in->>'expectation'), p_in->>'support')
  returning id into v_id;

  -- The reviews are written now, not remembered later.
  v_every := greatest(7, coalesce(nullif(p_in->>'reviewEveryDays','')::int, 14));
  d := v_start + v_every;
  while d < v_end loop
    i := i + 1;
    insert into pip_review (plan_id, due_on, seq) values (v_id, d, i);
    v_n := v_n + 1;
    d := d + v_every;
  end loop;
  i := i + 1;
  insert into pip_review (plan_id, due_on, seq) values (v_id, v_end, i);
  v_n := v_n + 1;

  insert into person_event (person_id, kind, note, at)
  values (v_person, 'PIP_OPENED',
          'PIP ' || v_start || ' to ' || v_end || ', ' || v_n || ' reviews', now());
  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor,'PIP_OPENED','person', v_person::text,
          jsonb_build_object('planId', v_id, 'reviews', v_n,
                             'startsOn', v_start, 'endsOn', v_end));

  return jsonb_build_object('ok', true, 'planId', v_id, 'reviews', v_n,
    'startsOn', v_start, 'endsOn', v_end,
    'note', v_n || ' review(s) are already booked, the last on the day the '
            'plan ends. None of them is a reminder -- each is a row that '
            'stays unanswered until somebody holds it.');
end $function$
;

CREATE OR REPLACE FUNCTION public.pip_review_hold(p_actor uuid, p_review uuid, p_judgement text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_plan pip_plan; v_j text;
begin
  select pl.* into v_plan from pip_review r join pip_plan pl on pl.id = r.plan_id
   where r.id = p_review;
  if v_plan.id is null then return jsonb_build_object('error','no_such_review'); end if;
  if not hr_may_discipline(p_actor, v_plan.person_id) then
    return jsonb_build_object('error','not_permitted',
      'reason','That plan is not yours to review.');
  end if;
  v_j := upper(coalesce(p_judgement,''));
  if v_j not in ('ON_TRACK','AT_RISK','OFF_TRACK') then
    return jsonb_build_object('error','missing_judgement',
      'reason','A review says on track, at risk, or off track.');
  end if;

  update pip_review
     set held_at = now(), held_by = p_actor, judgement = v_j, note = p_note
   where id = p_review;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor,'PIP_REVIEW_HELD','pip_plan', v_plan.id::text,
          jsonb_build_object('reviewId', p_review, 'judgement', v_j));

  return jsonb_build_object('ok', true, 'judgement', v_j,
    'remaining', (select count(*) from pip_review
                   where plan_id = v_plan.id and held_at is null));
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_acknowledge(p_actor uuid, p_sheet uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s plb_goal_sheet;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;
  if s.person_id <> p_actor then
    return jsonb_build_object('error','not_permitted',
      'reason','Only the person the sheet belongs to can acknowledge it.');
  end if;
  update plb_goal_sheet
     set acknowledged_at = now(),
         status = case when status = 'ISSUED' then 'ACKNOWLEDGED' else status end
   where id = p_sheet;
  return jsonb_build_object('ok', true, 'note','Acknowledged. Not acknowledging would not have changed anything.');
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_actual_from_perf(p_actor uuid, p_sheet uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s plb_goal_sheet; v_rel text; v_frozen timestamptz;
  r record; v numeric; v_set int := 0; v_blank int := 0;
  v_rows jsonb := '[]'::jsonb;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;

  v_rel := perf_rel(p_actor, s.person_id);
  if v_rel not in ('manage','admin') then
    return jsonb_build_object('error','not_permitted',
      'reason','Pulling a quarter''s actuals is the reporting manager''s, or '
               'an administrator''s. You may read the sheet either way.');
  end if;

  select data_frozen_at into v_frozen from plb_result where sheet_id = p_sheet;
  if v_frozen is not null then
    return jsonb_build_object('error','frozen',
      'reason','The KPI source data for that quarter is frozen.');
  end if;

  for r in
    select gk.kpi_id, k.name, k.unit, gk.target_value, gk.actual_value
      from plb_goal_kpi gk
      join kpi_definition k on k.id = gk.kpi_id
     where gk.sheet_id = p_sheet
     order by k.position, k.name
  loop
    v := perf_quarter_value(s.person_id, r.kpi_id, s.quarter);

    if v is null then
      v_blank := v_blank + 1;
      v_rows := v_rows || jsonb_build_object(
        'name', r.name, 'unit', r.unit, 'target', r.target_value,
        'actual', r.actual_value, 'filled', false,
        'why', 'nothing was filed against this measure in the quarter, so the '
               'actual is left as it was rather than written as a zero');
    else
      update plb_goal_kpi set actual_value = v
       where sheet_id = p_sheet and kpi_id = r.kpi_id;
      v_set := v_set + 1;
      v_rows := v_rows || jsonb_build_object(
        'name', r.name, 'unit', r.unit, 'target', r.target_value,
        'was', r.actual_value, 'actual', v, 'filled', true,
        'pct', case when coalesce(r.target_value,0) = 0 then null
                    else round(100.0 * v / r.target_value, 1) end);
    end if;
  end loop;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'PLB_ACTUALS_FROM_FILINGS', 'plb_goal_sheet', p_sheet::text,
          jsonb_build_object('quarter', s.quarter, 'set', v_set, 'blank', v_blank));

  return jsonb_build_object('ok', true, 'set', v_set, 'blank', v_blank,
    'rows', v_rows,
    'note', v_set || ' actual(s) taken from what was filed day by day' ||
            case when v_blank > 0
                 then ', and ' || v_blank || ' left alone because nothing was filed against them'
                 else '' end || '.');
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_actual_set(p_actor uuid, p_sheet uuid, p_kpi uuid, p_actual numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_frozen timestamptz;
begin
  if not exists (select 1 from plb_goal_sheet s2 where s2.id = p_sheet
                  and (perf_may_set(p_actor, s2.person_id) or plb_runs_scheme(p_actor))) then
    return jsonb_build_object('error','not_permitted',
      'reason','An actual is recorded by the person''s own reporting manager, or by HR, Business Excellence or an administrator.');
  end if;
  select data_frozen_at into v_frozen from plb_result where sheet_id = p_sheet;
  if v_frozen is not null then
    return jsonb_build_object('error','frozen',
      'reason','The KPI source data for that quarter is frozen.');
  end if;
  update plb_goal_kpi set actual_value = p_actual
   where sheet_id = p_sheet and kpi_id = p_kpi;
  if not found then return jsonb_build_object('error','no_such_kpi'); end if;
  return jsonb_build_object('ok', true, 'note','Recorded.');
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_attr_decide(p_actor uuid, p_sheet uuid, p_kpi uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s plb_goal_sheet; a plb_goal_attribute;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;
  if s.person_id = p_actor then
    return jsonb_build_object('error','not_permitted',
      'reason','Nobody approves their own attribute.');
  end if;
  select * into a from plb_goal_attribute where sheet_id = p_sheet and kpi_id = p_kpi;
  if a.id is null then return jsonb_build_object('error','not_on_this_sheet'); end if;
  if a.state <> 'PROPOSED' then
    return jsonb_build_object('error','nothing_proposed',
      'reason','There is nothing waiting on you for that attribute.');
  end if;
  if not p_approve and coalesce(btrim(p_note),'') = '' then
    return jsonb_build_object('error','reason_required',
      'reason','Returning a proposal says why, so it can be fixed rather than guessed at.');
  end if;

  update plb_goal_attribute
     set state = case when p_approve then 'APPROVED' else 'RETURNED' end,
         approved_at = case when p_approve then now() else null end,
         approved_by = p_actor, decided_note = nullif(btrim(p_note),'')
   where id = a.id;

  return jsonb_build_object('ok', true,
    'note', case when p_approve then 'Approved. It is now part of the sheet.'
                 else 'Returned, with your reason. It can be proposed again.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_attr_overlap(p_sheet uuid, p_text text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare r record; v_hit text[]; v_out text[] := '{}';
  v_stop text[] := array['about','after','against','before','between','branch','client','crux',
    'every','first','their','there','these','those','through','which','while','within','would',
    'month','monthly','quarter','report','reports','reporting','target','targets','value','values'];
begin
  if coalesce(btrim(p_text),'') = '' then return null; end if;
  for r in
    select d.name from plb_goal_kpi g join kpi_definition d on d.id = g.kpi_id
     where g.sheet_id = p_sheet
  loop
    select array_agg(distinct w) into v_hit
      from unnest(regexp_split_to_array(lower(p_text), '[^a-z]+')) w
     where length(w) >= 5 and not (w = any(v_stop))
       and w = any(regexp_split_to_array(lower(r.name), '[^a-z]+'));
    if v_hit is not null and array_length(v_hit, 1) > 0 then
      v_out := v_out || (array_to_string(v_hit, ', ') || ' -- also in "' || r.name || '"');
    end if;
  end loop;
  if array_length(v_out, 1) is null then return null; end if;
  return array_to_string(v_out, ' | ');
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_attr_propose(p_actor uuid, p_sheet uuid, p_kpi uuid, p_proposal text, p_evidence text, p_m1 text, p_m2 text, p_m3 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s plb_goal_sheet; a plb_goal_attribute; d kpi_definition; v_ov text;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;
  if s.person_id <> p_actor then
    return jsonb_build_object('error','not_permitted',
      'reason','A-4 and A-5 are the two things in the scheme that are yours. Only you propose them.');
  end if;

  select * into a from plb_goal_attribute where sheet_id = p_sheet and kpi_id = p_kpi;
  if a.id is null then return jsonb_build_object('error','not_on_this_sheet'); end if;
  select * into d from kpi_definition where id = p_kpi;
  if d.mandatory then
    return jsonb_build_object('error','fixed_attribute',
      'reason', d.name || ' is the same for everyone and is not proposed.');
  end if;
  if a.state = 'APPROVED' then
    return jsonb_build_object('error','already_approved',
      'reason','That attribute is approved. Changing it now needs a logged correction.');
  end if;

  if coalesce(btrim(p_proposal),'') = '' then
    return jsonb_build_object('error','no_proposal',
      'reason','Say what you are proposing, in a sentence.');
  end if;
  if coalesce(btrim(p_evidence),'') = '' then
    return jsonb_build_object('error','not_verifiable',
      'reason','Q1 of the admissibility test: is it externally verifiable? Name the certificate, '
              'ticket, sign-off or document. Self-assessment is not evidence.');
  end if;
  if coalesce(btrim(p_m1),'') = '' or coalesce(btrim(p_m2),'') = ''
     or coalesce(btrim(p_m3),'') = '' then
    return jsonb_build_object('error','no_milestones',
      'reason','Q2: a milestone for each month, not just an end date. Without them you score '
              'zero in the months before completion -- break it into three.');
  end if;

  v_ov := plb_attr_overlap(p_sheet, p_proposal);

  update plb_goal_attribute
     set proposal = btrim(p_proposal), evidence_ref = btrim(p_evidence),
         m1_milestone = btrim(p_m1), m2_milestone = btrim(p_m2), m3_milestone = btrim(p_m3),
         state = 'PROPOSED', proposed_at = now(),
         approved_at = null, approved_by = null, decided_note = null,
         overlap_note = v_ov
   where id = a.id;

  return jsonb_build_object('ok', true, 'overlap', v_ov,
    'note', case when v_ov is null
      then 'Proposed. Your manager approves or returns it.'
      else 'Proposed, with an overlap flagged against your own measure set: ' || v_ov ||
           '. Q3 says an activity cannot count twice. Your manager will look at it.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_centre(p_person uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select n.name
    from coverage_rule cr join op_node n on n.id = cr.op_node_id
   where cr.person_id = p_person and cr.effective_to is null
     and cr.role in ('BRANCH_MANAGER','LOCATION_HEAD')
   order by case cr.role when 'BRANCH_MANAGER' then 0 else 1 end, n.name
   limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.plb_certify(p_actor uuid, p_sheet uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s plb_goal_sheet; c jsonb;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;
  if s.person_id = p_actor then
    return jsonb_build_object('error','not_permitted',
      'reason','No chair certifies for itself.');
  end if;

  c := plb_compute(p_sheet);
  if c->>'achievement' is null then
    return jsonb_build_object('error','no_actuals',
      'reason','No KPI has an actual recorded, so there is no Achievement to certify.');
  end if;

  insert into plb_result (sheet_id, achievement, payout_factor, months_counted,
                          monthly_mean, consistency, amount_inr,
                          data_frozen_at, computed_at, certified_by, certified_at)
  values (p_sheet, (c->>'achievement')::numeric, (c->>'payoutFactor')::numeric,
          (c->>'monthsCounted')::int, (c->>'monthlyMean')::numeric,
          (c->>'consistency')::numeric, (c->>'amount')::numeric,
          now(), now(), p_actor, now())
  on conflict (sheet_id) do update
     set achievement = excluded.achievement, payout_factor = excluded.payout_factor,
         months_counted = excluded.months_counted, monthly_mean = excluded.monthly_mean,
         consistency = excluded.consistency, amount_inr = excluded.amount_inr,
         data_frozen_at = coalesce(plb_result.data_frozen_at, now()),
         computed_at = now(), certified_by = excluded.certified_by, certified_at = now()
   where plb_result.published_at is null;

  return c || jsonb_build_object('ok', true, 'certified', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_compute(p_sheet uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  s plb_goal_sheet;
  v_ach numeric; v_weights numeric; v_total numeric;
  v_mean numeric; v_months int; v_pf numeric; v_cf numeric; v_missing int;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;

  select sum(g.weight_pct * least(
             case when g.target_value is null or g.target_value = 0 then null
                  else g.actual_value / g.target_value end, 1.5))
           filter (where g.actual_value is not null and g.target_value is not null
                     and g.target_value <> 0),
         sum(g.weight_pct)
           filter (where g.actual_value is not null and g.target_value is not null
                     and g.target_value <> 0),
         sum(g.weight_pct),
         count(*) filter (where g.actual_value is null or g.target_value is null
                             or g.target_value = 0)
    into v_ach, v_weights, v_total, v_missing
    from plb_goal_kpi g where g.sheet_id = p_sheet;

  -- The whole measure set, or no answer. A partial Achievement is not a small
  -- Achievement -- it is a different number wearing the same name.
  if v_weights is null or v_total is null or abs(v_weights - v_total) > 0.001 then
    v_ach := null;
  else
    v_ach := round(v_ach, 3);
  end if;

  select round(avg(m.monthly_score), 3), count(*)
    into v_mean, v_months
    from plb_month_score m
   where m.sheet_id = p_sheet and not m.excluded
     and m.kpi_points is not null and m.attr_points is not null;

  v_pf := plb_payout_factor(v_ach);
  v_cf := plb_consistency(v_mean);

  return jsonb_build_object(
    'sheetId', p_sheet, 'quarter', s.quarter, 'targetPlb', s.target_plb_inr,
    'achievement', v_ach, 'payoutFactor', v_pf,
    'monthsCounted', v_months, 'monthlyMean', v_mean, 'consistency', v_cf,
    'amount', case when v_pf is null or v_cf is null then null
                   else round(s.target_plb_inr * v_pf / 100.0 * v_cf, 2) end,
    'weightsSeen', v_weights, 'weightsTotal', v_total,
    'measuresWithoutAnActual', v_missing);
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_consistency(p_mean numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case when p_mean is null then null
              else greatest(0.30, round(p_mean / 10.0, 4)) end;
$function$
;

CREATE OR REPLACE FUNCTION public.plb_countersign(p_actor uuid, p_sheet uuid, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m plb_month_score; s plb_goal_sheet;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  select * into m from plb_month_score where sheet_id = p_sheet and month = date_trunc('month',p_month)::date;
  if m.id is null then return jsonb_build_object('error','not_scored'); end if;
  if s.person_id = p_actor then
    return jsonb_build_object('error','not_permitted',
      'reason','A countersignature is a second pair of eyes, not your own.');
  end if;
  if m.scored_by = p_actor then
    return jsonb_build_object('error','not_permitted',
      'reason','You scored this month. Somebody else countersigns it.');
  end if;
  if coalesce(m.attr_points, 0) <= 7.5 then
    return jsonb_build_object('error','not_needed',
      'reason','An attribute score of ' || coalesce(m.attr_points,0) ||
               ' does not need a countersignature. Only above 7.5 does.');
  end if;
  update plb_month_score set countersign_by = p_actor, countersign_at = now() where id = m.id;
  return jsonb_build_object('ok', true, 'note','Countersigned.');
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_dispute_decide(p_actor uuid, p_dispute uuid, p_outcome text, p_decision text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d plb_dispute; s plb_goal_sheet;
begin
  select * into d from plb_dispute where id = p_dispute;
  if d.id is null then return jsonb_build_object('error','no_such_dispute'); end if;
  select * into s from plb_goal_sheet where id = d.sheet_id;
  if s.person_id = p_actor then
    return jsonb_build_object('error','not_permitted','reason','It is your own matter.');
  end if;
  -- "Nobody who made an earlier decision in your matter can decide your appeal"
  if d.responded_by = p_actor then
    return jsonb_build_object('error','already_decided_once',
      'reason','You wrote the response. Nobody who made an earlier decision in this matter '
              'can decide it again.');
  end if;
  if d.stage not in ('RAISED','RESPONDED','ESCALATED') then
    return jsonb_build_object('error','closed','reason','This dispute is already closed.');
  end if;
  if p_outcome not in ('UPHELD','PARTLY_UPHELD','REJECTED') then
    return jsonb_build_object('error','bad_outcome');
  end if;
  if coalesce(btrim(p_decision),'') = '' then
    return jsonb_build_object('error','no_decision',
      'reason','The decision is in writing, with reasons. That is the whole point of the stage.');
  end if;

  update plb_dispute
     set stage = 'DECIDED', outcome = p_outcome, decision = btrim(p_decision),
         decided_by = p_actor, decided_at = now(), closed_at = now(),
         ring_fenced_inr = case when p_outcome = 'REJECTED' then 0 else ring_fenced_inr end
   where id = p_dispute;

  insert into plb_correction (what, row_id, field, was, now_is, why, who)
  values ('plb_dispute', p_dispute, 'outcome', d.stage, p_outcome, btrim(p_decision), p_actor);

  return jsonb_build_object('ok', true,
    'note', case p_outcome
      when 'REJECTED' then 'Rejected, in writing. The ring-fence is released and the full '
                           'published amount is payable.'
      when 'UPHELD'   then 'Upheld. Correct the figure on the sheet; the recomputed result '
                           'is what is paid.'
      else 'Partly upheld. Correct what was accepted; the rest stands.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_dispute_escalate(p_actor uuid, p_dispute uuid, p_why text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d plb_dispute; s plb_goal_sheet; v_centre text;
begin
  select * into d from plb_dispute where id = p_dispute;
  if d.id is null then return jsonb_build_object('error','no_such_dispute'); end if;
  select * into s from plb_goal_sheet where id = d.sheet_id;
  if s.person_id <> p_actor then
    return jsonb_build_object('error','not_permitted','reason','Escalating is the employee''s.');
  end if;
  if d.stage <> 'RESPONDED' then
    return jsonb_build_object('error','nothing_to_escalate',
      'reason','There is no response to escalate yet.');
  end if;
  if current_date > d.escalate_due then
    return jsonb_build_object('error','too_late',
      'reason','The escalation window closed on ' || to_char(d.escalate_due,'DD Mon YYYY') || '.');
  end if;
  if coalesce(btrim(p_why),'') = '' then
    return jsonb_build_object('error','no_reason',
      'reason','Say why the response is not accepted.');
  end if;
  v_centre := plb_centre(s.person_id);
  update plb_dispute
     set stage = 'ESCALATED', escalated_at = now(), escalate_reason = btrim(p_why),
         decide_due = plb_wd_after(current_date, 10, v_centre)
   where id = p_dispute;
  return jsonb_build_object('ok', true,
    'note','Escalated. The Functional Head decides in writing by ' ||
      to_char(plb_wd_after(current_date, 10, v_centre),'DD Mon YYYY') || '.');
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_dispute_impact(p_dispute uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d plb_dispute; s plb_goal_sheet; c jsonb;
  v_old numeric; v_new numeric; v_ach numeric; v_pf numeric;
  g plb_goal_kpi; v_t numeric; v_a numeric;
begin
  select * into d from plb_dispute where id = p_dispute;
  if d.id is null or d.kpi_id is null or d.claimed_value is null then return null; end if;
  if d.element not in ('ACTUAL','TARGET') then return null; end if;

  select * into s from plb_goal_sheet where id = d.sheet_id;
  c := plb_compute(d.sheet_id);
  if (c->>'achievement') is null or (c->>'amount') is null then return null; end if;
  v_old := (c->>'amount')::numeric;

  select * into g from plb_goal_kpi where sheet_id = d.sheet_id and kpi_id = d.kpi_id;
  if g.id is null then return null; end if;
  v_t := case when d.element = 'TARGET' then d.claimed_value else g.target_value end;
  v_a := case when d.element = 'ACTUAL' then d.claimed_value else g.actual_value end;
  if v_t is null or v_t = 0 or v_a is null then return null; end if;

  -- the same arithmetic plb_compute does, with one row swapped
  v_ach := round((c->>'achievement')::numeric
           - g.weight_pct * least(g.actual_value / g.target_value, 1.5)
           + g.weight_pct * least(v_a / v_t, 1.5), 3);
  v_pf  := plb_payout_factor(v_ach);
  v_new := round(s.target_plb_inr * v_pf / 100.0 * (c->>'consistency')::numeric, 2);
  return greatest(v_new - v_old, 0);
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_dispute_raise(p_actor uuid, p_sheet uuid, p_element text, p_kpi uuid, p_month date, p_claimed text, p_claimed_value numeric, p_evidence text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s plb_goal_sheet; w jsonb; v_id uuid; v_centre text; v_impact numeric;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;
  if s.person_id <> p_actor then
    return jsonb_build_object('error','not_permitted',
      'reason','A dispute is the employee''s own. A manager who thinks a figure is wrong '
              'raises a correction, not a dispute.');
  end if;
  w := plb_dispute_window(p_sheet);
  if not (w->>'published')::boolean then
    return jsonb_build_object('error','not_published', 'reason', w->>'why');
  end if;
  if not (w->>'open')::boolean then
    return jsonb_build_object('error','window_closed',
      'reason','The window closed on ' || (w->>'closesOn') || '. Ten working days from '
              || (w->>'opensOn') || ', counted on the ' || coalesce(w->>'centre','national')
              || ' calendar.');
  end if;
  if coalesce(btrim(p_claimed),'') = '' then
    return jsonb_build_object('error','no_claim',
      'reason','Say what figure you believe is right. A dispute names an element and a number.');
  end if;
  if coalesce(btrim(p_evidence),'') = '' then
    return jsonb_build_object('error','no_evidence',
      'reason','Name your evidence. The same rule binds their response.');
  end if;

  v_centre := w->>'centre';
  insert into plb_dispute (sheet_id, element, kpi_id, month, claimed, claimed_value,
                           evidence, raised_by, respond_due)
  values (p_sheet, p_element, p_kpi, case when p_month is null then null
            else date_trunc('month', p_month)::date end,
          btrim(p_claimed), p_claimed_value, btrim(p_evidence), p_actor,
          plb_wd_after(current_date, 5, v_centre))
  returning id into v_id;

  v_impact := plb_dispute_impact(v_id);
  update plb_dispute set ring_fenced_inr = v_impact where id = v_id;

  return jsonb_build_object('ok', true, 'disputeId', v_id,
    'ringFenced', v_impact,
    'note', 'Raised. They have until ' ||
      to_char(plb_wd_after(current_date, 5, v_centre), 'DD Mon YYYY') ||
      ' to respond in writing with reasons and evidence.' ||
      case when v_impact is null or v_impact = 0 then
        ' Nothing is ring-fenced: this claim does not change the amount by itself.'
      else ' ' || to_char(v_impact, 'FM9,99,99,999.00') ||
           ' is ring-fenced meanwhile. The rest is paid on time.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_dispute_respond(p_actor uuid, p_dispute uuid, p_response text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d plb_dispute; s plb_goal_sheet; v_centre text; v_late int; v_due date;
begin
  select * into d from plb_dispute where id = p_dispute;
  if d.id is null then return jsonb_build_object('error','no_such_dispute'); end if;
  select * into s from plb_goal_sheet where id = d.sheet_id;
  if s.person_id = p_actor then
    return jsonb_build_object('error','not_permitted','reason','You raised this one.');
  end if;
  if d.stage <> 'RAISED' then
    return jsonb_build_object('error','not_awaiting_response',
      'reason','This dispute is at ' || lower(d.stage) || ', not waiting on a response.');
  end if;
  if coalesce(btrim(p_response),'') = '' then
    return jsonb_build_object('error','no_response',
      'reason','A response that cites no evidence is not a response, and the clock keeps running.');
  end if;

  v_centre := plb_centre(s.person_id);
  -- the delay, if there was one, is added to THEIR next deadline, not ours
  v_late := plb_wd_count(d.respond_due, current_date, v_centre);
  v_due  := plb_wd_after(current_date, 5 + v_late, v_centre);

  update plb_dispute
     set stage = 'RESPONDED', response = btrim(p_response),
         responded_by = p_actor, responded_at = now(), escalate_due = v_due
   where id = p_dispute;

  return jsonb_build_object('ok', true, 'lateWorkingDays', v_late,
    'note','Responded. They have until ' || to_char(v_due,'DD Mon YYYY') || ' to escalate' ||
      case when v_late > 0 then ' -- ' || v_late ||
        ' working day(s) were added because the response was late.' else '.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_dispute_window(p_sheet uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s plb_goal_sheet; r plb_result; v_centre text; v_from date; v_close date;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;
  select * into r from plb_result where sheet_id = p_sheet;
  if r.published_at is null then
    return jsonb_build_object('published', false, 'open', false,
      'why','The window opens when the result is published, not when it is certified.');
  end if;
  v_centre := plb_centre(s.person_id);
  v_from   := (r.published_at at time zone 'Asia/Kolkata')::date;
  v_close  := plb_wd_after(v_from, 10, v_centre);
  return jsonb_build_object(
    'published', true, 'centre', v_centre,
    'opensOn', v_from, 'closesOn', v_close,
    'workingDaysLeft', plb_wd_count(current_date, v_close, v_centre),
    'open', current_date <= v_close);
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_dispute_withdraw(p_actor uuid, p_dispute uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d plb_dispute; s plb_goal_sheet;
begin
  select * into d from plb_dispute where id = p_dispute;
  if d.id is null then return jsonb_build_object('error','no_such_dispute'); end if;
  select * into s from plb_goal_sheet where id = d.sheet_id;
  if s.person_id <> p_actor then
    return jsonb_build_object('error','not_permitted','reason','Only the person who raised it.');
  end if;
  if d.closed_at is not null then
    return jsonb_build_object('error','closed');
  end if;
  update plb_dispute set stage = 'WITHDRAWN', closed_at = now(), ring_fenced_inr = 0
   where id = p_dispute;
  return jsonb_build_object('ok', true,
    'note','Withdrawn. Nothing follows from having raised it.');
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_disputes(p_sheet uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d.id, 'element', d.element, 'kpi', k.name, 'month', d.month,
    'claimed', d.claimed, 'claimedValue', d.claimed_value, 'evidence', d.evidence,
    'raisedBy', (select full_name from person where id = d.raised_by),
    'raisedAt', d.raised_at, 'stage', d.stage, 'outcome', d.outcome,
    'respondDue', d.respond_due, 'response', d.response,
    'respondedBy', (select full_name from person where id = d.responded_by),
    'respondedAt', d.responded_at,
    'escalateDue', d.escalate_due, 'escalatedAt', d.escalated_at,
    'escalateReason', d.escalate_reason,
    'decideDue', d.decide_due, 'decision', d.decision,
    'decidedBy', (select full_name from person where id = d.decided_by),
    'decidedAt', d.decided_at,
    'ringFenced', d.ring_fenced_inr, 'closedAt', d.closed_at,
    'overdue', case when d.closed_at is not null then false
                    when d.stage = 'RAISED'    then current_date > d.respond_due
                    when d.stage = 'ESCALATED' then current_date > d.decide_due
                    else false end)
    order by d.raised_at), '[]'::jsonb)
  from plb_dispute d left join kpi_definition k on k.id = d.kpi_id
  where d.sheet_id = p_sheet;
$function$
;

CREATE OR REPLACE FUNCTION public.plb_month_suggest(p_actor uuid, p_sheet uuid, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s plb_goal_sheet; v_rel text; c perf_cycle;
  r record; v numeric; ratio numeric; pts numeric;
  v_sum numeric := 0; v_n int := 0; v_blank int := 0;
  v_rows jsonb := '[]'::jsonb; v_now jsonb;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;

  v_rel := perf_rel(p_actor, s.person_id);
  if v_rel is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That person is not in your line.');
  end if;

  select * into c from perf_cycle
   where period_kind = 'MONTH'
     and period_start = date_trunc('month', p_month)::date;
  if c.id is null then
    return jsonb_build_object('error','no_such_cycle',
      'reason','No monthly cycle has been opened for ' ||
               to_char(date_trunc('month', p_month), 'Mon YYYY') || '.');
  end if;

  for r in
    select gk.kpi_id, k.name, k.unit, gk.weight_pct
      from plb_goal_kpi gk
      join kpi_definition k on k.id = gk.kpi_id
     where gk.sheet_id = p_sheet
     order by k.position, k.name
  loop
    select perf_value(a.id), a.target_value into v, ratio
      from perf_assignment a
     where a.person_id = s.person_id and a.kpi_id = r.kpi_id
       and a.cycle_id = c.id and a.part_of_id is null
     limit 1;

    if v is null or coalesce(ratio, 0) = 0 then
      v_blank := v_blank + 1;
      v_rows := v_rows || jsonb_build_object(
        'name', r.name, 'unit', r.unit, 'points', null, 'counted', false,
        'why', case when v is null then 'nothing filed in this month'
                    else 'no target was set for this month' end);
      continue;
    end if;

    -- A ceiling measure is met by being small. Turning it the right way up
    -- here rather than in the caller is the difference between rewarding a
    -- low error rate and punishing it.
    ratio := case when perf_direction(r.unit) = 'CEILING'
                  then case when v = 0 then 150 else least(150, round(100.0 * ratio / v, 2)) end
                  else least(150, round(100.0 * v / ratio, 2)) end;

    pts := case when ratio >= 100 then 2.0
                when ratio >= 50  then 1.0
                else 0.0 end;

    v_sum := v_sum + pts; v_n := v_n + 1;
    v_rows := v_rows || jsonb_build_object(
      'name', r.name, 'unit', r.unit, 'value', v,
      'pct', ratio, 'points', pts, 'counted', true,
      'why', case when pts = 2 then 'at or past the target'
                  when pts = 1 then 'part of the way there'
                  else 'short of half the target' end);
  end loop;

  select jsonb_build_object('kpiPoints', ms.kpi_points, 'attrPoints', ms.attr_points,
                            'monthlyScore', ms.monthly_score,
                            'lockedAt', ms.locked_at, 'scoredAt', ms.scored_at)
    into v_now
    from plb_month_score ms
   where ms.sheet_id = p_sheet and ms.month = date_trunc('month', p_month)::date;

  return jsonb_build_object(
    'month', date_trunc('month', p_month)::date,
    'rel', v_rel,
    'maySet', v_rel in ('manage','admin'),
    'measures', v_rows,
    'counted', v_n, 'blank', v_blank,
    -- Out of ten, because the Constitution's KPI half is scored out of ten
    -- and the arithmetic downstream expects it that way.
    'suggested', case when v_n = 0 then null
                      else round(10.0 * v_sum / (2.0 * v_n), 2) end,
    'now', v_now,
    'says', case
      when v_n = 0 then 'Nothing can be suggested: no measure has both a target and a number this month.'
      else 'Suggested from ' || v_n || ' measure(s) with a target and a number' ||
           case when v_blank > 0 then ', ' || v_blank || ' left out and each one says why' else '' end ||
           '. This is what the filings say. The score is yours.' end,
    'note', 'Two points a measure: at or past the target is two, at least '
            'half way is one, short of that is none. Nothing here has been '
            'written -- it is a reading of the month, not a verdict on it.');
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_payout_factor(p_achievement numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p_achievement is null      then null
    when p_achievement < 50         then 0::numeric
    when p_achievement <= 85        then round((p_achievement - 50) * (100.0/35.0), 3)
    when p_achievement <= 95        then round(100 + (p_achievement - 85) * 0.5, 3)
    when p_achievement <= 115       then round(105 + (p_achievement - 95) * 1.0, 3)
    else 125::numeric
  end;
$function$
;

CREATE OR REPLACE FUNCTION public.plb_phase_targets(p_actor uuid, p_sheet uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s plb_goal_sheet; r record; c record;
  v_cycles uuid[]; v_n int; v_share numeric; v_kind text;
  v_set int := 0; v_pinned int := 0; v_blank int := 0; v_rows jsonb := '[]'::jsonb;
  v_shares numeric[]; i int;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;

  if not perf_may_set(p_actor, s.person_id) then
    return jsonb_build_object('error','not_permitted',
      'reason','Phasing a quarter into months sets somebody''s targets, and '
               'belongs to the person they report to.');
  end if;
  if s.status = 'LOCKED' then
    return jsonb_build_object('error','locked',
      'reason','That goal sheet is locked.');
  end if;

  select array_agg(q order by q) into v_cycles
    from plb_quarter_cycles(s.quarter) q;
  v_n := coalesce(array_length(v_cycles,1), 0);
  if v_n = 0 then
    return jsonb_build_object('error','no_cycles',
      'reason','No monthly period has been opened inside that quarter, so '
               'there is nothing to phase the target into.');
  end if;

  for r in
    select gk.kpi_id, gk.target_value, k.name, k.unit,
           perf_accrual_kind(k.id, k.unit) as kind
      from plb_goal_kpi gk join kpi_definition k on k.id = gk.kpi_id
     where gk.sheet_id = p_sheet
     order by k.position, k.name
  loop
    if r.target_value is null then
      v_blank := v_blank + 1;
      v_rows := v_rows || jsonb_build_object('name', r.name, 'set', 0,
        'why','no quarterly target to phase');
      continue;
    end if;

    -- The same rule a third time: a count divides, a level is copied.
    if r.kind = 'SUM' then
      v_share := round(r.target_value / v_n, 2);
    else
      v_share := r.target_value;
    end if;

    -- The three share columns are NOT NULL and default to zero, so a
    -- quarter with fewer than three months open writes zero for the
    -- months that do not exist. Zero is the honest value: there is no
    -- cycle to ask anybody for a number in.
    v_shares := '{}';
    for i in 1..3 loop
      v_shares := v_shares || case when i <= v_n then v_share else 0 end;
    end loop;
    update plb_goal_kpi
       set m1_share = v_shares[1], m2_share = v_shares[2], m3_share = v_shares[3]
     where sheet_id = p_sheet and kpi_id = r.kpi_id;

    -- Write each month's assignment, except where somebody agreed one by
    -- hand. The arithmetic gives way to the agreement.
    for c in
      select a.id, a.target_source
        from perf_assignment a
       where a.person_id = s.person_id and a.kpi_id = r.kpi_id
         and a.part_of_id is null
         and a.cycle_id = any(v_cycles)
    loop
      if c.target_source = 'MANUAL' then
        v_pinned := v_pinned + 1;
      else
        update perf_assignment
           set target_value = v_share, target_source = 'SHARED'
         where id = c.id;
        v_set := v_set + 1;
      end if;
    end loop;

    v_rows := v_rows || jsonb_build_object(
      'name', r.name, 'kind', r.kind, 'quarterly', r.target_value,
      'eachMonth', v_share, 'months', v_n,
      'divides', r.kind = 'SUM');
  end loop;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor,'PLB_TARGETS_PHASED','plb_goal_sheet', p_sheet::text,
          jsonb_build_object('set', v_set, 'pinned', v_pinned,
                             'months', v_n, 'quarter', s.quarter));

  return jsonb_build_object('ok', true,
    'months', v_n, 'set', v_set, 'leftPinned', v_pinned, 'noTarget', v_blank,
    'measures', v_rows,
    'note', v_set || ' monthly target(s) now come from the quarter' ||
      case when v_pinned > 0
           then ', and ' || v_pinned || ' agreed by hand were left alone'
           else '' end ||
      case when v_n < 3
           then '. Only ' || v_n || ' month(s) of that quarter are open, so the '
                'target divided across those.'
           else '.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_publish(p_actor uuid, p_sheet uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update plb_result set published_at = now()
   where sheet_id = p_sheet and certified_at is not null and published_at is null;
  if not found then
    return jsonb_build_object('error','not_certified',
      'reason','A result is published after it is certified, not before.');
  end if;
  return jsonb_build_object('ok', true,
    'note','Published in full. The dispute window is 10 working days from today.');
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_quarter(p_quarter date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'error', 'no_actor',
    'reason', 'The quarter is read as somebody. Call plb_quarter(quarter, actor) so the answer can be narrowed to the sheets that person may see.',
    'quarter', date_trunc('quarter', p_quarter)::date,
    'sheets', '[]'::jsonb, 'inScheme', '[]'::jsonb);
$function$
;

CREATE OR REPLACE FUNCTION public.plb_quarter(p_quarter date, p_actor uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'quarter', date_trunc('quarter', p_quarter)::date,
    'sheets', coalesce((
      select jsonb_agg(jsonb_build_object(
               'sheetId', s.id, 'person', p.full_name, 'personId', p.id,
               'employeeNo', p.employee_no,
               'chair', ch.title, 'status', s.status, 'targetPlb', s.target_plb_inr,
               'rel', perf_rel(p_actor, p.id),
               'maySet', perf_rel(p_actor, p.id) in ('manage','admin'),
               'acknowledged', s.acknowledged_at is not null,
               'monthsScored', (select count(*) from plb_month_score ms
                                 where ms.sheet_id = s.id and ms.kpi_points is not null),
               'attrsPending', (select count(*) from plb_goal_attribute ga
                                 where ga.sheet_id = s.id and ga.state = 'PROPOSED'),
               'needsCountersign', (select count(*) from plb_month_score ms
                                     where ms.sheet_id = s.id and coalesce(ms.attr_points,0) > 7.5
                                       and ms.countersign_at is null),
               'disputesOpen', (select count(*) from plb_dispute d
                                 where d.sheet_id = s.id and d.closed_at is null),
               'disputesOverdue', (select count(*) from plb_dispute d
                                 where d.sheet_id = s.id and d.closed_at is null
                                   and ((d.stage = 'RAISED' and current_date > d.respond_due)
                                     or (d.stage = 'ESCALATED' and current_date > d.decide_due))),
               'certified', (select r.certified_at is not null from plb_result r where r.sheet_id = s.id),
               'published', (select r.published_at is not null from plb_result r where r.sheet_id = s.id),
               'amount', (select r.amount_inr from plb_result r where r.sheet_id = s.id))
               order by ch.title, p.full_name)
        from plb_goal_sheet s
        join person p on p.id = s.person_id
        join chair ch on ch.id = s.chair_id
       where s.quarter = date_trunc('quarter', p_quarter)::date
         and perf_rel(p_actor, p.id) is not null), '[]'::jsonb),
    'inScheme', coalesce((
      select jsonb_agg(jsonb_build_object(
               'personId', p.id, 'person', p.full_name, 'employeeNo', p.employee_no,
               'chair', ch.title, 'chairCode', ch.code,
               'rel', perf_rel(p_actor, p.id),
               'kpiCount', (select count(*) from kpi_definition k
                             where k.chair_id = ch.id and k.active and k.position < 100),
               'hasSheet', exists (select 1 from plb_goal_sheet s
                                    where s.person_id = p.id
                                      and s.quarter = date_trunc('quarter', p_quarter)::date))
               order by ch.title, p.full_name)
        from chair_holder h
        join person p on p.id = h.person_id
        join chair ch on ch.id = h.chair_id
       where h.to_date is null
         and exists (select 1 from kpi_definition k
                      where k.chair_id = ch.id and k.active and k.position < 100)
         and perf_rel(p_actor, p.id) is not null), '[]'::jsonb));
$function$
;

CREATE OR REPLACE FUNCTION public.plb_quarter_cycles(p_quarter date)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select c.id from perf_cycle c
   where c.period_kind = 'MONTH'
     and c.period_start >= date_trunc('quarter', p_quarter)::date
     and c.period_start <  (date_trunc('quarter', p_quarter) + interval '3 months')::date
   order by c.period_start
$function$
;

CREATE OR REPLACE FUNCTION public.plb_quarter_from_months(p_person uuid, p_kpi uuid, p_quarter date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_kind text; v numeric;
begin
  select perf_accrual_kind(a.kpi_id, a.unit) into v_kind
    from perf_assignment a
   where a.person_id = p_person and a.kpi_id = p_kpi
     and a.cycle_id in (select plb_quarter_cycles(p_quarter))
     and a.part_of_id is null
   limit 1;
  if v_kind is null then return null; end if;

  if v_kind = 'SUM' then
    select sum(a.target_value) into v from perf_assignment a
     where a.person_id = p_person and a.kpi_id = p_kpi
       and a.part_of_id is null
       and a.cycle_id in (select plb_quarter_cycles(p_quarter));
  else
    -- A level is not added across months. Three months at 95% is a 95%
    -- quarter, not a 285% one.
    select avg(a.target_value) into v from perf_assignment a
     where a.person_id = p_person and a.kpi_id = p_kpi
       and a.part_of_id is null and a.target_value is not null
       and a.cycle_id in (select plb_quarter_cycles(p_quarter));
  end if;
  return v;
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_runs_scheme(p_actor uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from person p
     where p.id = p_actor
       and p.employment_status = 'ACTIVE' and p.superseded_by is null
       and (p.app_role = 'ADMIN'
            or coalesce(p.department,'') in ('Human Resources','Business Excellence')));
$function$
;

CREATE OR REPLACE FUNCTION public.plb_score_lock(p_actor uuid, p_sheet uuid, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_month date; v_n int; m plb_month_score;
begin
  v_month := date_trunc('month', p_month)::date;
  select * into m from plb_month_score where sheet_id = p_sheet and month = v_month;

  if m.id is not null and coalesce(m.attr_points, 0) > 7.5 and m.countersign_at is null then
    return jsonb_build_object('error','needs_countersign',
      'reason','An attribute score of ' || m.attr_points || ' out of 10 needs the Functional '
              'Head to countersign before the month locks. High attribute scores are checked, '
              'not waved through.');
  end if;

  update plb_month_score set locked_at = now()
   where sheet_id = p_sheet and month = v_month and locked_at is null
     and kpi_points is not null and attr_points is not null;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    insert into plb_month_score (sheet_id, month, excluded, excluded_why, locked_at)
    values (p_sheet, v_month, true, 'Nobody scored this month', now())
    on conflict (sheet_id, month) do update
       set excluded = true, excluded_why = 'Nobody scored this month', locked_at = now()
     where plb_month_score.kpi_points is null;
    return jsonb_build_object('ok', true, 'excluded', true,
      'note','Nobody scored that month, so it is excluded and the denominator reduces. '
             'The employee does not carry the omission.');
  end if;
  return jsonb_build_object('ok', true, 'note','Score locked for ' || to_char(v_month,'Mon YYYY') || '.');
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_score_month(p_actor uuid, p_sheet uuid, p_month date, p_kpi numeric, p_attr numeric, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s plb_goal_sheet; m plb_month_score; v_month date; v_gap numeric; v_self numeric;
begin
  v_month := date_trunc('month', p_month)::date;
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;
  if not (perf_may_set(p_actor, s.person_id) or plb_runs_scheme(p_actor)) then
    return jsonb_build_object('error','not_permitted',
      'reason','A month is scored by the person''s own reporting manager, or by HR, Business Excellence or an administrator.');
  end if;
  if s.person_id = p_actor then
    return jsonb_build_object('error','not_permitted',
      'reason','Nobody scores themselves.');
  end if;
  if p_kpi is null or p_attr is null then
    return jsonb_build_object('error','incomplete',
      'reason','Both halves are needed: KPIs out of 10 and attributes out of 10.');
  end if;
  if p_kpi * 2 <> floor(p_kpi * 2) or p_attr * 2 <> floor(p_attr * 2) then
    return jsonb_build_object('error','not_half_steps',
      'reason','Scores move in half-point steps against published anchors.');
  end if;

  select * into m from plb_month_score where sheet_id = p_sheet and month = v_month;
  if m.locked_at is not null then
    return jsonb_build_object('error','locked',
      'reason','That month is locked. Changing it needs a logged correction.');
  end if;

  -- the 2-point rule
  if m.self_kpi is not null and m.self_attr is not null then
    v_self := 0.75 * m.self_kpi + 0.25 * m.self_attr;
    v_gap  := abs((0.75 * p_kpi + 0.25 * p_attr) - v_self);
    if v_gap >= 2.0 and coalesce(btrim(p_reason),'') = '' then
      return jsonb_build_object('error','reason_required',
        'reason','Your score differs from the self-evaluation by ' || round(v_gap,2) ||
                 ' points. Name the component that accounts for the gap -- one line. '
                 'The score still stands; the explanation is compulsory.');
    end if;
  end if;

  insert into plb_month_score (sheet_id, month, kpi_points, attr_points,
                               scored_by, scored_at, gap_reason)
  values (p_sheet, v_month, p_kpi, p_attr, p_actor, now(), p_reason)
  on conflict (sheet_id, month) do update
     set kpi_points = excluded.kpi_points, attr_points = excluded.attr_points,
         scored_by = excluded.scored_by, scored_at = now(),
         gap_reason = coalesce(excluded.gap_reason, plb_month_score.gap_reason);

  return jsonb_build_object('ok', true,
    'monthlyScore', round(0.75 * p_kpi + 0.25 * p_attr, 2),
    'note', 'Scored ' || round(0.75 * p_kpi + 0.25 * p_attr, 2) || ' out of 10 for '
            || to_char(v_month, 'Mon YYYY') || '.');
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_self_eval(p_actor uuid, p_sheet uuid, p_month date, p_kpi numeric, p_attr numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s plb_goal_sheet;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.person_id <> p_actor then
    return jsonb_build_object('error','not_permitted',
      'reason','A self-evaluation is your own.');
  end if;
  insert into plb_month_score (sheet_id, month, self_kpi, self_attr, self_at)
  values (p_sheet, date_trunc('month', p_month)::date, p_kpi, p_attr, now())
  on conflict (sheet_id, month) do update
     set self_kpi = excluded.self_kpi, self_attr = excluded.self_attr, self_at = now()
   where plb_month_score.locked_at is null;
  return jsonb_build_object('ok', true,
    'note','Recorded. It is an input, not a score, and it is not averaged with your manager''s.');
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_sheet(p_sheet uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with s as (select * from plb_goal_sheet where id = p_sheet),
  c as (select plb_compute(p_sheet) as calc),
  fence as (select coalesce(sum(d.ring_fenced_inr), 0) as inr
              from plb_dispute d
             where d.sheet_id = p_sheet and d.closed_at is null),
  k as (
    select jsonb_agg(jsonb_build_object(
             'kpiId', g.kpi_id, 'name', d.name, 'unit', d.unit,
             'weight', g.weight_pct, 'target', g.target_value,
             'actual', g.actual_value,
             'ratio', case when g.target_value is null or g.target_value = 0 or g.actual_value is null
                           then null else round(100 * g.actual_value / g.target_value, 2) end,
             'ratioCapped', case when g.target_value is null or g.target_value = 0 or g.actual_value is null
                           then null else round(100 * least(g.actual_value / g.target_value, 1.5), 2) end,
             'basisLevel', g.basis_level, 'basisNote', g.basis_note,
             'split', jsonb_build_array(g.m1_share, g.m2_share, g.m3_share))
             order by d.position) as kpis
      from plb_goal_kpi g join kpi_definition d on d.id = g.kpi_id
     where g.sheet_id = p_sheet),
  a as (
    select jsonb_agg(jsonb_build_object(
             'kpiId', ga.kpi_id, 'name', d.name, 'unit', d.unit,
             'fixed', d.mandatory, 'proposal', ga.proposal,
             'state', ga.state, 'evidence', ga.evidence_ref,
             'milestones', jsonb_build_array(ga.m1_milestone, ga.m2_milestone, ga.m3_milestone),
             'overlapNote', ga.overlap_note, 'decidedNote', ga.decided_note,
             'proposedAt', ga.proposed_at,
             'approvedBy', (select full_name from person where id = ga.approved_by),
             'approvedAt', ga.approved_at) order by d.position) as attributes
      from plb_goal_attribute ga join kpi_definition d on d.id = ga.kpi_id
     where ga.sheet_id = p_sheet),
  m as (
    select jsonb_agg(jsonb_build_object(
             'month', ms.month, 'kpiPoints', ms.kpi_points,
             'attrPoints', ms.attr_points, 'monthlyScore', ms.monthly_score,
             'selfKpi', ms.self_kpi, 'selfAttr', ms.self_attr,
             'selfAt', ms.self_at, 'gapReason', ms.gap_reason,
             'lockedAt', ms.locked_at, 'excluded', ms.excluded,
             'excludedWhy', ms.excluded_why,
             'needsCountersign', coalesce(ms.attr_points, 0) > 7.5,
             'countersignAt', ms.countersign_at,
             'countersignBy', (select p.full_name from person p where p.id = ms.countersign_by),
             'scoredBy', (select p.full_name from person p where p.id = ms.scored_by))
             order by ms.month) as months
      from plb_month_score ms where ms.sheet_id = p_sheet),
  r as (select * from plb_result where sheet_id = p_sheet)
  select jsonb_build_object(
    'sheetId',   s.id,
    'person',    (select full_name from person where id = s.person_id),
    'personId',  s.person_id,
    'chair',     (select title from chair where id = s.chair_id),
    'quarter',   s.quarter,
    'status',    s.status,
    'isDefault', s.is_default,
    'issuedAt',  s.issued_at,
    'issuedBy',  (select full_name from person where id = s.issued_by),
    'acknowledgedAt', s.acknowledged_at,
    'lockedAt',  s.locked_at,
    'targetPlb', s.target_plb_inr,
    'kpis',      coalesce(k.kpis, '[]'::jsonb),
    'attributes',coalesce(a.attributes, '[]'::jsonb),
    'months',    coalesce(m.months, '[]'::jsonb),
    'calc',      c.calc,
    'disputeWindow', plb_dispute_window(p_sheet),
    'disputes',  plb_disputes(p_sheet),
    'ringFenced', fence.inr,
    'payableNow', case when (c.calc->>'amount') is null then null
                       else greatest((c.calc->>'amount')::numeric - fence.inr, 0) end,
    'result', case when r.sheet_id is null then null else jsonb_build_object(
        'achievement', r.achievement, 'payoutFactor', r.payout_factor,
        'monthsCounted', r.months_counted, 'monthlyMean', r.monthly_mean,
        'consistency', r.consistency, 'amount', r.amount_inr,
        'dataFrozenAt', r.data_frozen_at,
        'certifiedBy', (select full_name from person where id = r.certified_by),
        'certifiedAt', r.certified_at, 'publishedAt', r.published_at) end,
    'gate',      null,
    'arithmetic',
      case when (c.calc->>'amount') is null then
        case when (c.calc->>'achievement') is null then
          'Not yet computable: ' || coalesce(c.calc->>'measuresWithoutAnActual','some')
          || ' of ' || coalesce((select jsonb_array_length(k.kpis)::text), '0')
          || ' measures have no actual against a target. Achievement is the whole measure '
          || 'set or nothing -- a part of it is a different number wearing the same name.'
        else
          'Not yet computable: no month has been scored, so there is no consistency factor.'
        end
      else
        to_char(s.target_plb_inr,'FM9,99,99,999') || ' target  ×  '
        || (c.calc->>'payoutFactor') || '% payout factor (Achievement '
        || (c.calc->>'achievement') || '%)  ×  ' || (c.calc->>'consistency')
        || ' consistency (mean ' || (c.calc->>'monthlyMean') || ' of 10 over '
        || (c.calc->>'monthsCounted') || ' month(s))  =  '
        || to_char((c.calc->>'amount')::numeric,'FM9,99,99,999.00')
        || case when fence.inr > 0 then
             '.  Ring-fenced while disputed: ' || to_char(fence.inr,'FM9,99,99,999.00')
             || '.  Payable now: '
             || to_char(greatest((c.calc->>'amount')::numeric - fence.inr, 0),'FM9,99,99,999.00')
           else '' end
      end)
  from s, c, fence, k, a, m left join r on true;
$function$
;

CREATE OR REPLACE FUNCTION public.plb_sheet_for(p_actor uuid, p_sheet uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_rel text; v_out jsonb;
begin
  v_rel := plb_sheet_rel(p_actor, p_sheet);
  if v_rel is null then
    if not exists (select 1 from plb_goal_sheet where id = p_sheet) then
      return jsonb_build_object('error','no_such_sheet');
    end if;
    return jsonb_build_object('error','not_permitted',
      'reason','A goal sheet is the employee''s and the line above them.');
  end if;
  v_out := plb_sheet(p_sheet);
  if jsonb_typeof(v_out) = 'object' then
    v_out := v_out || jsonb_build_object(
      'rel', v_rel, 'mine', v_rel = 'self', 'maySet', v_rel in ('manage','admin'));
  end if;
  return v_out;
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_sheet_from_perf(p_actor uuid, p_person uuid, p_quarter date, p_plb_inr numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_sheet uuid; o jsonb; r record; v_n int := 0; v numeric; a person;
begin
  select * into a from person where id = p_actor
     and employment_status = 'ACTIVE' and superseded_by is null;

  -- Running the scheme is HR's and Business Excellence's; managing the
  -- person is their manager's. Either may issue a sheet, which is the set
  -- plb_sheet_issue has always served. Gating this on perf_may_set alone
  -- would have stopped HR doing their own job.
  if not (perf_may_set(p_actor, p_person)
          or a.app_role = 'ADMIN'
          or coalesce(a.department,'') in ('Human Resources','Business Excellence')) then
    return jsonb_build_object('error','not_permitted',
      'reason','Issuing somebody''s goal sheet belongs to the person they '
               'report to, or to HR.');
  end if;
  if p_actor = p_person then
    return jsonb_build_object('error','not_permitted',
      'reason','Nobody issues their own goal sheet.');
  end if;

  -- Issue it empty, so the registry decides the measures and the weights.
  o := plb_sheet_issue(p_actor, p_person, p_quarter, p_plb_inr,
                       '[]'::jsonb, false);
  if o->>'error' is not null then return o; end if;
  v_sheet := (o->>'sheetId')::uuid;

  for r in select gk.kpi_id from plb_goal_kpi gk where gk.sheet_id = v_sheet loop
    v := plb_quarter_from_months(p_person, r.kpi_id,
                                 date_trunc('quarter', p_quarter)::date);
    if v is not null then
      update plb_goal_kpi set target_value = v
       where sheet_id = v_sheet and kpi_id = r.kpi_id;
      v_n := v_n + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'sheetId', v_sheet, 'fromMonths', v_n,
    'note', v_n || ' quarterly target(s) read off the monthly targets that '
            'already existed, rather than typed in again. Where the months '
            'said nothing, the quarter is left blank.');
end $function$
;

