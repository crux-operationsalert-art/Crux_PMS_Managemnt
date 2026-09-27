-- The operations that maintain the model. Every one is SECURITY DEFINER and
-- does its own permission check, so a caller that skips the service is
-- refused exactly the same way -- the rule this codebase has paid twice to
-- learn, on rates and on client codes.

-- Open a month. The windows are the owner's rule: a manager sets KPIs in the
-- first week, and entries close a week after the month ends so the last few
-- working days can still be filed.
create or replace function public.perf_cycle_open(
  p_actor uuid, p_period date, p_kind text default 'MONTH')
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
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
end $fn$;

-- May this actor set KPIs for this person? Their manager, or HR, or an
-- administrator. A person cannot set their own.
create or replace function public.perf_may_set(p_actor uuid, p_person uuid)
returns boolean language sql stable security definer set search_path to 'public' as $fn$
  select exists (
    select 1 from person a
     where a.id = p_actor
       and a.employment_status = 'ACTIVE' and a.superseded_by is null
       and a.id <> p_person
       and (a.app_role = 'ADMIN'
            or coalesce(a.department,'') in ('Human Resources','Business Excellence')
            or exists (select 1 from person t where t.id = p_person and t.manager_id = a.id)));
$fn$;

-- Set one KPI on one person for one cycle.
create or replace function public.perf_assign(p_actor uuid, p_in jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare c perf_cycle; a perf_assignment; k kpi_definition; v_person uuid; v_id uuid;
begin
  v_person := (p_in->>'personId')::uuid;
  if not perf_may_set(p_actor, v_person) then
    return jsonb_build_object('error','not_permitted',
      'reason','KPIs are set by the person''s reporting manager, by HR, or by an administrator -- and never by themselves.');
  end if;

  select * into c from perf_cycle where id = (p_in->>'cycleId')::uuid;
  if c.id is null then return jsonb_build_object('error','no_such_cycle'); end if;
  if current_date > c.assign_closes
     and not exists (select 1 from person where id = p_actor and app_role = 'ADMIN') then
    return jsonb_build_object('error','window_closed',
      'reason','KPIs for ' || c.period_start || ' had to be set by ' || c.assign_closes ||
               '. An administrator can still change them, and it is recorded.');
  end if;

  if p_in ? 'kpiId' and (p_in->>'kpiId') is not null then
    select * into k from kpi_definition where id = (p_in->>'kpiId')::uuid;
  end if;

  insert into perf_assignment (cycle_id, person_id, kpi_id, name, unit, target_value,
      weight_pct, cadence_day, part_of_id, split_kind, split_ref, split_label,
      rolls_into_id, set_by, note)
  values (c.id, v_person, k.id,
          coalesce(p_in->>'name', k.name),
          coalesce(p_in->>'unit', k.unit),
          nullif(p_in->>'target','')::numeric,
          nullif(p_in->>'weight','')::numeric,
          nullif(p_in->>'cadenceDay','')::int,
          nullif(p_in->>'partOf','')::uuid,
          nullif(p_in->>'splitKind',''),
          nullif(p_in->>'splitRef','')::uuid,
          nullif(p_in->>'splitLabel',''),
          nullif(p_in->>'rollsInto','')::uuid,
          p_actor, nullif(p_in->>'note',''))
  returning id into v_id;

  if p_in ? 'cadence' and (p_in->>'cadence') is not null then
    execute format('update perf_assignment set cadence = %L where id = %L',
                   p_in->>'cadence', v_id);
  end if;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, 'PERF_KPI_SET', 'person', v_person::text, null, p_in);

  return jsonb_build_object('ok', true, 'assignmentId', v_id);
end $fn$;

-- The same measures onto many people at once. Each one goes through
-- perf_assign, so nobody gets a KPI by a route that skips the checks.
create or replace function public.perf_assign_bulk(p_actor uuid, p_in jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare p text; m jsonb; out jsonb := '[]'::jsonb; r jsonb; ok int := 0; bad int := 0;
begin
  for p in select jsonb_array_elements_text(p_in->'people') loop
    for m in select jsonb_array_elements(p_in->'measures') loop
      r := perf_assign(p_actor, m || jsonb_build_object(
             'personId', p, 'cycleId', p_in->>'cycleId'));
      if coalesce((r->>'ok')::boolean, false) then ok := ok + 1;
      else bad := bad + 1;
           out := out || jsonb_build_object('personId', p,
                     'measure', m->>'name', 'why', coalesce(r->>'reason', r->>'error'));
      end if;
    end loop;
  end loop;
  return jsonb_build_object('ok', bad = 0, 'set', ok, 'refused', bad, 'why', out,
    'note', ok || ' set' || case when bad > 0 then ', ' || bad || ' refused' else '' end || '.');
end $fn$;

-- Carry last cycle forward: the same measures, the same cadence, the same
-- roll-up, and the target left blank so it has to be thought about again.
create or replace function public.perf_carry_forward(
  p_actor uuid, p_cycle uuid, p_person uuid, p_keep_targets boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare c perf_cycle; prev perf_cycle; n int := 0; r record; v_id uuid;
begin
  if not perf_may_set(p_actor, p_person) then
    return jsonb_build_object('error','not_permitted');
  end if;
  select * into c from perf_cycle where id = p_cycle;
  if c.id is null then return jsonb_build_object('error','no_such_cycle'); end if;

  select * into prev from perf_cycle
   where period_kind = c.period_kind and period_start < c.period_start
   order by period_start desc limit 1;
  if prev.id is null then
    return jsonb_build_object('ok', true, 'copied', 0,
      'note','There is no earlier cycle to carry forward from.');
  end if;

  for r in select * from perf_assignment
            where cycle_id = prev.id and person_id = p_person and part_of_id is null
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
end $fn$;

-- File a number.
create or replace function public.perf_file(
  p_actor uuid, p_assignment uuid, p_as_of date, p_value numeric, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
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

  select value into was from perf_entry where assignment_id = p_assignment and as_of = p_as_of;

  insert into perf_entry (assignment_id, as_of, value, note, filed_by)
  values (p_assignment, p_as_of, p_value, p_note, p_actor)
  on conflict (assignment_id, as_of) do update
    set value = excluded.value, note = excluded.note,
        filed_by = excluded.filed_by, filed_at = now();

  -- a changed number is a different claim from a first one, and the trail
  -- should be able to tell them apart
  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, case when was is null then 'PERF_FILED' else 'PERF_REFILED' end,
          'perf_assignment', p_assignment::text,
          case when was is null then null else jsonb_build_object('value', was) end,
          jsonb_build_object('asOf', p_as_of, 'value', p_value, 'note', p_note));

  return jsonb_build_object('ok', true, 'value', perf_value(p_assignment),
    'note', case when was is null then 'Filed.'
                 else 'Changed from ' || was || '. The earlier figure is in the trail.' end);
end $fn$;

revoke all on function public.perf_cycle_open(uuid, date, text) from public, anon, authenticated;
revoke all on function public.perf_may_set(uuid, uuid) from public, anon, authenticated;
revoke all on function public.perf_assign(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.perf_assign_bulk(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.perf_carry_forward(uuid, uuid, uuid, boolean) from public, anon, authenticated;
revoke all on function public.perf_file(uuid, uuid, date, numeric, text) from public, anon, authenticated;
