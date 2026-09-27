-- The manager's read, and the score that falls out of it.
--
-- One call returns the whole tree: my measures, each with my own splits
-- under it, and each with the people who roll into it under that. Expanding
-- and collapsing is the screen's business; the shape is this function's.
--
-- Values are never recomputed here. Every number comes from perf_value(),
-- which owns the rate-versus-count rule, so there is exactly one place that
-- knows how a number climbs.

create or replace function public.perf_node(p_assignment uuid, p_depth int default 0)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
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
    'filings', (select count(*) from perf_entry e where e.assignment_id = a.id),
    'lastFiled', (select max(e.as_of) from perf_entry e where e.assignment_id = a.id),
    'parts', parts, 'team', team);
end $fn$;

create or replace function public.perf_tree(p_person uuid, p_cycle uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
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
       where a.person_id = p_person and a.cycle_id = p_cycle
         and a.part_of_id is null), '[]'::jsonb),
    'says', case
      when not exists (select 1 from perf_assignment a
                        where a.person_id = p_person and a.cycle_id = p_cycle)
      then 'Nothing has been set for this period yet. KPIs are set by the reporting manager, by HR, or by an administrator, and the window for '
           || c.period_start || ' ' || case when current_date <= c.assign_closes
              then 'is open until ' || c.assign_closes else 'closed on ' || c.assign_closes end || '.'
      else null end);
end $fn$;

-- The six months behind a measure, so a target is set against what actually
-- happened rather than against a feeling. Matches on the catalogue measure
-- where there is one and on the name where there is not, because a measure
-- assigned ad hoc still has a history worth seeing.
create or replace function public.perf_history(
  p_person uuid, p_name text, p_kpi uuid default null, p_months int default 6)
returns jsonb language sql stable security definer set search_path to 'public' as $fn$
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
$fn$;

-- The KPI half of the monthly score. The attribute half stays where it is,
-- in the PLB tables, and plb_compute still owns the 0.75/0.25 split.
--
-- Each ratio is capped at 150% before it is weighted, which is the scheme's
-- rule: an enormous overshoot on one measure must not buy a failure on
-- another. A measure with no target does not score and does not dilute --
-- it is left out of the weights rather than counted as zero, because a
-- target nobody set is not a target somebody missed.
create or replace function public.perf_kpi_score(p_person uuid, p_cycle uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare r record; wsum numeric := 0; w numeric := 0; n int := 0; skipped int := 0;
        rows jsonb := '[]'::jsonb; ratio numeric; v numeric;
begin
  for r in select a.* from perf_assignment a
            where a.person_id = p_person and a.cycle_id = p_cycle and a.part_of_id is null
            order by a.name loop
    v := perf_value(r.id);
    if coalesce(r.target_value, 0) = 0 or v is null then
      skipped := skipped + 1;
      -- Both can be true at once, and when they are, saying only the first
      -- sends a manager to chase a filing for a measure they never set a
      -- target on. Every reason that applies is named.
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
end $fn$;

revoke all on function public.perf_node(uuid, int) from public, anon, authenticated;
revoke all on function public.perf_tree(uuid, uuid) from public, anon, authenticated;
revoke all on function public.perf_history(uuid, text, uuid, int) from public, anon, authenticated;
revoke all on function public.perf_kpi_score(uuid, uuid) from public, anon, authenticated;
