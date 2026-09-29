-- =====================================================================
-- Crux baseline | 40_functions_3.sql | functions, part 3 of 4
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- Ordered by name, not by dependency. Load with check_function_bodies off.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.ops_alert_resolve(p_dedupe_key text, p_note text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with done as (
    update ops_alert set resolved_at = now(), resolved_note = p_note
     where dedupe_key = p_dedupe_key and resolved_at is null
    returning 1)
  select count(*)::int from done
$function$
;

CREATE OR REPLACE FUNCTION public.org_chair(p_code text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'code', c.code, 'title', c.title, 'sg', c.sg_level,
    'function', c.function_name, 'band', c.band, 'purpose', c.purpose,
    'parent', (select p.title from chair p where p.id = c.parent_id),
    'reports', coalesce((select jsonb_agg(k.title order by k.title)
                         from chair k where k.parent_id = c.id), '[]'::jsonb),
    'track', t.name,
    'knowledge_test', t.knowledge_test,
    'unlock', t.unlock,
    'headcount', (select count(distinct person_id) from chair_holder ch
                   where ch.chair_id = c.id and ch.to_date is null),
    'seatings', coalesce((select jsonb_agg(jsonb_build_object(
                   'scope', cs.scope_label, 'holder', cs.holder_text, 'note', cs.note,
                   'people', coalesce((select jsonb_agg(pe.full_name order by pe.full_name)
                              from chair_holder ch join person pe on pe.id = ch.person_id
                              where ch.seating_id = cs.id and ch.to_date is null), '[]'::jsonb))
                   order by cs.scope_label nulls first)
                 from chair_seating cs where cs.chair_id = c.id), '[]'::jsonb),
    -- the places this chair has, so a missing one can be chosen rather than typed
    'places', coalesce((select jsonb_agg(jsonb_build_object(
                   'id', cs.id, 'scope', coalesce(cs.scope_label, 'No particular place'))
                   order by cs.scope_label nulls first)
                 from chair_seating cs where cs.chair_id = c.id), '[]'::jsonb),
    'unplaced', coalesce((select jsonb_agg(jsonb_build_object(
                   'holder', ch.id, 'name', pe.full_name) order by pe.full_name)
                 from chair_holder ch join person pe on pe.id = ch.person_id
                 where ch.chair_id = c.id and ch.to_date is null and ch.seating_id is null),
                 '[]'::jsonb),
    'accountabilities', coalesce((select jsonb_agg(a.statement order by a.ord)
                 from chair_accountability a where a.chair_id = c.id), '[]'::jsonb),
    'measures', coalesce((select jsonb_agg(m.statement order by m.ord)
                 from chair_measure m where m.chair_id = c.id), '[]'::jsonb),
    'decides', coalesce((select jsonb_agg(a.statement order by a.ord)
                 from chair_authority a where a.chair_id = c.id and a.kind='DECIDE'), '[]'::jsonb),
    'escalates', coalesce((select jsonb_agg(a.statement order by a.ord)
                 from chair_authority a where a.chair_id = c.id and a.kind='ESCALATE'), '[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('task', tk.task,
                   'subtasks', coalesce((select jsonb_agg(st.statement order by st.ord)
                                from chair_subtask st where st.task_id = tk.id), '[]'::jsonb))
                   order by tk.ord)
                 from chair_task tk where tk.chair_id = c.id), '[]'::jsonb),
    'owns', coalesce((select jsonb_agg(jsonb_build_object('ref', x.ref, 'name', x.name) order by x.ref)
                 from process x where x.owner_chair_id = c.id), '[]'::jsonb),
    'parts', coalesce((select jsonb_agg(jsonb_build_object(
                   'part', pp.part, 'ref', x.ref, 'name', x.name) order by pp.part, x.ref)
                 from process_party pp join process x on x.id = pp.process_id
                 where pp.chair_id = c.id), '[]'::jsonb),
    'receives', coalesce((select jsonb_agg(jsonb_build_object(
                   'what', pi.what, 'from', fc.title, 'for', x.name) order by pi.what)
                 from process_input pi
                 join process x on x.id = pi.process_id
                 join chair fc on fc.id = pi.from_chair_id
                 where x.owner_chair_id = c.id), '[]'::jsonb),
    'supplies', coalesce((select jsonb_agg(jsonb_build_object(
                   'what', pi.what, 'to', oc.title, 'for', x.name) order by pi.what)
                 from process_input pi
                 join process x on x.id = pi.process_id
                 join chair oc on oc.id = x.owner_chair_id
                 where pi.from_chair_id = c.id), '[]'::jsonb),
    'levels', coalesce((select jsonb_agg(jsonb_build_object(
                   'level', l.level, 'name', l.level_name, 'requirement', l.requirement,
                   'qualification', l.qualification, 'experience', l.experience,
                   'certification', l.certification, 'test', l.test_score, 'evidence', l.evidence)
                   order by l.level)
                 from capability_level l where l.track_id = t.id), '[]'::jsonb),
    'topics', coalesce((select jsonb_agg(k.topic order by k.ord)
                 from capability_topic k where k.track_id = t.id), '[]'::jsonb),
    'psychometric', coalesce((select jsonb_agg(jsonb_build_object(
                   'instrument', ps.instrument, 'standard', ps.standard) order by ps.ord)
                 from capability_psychometric ps where ps.track_id = t.id), '[]'::jsonb)
  )
  from chair c
  left join capability_track t on t.id = c.capability_track_id
  where c.code = p_code;
$function$
;

CREATE OR REPLACE FUNCTION public.org_chart()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'stats', jsonb_build_object(
      'seats',     (select count(*) from chair),
      'seatings',  (select count(*) from chair_seating),
      'processes', (select count(*) from process),
      'tracks',    (select count(*) from capability_track),
      'people',    (select count(distinct person_id) from chair_holder where to_date is null)
    ),
    'seats', coalesce((
      select jsonb_agg(s order by s->>'sg' desc, s->>'title')
      from (
        select jsonb_build_object(
          'code',     c.code,
          'title',    c.title,
          'sg',       c.sg_level,
          'function', c.function_name,
          'band',     c.band,
          'purpose',  c.purpose,
          'parent',   p.code,
          'track',    t.name,
          'owns',     (select count(*) from process x where x.owner_chair_id = c.id),
          'does',     (select count(*) from process_party x where x.chair_id = c.id and x.part='R'),
          'advises',  (select count(*) from process_party x where x.chair_id = c.id and x.part='C'),
          'informed', (select count(*) from process_party x where x.chair_id = c.id and x.part='I'),
          -- the places this seat is held, each with the people placed there
          'seatings', coalesce((
             select jsonb_agg(jsonb_build_object(
                      'scope',      cs.scope_label,
                      'holder',     cs.holder_text,
                      'note',       cs.note,
                      'reports_to', rp.code,
                      'people',     coalesce((
                         select jsonb_agg(pe.full_name order by pe.full_name)
                         from chair_holder ch join person pe on pe.id = ch.person_id
                         where ch.seating_id = cs.id and ch.to_date is null), '[]'::jsonb))
                    order by cs.scope_label nulls first)
             from chair_seating cs
             left join chair rp on rp.id = cs.reports_to_chair_id
             where cs.chair_id = c.id), '[]'::jsonb),
          -- people on this chair whom the document did not place
          'holders', coalesce((
             select jsonb_agg(jsonb_build_object('name', pe.full_name, 'email', pe.work_email)
                    order by pe.full_name)
             from chair_holder ch join person pe on pe.id = ch.person_id
             where ch.chair_id = c.id and ch.to_date is null and ch.seating_id is null), '[]'::jsonb),
          'headcount', (select count(distinct person_id) from chair_holder ch
                         where ch.chair_id = c.id and ch.to_date is null)
        ) as s
        from chair c
        left join chair p on p.id = c.parent_id
        left join capability_track t on t.id = c.capability_track_id
      ) q
    ), '[]'::jsonb)
  );
$function$
;

CREATE OR REPLACE FUNCTION public.org_place_holder(p_actor uuid, p_holder uuid, p_seating uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; h chair_holder; s chair_seating; v_name text;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Recording where a chair is held is an administrator''s to do.');
  end if;

  select * into h from chair_holder where id = p_holder;
  if h.id is null then return jsonb_build_object('error','no_such_holder'); end if;

  if p_seating is null then
    update chair_holder set seating_id = null where id = p_holder;
    return jsonb_build_object('ok', true, 'place', null);
  end if;

  select * into s from chair_seating where id = p_seating;
  if s.id is null then return jsonb_build_object('error','no_such_place'); end if;
  if s.chair_id <> h.chair_id then
    return jsonb_build_object('error','wrong_chair',
      'reason','That place belongs to a different chair. Change the chair first.');
  end if;

  update chair_holder set seating_id = p_seating where id = p_holder;

  select full_name into v_name from person where id = h.person_id;
  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, 'CHAIR_HOLDER_PLACED', 'chair_holder', p_holder::text,
          jsonb_build_object('seating_id', h.seating_id),
          jsonb_build_object('seating_id', p_seating, 'person', v_name,
                             'place', s.scope_label));

  return jsonb_build_object('ok', true, 'person', v_name,
    'place', coalesce(s.scope_label, 'No particular place'));
end $function$
;

CREATE OR REPLACE FUNCTION public.org_unplaced()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'holder', ch.id, 'name', pe.full_name,
           'chair', c.code, 'title', c.title,
           'places', coalesce((select jsonb_agg(jsonb_build_object(
                        'id', cs.id, 'scope', coalesce(cs.scope_label, 'No particular place'))
                        order by cs.scope_label nulls first)
                      from chair_seating cs where cs.chair_id = c.id), '[]'::jsonb))
         order by c.code, pe.full_name), '[]'::jsonb)
  from chair_holder ch
  join person pe on pe.id = ch.person_id
  join chair c on c.id = ch.chair_id
  where ch.to_date is null and ch.seating_id is null
$function$
;

CREATE OR REPLACE FUNCTION public.otp_gate(p_mobile text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p person%rowtype;
begin
  select * into p from person where mobile = p_mobile and employment_status = 'ACTIVE';
  if not found then
    raise exception 'No active person holds that number.'
      using hint = 'The number must match the people master exactly. HR corrects it.';
  end if;
  return p.id;
end $function$
;

CREATE OR REPLACE FUNCTION public.outbox_claim(p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_sent int; v_cap int; v_room int; v_msgs jsonb;
begin
  insert into mail_budget (day, recipients_sent) values (current_date, 0)
    on conflict (day) do nothing;
  select recipients_sent, coalesce(cap,1500) into v_sent, v_cap
    from mail_budget where day = current_date;
  v_room := greatest(0, v_cap - coalesce(v_sent,0));
  if v_room = 0 then
    return jsonb_build_object('held','daily_cap_reached','cap',v_cap,'messages','[]'::jsonb);
  end if;

  with claimed as (
    select id from outbox
     where state = 'QUEUED' and not_before <= now()
     order by not_before
     for update skip locked
     limit least(p_limit, v_room)
  ), bumped as (
    update outbox o set attempts = o.attempts + 1
      from claimed c where o.id = c.id
    returning o.id, o.template_key, o.recipient, o.cc_addr, o.subject, o.body,
              o.entity_type, o.entity_id, o.attempts
  )
  select coalesce(jsonb_agg(to_jsonb(b)), '[]'::jsonb) into v_msgs from bumped b;

  return jsonb_build_object('messages', v_msgs, 'room', v_room);
end $function$
;

CREATE OR REPLACE FUNCTION public.outbox_failed(p_id uuid, p_error text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_attempts int;
begin
  select attempts into v_attempts from outbox where id = p_id;
  update outbox set
    state = case when v_attempts >= 6 then 'ABANDONED'::outbox_state else 'DEFERRED'::outbox_state end,
    not_before = now() + (least(v_attempts, 6) * interval '10 minutes'),
    last_error = p_error
   where id = p_id;
  insert into delivery (outbox_id, channel, recipient, state, error, at)
  select p_id, 'EMAIL', recipient, 'FAILED', p_error, now() from outbox where id = p_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.outbox_mirror_to_whatsapp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_policy text; v_mobile text; v_text text;
begin
  v_policy := coalesce(nullif((select value from app_setting where key='whatsapp_mirror'),''), 'all');
  if v_policy = 'off' then return new; end if;
  if v_policy <> 'all'
     and position(new.template_key in v_policy) = 0 then
    return new;
  end if;

  select p.mobile into v_mobile
    from person p
   where p.superseded_by is null
     and lower(p.work_email) = lower(new.recipient)
     and p.mobile is not null
   limit 1;
  if v_mobile is null then return new; end if;

  -- WhatsApp has no subject line, and a body written for e-mail carries
  -- markup. Give the reader the subject, then the text, laid out as it read.
  v_text := regexp_replace(new.body, '</(p|div|tr|li|h[1-6])>', E'\n', 'gi');
  v_text := regexp_replace(v_text, '<br\s*/?>', E'\n', 'gi');
  v_text := regexp_replace(v_text, '<[^>]+>', '', 'g');
  v_text := replace(replace(replace(replace(replace(v_text,
              '&amp;','&'), '&lt;','<'), '&gt;','>'), '&nbsp;',' '), '&quot;','"');
  v_text := btrim(regexp_replace(v_text, '[ \t]*\n[ \t]*', E'\n', 'g'));
  v_text := regexp_replace(v_text, '\n{3,}', E'\n\n', 'g');
  v_text := new.subject || E'\n\n' || v_text;

  if length(v_text) > 900 then
    v_text := left(v_text, 880) || E'\n\n[...] See the e-mail for the rest.';
  end if;

  perform wa_enqueue(
    new.template_key, v_mobile, v_text,
    new.entity_type, new.entity_id, new.not_before,
    'mirror:' || new.idempotency_key);

  return new;
exception when others then
  -- a mirror must never be the reason an e-mail fails to queue
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.outbox_requeue()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int;
begin
  update outbox set state = 'QUEUED'
   where state = 'DEFERRED' and not_before <= now();
  get diagnostics n = row_count;
  return n;
end $function$
;

CREATE OR REPLACE FUNCTION public.outbox_sent(p_id uuid, p_ref text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update outbox set state = 'SENT', sent_at = now(), last_error = null where id = p_id;
  insert into delivery (outbox_id, channel, recipient, state, provider_ref, at)
  select p_id, 'EMAIL', recipient, 'SENT', p_ref, now() from outbox where id = p_id;
  update mail_budget set recipients_sent = recipients_sent + 1 where day = current_date;
end $function$
;

CREATE OR REPLACE FUNCTION public.penalty_recovery_for(p_person uuid, p_rule uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select case when (select employee_type from person where id = p_person) = 'PARTNER'
              then 'FINANCE'
              else (select recovered_by from penalty_rule where id = p_rule) end;
$function$
;

CREATE OR REPLACE FUNCTION public.penalty_sweep(p_for_day date DEFAULT (CURRENT_DATE - 1))
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_run uuid;
  r_daily penalty_rule;
  r_matrix penalty_rule;
  v_p01 int := 0; v_p06 int := 0;
  v_ran text[] := '{}';
  v_notes text[] := '{}';
begin
  insert into job_run (job_key, started_at, state)
  values ('PENALTY_SWEEP', now(), 'RUNNING') returning id into v_run;

  select * into r_daily  from penalty_rule where code = 'P-01' and active;
  select * into r_matrix from penalty_rule where code = 'P-06' and active;

  -- P-01 - no daily count on a working day
  if r_daily.id is not null then
    v_ran := array_append(v_ran, 'P-01');
    if not exists (select 1 from kpi_definition where active) then
      v_notes := array_append(v_notes,
        'P-01 is on, but no KPI is defined for anybody, so nobody is expected '
        'to file a daily count yet and nobody was charged.');
    end if;
    insert into penalty_instance
      (rule_id, person_id, period, occurred_on, cutoff_missed, evidence,
       amount, recovered_by)
    select r_daily.id, p.id, to_char(p_for_day, 'YYYY-MM'), p_for_day,
           '23:59 on ' || to_char(p_for_day, 'DD Mon YYYY'),
           'No daily count filed for ' || to_char(p_for_day, 'DD Mon YYYY') || '.',
           r_daily.amount, penalty_recovery_for(p.id, r_daily.id)
      from person p
     where p.superseded_by is null
       and p.employment_status = 'ACTIVE'
       and exists (select 1 from chair_holder h
                    where h.person_id = p.id and h.to_date is null)
       and exists (select 1 from kpi_definition k
                    where k.person_id = p.id and k.active)
       and is_working_day(p_for_day, person_centre(p.id))
       and not exists (select 1 from daily_count d
                        where d.person_id = p.id and d.count_date = p_for_day)
    on conflict do nothing;
    get diagnostics v_p01 = row_count;
  end if;

  -- P-06 - the matrix clock runs out.
  -- Charged on the day it runs out, not every day after, so the branch is
  -- charged once and re-running the sweep changes nothing.
  if r_matrix.id is not null then
    v_ran := array_append(v_ran, 'P-06');
    if not exists (select 1 from branch where effective_from is not null) then
      v_notes := array_append(v_notes,
        'P-06 is on, but no branch carries an opening date, so the fourteen-day '
        'clock has nothing to start from. Fill opened_on in the Clients and '
        'branches upload for the rule to do anything.');
    end if;
    insert into penalty_instance
      (rule_id, person_id, period, occurred_on, cutoff_missed, evidence,
       entity_type, entity_id, amount, recovered_by)
    select distinct on (b.id)
           r_matrix.id, cr.person_id, to_char(p_for_day, 'YYYY-MM'), p_for_day,
           'Fourteen days from ' || to_char(b.effective_from, 'DD Mon YYYY'),
           'Branch ' || coalesce(b.code, b.name) || ' still has fewer than five '
             || 'complete matrix levels fourteen days after opening.',
           'branch', b.id, r_matrix.amount,
           penalty_recovery_for(cr.person_id, r_matrix.id)
      from branch b
      join coverage_rule cr on cr.branch_id = b.id
     where b.status = 'ACTIVE'
       and b.effective_from = p_for_day - 14
       and not matrix_complete(b.id)
       and (cr.effective_to is null or cr.effective_to >= p_for_day)
     order by b.id, cr.is_assigned_handler desc nulls last, cr.effective_from desc
    on conflict do nothing;
    get diagnostics v_p06 = row_count;
  end if;

  if v_ran = '{}' then
    v_notes := array_append(v_notes, 'No penalty rule is active, so nothing was charged.');
  end if;

  update job_run set finished_at = now(), state = 'DONE',
         counts = jsonb_build_object('day', p_for_day, 'P-01', v_p01, 'P-06', v_p06,
                                     'rules_run', to_jsonb(v_ran),
                                     'notes', to_jsonb(v_notes))
   where id = v_run;

  return jsonb_build_object('day', p_for_day, 'P-01', v_p01, 'P-06', v_p06,
    'rules_run', to_jsonb(v_ran), 'notes', to_jsonb(v_notes));
exception when others then
  update job_run set finished_at = now(), state = 'FAILED', error = sqlerrm where id = v_run;
  raise;
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_accrual_kind(p_kpi uuid, p_unit text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
declare a text; u text;
begin
  if p_kpi is not null then
    select lower(k.accrual::text) into a from kpi_definition k where k.id = p_kpi;
  end if;

  -- An explicit REPLACES is somebody saying so. Nothing overrides it.
  if a is not null and (a like '%replace%' or a like '%level%' or a like '%latest%'
                        or a like '%last%' or a like '%avg%' or a like '%aver%') then
    return 'LEVEL';
  end if;

  -- The design's own test, and it beats ADDS on purpose: /%|score/i is a
  -- level. A measure counted in per cent that claims to accumulate is a
  -- default nobody changed, and believing it is how a month reaches 181%.
  u := coalesce(p_unit, '');
  if u ~* '%|score|rate|ratio|pct|percent|per cent' then return 'LEVEL'; end if;

  return 'SUM';
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_assign(p_actor uuid, p_in jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c perf_cycle; k kpi_definition; v_person uuid; v_id uuid;
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
end $function$
;

CREATE OR REPLACE FUNCTION public.perf_assign_bulk(p_actor uuid, p_in jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
            where a.person_id = p_person and a.cycle_id = p_cycle and a.part_of_id is null
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

CREATE OR REPLACE FUNCTION public.perf_may_set(p_actor uuid, p_person uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from person a
     where a.id = p_actor
       and a.employment_status = 'ACTIVE'
       and a.superseded_by is null
       and a.id <> p_person
       and (a.app_role = 'ADMIN'
            or coalesce(a.department,'') in ('Human Resources','Business Excellence')
            or exists (select 1 from person t
                        where t.id = p_person and t.manager_id = a.id)));
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
    'filings', (select count(*) from perf_entry e where e.assignment_id = a.id),
    'lastFiled', (select max(e.as_of) from perf_entry e where e.assignment_id = a.id),
    'parts', parts, 'team', team);
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
begin
  insert into job_run (job_key, started_at, state)
  values ('PERF_REMINDERS', now(), 'RUNNING') returning id into v_run;

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
                           || coalesce(' ' || (item->>'unit'), '') else '' end
              || E'\n';
      end if;
    end loop;

    if lines = '' then n_skip := n_skip + 1; continue; end if;

    body := 'Good morning ' || split_part(r.full_name, ' ', 1) || E',\n\n'
         || 'These are due from you today, ' || to_char(p_on, 'FMDD FMMonth YYYY') || E':\n\n'
         || lines || E'\n'
         || 'Open Performance in Crux and file them. The number is for today -- '
         || 'filing it tomorrow does not make it tomorrow''s number.' || E'\n';

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
           || E'\n\nOpen Performance in Crux, then My team.\n';

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
                                     'cycle', c.id)
   where id = v_run;

  return jsonb_build_object('day', p_on, 'due', n_due, 'unset', n_unset,
    'note', case when n_due = 0 and n_unset = 0
      then 'Nothing was owed by anybody today, so nobody was written to.'
      else n_due || ' filing reminder(s) and ' || n_unset || ' setting reminder(s) queued.' end);
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
       where a.person_id = p_person and a.cycle_id = p_cycle
         and a.part_of_id is null), '[]'::jsonb),
    'says', case
      when not exists (select 1 from perf_assignment a
                        where a.person_id = p_person and a.cycle_id = p_cycle)
      then 'Nothing has been set for this period yet. KPIs are set by the reporting manager, by HR, or by an administrator, and the window for '
           || c.period_start || ' ' || case when current_date <= c.assign_closes
              then 'is open until ' || c.assign_closes else 'closed on ' || c.assign_closes end || '.'
      else null end);
end $function$
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
       and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
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
       and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT')
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
       and coalesce(q.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'), '[]'::jsonb),
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
     and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
  ) t;
$function$
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

CREATE OR REPLACE FUNCTION public.plb_actual_set(p_actor uuid, p_sheet uuid, p_kpi uuid, p_actual numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_frozen timestamptz;
begin
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
       where s.quarter = date_trunc('quarter', p_quarter)::date), '[]'::jsonb),
    'inScheme', coalesce((
      select jsonb_agg(jsonb_build_object(
               'personId', p.id, 'person', p.full_name, 'employeeNo', p.employee_no,
               'chair', ch.title, 'chairCode', ch.code,
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
                      where k.chair_id = ch.id and k.active and k.position < 100)), '[]'::jsonb));
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

CREATE OR REPLACE FUNCTION public.plb_sheet_issue(p_actor uuid, p_person uuid, p_quarter date, p_target numeric, p_targets jsonb DEFAULT '[]'::jsonb, p_default boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_chair uuid; v_sheet uuid; v_n int; v_w numeric; r record;
begin
  if p_actor = p_person and not p_default then
    return jsonb_build_object('error','not_permitted',
      'reason','Nobody issues their own goal sheet.');
  end if;

  select ch.chair_id into v_chair
    from chair_holder ch where ch.person_id = p_person and ch.to_date is null
    order by ch.is_primary desc nulls last limit 1;
  if v_chair is null then
    return jsonb_build_object('error','no_chair',
      'reason','That person is not seated in a chair, so there is no measure set to build from.');
  end if;

  select count(*) into v_n from kpi_definition
   where chair_id = v_chair and active and position < 100;
  if v_n = 0 then
    return jsonb_build_object('error','chair_not_in_scheme',
      'reason','That chair has no KPIs in the registry, so it is not in the PLB scheme.');
  end if;
  v_w := round(100.0 / v_n, 3);

  insert into plb_goal_sheet (person_id, chair_id, quarter, target_plb_inr,
                              status, issued_by, issued_at, is_default)
  values (p_person, v_chair, date_trunc('quarter', p_quarter)::date, p_target,
          'ISSUED', p_actor, now(), p_default)
  on conflict (person_id, quarter) do update
     set target_plb_inr = excluded.target_plb_inr,
         status = case when plb_goal_sheet.status = 'LOCKED'
                       then plb_goal_sheet.status else 'ISSUED' end
  returning id into v_sheet;

  if (select status from plb_goal_sheet where id = v_sheet) = 'LOCKED' then
    return jsonb_build_object('error','locked',
      'reason','That goal sheet is locked. KPIs, weights and targets are frozen.');
  end if;

  -- the KPIs come from the registry, never from the caller
  insert into plb_goal_kpi (sheet_id, kpi_id, weight_pct)
  select v_sheet, k.id, v_w
    from kpi_definition k
   where k.chair_id = v_chair and k.active and k.position < 100
  on conflict (sheet_id, kpi_id) do update set weight_pct = excluded.weight_pct;

  -- the five attributes, same for everyone
  insert into plb_goal_attribute (sheet_id, kpi_id)
  select v_sheet, k.id from kpi_definition k where k.chair_id is null and k.active
  on conflict do nothing;

  -- the caller may set targets, the basis level and the monthly split
  for r in select * from jsonb_to_recordset(coalesce(p_targets,'[]'::jsonb))
             as x(kpi_id uuid, target numeric, basis int, basis_note text,
                  m1 numeric, m2 numeric, m3 numeric)
  loop
    update plb_goal_kpi
       set target_value = coalesce(r.target, target_value),
           basis_level  = coalesce(r.basis, basis_level),
           basis_note   = coalesce(r.basis_note, basis_note),
           m1_share     = coalesce(r.m1, m1_share),
           m2_share     = coalesce(r.m2, m2_share),
           m3_share     = coalesce(r.m3, m3_share)
     where sheet_id = v_sheet and kpi_id = r.kpi_id;
  end loop;

  return jsonb_build_object('ok', true, 'sheetId', v_sheet, 'kpis', v_n,
    'weightEach', v_w,
    'note', 'Goal sheet issued with ' || v_n || ' KPIs at ' || v_w || '% each.');
end $function$
;

CREATE OR REPLACE FUNCTION public.plb_sheet_lock(p_actor uuid, p_sheet uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_missing int;
begin
  select count(*) into v_missing from plb_goal_kpi
   where sheet_id = p_sheet and (target_value is null or basis_level is null);
  if v_missing > 0 then
    return jsonb_build_object('error','incomplete',
      'reason', v_missing || ' KPI(s) have no target or no recorded basis level. '
                || 'A target you cannot trace to a level is an opinion with a number on it.');
  end if;
  update plb_goal_sheet set status = 'LOCKED', locked_at = now() where id = p_sheet;
  return jsonb_build_object('ok', true,
    'note','Goal sheet locked. KPIs, weights and targets are frozen for the quarter.');
end $function$
;

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

