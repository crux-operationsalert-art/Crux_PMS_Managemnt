-- =====================================================================
-- Crux baseline | 40_functions_4.sql | functions, part 4 of 4
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- Ordered by name, not by dependency. Load with check_function_bodies off.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.plb_unseated()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(x order by x->>'why', x->>'person'), '[]'::jsonb) from (
    select jsonb_build_object(
      'personId', p.id, 'person', p.full_name,
      'employeeNo', p.employee_no, 'email', p.work_email,
      'places', (select count(*) from coverage_rule c2
                  where c2.person_id = p.id and c2.role = 'BRANCH_MANAGER'
                    and c2.effective_to is null),
      'placeList', (select string_agg(n2.name, ', ' order by n2.name)
                      from coverage_rule c3 join op_node n2 on n2.id = c3.op_node_id
                     where c3.person_id = p.id and c3.role = 'BRANCH_MANAGER'
                       and c3.effective_to is null),
      'chairs', (select coalesce(string_agg(ch.title, ' / ' order by ch.title), '')
                   from chair_holder h join chair ch on ch.id = h.chair_id
                  where h.person_id = p.id and h.to_date is null),
      'why', case
        when exists (select 1 from chair_holder h join chair ch on ch.id = h.chair_id
                      where h.person_id = p.id and h.to_date is null
                        and ch.code = 'LOCATION_PARTNER')
          then 'A business partner. The scheme puts partners outside it, so this is correct and needs nothing.'
        when not exists (select 1 from chair_holder h
                          where h.person_id = p.id and h.to_date is null)
          then 'Runs a place and sits in no chair at all. Nothing measures them today.'
        else 'Sits in a chair that carries no measure set, so the scheme cannot see them.'
      end,
      'needsDecision', not exists (
        select 1 from chair_holder h join chair ch on ch.id = h.chair_id
         where h.person_id = p.id and h.to_date is null and ch.code = 'LOCATION_PARTNER')
    ) as x
    from person p
   where p.employment_status = 'ACTIVE' and p.superseded_by is null
     and exists (select 1 from coverage_rule cr
                  where cr.person_id = p.id and cr.role = 'BRANCH_MANAGER'
                    and cr.effective_to is null)
     and not exists (
       select 1 from chair_holder h join chair ch on ch.id = h.chair_id
        where h.person_id = p.id and h.to_date is null
          and exists (select 1 from kpi_definition k
                       where k.chair_id = ch.id and k.active and k.position < 100))
  ) t;
$function$
;

CREATE OR REPLACE FUNCTION public.plb_wd_after(p_from date, p_days integer, p_centre text DEFAULT NULL::text)
 RETURNS date
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare d date := p_from; n int := 0; guard int := 0;
begin
  if p_from is null or p_days is null then return null; end if;
  while n < p_days loop
    d := d + 1;
    guard := guard + 1;
    -- a calendar with every day marked a holiday would otherwise spin forever
    if guard > 400 then
      raise exception 'plb_wd_after: % working days from % never arrived', p_days, p_from;
    end if;
    if is_working_day(d, p_centre) then n := n + 1; end if;
  end loop;
  return d;
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_wd_count(p_from date, p_to date, p_centre text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p_from is null or p_to is null or p_to <= p_from then 0
    else (select count(*)::int from generate_series(p_from + 1, p_to, interval '1 day') g
           where is_working_day(g::date, p_centre))
  end;
$function$
;

CREATE OR REPLACE FUNCTION public.pms_attribute_balance(p_cycle uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select greatest(0, coalesce(sum(points), 0))
  from pms_adjustment where cycle_id = p_cycle and half = 'ATTRIBUTE' and applied;
$function$
;

CREATE OR REPLACE FUNCTION public.pms_cap_shadow()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if new.key = 'pms_cut_cap' and new.value is distinct from old.value then
    update app_setting set value = new.value where key = 'pms_monthly_cap';
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.pms_cascade_apply(p_cycle uuid, p_kind raisable_kind, p_source uuid, p_actor uuid, p_reason text)
 RETURNS TABLE(half text, points numeric, applied boolean)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  st record;
  v_down boolean := p_kind in ('ESCALATION','WARNING');
  v_size numeric;
  v_used numeric; v_over numeric; v_want numeric; v_room numeric;
  v_kc numeric := 0; v_blocked numeric := 0; v_kb numeric := 0;
  c_cap numeric := pms_cfg('pms_cut_cap', 2);
begin
  select * into st from pms_cycle_state(p_cycle);

  v_size := case p_kind
              when 'ESCALATION'   then pms_cfg('pms_esc_attr', 1)
              when 'WARNING'      then pms_cfg('pms_warn_attr', 2)
              when 'APPRECIATION' then pms_cfg('pms_appr_attr', 1)
              else                     pms_cfg('pms_idea_attr', 2)
            end;

  if v_down then
    v_used := least(st.attr, v_size);
    v_over := v_size - v_used;
    if v_over > 0 then
      v_want := (v_over / v_size) * case p_kind when 'ESCALATION'
                                      then pms_cfg('pms_esc_kpi', 0.5)
                                      else pms_cfg('pms_warn_kpi', 1) end;
      v_room := greatest(0, c_cap - st.cut);
      v_kc := least(v_want, v_room);
      v_blocked := v_want - v_kc;
    end if;

    if v_used > 0 then
      insert into pms_adjustment (cycle_id, source_kind, source_id, half, points, reason, actor_id, applied)
      values (p_cycle, p_kind, p_source, 'ATTRIBUTE', -v_used, p_reason, p_actor, true);
      half := 'ATTRIBUTE'; points := -v_used; applied := true; return next;
    end if;
    if v_kc > 0 then
      insert into pms_adjustment (cycle_id, source_kind, source_id, half, points, reason, actor_id, applied)
      values (p_cycle, p_kind, p_source, 'KPI', -v_kc,
              p_reason || ' - Attributes were already at zero', p_actor, true);
      half := 'KPI'; points := -v_kc; applied := true; return next;
    end if;
    if v_blocked > 0.001 then
      insert into pms_adjustment (cycle_id, source_kind, source_id, half, points, reason,
                                  actor_id, applied, capped, over_cap)
      values (p_cycle, p_kind, p_source, 'KPI', -v_blocked,
              p_reason || ' - beyond the ' || c_cap || '-point monthly cap; recorded and flagged to HR rather than taken off the score',
              p_actor, false, true, true);
      half := 'KPI'; points := -v_blocked; applied := false; return next;
    end if;
  else
    v_used := least(10 - st.attr, v_size);
    v_over := v_size - v_used;
    if v_over > 0 then v_kb := least(10 - st.kpi, v_over); end if;

    if v_used > 0 then
      insert into pms_adjustment (cycle_id, source_kind, source_id, half, points, reason, actor_id, applied)
      values (p_cycle, p_kind, p_source, 'ATTRIBUTE', v_used, p_reason, p_actor, true);
      half := 'ATTRIBUTE'; points := v_used; applied := true; return next;
    end if;
    if v_kb > 0 then
      insert into pms_adjustment (cycle_id, source_kind, source_id, half, points, reason, actor_id, applied)
      values (p_cycle, p_kind, p_source, 'KPI', v_kb,
              p_reason || ' - Attributes were already at ten', p_actor, true);
      half := 'KPI'; points := v_kb; applied := true; return next;
    end if;
  end if;
  return;
end $function$
;

CREATE OR REPLACE FUNCTION public.pms_cfg(p_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select nullif(regexp_replace(value, '[^0-9.]', '', 'g'), '')::numeric
       from app_setting where key = p_key),
    p_default)
$function$
;

CREATE OR REPLACE FUNCTION public.pms_cycle_score(p_cycle uuid, p_include_team boolean DEFAULT true)
 RETURNS TABLE(kpi numeric, attr numeric, final numeric, own numeric, cut numeric, held numeric, floored boolean, team_avg numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  st record;
  cy record;
  w_kpi numeric := pms_cfg('pms_wkpi', 70);
  share numeric := pms_cfg('pms_team_share', 50) / 100.0;
  floor_score numeric := pms_cfg('pms_probation', 5);
  has_base boolean;
begin
  select * into cy from pms_cycle c where c.id = p_cycle;
  if not found then return; end if;
  select * into st from pms_cycle_state(p_cycle);

  select exists (select 1 from pms_component where cycle_id = p_cycle
                  and kind in ('KPI','ATTRIBUTE')) into has_base;
  if not has_base then
    kpi := null; attr := null; final := null; own := null;
    cut := st.cut; held := st.held; floored := false; team_avg := null;
    return next; return;
  end if;

  kpi := st.kpi; own := st.attr; cut := st.cut; held := st.held;
  team_avg := null;

  if p_include_team then
    team_avg := pms_team_average(cy.person_id, cy.period);
    if team_avg is not null then
      attr := own * (1 - share) + team_avg * share;
    else
      attr := own;
    end if;
  else
    attr := own;
  end if;

  attr := greatest(0, least(10, attr));
  final := (kpi * w_kpi + attr * (100 - w_kpi)) / 100.0;

  floored := cy.on_probation and final < floor_score;
  if floored then final := floor_score; end if;
  return next;
end $function$
;

CREATE OR REPLACE FUNCTION public.pms_cycle_state(p_cycle uuid)
 RETURNS TABLE(attr numeric, kpi numeric, cut numeric, held numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare rec record;
begin
  attr := coalesce((select raw from pms_component where cycle_id = p_cycle and kind = 'ATTRIBUTE'), 0);
  kpi  := coalesce((select raw from pms_component where cycle_id = p_cycle and kind = 'KPI'), 0);
  cut  := 0;
  held := coalesce((select sum(abs(a.points)) from pms_adjustment a
                     where a.cycle_id = p_cycle and not a.applied), 0);

  for rec in select a.points as pts, a.half as hf from pms_adjustment a
              where a.cycle_id = p_cycle and a.applied
              order by a.at, a.id loop
    if rec.hf = 'ATTRIBUTE' then
      attr := greatest(0, least(10, attr + rec.pts));
    else
      if rec.pts < 0 then cut := cut - rec.pts; end if;
      kpi := greatest(0, least(10, kpi + rec.pts));
    end if;
  end loop;
  return next;
end $function$
;

CREATE OR REPLACE FUNCTION public.pms_team_average(p_person uuid, p_period date)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with recursive my_chair as (
    select ch.chair_id from chair_holder ch
     where ch.person_id = p_person and ch.to_date is null
  ), below as (
    select c.id from chair c join my_chair m on c.parent_id = m.chair_id
    union all
    select c.id from chair c join below b on c.parent_id = b.id
  ), ppl as (
    select distinct h.person_id from chair_holder h
      join below b on b.id = h.chair_id
     where h.to_date is null
  )
  select avg(s.final)
    from ppl p
    join pms_cycle cy on cy.person_id = p.person_id and cy.period = p_period
    cross join lateral pms_cycle_score(cy.id, false) s
$function$
;

CREATE OR REPLACE FUNCTION public.pms_weighting_for(p_person uuid, p_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare w pms_weighting; v_next date; v_scope text;
begin
  select * into w from pms_weighting
   where person_id = p_person and effective_from <= p_on
   order by effective_from desc limit 1;
  if w.id is not null then v_scope := 'you'; end if;

  if w.id is null then
    select pw.* into w from pms_weighting pw
     where pw.chair_id is not null and pw.effective_from <= p_on
       and exists (select 1 from chair_holder h
                    where h.person_id = p_person and h.chair_id = pw.chair_id
                      and (h.to_date is null or h.to_date >= p_on))
     order by pw.effective_from desc limit 1;
    if w.id is not null then v_scope := 'your chair'; end if;
  end if;

  if w.id is null then
    select * into w from pms_weighting
     where scope_all and effective_from <= p_on
     order by effective_from desc limit 1;
    if w.id is not null then v_scope := 'everybody'; end if;
  end if;

  if w.id is not null then
    return jsonb_build_object(
      'applies', true, 'scope', v_scope,
      'kpiPercent', w.kpi_percent, 'attrPercent', w.attr_percent,
      'effectiveFrom', w.effective_from,
      'note', 'A monthly score is ' || w.kpi_percent || '% of the KPI score and '
              || w.attr_percent || '% of the Attribute score, both out of ten.');
  end if;

  select min(pw2.effective_from) into v_next from pms_weighting pw2
   where pw2.effective_from > p_on
     and (pw2.scope_all or pw2.person_id = p_person
          or exists (select 1 from chair_holder h
                      where h.person_id = p_person and h.chair_id = pw2.chair_id));

  return jsonb_build_object(
    'applies', false, 'scope', null,
    'kpiPercent', null, 'attrPercent', null,
    'startsOn', v_next,
    'note', case when v_next is null
                 then 'No KPI/Attribute split has been set, so no monthly score can be worked out. '
                      || 'Admin or HR sets one on the Performance screen.'
                 else 'The scheme starts on ' || to_char(v_next, 'FMDD Month YYYY')
                      || '. Nothing is scored before then.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.pms_window_may_open(p_person uuid, p_period date)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select not exists (
    select 1
    from chair_holder ch
    join chair c on c.id = ch.chair_id
    join chair_holder sub_h on true
    join chair sub on sub.id = sub_h.chair_id and sub.parent_id = c.id
    left join pms_cycle pc on pc.person_id = sub_h.person_id and pc.period = p_period
    where ch.person_id = p_person and ch.to_date is null and sub_h.to_date is null
      and coalesce(pc.state, 'PENDING') <> 'CLOSED'
  )
  or not (select coalesce(value, 'Yes') like 'Y%' from app_setting where key = 'pms_bottom_up');
$function$
;

CREATE OR REPLACE FUNCTION public.raise_escalation(p_assignment uuid, p_level integer, p_trigger text, p_actor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a assignment%rowtype; si sla_instance%rowtype; v_route jsonb;
  v_key text; v_id uuid; v_name text;
begin
  select * into a from assignment where id = p_assignment;
  if not found then return jsonb_build_object('error','no_such_assignment'); end if;
  if a.current_state in ('CLOSED','CANCELLED') then
    return jsonb_build_object('skipped','assignment_finished');
  end if;

  v_key := encode(extensions.digest(concat_ws('|', p_assignment::text,
             a.breach_cycle_no::text, p_level::text, p_trigger), 'sha256'), 'hex');

  v_route := ogl_escalation_route(p_assignment, p_level);

  insert into escalation_instance (assignment_id, breach_cycle_no, escalation_level,
    trigger_code, idempotency_key, resolved_to_id, resolved_chair_id,
    route_trace, fallback_used, fallback_reason)
  values (p_assignment, a.breach_cycle_no, p_level, p_trigger, v_key,
    nullif(v_route->>'person_id','')::uuid, nullif(v_route->>'chair_id','')::uuid,
    coalesce(v_route->'trace','[]'::jsonb),
    coalesce((v_route->>'fallback_used')::boolean, false),
    v_route->>'fallback_reason')
  on conflict (idempotency_key) do nothing
  returning id into v_id;

  -- the same sweep running twice raises one escalation
  if v_id is null then
    return jsonb_build_object('duplicate', true, 'key', v_key);
  end if;

  si := ogl_live_sla(p_assignment);
  select full_name into v_name from person where id = a.allocated_to_id;

  insert into assignment_event (assignment_id, event_type, actor_id, is_system, payload)
  values (p_assignment, 'ESCALATED', p_actor, p_actor is null,
          jsonb_build_object('level', p_level, 'trigger', p_trigger,
                             'to', v_route->>'person_id', 'escalation', v_id));

  perform ogl_notify(p_assignment, nullif(v_route->>'person_id','')::uuid,
    'ESCALATION_L' || p_level,
    'escalated to level ' || p_level,
    'Assignment ' || coalesce(a.ref,'') || ' has been escalated to level ' || p_level ||
    ' because of ' || replace(lower(p_trigger), '_', ' ') || '.' || E'\n' ||
    'Allocated to: ' || coalesce(v_name, 'nobody yet') || '.' ||
    case when si.id is not null then E'\n' ||
      'Due ' || to_char(ogl_ts(coalesce(si.extended_to, si.due_at)), 'DD Mon at HH24:MI') || ' IST, ' ||
      'status ' || si.sla_status || '.' else '' end,
    v_key);

  -- a gap in configuration must never be the reason nobody hears about a
  -- breach, and must never stay invisible either
  if coalesce((v_route->>'fallback_used')::boolean, false) then
    insert into assignment_event (assignment_id, event_type, is_system, payload)
    values (p_assignment, 'ESCALATION_FALLBACK_USED', true,
            jsonb_build_object('level', p_level, 'reason', v_route->>'fallback_reason'));

    perform mail_enqueue('CONFIG_GAP', p.work_email,
      'Crux - the escalation matrix has a gap',
      v_route->>'fallback_reason' || E'\n\n' ||
      'The escalation was delivered anyway, by walking up the line from the ' ||
      'assignee. Adding the missing row will route the next one properly.',
      'assignment', p_assignment, null, now(),
      'configgap:' || coalesce(a.to_location_id::text,'-') || ':' || p_level || ':' || current_date::text)
      from person p
     where p.app_role = 'ADMIN' and p.employment_status = 'ACTIVE' and p.superseded_by is null;
  end if;

  return jsonb_build_object('id', v_id, 'level', p_level, 'trigger', p_trigger,
    'to', v_route->>'person_id', 'fallback_used', v_route->>'fallback_used');
end $function$
;

CREATE OR REPLACE FUNCTION public.recipient_reconciliation()
 RETURNS TABLE(verdict text, detail text)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_old       int;
  v_old_ok    int;
  v_new       int;
  v_missing   int;
  v_extra     int;
  v_detail    text;
begin
  select count(*) into v_old from stg.email_log;

  if v_old = 0 then
    delete from cutover_check where check_name = 'M-01 recipient reconciliation';
    insert into cutover_check (check_name, expectation, outcome, detail, result)
    values ('M-01 recipient reconciliation',
            'every recipient the old system reached is reachable by the new one',
            'not attempted',
            'stg.email_log is empty. Load the EMAIL_LOG staging files first; '
            || 'the check then reports for itself.', 'FAIL');
    return query select 'not attempted'::text,
      'stg.email_log is empty — load it and run this again.'::text;
    return;
  end if;

  -- The old log's successful sends, by recipient.
  create temp table _old_recip on commit drop as
  select distinct lower(btrim(e.recipient)) as addr
  from stg.email_log e
  where stg.present(e.recipient)
    and upper(coalesce(e.state, '')) not in ('FAILED', 'BOUNCED', 'ABANDONED');
  select count(*) into v_old_ok from _old_recip;

  -- Every address the new system can reach today: a matrix contact on a
  -- dispatchable branch, a branch contact, or a live person.
  create temp table _new_recip on commit drop as
  select distinct lower(btrim(x.addr)) as addr from (
    select m.email as addr from matrix_contact m
     where coalesce(btrim(m.email), '') <> ''
    union all
    select bc.email from branch_contact bc
     where coalesce(btrim(bc.email), '') <> ''
    union all
    select p.work_email from person p
     where p.superseded_by is null and p.employment_status = 'ACTIVE'
       and coalesce(btrim(p.work_email), '') <> ''
  ) x;
  select count(*) into v_new from _new_recip;

  select count(*) into v_missing
  from _old_recip o where not exists (select 1 from _new_recip n where n.addr = o.addr);

  select count(*) into v_extra
  from _new_recip n where not exists (select 1 from _old_recip o where o.addr = n.addr);

  v_detail := format(
    '%s rows in the old log, %s distinct recipients it reached. The new system holds %s '
    || 'addresses. %s of the old recipients are unreachable now; %s addresses are new '
    || '(expected — the matrix grew). Unreachable is the number that matters.',
    v_old, v_old_ok, v_new, v_missing, v_extra);

  delete from cutover_check where check_name = 'M-01 recipient reconciliation';
  insert into cutover_check (check_name, expectation, outcome, detail, result)
  values ('M-01 recipient reconciliation',
          'no recipient the old system reached is unreachable now',
          v_missing || ' unreachable of ' || v_old_ok,
          v_detail,
          case when v_missing = 0 then 'PASS' else 'FAIL' end);

  return query select
    case when v_missing = 0 then 'PASS' else 'FAIL' end::text,
    v_detail::text;
end $function$
;

CREATE OR REPLACE FUNCTION public.request_action(p_actor uuid, p_task uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t request_task; rz raisable; a person%rowtype; late boolean;
begin
  select * into t from request_task where id = p_task;
  if t.id is null then return jsonb_build_object('error','no_such_task'); end if;
  select * into rz from raisable where id = t.raisable_id;
  select * into a from person where id = p_actor;

  if t.responder_id <> p_actor
     and not exists (select 1 from person where id = p_actor and app_role = 'ADMIN') then
    return jsonb_build_object('error','not_yours',
      'reason','That request is on somebody else. Actioning it for them would '
            || 'clear the record without clearing the work.');
  end if;
  if t.actioned_at is not null then
    return jsonb_build_object('ok', true,
      'note','That one was already actioned on ' || to_char(t.actioned_at, 'FMDD FMMon') || '.');
  end if;

  late := now() > t.due_at;
  update request_task set actioned_at = now() where id = p_task;

  insert into notification (person_id, at, kind, text, entity_type, entity_id)
  values (rz.raised_by, now(), 'REQUEST_ACTIONED',
          a.full_name || ' has answered ' || rz.ref
          || coalesce(': ' || nullif(btrim(coalesce(p_note,'')),''), '.'),
          'raisable', rz.id);

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, 'REQUEST_ACTIONED', 'raisable', rz.ref,
          jsonb_build_object('dueAt', t.due_at, 'strikes', t.strike_count),
          jsonb_build_object('note', nullif(btrim(coalesce(p_note,'')),''), 'late', late));

  return jsonb_build_object('ok', true, 'late', late,
    'note', case when late
      then 'Actioned, and it was past its due time. ' || t.strike_count
           || ' strike(s) are already recorded against it; actioning stops any more.'
      else 'Actioned, inside the time. The person who raised it has been told.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.request_raise(p_actor uuid, p_in jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_dept text; v_type text; v_body text; v_to uuid; v_ref text;
  v_id uuid; v_task uuid; v_due timestamptz; a person%rowtype; b person%rowtype;
begin
  select * into a from person where id = p_actor;
  if a.id is null then return jsonb_build_object('error','no_such_actor'); end if;

  v_dept := btrim(coalesce(p_in->>'department',''));
  v_type := btrim(coalesce(p_in->>'type',''));
  v_body := btrim(coalesce(p_in->>'body',''));

  if v_dept = '' or v_body = '' then
    return jsonb_build_object('error','incomplete',
      'reason','A request names the department it is for and says what you need. '
            || 'Without both it is a note to nobody.');
  end if;

  v_to := request_responder(v_dept, p_actor);
  if v_to is null then
    if exists (select 1 from person where coalesce(department,'') = v_dept
                 and employment_status = 'ACTIVE' and superseded_by is null) then
      return jsonb_build_object('error','only_you',
        'reason','You are the only active person in ' || v_dept ||
                 ', so there is nobody there to send this to.');
    end if;
    return jsonb_build_object('error','nobody_there',
      'reason','Nobody active is recorded in ' || v_dept ||
               '. Ask HR to seat somebody there before raising against it.');
  end if;
  select * into b from person where id = v_to;

  v_due := working_hours_after(now(), 6::numeric, person_centre(v_to));
  v_ref := next_ref('REQ');

  insert into raisable (kind, ref, raised_by, department, body, created_at)
  values ('ASSISTANCE', v_ref, p_actor, v_dept,
          case when v_type = '' then v_body else v_type || ' · ' || v_body end,
          now())
  returning id into v_id;

  insert into request_task (raisable_id, responder_id, due_at)
  values (v_id, v_to, v_due) returning id into v_task;

  insert into notification (person_id, at, kind, text, entity_type, entity_id)
  values (v_to, now(), 'REQUEST_RAISED',
          a.full_name || ' needs something from ' || v_dept || ': ' || v_body,
          'raisable', v_id);

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, 'REQUEST_RAISED', 'raisable', v_ref, null,
          jsonb_build_object('department', v_dept, 'type', nullif(v_type,''),
                             'responder', b.full_name, 'dueAt', v_due));

  return jsonb_build_object('ok', true, 'ref', v_ref, 'taskId', v_task,
    'responder', b.full_name, 'dueAt', v_due,
    'note', 'Sent to ' || b.full_name || ' in ' || v_dept || '. It is a task on '
         || 'them now, due ' || to_char(v_due, 'FMDD FMMon HH24:MI')
         || '. An unactioned request counts against the responder, not against you.');
end $function$
;

CREATE OR REPLACE FUNCTION public.request_responder(p_dept text, p_not uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.id
    from person p
    left join chair_holder h on h.person_id = p.id and h.to_date is null
    left join chair ch on ch.id = h.chair_id
   where p.employment_status = 'ACTIVE' and p.superseded_by is null
     and coalesce(p.department,'') = p_dept
     and (p_not is null or p.id <> p_not)
   order by
     case when ch.title ~* 'head|chief|vice president' then 0 else 1 end,
     (select count(*) from request_task rt
       where rt.responder_id = p.id and rt.actioned_at is null),
     p.full_name
   limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.request_strike_sweep(p_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_run uuid; r record; n int := 0; told int := 0;
begin
  insert into job_run (job_key, started_at, state)
  values ('REQUEST_STRIKES', now(), 'RUNNING') returning id into v_run;

  for r in
    select t.id, t.strike_count, t.due_at, t.responder_id,
           rz.ref, rz.department, rz.body,
           p.full_name, p.manager_id, m.full_name as manager
      from request_task t
      join raisable rz on rz.id = t.raisable_id
      join person p on p.id = t.responder_id
      left join person m on m.id = p.manager_id
     where t.actioned_at is null
       and t.due_at < now()
       and t.strike_count < 3
  loop
    update request_task set strike_count = strike_count + 1 where id = r.id;
    n := n + 1;

    insert into notification (person_id, at, kind, text, entity_type, entity_id)
    values (r.responder_id, now(), 'REQUEST_STRIKE',
            'Strike ' || (r.strike_count + 1) || ' of 3 on ' || r.ref
            || ', which was due ' || to_char(r.due_at, 'FMDD FMMon HH24:MI')
            || '. ' || r.body, 'request_task', r.id);

    if r.strike_count + 1 >= 2 and r.manager_id is not null then
      insert into notification (person_id, at, kind, text, entity_type, entity_id)
      values (r.manager_id, now(), 'REQUEST_STRIKE',
              r.full_name || ' is at strike ' || (r.strike_count + 1) || ' of 3 on '
              || r.ref || ' (' || r.department || ').', 'request_task', r.id);
      told := told + 1;
    end if;

    insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
    values (null, 'REQUEST_STRIKE', 'raisable', r.ref,
            jsonb_build_object('strikes', r.strike_count),
            jsonb_build_object('strikes', r.strike_count + 1, 'responder', r.full_name));
  end loop;

  update job_run set finished_at = now(), state = 'DONE',
         counts = jsonb_build_object('day', p_on, 'strikes', n, 'managers_told', told)
   where id = v_run;

  return jsonb_build_object('strikes', n, 'managersTold', told,
    'note', case when n = 0 then 'Every request was answered in time.'
                 else n || ' strike(s) recorded.' end);
exception when others then
  update job_run set finished_at = now(), state = 'FAILED', error = sqlerrm where id = v_run;
  raise;
end $function$
;

CREATE OR REPLACE FUNCTION public.sample_count()
 RETURNS TABLE(table_name text, rows bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select s.table_name, count(*) from sample_row s
  group by s.table_name order by s.table_name
$function$
;

CREATE OR REPLACE FUNCTION public.sample_purge()
 RETURNS TABLE(table_name text, removed bigint)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  r record; n bigint; grew boolean; pass int; total int;
begin
  create temp table if not exists doomed(tbl text, id text, primary key (tbl, id)) on commit drop;
  delete from doomed;
  insert into doomed(tbl, id) select s.table_name, s.row_id::text from sample_row s on conflict do nothing;

  create temp table if not exists purge_report(tbl text, removed bigint) on commit drop;
  delete from purge_report;

  for pass in 1..12 loop
    grew := false;
    for r in
      select c.conrelid::regclass::text as tbl, a.attname as col,
             replace(c.confrelid::regclass::text,'"','') as ref,
             exists (select 1 from pg_attribute ia
                      where ia.attrelid = c.conrelid and ia.attname = 'id' and ia.attnum > 0) as has_id
      from pg_constraint c
      join unnest(c.conkey) with ordinality k(attnum, ord) on true
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
      where c.contype = 'f' and a.attnotnull
        and replace(c.confrelid::regclass::text,'"','') in (select distinct tbl from doomed)
    loop
      if r.has_id then
        execute format(
          'insert into doomed(tbl,id) select %L, t.id::text from %s t
             where t.%I::text in (select id from doomed where tbl = %L) on conflict do nothing',
          replace(r.tbl,'"',''), r.tbl, r.col, r.ref);
        get diagnostics n = row_count;
        if n > 0 then grew := true; end if;
      end if;
    end loop;
    exit when not grew;
  end loop;

  for r in
    select c.conrelid::regclass::text as tbl, a.attname as col,
           replace(c.confrelid::regclass::text,'"','') as ref,
           exists (select 1 from pg_attribute ia
                    where ia.attrelid = c.conrelid and ia.attname = 'id' and ia.attnum > 0) as has_id,
           (c.conrelid = c.confrelid) as self_ref
    from pg_constraint c
    join unnest(c.conkey) with ordinality k(attnum, ord) on true
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
    where c.contype = 'f' and not a.attnotnull
      and replace(c.confrelid::regclass::text,'"','') in (select distinct tbl from doomed)
  loop
    begin
      if r.has_id and not r.self_ref then
        execute format(
          'update %s t set %I = null where t.%I::text in (select id from doomed where tbl = %L)
             and t.id::text not in (select id from doomed where tbl = %L)',
          r.tbl, r.col, r.col, r.ref, replace(r.tbl,'"',''));
      else
        execute format('update %s t set %I = null where t.%I::text in (select id from doomed where tbl = %L)',
                       r.tbl, r.col, r.col, r.ref);
      end if;
    exception when others then null;
    end;
  end loop;

  for pass in 1..12 loop
    total := 0;
    for r in
      select c.conrelid::regclass::text as tbl, a.attname as col,
             replace(c.confrelid::regclass::text,'"','') as ref
      from pg_constraint c
      join unnest(c.conkey) with ordinality k(attnum, ord) on true
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
      where c.contype = 'f' and a.attnotnull
        and not exists (select 1 from pg_attribute ia
                         where ia.attrelid = c.conrelid and ia.attname = 'id' and ia.attnum > 0)
        and replace(c.confrelid::regclass::text,'"','') in (select distinct tbl from doomed)
    loop
      begin
        execute format('delete from %s t where t.%I::text in (select id from doomed where tbl = %L)',
                       r.tbl, r.col, r.ref);
        get diagnostics n = row_count; total := total + n;
      exception when others then null;
      end;
    end loop;

    for r in select distinct d.tbl as t from doomed d loop
      begin
        execute format('delete from %I where id::text in (select id from doomed where tbl = %L)', r.t, r.t);
        get diagnostics n = row_count;
        if n > 0 then
          total := total + n;
          insert into purge_report values (r.t, n);
          execute format('delete from doomed where tbl = %L', r.t);
        end if;
      exception when others then null;
      end;
    end loop;
    exit when total = 0;
  end loop;

  delete from sample_row s
  where not exists (select 1 from doomed d where d.tbl = s.table_name and d.id = s.row_id::text);

  for r in select p.tbl as t, sum(p.removed) as c from purge_report p group by 1 order by 1 loop
    table_name := r.t; removed := r.c; return next;
  end loop;
end $function$
;

CREATE OR REPLACE FUNCTION public.sample_seed(p_actor uuid DEFAULT NULL::uuid)
 RETURNS TABLE(table_name text, rows bigint)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  d_ops uuid; d_hr uuid;
  c_md uuid; c_ops uuid; c_rm uuid; c_bm uuid; c_ex uuid;
  p_md uuid; p_ops uuid; p_rm uuid; p_bm uuid; p_ex1 uuid; p_ex2 uuid;
  cl_a uuid; cl_b uuid;
  br_1 uuid; br_2 uuid; br_3 uuid;
  g_city uuid; g_state uuid;
  cat uuid; case_1 uuid;
  k_bm uuid; k_ex uuid;
  cyc uuid; lvl int;
  period date := date_trunc('month', current_date)::date;
begin
  if exists (select 1 from sample_row) then
    raise exception 'sample data is already loaded; purge it first';
  end if;

  select id into g_city from geo_node where level = 'CITY' order by name limit 1;
  select id into g_state from geo_node where level = 'STATE' order by name limit 1;

  insert into person (full_name, employee_no, work_email, mobile, department, app_role, source_ref)
  values ('Sample: Meera Nair','SMP-0001','sample.md@example.invalid','9000000001','MD Office','ADMIN','SAMPLE')
  returning id into p_md;
  insert into person (full_name, employee_no, work_email, mobile, department, app_role, manager_id, source_ref)
  values ('Sample: Arjun Rao','SMP-0002','sample.ops@example.invalid','9000000002','Operations','MANAGER',p_md,'SAMPLE')
  returning id into p_ops;
  insert into person (full_name, employee_no, work_email, mobile, department, app_role, manager_id, source_ref)
  values ('Sample: Kavita Iyer','SMP-0003','sample.rm@example.invalid','9000000003','Operations','MANAGER',p_ops,'SAMPLE')
  returning id into p_rm;
  insert into person (full_name, employee_no, work_email, mobile, department, app_role, manager_id, source_ref)
  values ('Sample: Rohit Sharma','SMP-0004','sample.bm@example.invalid','9000000004','Operations','MANAGER',p_rm,'SAMPLE')
  returning id into p_bm;
  insert into person (full_name, employee_no, work_email, mobile, department, app_role, manager_id, source_ref)
  values ('Sample: Neha Joshi','SMP-0005','sample.ex1@example.invalid','9000000005','Operations','VIEWER',p_bm,'SAMPLE')
  returning id into p_ex1;
  insert into person (full_name, employee_no, work_email, mobile, department, app_role, manager_id, employee_type, source_ref)
  values ('Sample: Imran Qureshi','SMP-0006','sample.ex2@example.invalid','9000000006','Operations','VIEWER',p_bm,'PARTNER','SAMPLE')
  returning id into p_ex2;
  perform sample_tag('person', x) from unnest(array[p_md,p_ops,p_rm,p_bm,p_ex1,p_ex2]) x;

  insert into desk (name, primary_person_id) values ('Sample Operations desk', p_ops) returning id into d_ops;
  insert into desk (name, primary_person_id) values ('Sample HR desk', p_md) returning id into d_hr;
  perform sample_tag('desk', x) from unnest(array[d_ops,d_hr]) x;

  insert into chair (code,title,level,desk_id) values ('SMP_MD','Sample Managing Director','board',d_hr) returning id into c_md;
  insert into chair (code,title,level,desk_id,parent_id) values ('SMP_OPS','Sample Operations Head','function',d_ops,c_md) returning id into c_ops;
  insert into chair (code,title,level,desk_id,parent_id) values ('SMP_RM','Sample Regional Manager','region',d_ops,c_ops) returning id into c_rm;
  insert into chair (code,title,level,desk_id,parent_id,reports_daily) values ('SMP_BM','Sample Branch Manager','branch',d_ops,c_rm,true) returning id into c_bm;
  insert into chair (code,title,level,desk_id,parent_id,reports_daily) values ('SMP_EX','Sample Executive','executive',d_ops,c_bm,true) returning id into c_ex;
  perform sample_tag('chair', x) from unnest(array[c_md,c_ops,c_rm,c_bm,c_ex]) x;

  insert into chair_holder (chair_id,person_id,is_primary) values
   (c_md,p_md,true),(c_ops,p_ops,true),(c_rm,p_rm,true),(c_bm,p_bm,true),(c_ex,p_ex1,true);
  perform sample_tag('chair_holder', id) from chair_holder
   where chair_id in (c_md,c_ops,c_rm,c_bm,c_ex);

  insert into client (code,name,source_ref) values ('SMP-A','Sample Client Alpha','SAMPLE') returning id into cl_a;
  insert into client (code,name,source_ref) values ('SMP-B','Sample Client Beta','SAMPLE') returning id into cl_b;
  perform sample_tag('client', x) from unnest(array[cl_a,cl_b]) x;

  insert into branch (client_id,code,name,geo_node_id,source_ref)
  values (cl_a,'SMP-A-001','Sample Branch One',g_city,'SAMPLE') returning id into br_1;
  insert into branch (client_id,code,name,geo_node_id,source_ref)
  values (cl_a,'SMP-A-002','Sample Branch Two',g_city,'SAMPLE') returning id into br_2;
  insert into branch (client_id,code,name,geo_node_id,source_ref)
  values (cl_b,'SMP-B-001','Sample Branch Three',g_city,'SAMPLE') returning id into br_3;
  perform sample_tag('branch', x) from unnest(array[br_1,br_2,br_3]) x;

  for lvl in 1..5 loop
    insert into matrix_contact (client_id,branch_id,level,level_name,name,email,mobile,source_ref)
    values (cl_a, br_1, lvl, 'Level ' || lvl, 'Sample Contact L' || lvl,
            'sample.l' || lvl || '@example.invalid', '900000010' || lvl, 'SAMPLE');
  end loop;
  perform sample_tag('matrix_contact', id) from matrix_contact where branch_id = br_1;

  insert into coverage_rule (person_id, role, scope_type, client_id, source_ref)
  values (p_bm,'BRANCH_MANAGER','CLIENT',cl_a,'SAMPLE');
  insert into coverage_rule (person_id, role, scope_type, client_id, source_ref)
  values (p_rm,'ZONAL_MANAGER','CLIENT',cl_b,'SAMPLE');
  perform sample_tag('coverage_rule', id) from coverage_rule where source_ref = 'SAMPLE';

  insert into category (name, desk_id, chase_hours) values ('Sample: Service quality', d_ops, 24)
  returning id into cat;
  perform sample_tag('category', cat);

  insert into "case" (ref,client_id,branch_id,category_id,raised_by,against_person_id,
                      description,desk_id,status,next_chase_at,source_ref)
  values ('SMP-ESC-0001',cl_a,br_1,cat,p_rm,p_bm,
          'Sample escalation: response not received within the agreed window.',
          d_ops,'OPEN', working_hours_after(now(), 24),'SAMPLE')
  returning id into case_1;
  perform sample_tag('case', case_1);
  insert into escalation_party (case_id,person_id,part) values (case_1,p_rm,'RAISER'),(case_1,p_bm,'RESPONDENT');

  insert into kpi_definition (chair_id,name,unit) values (c_bm,'Sample: Cases closed','count') returning id into k_bm;
  insert into kpi_definition (chair_id,name,unit) values (c_ex,'Sample: Verifications completed','count') returning id into k_ex;
  perform sample_tag('kpi_definition', x) from unnest(array[k_bm,k_ex]) x;

  insert into kpi_target (kpi_id,person_id,period,target_value,set_by)
  values (k_bm,p_bm,to_char(period,'YYYY-MM'),120,p_rm),
         (k_ex,p_ex1,to_char(period,'YYYY-MM'),300,p_bm);
  perform sample_tag('kpi_target', id) from kpi_target where kpi_id in (k_bm,k_ex);

  insert into pms_cycle (person_id, chair_id, period, state) values (p_bm,c_bm,period,'PENDING')
  returning id into cyc;
  perform sample_tag('pms_cycle', cyc);
  insert into pms_component (cycle_id,kind,raw,weight_pct) values (cyc,'KPI',7,70),(cyc,'ATTRIBUTE',6,30);
  perform sample_tag('pms_component', id) from pms_component where cycle_id = cyc;

  insert into pms_cycle (person_id, chair_id, period, state) values (p_ex1,c_ex,period,'PENDING')
  returning id into cyc;
  perform sample_tag('pms_cycle', cyc);
  insert into pms_component (cycle_id,kind,raw,weight_pct) values (cyc,'KPI',8,70),(cyc,'ATTRIBUTE',7,30);
  perform sample_tag('pms_component', id) from pms_component where cycle_id = cyc;

  insert into rate (code,client_id,scope,value,effective_from,reason,created_by)
  values ('SMP-RATE-001',cl_a,'client',100.00,date_trunc('year',current_date)::date,'Sample placeholder rate',p_actor),
         ('SMP-RATE-002',cl_b,'client',150.00,date_trunc('year',current_date)::date,'Sample placeholder rate',p_actor);
  perform sample_tag('rate', id) from rate where code like 'SMP-RATE-%';

  insert into penalty_rule (code,what,plain_language,applies_to,frequency,cutoff_spec,amount,recovered_by,created_by)
  values ('SMP-P-01','Daily count not filed','File your daily numbers before the day closes at 23:59.',
          'ALL','DAILY','23:59 same day',200,'HR',p_actor);
  perform sample_tag('penalty_rule', id) from penalty_rule where code = 'SMP-P-01';

  insert into business_record (period,business_date,client_id,geo_node_id,owner_id,mtd,day10,target,revenue,source_ref)
  values (to_char(period,'YYYY-MM'),current_date,cl_a,g_city,p_bm,820,260,1000,82000,'SAMPLE'),
         (to_char(period,'YYYY-MM'),current_date,cl_b,g_city,p_rm,410,150,600,61500,'SAMPLE');
  perform sample_tag('business_record', id) from business_record where source_ref = 'SAMPLE';

  return query select * from sample_count();
end $function$
;

CREATE OR REPLACE FUNCTION public.sample_tag(p_table text, p_id uuid)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'public'
AS $function$
  insert into sample_row (table_name, row_id) values (p_table, p_id)
  on conflict do nothing
  returning row_id
$function$
;

CREATE OR REPLACE FUNCTION public.task_assign(p_actor uuid, p_in jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_title   text := nullif(btrim(p_in->>'title'), '');
  v_detail  text := nullif(btrim(p_in->>'detail'), '');
  v_due     date := nullif(p_in->>'dueOn','')::date;
  v_weight  numeric := nullif(p_in->>'attributeWeight','')::numeric;
  v_period  text := coalesce(nullif(p_in->>'period',''), to_char(coalesce(v_due, current_date), 'YYYY-MM'));
  v_admin   boolean;
  v_made    int := 0;
  v_refused text[] := '{}';
  r record;
begin
  if p_actor is null then return jsonb_build_object('error','no_actor'); end if;
  if v_title is null then return jsonb_build_object('error','no_title',
      'reason','A task needs a sentence saying what is being asked for.'); end if;
  if v_weight is not null and (v_weight < 0 or v_weight > 2) then
    return jsonb_build_object('error','bad_weight',
      'reason','An attribute is worth 0 to 2 points. A task cannot be worth more than the attribute it feeds.');
  end if;

  select coalesce(p.app_role = 'ADMIN', false) into v_admin from person p where p.id = p_actor;

  create temp table if not exists _mine (person_id uuid primary key) on commit drop;
  delete from _mine;
  insert into _mine select person_id from kpi_subtree_people(p_actor) on conflict do nothing;

  for r in
    select distinct pe.id as person_id, pe.full_name
      from person pe
     where pe.employment_status = 'ACTIVE' and pe.superseded_by is null
       and coalesce(pe.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
       and (
            (p_in ? 'people'
               and pe.id in (select (jsonb_array_elements_text(p_in->'people'))::uuid))
         or (nullif(p_in->>'chair','') is not null and exists (
               select 1 from chair_holder h
                where h.person_id = pe.id and h.chair_id = (p_in->>'chair')::uuid
                  and (h.to_date is null or h.to_date >= current_date)))
         or (nullif(p_in->>'department','') is not null and pe.department = p_in->>'department')
         or (coalesce((p_in->>'allReports')::boolean, false)
               and pe.id in (select person_id from _mine))
       )
     order by pe.full_name
  loop
    if not v_admin
       and r.person_id <> p_actor
       and r.person_id not in (select person_id from _mine) then
      v_refused := v_refused || r.full_name;
      continue;
    end if;
    insert into task (person_id, assigned_by, title, detail, due_on, period,
                      status, attribute_weight)
    values (r.person_id, p_actor, v_title, v_detail, v_due, v_period, 'OPEN', v_weight);
    v_made := v_made + 1;
  end loop;

  if v_made = 0 and array_length(v_refused,1) is null then
    return jsonb_build_object('error','nobody',
      'reason','That names nobody who is still here.');
  end if;

  return jsonb_build_object('created', v_made, 'period', v_period,
    'refused', to_jsonb(v_refused),
    'note', case when array_length(v_refused,1) is null then null
                 else 'A task can only be set for somebody who reports to you.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.task_cancel(p_actor uuid, p_task uuid, p_why text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t task;
begin
  select * into t from task where id = p_task;
  if t.id is null then return jsonb_build_object('error','no_such_task'); end if;
  if p_actor <> t.assigned_by
     and not exists (select 1 from person p where p.id = p_actor and p.app_role = 'ADMIN') then
    return jsonb_build_object('error','not_yours',
      'reason','Only whoever set a task can call it off.');
  end if;
  update task set status = 'CANCELLED', outcome = nullif(btrim(p_why),''), closed_at = now()
   where id = p_task and status = 'OPEN';
  return jsonb_build_object('cancelled', found);
end $function$
;

CREATE OR REPLACE FUNCTION public.task_close(p_actor uuid, p_task uuid, p_outcome text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t task; v_state text;
begin
  select * into t from task where id = p_task;
  if t.id is null then return jsonb_build_object('error','no_such_task'); end if;
  if t.status <> 'OPEN' then
    return jsonb_build_object('error','already_closed', 'status', t.status);
  end if;
  if p_actor <> t.person_id and p_actor <> t.assigned_by
     and not exists (select 1 from person p where p.id = p_actor and p.app_role = 'ADMIN') then
    return jsonb_build_object('error','not_yours',
      'reason','A task is closed by the person it was set for, or by whoever set it.');
  end if;

  v_state := case when t.due_on is null or current_date <= t.due_on then 'DONE' else 'LATE' end;

  update task set status = v_state, outcome = nullif(btrim(p_outcome),''), closed_at = now()
   where id = p_task;

  return jsonb_build_object('status', v_state, 'dueOn', t.due_on, 'closedOn', current_date);
end $function$
;

CREATE OR REPLACE FUNCTION public.task_evidence(p_person uuid, p_period text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'period',   p_period,
    'assigned', count(*),
    'onTime',   count(*) filter (where status = 'DONE'),
    'late',     count(*) filter (where status = 'LATE'),
    'missed',   count(*) filter (where status = 'MISSED'),
    'open',     count(*) filter (where status = 'OPEN'),
    'cancelled',count(*) filter (where status = 'CANCELLED'),
    'a3Suggested', case
      when count(*) filter (where status in ('DONE','LATE','MISSED')) = 0 then null
      else round( 2.0 * (
             count(*) filter (where status = 'DONE')
             + 0.5 * count(*) filter (where status = 'LATE')
           )::numeric
           / nullif(count(*) filter (where status in ('DONE','LATE','MISSED')), 0), 2)
      end,
    'items', coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'title', title, 'dueOn', due_on, 'status', status,
        'outcome', outcome, 'weight', attribute_weight,
        'setBy', (select pp.full_name from person pp where pp.id = assigned_by))
      order by due_on nulls last, created_at), '[]'::jsonb))
  from task where person_id = p_person and period = p_period;
$function$
;

CREATE OR REPLACE FUNCTION public.task_mine(p_person uuid, p_period text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'period', p_period,
    'owed', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id, 'title', t.title, 'detail', t.detail, 'dueOn', t.due_on,
               'status', t.status, 'weight', t.attribute_weight,
               'overdue', (t.status = 'OPEN' and t.due_on is not null and t.due_on < current_date),
               'setBy', b.full_name)
             order by t.due_on nulls last, t.created_at)
        from task t join person b on b.id = t.assigned_by
       where t.person_id = p_person and t.period = p_period), '[]'::jsonb),
    'set', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id, 'title', t.title, 'dueOn', t.due_on, 'status', t.status,
               'forWhom', w.full_name)
             order by t.due_on nulls last, t.created_at)
        from task t join person w on w.id = t.person_id
       where t.assigned_by = p_person and t.period = p_period), '[]'::jsonb));
$function$
;

CREATE OR REPLACE FUNCTION public.task_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_missed int := 0; v_told int := 0; v_more int := 0;
begin
  create temp table if not exists _missed (id uuid primary key, person_id uuid,
                                           assigned_by uuid, title text) on commit drop;
  delete from _missed;

  with gone as (
    update task set status = 'MISSED'
     where status = 'OPEN' and due_on is not null and due_on < current_date
    returning id, person_id, assigned_by, title)
  insert into _missed select id, person_id, assigned_by, title from gone;
  get diagnostics v_missed = row_count;

  if v_missed = 0 then
    return jsonb_build_object('tasks_missed', 0, 'people_told', 0);
  end if;

  insert into notification (person_id, kind, text, entity_type, entity_id, push, at)
  select m.person_id, 'TASK_MISSED',
         count(*) || ' task' || case when count(*) = 1 then '' else 's' end
           || ' you were given went past its date'
           || case when count(*) = 1 then ' — ' || min(m.title) else '' end
           || '. A missed task stands as a nil for A-3 this month.',
         'person', m.person_id, true, now()
    from _missed m group by m.person_id;
  get diagnostics v_told = row_count;

  insert into notification (person_id, kind, text, entity_type, entity_id, push, at)
  select m.assigned_by, 'TASK_MISSED',
         count(*) || ' task' || case when count(*) = 1 then '' else 's' end
           || ' you set went past the date you gave'
           || case when count(*) = 1 then ' — ' || min(m.title) else '' end
           || '. Close the ones that were done, and call off the ones that should not have been asked for.',
         'person', m.assigned_by, false, now()
    from _missed m where m.assigned_by <> m.person_id group by m.assigned_by;
  get diagnostics v_more = row_count;
  v_told := v_told + v_more;

  return jsonb_build_object('tasks_missed', v_missed, 'people_told', v_told);
end $function$
;

CREATE OR REPLACE FUNCTION public.ua_assignments(p_batch uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare r record; v_op uuid; v_client uuid; v_person uuid;
begin
  for r in select raw from upload_row where batch_id = p_batch order by row_no loop
    v_op := op_location_for(ul_txt(r.raw,'location'));
    select c.id into v_client from client c where lower(btrim(c.code)) = lower(btrim(ul_txt(r.raw,'client_code')));
    select p.id into v_person from person p where p.employee_no = ul_txt(r.raw,'handler_employee_no') and p.superseded_by is null;

    -- the validator has already refused a row missing any of these; this is
    -- the belt to that pair of braces, because the old version inserted
    -- nothing at all when a join found no row and said nothing about it
    if v_op is null or v_client is null or v_person is null then
      raise exception 'Assignment row for client % at % could not be resolved '
        '(client %, location %, handler %). Nothing was applied.',
        ul_txt(r.raw,'client_code'), ul_txt(r.raw,'location'),
        v_client is not null, v_op is not null, v_person is not null;
    end if;

    insert into coverage_rule (person_id, role, scope_type, client_id, op_node_id,
                               product, effective_from, effective_to,
                               is_assigned_handler, source_ref)
    values (v_person, 'HANDLER', 'CLIENT_ZONE', v_client, v_op,
            ul_txt(r.raw,'product'),
            ul_date(ul_txt(r.raw,'effective_from')), ul_date(ul_txt(r.raw,'effective_to')),
            true, 'bulk upload');

    if ul_txt(r.raw,'location_head_employee_no') is not null then
      insert into coverage_rule (person_id, role, scope_type, client_id, op_node_id,
                                 product, effective_from, effective_to,
                                 is_assigned_handler, source_ref)
      select p.id, 'LOCATION_HEAD', 'CLIENT_ZONE', v_client, v_op,
             ul_txt(r.raw,'product'),
             ul_date(ul_txt(r.raw,'effective_from')), ul_date(ul_txt(r.raw,'effective_to')),
             false, 'bulk upload'
        from person p where p.employee_no = ul_txt(r.raw,'location_head_employee_no') and p.superseded_by is null;
    end if;
  end loop;
end $function$
;

CREATE OR REPLACE FUNCTION public.ua_chairs(p_batch uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  insert into chair (code, title, level, reports_daily)
  select ul_txt(raw,'chair_code'), ul_txt(raw,'title'), lower(ul_txt(raw,'level')),
         lower(coalesce(ul_txt(raw,'reports_daily'),'no')) in ('yes','true')
    from upload_row where batch_id = p_batch
  on conflict (code) do update
    set title = excluded.title, level = excluded.level, reports_daily = excluded.reports_daily;

  -- second pass: a chair can report to one created by the same file
  update chair c set parent_id = p.id
    from upload_row r join chair p on p.code = ul_txt(r.raw,'reports_to_chair_code')
   where r.batch_id = p_batch and c.code = ul_txt(r.raw,'chair_code');
end $function$
;

CREATE OR REPLACE FUNCTION public.ua_clients(p_batch uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  insert into client (code, name, status, source_ref)
  select distinct on (ul_txt(raw,'client_code'))
         ul_txt(raw,'client_code'), ul_txt(raw,'client_name'), 'ACTIVE', 'bulk upload'
    from upload_row where batch_id = p_batch
   order by ul_txt(raw,'client_code'), row_no
  on conflict (code) do update set name = excluded.name, updated_at = now();

  insert into branch (client_id, code, name, address, op_node_id, status,
                      effective_from, source_ref)
  select c.id, ul_txt(r.raw,'branch_code'), ul_txt(r.raw,'branch_name'),
         ul_txt(r.raw,'address'), op_location_for(ul_txt(r.raw,'zone')),
         upper(coalesce(ul_txt(r.raw,'status'),'ACTIVE'))::entity_status,
         ul_date(ul_txt(r.raw,'opened_on')), 'bulk upload'
    from upload_row r
    join client c on lower(btrim(c.code)) = lower(btrim(ul_txt(r.raw,'client_code')))
   where r.batch_id = p_batch and op_location_for(ul_txt(r.raw,'zone')) is not null
  on conflict (client_id, code) do update
    set name = excluded.name, address = excluded.address,
        op_node_id = excluded.op_node_id, status = excluded.status,
        effective_from = coalesce(excluded.effective_from, branch.effective_from),
        updated_at = now();

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'CLIENTS_UPLOADED', 'upload_batch', p_batch::text,
          jsonb_build_object('rows', (select count(*) from upload_row where batch_id = p_batch)));
end $function$
;

CREATE OR REPLACE FUNCTION public.ua_collections(p_batch uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_bad text; v_expect int; v_got int;
begin
  select string_agg(distinct ul_txt(r.raw, 'zone'), ', ') into v_bad
    from upload_row r
   where r.batch_id = p_batch and r.error is null
     and ul_txt(r.raw, 'zone') is not null
     and op_zone_id(ul_txt(r.raw, 'zone')) is null;
  if v_bad is not null then
    raise exception 'Not one of your zones or locations: %. Nothing has been loaded.', v_bad;
  end if;

  select string_agg(distinct ul_txt(r.raw, 'client_code'), ', ') into v_bad
    from upload_row r
   where r.batch_id = p_batch and r.error is null
     and not exists (select 1 from client c where lower(btrim(c.code)) = lower(btrim(ul_txt(r.raw, 'client_code'))));
  if v_bad is not null then
    raise exception 'These client codes are not on file: %. Nothing has been loaded.', v_bad;
  end if;

  select count(*) into v_expect from upload_row where batch_id = p_batch and error is null;

  insert into perf_revenue (client_id, op_node_id, period, invoiced_inr, realised_inr,
                            loaded_by, source_ref)
  select c.id, op_zone_id(ul_txt(r.raw, 'zone')), (ul_txt(r.raw, 'period') || '-01')::date,
         round(ul_txt(r.raw, 'billed')::numeric)::bigint,
         round(ul_txt(r.raw, 'collected')::numeric)::bigint,
         p_actor, 'bulk upload'
    from upload_row r
    join client c on lower(btrim(c.code)) = lower(btrim(ul_txt(r.raw, 'client_code')))
   where r.batch_id = p_batch and r.error is null;

  get diagnostics v_got = row_count;
  if v_got <> v_expect then
    raise exception 'The file has % rows and % were written. Nothing has been loaded.', v_expect, v_got;
  end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.ua_escalation(p_batch uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare r record; v_client uuid; v_zone uuid; v_branch uuid; v_person uuid; v_chair uuid; v_id uuid;
begin
  for r in select * from upload_row where batch_id = p_batch and error is null order by row_no loop
    v_client := null; v_branch := null; v_person := null; v_chair := null; v_zone := null;

    if nullif(btrim(r.raw->>'client_code'), '') is not null then
      select id into v_client from client where lower(btrim(code)) = lower(btrim(btrim(r.raw->>'client_code')));
    end if;
    if nullif(btrim(r.raw->>'zone'), '') is not null then
      v_zone := op_zone_id(btrim(r.raw->>'zone'));
      if v_zone is null then
        raise exception 'Row %: "%" is not one of your zones or locations. A route scoped to a zone that cannot be placed would tell everybody, so nothing has been loaded.', r.row_no, btrim(r.raw->>'zone');
      end if;
    end if;
    if nullif(btrim(r.raw->>'branch_code'), '') is not null then
      select id into v_branch from branch where code = btrim(r.raw->>'branch_code');
    end if;
    if nullif(btrim(r.raw->>'person_email'), '') is not null then
      select id into v_person from person
       where lower(work_email) = lower(btrim(r.raw->>'person_email'))
         and employment_status = 'ACTIVE' and superseded_by is null;
    end if;
    if nullif(btrim(r.raw->>'chair_code'), '') is not null then
      select id into v_chair from chair where code = btrim(r.raw->>'chair_code');
    end if;

    update ogl_escalation_matrix
       set effective_to = current_date - 1
     where effective_to is null
       and client_id is not distinct from v_client
       and location_id is not distinct from v_zone
       and branch_id is not distinct from v_branch
       and escalation_level = (btrim(r.raw->>'level'))::int
       and sequence_no = coalesce(nullif(btrim(r.raw->>'sequence_no'), '')::int, 1);

    insert into ogl_escalation_matrix (client_id, location_id, branch_id,
      escalation_level, chair_id, person_id, sequence_no, effective_from)
    values (v_client, v_zone, v_branch, (btrim(r.raw->>'level'))::int,
      v_chair, v_person, coalesce(nullif(btrim(r.raw->>'sequence_no'), '')::int, 1),
      current_date)
    returning id into v_id;

    insert into audit_entry (actor_id, action, entity_type, entity_id, entity_ref, new_value)
    values (p_actor, 'ESCALATION_ROUTE_LOADED', 'ogl_escalation_matrix', v_id,
            coalesce(btrim(r.raw->>'zone'), 'every zone') || ' L' || btrim(r.raw->>'level'), r.raw);
  end loop;
end $function$
;

CREATE OR REPLACE FUNCTION public.ua_geography(p_batch uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
declare r record; v_zone uuid; v_state uuid; v_city uuid; v_old uuid; v_grp uuid; v_op uuid;
        v_moved int := 0; v_spelling int := 0; v_city_moved int := 0; v_ops int := 0;
begin
  for r in select row_no, raw from upload_row where batch_id = p_batch order by row_no loop

    select id into v_zone from geo_node
     where level = 'ZONE' and lower(name) = lower(geo_region(ul_txt(r.raw,'region')));
    if v_zone is null then
      insert into geo_node (level, name) values ('ZONE', geo_region(ul_txt(r.raw,'region')))
      returning id into v_zone;
    end if;

    -- the operating zone is a real place in the operating grouping, not a
    -- label, because a branch has to be able to point at it
    if ul_txt(r.raw,'zone') is not null then
      select id into v_grp from op_node
       where level='GROUP' and lower(btrim(name)) = lower(geo_region(ul_txt(r.raw,'region')));
      if v_grp is null then
        insert into op_node (level, name, active, source_ref)
        values ('GROUP', geo_region(ul_txt(r.raw,'region')), true, 'Geography upload')
        returning id into v_grp;
      end if;
      select id into v_op from op_node
       where level='ZONE' and lower(btrim(name)) = lower(btrim(ul_txt(r.raw,'zone')));
      if v_op is null then
        insert into op_node (level, name, parent_id, active, source_ref)
        values ('ZONE', ul_txt(r.raw,'zone'), v_grp, true, 'Geography upload');
        v_ops := v_ops + 1;
      end if;
    end if;

    select id into v_state from geo_node
     where level = 'STATE' and lower(btrim(name)) = lower(btrim(ul_txt(r.raw,'state')))
     limit 1;

    if v_state is null then
      select id into v_state from geo_node
       where level = 'STATE'
         and extensions.levenshtein(lower(btrim(name)),
                                    lower(btrim(ul_txt(r.raw,'state')))) between 1 and 2
       order by extensions.levenshtein(lower(btrim(name)),
                                       lower(btrim(ul_txt(r.raw,'state')))), name
       limit 1;
      if v_state is not null then
        v_spelling := v_spelling + 1;
        insert into migration_review (entity_type, entity_ref, question, context)
        select 'geo_node', v_state::text,
               'Is "' || ul_txt(r.raw,'state') || '" the same state as "' || g.name || '"?',
               'The Geography file spelled it differently. It was matched to the ' ||
               'existing row rather than added again, so the branches already on ' ||
               'it stay together. Rename it if the file is right.'
          from geo_node g where g.id = v_state
         and not exists (select 1 from migration_review m
                          where m.entity_type='geo_node' and m.entity_ref = v_state::text);
      end if;
    end if;

    if v_state is null then
      insert into geo_node (level, name, parent_id, group_name, op_zone)
      values ('STATE', ul_txt(r.raw,'state'), v_zone,
              ul_txt(r.raw,'group'), ul_txt(r.raw,'zone'))
      returning id into v_state;
    else
      select parent_id into v_old from geo_node where id = v_state;
      if v_old is distinct from v_zone then
        v_moved := v_moved + 1;
        insert into migration_review (entity_type, entity_ref, question, context)
        select 'geo_node', v_state::text,
               'Should ' || g.name || ' sit in ' || geo_region(ul_txt(r.raw,'region')) || '?',
               'It was in ' || coalesce(o.name,'no region') || '. The Geography file ' ||
               'moved it. Every branch stayed attached - a branch points at the ' ||
               'state, not at the region above it.'
          from geo_node g left join geo_node o on o.id = v_old
         where g.id = v_state;
        update geo_node set parent_id = v_zone where id = v_state;
      end if;
      update geo_node set group_name = coalesce(ul_txt(r.raw,'group'), group_name),
                          op_zone    = coalesce(ul_txt(r.raw,'zone'), op_zone)
       where id = v_state;
    end if;

    if ul_txt(r.raw,'city') is not null then
      select id into v_city from geo_node
       where level = 'CITY' and parent_id = v_state
         and lower(btrim(name)) = lower(btrim(ul_txt(r.raw,'city')));

      if v_city is null then
        select id into v_city from geo_node g
         where g.level = 'CITY' and lower(btrim(g.name)) = lower(btrim(ul_txt(r.raw,'city')))
           and (select count(*) from geo_node x
                 where x.level='CITY' and lower(btrim(x.name)) = lower(btrim(ul_txt(r.raw,'city')))) = 1
         limit 1;
        if v_city is not null then
          v_city_moved := v_city_moved + 1;
          update geo_node set parent_id = v_state where id = v_city;
        end if;
      end if;

      if v_city is null then
        insert into geo_node (level, name, parent_id, group_name, op_zone)
        values ('CITY', ul_txt(r.raw,'city'), v_state,
                ul_txt(r.raw,'group'), ul_txt(r.raw,'zone'));
      else
        update geo_node set group_name = coalesce(ul_txt(r.raw,'group'), group_name),
                            op_zone    = coalesce(ul_txt(r.raw,'zone'), op_zone)
         where id = v_city;
      end if;
    end if;
  end loop;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'GEOGRAPHY_UPLOADED', 'upload_batch', p_batch::text,
          jsonb_build_object('states_moved', v_moved, 'cities_moved', v_city_moved,
                             'spellings_matched', v_spelling, 'operating_zones_added', v_ops));
end $function$
;

CREATE OR REPLACE FUNCTION public.ua_holidays(p_batch uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_file text;
begin
  select file_name into v_file from upload_batch where id = p_batch;
  insert into holiday (day, name, applies_to, confirmed, source, batch_id)
  select ul_date(ul_txt(raw,'date')), ul_txt(raw,'name'),
         coalesce(ul_txt(raw,'scope'), 'ALL'),
         lower(coalesce(raw->>'confirmed','yes')) in ('yes','true'),
         'bulk upload: ' || v_file, p_batch
    from upload_row where batch_id = p_batch
  on conflict (day) do update
    set name = excluded.name, applies_to = excluded.applies_to,
        confirmed = excluded.confirmed, source = excluded.source, batch_id = excluded.batch_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.ua_kpi_targets(p_batch uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  insert into target (person_id, period, category, sub_category, target_value, updated_by)
  select p.id, ul_txt(r.raw,'period'), ul_txt(r.raw,'kpi_name'),
         ul_txt(r.raw,'sub_category'), ul_txt(r.raw,'target')::numeric, p_actor
    from upload_row r
    join person p on p.employee_no = ul_txt(r.raw,'employee_no') and p.superseded_by is null
   where r.batch_id = p_batch;
end $function$
;

CREATE OR REPLACE FUNCTION public.ua_opening(p_batch uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_cat uuid; v_desk uuid; v_cal uuid; v_rule uuid;
        r record; v_case uuid; v_party uuid; v_assign uuid; v_vt uuid;
        v_from uuid; v_to uuid; v_bad text;
begin
  select string_agg(distinct ul_txt(raw, 'zone'), ', ') into v_bad
    from upload_row
   where batch_id = p_batch and error is null
     and lower(ul_txt(raw, 'record_type')) = 'ogl_assignment'
     and op_zone_id(ul_txt(raw, 'zone')) is null;
  if v_bad is not null then
    raise exception 'Not one of your zones or locations: %. Nothing has been loaded.', v_bad;
  end if;

  select id into v_desk from desk where name = 'Cutover desk';
  if v_desk is null then
    insert into desk (name, primary_person_id, escalation_only)
    values ('Cutover desk', p_actor, false) returning id into v_desk;
  end if;

  select id into v_cat from category where name = 'Migrated at cutover';
  if v_cat is null then
    insert into category (name, desk_id, pinned, chase_hours, active)
    values ('Migrated at cutover', v_desk, false, 24, true) returning id into v_cat;
  end if;

  insert into "case" (ref, client_id, category_id, raised_by, owner_person_id, desk_id,
                      status, created_at, last_activity_at, source_ref)
  select ul_txt(r2.raw, 'reference'), c.id, v_cat, o.id, o.id, v_desk,
         upper(ul_txt(r2.raw, 'current_state'))::case_status,
         ogl_ts(ul_txt(r2.raw, 'created_at')), ogl_ts(ul_txt(r2.raw, 'created_at')),
         'opening balance'
    from upload_row r2
    join client c on lower(btrim(c.code)) = lower(btrim(ul_txt(r2.raw, 'client_code')))
    join person o on o.employee_no = ul_txt(r2.raw, 'owner_employee_no') and o.superseded_by is null
   where r2.batch_id = p_batch and r2.error is null
     and lower(ul_txt(r2.raw, 'record_type')) = 'escalation'
  on conflict (ref) do nothing;

  insert into claim (ref, person_id, amount, stage, created_at)
  select ul_txt(r2.raw, 'reference'), o.id,
         coalesce(ul_txt(r2.raw, 'amount')::numeric, 0),
         upper(ul_txt(r2.raw, 'current_state'))::claim_stage,
         ogl_ts(ul_txt(r2.raw, 'created_at'))
    from upload_row r2
    join person o on o.employee_no = ul_txt(r2.raw, 'owner_employee_no') and o.superseded_by is null
   where r2.batch_id = p_batch and r2.error is null
     and lower(ul_txt(r2.raw, 'record_type')) = 'claim'
  on conflict (ref) do nothing;

  if exists (select 1 from upload_row where batch_id = p_batch and error is null
              and lower(ul_txt(raw, 'record_type')) = 'ogl_assignment') then

    select id into v_cal from business_calendar where code = 'DEFAULT';

    select id into v_rule from sla_rule where code = 'CUTOVER' and version = 1;
    if v_rule is null then
      insert into sla_rule (code, version, tat_business_minutes, specificity, effective_from)
      values ('CUTOVER', 1, 1440, 0, current_date) returning id into v_rule;
    end if;

    for r in select row_no, raw from upload_row where batch_id = p_batch and error is null
              and lower(ul_txt(raw, 'record_type')) = 'ogl_assignment' order by row_no loop

      v_to := op_zone_id(ul_txt(r.raw, 'zone'));
      if v_to is null then
        raise exception 'Row %: "%" is not one of your zones or locations. Nothing has been loaded.',
          r.row_no, ul_txt(r.raw, 'zone');
      end if;

      select id into v_vt from verification_type
       where upper(code) = upper(coalesce(ul_txt(r.raw, 'verification_type'), 'RESIDENT'));

      insert into verification_case (force1_case_id, client_id, applicant_name,
                                     applicant_contact, applicant_address, pincode, created_by)
      select ul_txt(r.raw, 'force1_case_id'), c.id,
             ul_txt(r.raw, 'applicant_name'),
             coalesce(ul_txt(r.raw, 'applicant_contact'), 'not captured at cutover'),
             coalesce(ul_txt(r.raw, 'applicant_address'), 'not captured at cutover'),
             coalesce(ul_txt(r.raw, 'pincode'), '000000'),
             p_actor
        from client c where lower(btrim(c.code)) = lower(btrim(ul_txt(r.raw, 'client_code')))
      on conflict (force1_case_id) do nothing;

      select id into v_case from verification_case
       where force1_case_id = ul_txt(r.raw, 'force1_case_id');
      if v_case is null then
        raise exception 'Row %: client code "%" is not on file, so the case could not be created. Nothing has been loaded.', r.row_no, ul_txt(r.raw, 'client_code');
      end if;

      insert into case_party (case_id, party_role, seq_no, name, same_as_applicant)
      values (v_case, 'APPLICANT', 1, ul_txt(r.raw, 'applicant_name'), true)
      on conflict (case_id, party_role, seq_no) do nothing;
      select id into v_party from case_party
       where case_id = v_case and party_role = 'APPLICANT' and seq_no = 1;

      if ul_txt(r.raw, 'force1_point_id') is not null then
        insert into case_verification_requirement
          (case_id, party_id, verification_type_id, force1_point_id, status)
        values (v_case, v_party, v_vt, ul_txt(r.raw, 'force1_point_id'),
                case when upper(ul_txt(r.raw, 'current_state')) in ('CLOSED', 'CANCELLED')
                     then 'CLOSED' else 'IN_PROGRESS' end)
        on conflict (force1_point_id, attempt_no) do nothing;
      end if;

      select cr.op_node_id into v_from
        from coverage_rule cr join person p on p.id = cr.person_id
       where p.employee_no = ul_txt(r.raw, 'owner_employee_no') and p.superseded_by is null
         and cr.op_node_id is not null
       limit 1;

      insert into assignment (ref, case_id, assignor_id, assignor_chair_id,
                              from_location_id, to_location_id, allocated_to_id,
                              current_state, next_action_owner_id,
                              self_assign_reason, source_ref, created_at, closed_at)
      select ul_txt(r.raw, 'reference'), v_case, o.id, ch.chair_id,
             coalesce(v_from, v_to), v_to, o.id,
             upper(ul_txt(r.raw, 'current_state')),
             case when upper(ul_txt(r.raw, 'current_state')) in ('CLOSED', 'CANCELLED')
                  then null else o.id end,
             'migrated at cutover', 'opening balance',
             ogl_ts(ul_txt(r.raw, 'created_at')),
             case when upper(ul_txt(r.raw, 'current_state')) in ('CLOSED', 'CANCELLED')
                  then ogl_ts(ul_txt(r.raw, 'created_at')) else null end
        from person o
        join chair_holder ch on ch.person_id = o.id and ch.to_date is null
       where o.employee_no = ul_txt(r.raw, 'owner_employee_no') and o.superseded_by is null
       limit 1
      on conflict (ref) do nothing;

      select id into v_assign from assignment where ref = ul_txt(r.raw, 'reference');
      if v_assign is null then
        raise exception 'Row %: employee number "%" holds no chair, so the assignment has no assignor. Nothing has been loaded.', r.row_no, ul_txt(r.raw, 'owner_employee_no');
      end if;

      if upper(ul_txt(r.raw, 'current_state')) not in ('CLOSED', 'CANCELLED', 'DRAFT') then
        insert into sla_instance (assignment_id, breach_cycle_no, sla_rule_id, calendar_id,
                                  tat_business_minutes, started_at, due_at, rule_trace)
        values (v_assign, 1, v_rule, v_cal, 1440,
                ogl_ts(ul_txt(r.raw, 'created_at')),
                add_business_minutes(ogl_ts(ul_txt(r.raw, 'created_at')), 1440, v_cal),
                jsonb_build_object('rule', 'CUTOVER v1',
                  'why', 'Migrated at cutover: no rule dimensions were captured, so the '
                         || 'default applies and the trace says so rather than implying a match.'))
        on conflict (assignment_id, breach_cycle_no) do nothing;
      end if;

      insert into assignment_event (assignment_id, event_type, actor_id, to_state, is_system, payload)
      values (v_assign, 'ASSIGNMENT_CREATED', p_actor, upper(ul_txt(r.raw, 'current_state')), true,
              jsonb_build_object('source', 'opening balance',
                'note', 'Seated directly in its state. The history before cutover happened '
                        || 'in the old system and is not replayed here.'));
    end loop;
  end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.ua_past_perf(p_batch uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_bad text; v_expect int; v_got int;
begin
  select string_agg(distinct ul_txt(r.raw, 'location_code'), ', ') into v_bad
    from upload_row r
   where r.batch_id = p_batch and r.error is null
     and lower(ul_txt(r.raw, 'file_part')) in ('revenue', 'collections')
     and ul_txt(r.raw, 'location_code') is not null
     and op_zone_id(ul_txt(r.raw, 'location_code')) is null;
  if v_bad is not null then
    raise exception 'Not one of your zones or locations: %. Nothing has been loaded.', v_bad;
  end if;

  insert into perf_month (person_id, period, kpi_name, sub_category, unit,
                          target_value, achieved, mtd_achieved, source, loaded_by)
  select p.id, (ul_txt(r.raw, 'period') || '-01')::date, ul_txt(r.raw, 'kpi_name'),
         ul_txt(r.raw, 'sub_category'), ul_txt(r.raw, 'unit'),
         ul_txt(r.raw, 'target')::numeric, ul_txt(r.raw, 'achieved')::numeric,
         ul_txt(r.raw, 'mtd_achieved')::numeric,
         coalesce(ul_txt(r.raw, 'source'), 'bulk upload'), p_actor
    from upload_row r
    join person p on p.employee_no = ul_txt(r.raw, 'employee_no') and p.superseded_by is null
   where r.batch_id = p_batch and r.error is null
     and lower(ul_txt(r.raw, 'file_part')) = 'mtd';

  select count(*) into v_expect from upload_row
   where batch_id = p_batch and error is null
     and lower(ul_txt(raw, 'file_part')) = 'revenue';

  insert into perf_revenue (client_id, op_node_id, branch_id, period,
                            invoiced_inr, realised_inr, owner_person_id, loaded_by, source_ref)
  select c.id, op_zone_id(ul_txt(r.raw, 'location_code')), b.id,
         (ul_txt(r.raw, 'period') || '-01')::date,
         ul_txt(r.raw, 'invoiced_inr')::bigint, ul_txt(r.raw, 'realised_inr')::bigint,
         o.id, p_actor, coalesce(ul_txt(r.raw, 'source'), 'bulk upload')
    from upload_row r
    join client c on lower(btrim(c.code)) = lower(btrim(ul_txt(r.raw, 'client_code')))
    left join branch b on b.client_id = c.id and b.code = ul_txt(r.raw, 'branch_code')
    left join person o on o.employee_no = ul_txt(r.raw, 'owner_employee_no') and o.superseded_by is null
   where r.batch_id = p_batch and r.error is null
     and lower(ul_txt(r.raw, 'file_part')) = 'revenue';

  get diagnostics v_got = row_count;
  if v_got <> v_expect then
    raise exception 'The revenue part has % rows and % were written. Nothing has been loaded.', v_expect, v_got;
  end if;

  select count(*) into v_expect from upload_row
   where batch_id = p_batch and error is null
     and lower(ul_txt(raw, 'file_part')) = 'collections';

  insert into perf_collection (client_id, op_node_id, branch_id, period,
                               opening_outstanding_inr, collected_inr, closing_outstanding_inr,
                               owner_person_id, loaded_by, source_ref)
  select c.id, op_zone_id(ul_txt(r.raw, 'location_code')), b.id,
         (ul_txt(r.raw, 'period') || '-01')::date,
         ul_txt(r.raw, 'opening_outstanding_inr')::bigint,
         ul_txt(r.raw, 'collected_inr')::bigint,
         ul_txt(r.raw, 'closing_outstanding_inr')::bigint,
         o.id, p_actor, coalesce(ul_txt(r.raw, 'source'), 'bulk upload')
    from upload_row r
    join client c on lower(btrim(c.code)) = lower(btrim(ul_txt(r.raw, 'client_code')))
    left join branch b on b.client_id = c.id and b.code = ul_txt(r.raw, 'branch_code')
    left join person o on o.employee_no = ul_txt(r.raw, 'owner_employee_no') and o.superseded_by is null
   where r.batch_id = p_batch and r.error is null
     and lower(ul_txt(r.raw, 'file_part')) = 'collections';

  get diagnostics v_got = row_count;
  if v_got <> v_expect then
    raise exception 'The collections part has % rows and % were written. Nothing has been loaded.', v_expect, v_got;
  end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.ua_people(p_batch uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_adopted int := 0;
begin
  -- 1 - Adopt. Somebody already here by address, with no employee number, is
  --     this person. A blank department keeps what is recorded; it never
  --     clears it.
  update person p set
      employee_no   = ul_txt(r.raw,'employee_no'),
      full_name     = ul_txt(r.raw,'full_name'),
      mobile        = coalesce(ul_mobile(ul_txt(r.raw,'mobile')), p.mobile),
      department    = coalesce(dept_canon(ul_txt(r.raw,'department')), p.department),
      employee_type = upper(coalesce(ul_txt(r.raw,'employment_type'),'EMPLOYEE')),
      joined_on     = coalesce(ul_date(ul_txt(r.raw,'date_of_joining')), p.joined_on),
      source_ref    = coalesce(p.source_ref, 'bulk upload'),
      updated_at    = now()
    from upload_row r
   where r.batch_id = p_batch
     and lower(btrim(p.work_email)) = lower(btrim(ul_txt(r.raw,'work_email')))
     and p.superseded_by is null
     and p.employee_no is null;
  get diagnostics v_adopted = row_count;

  -- 2 - Everybody else, by employee number.
  insert into person (employee_no, full_name, work_email, mobile, department,
                      employment_status, employee_type, joined_on, app_role, source_ref)
  select ul_txt(raw,'employee_no'),
         ul_txt(raw,'full_name'),
         lower(ul_txt(raw,'work_email')),
         ul_mobile(ul_txt(raw,'mobile')),
         dept_canon(ul_txt(raw,'department')),
         'ACTIVE',
         upper(coalesce(ul_txt(raw,'employment_type'),'EMPLOYEE')),
         ul_date(ul_txt(raw,'date_of_joining')),
         'VIEWER',
         'bulk upload'
    from upload_row where batch_id = p_batch
  on conflict (employee_no) where employee_no is not null do update
    set full_name = excluded.full_name, work_email = excluded.work_email,
        mobile = coalesce(excluded.mobile, person.mobile),
        department = coalesce(excluded.department, person.department),
        employee_type = excluded.employee_type,
        joined_on = excluded.joined_on, updated_at = now();

  -- managers second, so a person can report to someone created by this file.
  -- A blank column leaves the manager alone rather than clearing it, because
  -- the join simply does not match.
  update person p set manager_id = m.id
    from upload_row r
    join person m on m.employee_no = ul_txt(r.raw,'reports_to_employee_no') and m.superseded_by is null
                 and m.superseded_by is null
   where r.batch_id = p_batch and p.employee_no = ul_txt(r.raw,'employee_no') and p.superseded_by is null
     and p.superseded_by is null
     and p.manager_id is distinct from m.id;

  -- seat each person in their chair; an existing seat is vacated first so a
  -- move shows as a move rather than two people holding one chair
  update chair_holder ch set to_date = current_date
    from upload_row r
    join person p on p.employee_no = ul_txt(r.raw,'employee_no') and p.superseded_by is null
   where r.batch_id = p_batch and ch.person_id = p.id and ch.to_date is null
     and ch.chair_id <> (select c.id from chair c
                          where c.title = ul_txt(r.raw,'chair') or c.code = ul_txt(r.raw,'chair') limit 1);

  insert into chair_holder (chair_id, person_id, is_primary, from_date)
  select c.id, p.id,
         not exists (select 1 from chair_holder x
                      where x.person_id = p.id and x.is_primary and x.to_date is null),
         coalesce(ul_date(ul_txt(r.raw,'date_of_joining')), current_date)
    from upload_row r
    join person p on p.employee_no = ul_txt(r.raw,'employee_no') and p.superseded_by is null
    join lateral (select c2.id from chair c2
                   where c2.title = ul_txt(r.raw,'chair') or c2.code = ul_txt(r.raw,'chair')
                   limit 1) c on true
   where r.batch_id = p_batch
     and not exists (select 1 from chair_holder x
                      where x.person_id = p.id and x.chair_id = c.id and x.to_date is null);

  -- a person loaded without a mobile is a question for HR, not a blocker
  insert into migration_review (entity_type, entity_ref, question, context)
  select 'person', 'UPLOAD!' || ul_txt(r.raw,'employee_no'),
         'What is the mobile number for ' || ul_txt(r.raw,'full_name') || '?',
         'Loaded without one. Sign-in by OTP needs it where there is no Google account.'
    from upload_row r
   where r.batch_id = p_batch
     and ul_mobile(ul_txt(r.raw,'mobile')) is null
     and not exists (select 1 from migration_review x
                      where x.entity_type = 'person'
                        and x.entity_ref = 'UPLOAD!' || ul_txt(r.raw,'employee_no'));

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'PEOPLE_UPLOADED', 'upload_batch', p_batch::text,
          jsonb_build_object('adopted_existing', v_adopted));
end $function$
;

CREATE OR REPLACE FUNCTION public.ua_rates(p_batch uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare r record; v_rate uuid; v_seq int; v_zone text; v_node uuid; v_client uuid;
begin
  select coalesce(count(*), 0) into v_seq from rate;

  for r in select row_no, raw from upload_row
            where batch_id = p_batch and error is null order by row_no loop
    v_seq := v_seq + 1;
    v_zone := ul_txt(r.raw, 'zone');
    v_node := null;

    if v_zone is not null then
      v_node := op_zone_id(v_zone);
      if v_node is null then
        raise exception 'Row %: "%" is not one of your zones or locations. A rate scoped to a zone that cannot be placed would be priced against every branch of the client, so nothing has been loaded.', r.row_no, v_zone;
      end if;
    end if;

    select c.id into v_client from client c where lower(btrim(c.code)) = lower(btrim(ul_txt(r.raw, 'client_code')));
    if v_client is null then
      raise exception 'Row %: client code "%" is not on file. Nothing has been loaded.',
        r.row_no, ul_txt(r.raw, 'client_code');
    end if;

    insert into rate (code, client_id, scope, value, currency,
                      effective_from, effective_to, reason, created_by)
    values ('RATE-' || lpad(v_seq::text, 6, '0'), v_client,
            (case when v_node is null then 'client' else 'exact' end)::rate_scope,
            ul_txt(r.raw, 'rate')::numeric,
            coalesce(ul_txt(r.raw, 'currency'), 'INR'),
            ul_date(ul_txt(r.raw, 'effective_from')),
            ul_date(ul_txt(r.raw, 'effective_to')),
            ul_txt(r.raw, 'reason'), p_actor)
    returning id into v_rate;

    if v_node is not null then
      insert into rate_location (rate_id, op_node_id) values (v_rate, v_node)
      on conflict do nothing;
      if not exists (select 1 from rate_location where rate_id = v_rate) then
        raise exception 'Row %: the rate was written but its location was not. Nothing has been loaded.', r.row_no;
      end if;
    end if;
  end loop;
end $function$
;

CREATE OR REPLACE FUNCTION public.ua_sla_rules(p_batch uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare r record; v_client uuid; v_type uuid; v_zone uuid; v_ver int; v_spec int; v_id uuid;
begin
  for r in select * from upload_row where batch_id = p_batch and error is null order by row_no loop
    v_client := null; v_type := null; v_zone := null;
    if nullif(btrim(r.raw->>'client_code'), '') is not null then
      select id into v_client from client where lower(btrim(code)) = lower(btrim(btrim(r.raw->>'client_code')));
      if v_client is null then
        raise exception 'Row %: client code "%" is not on file. Nothing has been loaded.',
          r.row_no, btrim(r.raw->>'client_code');
      end if;
    end if;
    if nullif(btrim(r.raw->>'verification_type'), '') is not null then
      select id into v_type from verification_type where code = upper(btrim(r.raw->>'verification_type'));
    end if;
    if nullif(btrim(r.raw->>'zone'), '') is not null then
      v_zone := op_zone_id(btrim(r.raw->>'zone'));
      if v_zone is null then
        raise exception 'Row %: "%" is not one of your zones or locations. A rule scoped to a zone that cannot be placed would apply everywhere and outrank the rule that should have won, so nothing has been loaded.', r.row_no, btrim(r.raw->>'zone');
      end if;
    end if;

    v_spec := (case when v_client is not null then 16 else 0 end)
            + (case when v_type is not null then 16 else 0 end)
            + (case when v_zone is not null then 8 else 0 end)
            + (case when nullif(btrim(r.raw->>'priority'), '') is not null then 8 else 0 end);

    select coalesce(max(version), 0) + 1 into v_ver from sla_rule where code = btrim(r.raw->>'code');

    insert into sla_rule (code, version, client_id, verification_type_id, op_node_id,
      priority, tat_business_minutes, grace_minutes, at_risk_pct, specificity,
      effective_from, effective_to)
    values (btrim(r.raw->>'code'), v_ver, v_client, v_type, v_zone,
      nullif(btrim(r.raw->>'priority'), ''),
      (btrim(r.raw->>'tat_business_minutes'))::int,
      coalesce(nullif(btrim(r.raw->>'grace_minutes'), '')::int, 0),
      coalesce(nullif(btrim(r.raw->>'at_risk_pct'), '')::int, 75),
      v_spec,
      ul_date(r.raw->>'effective_from'),
      ul_date(r.raw->>'effective_to'))
    returning id into v_id;

    update sla_rule set effective_to = ul_date(r.raw->>'effective_from') - 1
     where code = btrim(r.raw->>'code') and version < v_ver and effective_to is null;

    insert into audit_entry (actor_id, action, entity_type, entity_id, entity_ref, new_value)
    values (p_actor, 'SLA_RULE_LOADED', 'sla_rule', v_id,
            btrim(r.raw->>'code') || ' v' || v_ver, r.raw);
  end loop;
end $function$
;

CREATE OR REPLACE FUNCTION public.ul_code(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p is null then null
    -- a code that is really a number, saved by a spreadsheet as one
    when btrim(p) ~ '^\d+\.0+$' then split_part(btrim(p), '.', 1)
    else nullif(btrim(p), '')
  end
$function$
;

CREATE OR REPLACE FUNCTION public.ul_date(p text)
 RETURNS date
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
declare s text; d date; yy int; cutoff int;
begin
  s := btrim(coalesce(p, ''));
  if s = '' then return null; end if;
  -- a spreadsheet writes the separator three different ways
  s := replace(replace(s, '.', '-'), '/', '-');

  begin
    if s ~ '^\d{4}-\d{1,2}-\d{1,2}$' then
      d := to_date(s, 'YYYY-MM-DD');
    elsif s ~ '^\d{1,2}-\d{1,2}-\d{4}$' then
      -- day first: the form every Indian sheet writes
      d := to_date(s, 'DD-MM-YYYY');
    elsif s ~ '^\d{1,2}-\d{1,2}-\d{2}$' then
      -- day first with a two-digit year: 01-09-26. Excel's favourite, and what
      -- the rates export produced for all 850 of its rows.
      yy := split_part(s, '-', 3)::int;
      cutoff := (extract(year from current_date)::int % 100) + 5;
      d := to_date(split_part(s,'-',1) || '-' || split_part(s,'-',2) || '-' ||
                   lpad((case when yy <= cutoff then 2000 + yy else 1900 + yy end)::text, 4, '0'),
                   'DD-MM-YYYY');
    elsif s ~ '^\d{1,2}-[A-Za-z]{3,}-\d{4}$' then
      begin
        d := to_date(s, 'DD-Mon-YYYY');            -- 01-Apr-2024
      exception when others then
        d := to_date(s, 'DD-Month-YYYY');          -- 01-April-2024
      end;
    else
      return null;
    end if;
  exception when others then
    return null;
  end;

  -- to_date will invent a date out of nonsense rather than refuse it
  if d < date '1900-01-01' or d > current_date + 365 then return null; end if;
  return d;
end $function$
;

CREATE OR REPLACE FUNCTION public.ul_date_ok(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select ul_date(p) is not null;
$function$
;

CREATE OR REPLACE FUNCTION public.ul_mobile(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  -- drop a trailing Excel decimal, then keep the digits
  select nullif(regexp_replace(regexp_replace(coalesce(p,''), '\.0+$', ''), '[^0-9]', '', 'g'), '')
$function$
;

CREATE OR REPLACE FUNCTION public.ul_txt(r jsonb, k text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$ select nullif(btrim(r->>k), '') $function$
;

CREATE OR REPLACE FUNCTION public.upload_apply(p_batch uuid, p_actor uuid)
 RETURNS TABLE(applied integer)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_kind text; v_state text; v_err int; v_fn text; v_n int;
begin
  select kind, state, rows_error into v_kind, v_state, v_err
    from upload_batch where id = p_batch for update;
  if v_kind is null then raise exception 'no such batch'; end if;
  if v_state = 'APPLIED' then raise exception 'batch already applied'; end if;
  if v_err > 0 then
    raise exception 'file has % errored row(s); a file with any error applies zero rows', v_err
      using errcode = 'check_violation';
  end if;

  select applier into v_fn from upload_kind where kind = v_kind and implemented;
  if v_fn is null then raise exception 'no loader is implemented for %', v_kind; end if;
  execute format('select %I($1, $2)', v_fn) using p_batch, p_actor;

  update upload_batch set state = 'APPLIED', applied_at = now(), applied_by = p_actor
   where id = p_batch;

  select count(*)::int into v_n from upload_row where batch_id = p_batch and error is null;
  applied := v_n;
  return next;
end $function$
;

CREATE OR REPLACE FUNCTION public.upload_apply_audited(p_batch uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_applied int;
begin
  select applied into v_applied from upload_apply(p_batch, p_actor);
  insert into audit_entry (actor_id, action, entity_type, entity_id, entity_ref, new_value)
  values (p_actor, 'UPLOAD_APPLIED', 'upload_batch', p_batch, p_batch::text,
          jsonb_build_object('applied', v_applied));
  return jsonb_build_object('applied', v_applied, 'note', 'Loaded.');
exception
  when check_violation then
    if sqlerrm like '%applies zero rows%' then
      return jsonb_build_object('error','has_errors','reason', sqlerrm);
    end if;
    return jsonb_build_object('error','apply_failed',
      'reason','The file passed validation but the database refused a row: ' || sqlerrm,
      'hint','Nothing was written. This is a gap in the loader, not in your file.');
  when others then
    return jsonb_build_object('error','apply_failed',
      'reason','The file passed validation but the database refused a row: ' || sqlerrm,
      'hint','Nothing was written. This is a gap in the loader, not in your file.');
end $function$
;

CREATE OR REPLACE FUNCTION public.upload_cancel(p_batch uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;
begin
  update upload_batch set state = 'CANCELLED'
   where id = p_batch and state = 'PREVIEW' returning id into v_id;
  if v_id is null then
    return jsonb_build_object('error','not_cancellable',
      'reason','Only a batch still in preview can be cancelled.');
  end if;
  insert into audit_entry (actor_id, action, entity_type, entity_id, entity_ref)
  values (p_actor, 'UPLOAD_CANCELLED', 'upload_batch', p_batch, p_batch::text);
  return jsonb_build_object('id', v_id, 'state', 'CANCELLED');
end $function$
;

CREATE OR REPLACE FUNCTION public.upload_history(p_limit integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.uploaded_at desc), '[]'::jsonb)
    from (select b.id, b.kind, b.file_name, b.state, b.uploaded_at,
                 b.rows_total, b.rows_ok, b.rows_error, p.full_name as uploaded_by
            from upload_batch b left join person p on p.id = b.uploaded_by
           order by b.uploaded_at desc limit p_limit) x
$function$
;

CREATE OR REPLACE FUNCTION public.upload_key(p_kind text)
 RETURNS TABLE(ord integer, line text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select 1, 'YOUR LOCATIONS - the location column must be one of these'
   where p_kind = 'Assignments'
  union all
  select 2 + (row_number() over (order by l.name))::int,
         concat_ws(',', csv_cell(l.name), csv_cell(coalesce(z.name,'')))
    from op_node l left join op_node z on z.id = l.parent_id
   where p_kind = 'Assignments' and l.level = 'LOCATION' and l.active
  union all
  select 500, '' where p_kind = 'Assignments'
  union all
  select 501, 'WHO HOLDS A CHAIR - any of these can be a handler or a location head'
   where p_kind = 'Assignments'
  union all
  select 502 + (row_number() over (order by p.employee_no))::int,
         concat_ws(',', csv_cell(p.employee_no), csv_cell(p.full_name), csv_cell(ch.title))
    from person p
    join chair_holder h on h.person_id = p.id and h.to_date is null
    join chair ch on ch.id = h.chair_id
   where p_kind = 'Assignments' and p.employee_no is not null
     and p.employment_status = 'ACTIVE'

  union all
  select 1, 'YOUR DEPARTMENTS - the department column must be one of these, and '
            'what each one is allowed to see of a client'
   where p_kind = 'People'
  union all
  select 2 + (row_number() over (order by d.department))::int,
         concat_ws(',', csv_cell(d.department), csv_cell(
           case d.view_kind
             when 'matrix'   then 'The full escalation matrix, for the clients they cover'
             when 'contacts' then 'Client and branch contacts only, for the clients they cover'
             else 'No client data at all' end))
    from client_view_policy d
   where p_kind = 'People'
  union all
  select 500, '' where p_kind = 'People'
  union all
  select 501, 'YOUR CHAIRS - the chair column must be one of these, either the code or the title'
   where p_kind = 'People'
  union all
  select 502 + (row_number() over (order by c.code))::int,
         concat_ws(',', csv_cell(c.code), csv_cell(c.title), csv_cell(coalesce(c.function_name,'')))
    from chair c
   where p_kind = 'People';
$function$
;

CREATE OR REPLACE FUNCTION public.upload_kinds()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(k) order by k.load_order), '[]'::jsonb)
    from (select kind, load_order, needs, implemented from upload_kind) k
$function$
;

CREATE OR REPLACE FUNCTION public.upload_preview(p_batch uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'batch', to_jsonb(b),
    'errors', coalesce((select jsonb_agg(jsonb_build_object('row_no', row_no, 'error', error, 'raw', raw) order by row_no)
        from (select row_no, error, raw from upload_row where batch_id = b.id and error is not null order by row_no limit 200) e), '[]'::jsonb),
    'sample', coalesce((select jsonb_agg(jsonb_build_object('row_no', row_no, 'raw', raw) order by row_no)
        from (select row_no, raw from upload_row where batch_id = b.id and error is null order by row_no limit 20) s), '[]'::jsonb))
  from upload_batch b where b.id = p_batch
$function$
;

CREATE OR REPLACE FUNCTION public.upload_provenance(p_kind text)
 RETURNS TABLE(ord integer, line text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select 1, csv_cell('client_code and location') || ',' ||
            csv_cell('Every client with at least one branch at that location. Fact, not a guess.')
   where p_kind = 'Assignments'
  union all
  select 2, csv_cell('handler_employee_no') || ',' ||
            csv_cell('Whoever covers most of that client''s branches there today. A suggestion - check it.')
   where p_kind = 'Assignments'
  union all
  select 3, csv_cell('location_head_employee_no') || ',' ||
            csv_cell('Who that handler reports to on the People file. A weak suggestion - correct it first.')
   where p_kind = 'Assignments'
  union all
  select 4, csv_cell('a blank handler') || ',' ||
            csv_cell('The tool has no basis for a suggestion. Look the number up in the key below.')
   where p_kind = 'Assignments'

  union all
  select 1, csv_cell('everything except department') || ',' ||
            csv_cell('What the tool holds for that person today. Fact, not a guess.')
   where p_kind = 'People'
  union all
  select 2, csv_cell('department, where it was already set') || ',' ||
            csv_cell('What the tool holds. Fact.')
   where p_kind = 'People'
  union all
  select 3, csv_cell('department, where it was blank') || ',' ||
            csv_cell('Taken from the chair, where the chair means exactly one department. '
                     'A suggestion - nobody has ever confirmed it, and it decides what '
                     'this person can see. Check every one.')
   where p_kind = 'People'
  union all
  select 4, csv_cell('a blank department') || ',' ||
            csv_cell('The chair spans more than one department, so the tool will not guess. Fill it in.')
   where p_kind = 'People'
  union all
  select 5, csv_cell('a blank employee_no') || ',' ||
            csv_cell('That person has never been given one. The file will not load until you do - '
                     'that is deliberate, it is the only way they can be told apart.')
   where p_kind = 'People'
  union all
  select 6, csv_cell('reports_to_name') || ',' ||
            csv_cell('Ignored on upload. It is there so you can read the reporting line '
                     'without looking every number up.')
   where p_kind = 'People';
$function$
;

CREATE OR REPLACE FUNCTION public.upload_seed(p_kind text)
 RETURNS TABLE(ord integer, line text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin

  -- ASSIGNMENTS. Every client that has a branch at an operating location, with
  -- whoever covers most of that client's branches there today.
  --
  -- This used to reach coverage through the cut-over branches, by name match,
  -- because that is where the coverage was. migration 132 moved all 1,123
  -- rules onto the real master, which left that path reading an empty set: the
  -- seed still produced 59 rows and every handler cell in all 59 came out
  -- blank, where it had filled 21 before the fold. Coverage sits on the
  -- branches themselves now, so it is read from there.
  if p_kind = 'Assignments' then
    return query
    with cov as (
      -- branch-level rules only; a client-level or zone-level rule names no
      -- branch, so it cannot say which location it belongs to
      select b.client_id, b.op_node_id, cr.person_id,
             row_number() over (partition by b.client_id, b.op_node_id
                                order by count(*) desc, min(cr.created_at)) rn
        from coverage_rule cr
        join branch b on b.id = cr.branch_id
       where cr.effective_to is null and b.op_node_id is not null
       group by b.client_id, b.op_node_id, cr.person_id
    ), have as (
      select distinct b.client_id, b.op_node_id
        from branch b join client c on c.id = b.client_id
       where b.op_node_id is not null and c.status = 'ACTIVE'
    )
    select row_number() over (order by c.code, o.name)::int,
           concat_ws(',',
             csv_cell(c.code), csv_cell(o.name), csv_cell(''),
             csv_cell(coalesce(h.employee_no,'')), csv_cell(coalesce(h.full_name,'')),
             csv_cell(coalesce(m.employee_no,'')), csv_cell(coalesce(m.full_name,'')),
             csv_cell(to_char(date_trunc('month', current_date), 'YYYY-MM-DD')), csv_cell(''))
      from have
      join client  c on c.id = have.client_id
      join op_node o on o.id = have.op_node_id and o.active
      left join cov    on cov.client_id = have.client_id
                      and cov.op_node_id = have.op_node_id and cov.rn = 1
      left join person h on h.id = cov.person_id
      left join person m on m.id = h.manager_id
     order by c.code, o.name;

  -- PEOPLE. Everybody on the staff, as the tool holds them now, so the file is
  -- corrected rather than authored. The client's own branch contacts live in
  -- person as well -- 533 of them, every one at a client's domain -- and they
  -- are not staff, so is_staff keeps them out.
  --
  -- Two columns carry a suggestion rather than a fact. A blank department
  -- takes one from the chair where the chair means exactly one department,
  -- which covers all 48 of the people who have none. Six people have no
  -- employee number yet, so their first cell comes down blank on purpose --
  -- fill it and the file loads, leave it and it will not, which is the point.
  elsif p_kind = 'People' then
    return query
    select row_number() over (order by coalesce(p.employee_no,'ZZZZ'), p.full_name)::int,
           concat_ws(',',
             csv_cell(coalesce(p.employee_no,'')),
             csv_cell(p.full_name),
             csv_cell(coalesce(p.work_email,'')),
             csv_cell(coalesce(p.mobile,'')),
             csv_cell(coalesce(ch.title,'')),
             csv_cell(coalesce(p.department, dept_from_chair(p.id), '')),
             csv_cell(coalesce(m.employee_no,'')),
             csv_cell(coalesce(m.full_name,'')),
             csv_cell(coalesce(to_char(p.joined_on,'YYYY-MM-DD'),'')),
             csv_cell(initcap(lower(coalesce(p.employee_type,'EMPLOYEE')))))
      from person p
      left join lateral (
             select c.title from chair_holder h join chair c on c.id = h.chair_id
              where h.person_id = p.id and h.to_date is null
              order by h.is_primary desc, h.from_date limit 1) ch on true
      left join person m on m.id = p.manager_id
     where p.superseded_by is null
       and p.employment_status = 'ACTIVE'
       and is_staff(p.id)
     order by coalesce(p.employee_no,'ZZZZ'), p.full_name;
  end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.upload_stage(p_kind text, p_file text, p_rows jsonb, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_batch uuid;
  v_total int; v_ok int; v_bad int;
  v_impl boolean;
begin
  select implemented into v_impl from upload_kind where kind = p_kind;
  if not found then
    return jsonb_build_object('error','bad_kind',
      'reason','Unknown file kind. The kinds list gives them in load order.');
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    return jsonb_build_object('error','empty_file',
      'reason','The file has a header but no data rows.');
  end if;
  insert into upload_batch (kind, file_name, uploaded_by)
  values (p_kind, coalesce(nullif(p_file,''),'upload.csv'), p_actor)
  returning id into v_batch;
  insert into upload_row (batch_id, row_no, raw)
  select v_batch, ord + 1, val
    from jsonb_array_elements(p_rows) with ordinality as t(val, ord);
  select rows_total, rows_ok, rows_error into v_total, v_ok, v_bad
    from upload_validate(v_batch);
  insert into audit_entry (actor_id, action, entity_type, entity_id, entity_ref, new_value)
  values (p_actor, 'UPLOAD_STAGED', 'upload_batch', v_batch, v_batch::text,
          jsonb_build_object('kind', p_kind, 'rows', v_total, 'errors', v_bad));
  return jsonb_build_object(
    'batchId', v_batch,
    'rows_total', v_total, 'rows_ok', v_ok, 'rows_error', v_bad,
    'implemented', v_impl,
    'applicable', v_impl and v_bad = 0,
    'errors', coalesce((select jsonb_agg(jsonb_build_object('row_no', row_no, 'error', error, 'raw', raw) order by row_no)
        from (select row_no, error, raw from upload_row where batch_id = v_batch and error is not null order by row_no limit 200) e), '[]'::jsonb),
    'sample', coalesce((select jsonb_agg(jsonb_build_object('row_no', row_no, 'raw', raw) order by row_no)
        from (select row_no, raw from upload_row where batch_id = v_batch and error is null order by row_no limit 20) s), '[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.upload_template(p_kind text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_csv text; v_seeded boolean; v_keyed boolean; v_prov boolean;
begin
  if not exists (select 1 from upload_column where kind = p_kind) then return null; end if;
  select exists (select 1 from upload_seed(p_kind))       into v_seeded;
  select exists (select 1 from upload_key(p_kind))        into v_keyed;
  select exists (select 1 from upload_provenance(p_kind)) into v_prov;

  select string_agg(line, E'\n' order by ord) into v_csv from (
    select 0 as ord, 'Crux bulk upload template,' || csv_cell(p_kind) as line
    union all select 1, case when v_seeded
      then 'The rows below are filled in from what the tool already knows. Check '
           'them, correct them, and add anything missing.'
      else 'Row below the header is an example - delete it before uploading.' end
    union all select 2, 'A file with any error applies zero rows.'
    union all select 3, ''
    union all select 4, (select string_agg(csv_cell(name), ',' order by ord)
                           from upload_column where kind = p_kind)
    union all select 5 + s.ord, s.line from upload_seed(p_kind) s where v_seeded
    union all select 5, (select string_agg(csv_cell(example), ',' order by ord)
                           from upload_column where kind = p_kind) where not v_seeded
    union all select 1000000, ''
    union all select 1000001, 'NOTES'
    union all select 1000002, (select string_agg(csv_cell(name) || ',' || csv_cell(rule), E'\n' order by ord)
                                 from upload_column where kind = p_kind)
    union all select 1000003, '' where v_prov
    union all select 1000004, 'WHERE THE FILLED-IN VALUES CAME FROM' where v_prov
    union all select 1000004 + v.ord, v.line from upload_provenance(p_kind) v where v_prov
    union all select 2000000, '' where v_keyed
    union all select 2000000 + k.ord, k.line from upload_key(p_kind) k where v_keyed
  ) s;

  -- U+FEFF. Without it Excel opens the file as ANSI and every accented
  -- character, rupee sign and dash in it turns to mojibake.
  return E'﻿' || v_csv;
end $function$
;

CREATE OR REPLACE FUNCTION public.upload_validate(p_batch uuid)
 RETURNS TABLE(rows_total integer, rows_ok integer, rows_error integer)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_kind text; v_fn text; v_total int; v_ok int; v_bad int;
begin
  select kind into v_kind from upload_batch where id = p_batch;
  if v_kind is null then raise exception 'no such batch'; end if;

  update upload_row set error = null where batch_id = p_batch;

  select validator into v_fn from upload_kind where kind = v_kind and implemented;
  if v_fn is null then
    update upload_row set error = 'no loader is implemented for this file kind yet'
     where batch_id = p_batch;
  else
    execute format('select %I($1)', v_fn) using p_batch;
  end if;

  select count(*)::int,
         count(*) filter (where error is null)::int,
         count(*) filter (where error is not null)::int
    into v_total, v_ok, v_bad
    from upload_row where batch_id = p_batch;

  update upload_batch b set rows_total = v_total, rows_ok = v_ok, rows_error = v_bad
   where b.id = p_batch;

  rows_total := v_total; rows_ok := v_ok; rows_error := v_bad;
  return next;
end $function$
;

CREATE OR REPLACE FUNCTION public.uv_assignments(p_batch uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  update upload_row r set error = e.msg from (
    select r2.id, nullif(concat_ws('; ',
      case when ul_txt(r2.raw,'client_code') is null then 'client_code is required'
           when not exists (select 1 from client c where lower(btrim(c.code)) = lower(btrim(ul_txt(r2.raw,'client_code'))))
           then 'client_code ' || ul_txt(r2.raw,'client_code') || ' does not exist - load Clients first' end,
      case when ul_txt(r2.raw,'location') is null then 'location is required'
           when op_location_for(ul_txt(r2.raw,'location')) is null
           then 'location ' || ul_txt(r2.raw,'location') || ' is not in the operating '
                || 'grouping. An administrator adds it under Configuration, Locations.' end,
      case when ul_txt(r2.raw,'handler_employee_no') is null then 'handler_employee_no is required'
           when not exists (select 1 from person p where p.employee_no = ul_txt(r2.raw,'handler_employee_no') and p.superseded_by is null)
           then 'handler_employee_no ' || ul_txt(r2.raw,'handler_employee_no') || ' is not on the people master - load People first' end,
      case when ul_txt(r2.raw,'location_head_employee_no') is not null
            and not exists (select 1 from person p where p.employee_no = ul_txt(r2.raw,'location_head_employee_no') and p.superseded_by is null)
           then 'location_head_employee_no ' || ul_txt(r2.raw,'location_head_employee_no') || ' is not on the people master' end,
      case when ul_txt(r2.raw,'effective_from') is null then 'effective_from is required'
           when not ul_date_ok(ul_txt(r2.raw,'effective_from')) then 'effective_from is not a date the tool can read. YYYY-MM-DD, DD-MM-YYYY and DD-MM-YY all work' end,
      case when ul_txt(r2.raw,'effective_to') is not null and ul_date(ul_txt(r2.raw,'effective_to')) is null
           then 'effective_to is not a date the tool can read. YYYY-MM-DD, DD-MM-YYYY and DD-MM-YY all work, or left blank' end,
      case when ul_date_ok(ul_txt(r2.raw,'effective_from')) and ul_date_ok(ul_txt(r2.raw,'effective_to'))
            and ul_date(ul_txt(r2.raw,'effective_to')) <= ul_date(ul_txt(r2.raw,'effective_from'))
           then 'effective_to must be after effective_from' end
    ), '') as msg
    from upload_row r2 where r2.batch_id = p_batch
  ) e where r.id = e.id and e.msg is not null;

  -- two rows in this file covering the same client, location and product at once
  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'overlaps another row in this file for the same client, location and product'
    from (
      select a.id from upload_row a join upload_row b
        on a.batch_id = b.batch_id and a.id <> b.id
       and ul_txt(a.raw,'client_code') = ul_txt(b.raw,'client_code')
       and lower(ul_txt(a.raw,'location')) = lower(ul_txt(b.raw,'location'))
       and coalesce(lower(ul_txt(a.raw,'product')),'') = coalesce(lower(ul_txt(b.raw,'product')),'')
       and daterange(ul_date(ul_txt(a.raw,'effective_from')), ul_date(ul_txt(a.raw,'effective_to')), '[)')
        && daterange(ul_date(ul_txt(b.raw,'effective_from')), ul_date(ul_txt(b.raw,'effective_to')), '[)')
      where a.batch_id = p_batch and a.error is null and b.error is null
    ) o where r.id = o.id;

  -- and against what is already covered, so the overlap trigger never has to
  -- abort the whole file to say so
  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'overlaps a coverage rule that already exists for this client and location'
    from upload_row r2
    join client c on lower(btrim(c.code)) = lower(btrim(ul_txt(r2.raw,'client_code')))
    join op_node o on o.level='LOCATION'
                  and lower(btrim(o.name)) = lower(btrim(ul_txt(r2.raw,'location')))
   where r.id = r2.id and r2.batch_id = p_batch and r2.error is null
     and exists (
       select 1 from coverage_rule cr
        where cr.client_id = c.id and cr.op_node_id = o.id
          and coalesce(lower(cr.product),'') = coalesce(lower(ul_txt(r2.raw,'product')),'')
          and cr.is_assigned_handler
          and daterange(cr.effective_from, cr.effective_to, '[)')
           && daterange(ul_date(ul_txt(r2.raw,'effective_from')), ul_date(ul_txt(r2.raw,'effective_to')), '[)'));
end $function$
;

CREATE OR REPLACE FUNCTION public.uv_chairs(p_batch uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  update upload_row r set error = e.msg from (
    select r2.id, nullif(concat_ws('; ',
      case when ul_txt(r2.raw,'chair_code') is null then 'chair_code is required' end,
      case when ul_txt(r2.raw,'title') is null then 'title is required' end,
      case when lower(coalesce(ul_txt(r2.raw,'level'),'')) not in
                ('board','function','region','branch','executive','admin')
           then 'level must be board, function, region, branch, executive or admin' end,
      case when ul_txt(r2.raw,'reports_to_chair_code') is not null
            and not exists (select 1 from chair c where c.code = ul_txt(r2.raw,'reports_to_chair_code'))
            and not exists (select 1 from upload_row r3 where r3.batch_id = p_batch
                              and ul_txt(r3.raw,'chair_code') = ul_txt(r2.raw,'reports_to_chair_code'))
           then 'reports_to_chair_code ' || ul_txt(r2.raw,'reports_to_chair_code') ||
                ' is neither in this file nor already in the structure' end,
      case when ul_txt(r2.raw,'reports_to_chair_code') = ul_txt(r2.raw,'chair_code')
           then 'a chair cannot report to itself' end,
      case when lower(coalesce(ul_txt(r2.raw,'reports_daily'),'no')) not in ('yes','no','true','false')
           then 'reports_daily must be yes or no' end
    ), '') as msg
    from upload_row r2 where r2.batch_id = p_batch
  ) e where r.id = e.id and e.msg is not null;

  update upload_row r set error = coalesce(r.error || '; ', '') || 'duplicate chair_code in this file'
    from (select id, row_number() over (partition by lower(ul_txt(raw,'chair_code')) order by row_no) rn
            from upload_row where batch_id = p_batch and error is null) d
   where r.id = d.id and d.rn > 1;
end $function$
;

CREATE OR REPLACE FUNCTION public.uv_clients(p_batch uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  update upload_row set error = null where batch_id = p_batch and error is not null;

  update upload_row r set error = e.msg from (
    select r2.id, nullif(concat_ws('; ',
      case when ul_txt(r2.raw,'client_code') is null then 'client_code is required' end,
      case when ul_txt(r2.raw,'client_name') is null then 'client_name is required' end,
      case when ul_txt(r2.raw,'branch_code') is null then 'branch_code is required' end,
      case when ul_txt(r2.raw,'branch_name') is null then 'branch_name is required' end,
      case when ul_txt(r2.raw,'zone') is null then 'zone is required'
           when op_location_for(ul_txt(r2.raw,'zone')) is null
           then 'zone ' || ul_txt(r2.raw,'zone') || ' is not one of your locations. '
                || 'Configuration, Locations lists them, and that is also where '
                || 'a new one is added.' end,
      case when ul_txt(r2.raw,'status') is not null
            and upper(ul_txt(r2.raw,'status')) not in ('ACTIVE','INACTIVE')
           then 'status must be ACTIVE or INACTIVE, or left blank' end,
      case when ul_txt(r2.raw,'opened_on') is not null
            and ul_date(ul_txt(r2.raw,'opened_on')) is null
           then 'opened_on is not a date the tool can read. YYYY-MM-DD, DD-MM-YYYY and DD-MM-YY all work, or left blank' end
    ), '') as msg
    from upload_row r2 where r2.batch_id = p_batch
  ) e where r.id = e.id and e.msg is not null;

  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'this client and branch_code appear on an earlier line'
    from (select id, row_number() over (
            partition by lower(btrim(ul_txt(raw,'client_code'))),
                         lower(btrim(ul_txt(raw,'branch_code')))
            order by row_no) rn
            from upload_row where batch_id = p_batch and error is null) d
   where r.id = d.id and d.rn > 1;

  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'client_code ' || ul_txt(r.raw,'client_code') ||
         ' is given more than one client_name in this file'
    from (select lower(btrim(ul_txt(raw,'client_code'))) cc
            from upload_row where batch_id = p_batch and error is null
           group by 1
          having count(distinct lower(btrim(coalesce(ul_txt(raw,'client_name'),'')))) > 1) d
   where r.batch_id = p_batch and r.error is null
     and lower(btrim(ul_txt(r.raw,'client_code'))) = d.cc;
end $function$
;

CREATE OR REPLACE FUNCTION public.uv_collections(p_batch uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  update upload_row r set error = e.msg from (
    select r2.id, nullif(concat_ws('; ',
      case when ul_txt(r2.raw,'period') is null then 'period is required'
           when not is_ym(ul_txt(r2.raw,'period')) then 'period must be a month, written YYYY-MM' end,
      case when ul_txt(r2.raw,'client_code') is null then 'client_code is required'
           when not exists (select 1 from client c where lower(btrim(c.code)) = lower(btrim(ul_txt(r2.raw,'client_code'))))
           then 'client_code ' || ul_txt(r2.raw,'client_code') || ' does not exist - load Clients first' end,
      case when ul_txt(r2.raw,'zone') is null then 'zone is required'
           when not is_op_zone(ul_txt(r2.raw,'zone'))
           then 'zone ' || ul_txt(r2.raw,'zone') || ' is not one of your operating zones or locations - add it, or teach the spelling, under Places, coverage and owners' end,
      case when ul_txt(r2.raw,'billed') is null then 'billed is required'
           when ul_txt(r2.raw,'billed') !~ '^\d+(\.\d{1,2})?$' then 'billed must be a non-negative number' end,
      case when ul_txt(r2.raw,'collected') is null then 'collected is required'
           when ul_txt(r2.raw,'collected') !~ '^\d+(\.\d{1,2})?$' then 'collected must be a non-negative number' end
    ), '') as msg
    from upload_row r2 where r2.batch_id = p_batch
  ) e where r.id = e.id and e.msg is not null;

  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'duplicate client, zone and month in this file'
    from (select id, row_number() over (
            partition by lower(ul_txt(raw,'client_code')), lower(ul_txt(raw,'zone')), ul_txt(raw,'period')
            order by row_no) rn
            from upload_row where batch_id = p_batch and error is null) d
   where r.id = d.id and d.rn > 1;
end $function$
;

CREATE OR REPLACE FUNCTION public.uv_escalation(p_batch uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  update upload_row r set error = e.msg
    from (
      select r2.id, nullif(concat_ws('; ',
        case when nullif(btrim(r2.raw->>'client_code'),'') is not null
              and not exists (select 1 from client c where lower(btrim(c.code)) = lower(btrim(r2.raw->>'client_code')))
             then 'client_code ' || (r2.raw->>'client_code') || ' does not exist - load Clients first' end,
        case when nullif(btrim(r2.raw->>'zone'),'') is null then 'zone is required'
             when not is_op_zone(r2.raw->>'zone')
             then 'zone ' || (r2.raw->>'zone') || ' is not one of your operating zones or locations - add it, or teach the spelling, under Places, coverage and owners'
        end,
        case when nullif(btrim(r2.raw->>'branch_code'),'') is not null
              and not exists (select 1 from branch b where b.code = btrim(r2.raw->>'branch_code'))
             then 'branch_code ' || (r2.raw->>'branch_code') || ' does not exist' end,
        case when nullif(btrim(r2.raw->>'level'),'') is null then 'level is required'
             when (r2.raw->>'level') !~ '^[1-4]$' then 'level must be 1, 2, 3 or 4'
        end,
        case when nullif(btrim(r2.raw->>'person_email'),'') is null
              and nullif(btrim(r2.raw->>'chair_code'),'') is null
             then 'give a person_email or a chair_code - an escalation level with nobody in it is the gap this table exists to close' end,
        case when nullif(btrim(r2.raw->>'person_email'),'') is not null
              and not exists (select 1 from person p
                               where lower(p.work_email) = lower(btrim(r2.raw->>'person_email'))
                                 and p.employment_status = 'ACTIVE' and p.superseded_by is null)
             then 'person_email ' || (r2.raw->>'person_email') || ' is not an active person - load People first' end,
        case when nullif(btrim(r2.raw->>'chair_code'),'') is not null
              and not exists (select 1 from chair c where c.code = btrim(r2.raw->>'chair_code'))
             then 'chair_code ' || (r2.raw->>'chair_code') || ' does not exist - load Chairs first' end,
        case when nullif(btrim(r2.raw->>'sequence_no'),'') is not null
              and (r2.raw->>'sequence_no') !~ '^\d+$' then 'sequence_no must be a whole number' end
      ), '') as msg
      from upload_row r2 where r2.batch_id = p_batch
    ) e
   where r.id = e.id and e.msg is not null;

  update upload_row r set error = coalesce(r.error || '; ', '') || 'another row in this file has the same client, zone, branch, level and sequence'
    from (select id, row_number() over (
            partition by coalesce(lower(btrim(raw->>'client_code')),''),
                         lower(btrim(raw->>'zone')),
                         coalesce(lower(btrim(raw->>'branch_code')),''),
                         btrim(raw->>'level'),
                         coalesce(nullif(btrim(raw->>'sequence_no'),''),'1')
            order by row_no) rn
          from upload_row where batch_id = p_batch and error is null) d
   where r.id = d.id and d.rn > 1;
end $function$
;

CREATE OR REPLACE FUNCTION public.uv_geography(p_batch uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  update upload_row set error = null where batch_id = p_batch and error is not null;

  update upload_row r set error = e.msg from (
    select r2.id, nullif(concat_ws('; ',
      case when ul_txt(r2.raw,'region') is null
           then 'region is required - it is the top of the geography tree'
           when geo_region(ul_txt(r2.raw,'region')) is null
           then 'region must be East, West, North, South, Central or North East' end,
      case when ul_txt(r2.raw,'zone') is null then 'zone is required' end,
      case when ul_txt(r2.raw,'state') is null then 'state is required' end
    ), '') as msg
    from upload_row r2 where r2.batch_id = p_batch
  ) e where r.id = e.id and e.msg is not null;

  -- A duplicate is the same place twice. The same zone twice is the file
  -- doing its job: one row per city, many cities to a zone.
  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'the same region, state and city appear on an earlier line'
    from (select id, row_number() over (
            partition by geo_region(ul_txt(raw,'region')),
                         lower(btrim(ul_txt(raw,'state'))),
                         lower(btrim(coalesce(ul_txt(raw,'city'),'')))
            order by row_no) rn
            from upload_row where batch_id = p_batch and error is null) d
   where r.id = d.id and d.rn > 1;

  -- A state cannot sit in two regions at once, so the file has to pick one.
  update upload_row r set error = coalesce(r.error || '; ', '') ||
         ul_txt(r.raw,'state') || ' is put in more than one region by this file'
    from (select a.id from upload_row a
            join upload_row b on a.batch_id = b.batch_id and a.id <> b.id
             and lower(btrim(ul_txt(a.raw,'state'))) = lower(btrim(ul_txt(b.raw,'state')))
             and geo_region(ul_txt(a.raw,'region')) is distinct from geo_region(ul_txt(b.raw,'region'))
           where a.batch_id = p_batch and a.error is null and b.error is null) x
   where r.id = x.id;
end $function$
;

CREATE OR REPLACE FUNCTION public.uv_holidays(p_batch uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  update upload_row r set error = e.msg from (
    select r2.id, nullif(concat_ws('; ',
      case when ul_txt(r2.raw,'date') is null then 'date is required'
           when not ul_date_ok(ul_txt(r2.raw,'date')) then 'date is not a date the tool can read. YYYY-MM-DD, DD-MM-YYYY and DD-MM-YY all work' end,
      case when ul_txt(r2.raw,'name') is null then 'name is required' end,
      case when lower(coalesce(r2.raw->>'confirmed','no')) not in ('yes','no','true','false','')
           then 'confirmed must be yes or no' end
    ), '') as msg
    from upload_row r2 where r2.batch_id = p_batch
  ) e where r.id = e.id and e.msg is not null;

  update upload_row r set error = coalesce(r.error || '; ', '') || 'duplicate date in this file'
    from (select id, row_number() over (partition by raw->>'date' order by row_no) rn
            from upload_row where batch_id = p_batch and error is null) d
   where r.id = d.id and d.rn > 1;
end $function$
;

CREATE OR REPLACE FUNCTION public.uv_kpi_targets(p_batch uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  update upload_row r set error = e.msg from (
    select r2.id, nullif(concat_ws('; ',
      case when ul_txt(r2.raw,'period') is null then 'period is required'
           when not is_ym(ul_txt(r2.raw,'period')) then 'period must be a month, written YYYY-MM' end,
      case when ul_txt(r2.raw,'employee_no') is null then 'employee_no is required'
           when not exists (select 1 from person p where p.employee_no = ul_txt(r2.raw,'employee_no') and p.superseded_by is null)
           then 'employee_no ' || ul_txt(r2.raw,'employee_no') || ' is not on the people master - load People first' end,
      case when ul_txt(r2.raw,'kpi_name') is null then 'kpi_name is required' end,
      case when ul_txt(r2.raw,'target') is null then 'target is required'
           when ul_txt(r2.raw,'target') !~ '^\d+(\.\d+)?$' then 'target must be a non-negative number' end,
      case when ul_txt(r2.raw,'unit') is not null
            and lower(ul_txt(r2.raw,'unit')) not in ('count','%','score','inr lakh','rs lakh','lakh')
            and ul_txt(r2.raw,'unit') <> ''
           then 'unit must be count, %, score or a lakh unit' end
    ), '') as msg
    from upload_row r2 where r2.batch_id = p_batch
  ) e where r.id = e.id and e.msg is not null;

  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'duplicate person, KPI, sub-category and month in this file'
    from (select id, row_number() over (
            partition by lower(ul_txt(raw,'employee_no')), lower(ul_txt(raw,'kpi_name')),
                         coalesce(lower(ul_txt(raw,'sub_category')),''), ul_txt(raw,'period')
            order by row_no) rn
            from upload_row where batch_id = p_batch and error is null) d
   where r.id = d.id and d.rn > 1;

  -- "Sub-category targets must add up to the KPI target" - the template says
  -- so, so the file has to be held to it.
  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'sub-category targets for this KPI add up to ' || s.kids ||
         ', but the KPI target is ' || s.parent
    from (
      select lower(ul_txt(raw,'employee_no')) en, lower(ul_txt(raw,'kpi_name')) kn,
             ul_txt(raw,'period') pr,
             sum(case when ul_txt(raw,'sub_category') is null then 0 else ul_txt(raw,'target')::numeric end) kids,
             max(case when ul_txt(raw,'sub_category') is null then ul_txt(raw,'target')::numeric end) parent
        from upload_row where batch_id = p_batch and error is null
       group by 1,2,3
      having max(case when ul_txt(raw,'sub_category') is null then ul_txt(raw,'target')::numeric end) is not null
         and sum(case when ul_txt(raw,'sub_category') is null then 0 else ul_txt(raw,'target')::numeric end) > 0
         and sum(case when ul_txt(raw,'sub_category') is null then 0 else ul_txt(raw,'target')::numeric end)
             <> max(case when ul_txt(raw,'sub_category') is null then ul_txt(raw,'target')::numeric end)
    ) s
   where r.batch_id = p_batch and r.error is null
     and lower(ul_txt(r.raw,'employee_no')) = s.en
     and lower(ul_txt(r.raw,'kpi_name')) = s.kn
     and ul_txt(r.raw,'period') = s.pr;
end $function$
;

CREATE OR REPLACE FUNCTION public.uv_opening(p_batch uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  update upload_row r set error = e.msg from (
    select r2.id, nullif(concat_ws('; ',
      case when lower(coalesce(ul_txt(r2.raw,'record_type'),'')) not in ('escalation','ogl_assignment','claim')
           then 'record_type must be escalation, ogl_assignment or claim' end,
      case when ul_txt(r2.raw,'reference') is null then 'reference is required' end,
      case when ul_txt(r2.raw,'created_at') is null then 'created_at is required'
           when ul_txt(r2.raw,'created_at') !~ '^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2})?)?$'
                or not ul_date_ok(left(ul_txt(r2.raw,'created_at'),10))
           then 'created_at must be a real date and time, written YYYY-MM-DDTHH:MM' end,
      case when ul_txt(r2.raw,'owner_employee_no') is null then 'owner_employee_no is required'
           when not exists (select 1 from person p where p.employee_no = ul_txt(r2.raw,'owner_employee_no') and p.superseded_by is null)
           then 'owner_employee_no ' || ul_txt(r2.raw,'owner_employee_no') || ' is not on the people master' end,
      case when lower(coalesce(ul_txt(r2.raw,'record_type'),'')) = 'escalation' then
        nullif(concat_ws('; ',
          case when upper(coalesce(ul_txt(r2.raw,'current_state'),'')) not in
                    ('OPEN','IN_PROGRESS','RESOLVED','CLOSED','BLOCKED')
               then 'current_state for an escalation must be OPEN, IN_PROGRESS, RESOLVED, CLOSED or BLOCKED' end,
          case when ul_txt(r2.raw,'client_code') is null then 'client_code is required for an escalation'
               when not exists (select 1 from client c where lower(btrim(c.code)) = lower(btrim(ul_txt(r2.raw,'client_code'))))
               then 'client_code ' || ul_txt(r2.raw,'client_code') || ' does not exist' end
        ), '') end,
      case when lower(coalesce(ul_txt(r2.raw,'record_type'),'')) = 'claim' then
        nullif(concat_ws('; ',
          case when upper(coalesce(ul_txt(r2.raw,'current_state'),'')) not in
                    ('DRAFT','OPS_APPROVAL','HR_APPROVAL','ACCOUNTS','DISPUTED','PAID','REJECTED')
               then 'current_state for a claim must be DRAFT, OPS_APPROVAL, HR_APPROVAL, ACCOUNTS, DISPUTED, PAID or REJECTED' end,
          case when ul_txt(r2.raw,'amount') is not null and ul_txt(r2.raw,'amount') !~ '^\d+(\.\d{1,2})?$'
               then 'amount must be a non-negative number' end
        ), '') end,
      case when lower(coalesce(ul_txt(r2.raw,'record_type'),'')) = 'ogl_assignment' then
        nullif(concat_ws('; ',
          case when upper(coalesce(ul_txt(r2.raw,'current_state'),'')) not in
                    ('DRAFT','SUBMITTED','ASSIGNED','ACCEPTED','IN_PROGRESS','AWAITING_INFORMATION',
                     'DELAY_REVIEW','COMPLETED','UNDER_REVIEW','REWORK','ARBITRATION','CLOSED',
                     'REOPENED','CANCELLED')
               then 'current_state for an OGL assignment must be one of the fourteen states - '
                    || 'DRAFT, SUBMITTED, ASSIGNED, ACCEPTED, IN_PROGRESS, AWAITING_INFORMATION, '
                    || 'DELAY_REVIEW, COMPLETED, UNDER_REVIEW, REWORK, ARBITRATION, CLOSED, REOPENED or CANCELLED' end,
          case when ul_txt(r2.raw,'client_code') is null then 'client_code is required for an OGL assignment'
               when not exists (select 1 from client c where lower(btrim(c.code)) = lower(btrim(ul_txt(r2.raw,'client_code'))))
               then 'client_code ' || ul_txt(r2.raw,'client_code') || ' does not exist' end,
          case when ul_txt(r2.raw,'zone') is null then 'zone is required for an OGL assignment - it is the target location'
               when not is_op_zone(ul_txt(r2.raw,'zone'))
               then 'zone ' || ul_txt(r2.raw,'zone') || ' is not one of your zones or locations' end,
          case when ul_txt(r2.raw,'force1_case_id') is null
               then 'force1_case_id is required for an OGL assignment' end,
          case when ul_txt(r2.raw,'applicant_name') is null
               then 'applicant_name is required for an OGL assignment' end,
          case when ul_txt(r2.raw,'verification_type') is not null
                and not exists (select 1 from verification_type vt
                                 where upper(vt.code) = upper(ul_txt(r2.raw,'verification_type')))
               then 'verification_type ' || ul_txt(r2.raw,'verification_type')
                    || ' is not one of RESIDENT, BUSINESS, EMPLOYEE or QUOTATION' end
        ), '') end
    ), '') as msg
    from upload_row r2 where r2.batch_id = p_batch
  ) e where r.id = e.id and e.msg is not null;

  update upload_row r set error = coalesce(r.error || '; ', '') || 'duplicate reference in this file'
    from (select id, row_number() over (partition by lower(ul_txt(raw,'reference')) order by row_no) rn
            from upload_row where batch_id = p_batch and error is null) d
   where r.id = d.id and d.rn > 1;
end $function$
;

CREATE OR REPLACE FUNCTION public.uv_past_perf(p_batch uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  update upload_row r set error = e.msg from (
    select r2.id, nullif(concat_ws('; ',
      case when lower(coalesce(ul_txt(r2.raw,'file_part'),'')) not in ('mtd','revenue','collections')
           then 'file_part must be mtd, revenue or collections' end,
      case when ul_txt(r2.raw,'period') is null then 'period is required'
           when not is_ym(ul_txt(r2.raw,'period')) then 'period must be a month, written YYYY-MM' end,
      case when lower(coalesce(ul_txt(r2.raw,'file_part'),'')) = 'mtd' then
        nullif(concat_ws('; ',
          case when ul_txt(r2.raw,'employee_no') is null then 'employee_no is required for mtd'
               when not exists (select 1 from person p where p.employee_no = ul_txt(r2.raw,'employee_no') and p.superseded_by is null)
               then 'employee_no ' || ul_txt(r2.raw,'employee_no') || ' is not on the people master' end,
          case when ul_txt(r2.raw,'kpi_name') is null then 'kpi_name is required for mtd' end,
          case when ul_txt(r2.raw,'achieved') is null then 'achieved is required for mtd'
               when ul_txt(r2.raw,'achieved') !~ '^-?\d+(\.\d+)?$' then 'achieved must be a number' end,
          case when ul_txt(r2.raw,'mtd_achieved') is not null
                and ul_txt(r2.raw,'mtd_achieved') !~ '^-?\d+(\.\d+)?$' then 'mtd_achieved must be a number' end,
          case when ul_txt(r2.raw,'target') is not null
                and ul_txt(r2.raw,'target') !~ '^-?\d+(\.\d+)?$' then 'target must be a number' end
        ), '') end,
      case when lower(coalesce(ul_txt(r2.raw,'file_part'),'')) in ('revenue','collections') then
        nullif(concat_ws('; ',
          case when ul_txt(r2.raw,'client_code') is null then 'client_code is required for ' || lower(ul_txt(r2.raw,'file_part'))
               when not exists (select 1 from client c where lower(btrim(c.code)) = lower(btrim(ul_txt(r2.raw,'client_code'))))
               then 'client_code ' || ul_txt(r2.raw,'client_code') || ' does not exist' end,
          case when ul_txt(r2.raw,'location_code') is null then 'location_code is required for ' || lower(ul_txt(r2.raw,'file_part'))
               when not is_op_zone(ul_txt(r2.raw,'location_code'))
               then 'location_code ' || ul_txt(r2.raw,'location_code') || ' is not one of your zones or locations' end,
          case when ul_txt(r2.raw,'owner_employee_no') is not null
                and not exists (select 1 from person p where p.employee_no = ul_txt(r2.raw,'owner_employee_no') and p.superseded_by is null)
               then 'owner_employee_no ' || ul_txt(r2.raw,'owner_employee_no') || ' is not on the people master' end
        ), '') end,
      case when lower(coalesce(ul_txt(r2.raw,'file_part'),'')) = 'revenue' then
        nullif(concat_ws('; ',
          case when ul_txt(r2.raw,'invoiced_inr') is null then 'invoiced_inr is required for revenue'
               when ul_txt(r2.raw,'invoiced_inr') !~ '^\d+$' then 'invoiced_inr must be whole rupees, no commas' end,
          case when ul_txt(r2.raw,'realised_inr') is null then 'realised_inr is required for revenue'
               when ul_txt(r2.raw,'realised_inr') !~ '^\d+$' then 'realised_inr must be whole rupees, no commas' end
        ), '') end,
      case when lower(coalesce(ul_txt(r2.raw,'file_part'),'')) = 'collections' then
        nullif(concat_ws('; ',
          case when coalesce(ul_txt(r2.raw,'opening_outstanding_inr'),'') !~ '^\d+$' then 'opening_outstanding_inr must be whole rupees' end,
          case when coalesce(ul_txt(r2.raw,'collected_inr'),'') !~ '^\d+$' then 'collected_inr must be whole rupees' end,
          case when coalesce(ul_txt(r2.raw,'closing_outstanding_inr'),'') !~ '^\d+$' then 'closing_outstanding_inr must be whole rupees' end,
          case when ul_txt(r2.raw,'opening_outstanding_inr') ~ '^\d+$'
                and ul_txt(r2.raw,'collected_inr') ~ '^\d+$'
                and ul_txt(r2.raw,'closing_outstanding_inr') ~ '^\d+$'
                and ul_txt(r2.raw,'opening_outstanding_inr')::bigint - ul_txt(r2.raw,'collected_inr')::bigint
                    <> ul_txt(r2.raw,'closing_outstanding_inr')::bigint
               then 'opening minus collected must equal closing' end
        ), '') end
    ), '') as msg
    from upload_row r2 where r2.batch_id = p_batch
  ) e where r.id = e.id and e.msg is not null;
end $function$
;

CREATE OR REPLACE FUNCTION public.uv_people(p_batch uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_depts text;
begin
  update upload_row set error = null where batch_id = p_batch and error is not null;

  select string_agg(department, ', ' order by department) into v_depts from client_view_policy;

  update upload_row r set error = e.msg from (
    select r2.id, nullif(concat_ws('; ',
      case when ul_txt(r2.raw,'employee_no') is null then 'employee_no is required' end,
      case when ul_txt(r2.raw,'full_name') is null then 'full_name is required' end,
      case when ul_txt(r2.raw,'work_email') is null then 'work_email is required'
           when ul_txt(r2.raw,'work_email') !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$'
           then 'work_email is not a valid address' end,
      case when ul_mobile(ul_txt(r2.raw,'mobile')) is not null
            and ul_mobile(ul_txt(r2.raw,'mobile')) !~ '^[0-9]{10,13}$'
           then 'mobile must be 10 to 13 digits, or left blank' end,
      case when ul_txt(r2.raw,'chair') is null then 'chair is required'
           when not exists (select 1 from chair c
                             where c.title = ul_txt(r2.raw,'chair')
                                or c.code  = ul_txt(r2.raw,'chair'))
           then 'chair ' || ul_txt(r2.raw,'chair') || ' does not exist - load Chairs first' end,

      -- department. Written but not a department at all is always refused.
      -- Left blank is refused only for somebody the master does not already
      -- hold a department for, so a partial file need not restate it.
      case when ul_txt(r2.raw,'department') is not null
            and dept_canon(ul_txt(r2.raw,'department')) is null
           then 'department ' || ul_txt(r2.raw,'department') || ' is not one of ' || v_depts end,
      case when ul_txt(r2.raw,'department') is null
            and not exists (select 1 from person p
                             where p.employee_no = ul_txt(r2.raw,'employee_no') and p.superseded_by is null
                               and p.superseded_by is null
                               and p.department is not null)
           then 'department is required - it is what decides whether this person '
                'sees client data at all. One of ' || v_depts end,

      case when ul_txt(r2.raw,'reports_to_employee_no') is not null
            and not exists (select 1 from person p
                             where p.employee_no = ul_txt(r2.raw,'reports_to_employee_no') and p.superseded_by is null
                               and p.superseded_by is null)
            and not exists (select 1 from upload_row r3 where r3.batch_id = p_batch
                              and ul_txt(r3.raw,'employee_no') = ul_txt(r2.raw,'reports_to_employee_no'))
           then 'reports_to_employee_no ' || ul_txt(r2.raw,'reports_to_employee_no') ||
                ' is neither in this file nor already on the people master' end,
      case when ul_txt(r2.raw,'reports_to_employee_no') = ul_txt(r2.raw,'employee_no')
           then 'a person cannot report to themselves' end,
      case when ul_txt(r2.raw,'reports_to_employee_no') is null
            and exists (select 1 from chair c
                         where (c.title = ul_txt(r2.raw,'chair') or c.code = ul_txt(r2.raw,'chair'))
                           and chair_reports_to_someone(c.id))
            and not exists (select 1 from person p
                             where p.employee_no = ul_txt(r2.raw,'employee_no') and p.superseded_by is null
                               and p.superseded_by is null
                               and p.manager_id is not null)
           then 'reports_to_employee_no is required - a manager sees their team''s '
                'work through it, and nobody sees this person''s work without it. '
                'Only the person at the top of the company may leave it blank' end,

      case when ul_txt(r2.raw,'date_of_joining') is not null
            and ul_date(ul_txt(r2.raw,'date_of_joining')) is null
           then 'date_of_joining is not a date the tool can read. YYYY-MM-DD, DD-MM-YYYY and DD-MM-YY all work' end,
      case when lower(coalesce(ul_txt(r2.raw,'employment_type'),'employee'))
                not in ('employee','partner','intern','contract')
           then 'employment_type must be Employee, Partner, Intern or Contract' end
    ), '') as msg
    from upload_row r2 where r2.batch_id = p_batch
  ) e where r.id = e.id and e.msg is not null;

  update upload_row r set error = coalesce(r.error || '; ', '') || 'duplicate employee_no in this file'
    from (select id, row_number() over (partition by lower(ul_txt(raw,'employee_no')) order by row_no) rn
            from upload_row where batch_id = p_batch and error is null) d
   where r.id = d.id and d.rn > 1;

  update upload_row r set error = coalesce(r.error || '; ', '') || 'duplicate work_email in this file'
    from (select id, row_number() over (partition by lower(ul_txt(raw,'work_email')) order by row_no) rn
            from upload_row where batch_id = p_batch and error is null) d
   where r.id = d.id and d.rn > 1;

  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'mobile ' || d.mob || ' is also on line ' || d.other_row ||
         ', ' || d.other_name || ' (' || d.other_emp || ')' ||
         ' - if that is the same person, delete one of the two lines'
    from (
      select r2.id,
             ul_mobile(ul_txt(r2.raw,'mobile')) mob,
             min(r3.row_no) other_row,
             min(ul_txt(r3.raw,'full_name')) other_name,
             min(ul_txt(r3.raw,'employee_no')) other_emp
        from upload_row r2
        join upload_row r3
          on r3.batch_id = r2.batch_id and r3.id <> r2.id and r3.error is null
         and ul_mobile(ul_txt(r3.raw,'mobile')) = ul_mobile(ul_txt(r2.raw,'mobile'))
       where r2.batch_id = p_batch and r2.error is null
         and ul_mobile(ul_txt(r2.raw,'mobile')) is not null
       group by r2.id, ul_mobile(ul_txt(r2.raw,'mobile'))
    ) d
   where r.id = d.id;

  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'work_email already belongs to ' || p.full_name ||
         ' (' || p.employee_no || '), who is a different person'
    from upload_row r2
    join person p on lower(btrim(p.work_email)) = lower(btrim(ul_txt(r2.raw,'work_email')))
                 and p.superseded_by is null
   where r.id = r2.id and r2.batch_id = p_batch and r2.error is null
     and p.employee_no is not null
     and p.employee_no <> ul_txt(r2.raw,'employee_no');

  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'mobile ' || ul_mobile(ul_txt(r2.raw,'mobile')) || ' already belongs to ' ||
         p.full_name || ' (' || p.employee_no || '), who is a different person'
    from upload_row r2
    join person p on p.mobile = ul_mobile(ul_txt(r2.raw,'mobile')) and p.left_on is null
   where r.id = r2.id and r2.batch_id = p_batch and r2.error is null
     and p.employee_no is not null
     and p.employee_no <> ul_txt(r2.raw,'employee_no');

  -- A reporting line that loops has no top, so the org chart never finishes
  -- drawing and no manager's subtree ever resolves. The file can make a loop
  -- by itself -- A reports to B, B reports to A -- or by joining onto the
  -- master, where B already reports to A. Both are found by walking the line
  -- upward from every row in the file, reading the file wherever the file
  -- names that person and the master everywhere else, which is exactly the
  -- picture that would exist after apply.
  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'the reporting line from ' || ul_txt(r.raw,'employee_no') ||
         ' comes back round to ' || ul_txt(r.raw,'employee_no') ||
         ' - somebody in that chain has the wrong manager'
    from (
      with recursive edge as (
        select ul_txt(x.raw,'employee_no') emp, ul_txt(x.raw,'reports_to_employee_no') mgr
          from upload_row x
         where x.batch_id = p_batch and ul_txt(x.raw,'employee_no') is not null
        union
        select p.employee_no, m.employee_no
          from person p join person m on m.id = p.manager_id
         where p.superseded_by is null and m.superseded_by is null
           and p.employee_no is not null and m.employee_no is not null
           and not exists (select 1 from upload_row x2 where x2.batch_id = p_batch
                             and ul_txt(x2.raw,'employee_no') = p.employee_no)
      ), walk as (
        select e.emp as start_emp, e.mgr as at, 1 as depth
          from edge e
         where e.mgr is not null
           and exists (select 1 from upload_row x3 where x3.batch_id = p_batch
                         and ul_txt(x3.raw,'employee_no') = e.emp)
        union all
        select w.start_emp, e.mgr, w.depth + 1
          from walk w join edge e on e.emp = w.at
         where e.mgr is not null and w.depth < 60 and w.at <> w.start_emp
      )
      select distinct start_emp from walk where at = start_emp
    ) c
   where r.batch_id = p_batch and r.error is null
     and ul_txt(r.raw,'employee_no') = c.start_emp;

  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'work_email domain ' || split_part(ul_txt(r.raw,'work_email'),'@',2) ||
         ' looks like a misspelling of ' || m.common_domain ||
         ' - correct it, or load it alone if it is genuinely a different domain'
    from (
      select (select lower(split_part(ul_txt(x.raw,'work_email'),'@',2)) as d
                from upload_row x where x.batch_id = p_batch and x.error is null
               group by 1 order by count(*) desc, 1 limit 1) as common_domain
    ) m
   where r.batch_id = p_batch and r.error is null
     and m.common_domain is not null
     and lower(split_part(ul_txt(r.raw,'work_email'),'@',2)) <> m.common_domain
     and extensions.levenshtein(lower(split_part(ul_txt(r.raw,'work_email'),'@',2)), m.common_domain) between 1 and 2;
end $function$
;

CREATE OR REPLACE FUNCTION public.uv_rates(p_batch uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  update upload_row r set error = e.msg from (
    select r2.id, nullif(concat_ws('; ',
      case when ul_txt(r2.raw,'client_code') is null then 'client_code is required'
           when not exists (select 1 from client c
                             where lower(btrim(c.code)) = lower(btrim(ul_txt(r2.raw,'client_code'))))
           then 'client_code ' || ul_txt(r2.raw,'client_code')
                || ' does not exist - load Clients first' end,
      case when ul_txt(r2.raw,'zone') is not null and not is_op_zone(ul_txt(r2.raw,'zone'))
           then 'zone ' || ul_txt(r2.raw,'zone') || ' is not one of your operating zones or '
                || 'locations - add it, or teach the spelling, under Places, coverage and owners' end,
      case when ul_txt(r2.raw,'rate') is null then 'rate is required'
           when ul_txt(r2.raw,'rate') !~ '^\d+(\.\d{1,2})?$'
           then 'rate must be a non-negative number with at most two decimals' end,
      case when ul_txt(r2.raw,'effective_from') is null then 'effective_from is required'
           when ul_date(ul_txt(r2.raw,'effective_from')) is null
           then 'effective_from is not a date the tool can read. YYYY-MM-DD, DD-MM-YYYY '
                || 'and DD-MM-YY all work' end,
      case when ul_txt(r2.raw,'effective_to') is not null
            and ul_date(ul_txt(r2.raw,'effective_to')) is null
           then 'effective_to is not a date the tool can read. YYYY-MM-DD, DD-MM-YYYY and '
                || 'DD-MM-YY all work, or left blank' end,
      case when ul_date(ul_txt(r2.raw,'effective_to')) is not null
            and ul_date(ul_txt(r2.raw,'effective_from')) is not null
            and ul_date(ul_txt(r2.raw,'effective_to')) <= ul_date(ul_txt(r2.raw,'effective_from'))
           then 'effective_to must be after effective_from' end
    ), '') as msg
    from upload_row r2 where r2.batch_id = p_batch
  ) e where r.id = e.id and e.msg is not null;

  -- an exact repeat of an earlier line
  with rows as (
    select id, row_no,
           lower(btrim(coalesce(ul_txt(raw,'client_code'),''))) as cc,
           coalesce(op_zone_id(ul_txt(raw,'zone'))::text,'') as zid,
           ul_date(ul_txt(raw,'effective_from')) as dfrom,
           ul_date(ul_txt(raw,'effective_to')) as dto,
           coalesce(btrim(ul_txt(raw,'rate')),'') as rate
      from upload_row where batch_id = p_batch and error is null
  ), dup as (
    select id, row_no,
           min(row_no) over (partition by cc, zid, dfrom, dto, rate) as first_at
      from rows
  )
  update upload_row r
     set error = coalesce(r.error || '; ', '') ||
                 'identical to line ' || dup.first_at || ' of this file'
    from dup where r.id = dup.id and dup.row_no > dup.first_at;

  -- and a genuine clash: same client, same PLACE once resolved, periods that
  -- intersect. Named, so the reader knows which two lines to look at.
  with rows as (
    select id, row_no,
           lower(btrim(coalesce(ul_txt(raw,'client_code'),''))) as cc,
           coalesce(op_zone_id(ul_txt(raw,'zone'))::text,'') as zid,
           daterange(ul_date(ul_txt(raw,'effective_from')),
                     ul_date(ul_txt(raw,'effective_to')), '[)') as period
      from upload_row where batch_id = p_batch and error is null
  ), clash as (
    select a.id, min(b.row_no) as other
      from rows a join rows b
        on a.id <> b.id and a.cc = b.cc and a.zid = b.zid and a.period && b.period
     group by a.id
  )
  update upload_row r
     set error = coalesce(r.error || '; ', '') ||
                 'its dates overlap line ' || clash.other
                 || ', which prices the same client and place'
    from clash where r.id = clash.id;
end $function$
;

CREATE OR REPLACE FUNCTION public.uv_sla_rules(p_batch uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  update upload_row r set error = e.msg
    from (
      select r2.id, nullif(concat_ws('; ',
        case when nullif(btrim(r2.raw->>'code'),'') is null then 'code is required' end,
        case when nullif(btrim(r2.raw->>'client_code'),'') is not null
              and not exists (select 1 from client c where lower(btrim(c.code)) = lower(btrim(r2.raw->>'client_code')))
             then 'client_code ' || (r2.raw->>'client_code') || ' does not exist - load Clients first' end,
        case when nullif(btrim(r2.raw->>'verification_type'),'') is not null
              and not exists (select 1 from verification_type t
                               where t.code = upper(btrim(r2.raw->>'verification_type')))
             then 'verification_type must be RESIDENT, BUSINESS, EMPLOYEE or QUOTATION' end,
        case when nullif(btrim(r2.raw->>'zone'),'') is not null
              and not is_op_zone(r2.raw->>'zone')
             then 'zone ' || (r2.raw->>'zone') || ' is not one of your operating zones or locations - add it, or teach the spelling, under Places, coverage and owners' end,
        case when nullif(btrim(r2.raw->>'tat_business_minutes'),'') is null then 'tat_business_minutes is required'
             when (r2.raw->>'tat_business_minutes') !~ '^\d+$' then 'tat_business_minutes must be a whole number of minutes'
             when (r2.raw->>'tat_business_minutes')::int < 1 then 'tat_business_minutes must be at least 1'
             when (r2.raw->>'tat_business_minutes')::int > 100000 then 'tat_business_minutes over 100000 is almost certainly clock minutes, not business minutes'
        end,
        case when nullif(btrim(r2.raw->>'grace_minutes'),'') is not null
              and (r2.raw->>'grace_minutes') !~ '^\d+$' then 'grace_minutes must be a whole number' end,
        case when nullif(btrim(r2.raw->>'at_risk_pct'),'') is not null
              and ((r2.raw->>'at_risk_pct') !~ '^\d+$' or (r2.raw->>'at_risk_pct')::int not between 1 and 99)
             then 'at_risk_pct must be between 1 and 99' end,
        case when nullif(btrim(r2.raw->>'effective_from'),'') is null then 'effective_from is required'
             when not ul_date_ok(btrim(r2.raw->>'effective_from')) then 'effective_from is not a date the tool can read. YYYY-MM-DD, DD-MM-YYYY and DD-MM-YY all work'
        end,
        case when nullif(btrim(r2.raw->>'effective_to'),'') is not null
              and ul_date(btrim(r2.raw->>'effective_to')) is null
             then 'effective_to is not a date the tool can read. YYYY-MM-DD, DD-MM-YYYY and DD-MM-YY all work, or left blank' end,
        case when nullif(btrim(r2.raw->>'effective_to'),'') is not null
              and ul_date_ok(btrim(r2.raw->>'effective_to')) and ul_date_ok(btrim(r2.raw->>'effective_from'))
              and ul_date(r2.raw->>'effective_to') <= ul_date(r2.raw->>'effective_from')
             then 'effective_to must be after effective_from' end
      ), '') as msg
      from upload_row r2 where r2.batch_id = p_batch
    ) e
   where r.id = e.id and e.msg is not null;

  -- two rows in one file with the same code and the same start date would
  -- become two versions of the same thing on the same day
  update upload_row r set error = coalesce(r.error || '; ', '') || 'another row in this file has the same code and effective_from'
    from (select id, row_number() over (partition by btrim(raw->>'code'), btrim(raw->>'effective_from')
                                        order by row_no) rn
            from upload_row where batch_id = p_batch and error is null) d
   where r.id = d.id and d.rn > 1;
end $function$
;

CREATE OR REPLACE FUNCTION public.wa_bridge_by_token(p_token text)
 RETURNS wa_bridge
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select * from wa_bridge
   where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
     and disabled_at is null
   limit 1
$function$
;

CREATE OR REPLACE FUNCTION public.wa_bridge_claim(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  b wa_bridge;
  v_gap int; v_jit int; v_burst int; v_per_device int; v_stale int;
  v_global_cap int; v_global_sent int; v_room int; v_wait int;
  v_rows jsonb;
begin
  select * into b from wa_bridge_by_token(p_token);
  if b.id is null then return jsonb_build_object('error','unknown_device'); end if;

  v_gap        := coalesce(nullif((select value from app_setting where key='whatsapp_web_gap_seconds'),''),'14')::int;
  v_jit        := coalesce(nullif((select value from app_setting where key='whatsapp_web_jitter_seconds'),''),'9')::int;
  v_burst      := coalesce(nullif((select value from app_setting where key='whatsapp_web_burst'),''),'4')::int;
  v_per_device := coalesce(nullif((select value from app_setting where key='whatsapp_web_daily_per_device'),''),'180')::int;
  v_stale      := coalesce(nullif((select value from app_setting where key='whatsapp_web_stale_seconds'),''),'150')::int;

  update wa_bridge set last_seen_at = now() where id = b.id;

  if b.state <> 'READY' then
    return jsonb_build_object('messages','[]'::jsonb,'state',b.state,
      'gapSeconds',v_gap,'jitterSeconds',v_jit,
      'reason','not_linked');
  end if;

  -- the day rolls over on its own
  if b.sent_day is distinct from current_date then
    update wa_bridge set sent_day = current_date, sent_today = 0 where id = b.id;
    b.sent_today := 0;
  end if;

  -- do not send faster than a person plausibly would
  v_wait := greatest(0, v_gap - extract(epoch from (now() - coalesce(b.last_sent_at, 'epoch'::timestamptz)))::int);
  if v_wait > 0 then
    return jsonb_build_object('messages','[]'::jsonb,'state','READY',
      'gapSeconds',v_gap,'jitterSeconds',v_jit,'waitSeconds',v_wait,'reason','pacing');
  end if;

  v_global_cap  := coalesce(nullif((select value from app_setting where key='whatsapp_daily_cap'),''),'1000')::int;
  insert into wa_budget (day, cap) values (current_date, v_global_cap)
    on conflict (day) do nothing;
  select recipients_sent into v_global_sent from wa_budget where day = current_date;

  v_room := least(v_burst, v_per_device - b.sent_today, v_global_cap - coalesce(v_global_sent,0));
  if v_room <= 0 then
    return jsonb_build_object('messages','[]'::jsonb,'state','READY',
      'gapSeconds',v_gap,'jitterSeconds',v_jit,'reason','daily_cap_reached');
  end if;

  with picked as (
    update wa_outbox o set attempts = o.attempts + 1, bridge_id = b.id
     where o.id in (
       select id from wa_outbox
        where state = 'QUEUED' and not_before <= now()
        order by not_before
        limit v_room
        for update skip locked)
    returning o.id, o.recipient, o.body, o.template_key)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'to', recipient, 'body', body, 'template', template_key)), '[]'::jsonb)
    into v_rows from picked;

  return jsonb_build_object('messages', v_rows, 'state','READY',
    'gapSeconds', v_gap, 'jitterSeconds', v_jit);
end $function$
;

CREATE OR REPLACE FUNCTION public.wa_bridge_create(p_actor uuid, p_name text, p_kind text DEFAULT 'laptop'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_token text; v_id uuid;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Adding a sending device is an administrator''s to do.');
  end if;
  if coalesce(trim(p_name),'') = '' then
    return jsonb_build_object('error','no_name',
      'reason','Give the device a name you will recognise later.');
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into wa_bridge (name, device_kind, token_hash, created_by)
  values (trim(p_name), coalesce(nullif(p_kind,''),'laptop'),
          encode(extensions.digest(v_token, 'sha256'), 'hex'), p_actor)
  returning id into v_id;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'WA_BRIDGE_CREATED', 'wa_bridge', v_id::text,
          jsonb_build_object('name', trim(p_name), 'kind', p_kind));

  -- the only time the token is ever readable
  return jsonb_build_object('id', v_id, 'token', v_token, 'name', trim(p_name));
end $function$
;

CREATE OR REPLACE FUNCTION public.wa_bridge_disable(p_actor uuid, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; b wa_bridge;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Retiring a sending device is an administrator''s to do.');
  end if;

  select * into b from wa_bridge where id = p_id;
  if b.id is null then return jsonb_build_object('error','no_such_device'); end if;

  update wa_bridge set disabled_at = now(), state = 'DISABLED',
                       qr_payload = null, token_hash = 'retired:' || id::text
   where id = p_id;

  -- anything it was holding goes back to the queue for another device
  update wa_outbox set state = 'QUEUED', not_before = now()
   where bridge_id = p_id and state = 'QUEUED';

  perform ops_alert_resolve('wa_bridge_down:' || p_id::text, 'The device was retired.');
  perform ops_alert_resolve('wa_bridge_qr:'   || p_id::text, 'The device was retired.');

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'WA_BRIDGE_DISABLED', 'wa_bridge', p_id::text,
          jsonb_build_object('name', b.name));

  return jsonb_build_object('ok', true, 'name', b.name);
end $function$
;

CREATE OR REPLACE FUNCTION public.wa_bridge_heartbeat(p_token text, p_state text, p_phone text DEFAULT NULL::text, p_detail text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b wa_bridge; v_retry int; v_was text;
begin
  select * into b from wa_bridge_by_token(p_token);
  if b.id is null then
    return jsonb_build_object('error','unknown_device');
  end if;
  v_was := b.state;
  v_retry := coalesce(nullif((select value from app_setting
                               where key='whatsapp_web_retry_minutes'),''),'5')::int;

  update wa_bridge set
    state        = case when p_state in ('NEEDS_QR','READY','STALE') then p_state else state end,
    phone_number = coalesce(nullif(p_phone,''), phone_number),
    last_seen_at = now(),
    qr_payload   = case when p_state = 'READY' then null else qr_payload end,
    qr_image     = case when p_state = 'READY' then null else qr_image end,
    note         = coalesce(p_detail, note)
   where id = b.id;

  if p_state <> v_was then
    insert into wa_bridge_event (bridge_id, kind, detail)
    values (b.id, p_state, p_detail);
  end if;

  if p_state = 'READY' then
    perform ops_alert_resolve('wa_bridge_down:' || b.id::text, 'The device reconnected.');
    perform ops_alert_resolve('wa_bridge_qr:'   || b.id::text, 'The code was scanned.');
  elsif p_state = 'STALE' then
    perform ops_alert_raise(
      'WHATSAPP_BRIDGE_DOWN',
      'WhatsApp sending device "' || b.name || '" has dropped its link',
      'wa_bridge_down:' || b.id::text,
      'URGENT',
      coalesce(p_detail, 'The device lost its WhatsApp session.'),
      'It will reattempt by itself. If it keeps failing, open the device and '
      'check it is running and online. Messages are held meanwhile, not lost.',
      now() + make_interval(mins => v_retry),
      'wa_bridge', b.id);
  end if;

  return jsonb_build_object('ok', true, 'state', p_state,
    'retryMinutes', v_retry,
    'gapSeconds', coalesce(nullif((select value from app_setting where key='whatsapp_web_gap_seconds'),''),'14')::int,
    'jitterSeconds', coalesce(nullif((select value from app_setting where key='whatsapp_web_jitter_seconds'),''),'9')::int);
end $function$
;

CREATE OR REPLACE FUNCTION public.wa_bridge_peek_qr(p_actor uuid, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; b wa_bridge;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Linking a sending device is an administrator''s to do.');
  end if;

  select * into b from wa_bridge where id = p_id and disabled_at is null;
  if b.id is null then return jsonb_build_object('error','no_such_device'); end if;

  return jsonb_build_object(
    'id', b.id, 'name', b.name, 'state', b.state,
    'qr', b.qr_payload, 'image', b.qr_image,
    'age', case when b.last_qr_at is null then null
                else extract(epoch from (now() - b.last_qr_at))::int end,
    'lastSeen', b.last_seen_at);
end $function$
;

CREATE OR REPLACE FUNCTION public.wa_bridge_qr(p_token text, p_qr text, p_qr_image text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b wa_bridge;
begin
  select * into b from wa_bridge_by_token(p_token);
  if b.id is null then return jsonb_build_object('error','unknown_device'); end if;

  update wa_bridge set qr_payload = p_qr, qr_image = p_qr_image, last_qr_at = now(),
                       state = 'NEEDS_QR', last_seen_at = now()
   where id = b.id;

  insert into wa_bridge_event (bridge_id, kind, detail) values (b.id, 'NEEDS_QR', null);

  perform ops_alert_raise(
    'WHATSAPP_QR',
    'Scan the WhatsApp code for "' || b.name || '"',
    'wa_bridge_qr:' || b.id::text,
    'URGENT',
    'The device is waiting to be linked and cannot send until it is.',
    'Open the WhatsApp screen and press "Show the code", then on the phone that '
    'owns the company number: WhatsApp, Settings, Linked devices, Link a device. '
    'The code changes every minute or so.',
    null, 'wa_bridge', b.id);

  return jsonb_build_object('ok', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.wa_bridge_result(p_token text, p_id uuid, p_ok boolean, p_provider_msg_id text DEFAULT NULL::text, p_error text DEFAULT NULL::text, p_permanent boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b wa_bridge; v_retry int; v_attempts int;
begin
  select * into b from wa_bridge_by_token(p_token);
  if b.id is null then return jsonb_build_object('error','unknown_device'); end if;

  v_retry := coalesce(nullif((select value from app_setting
                               where key='whatsapp_web_retry_minutes'),''),'5')::int;

  if p_ok then
    perform wa_sent(p_id, p_provider_msg_id);
    update wa_bridge set sent_today = sent_today + 1, sent_day = current_date,
                         last_sent_at = now(), last_seen_at = now()
     where id = b.id;
    return jsonb_build_object('ok', true);
  end if;

  select attempts into v_attempts from wa_outbox where id = p_id;
  if p_permanent or v_attempts >= 5 then
    update wa_outbox set state='ABANDONED', last_error=p_error where id = p_id;
  else
    update wa_outbox set state='QUEUED', last_error=p_error,
           not_before = now() + make_interval(mins => v_retry)
     where id = p_id;
  end if;
  update wa_bridge set last_seen_at = now() where id = b.id;
  insert into wa_bridge_event (bridge_id, kind, detail) values (b.id, 'SEND_FAILED', p_error);
  return jsonb_build_object('ok', false, 'retryMinutes', v_retry);
end $function$
;

CREATE OR REPLACE FUNCTION public.wa_bridge_sweep()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_stale int; n int := 0; r record; v_retry int;
begin
  v_stale := coalesce(nullif((select value from app_setting where key='whatsapp_web_stale_seconds'),''),'150')::int;
  v_retry := coalesce(nullif((select value from app_setting where key='whatsapp_web_retry_minutes'),''),'5')::int;

  for r in
    select * from wa_bridge
     where disabled_at is null and state in ('READY','NEEDS_QR')
       and (last_seen_at is null or last_seen_at < now() - make_interval(secs => v_stale))
  loop
    update wa_bridge set state = 'STALE' where id = r.id;
    insert into wa_bridge_event (bridge_id, kind, detail)
    values (r.id, 'STALE', 'Stopped checking in.');
    perform ops_alert_raise(
      'WHATSAPP_BRIDGE_DOWN',
      'WhatsApp sending device "' || r.name || '" has stopped responding',
      'wa_bridge_down:' || r.id::text,
      'URGENT',
      'It last checked in ' || coalesce(to_char(r.last_seen_at, 'DD Mon HH24:MI'), 'never') || '.',
      'Open that device and check the bridge is running and online. Messages are '
      'held in the queue meanwhile, not lost.',
      now() + make_interval(mins => v_retry),
      'wa_bridge', r.id);
    n := n + 1;
  end loop;
  return n;
end $function$
;

CREATE OR REPLACE FUNCTION public.wa_bridges_live()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select count(*)::int from wa_bridge
   where state = 'READY' and disabled_at is null
     and last_seen_at > now() - make_interval(secs =>
       coalesce(nullif((select value from app_setting where key='whatsapp_web_stale_seconds'),''),'150')::int)
$function$
;

CREATE OR REPLACE FUNCTION public.wa_claim(p_limit integer DEFAULT 25)
 RETURNS SETOF wa_outbox
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_cap int; v_sent int; v_room int;
begin
  -- whatsapp_web is pulled by the linked device, not pushed from here
  if coalesce((select value from app_setting where key='whatsapp_provider'),'') = 'whatsapp_web' then
    return;
  end if;
  if not (wa_status()->>'ready')::boolean then
    return;
  end if;

  insert into wa_budget (day, cap)
  values (current_date,
          coalesce(nullif((select value from app_setting where key='whatsapp_daily_cap'),''),'1000')::int)
  on conflict (day) do nothing;

  select cap, recipients_sent into v_cap, v_sent from wa_budget where day = current_date;
  v_room := greatest(v_cap - v_sent, 0);
  if v_room = 0 then return; end if;

  return query
  update wa_outbox o set attempts = o.attempts + 1
   where o.id in (
     select id from wa_outbox
      where state = 'QUEUED' and not_before <= now()
      order by not_before
      limit least(p_limit, v_room)
      for update skip locked)
  returning o.*;
end $function$
;

CREATE OR REPLACE FUNCTION public.wa_configure(p_actor uuid, p_provider text DEFAULT NULL::text, p_from text DEFAULT NULL::text, p_account text DEFAULT NULL::text, p_token text DEFAULT NULL::text, p_cap text DEFAULT NULL::text, p_country_code text DEFAULT NULL::text, p_mirror text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_changed text[] := '{}';
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','WhatsApp settings are an administrator''s to change.');
  end if;

  if p_provider is not null then
    if p_provider <> '' and p_provider not in ('meta','twilio','whatsapp_web') then
      return jsonb_build_object('error','unknown_provider',
        'reason','Known providers are meta, twilio and whatsapp_web.');
    end if;
    update app_setting set value = p_provider, updated_by = p_actor, updated_at = now()
     where key = 'whatsapp_provider';
    v_changed := array_append(v_changed, 'provider');
  end if;

  if p_from is not null then
    update app_setting set value = p_from, updated_by = p_actor, updated_at = now()
     where key = 'whatsapp_from';
    v_changed := array_append(v_changed, 'from');
  end if;

  if p_account is not null then
    update app_setting set value = p_account, updated_by = p_actor, updated_at = now()
     where key = 'whatsapp_account';
    v_changed := array_append(v_changed, 'account');
  end if;

  if coalesce(p_token,'') <> '' then
    update app_setting set value = p_token, updated_by = p_actor, updated_at = now()
     where key = 'whatsapp_token';
    v_changed := array_append(v_changed, 'token');
  end if;

  if p_country_code is not null and p_country_code ~ '^\d{1,4}$' then
    update app_setting set value = p_country_code, updated_by = p_actor, updated_at = now()
     where key = 'whatsapp_country_code';
    v_changed := array_append(v_changed, 'country_code');
  end if;

  if p_mirror is not null then
    update app_setting set value = coalesce(nullif(trim(p_mirror),''),'all'),
           updated_by = p_actor, updated_at = now()
     where key = 'whatsapp_mirror';
    v_changed := array_append(v_changed, 'mirror');
  end if;

  if p_cap is not null and p_cap ~ '^\d+$' then
    update app_setting set value = p_cap, updated_by = p_actor, updated_at = now()
     where key = 'whatsapp_daily_cap';
    insert into wa_budget (day, cap) values (current_date, p_cap::int)
      on conflict (day) do update set cap = excluded.cap;
    v_changed := array_append(v_changed, 'cap');
  end if;

  update app_setting set value =
    case when (wa_status()->>'ready')::boolean then 'Connected' else 'Not connected' end
   where key = 'whatsapp';

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'WHATSAPP_CONFIGURED', 'app_setting', 'whatsapp',
          jsonb_build_object('changed', v_changed));

  return wa_status() || jsonb_build_object('changed', to_jsonb(v_changed));
end $function$
;

CREATE OR REPLACE FUNCTION public.wa_e164(p text, p_cc text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  with d as (
    select regexp_replace(regexp_replace(coalesce(p,''), '\.0+$', ''), '[^0-9]', '', 'g') as n
  )
  select case
    when d.n = '' then null
    -- already carries a country code
    when length(d.n) between 11 and 15 and left(d.n,2) = coalesce(nullif(p_cc,''),'91') then '+' || d.n
    when length(d.n) between 11 and 15 and left(d.n,1) = '0'
      then '+' || coalesce(nullif(p_cc,''),'91') || ltrim(d.n, '0')
    when length(d.n) = 10 then '+' || coalesce(nullif(p_cc,''),'91') || d.n
    when length(d.n) between 11 and 15 then '+' || d.n
    else null
  end
  from d
$function$
;

CREATE OR REPLACE FUNCTION public.wa_enqueue(p_template text, p_recipient text, p_body text, p_entity_type text DEFAULT NULL::text, p_entity_id uuid DEFAULT NULL::uuid, p_not_before timestamp with time zone DEFAULT now(), p_scope text DEFAULT NULL::text, p_template_name text DEFAULT NULL::text, p_template_vars jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_to text; v_key text; v_id uuid;
begin
  if coalesce(trim(p_body),'') = '' then
    return jsonb_build_object('queued', false, 'reason', 'no_body',
      'detail', 'A queued message must carry the text a person will read.');
  end if;

  v_to := wa_e164(p_recipient,
           (select value from app_setting where key = 'whatsapp_country_code'));
  if v_to is null then
    return jsonb_build_object('queued', false, 'reason', 'no_number',
      'detail', 'There is no usable mobile number for this recipient.');
  end if;

  v_key := p_template || '|' || v_to || '|' || coalesce(p_entity_type,'') || '|' ||
           coalesce(p_entity_id::text,'') || '|' || coalesce(p_scope,'');

  insert into wa_outbox (idempotency_key, template_key, entity_type, entity_id,
                         recipient, body, not_before, template_name, template_vars)
  values (v_key, p_template, p_entity_type, p_entity_id,
          v_to, p_body, coalesce(p_not_before, now()), p_template_name, p_template_vars)
  on conflict (idempotency_key) do nothing
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('queued', false, 'reason', 'already_queued',
      'detail', 'This message is already in the queue for this recipient.');
  end if;
  return jsonb_build_object('queued', true, 'id', v_id, 'to', v_to);
end $function$
;

CREATE OR REPLACE FUNCTION public.wa_failed(p_id uuid, p_error text, p_permanent boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_attempts int;
begin
  select attempts into v_attempts from wa_outbox where id = p_id;
  if p_permanent or v_attempts >= 5 then
    update wa_outbox set state = 'ABANDONED', last_error = p_error where id = p_id;
  else
    update wa_outbox set state = 'QUEUED', last_error = p_error,
                         not_before = now() + (interval '1 minute' * power(3, v_attempts))
     where id = p_id;
  end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.wa_forget_secrets(p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','WhatsApp settings are an administrator''s to change.');
  end if;
  update app_setting set value = '', updated_by = p_actor, updated_at = now()
   where key = 'whatsapp_token';
  update app_setting set value = 'Not connected' where key = 'whatsapp';
  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'WHATSAPP_SECRETS_FORGOTTEN', 'app_setting', 'whatsapp', '{}'::jsonb);
  return wa_status();
end $function$
;

CREATE OR REPLACE FUNCTION public.wa_sent(p_id uuid, p_provider_msg_id text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update wa_outbox set state = 'SENT', sent_at = now(), last_error = null,
                       provider_msg_id = p_provider_msg_id
   where id = p_id;
  insert into wa_budget (day, recipients_sent, cap)
  values (current_date, 1,
          coalesce(nullif((select value from app_setting where key='whatsapp_daily_cap'),''),'1000')::int)
  on conflict (day) do update set recipients_sent = wa_budget.recipients_sent + 1;
end $function$
;

CREATE OR REPLACE FUNCTION public.wa_set_mirror(p_actor uuid, p_mirror text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','WhatsApp settings are an administrator''s to change.');
  end if;
  update app_setting set value = coalesce(nullif(trim(p_mirror),''),'all'),
         updated_by = p_actor, updated_at = now()
   where key = 'whatsapp_mirror';
  return wa_status();
end $function$
;

CREATE OR REPLACE FUNCTION public.wa_settings()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from app_setting
   where key in ('whatsapp_provider','whatsapp_from','whatsapp_account',
                 'whatsapp_token','whatsapp_daily_cap','whatsapp_country_code')
$function$
;

CREATE OR REPLACE FUNCTION public.wa_status()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with s as (select key, value from app_setting where key like 'whatsapp%'),
  p as (select coalesce(nullif((select value from s where key='whatsapp_provider'), ''), '') as provider)
  select jsonb_build_object(
    'provider',  nullif((select provider from p), ''),
    'from',      nullif((select value from s where key='whatsapp_from'), ''),
    'account',   nullif((select value from s where key='whatsapp_account'), ''),
    'countryCode', coalesce(nullif((select value from s where key='whatsapp_country_code'),''), '91'),
    'mirror',    coalesce(nullif((select value from s where key='whatsapp_mirror'),''), 'all'),
    'tokenSet',  coalesce(nullif((select value from s where key='whatsapp_token'), ''), '') <> '',
    'cap',       coalesce(nullif((select value from s where key='whatsapp_daily_cap'),''),'1000')::int,
    -- staff only. A client contact is reached through the matrix, one branch
    -- at a time, never through a broadcast to everybody with a number.
    'reachable', (select count(*) from person
                   where superseded_by is null and mobile is not null
                     and coalesce(employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'),
    'contactsNotCounted', (select count(*) from person
                            where superseded_by is null and mobile is not null
                              and employee_type = 'CLIENT_CONTACT'),
    'devices',   (select provider from p) = 'whatsapp_web',
    'bridgesLive', wa_bridges_live(),
    'bridges',   coalesce((select jsonb_agg(jsonb_build_object(
                    'id', b.id, 'name', b.name, 'kind', b.device_kind,
                    'state', b.state, 'phone', b.phone_number,
                    'lastSeen', b.last_seen_at, 'sentToday', b.sent_today,
                    'hasQr', b.qr_payload is not null)
                  order by b.created_at)
                  from wa_bridge b where b.disabled_at is null), '[]'::jsonb),
    'pacing',    jsonb_build_object(
                   'gapSeconds',    coalesce(nullif((select value from s where key='whatsapp_web_gap_seconds'),''),'14')::int,
                   'jitterSeconds', coalesce(nullif((select value from s where key='whatsapp_web_jitter_seconds'),''),'9')::int,
                   'perDevice',     coalesce(nullif((select value from s where key='whatsapp_web_daily_per_device'),''),'180')::int,
                   'retryMinutes',  coalesce(nullif((select value from s where key='whatsapp_web_retry_minutes'),''),'5')::int),
    'ready',     case (select provider from p)
                   when '' then false
                   when 'whatsapp_web' then wa_bridges_live() > 0
                   else coalesce(nullif((select value from s where key='whatsapp_from'), ''), '') <> ''
                    and coalesce(nullif((select value from s where key='whatsapp_token'), ''), '') <> ''
                 end,
    'queued',    (select count(*) from wa_outbox where state='QUEUED'),
    'deferred',  (select count(*) from wa_outbox where state='DEFERRED'),
    'abandoned', (select count(*) from wa_outbox where state='ABANDONED'),
    'sent',      (select count(*) from wa_outbox where state='SENT'),
    'sentToday', coalesce((select recipients_sent from wa_budget where day = current_date), 0),
    'lastError', (select last_error from wa_outbox
                   where last_error is not null order by created_at desc limit 1),
    'recent',    coalesce((select jsonb_agg(r order by r->>'created_at' desc) from (
                   select jsonb_build_object(
                     'template_key', o.template_key, 'recipient', o.recipient,
                     'state', o.state, 'attempts', o.attempts, 'sent_at', o.sent_at,
                     'last_error', o.last_error, 'created_at', o.created_at) as r
                   from wa_outbox o order by o.created_at desc limit 10) q), '[]'::jsonb)
  )
$function$
;

CREATE OR REPLACE FUNCTION public.wa_test(p_actor uuid, p_to text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_to text; v_out jsonb;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Sending a test is an administrator''s to do.');
  end if;

  v_to := coalesce(nullif(trim(p_to), ''), (select mobile from person where id = p_actor));
  if wa_e164(v_to, (select value from app_setting where key='whatsapp_country_code')) is null then
    return jsonb_build_object('error','no_number',
      'reason','Give a mobile number to send the test to. Your own person record has none.');
  end if;

  -- a test must be sendable more than once, so its key carries the minute
  v_out := wa_enqueue('TEST', v_to,
    'Crux test message. If you are reading this, WhatsApp is connected and working.',
    'app_setting', null, now(), to_char(now(), 'YYYY-MM-DD HH24:MI:SS'));

  if not (v_out->>'queued')::boolean then
    return jsonb_build_object('error', v_out->>'reason', 'reason', v_out->>'detail');
  end if;
  return v_out;
end $function$
;

CREATE OR REPLACE FUNCTION public.working_hours_after(p_from timestamp with time zone, p_hours numeric)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select working_hours_after(p_from, p_hours, null::text);
$function$
;

CREATE OR REPLACE FUNCTION public.working_hours_after(p_from timestamp with time zone, p_hours numeric, p_centre text)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  cur     timestamptz := p_from;
  left_   numeric     := p_hours;
  open_h  int := coalesce((select split_part(value, ':', 1)::int from app_setting where key = 'day_start'), 10);
  close_h int := coalesce((select split_part(value, ':', 1)::int from app_setting where key = 'day_end'), 19);
  sat_h   numeric := pms_cfg('sat_hours', 4);
  sat_on  boolean := coalesce((select value ilike 'y%' from app_setting where key = 'sat'), true);
  day_cap numeric;
  avail   numeric;
begin
  while left_ > 0 loop
    if extract(dow from cur) = 0
       or (extract(dow from cur) = 6 and not sat_on)
       or holiday_applies(cur::date, p_centre) then
      cur := date_trunc('day', cur) + interval '1 day' + (open_h || ' hours')::interval;
      continue;
    end if;
    day_cap := case when extract(dow from cur) = 6 then sat_h else close_h - open_h end;
    if cur::time < (open_h || ':00')::time then
      cur := date_trunc('day', cur) + (open_h || ' hours')::interval;
    end if;
    avail := least(day_cap, extract(epoch from ((date_trunc('day', cur) + ((open_h + day_cap) || ' hours')::interval) - cur)) / 3600.0);
    if avail <= 0 then
      cur := date_trunc('day', cur) + interval '1 day' + (open_h || ' hours')::interval;
      continue;
    end if;
    if left_ <= avail then
      return cur + (left_ || ' hours')::interval;
    end if;
    left_ := left_ - avail;
    cur := date_trunc('day', cur) + interval '1 day' + (open_h || ' hours')::interval;
  end loop;
  return cur;
end $function$
;

