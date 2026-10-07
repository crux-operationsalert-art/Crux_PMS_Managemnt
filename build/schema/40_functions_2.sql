-- =====================================================================
-- Crux baseline | 40_functions_2.sql | functions, part 2 of 4
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- Ordered by name, not by dependency. Load with check_function_bodies off.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.ogl_attach_done(p_assignment uuid, p_actor uuid, p_key text, p_file_name text, p_mime text DEFAULT NULL::text, p_bytes bigint DEFAULT NULL::bigint, p_doc_kind text DEFAULT 'EVIDENCE'::text, p_requirement uuid DEFAULT NULL::uuid, p_caption text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a assignment%rowtype; v_id uuid;
begin
  select * into a from assignment where id = p_assignment;
  if not found then return jsonb_build_object('error','no_such_assignment'); end if;
  -- the key has to be one we would have issued for this assignment
  if p_key not like (a.ref || '/%') then
    return jsonb_build_object('error','key_mismatch',
      'reason','That storage key does not belong to this assignment.');
  end if;

  insert into ogl_attachment (assignment_id, requirement_id, doc_kind, file_name,
    party_kind, party_seq, storage_key, mime, bytes, uploaded_by, uploaded_at, caption)
  values (p_assignment, p_requirement, upper(coalesce(nullif(btrim(p_doc_kind),''),'EVIDENCE')),
    btrim(p_file_name), 'APPLICANT', 1, p_key, p_mime, p_bytes, p_actor, now(), p_caption)
  returning id into v_id;

  insert into assignment_event (assignment_id, event_type, actor_id, payload)
  values (p_assignment, 'EVIDENCE_ATTACHED', p_actor,
          jsonb_build_object('attachment', v_id, 'file', btrim(p_file_name),
                             'requirement', p_requirement, 'bytes', p_bytes));

  return jsonb_build_object('id', v_id, 'file_name', btrim(p_file_name));
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_attach_remove(p_attachment uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t ogl_attachment%rowtype; a assignment%rowtype;
begin
  select * into t from ogl_attachment where id = p_attachment;
  if not found then return jsonb_build_object('error','no_such_attachment'); end if;
  select * into a from assignment where id = t.assignment_id;
  if p_actor not in (t.uploaded_by, a.assignor_id)
     and (select app_role from person where id = p_actor) is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_yours',
      'reason','The person who attached it, the assignor, or an administrator.');
  end if;
  update ogl_attachment set removed_at = now(), removed_by = p_actor
   where id = p_attachment and removed_at is null;
  insert into assignment_event (assignment_id, event_type, actor_id, payload)
  values (t.assignment_id, 'EVIDENCE_REMOVED', p_actor,
          jsonb_build_object('attachment', p_attachment, 'file', t.file_name));
  return jsonb_build_object('id', p_attachment, 'removed', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_attachments(p_assignment uuid, p_person uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d jsonb;
begin
  -- borrow ogl_detail's scoping rather than write a second version of it
  d := ogl_detail(p_assignment, p_person);
  if d ? 'error' then return d; end if;

  return jsonb_build_object('attachments', coalesce((
    select jsonb_agg(jsonb_build_object('id', t.id, 'file_name', t.file_name,
             'doc_kind', t.doc_kind, 'caption', t.caption, 'bytes', t.bytes,
             'mime', t.mime, 'key', t.storage_key,
             'bucket', case when t.storage_key like '%.pdf' then 'case-documents' else 'visit-photos' end,
             'point', (select r.force1_point_id from case_verification_requirement r
                        where r.id = t.requirement_id),
             'by', (select full_name from person where id = t.uploaded_by),
             'at', t.uploaded_at) order by t.uploaded_at desc)
      from ogl_attachment t
     where t.assignment_id = p_assignment and t.removed_at is null), '[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_attribution_confirm(p_segment uuid, p_reason uuid, p_actor uuid, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s sla_clock_segment%rowtype; a assignment%rowtype; r reason_taxonomy%rowtype;
  v_attr text;
begin
  select * into s from sla_clock_segment where id = p_segment for update;
  if not found then return jsonb_build_object('error','no_such_segment'); end if;
  if s.attribution <> 'PENDING_REVIEW' then
    return jsonb_build_object('error','nothing_pending',
      'reason','That stretch of time is already attributed to ' || s.attribution || '.');
  end if;

  select asg.* into a from assignment asg
    join sla_instance si on si.assignment_id = asg.id
   where si.id = s.sla_instance_id;

  if a.assignor_id is distinct from p_actor
     and (select app_role from person where id = p_actor) is distinct from 'ADMIN'
     and not exists (select 1 from person p where p.id = a.assignor_id and p.manager_id = p_actor) then
    return jsonb_build_object('error','not_yours_to_confirm',
      'reason','The assignor, their manager, or an administrator confirms attribution.');
  end if;

  select * into r from reason_taxonomy where id = p_reason and context = 'ATTRIBUTION';
  if not found then
    return jsonb_build_object('error','no_such_reason',
      'reason','Choose one of the attribution outcomes.');
  end if;
  if r.requires_remarks and coalesce(btrim(coalesce(p_remarks,'')),'') = '' then
    return jsonb_build_object('error','remarks_required',
      'reason','Reclassifying time needs a sentence saying why.');
  end if;

  v_attr := case r.code
    when 'RECLASSIFIED_ASSIGNEE' then 'ASSIGNEE'
    when 'RECLASSIFIED_EXTERNAL' then 'EXTERNAL'
    -- the delay's own reason stands
    else coalesce((select implied_attribution from reason_taxonomy where id = s.reason_id), 'EXTERNAL')
  end;

  update sla_clock_segment
     set attribution      = v_attr,
         counts_to_strike = (v_attr = 'ASSIGNEE'),
         reason_text      = coalesce(p_remarks, s.reason_text),
         set_by           = p_actor
   where id = p_segment;

  insert into assignment_event (assignment_id, event_type, actor_id, payload)
  values (a.id, 'ATTRIBUTION_CONFIRMED', p_actor,
          jsonb_build_object('segment', p_segment, 'outcome', r.code,
                             'attribution', v_attr, 'remarks', p_remarks));

  return jsonb_build_object('segment', p_segment, 'outcome', r.code, 'attribution', v_attr);
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_attribution_pending(p_sla uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from sla_clock_segment
                  where sla_instance_id = p_sla and attribution = 'PENDING_REVIEW')
$function$
;

CREATE OR REPLACE FUNCTION public.ogl_attribution_tray(p_person uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.opened_at), '[]'::jsonb) from (
    select s.id as segment_id, s.opened_at, s.reason_text,
           a.id as assignment_id, a.ref, a.current_state,
           p.full_name as allocated_to,
           business_minutes_between(s.opened_at, coalesce(s.closed_at, now()), si.calendar_id) as minutes
      from sla_clock_segment s
      join sla_instance si on si.id = s.sla_instance_id
      join assignment a on a.id = si.assignment_id
      left join person p on p.id = a.allocated_to_id
     where s.attribution = 'PENDING_REVIEW'
       and (a.assignor_id = p_person
            or exists (select 1 from person m where m.id = a.assignor_id and m.manager_id = p_person)
            or (select app_role from person where id = p_person) = 'ADMIN')
     order by s.opened_at) x
$function$
;

CREATE OR REPLACE FUNCTION public.ogl_backfill_segments()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_n int := 0; r record;
begin
  for r in select si.id, si.started_at from sla_instance si
            where si.stopped_at is null
              and not exists (select 1 from sla_clock_segment s where s.sla_instance_id = si.id)
  loop
    perform ogl_segment_open(r.id, 'RUNNING', 'ASSIGNEE', true, true,
                             null, 'opening segment', null, r.started_at);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_case_create(p_actor uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_client uuid; v_branch uuid; v_to uuid; v_from uuid; v_chair uuid;
  v_case uuid; v_asg uuid; v_ref text; v_alloc uuid;
  v_party uuid; v_type uuid; v_prior case_verification_requirement%rowtype;
  v_prior_case verification_case%rowtype;
  v jsonb; m jsonb; v_held int := 0; v_made int := 0; v_pending jsonb := '[]'::jsonb;
  v_addr text; v_self text;
begin
  if not exists (select 1 from person where id = p_actor
                  and employment_status = 'ACTIVE' and superseded_by is null) then
    return jsonb_build_object('error','no_such_actor');
  end if;

  select id into v_client from client
   where code = btrim(p_payload->>'client_code') or lower(name) = lower(btrim(p_payload->>'client_code'));
  if v_client is null then
    return jsonb_build_object('error','no_such_client',
      'reason','No client matches "' || coalesce(p_payload->>'client_code','') || '".');
  end if;

  select id into v_to from geo_node
   where level = 'ZONE' and lower(name) = lower(btrim(p_payload->>'to_location'));
  if v_to is null then
    return jsonb_build_object('error','no_such_location',
      'reason','No zone is called "' || coalesce(p_payload->>'to_location','') ||
               '". Load Geography first, or use the name exactly as it is loaded.');
  end if;

  if nullif(btrim(coalesce(p_payload->>'branch_code','')),'') is not null then
    select id into v_branch from branch where code = btrim(p_payload->>'branch_code');
  end if;

  if nullif(btrim(coalesce(p_payload->>'from_location','')),'') is not null then
    select id into v_from from geo_node
     where level = 'ZONE' and lower(name) = lower(btrim(p_payload->>'from_location'));
  end if;
  -- a location that raises work for itself is allowed, and has to say so
  if v_from is null then v_from := v_to; end if;
  if v_from = v_to then
    v_self := coalesce(nullif(btrim(coalesce(p_payload->>'self_assign_reason','')),''),
                       'Raised and verified in the same location.');
  end if;

  select h.chair_id into v_chair from chair_holder h
   where h.person_id = p_actor and h.from_date <= current_date
     and (h.to_date is null or h.to_date >= current_date)
   order by h.is_primary desc limit 1;
  if v_chair is null then
    return jsonb_build_object('error','no_chair',
      'reason','You do not hold a chair, and an assignment is raised by a chair '
             ||'rather than by a person. Ask an administrator to seat you.');
  end if;

  if nullif(btrim(coalesce(p_payload->>'allocated_to','')),'') is not null then
    select id into v_alloc from person
     where lower(work_email) = lower(btrim(p_payload->>'allocated_to'))
       and employment_status = 'ACTIVE' and superseded_by is null;
  end if;

  if jsonb_typeof(p_payload->'verifications') <> 'array'
     or jsonb_array_length(p_payload->'verifications') = 0 then
    return jsonb_build_object('error','no_verifications',
      'reason','An assignment with nothing to verify is not an assignment.');
  end if;

  insert into verification_case (force1_case_id, client_id, branch_id, applicant_name,
    applicant_contact, applicant_address, pincode, created_by)
  values (btrim(p_payload->>'force1_case_id'), v_client, v_branch,
    btrim(p_payload->>'applicant_name'), btrim(p_payload->>'applicant_contact'),
    btrim(p_payload->>'applicant_address'), btrim(p_payload->>'pincode'), p_actor)
  returning id into v_case;

  v_ref := next_ref('OGL', 5);
  insert into assignment (ref, case_id, assignor_id, assignor_chair_id,
    from_location_id, to_location_id, allocated_to_id, current_state,
    next_action_owner_id, self_assign_reason, source_ref)
  values (v_ref, v_case, p_actor, v_chair, v_from, v_to, v_alloc, 'DRAFT',
    p_actor, v_self, 'raised in the tool')
  returning id into v_asg;

  insert into assignment_event (assignment_id, event_type, actor_id, to_state, payload)
  values (v_asg, 'ASSIGNMENT_CREATED', p_actor, 'DRAFT',
          jsonb_build_object('case', v_case, 'ref', v_ref));

  for v in select * from jsonb_array_elements(p_payload->'verifications') loop
    select id into v_type from verification_type
     where code = upper(btrim(v->>'type')) and active;
    if v_type is null then
      raise exception 'No verification type "%". They are RESIDENT, BUSINESS, EMPLOYEE and QUOTATION.',
        coalesce(v->>'type','');
    end if;
    if nullif(btrim(coalesce(v->>'point_id','')),'') is null then
      raise exception 'Every selected verification needs a Point ID. "%" has none.', coalesce(v->>'type','');
    end if;

    v_addr := coalesce(nullif(btrim(coalesce(v->>'address','')),''),
                       btrim(p_payload->>'applicant_address'));

    insert into case_party (case_id, party_role, seq_no, name, contact, address, same_as_applicant)
    values (v_case, upper(coalesce(nullif(btrim(coalesce(v->>'party_role','')),''),'APPLICANT')),
      coalesce((v->>'seq_no')::int,
               (select count(*) + 1 from case_party
                 where case_id = v_case
                   and party_role = upper(coalesce(nullif(btrim(coalesce(v->>'party_role','')),''),'APPLICANT')))),
      coalesce(nullif(btrim(coalesce(v->>'name','')),''), btrim(p_payload->>'applicant_name')),
      coalesce(nullif(btrim(coalesce(v->>'contact','')),''), btrim(p_payload->>'applicant_contact')),
      v_addr,
      coalesce(nullif(btrim(coalesce(v->>'name','')),''), btrim(p_payload->>'applicant_name'))
        = btrim(p_payload->>'applicant_name'))
    returning id into v_party;

    select * into v_prior from case_verification_requirement
     where force1_point_id = btrim(v->>'point_id')
     order by attempt_no desc limit 1;

    if found then
      select * into v_prior_case from verification_case where id = v_prior.case_id;
      m := ogl_addr_match(v_prior_case.applicant_address, v_addr);
      insert into repeat_point_decision (force1_point_id, prior_requirement_id,
        address_match, match_score, proposed, case_id, party_id,
        verification_type_id, new_address, assignment_id)
      values (btrim(v->>'point_id'), v_prior.id,
        m->>'match', (m->>'score')::int,
        case when m->>'match' = 'DIFFERENT' then 'NEW_ASSIGNMENT' else 'REVISIT' end,
        v_case, v_party, v_type, v_addr, v_asg);
      v_held := v_held + 1;
      v_pending := v_pending || jsonb_build_object(
        'point_id', btrim(v->>'point_id'), 'match', m->>'match', 'score', m->>'score',
        'proposed', case when m->>'match' = 'DIFFERENT' then 'NEW_ASSIGNMENT' else 'REVISIT' end,
        'prior_ref', (select a.ref from assignment a where a.case_id = v_prior.case_id limit 1));
    else
      insert into case_verification_requirement (case_id, party_id, verification_type_id,
        force1_point_id, attempt_no, lineage)
      values (v_case, v_party, v_type, btrim(v->>'point_id'), 1, 'ORIGINAL');
      v_made := v_made + 1;
    end if;
  end loop;

  return jsonb_build_object('id', v_asg, 'ref', v_ref, 'case', v_case,
    'state', 'DRAFT', 'points_created', v_made, 'points_held', v_held,
    'pending_decisions', v_pending,
    'note', case when v_held > 0
      then v_held || ' Point ID(s) have been used before. They are waiting for you to '
         || 'say whether each is a revisit, a reopen, new work, or keyed in error. '
         || 'Nothing starts until you do.'
      else 'Raised as a draft. Submit it when it is ready.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_complete(p_assignment uuid, p_actor uuid, p_channel text, p_recipient text DEFAULT NULL::text, p_reference text DEFAULT NULL::text, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a assignment%rowtype; v_left int; v_id uuid; v_back boolean;
begin
  select * into a from assignment where id = p_assignment for update;
  if not found then return jsonb_build_object('error','no_such_assignment'); end if;
  if a.allocated_to_id is distinct from p_actor
     and (select app_role from person where id = p_actor) is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_the_assignee',
      'reason','The person the work is allocated to completes it.');
  end if;
  if a.current_state not in ('IN_PROGRESS','REWORK') then
    return jsonb_build_object('error','wrong_state',
      'reason','This is ' || a.current_state || '.');
  end if;
  if a.open_request_type is not null then
    return jsonb_build_object('error','request_open',
      'reason','A ' || a.open_request_type || ' is open. Resolve it before completing.');
  end if;

  select count(*) into v_left from case_verification_requirement
   where case_id = a.case_id and status in ('PENDING','IN_PROGRESS');
  if v_left > 0 then
    return jsonb_build_object('error','points_unreported',
      'reason', v_left || ' verification point(s) have no finding recorded. '
             || 'Report each one before completing.');
  end if;

  if coalesce(btrim(coalesce(p_channel,'')),'') = '' then
    return jsonb_build_object('error','channel_required',
      'reason','Say how the report was delivered - the channel is the evidence.');
  end if;

  -- a completion dated before the last thing that happened is flagged, not
  -- refused: backdating is sometimes honest and always worth seeing
  v_back := exists (select 1 from assignment_event e
                     where e.assignment_id = p_assignment and e.occurred_at > now());

  insert into assignment_completion (assignment_id, breach_cycle_no, channel,
    recipient, force1_ref, message_ref, other_remarks, submitted_by, shared_at)
  values (p_assignment, a.breach_cycle_no, upper(btrim(p_channel)),
    nullif(btrim(coalesce(p_recipient,'')),''),
    nullif(btrim(coalesce(p_reference,'')),''),
    nullif(btrim(coalesce(p_reference,'')),''),
    p_remarks, p_actor, now())
  returning id into v_id;

  insert into assignment_event (assignment_id, event_type, actor_id, payload)
  values (p_assignment, 'COMPLETED', p_actor,
          jsonb_build_object('completion', v_id, 'channel', upper(btrim(p_channel)),
                             'recipient', p_recipient, 'reference', p_reference));

  return ogl_transition(p_assignment, 'COMPLETED', p_actor,
           'report delivered by ' || upper(btrim(p_channel)))
         || jsonb_build_object('completion', v_id, 'backdate_flagged', v_back);
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_detail(p_assignment uuid, p_person uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a assignment%rowtype; si sla_instance%rowtype; v_may boolean;
begin
  select * into a from assignment where id = p_assignment;
  if not found then return jsonb_build_object('error','no_such_assignment'); end if;

  -- D8: nobody borrows another chair's data, and an empty answer says why
  v_may := p_person in (a.assignor_id, a.allocated_to_id, a.next_action_owner_id)
        or (select app_role from person where id = p_person) = 'ADMIN'
        or exists (select 1 from person p where p.id in (a.assignor_id, a.allocated_to_id)
                     and p.manager_id = p_person)
        or exists (select 1 from temp_participant_grant g
                    where g.assignment_id = p_assignment and g.person_id = p_person
                      and g.revoked_at is null and g.expires_at > now())
        or exists (select 1 from escalation_instance e
                    where e.assignment_id = p_assignment and e.resolved_to_id = p_person);
  if not v_may then
    return jsonb_build_object('error','not_yours',
      'reason','This assignment belongs to another chair. You are not the assignor, '
             ||'the assignee, their manager, or anyone it has been escalated to.');
  end if;

  si := ogl_live_sla(p_assignment);

  return jsonb_build_object(
    'assignment', to_jsonb(a) || jsonb_build_object(
      'assignor', (select full_name from person where id = a.assignor_id),
      'allocated_to', (select full_name from person where id = a.allocated_to_id),
      'next_action_owner', (select full_name from person where id = a.next_action_owner_id),
      'location', (select name from geo_node where id = a.to_location_id)),
    'case', (select to_jsonb(c) || jsonb_build_object(
               'client', (select name from client where id = c.client_id))
               from verification_case c where c.id = a.case_id),
    'parties', coalesce((select jsonb_agg(to_jsonb(cp) order by cp.party_role, cp.seq_no)
                  from case_party cp where cp.case_id = a.case_id), '[]'::jsonb),
    'requirements', coalesce((select jsonb_agg(to_jsonb(cr) || jsonb_build_object(
                       'verification_type', (select label from verification_type where id = cr.verification_type_id))
                       order by cr.force1_point_id, cr.attempt_no)
                       from case_verification_requirement cr where cr.case_id = a.case_id), '[]'::jsonb),
    'sla', case when si.id is null then null else
      to_jsonb(si) || jsonb_build_object(
        'elapsed_minutes', ogl_elapsed_sla(si.id),
        'strike_exposure', ogl_strike_exposure(si.id),
        'attribution_pending', ogl_attribution_pending(si.id),
        'due_ist', to_char(ogl_ts(coalesce(si.extended_to, si.due_at)), 'DD Mon YYYY HH24:MI'))
      end,
    'segments', coalesce((select jsonb_agg(to_jsonb(s) order by s.seq_no)
                  from sla_clock_segment s where s.sla_instance_id = si.id), '[]'::jsonb),
    'requests', coalesce((select jsonb_agg(to_jsonb(q) || jsonb_build_object(
                   'reason', (select label from reason_taxonomy where id = q.reason_id),
                   'raised_by_name', (select full_name from person where id = q.raised_by))
                   order by q.raised_at desc)
                   from assignment_request q where q.assignment_id = p_assignment), '[]'::jsonb),
    'escalations', coalesce((select jsonb_agg(to_jsonb(e) || jsonb_build_object(
                     'to', (select full_name from person where id = e.resolved_to_id))
                     order by e.raised_at desc)
                     from escalation_instance e where e.assignment_id = p_assignment), '[]'::jsonb),
    'strikes', coalesce((select jsonb_agg(to_jsonb(st) order by st.occurred_at desc)
                 from strike_event st where st.assignment_id = p_assignment), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object(
                 'at', ev.occurred_at, 'type', ev.event_type, 'from', ev.from_state,
                 'to', ev.to_state, 'system', ev.is_system,
                 'by', (select full_name from person where id = ev.actor_id),
                 'payload', ev.payload) order by ev.occurred_at desc, ev.id desc)
                 from (select * from assignment_event
                        where assignment_id = p_assignment
                        order by occurred_at desc, id desc limit 60) ev), '[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_dispute_classify(p_request uuid, p_actor uuid, p_outcome text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare q assignment_request%rowtype; a assignment%rowtype; v_id uuid; v_waived int := 0;
begin
  select * into q from assignment_request where id = p_request for update;
  if not found then return jsonb_build_object('error','no_such_request'); end if;
  if q.request_type <> 'DISPUTE' then
    return jsonb_build_object('error','not_a_dispute');
  end if;
  if q.resolved_at is not null then
    return jsonb_build_object('error','already_classified',
      'reason','That dispute was classified as ' || q.resolution || '.');
  end if;
  if p_outcome not in ('UPHELD','NOT_UPHELD') then
    return jsonb_build_object('error','bad_outcome');
  end if;
  if coalesce(btrim(coalesce(p_reason,'')),'') = '' then
    return jsonb_build_object('error','reason_required',
      'reason','Classifying a dispute needs a sentence saying why.');
  end if;

  select * into a from assignment where id = q.assignment_id;

  update assignment_request set resolution = p_outcome, resolved_by = p_actor,
         resolved_at = now(), resolution_remarks = p_reason
   where id = p_request;

  insert into assignment_event (assignment_id, event_type, actor_id, payload)
  values (q.assignment_id, 'DISPUTE_CLASSIFIED', p_actor,
          jsonb_build_object('request', p_request, 'outcome', p_outcome, 'reason', p_reason));

  if p_outcome = 'UPHELD' and a.allocated_to_id is not null then
    insert into strike_event (person_id, location_id, assignment_id, breach_cycle_no,
      trigger_code, occurred_at, strike_no, facts)
    values (a.allocated_to_id, a.to_location_id, q.assignment_id, q.breach_cycle_no,
      'DISPUTE_UPHELD', now(),
      (select count(*) + 1 from strike_event
        where person_id = a.allocated_to_id and status = 'ACTIVE'
          and occurred_at > now() - (ogl_setting_int('ogl_strike_window_days',90) || ' days')::interval),
      jsonb_build_object('ref', a.ref, 'dispute', p_request, 'reason', p_reason))
    on conflict (assignment_id, breach_cycle_no, trigger_code) do nothing
    returning id into v_id;
    if v_id is not null then
      insert into assignment_event (assignment_id, event_type, is_system, payload)
      values (q.assignment_id, 'STRIKE_GENERATED', true,
              jsonb_build_object('strike', v_id, 'because','dispute upheld'));
    end if;
  end if;

  if p_outcome = 'NOT_UPHELD' then
    update strike_event
       set status = 'WAIVED', waived_by = p_actor,
           waived_reason = 'The dispute behind this was not upheld: ' || p_reason
     where assignment_id = q.assignment_id and breach_cycle_no = q.breach_cycle_no
       and status = 'ACTIVE';
    get diagnostics v_waived = row_count;
    if v_waived > 0 then
      insert into assignment_event (assignment_id, event_type, actor_id, payload)
      values (q.assignment_id, 'STRIKE_WAIVED', p_actor,
              jsonb_build_object('count', v_waived, 'because','dispute not upheld'));
    end if;
  end if;

  return jsonb_build_object('id', p_request, 'outcome', p_outcome,
    'strike', v_id, 'strikes_waived', v_waived);
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_elapsed_sla(p_sla uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(sum(
           case when s.closed_at is not null then s.business_minutes
                else business_minutes_between(s.opened_at, now(), si.calendar_id) end), 0)::int
    from sla_clock_segment s join sla_instance si on si.id = s.sla_instance_id
   where s.sla_instance_id = p_sla and s.counts_to_sla
$function$
;

CREATE OR REPLACE FUNCTION public.ogl_escalation_route(p_assignment uuid, p_level integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  a assignment%rowtype; vc verification_case%rowtype;
  m ogl_escalation_matrix%rowtype; v_person uuid; v_chair uuid;
  v_steps int; v_cur uuid; v_trace jsonb := '[]'::jsonb;
begin
  select * into a from assignment where id = p_assignment;
  if not found then return jsonb_build_object('error','no_such_assignment'); end if;
  select * into vc from verification_case where id = a.case_id;

  -- 1. client + location + branch
  select * into m from ogl_escalation_matrix
   where escalation_level = p_level and effective_to is null
     and client_id is not distinct from vc.client_id
     and location_id is not distinct from a.to_location_id
     and branch_id is not distinct from vc.branch_id
   order by sequence_no limit 1;
  v_trace := v_trace || jsonb_build_object('tried','client+location+branch','hit', found);

  -- 2. client + location
  if not found then
    select * into m from ogl_escalation_matrix
     where escalation_level = p_level and effective_to is null
       and client_id is not distinct from vc.client_id
       and location_id is not distinct from a.to_location_id
       and branch_id is null
     order by sequence_no limit 1;
    v_trace := v_trace || jsonb_build_object('tried','client+location','hit', found);
  end if;

  -- 3. location alone
  if not found then
    select * into m from ogl_escalation_matrix
     where escalation_level = p_level and effective_to is null
       and client_id is null
       and location_id is not distinct from a.to_location_id
     order by sequence_no limit 1;
    v_trace := v_trace || jsonb_build_object('tried','location','hit', found);
  end if;

  if found then
    v_person := m.person_id;
    v_chair  := m.chair_id;
    -- a chair without a named person resolves to whoever sits in it now
    if v_person is null and v_chair is not null then
      select id into v_person from person
       where employment_status = 'ACTIVE' and superseded_by is null
         and id in (select person_id from chair_seat where chair_id = v_chair and vacated_on is null)
       limit 1;
    end if;
    if v_person is not null then
      return jsonb_build_object('person_id', v_person, 'chair_id', v_chair,
        'fallback_used', false, 'trace', v_trace);
    end if;
    v_trace := v_trace || jsonb_build_object('note','matrix row found but nobody sits in it');
  end if;

  -- 4. the walk. Level N means N managers above the assignee.
  v_cur := coalesce(a.allocated_to_id, a.assignor_id);
  v_steps := p_level;
  while v_steps > 0 and v_cur is not null loop
    select manager_id into v_cur from person where id = v_cur;
    v_steps := v_steps - 1;
  end loop;
  -- climbing past the top lands on the top, not on nobody
  if v_cur is null then
    select id into v_cur from person
     where manager_id is null and employment_status = 'ACTIVE' and superseded_by is null
     limit 1;
  end if;
  v_trace := v_trace || jsonb_build_object('tried','hierarchy walk','hit', v_cur is not null);

  return jsonb_build_object('person_id', v_cur, 'chair_id', null,
    'fallback_used', true,
    'fallback_reason',
      'No escalation matrix row for level ' || p_level || ' at client ' ||
      coalesce((select name from client where id = vc.client_id), 'unknown') ||
      ', location ' || coalesce((select name from geo_node where id = a.to_location_id), 'unknown') ||
      '. Delivered by walking up the line from the assignee instead.',
    'trace', v_trace);
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_escalation_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; v_step int; v_level int; v_raised int := 0; l int; res jsonb;
begin
  v_step := greatest(ogl_setting_int('ogl_escalation_step_minutes', 240), 1);

  for r in
    select si.id, si.assignment_id, si.calendar_id,
           coalesce(si.extended_to, si.due_at) as deadline
      from sla_instance si
      join assignment a on a.id = si.assignment_id
     where si.stopped_at is null
       and si.sla_status = 'BREACHED'
       and a.current_state not in ('CLOSED','CANCELLED')
       -- a paused clock is not breaching; nothing to climb
       and not exists (select 1 from sla_clock_segment s
                        where s.sla_instance_id = si.id and s.closed_at is null
                          and s.counts_to_sla = false)
  loop
    v_level := least(4, 1 + (business_minutes_between(r.deadline, now(), r.calendar_id) / v_step)::int);
    -- every level up to the current one, so a sweep that was not running
    -- for a day does not skip the levels it slept through
    for l in 1..v_level loop
      res := raise_escalation(r.assignment_id, l, 'BREACH');
      if not coalesce((res->>'duplicate')::boolean, false) and res ? 'id' then
        v_raised := v_raised + 1;
      end if;
    end loop;
  end loop;

  return jsonb_build_object('escalations_raised', v_raised);
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_grant_participant(p_assignment uuid, p_person uuid, p_actor uuid, p_reason text, p_hours integer DEFAULT 72)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a assignment%rowtype; v_id uuid;
begin
  select * into a from assignment where id = p_assignment;
  if not found then return jsonb_build_object('error','no_such_assignment'); end if;
  if a.assignor_id is distinct from p_actor
     and (select app_role from person where id = p_actor) is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_permitted',
      'reason','The assignor or an administrator lends access to an assignment.');
  end if;
  if coalesce(btrim(coalesce(p_reason,'')),'') = '' then
    return jsonb_build_object('error','reason_required',
      'reason','Lending access needs a reason. That is the whole record of why.');
  end if;

  insert into temp_participant_grant (assignment_id, person_id, granted_by, reason, expires_at)
  values (p_assignment, p_person, p_actor, p_reason,
          now() + (greatest(1, least(p_hours, 720)) || ' hours')::interval)
  returning id into v_id;

  insert into assignment_event (assignment_id, event_type, actor_id, payload)
  values (p_assignment, 'PARTICIPANT_GRANTED', p_actor,
          jsonb_build_object('person', p_person, 'reason', p_reason, 'hours', p_hours));
  return jsonb_build_object('id', v_id, 'expires_in_hours', p_hours);
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_is_working_day(p_day date, p_cal uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select case extract(isodow from p_day)
           when 6 then (select works_saturday from business_calendar where id = p_cal)
           when 7 then (select works_sunday   from business_calendar where id = p_cal)
           else true
         end
     and not exists (select 1 from holiday h where h.day = p_day and h.confirmed)
$function$
;

CREATE OR REPLACE FUNCTION public.ogl_list(p_person uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_admin boolean;
begin
  select app_role = 'ADMIN' into v_admin from person where id = p_person;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.due_at nulls last)
      from (
        select a.id, a.ref, a.current_state, a.created_at, a.closed_at,
               vc.applicant_name, vc.force1_case_id,
               c.name as client, g.name as location,
               si.sla_status, si.due_at,
               n.full_name as next_action_owner
          from assignment a
          join verification_case vc on vc.id = a.case_id
          join client c on c.id = vc.client_id
          join geo_node g on g.id = a.to_location_id
          left join sla_instance si on si.assignment_id = a.id
                                   and si.breach_cycle_no = a.breach_cycle_no
          left join person n on n.id = a.next_action_owner_id
         where v_admin
            or a.assignor_id = p_person
            or a.allocated_to_id = p_person
            or a.next_action_owner_id = p_person
         order by si.due_at nulls last
         limit 200) x), '[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_live_sla(p_assignment uuid)
 RETURNS sla_instance
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select si.* from sla_instance si
    join assignment a on a.id = si.assignment_id
   where si.assignment_id = p_assignment
     and si.breach_cycle_no = a.breach_cycle_no
     and si.stopped_at is null
   limit 1
$function$
;

CREATE OR REPLACE FUNCTION public.ogl_notify(p_assignment uuid, p_person uuid, p_template text, p_subject text, p_body text, p_scope text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_email text; a assignment%rowtype;
begin
  if p_person is null then return jsonb_build_object('skipped','no_person'); end if;
  select work_email into v_email from person
   where id = p_person and employment_status = 'ACTIVE' and superseded_by is null;
  if v_email is null then return jsonb_build_object('skipped','no_active_person'); end if;
  select * into a from assignment where id = p_assignment;

  return mail_enqueue(p_template, v_email,
    coalesce(a.ref, '') || ' - ' || p_subject,
    p_body || E'\n\n' || 'Assignment ' || coalesce(a.ref,'') ||
      ', currently ' || coalesce(a.current_state,'') || '.',
    'assignment', p_assignment, null, now(),
    coalesce(p_scope, p_assignment::text || ':' || p_template || ':' || current_date::text));
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_open_points(p_assignment uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.force1_point_id), '[]'::jsonb) from (
    select r.id, r.force1_point_id, r.status, r.attempt_no, r.lineage,
           t.label as verification_type, p.name as party, p.party_role, p.address
      from case_verification_requirement r
      join assignment a on a.case_id = r.case_id
      join verification_type t on t.id = r.verification_type_id
      join case_party p on p.id = r.party_id
     where a.id = p_assignment and r.status in ('PENDING','IN_PROGRESS')) x
$function$
;

CREATE OR REPLACE FUNCTION public.ogl_pause_preview(p_assignment uuid, p_reason uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  si sla_instance%rowtype; r reason_taxonomy%rowtype;
  v_elapsed int; v_pct numeric; v_limit int; v_cap int;
  c1 boolean; c2 boolean; c3 boolean; v_prior int;
begin
  si := ogl_live_sla(p_assignment);
  if si.id is null then
    return jsonb_build_object('eligible', false,
      'reason','This assignment has no running clock, so there is nothing to pause.');
  end if;
  select * into r from reason_taxonomy where id = p_reason;

  v_limit := ogl_setting_int('ogl_pause_consumed_pct', 50);
  v_cap   := ogl_setting_int('ogl_pause_cap_minutes', 120);
  v_elapsed := ogl_elapsed_sla(si.id);
  v_pct := round(100.0 * v_elapsed / greatest(si.tat_business_minutes,1), 1);

  select count(*) into v_prior from assignment_request
   where assignment_id = p_assignment and breach_cycle_no = si.breach_cycle_no
     and pause_granted;

  c1 := v_pct < v_limit;
  c2 := v_prior = 0;
  c3 := coalesce(r.pause_eligible, false);

  return jsonb_build_object(
    'eligible', c1 and c2 and c3,
    'cap_minutes', v_cap,
    'elapsed_minutes', v_elapsed,
    'tat_minutes', si.tat_business_minutes,
    'consumed_pct', v_pct,
    'conditions', jsonb_build_array(
      jsonb_build_object('test','Less than ' || v_limit || '% of the time has gone',
        'pass', c1,
        'detail', v_elapsed || ' of ' || si.tat_business_minutes ||
                  ' business minutes used, ' || v_pct || '%'),
      jsonb_build_object('test','No pause has been granted on this cycle yet',
        'pass', c2,
        'detail', case when c2 then 'none so far'
                       else v_prior || ' already granted on cycle ' || si.breach_cycle_no end),
      jsonb_build_object('test','The reason given may stop the clock',
        'pass', c3,
        'detail', case when r.id is null then 'no reason chosen'
                       when c3 then r.label || ' - the information is somebody else''s to supply'
                       else r.label || ' - this is ours to resolve, so the clock keeps running' end)),
    'plain', case
      when c1 and c2 and c3 then
        'The clock will stop while this is open, for at most ' || v_cap ||
        ' business minutes. Anything beyond that still counts against the deadline.'
      else 'The clock will keep running. Raising this is still the right thing to do; it simply does not buy time.'
      end);
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_pending_decisions(p_person uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.asked_at), '[]'::jsonb) from (
    select d.id, d.force1_point_id, d.address_match, d.match_score, d.proposed,
           d.new_address, d.asked_at, a.ref, a.id as assignment_id,
           vc.applicant_name,
           pc.applicant_address as prior_address,
           pa.ref as prior_ref,
           pr.status as prior_status, pr.attempt_no as prior_attempt
      from repeat_point_decision d
      join assignment a on a.id = d.assignment_id
      join verification_case vc on vc.id = d.case_id
      join case_verification_requirement pr on pr.id = d.prior_requirement_id
      join verification_case pc on pc.id = pr.case_id
      left join assignment pa on pa.case_id = pr.case_id
     where d.decision is null
       and (a.assignor_id = p_person
            or (select app_role from person where id = p_person) = 'ADMIN')
     order by d.asked_at) x
$function$
;

CREATE OR REPLACE FUNCTION public.ogl_people()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.full_name), '[]'::jsonb) from (
    select p.id, p.full_name, p.work_email, d.title as designation
      from person p left join designation d on d.id = p.designation_id
     where p.employment_status = 'ACTIVE' and p.superseded_by is null) x
$function$
;

CREATE OR REPLACE FUNCTION public.ogl_reasons(p_context text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.context, x.label), '[]'::jsonb) from (
    select id, context, code, label, requires_remarks, implied_attribution, pause_eligible
      from reason_taxonomy
     where active and (p_context is null or context = p_context)) x
$function$
;

CREATE OR REPLACE FUNCTION public.ogl_repeat_decide(p_decision uuid, p_actor uuid, p_choice text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  d repeat_point_decision%rowtype; a assignment%rowtype;
  pr case_verification_requirement%rowtype; v_new uuid;
begin
  select * into d from repeat_point_decision where id = p_decision for update;
  if not found then return jsonb_build_object('error','no_such_decision'); end if;
  if d.decision is not null then
    return jsonb_build_object('error','already_decided',
      'reason','That was decided on ' || to_char(ogl_ts(d.decided_at),'DD Mon') ||
               ' as ' || d.decision || '.');
  end if;
  if p_choice not in ('REVISIT','REOPEN','NEW_ASSIGNMENT','REFUSED_DUPLICATE') then
    return jsonb_build_object('error','bad_choice',
      'reason','The choices are REVISIT, REOPEN, NEW_ASSIGNMENT and REFUSED_DUPLICATE.');
  end if;

  select * into a from assignment where id = d.assignment_id;
  if a.assignor_id is distinct from p_actor
     and (select app_role from person where id = p_actor) is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_yours_to_decide',
      'reason','The assignor decides what a repeated Point ID means.');
  end if;
  -- a fuzzy or different address may not be called a revisit on a shrug
  if p_choice = 'REVISIT' and d.address_match = 'DIFFERENT'
     and coalesce(btrim(coalesce(p_reason,'')),'') = '' then
    return jsonb_build_object('error','reason_required',
      'reason','The address is different from the previous attempt. Calling it a '
             ||'revisit needs a sentence saying why.');
  end if;

  select * into pr from case_verification_requirement where id = d.prior_requirement_id;

  if p_choice = 'REVISIT' then
    -- new work against the same point: a fresh attempt, the prior one left
    -- closed and fully readable
    insert into case_verification_requirement (case_id, party_id, verification_type_id,
      force1_point_id, attempt_no, lineage, supersedes_id)
    values (d.case_id, d.party_id, d.verification_type_id, d.force1_point_id,
      pr.attempt_no + 1, 'REVISIT', pr.id)
    returning id into v_new;

  elsif p_choice = 'REOPEN' then
    -- "overwrite" is a workflow word, never a storage one: the earlier report
    -- stays retrievable under its own attempt, marked superseded
    insert into case_verification_requirement (case_id, party_id, verification_type_id,
      force1_point_id, attempt_no, lineage, supersedes_id)
    values (d.case_id, d.party_id, d.verification_type_id, d.force1_point_id,
      pr.attempt_no + 1, 'REOPENED', pr.id)
    returning id into v_new;
    update case_verification_requirement set status = 'SUPERSEDED' where id = pr.id;

  elsif p_choice = 'NEW_ASSIGNMENT' then
    insert into case_verification_requirement (case_id, party_id, verification_type_id,
      force1_point_id, attempt_no, lineage)
    values (d.case_id, d.party_id, d.verification_type_id, d.force1_point_id,
      pr.attempt_no + 1, 'ORIGINAL')
    returning id into v_new;
  end if;
  -- REFUSED_DUPLICATE creates nothing; the point was keyed in error

  update repeat_point_decision
     set decision = p_choice, decided_by = p_actor, decided_at = now(),
         reason = p_reason, new_requirement_id = v_new
   where id = p_decision;

  insert into assignment_event (assignment_id, event_type, actor_id, payload)
  values (d.assignment_id, 'REPEAT_POINT_DECIDED', p_actor,
          jsonb_build_object('point_id', d.force1_point_id, 'decision', p_choice,
                             'address_match', d.address_match, 'score', d.match_score,
                             'reason', p_reason, 'requirement', v_new));

  return jsonb_build_object('id', p_decision, 'decision', p_choice,
    'requirement', v_new,
    'still_waiting', (select count(*) from repeat_point_decision
                       where assignment_id = d.assignment_id and decision is null));
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_report_point(p_requirement uuid, p_actor uuid, p_outcome text, p_remarks text DEFAULT NULL::text, p_findings jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r case_verification_requirement%rowtype; a assignment%rowtype; v_left int;
begin
  select * into r from case_verification_requirement where id = p_requirement for update;
  if not found then return jsonb_build_object('error','no_such_requirement'); end if;

  select * into a from assignment where case_id = r.case_id
   order by created_at desc limit 1;
  if a.id is null then return jsonb_build_object('error','no_assignment_for_case'); end if;

  if a.allocated_to_id is distinct from p_actor
     and (select app_role from person where id = p_actor) is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_the_assignee',
      'reason','The person the work is allocated to reports what they found.');
  end if;
  if a.current_state not in ('IN_PROGRESS','REWORK') then
    return jsonb_build_object('error','wrong_state',
      'reason','Findings are recorded while work is in progress. This is ' || a.current_state || '.');
  end if;
  if r.status in ('CLOSED','CANCELLED','SUPERSEDED') then
    return jsonb_build_object('error','not_open',
      'reason','That point is ' || r.status || '.');
  end if;
  if p_outcome not in ('POSITIVE','NEGATIVE','REFER','UNTRACEABLE','PARTIAL') then
    return jsonb_build_object('error','bad_outcome',
      'reason','The outcome is one of POSITIVE, NEGATIVE, REFER, UNTRACEABLE or PARTIAL.');
  end if;
  -- anything but a clean positive has to say what happened
  if p_outcome <> 'POSITIVE' and coalesce(btrim(coalesce(p_remarks,'')),'') = '' then
    return jsonb_build_object('error','remarks_required',
      'reason','A ' || p_outcome || ' finding needs a sentence saying what was seen.');
  end if;

  update case_verification_requirement
     set status = 'REPORTED', outcome = p_outcome, remarks = p_remarks,
         findings = coalesce(p_findings, '{}'::jsonb),
         reported_at = now(), reported_by = p_actor
   where id = p_requirement;

  insert into assignment_event (assignment_id, event_type, actor_id, payload)
  values (a.id, 'POINT_REPORTED', p_actor,
          jsonb_build_object('requirement', p_requirement, 'point_id', r.force1_point_id,
                             'outcome', p_outcome, 'remarks', p_remarks));

  select count(*) into v_left from case_verification_requirement
   where case_id = r.case_id and status in ('PENDING','IN_PROGRESS');

  return jsonb_build_object('id', p_requirement, 'outcome', p_outcome,
    'still_to_report', v_left,
    'note', case when v_left = 0
      then 'Every point is reported. The assignment can be completed.'
      else v_left || ' point(s) still to report.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_request_raise(p_assignment uuid, p_type text, p_actor uuid, p_reason uuid, p_remarks text DEFAULT NULL::text, p_delay_category text DEFAULT NULL::text, p_expected_completion timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a assignment%rowtype; si sla_instance%rowtype; r reason_taxonomy%rowtype;
  v_seq int; v_id uuid; v_sub int; v_due timestamptz;
  v_pause jsonb; v_granted boolean := false; v_to text; v_counter uuid;
  v_actor_name text;
begin
  if p_type not in ('RFI','DELAY','DISPUTE','HOLD') then
    return jsonb_build_object('error','unknown_request',
      'reason','A request is one of RFI, DELAY, DISPUTE or HOLD.');
  end if;

  select * into a from assignment where id = p_assignment for update;
  if not found then return jsonb_build_object('error','no_such_assignment'); end if;

  select * into r from reason_taxonomy where id = p_reason and active;
  if not found then
    return jsonb_build_object('error','no_such_reason',
      'reason','Choose a reason from the list for this kind of request.');
  end if;
  if r.context <> p_type then
    return jsonb_build_object('error','wrong_reason_context',
      'reason','"' || r.label || '" is a ' || r.context || ' reason, not a ' || p_type || ' one.');
  end if;
  if r.requires_remarks and coalesce(btrim(coalesce(p_remarks,'')),'') = '' then
    return jsonb_build_object('error','remarks_required',
      'reason','"' || r.label || '" needs a sentence saying what happened.');
  end if;

  -- who may raise what. The assignee reports what is in their way; the
  -- assignor disputes what came back. Neither does the other's.
  if p_type in ('RFI','DELAY') then
    if a.allocated_to_id is distinct from p_actor then
      return jsonb_build_object('error','not_the_assignee',
        'reason','Only the person the work is allocated to raises a ' || p_type || '.');
    end if;
    if a.current_state not in ('IN_PROGRESS','REWORK') then
      return jsonb_build_object('error','wrong_state',
        'reason','A ' || p_type || ' is raised while work is in progress. This is ' || a.current_state || '.');
    end if;
  elsif p_type = 'DISPUTE' then
    if a.assignor_id is distinct from p_actor then
      return jsonb_build_object('error','not_the_assignor',
        'reason','Only the assignor disputes a completed report.');
    end if;
    if a.current_state <> 'UNDER_REVIEW' then
      return jsonb_build_object('error','wrong_state',
        'reason','A dispute is raised on a report under review. This is ' || a.current_state || '.');
    end if;
  else -- HOLD
    if a.assignor_id is distinct from p_actor
       and (select app_role from person where id = p_actor) is distinct from 'ADMIN' then
      return jsonb_build_object('error','not_permitted',
        'reason','A hold is placed by the assignor or an administrator.');
    end if;
    if a.current_state in ('CLOSED','CANCELLED','COMPLETED','UNDER_REVIEW') then
      return jsonb_build_object('error','wrong_state',
        'reason','There is nothing left running to hold.');
    end if;
  end if;

  if p_type <> 'DISPUTE' and a.open_request_type is not null then
    return jsonb_build_object('error','request_open',
      'reason','A ' || a.open_request_type || ' is already open. Resolve it first.');
  end if;
  if p_type = 'DELAY' and a.delay_count >= 3 then
    return jsonb_build_object('error','delay_limit',
      'reason','Three delays have already been reported on this assignment.');
  end if;
  if p_type = 'DELAY' and p_expected_completion is null then
    return jsonb_build_object('error','expected_completion_required',
      'reason','A reported delay has to say when the work will be done.');
  end if;

  si := ogl_live_sla(p_assignment);

  -- the clock, decided before the row is written so the decision and its
  -- arithmetic are stored with the request rather than recomputed later
  if p_type in ('RFI','HOLD') and si.id is not null then
    if p_type = 'RFI' then
      v_pause := ogl_pause_preview(p_assignment, p_reason);
      v_granted := (v_pause->>'eligible')::boolean;
    else
      v_granted := r.pause_eligible;
      v_pause := jsonb_build_object('eligible', v_granted,
        'plain','An approved hold stops the clock for as long as it lasts.');
    end if;
  end if;

  v_sub := case p_type
             when 'RFI'   then ogl_setting_int('ogl_rfi_sub_tat_minutes', 120)
             when 'DELAY' then ogl_setting_int('ogl_delay_sub_tat_minutes', 60)
             else null end;
  if v_sub is not null and si.id is not null then
    v_due := add_business_minutes(now(), v_sub, si.calendar_id);
  end if;

  select coalesce(max(seq_no),0) + 1 into v_seq from assignment_request
   where assignment_id = p_assignment and request_type = p_type
     and breach_cycle_no = a.breach_cycle_no;

  insert into assignment_request (assignment_id, breach_cycle_no, request_type, seq_no,
    raised_by, reason_id, remarks, delay_category, expected_completion,
    sub_tat_minutes, sub_tat_due_at, pause_granted)
  values (p_assignment, a.breach_cycle_no, p_type, v_seq, p_actor, p_reason, p_remarks,
    coalesce(p_delay_category, case when p_type='DELAY' then r.implied_attribution end),
    p_expected_completion, v_sub, v_due, v_granted)
  returning id into v_id;

  if v_granted and si.id is not null then
    perform ogl_segment_open(si.id, 'PAUSED', coalesce(r.implied_attribution,'EXTERNAL'),
                             false, false, p_reason, r.label, p_actor);
  end if;

  if p_type <> 'DISPUTE' then
    update assignment set open_request_type = p_type where id = p_assignment;
  end if;

  insert into assignment_event (assignment_id, event_type, actor_id, from_state, to_state, payload)
  values (p_assignment, p_type || '_RAISED', p_actor, a.current_state, a.current_state,
          jsonb_build_object('request', v_id, 'reason', r.code, 'remarks', p_remarks,
                             'pause', v_pause, 'sub_tat_due_at', v_due));
  if v_sub is not null then
    insert into assignment_event (assignment_id, event_type, actor_id, is_system, payload)
    values (p_assignment, 'SUB_TAT_STARTED', p_actor, true,
            jsonb_build_object('request', v_id, 'minutes', v_sub, 'due_at', v_due));
  end if;

  -- the state move, through the only thing allowed to make one
  if p_type = 'RFI' then
    perform ogl_transition(p_assignment, 'AWAITING_INFORMATION', p_actor, r.label);
    v_counter := a.assignor_id;
  elsif p_type = 'DELAY' then
    perform ogl_transition(p_assignment, 'DELAY_REVIEW', p_actor, r.label);
    v_counter := a.assignor_id;
  elsif p_type = 'DISPUTE' then
    if a.dispute_count >= 2 then
      perform ogl_transition(p_assignment, 'ARBITRATION', p_actor, r.label);
    else
      perform ogl_transition(p_assignment, 'REWORK', p_actor, r.label);
    end if;
    v_counter := a.allocated_to_id;
  else
    v_counter := a.allocated_to_id;
  end if;

  select full_name into v_actor_name from person where id = p_actor;
  select coalesce(a.ref,'') into v_to;

  perform ogl_notify(p_assignment, v_counter, p_type || '_RAISED',
    case p_type when 'RFI' then 'information needed'
                when 'DELAY' then 'a delay has been reported'
                when 'DISPUTE' then 'the report has been disputed'
                else 'placed on hold' end,
    coalesce(v_actor_name,'Someone') || ' raised a ' || p_type || ' on ' || v_to || '.' ||
    E'\n' || 'Reason: ' || r.label ||
    coalesce(E'\n' || 'Remarks: ' || p_remarks, '') ||
    case when v_due is not null then
      E'\n' || 'You have until ' || to_char(ogl_ts(v_due), 'DD Mon, HH24:MI') ||
      ' IST to respond.' else '' end,
    p_assignment::text || ':' || p_type || ':' || v_id::text);

  return jsonb_build_object('id', v_id, 'type', p_type, 'seq_no', v_seq,
    'pause_granted', v_granted, 'pause', v_pause,
    'sub_tat_due_at', v_due,
    'state', (select current_state from assignment where id = p_assignment));
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_request_resolve(p_request uuid, p_resolution text, p_actor uuid, p_remarks text DEFAULT NULL::text, p_system boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  q assignment_request%rowtype; a assignment%rowtype; si sla_instance%rowtype;
  r reason_taxonomy%rowtype; v_paused int; v_credit int; v_cap int;
  v_ext timestamptz; v_ceiling timestamptz; v_attr text; v_ok text[];
  v_new_due timestamptz;
begin
  select * into q from assignment_request where id = p_request for update;
  if not found then return jsonb_build_object('error','no_such_request'); end if;
  if q.resolved_at is not null then
    return jsonb_build_object('error','already_resolved',
      'reason','This was resolved on ' || to_char(ogl_ts(q.resolved_at),'DD Mon at HH24:MI') ||
               ' as ' || q.resolution || '.');
  end if;

  select * into a from assignment where id = q.assignment_id for update;
  select * into r from reason_taxonomy where id = q.reason_id;

  v_ok := case q.request_type
            when 'RFI'   then array['ANSWERED','REJECTED_INVALID']
            when 'DELAY' then array['ACCEPTED','DENIED','AUTO_ACCEPTED']
            when 'HOLD'  then array['RELEASED']
            when 'DISPUTE' then array['UPHELD','NOT_UPHELD']
            end;
  if not (p_resolution = any(v_ok)) then
    return jsonb_build_object('error','bad_resolution',
      'reason','A ' || q.request_type || ' is resolved as one of: ' || array_to_string(v_ok, ', ') || '.');
  end if;

  -- the counterparty answers, not the person who asked. A system sweep is
  -- the one exception and it says so rather than borrowing somebody's name.
  if not p_system then
    if q.request_type in ('RFI','DELAY','HOLD') then
      if a.assignor_id is distinct from p_actor
         and (select app_role from person where id = p_actor) is distinct from 'ADMIN' then
        return jsonb_build_object('error','not_the_assignor',
          'reason','The assignor answers a ' || q.request_type || '.');
      end if;
    end if;
    if p_resolution = 'AUTO_ACCEPTED' then
      return jsonb_build_object('error','not_yours_to_give',
        'reason','AUTO_ACCEPTED is what happens when nobody answers. It is not a choice.');
    end if;
  end if;

  si := ogl_live_sla(q.assignment_id);

  if q.pause_granted and si.id is not null then
    v_paused := ogl_segment_close(si.id, now());
    v_cap := case q.request_type when 'RFI'
               then ogl_setting_int('ogl_pause_cap_minutes', 120)
               else 100000 end;   -- an approved hold is not capped; it is approved
    v_credit := least(coalesce(v_paused,0), v_cap);
    v_new_due := add_business_minutes(si.due_at, v_credit, si.calendar_id);
    update sla_instance set due_at = v_new_due where id = si.id;
    update assignment_request set pause_minutes_credited = v_credit where id = p_request;
    insert into assignment_event (assignment_id, event_type, actor_id, is_system, payload)
    values (q.assignment_id, 'CLOCK_RESUMED', p_actor, p_system,
            jsonb_build_object('paused_minutes', v_paused, 'credited', v_credit,
                               'capped', coalesce(v_paused,0) > v_cap, 'due_at', v_new_due));
  end if;

  -- an accepted delay moves the due date, never past the ceiling, and never
  -- backwards: asking for less time than you already have changes nothing
  if q.request_type = 'DELAY' and p_resolution in ('ACCEPTED','AUTO_ACCEPTED') and si.id is not null then
    v_ceiling := add_business_minutes(coalesce(si.due_at, now()),
                   ogl_setting_int('ogl_delay_extension_cap_minutes', 720), si.calendar_id);
    v_ext := least(coalesce(q.expected_completion, v_ceiling), v_ceiling);
    if v_ext > coalesce(si.extended_to, si.due_at) then
      update sla_instance set extended_to = v_ext where id = si.id;
    else
      v_ext := null;   -- nothing moved; say nothing moved
    end if;
    insert into assignment_event (assignment_id, event_type, actor_id, is_system, payload)
    values (q.assignment_id,
            case when p_resolution='AUTO_ACCEPTED' then 'DELAY_AUTO_ACCEPTED' else 'DELAY_ACCEPTED' end,
            p_actor, p_system,
            jsonb_build_object('asked_for', q.expected_completion, 'granted_to', v_ext,
                               'ceiling', v_ceiling,
                               'capped', coalesce(q.expected_completion, v_ceiling) > v_ceiling,
                               'no_change', v_ext is null));
  end if;

  -- the segment the assignment runs in from here. An auto-accepted delay
  -- runs as PENDING_REVIEW: the time counts against the deadline, because it
  -- passed, but not against anybody's record until a person says whose it
  -- was. Silence must not be able to convict or acquit.
  if si.id is not null and q.request_type <> 'DISPUTE' then
    if p_resolution = 'AUTO_ACCEPTED' then
      v_attr := 'PENDING_REVIEW';
      perform ogl_segment_open(si.id, 'RUNNING', v_attr, true, false, q.reason_id,
                               'auto-accepted delay, attribution not yet confirmed', p_actor);
    else
      v_attr := case when p_resolution = 'ACCEPTED' then coalesce(r.implied_attribution,'ASSIGNEE')
                     else 'ASSIGNEE' end;
      perform ogl_segment_open(si.id, 'RUNNING', v_attr, true,
                               v_attr = 'ASSIGNEE', q.reason_id, r.label, p_actor);
    end if;
  end if;

  update assignment_request set resolution = p_resolution, resolved_by = p_actor,
         resolved_at = now(), resolution_remarks = p_remarks
   where id = p_request;

  if q.request_type <> 'DISPUTE' then
    update assignment set open_request_type = null where id = q.assignment_id;
  end if;

  if not (q.request_type = 'DELAY' and p_resolution in ('ACCEPTED','AUTO_ACCEPTED')) then
    insert into assignment_event (assignment_id, event_type, actor_id, is_system, payload)
    values (q.assignment_id, q.request_type || '_' ||
            case p_resolution when 'REJECTED_INVALID' then 'REJECTED' else p_resolution end,
            p_actor, p_system,
            jsonb_build_object('request', p_request, 'remarks', p_remarks));
  end if;

  if q.request_type in ('RFI','DELAY') and a.current_state in ('AWAITING_INFORMATION','DELAY_REVIEW') then
    perform ogl_transition(q.assignment_id, 'IN_PROGRESS', p_actor,
      q.request_type || ' ' || p_resolution);
  end if;

  perform ogl_notify(q.assignment_id, q.raised_by, q.request_type || '_' || p_resolution,
    case p_resolution
      when 'ANSWERED' then 'your question has been answered'
      when 'REJECTED_INVALID' then 'your request was not accepted'
      when 'ACCEPTED' then 'your delay was accepted'
      when 'AUTO_ACCEPTED' then 'your delay was accepted with nobody reviewing it'
      when 'DENIED' then 'your delay was not accepted'
      else 'the hold has been released' end,
    'The ' || q.request_type || ' you raised has been resolved as ' || p_resolution || '.' ||
    coalesce(E'\n' || 'Remarks: ' || p_remarks, '') ||
    case when v_credit is not null and v_credit > 0 then
      E'\n' || v_credit || ' business minutes were credited back to the clock.'
      else '' end ||
    case when v_ext is not null then
      E'\n' || 'The deadline moved to ' || to_char(ogl_ts(v_ext), 'DD Mon at HH24:MI') || ' IST.'
      else '' end,
    p_request::text || ':resolved');

  return jsonb_build_object('id', p_request, 'resolution', p_resolution,
    'credited_minutes', v_credit, 'extended_to', v_ext,
    'state', (select current_state from assignment where id = q.assignment_id));
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_review_accept(p_assignment uuid, p_actor uuid, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a assignment%rowtype; r jsonb;
begin
  select * into a from assignment where id = p_assignment for update;
  if not found then return jsonb_build_object('error','no_such_assignment'); end if;
  if a.current_state <> 'UNDER_REVIEW' then
    return jsonb_build_object('error','wrong_state',
      'reason','A report is accepted while it is under review. This is ' || a.current_state || '.');
  end if;
  if a.assignor_id is distinct from p_actor
     and (select app_role from person where id = p_actor) is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_the_assignor',
      'reason','The assignor accepts the report.');
  end if;

  update case_verification_requirement set status = 'CLOSED'
   where case_id = a.case_id and status = 'REPORTED';

  insert into assignment_event (assignment_id, event_type, actor_id, payload)
  values (p_assignment, 'REVIEW_ACCEPTED', p_actor, jsonb_build_object('remarks', p_remarks));

  r := ogl_transition(p_assignment, 'CLOSED', p_actor, coalesce(p_remarks, 'report accepted'));
  perform ogl_notify(p_assignment, a.allocated_to_id, 'REVIEW_ACCEPTED',
    'your report was accepted', 'The report you submitted has been accepted and the assignment is closed.',
    p_assignment::text || ':accepted');
  return r;
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_revoke_participant(p_grant uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g temp_participant_grant%rowtype;
begin
  select * into g from temp_participant_grant where id = p_grant;
  if not found then return jsonb_build_object('error','no_such_grant'); end if;
  update temp_participant_grant set revoked_at = now()
   where id = p_grant and revoked_at is null;
  insert into assignment_event (assignment_id, event_type, actor_id, payload)
  values (g.assignment_id, 'PARTICIPANT_REVOKED', p_actor,
          jsonb_build_object('grant', p_grant, 'person', g.person_id));
  return jsonb_build_object('id', p_grant, 'revoked', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_segment_close(p_sla uuid, p_at timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_seg sla_clock_segment%rowtype; v_cal uuid; v_min int;
begin
  select * into v_seg from sla_clock_segment
   where sla_instance_id = p_sla and closed_at is null for update;
  if not found then return null; end if;

  select calendar_id into v_cal from sla_instance where id = p_sla;
  v_min := business_minutes_between(v_seg.opened_at, greatest(p_at, v_seg.opened_at), v_cal);

  update sla_clock_segment
     set closed_at = greatest(p_at, v_seg.opened_at), business_minutes = v_min
   where id = v_seg.id;
  return v_min;
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_segment_open(p_sla uuid, p_state text, p_attribution text, p_counts_sla boolean, p_counts_strike boolean, p_reason uuid DEFAULT NULL::uuid, p_reason_text text DEFAULT NULL::text, p_by uuid DEFAULT NULL::uuid, p_at timestamp with time zone DEFAULT now())
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_id uuid; v_seq int;
begin
  perform ogl_segment_close(p_sla, p_at);
  select coalesce(max(seq_no), 0) + 1 into v_seq
    from sla_clock_segment where sla_instance_id = p_sla;

  insert into sla_clock_segment (sla_instance_id, seq_no, segment_state, attribution,
         counts_to_sla, counts_to_strike, reason_id, reason_text, opened_at, set_by)
  values (p_sla, v_seq, p_state, p_attribution, p_counts_sla, p_counts_strike,
          p_reason, p_reason_text, p_at, p_by)
  returning id into v_id;
  return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_setting_int(p_key text, p_default integer)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce((select nullif(value,'')::int from app_setting where key = p_key), p_default)
$function$
;

CREATE OR REPLACE FUNCTION public.ogl_sla_start(p_assignment uuid, p_actor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a assignment%rowtype; vc verification_case%rowtype;
  v_cal uuid; v_rule sla_rule%rowtype; v_trace jsonb; v_id uuid;
  v_due timestamptz; v_vtype uuid;
begin
  select * into a from assignment where id = p_assignment;
  if not found then return jsonb_build_object('error','no_such_assignment'); end if;

  if exists (select 1 from sla_instance
              where assignment_id = p_assignment and breach_cycle_no = a.breach_cycle_no) then
    return jsonb_build_object('exists', true,
      'reason','Cycle ' || a.breach_cycle_no || ' already has a clock.');
  end if;

  select * into vc from verification_case where id = a.case_id;
  select r.verification_type_id into v_vtype from case_verification_requirement r
   where r.case_id = a.case_id order by r.attempt_no desc limit 1;

  -- the calendar of the location the work is in, else the default
  select id into v_cal from business_calendar
   where geo_node_id = a.to_location_id and effective_to is null limit 1;
  if v_cal is null then
    select id into v_cal from business_calendar where code = 'DEFAULT' limit 1;
  end if;
  if v_cal is null then
    return jsonb_build_object('error','no_calendar',
      'reason','No business calendar is configured, so no deadline can be computed.');
  end if;

  with scored as (
    select r.*,
      (case when r.client_id is not null and r.client_id = vc.client_id then 16 else 0 end) +
      (case when r.verification_type_id is not null and r.verification_type_id = v_vtype then 16 else 0 end) +
      (case when r.geo_node_id is not null and r.geo_node_id = a.to_location_id then 8 else 0 end) +
      (case when r.priority is not null and r.priority = a.priority_bucket then 8 else 0 end)
        as score
      from sla_rule r
     where r.effective_from <= current_date
       and (r.effective_to is null or r.effective_to >= current_date)
       and (r.client_id is null or r.client_id = vc.client_id)
       and (r.verification_type_id is null or r.verification_type_id = v_vtype)
       and (r.geo_node_id is null or r.geo_node_id = a.to_location_id)
       and (r.priority is null or r.priority = a.priority_bucket)
  )
  select * into v_rule from scored order by score desc, effective_from desc, version desc limit 1;

  if v_rule.id is null then
    return jsonb_build_object('error','no_rule',
      'reason','No SLA rule matches this assignment, so no deadline can be set. '
             ||'Load a rate card and an SLA rule before starting work.');
  end if;

  with scored as (
    select r.code, r.version, r.tat_business_minutes,
      (case when r.client_id is not null and r.client_id = vc.client_id then 16 else 0 end) +
      (case when r.verification_type_id is not null and r.verification_type_id = v_vtype then 16 else 0 end) +
      (case when r.geo_node_id is not null and r.geo_node_id = a.to_location_id then 8 else 0 end) +
      (case when r.priority is not null and r.priority = a.priority_bucket then 8 else 0 end)
        as score
      from sla_rule r
     where r.effective_from <= current_date
       and (r.effective_to is null or r.effective_to >= current_date)
  )
  select jsonb_build_object(
    'chosen', jsonb_build_object('code', v_rule.code, 'version', v_rule.version),
    'dimensions', jsonb_build_object('client', 16, 'verification_type', 16,
                                     'geography', 8, 'priority', 8),
    'runners_up', coalesce(jsonb_agg(jsonb_build_object(
        'code', s.code, 'version', s.version, 'score', s.score,
        'tat', s.tat_business_minutes) order by s.score desc), '[]'::jsonb))
    into v_trace
    from (select * from scored order by score desc limit 5) s;

  v_due := add_business_minutes(now(), v_rule.tat_business_minutes, v_cal);

  insert into sla_instance (assignment_id, breach_cycle_no, sla_rule_id, rule_trace,
    calendar_id, tat_business_minutes, started_at, due_at)
  values (p_assignment, a.breach_cycle_no, v_rule.id, v_trace, v_cal,
    v_rule.tat_business_minutes, now(), v_due)
  returning id into v_id;

  perform ogl_segment_open(v_id, 'RUNNING', 'ASSIGNEE', true, true, null,
                           'work in progress', p_actor);

  insert into assignment_event (assignment_id, event_type, actor_id, payload)
  values (p_assignment, 'SLA_INSTANCE_CREATED', p_actor,
          jsonb_build_object('instance', v_id, 'cycle', a.breach_cycle_no,
                             'tat', v_rule.tat_business_minutes, 'due_at', v_due,
                             'rule', v_rule.code || ' v' || v_rule.version));

  return jsonb_build_object('id', v_id, 'due_at', v_due,
    'tat_business_minutes', v_rule.tat_business_minutes,
    'rule', v_rule.code || ' v' || v_rule.version, 'trace', v_trace);
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_sla_stop(p_assignment uuid, p_actor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare si sla_instance%rowtype; v_min int;
begin
  si := ogl_live_sla(p_assignment);
  if si.id is null then return jsonb_build_object('skipped','no_running_clock'); end if;
  v_min := ogl_segment_close(si.id, now());
  update sla_instance set stopped_at = now() where id = si.id;
  insert into assignment_event (assignment_id, event_type, actor_id, is_system, payload)
  values (p_assignment, 'CLOCK_STOPPED', p_actor, p_actor is null,
          jsonb_build_object('instance', si.id, 'final_segment_minutes', v_min,
                             'elapsed', ogl_elapsed_sla(si.id)));
  return jsonb_build_object('instance', si.id, 'elapsed', ogl_elapsed_sla(si.id));
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_strike_exposure(p_sla uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(sum(
           case when s.closed_at is not null then s.business_minutes
                else business_minutes_between(s.opened_at, now(), si.calendar_id) end), 0)::int
    from sla_clock_segment s join sla_instance si on si.id = s.sla_instance_id
   where s.sla_instance_id = p_sla
     and s.counts_to_strike and s.attribution = 'ASSIGNEE'
$function$
;

CREATE OR REPLACE FUNCTION public.ogl_strike_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r record; v_made int := 0; v_no int; v_window int; v_exposure int; v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtext('ogl_strike_sweep'));
  v_window := ogl_setting_int('ogl_strike_window_days', 90);

  for r in
    select si.id as sla_id, si.assignment_id, si.breach_cycle_no,
           si.tat_business_minutes, si.calendar_id,
           coalesce(si.extended_to, si.due_at) as deadline,
           coalesce(sr.grace_minutes, 0) as grace,
           a.allocated_to_id, a.to_location_id, a.ref
      from sla_instance si
      join sla_rule sr on sr.id = si.sla_rule_id
      join assignment a on a.id = si.assignment_id
     where si.sla_status = 'BREACHED'
       and a.allocated_to_id is not null
       and a.current_state not in ('CANCELLED')
       -- nobody is struck for time whose owner has not been established
       and not ogl_attribution_pending(si.id)
       and not exists (select 1 from strike_event s
                        where s.assignment_id = si.assignment_id
                          and s.breach_cycle_no = si.breach_cycle_no
                          and s.trigger_code = 'SLA_BREACH')
  loop
    -- past grace, measured in business minutes like everything else
    if now() <= add_business_minutes(r.deadline, r.grace, r.calendar_id) then
      continue;
    end if;

    -- and the assignee's own time has to exceed the whole TAT. Time that
    -- belonged to the client, the weather or the assignor does not count.
    v_exposure := ogl_strike_exposure(r.sla_id);
    if v_exposure <= r.tat_business_minutes then
      continue;
    end if;

    select count(*) + 1 into v_no from strike_event
     where person_id = r.allocated_to_id and status = 'ACTIVE'
       and occurred_at > now() - (v_window || ' days')::interval;

    insert into strike_event (person_id, location_id, assignment_id, breach_cycle_no,
      trigger_code, occurred_at, attributable_minutes, strike_no, facts)
    values (r.allocated_to_id, r.to_location_id, r.assignment_id, r.breach_cycle_no,
      'SLA_BREACH', now(), v_exposure, v_no,
      jsonb_build_object('ref', r.ref, 'tat', r.tat_business_minutes,
                         'exposure', v_exposure, 'deadline', r.deadline,
                         'grace_minutes', r.grace))
    on conflict (assignment_id, breach_cycle_no, trigger_code) do nothing
    returning id into v_id;

    if v_id is not null then
      v_made := v_made + 1;
      insert into assignment_event (assignment_id, event_type, is_system, payload)
      values (r.assignment_id, 'STRIKE_GENERATED', true,
              jsonb_build_object('strike', v_id, 'person', r.allocated_to_id,
                                 'strike_no', v_no, 'minutes', v_exposure));

      perform ogl_notify(r.assignment_id, r.allocated_to_id, 'STRIKE',
        'a strike has been recorded',
        'A strike has been recorded against ' || r.ref || '. It is strike ' ||
        v_no || ' in the last ' || v_window || ' days.' || E'\n' ||
        v_exposure || ' business minutes of the delay were attributed to you, ' ||
        'against a target of ' || r.tat_business_minutes || '.' || E'\n\n' ||
        'If you believe the attribution is wrong, say so - a strike can be ' ||
        'waived, and the record of the waiver stays visible.',
        r.assignment_id::text || ':strike:' || r.breach_cycle_no);
    end if;
  end loop;

  return jsonb_build_object('strikes_generated', v_made);
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_strike_waive(p_strike uuid, p_actor uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; s strike_event%rowtype;
begin
  select app_role into v_role from person where id = p_actor;
  if v_role not in ('ADMIN','MANAGER') then
    return jsonb_build_object('error','not_permitted',
      'reason','A manager or an administrator waives a strike.');
  end if;
  if coalesce(btrim(coalesce(p_reason,'')),'') = '' then
    return jsonb_build_object('error','reason_required',
      'reason','Waiving a strike needs a reason. It is the whole record of why.');
  end if;
  select * into s from strike_event where id = p_strike;
  if not found then return jsonb_build_object('error','no_such_strike'); end if;
  if s.status <> 'ACTIVE' then
    return jsonb_build_object('error','not_active',
      'reason','That strike is already ' || s.status || '.');
  end if;

  update strike_event set status = 'WAIVED', waived_by = p_actor, waived_reason = p_reason
   where id = p_strike;
  insert into assignment_event (assignment_id, event_type, actor_id, payload)
  values (s.assignment_id, 'STRIKE_WAIVED', p_actor,
          jsonb_build_object('strike', p_strike, 'reason', p_reason));
  return jsonb_build_object('id', p_strike, 'status','WAIVED');
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_strikes(p_person uuid, p_of uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.occurred_at desc), '[]'::jsonb) from (
    select s.id, s.occurred_at, s.trigger_code, s.status, s.strike_no,
           s.attributable_minutes, s.waived_reason, s.facts,
           p.full_name as person, a.ref
      from strike_event s
      join person p on p.id = s.person_id
      left join assignment a on a.id = s.assignment_id
     where (coalesce(p_of, p_person) = s.person_id)
       and (s.person_id = p_person
            or (select app_role from person where id = p_person) in ('ADMIN','MANAGER')
            or p.manager_id = p_person)
     order by s.occurred_at desc limit 100) x
$function$
;

CREATE OR REPLACE FUNCTION public.ogl_sub_tat_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r record; v_breached int := 0; v_auto int := 0; v_esc int := 0; v_prior int;
  a assignment%rowtype;
begin
  for r in
    select q.* from assignment_request q
      join assignment asg on asg.id = q.assignment_id
     where q.resolved_at is null
       and q.sub_tat_breached = false
       and q.sub_tat_due_at is not null
       and q.sub_tat_due_at <= now()
       and asg.current_state not in ('CLOSED','CANCELLED')
     order by q.sub_tat_due_at
  loop
    update assignment_request set sub_tat_breached = true where id = r.id;
    v_breached := v_breached + 1;

    insert into assignment_event (assignment_id, event_type, is_system, payload)
    values (r.assignment_id, 'SUB_TAT_BREACHED', true,
            jsonb_build_object('request', r.id, 'type', r.request_type,
                               'due_at', r.sub_tat_due_at, 'minutes', r.sub_tat_minutes));

    if r.request_type = 'DELAY' then
      -- One auto-accept per assignment. A second unreviewed delay does not
      -- accept itself; it goes up a level. Otherwise silence becomes a
      -- renewable extension, which is exactly how the old system lost a year.
      select count(*) into v_prior from assignment_request
       where assignment_id = r.assignment_id and resolution = 'AUTO_ACCEPTED';

      if v_prior = 0 then
        select * into a from assignment where id = r.assignment_id;
        perform ogl_request_resolve(r.id, 'AUTO_ACCEPTED', a.assignor_id,
          'Nobody reviewed this within ' || r.sub_tat_minutes ||
          ' business minutes, so it was accepted. The time is recorded as ' ||
          'unattributed until somebody confirms whose it was.', true);
        v_auto := v_auto + 1;
        -- the assignor's manager is told, because an auto-accept is a thing
        -- that happened to them rather than a thing they did
        perform ogl_notify(r.assignment_id,
          (select manager_id from person where id = a.assignor_id),
          'DELAY_AUTO_ACCEPTED_MGR', 'a delay accepted itself',
          'A reported delay was accepted automatically because it was not ' ||
          'reviewed within ' || r.sub_tat_minutes || ' business minutes. It is ' ||
          'waiting in Confirm attribution until somebody says whose time it was.',
          r.id::text || ':auto:mgr');
      else
        perform raise_escalation(r.assignment_id, 2, 'SUB_TAT_BREACH');
        v_esc := v_esc + 1;
      end if;
    else
      perform raise_escalation(r.assignment_id, 1, 'SUB_TAT_BREACH');
      v_esc := v_esc + 1;
    end if;
  end loop;

  return jsonb_build_object('sub_tat_breached', v_breached,
    'delays_auto_accepted', v_auto, 'escalated', v_esc);
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_submit(p_assignment uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a assignment%rowtype; vc verification_case%rowtype; v_waiting int; v_pts int;
begin
  select * into a from assignment where id = p_assignment;
  if not found then return jsonb_build_object('error','no_such_assignment'); end if;
  if a.assignor_id is distinct from p_actor
     and (select app_role from person where id = p_actor) is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_the_assignor');
  end if;

  select count(*) into v_waiting from repeat_point_decision
   where assignment_id = p_assignment and decision is null;
  if v_waiting > 0 then
    return jsonb_build_object('error','decisions_waiting',
      'reason', v_waiting || ' repeated Point ID(s) are waiting for you to say what '
             || 'they are. Nothing can start until they are decided.');
  end if;

  select count(*) into v_pts from case_verification_requirement
   where case_id = a.case_id and status not in ('CANCELLED','SUPERSEDED');
  if v_pts = 0 then
    return jsonb_build_object('error','no_verifications',
      'reason','Every verification on this case was refused as a duplicate. '
             ||'There is nothing to send.');
  end if;

  select * into vc from verification_case where id = a.case_id;
  if coalesce(btrim(vc.applicant_name),'') = ''
     or coalesce(btrim(vc.applicant_address),'') = ''
     or coalesce(btrim(vc.applicant_contact),'') = ''
     or coalesce(btrim(vc.pincode),'') = '' then
    return jsonb_build_object('error','incomplete_case',
      'reason','Name, contact, address and pincode are all needed before this goes out.');
  end if;

  return ogl_transition(p_assignment, 'SUBMITTED', p_actor, 'submitted');
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_transition(p_assignment uuid, p_to text, p_actor uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a assignment%rowtype; v_guard text; v_next uuid; v_clock jsonb;
begin
  select * into a from assignment where id = p_assignment for update;
  if not found then
    return jsonb_build_object('error','no_such_assignment');
  end if;

  if a.current_state = p_to then
    return jsonb_build_object('error','already_there',
      'reason','This assignment is already ' || p_to || '.');
  end if;

  select guard_note into v_guard from ogl_transition_rule
   where from_state = a.current_state and to_state = p_to;
  if not found then
    return jsonb_build_object('error','transition_refused',
      'reason', a.current_state || ' does not go to ' || p_to || '.',
      'hint','The states that follow ' || a.current_state || ' are: ' ||
             coalesce((select string_agg(to_state, ', ' order by to_state)
                         from ogl_transition_rule where from_state = a.current_state), 'none'));
  end if;

  if p_to = 'DELAY_REVIEW' and a.delay_count >= 3 then
    return jsonb_build_object('error','delay_limit',
      'reason','Three delays have already been reported on this assignment.');
  end if;
  if p_to = 'REWORK' and a.current_state = 'UNDER_REVIEW' and a.dispute_count >= 2 then
    return jsonb_build_object('error','dispute_limit',
      'reason','Two disputes have already been raised. The third goes to arbitration.');
  end if;
  if p_to = 'CANCELLED' and a.open_request_type is not null then
    return jsonb_build_object('error','request_open',
      'reason','A ' || a.open_request_type || ' is open. Resolve it before cancelling.');
  end if;
  if p_to = 'CLOSED' and a.current_state = 'UNDER_REVIEW' then
    if a.open_request_type is not null then
      return jsonb_build_object('error','request_open',
        'reason','A ' || a.open_request_type || ' is open. Resolve it before closing.');
    end if;
    if exists (select 1 from case_verification_requirement r
                where r.case_id = a.case_id
                  and r.status in ('PENDING','IN_PROGRESS','DISPUTED')) then
      return jsonb_build_object('error','requirement_incomplete',
        'reason','Not every verification on this case has been reported.');
    end if;
  end if;
  if p_to = 'REOPENED' and a.closed_at is not null and a.closed_at < now() - interval '7 days' then
    return jsonb_build_object('error','too_late_to_reopen',
      'reason','A closed assignment can be reopened for seven days. This one closed on '
               || to_char(ogl_ts(a.closed_at), 'DD Mon YYYY') || '.');
  end if;
  if p_to = 'REOPENED' and coalesce(btrim(coalesce(p_reason,'')),'') = '' then
    return jsonb_build_object('error','reason_required',
      'reason','Reopening needs a reason. It is the first thing anyone asks.');
  end if;

  v_next := case p_to
    when 'SUBMITTED'            then null
    when 'ASSIGNED'             then a.allocated_to_id
    when 'ACCEPTED'             then a.allocated_to_id
    when 'IN_PROGRESS'          then a.allocated_to_id
    when 'AWAITING_INFORMATION' then a.assignor_id
    when 'DELAY_REVIEW'         then a.assignor_id
    when 'COMPLETED'            then a.assignor_id
    when 'UNDER_REVIEW'         then a.assignor_id
    when 'REWORK'               then a.allocated_to_id
    when 'ARBITRATION'          then null
    else null end;

  perform set_config('crux.ogl_transition', 'on', true);

  update assignment set
    current_state        = p_to,
    next_action_owner_id = v_next,
    delay_count   = delay_count   + case when p_to = 'DELAY_REVIEW' then 1 else 0 end,
    dispute_count = dispute_count + case when p_to = 'REWORK' and a.current_state = 'UNDER_REVIEW' then 1 else 0 end,
    breach_cycle_no = breach_cycle_no + case when p_to = 'REWORK' or p_to = 'REOPENED' then 1 else 0 end,
    closed_at = case when p_to in ('CLOSED','CANCELLED') then now()
                     when p_to = 'REOPENED' then null
                     else closed_at end
   where id = p_assignment;

  perform set_config('crux.ogl_transition', 'off', true);

  insert into assignment_event (assignment_id, event_type, actor_id, from_state, to_state, payload)
  values (p_assignment, 'STATE_CHANGED', p_actor, a.current_state, p_to,
          jsonb_build_object('reason', p_reason, 'guard', v_guard));

  -- the clock follows the state, in the same transaction as the state
  if p_to = 'IN_PROGRESS' and a.current_state in ('ACCEPTED','REOPENED') then
    v_clock := ogl_sla_start(p_assignment, p_actor);
  elsif p_to in ('REWORK','REOPENED') then
    -- a new cycle is new work with its own deadline; the old one is closed
    perform ogl_sla_stop(p_assignment, p_actor);
    if p_to = 'REWORK' then v_clock := ogl_sla_start(p_assignment, p_actor); end if;
  elsif p_to in ('COMPLETED','CLOSED','CANCELLED') then
    v_clock := ogl_sla_stop(p_assignment, p_actor);
  end if;

  if p_to = 'COMPLETED' then
    perform ogl_transition(p_assignment, 'UNDER_REVIEW', p_actor, 'automatic on completion');
    return jsonb_build_object('state','UNDER_REVIEW','via','COMPLETED','clock', v_clock);
  end if;

  return jsonb_build_object('state', p_to, 'next_action_owner', v_next, 'clock', v_clock);
end $function$
;

CREATE OR REPLACE FUNCTION public.ogl_ts(p text)
 RETURNS timestamp with time zone
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p is null then null
    when p ~ '(Z|[+-]\d{2}:?\d{2})$' then replace(p,' ','T')::timestamptz
    else (replace(p,' ','T')::timestamp at time zone 'Asia/Kolkata')
  end
$function$
;

CREATE OR REPLACE FUNCTION public.ogl_ts(p timestamp with time zone)
 RETURNS timestamp without time zone
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select (p at time zone 'Asia/Kolkata')
$function$
;

CREATE OR REPLACE FUNCTION public.op_alias_remove(p_actor uuid, p_written_as text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_key text; v_means text;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin');
  end if;

  v_key := lower(btrim(coalesce(p_written_as, '')));
  select means into v_means from op_node_alias where written_as = v_key;
  if v_means is null then return jsonb_build_object('error','no_such_alias'); end if;

  delete from op_node_alias where written_as = v_key;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value)
  values (p_actor, 'PLACE_ALIAS_REMOVED', 'op_node_alias', v_key,
          jsonb_build_object('means', v_means));

  return jsonb_build_object('ok', true, 'writtenAs', v_key,
    'note', 'A file that says "' || v_key || '" will now be refused unless the '
            'grouping already calls something that.');
end $function$
;

CREATE OR REPLACE FUNCTION public.op_alias_save(p_actor uuid, p_written_as text, p_means text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_key text; v_target uuid; v_name text;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Spellings are an administrator''s to teach.');
  end if;

  v_key := lower(btrim(coalesce(p_written_as, '')));
  if v_key = '' or coalesce(btrim(p_means), '') = '' then
    return jsonb_build_object('error','incomplete',
      'reason','An alias needs the form a file writes and the place it means.');
  end if;

  if exists (select 1 from op_node o where lower(btrim(o.name)) = v_key) then
    return jsonb_build_object('error','shadows_a_real_name',
      'reason','The grouping already calls something "' || btrim(p_written_as) ||
               '". An alias for it would quietly outrank the real place. Rename '
               'the place instead, or point the file at the name it already has.');
  end if;

  v_target := op_zone_id(p_means);
  if v_target is null then
    return jsonb_build_object('error','means_nothing',
      'reason','"' || btrim(p_means) || '" is not a zone or a location, so the alias '
               'would send the file somewhere that does not exist.');
  end if;
  select name into v_name from op_node where id = v_target;

  insert into op_node_alias (written_as, means, note, created_by)
  values (v_key, btrim(p_means), nullif(btrim(coalesce(p_note, '')), ''), p_actor)
  on conflict (written_as) do update
    set means = excluded.means, note = excluded.note, created_by = excluded.created_by;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'PLACE_ALIAS_SAVED', 'op_node_alias', v_key,
          jsonb_build_object('means', btrim(p_means), 'resolves', v_name));

  return jsonb_build_object('ok', true, 'writtenAs', v_key, 'resolves', v_name,
    'note', 'A file that says "' || btrim(p_written_as) || '" will load against ' || v_name || '.');
end $function$
;

CREATE OR REPLACE FUNCTION public.op_branch_save(p_actor uuid, p_client uuid, p_code text, p_name text, p_node uuid DEFAULT NULL::uuid, p_id uuid DEFAULT NULL::uuid, p_address text DEFAULT NULL::text, p_active boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_id uuid; v_old text; v_client text; v_place text;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','The branch master is an administrator''s to change.');
  end if;
  if coalesce(btrim(p_code),'') = '' or coalesce(btrim(p_name),'') = '' then
    return jsonb_build_object('error','incomplete',
      'reason','A branch needs the code the client calls it and a name a person recognises.');
  end if;

  select name into v_client from client where id = p_client;
  if v_client is null then return jsonb_build_object('error','no_such_client'); end if;
  if p_node is not null then
    select name into v_place from op_node where id = p_node;
    if v_place is null then return jsonb_build_object('error','no_such_place'); end if;
  end if;

  if p_id is not null then
    select name into v_old from branch where id = p_id;
    if v_old is null then return jsonb_build_object('error','no_such_branch'); end if;
    update branch
       set code = btrim(p_code), name = btrim(p_name),
           op_node_id = coalesce(p_node, op_node_id),
           address = coalesce(nullif(btrim(coalesce(p_address,'')), ''), address),
           status = case when p_active is null then status
                         when p_active then 'ACTIVE'::entity_status
                         else 'INACTIVE'::entity_status end,
           updated_at = now()
     where id = p_id returning id into v_id;
  else
    insert into branch (client_id, code, name, address, op_node_id, status, source_ref)
    values (p_client, btrim(p_code), btrim(p_name),
            nullif(btrim(coalesce(p_address,'')), ''), p_node,
            (case when p_active is false then 'INACTIVE' else 'ACTIVE' end)::entity_status,
            'added on the Places screen')
    returning id into v_id;
  end if;

  insert into audit_entry (actor_id, action, entity_type, entity_id, entity_ref, old_value, new_value)
  values (p_actor, case when p_id is null then 'BRANCH_ADDED' else 'BRANCH_CHANGED' end,
          'branch', v_id, btrim(p_code),
          case when v_old is null then null else jsonb_build_object('name', v_old) end,
          jsonb_build_object('client', v_client, 'name', btrim(p_name), 'place', v_place));

  return jsonb_build_object('ok', true, 'id', v_id,
    'note', btrim(p_name) || ' saved' ||
            case when v_place is not null then ' at ' || v_place else '' end || '.');
exception when unique_violation then
  return jsonb_build_object('error','code_taken',
    'reason','That client already has a branch with this code. A code is how the '
             'client names the branch, so two of them would make a file ambiguous.');
end $function$
;

CREATE OR REPLACE FUNCTION public.op_branches(p_node uuid, p_client uuid DEFAULT NULL::uuid, p_q text DEFAULT NULL::text, p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with hit as (
  select b.id, b.code, b.name, b.address, b.status::text as status,
         c.name as client, c.code as client_code, c.id as client_id
    from branch b join client c on c.id = b.client_id
   where b.op_node_id = p_node
     and (p_client is null or b.client_id = p_client)
     and (coalesce(btrim(p_q),'') = ''
          or b.code ilike '%' || btrim(p_q) || '%'
          or b.name ilike '%' || btrim(p_q) || '%')
)
select jsonb_build_object(
  'total', (select count(*) from hit),
  'shown', least((select count(*) from hit), greatest(coalesce(p_limit, 200), 1)),
  'rows', coalesce((select jsonb_agg(to_jsonb(q) order by q.client, q.name)
                      from (select * from hit order by client, name
                             limit greatest(coalesce(p_limit, 200), 1)) q), '[]'::jsonb)
);
$function$
;

CREATE OR REPLACE FUNCTION public.op_bulk_assign(p_actor uuid, p_node uuid, p_person uuid, p_clients uuid[] DEFAULT NULL::uuid[], p_product text DEFAULT NULL::text, p_from date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_place text; v_who text; v_made int := 0; v_skip int := 0;
        v_branches int; c uuid; v_ids uuid[];
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Operations and the administrator assign coverage.');
  end if;

  select name into v_place from op_node where id = p_node;
  select full_name into v_who from person
   where id = p_person and employment_status = 'ACTIVE' and superseded_by is null;
  if v_place is null then return jsonb_build_object('error','no_such_place'); end if;
  if v_who is null then return jsonb_build_object('error','no_such_person'); end if;

  -- the clients actually present at that place, narrowed to the list if given
  select coalesce(array_agg(distinct b.client_id), '{}')
    into v_ids
    from branch b join client c2 on c2.id = b.client_id
   where b.op_node_id = p_node and b.status = 'ACTIVE' and c2.status = 'ACTIVE'
     and (p_clients is null or b.client_id = any(p_clients));

  if array_length(v_ids, 1) is null then
    return jsonb_build_object('error','nothing_there',
      'reason','No active client has an active branch at ' || v_place || ', so there '
               'is nothing to assign. Add the client to this place first.');
  end if;

  foreach c in array v_ids loop
    if exists (select 1 from coverage_rule r
                where r.scope_type = 'LOCATION' and r.op_node_id = p_node
                  and r.person_id = p_person and r.client_id = c
                  and r.effective_to is null) then
      v_skip := v_skip + 1;
    else
      insert into coverage_rule (person_id, role, scope_type, op_node_id, client_id,
                                 product, effective_from, is_assigned_handler, source_ref)
      values (p_person, 'HANDLER', 'LOCATION', p_node, c,
              nullif(btrim(coalesce(p_product,'')), ''),
              coalesce(p_from, current_date), true, 'Places screen, whole place');
      v_made := v_made + 1;
    end if;
  end loop;

  select count(*) into v_branches from branch b
   where b.op_node_id = p_node and b.status = 'ACTIVE' and b.client_id = any(v_ids);

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'COVERAGE_ASSIGNED_WHOLE_PLACE', 'op_node', v_place,
          jsonb_build_object('person', v_who, 'clients', v_made,
                             'already_had', v_skip, 'branches', v_branches));

  return jsonb_build_object('ok', true, 'clients', v_made, 'alreadyHad', v_skip,
    'branches', v_branches,
    'note', v_who || ' now covers ' || v_made || ' client(s) at ' || v_place ||
            ', which is ' || v_branches || ' branches' ||
            case when v_skip > 0 then '. ' || v_skip || ' they already covered were left alone.'
                 else '.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.op_chair_seat(p_actor uuid, p_person uuid, p_chair uuid, p_place text DEFAULT NULL::text, p_primary boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_who text; v_chair text; v_seat uuid; v_id uuid;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Seating a chair is an administrator''s to do.');
  end if;

  select full_name into v_who from person
   where id = p_person and employment_status = 'ACTIVE' and superseded_by is null;
  select title into v_chair from chair where id = p_chair;
  if v_who is null then return jsonb_build_object('error','no_such_person'); end if;
  if v_chair is null then return jsonb_build_object('error','no_such_chair'); end if;

  if coalesce(btrim(p_place),'') <> '' then
    select id into v_seat from chair_seating
     where chair_id = p_chair and lower(btrim(scope_label)) = lower(btrim(p_place));
    if v_seat is null then
      insert into chair_seating (chair_id, scope_label, source_ref)
      values (p_chair, btrim(p_place), 'Places screen') returning id into v_seat;
    end if;
  end if;

  if exists (select 1 from chair_holder
              where person_id = p_person and chair_id = p_chair and to_date is null
                and seating_id is not distinct from v_seat) then
    return jsonb_build_object('ok', true,
      'note', v_who || ' already holds ' || v_chair ||
              case when v_seat is null then '.' else ' at ' || btrim(p_place) || '.' end);
  end if;

  if p_primary then
    update chair_holder set is_primary = false
     where person_id = p_person and to_date is null and is_primary;
  end if;

  insert into chair_holder (chair_id, person_id, is_primary, from_date, seating_id)
  values (p_chair, p_person, coalesce(p_primary, false), current_date, v_seat)
  returning id into v_id;

  insert into audit_entry (actor_id, action, entity_type, entity_id, entity_ref, new_value)
  values (p_actor, 'CHAIR_SEATED', 'chair_holder', v_id, v_chair,
          jsonb_build_object('person', v_who, 'place', nullif(btrim(coalesce(p_place,'')),''),
                             'primary', coalesce(p_primary, false)));

  return jsonb_build_object('ok', true,
    'note', v_who || ' now holds ' || v_chair ||
            case when v_seat is null then '' else ' at ' || btrim(p_place) end ||
            '. That is the job; who runs the place day to day is set separately.');
end $function$
;

CREATE OR REPLACE FUNCTION public.op_chair_unseat(p_actor uuid, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_n int;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then return jsonb_build_object('error','not_admin'); end if;

  update chair_holder set to_date = current_date where id = p_id and to_date is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    return jsonb_build_object('error','already_ended',
      'reason','That seating has already ended, or it does not exist.');
  end if;
  insert into audit_entry (actor_id, action, entity_type, entity_id, new_value)
  values (p_actor, 'CHAIR_UNSEATED', 'chair_holder', p_id,
          jsonb_build_object('to', current_date));
  return jsonb_build_object('ok', true, 'note','Ended today. The seating stays on file.');
end $function$
;

CREATE OR REPLACE FUNCTION public.op_city_align(p_actor uuid, p_geo uuid, p_node uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_city text; v_lvl text; v_old text; v_new text;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Aligning a city to an operating zone is an administrator''s to change.');
  end if;

  select name, level, op_zone into v_city, v_lvl, v_old from geo_node where id = p_geo;
  if v_city is null then return jsonb_build_object('error','no_such_city'); end if;
  if v_lvl not in ('CITY','STATE') then
    return jsonb_build_object('error','not_a_city',
      'reason','Only a city or a state answers to an operating zone.');
  end if;

  if p_node is not null then
    select name into v_new from op_node where id = p_node and level in ('ZONE','LOCATION');
    if v_new is null then
      return jsonb_build_object('error','no_such_place',
        'reason','A city answers to an operating zone or one of its locations.');
    end if;
  end if;

  update geo_node set op_zone = v_new where id = p_geo;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, 'CITY_ALIGNED', 'geo_node', p_geo::text,
          jsonb_build_object('opZone', v_old), jsonb_build_object('opZone', v_new));

  return jsonb_build_object('ok', true, 'city', v_city,
    'opZone', v_new,
    'note', case when v_new is null then v_city || ' now answers to no operating zone.'
                 else v_city || ' now answers to ' || v_new || '.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.op_client_place(p_actor uuid, p_client uuid, p_node uuid, p_attach boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_place text; v_client text; v_n int; v_left int;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Where a client''s branches sit is an administrator''s to change.');
  end if;

  select name into v_place from op_node where id = p_node;
  select name into v_client from client where id = p_client;
  if v_place is null then return jsonb_build_object('error','no_such_place'); end if;
  if v_client is null then return jsonb_build_object('error','no_such_client'); end if;

  if p_attach then
    update branch set op_node_id = p_node, updated_at = now()
     where client_id = p_client and op_node_id is null and status = 'ACTIVE';
    get diagnostics v_n = row_count;
    select count(*) into v_left from branch
     where client_id = p_client and op_node_id is null and status = 'ACTIVE';
  else
    update branch set op_node_id = null, updated_at = now()
     where client_id = p_client and op_node_id = p_node;
    get diagnostics v_n = row_count;
    select count(*) into v_left from branch
     where client_id = p_client and op_node_id is null and status = 'ACTIVE';
  end if;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor,
          case when p_attach then 'CLIENT_PLACED' else 'CLIENT_UNPLACED' end,
          'op_node', v_place,
          jsonb_build_object('client', v_client, 'branches', v_n, 'unplaced_after', v_left));

  return jsonb_build_object('ok', true, 'branches', v_n, 'unplaced', v_left,
    'note', case
      when p_attach and v_n = 0 then
        v_client || ' has no branch waiting to be placed, so nothing moved. Every '
        || 'branch it has already sits somewhere.'
      when p_attach then
        v_n || ' branch(es) of ' || v_client || ' now sit at ' || v_place || '.'
      when v_n = 0 then
        v_client || ' has no branch at ' || v_place || '.'
      else
        v_n || ' branch(es) of ' || v_client || ' were taken off ' || v_place ||
        '. They are not deleted -- they are waiting to be placed, and the screen counts them.'
    end);
end $function$
;

CREATE OR REPLACE FUNCTION public.op_location_for(p_name text)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select op_place(p_name, true);
$function$
;

CREATE OR REPLACE FUNCTION public.op_options()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'people', coalesce((select jsonb_agg(jsonb_build_object(
                  'id', p.id, 'name', p.full_name, 'employeeNo', p.employee_no,
                  'chair', ch.title) order by p.full_name)
        from person p
        left join chair_holder h on h.person_id = p.id and h.to_date is null and h.is_primary
        left join chair ch on ch.id = h.chair_id
       where p.employment_status = 'ACTIVE' and p.superseded_by is null), '[]'::jsonb),
    'chairs', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'title', c.title)
                        order by c.title) from chair c), '[]'::jsonb),
    'clients', coalesce((select jsonb_agg(jsonb_build_object(
                  'id', c.id, 'code', c.code, 'name', c.name,
                  'unplaced', (select count(*) from branch br
                                where br.client_id = c.id and br.op_node_id is null
                                  and br.status = 'ACTIVE'))
                order by c.name)
        from client c where c.status = 'ACTIVE'), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(distinct product) from coverage_rule
                           where product is not null and btrim(product) <> ''), '[]'::jsonb)
  );
$function$
;

CREATE OR REPLACE FUNCTION public.op_place(p_name text, p_locations_only boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare s text; head text; tail text; hit uuid;
begin
  s := btrim(coalesce(p_name, ''));
  if s = '' then return null; end if;

  if position('/' in s) > 0 then
    head := btrim(split_part(s, '/', 1));
    tail := btrim(split_part(s, '/', 2));
  else
    head := s; tail := null;
  end if;

  -- the right half names a location inside the left one, and that stays true
  -- when the two are spelt the same: "Pune / Pune" is the Pune location
  if tail is not null then
    hit := op_resolve_one(tail, 'LOCATION');
    if hit is not null then return hit; end if;
  end if;

  -- a name written alone, or the left half, names the zone
  if not p_locations_only then
    hit := op_resolve_one(head, 'ZONE');
    if hit is not null then return hit; end if;
  end if;

  -- and a name that is neither still finds whatever matches it
  hit := op_resolve_one(head, case when p_locations_only then 'LOCATION' else 'ANY' end);
  if hit is not null then return hit; end if;
  if tail is not null then
    hit := op_resolve_one(tail, case when p_locations_only then 'LOCATION' else 'ANY' end);
  end if;
  return hit;
end $function$
;

CREATE OR REPLACE FUNCTION public.op_place(p_node uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with me as (select id, name, level, parent_id, active from op_node where id = p_node),
b as (
  select br.id, br.client_id
    from branch br join client c on c.id = br.client_id
   where br.op_node_id = p_node and br.status = 'ACTIVE' and c.status = 'ACTIVE'
),
rules as (
  select r.id, r.person_id, r.role, r.client_id, r.product, r.effective_from
    from coverage_rule r
   where r.op_node_id = p_node and r.scope_type = 'LOCATION' and r.effective_to is null
),
rates as (
  select distinct on (r.client_id) r.client_id, r.id, r.code, r.value, r.currency,
         r.effective_from, r.effective_to, r.reason
    from rate r join rate_location rl on rl.rate_id = r.id
   where rl.op_node_id = p_node and r.status = 'active'
   order by r.client_id, r.effective_from desc
)
select jsonb_build_object(
  'id', (select id from me), 'name', (select name from me),
  'level', (select level from me), 'active', (select active from me),
  'under', (select o.name from op_node o where o.id = (select parent_id from me)),
  'branches', (select count(*) from b),

  'clients', coalesce((
    select jsonb_agg(jsonb_build_object(
      'clientId', c.id, 'code', c.code, 'name', c.name,
      'branches', (select count(*) from b where b.client_id = c.id),
      'handlers', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'ruleId', ru.id, 'personId', ru.person_id, 'name', p.full_name,
                 'employeeNo', p.employee_no, 'role', ru.role,
                 'product', ru.product, 'from', ru.effective_from)
               order by p.full_name)
          from rules ru join person p on p.id = ru.person_id
         where ru.client_id = c.id), '[]'::jsonb),
      'rate', (select jsonb_build_object('id', rt.id, 'code', rt.code, 'value', rt.value,
                        'currency', rt.currency, 'from', rt.effective_from,
                        'to', rt.effective_to, 'reason', rt.reason)
                 from rates rt where rt.client_id = c.id))
    order by c.name)
    from client c where c.id in (select distinct client_id from b)), '[]'::jsonb),

  -- who runs the place itself, rather than one client at it
  'managers', coalesce((
    select jsonb_agg(jsonb_build_object(
             'ruleId', ru.id, 'personId', ru.person_id, 'name', p.full_name,
             'employeeNo', p.employee_no, 'role', ru.role, 'from', ru.effective_from,
             'client', (select c2.name from client c2 where c2.id = ru.client_id))
           order by ru.role, p.full_name)
      from rules ru join person p on p.id = ru.person_id
     where ru.role <> 'HANDLER'), '[]'::jsonb),

  -- the job, which is a different thing: who is seated here by chair
  'seated', coalesce((
    select jsonb_agg(jsonb_build_object(
             'holderId', h.id, 'personId', p.id, 'name', p.full_name,
             'employeeNo', p.employee_no, 'chair', ch.title,
             'primary', h.is_primary, 'from', h.from_date)
           order by ch.title, p.full_name)
      from chair_holder h
      join chair_seating s on s.id = h.seating_id
      join chair ch on ch.id = h.chair_id
      join person p on p.id = h.person_id
     where h.to_date is null
       and lower(btrim(s.scope_label)) = lower(btrim((select name from me)))
       and p.employment_status = 'ACTIVE' and p.superseded_by is null), '[]'::jsonb),

  'clientsNotHere', coalesce((
    select jsonb_agg(jsonb_build_object('id', c.id, 'code', c.code, 'name', c.name,
             'unplaced', (select count(*) from branch br
                           where br.client_id = c.id and br.op_node_id is null
                             and br.status = 'ACTIVE'))
           order by c.name)
      from client c
     where c.status = 'ACTIVE' and c.id not in (select distinct client_id from b)), '[]'::jsonb)
);
$function$
;

CREATE OR REPLACE FUNCTION public.op_places()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with b as (
  select br.id, br.op_node_id, br.client_id
    from branch br join client c on c.id = br.client_id
   where br.status = 'ACTIVE' and c.status = 'ACTIVE' and br.op_node_id is not null
), citymap as (
  select g.id, g.name, g.level, g.op_zone, g.parent_id,
         op_zone_id(g.op_zone) as node_id,
         (select count(*) from branch br where br.geo_node_id = g.id) as branches
    from geo_node g where g.level in ('CITY','STATE')
), locs as (
  select l.id, l.name, l.active, l.parent_id,
         (select count(*) from b where b.op_node_id = l.id) as branches,
         (select count(distinct b.client_id) from b where b.op_node_id = l.id) as clients,
         (select count(*) from (
            select b.client_id from b where b.op_node_id = l.id group by b.client_id
            except
            select r.client_id from coverage_rule r
             where r.op_node_id = l.id and r.scope_type = 'LOCATION'
               and r.effective_to is null and r.client_id is not null
          ) q) as unassigned,
         (select count(*) from coverage_rule r
           where r.op_node_id = l.id and r.scope_type = 'LOCATION'
             and r.effective_to is null and r.role <> 'HANDLER') as managers,
         coalesce((select jsonb_agg(cm.name order by cm.name)
             from citymap cm where cm.node_id = l.id), '[]'::jsonb) as cities
    from op_node l where l.level = 'LOCATION'
), zones as (
  select z.id, z.name, z.active, z.parent_id,
         coalesce((select jsonb_agg(jsonb_build_object(
                    'id', lo.id, 'name', lo.name, 'active', lo.active,
                    'branches', lo.branches, 'clients', lo.clients,
                    'unassigned', lo.unassigned, 'managers', lo.managers,
                    'cities', lo.cities) order by lo.name)
             from locs lo where lo.parent_id = z.id), '[]'::jsonb) as locations,
         coalesce((select sum(lo.branches) from locs lo where lo.parent_id = z.id), 0) as branches,
         (select count(*) from coverage_rule r
           where r.op_node_id = z.id and r.scope_type = 'LOCATION'
             and r.effective_to is null and r.role <> 'HANDLER') as managers,
         coalesce((select jsonb_agg(cm.name order by cm.name)
             from citymap cm where cm.node_id = z.id), '[]'::jsonb) as cities
    from op_node z where z.level = 'ZONE'
)
select jsonb_build_object(
  'groups', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', g.id, 'name', g.name, 'active', g.active,
             'zones', coalesce((select jsonb_agg(jsonb_build_object(
                          'id', z.id, 'name', z.name, 'active', z.active,
                          'branches', z.branches, 'managers', z.managers,
                          'cities', z.cities, 'locations', z.locations)
                        order by z.name)
                   from zones z where z.parent_id = g.id), '[]'::jsonb))
           order by g.sort, g.name)
      from op_node g where g.level = 'GROUP'), '[]'::jsonb),
  'cities', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', cm.id, 'name', cm.name, 'level', cm.level, 'under', pg.name,
             'opZone', cm.op_zone,
             'resolves', (select o.name from op_node o where o.id = cm.node_id),
             'branches', cm.branches)
           order by (cm.node_id is not null), cm.level desc, cm.name)
      from citymap cm left join geo_node pg on pg.id = cm.parent_id), '[]'::jsonb),
  'aliases', coalesce((
    select jsonb_agg(jsonb_build_object(
             'writtenAs', a.written_as, 'means', a.means, 'note', a.note,
             'resolves', (select o.name from op_node o where o.id = op_zone_id(a.means)))
           order by a.written_as)
      from op_node_alias a), '[]'::jsonb),
  'places', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name,
                        'level', o.level) order by o.level, o.name)
      from op_node o where o.active), '[]'::jsonb),
  'roles', jsonb_build_array(
      jsonb_build_object('key','ZONAL_MANAGER','label','Zonal Manager'),
      jsonb_build_object('key','BRANCH_MANAGER','label','Branch Manager'),
      jsonb_build_object('key','LOCATION_HEAD','label','Location head'),
      jsonb_build_object('key','HANDLER','label','Handler')),
  'unplacedBranches', (select count(*) from branch br join client c on c.id = br.client_id
                        where br.op_node_id is null and br.status = 'ACTIVE' and c.status = 'ACTIVE'),
  'unalignedCities',  (select count(*) from citymap where node_id is null)
);
$function$
;

CREATE OR REPLACE FUNCTION public.op_rate_set(p_actor uuid, p_client uuid, p_value numeric, p_from text, p_node uuid DEFAULT NULL::uuid, p_to text DEFAULT NULL::text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_dept text; v_client text; v_place text;
        d_from date; d_to date; v_prev record; v_id uuid; v_seq int; v_code text;
begin
  select app_role, department into v_role, v_dept from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' and coalesce(v_dept,'') <> 'Finance & Accounts' then
    return jsonb_build_object('error','not_permitted',
      'reason','Finance and the administrator own the rate master.');
  end if;

  select name into v_client from client where id = p_client;
  if v_client is null then return jsonb_build_object('error','no_such_client'); end if;
  if p_node is not null then
    select name into v_place from op_node where id = p_node;
    if v_place is null then return jsonb_build_object('error','no_such_place'); end if;
  end if;

  if p_value is null or p_value < 0 then
    return jsonb_build_object('error','bad_value',
      'reason','A rate is an amount that is not negative.');
  end if;

  d_from := ul_date(p_from);
  d_to   := ul_date(p_to);
  if d_from is null then
    return jsonb_build_object('error','bad_date',
      'reason','The date it takes effect is not one the tool can read. '
               'YYYY-MM-DD, DD-MM-YYYY and DD-MM-YY all work.');
  end if;
  if p_to is not null and btrim(p_to) <> '' and d_to is null then
    return jsonb_build_object('error','bad_date',
      'reason','The date it runs to is not one the tool can read, or leave it blank.');
  end if;
  if d_to is not null and d_to <= d_from then
    return jsonb_build_object('error','bad_period',
      'reason','The date it runs to must be after the date it takes effect.');
  end if;

  -- a live rate for the same client and place over an overlapping period
  select r.id, r.code, r.value, r.effective_from, r.effective_to into v_prev
    from rate r
    left join rate_location rl on rl.rate_id = r.id
   where r.client_id = p_client
     and rl.op_node_id is not distinct from p_node
     and r.status = 'active'
     and daterange(r.effective_from, r.effective_to, '[)')
      && daterange(d_from, d_to, '[)')
   order by r.effective_from desc limit 1;

  if v_prev.id is not null then
    if v_prev.effective_from >= d_from then
      return jsonb_build_object('error','clashes',
        'reason', v_client || ' already has a rate for ' || coalesce(v_place, 'every branch')
                  || ' from ' || v_prev.effective_from || ', which starts on or after this one. '
                  || 'End that one first, or start this one later.');
    end if;
    update rate set effective_to = d_from - 1, updated_by = p_actor, updated_at = now()
     where id = v_prev.id;
  end if;

  select coalesce(count(*), 0) into v_seq from rate;
  v_code := 'RATE-' || lpad((v_seq + 1)::text, 6, '0');

  insert into rate (code, client_id, scope, value, currency, effective_from,
                    effective_to, status, reason, created_by)
  values (v_code, p_client,
          (case when p_node is null then 'client' else 'exact' end)::rate_scope,
          p_value, 'INR', d_from, d_to, 'active',
          nullif(btrim(coalesce(p_reason,'')), ''), p_actor)
  returning id into v_id;

  if p_node is not null then
    insert into rate_location (rate_id, op_node_id) values (v_id, p_node)
    on conflict do nothing;
  end if;

  insert into audit_entry (actor_id, action, entity_type, entity_id, entity_ref, old_value, new_value)
  values (p_actor, 'RATE_SET', 'rate', v_id, v_code,
          case when v_prev.id is null then null
               else jsonb_build_object('code', v_prev.code, 'value', v_prev.value) end,
          jsonb_build_object('client', v_client, 'place', v_place, 'value', p_value,
                             'from', d_from, 'to', d_to));

  return jsonb_build_object('ok', true, 'id', v_id, 'code', v_code,
    'from', d_from, 'to', d_to,
    'note', v_client || ' at ' || coalesce(v_place, 'every branch') || ' is ' || p_value
            || ' from ' || to_char(d_from, 'DD Mon YYYY')
            || case when d_to is null then ' onwards' else ' to ' || to_char(d_to, 'DD Mon YYYY') end
            || case when v_prev.id is not null
                    then '. The previous rate was end-dated, not overwritten -- a closed '
                         || 'month still reads the rate that was valid then.'
                    else '.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.op_resolve_one(p_name text, p_want text)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  s text; re text; hit uuid; n int; v_means text; pass int;
begin
  s := btrim(coalesce(p_name, ''));
  if s = '' then return null; end if;

  -- pass 1 is the name as written; pass 2 is what it has been taught to mean
  for pass in 1..2 loop
    if pass = 2 then
      select a.means into v_means
        from op_node_alias a where a.written_as = lower(btrim(p_name));
      if v_means is null then return null; end if;
      s := v_means;
    end if;

    re := case when length(s) >= 4
               then '(^|[^[:alnum:]])'
                    || regexp_replace(s, '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g')
                    || '([^[:alnum:]]|$)'
               else null end;

    with cand as (
      select o.id, o.name, o.active, o.level,
             (lower(btrim(o.name)) = lower(s)) as is_exact,
             (select count(*) from branch b where b.op_node_id = o.id) as branches
        from op_node o
       where (p_want = 'ANY'
              or (p_want = 'LOCATION' and o.level = 'LOCATION' and o.active)
              or (p_want = 'ZONE'     and o.level = 'ZONE'     and o.active))
         and (lower(btrim(o.name)) = lower(s) or (re is not null and o.name ~* re))
    ), live as (
      select * from cand where active or branches > 0
    ), ranked as (
      select live.*,
             row_number() over (order by is_exact desc, active desc, branches desc,
                                         length(name), name) as rn,
             dense_rank() over (order by is_exact desc, active desc, branches desc) as tier
        from live
    )
    select rk.id,
           (select count(distinct lower(btrim(r2.name))) from ranked r2 where r2.tier = 1)
      into hit, n
      from ranked rk where rk.rn = 1;

    if hit is not null and n = 1 then return hit; end if;
  end loop;

  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.op_retire(p_actor uuid, p_id uuid, p_active boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; n int; v_name text; v_kids int;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin');
  end if;

  select name into v_name from op_node where id = p_id;
  if v_name is null then return jsonb_build_object('error','no_such_node'); end if;

  select count(*) into n from coverage_rule where op_node_id = p_id;
  select count(*) into v_kids from op_node where parent_id = p_id and active;

  update op_node set active = p_active, updated_at = now() where id = p_id;
  -- switching off a zone switches off what sits under it, or the locations
  -- would go on being offered by a zone that is no longer in use
  if not p_active then
    update op_node set active = false, updated_at = now() where parent_id = p_id;
  end if;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, case when p_active then 'OP_NODE_RESTORED' else 'OP_NODE_RETIRED' end,
          'op_node', p_id::text,
          jsonb_build_object('name', v_name, 'coverage', n, 'children', v_kids));

  return jsonb_build_object('ok', true, 'name', v_name, 'active', p_active,
    'note', case when p_active then null
                 when n > 0 then n || ' coverage rule(s) still name it. They are '
                      'untouched - it simply stops being offered for new ones.'
                 when v_kids > 0 then v_kids || ' thing(s) under it were switched off too.'
            end);
end $function$
;

CREATE OR REPLACE FUNCTION public.op_role_end(p_actor uuid, p_id uuid, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_n int;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin');
  end if;

  update coverage_rule set effective_to = coalesce(p_to, current_date)
   where id = p_id and effective_to is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    return jsonb_build_object('error','already_ended',
      'reason','That role has already been ended, or it does not exist.');
  end if;

  insert into audit_entry (actor_id, action, entity_type, entity_id, new_value)
  values (p_actor, 'PLACE_ROLE_ENDED', 'coverage_rule', p_id,
          jsonb_build_object('to', coalesce(p_to, current_date)));
  return jsonb_build_object('ok', true,
    'note','Ended today. The rule stays on file with its dates.');
end $function$
;

CREATE OR REPLACE FUNCTION public.op_role_set(p_actor uuid, p_node uuid, p_person uuid, p_role text, p_client uuid DEFAULT NULL::uuid, p_from date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_place text; v_who text; v_n int; v_id uuid;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Who runs a place is an administrator''s to set.');
  end if;
  if upper(coalesce(btrim(p_role),'')) not in
     ('ZONAL_MANAGER','BRANCH_MANAGER','LOCATION_HEAD','HANDLER') then
    return jsonb_build_object('error','bad_role',
      'reason','A place-role is Zonal Manager, Branch Manager, Location head or Handler.');
  end if;

  select name into v_place from op_node where id = p_node;
  select full_name into v_who from person
   where id = p_person and employment_status = 'ACTIVE' and superseded_by is null;
  if v_place is null then return jsonb_build_object('error','no_such_place'); end if;
  if v_who is null then
    return jsonb_build_object('error','no_such_person',
      'reason','That person is not on the active people master.');
  end if;

  update coverage_rule
     set effective_to = coalesce(p_from, current_date) - 1
   where scope_type = 'LOCATION' and op_node_id = p_node
     and role = upper(btrim(p_role))
     and client_id is not distinct from p_client
     and effective_to is null;
  get diagnostics v_n = row_count;

  insert into coverage_rule (person_id, role, scope_type, op_node_id, client_id,
                             effective_from, is_assigned_handler, source_ref)
  values (p_person, upper(btrim(p_role)), 'LOCATION', p_node, p_client,
          coalesce(p_from, current_date),
          upper(btrim(p_role)) = 'HANDLER', 'Places screen')
  returning id into v_id;

  insert into audit_entry (actor_id, action, entity_type, entity_id, entity_ref, new_value)
  values (p_actor, 'PLACE_ROLE_SET', 'coverage_rule', v_id, v_place,
          jsonb_build_object('role', upper(btrim(p_role)), 'person', v_who,
                             'client', p_client, 'replaced', v_n));

  return jsonb_build_object('ok', true, 'id', v_id,
    'note', v_who || ' now runs ' || v_place || ' as ' ||
            lower(replace(upper(btrim(p_role)), '_', ' ')) ||
            case when v_n > 0 then '. The previous holder was end-dated, not removed.'
                 else '.' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.op_save(p_actor uuid, p_name text, p_id uuid DEFAULT NULL::uuid, p_parent uuid DEFAULT NULL::uuid, p_active boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_level text; v_parent_level text; v_id uuid;
        v_old text; v_old_parent uuid; v_old_parent_name text; v_new_parent_name text;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','The operating grouping is an administrator''s to change.');
  end if;
  if coalesce(btrim(p_name),'') = '' then
    return jsonb_build_object('error','no_name','reason','Give it a name.');
  end if;

  if p_id is not null then
    select name, level, parent_id into v_old, v_level, v_old_parent
      from op_node where id = p_id;
    if v_old is null then return jsonb_build_object('error','no_such_node'); end if;

    if p_parent is not null and p_parent is distinct from v_old_parent then
      if p_parent = p_id then
        return jsonb_build_object('error','self_parent',
          'reason','A place cannot sit inside itself.');
      end if;
      select level, name into v_parent_level, v_new_parent_name
        from op_node where id = p_parent;
      if v_parent_level is null then
        return jsonb_build_object('error','no_such_parent');
      end if;
      if not ((v_level = 'LOCATION' and v_parent_level = 'ZONE')
           or (v_level = 'ZONE'     and v_parent_level = 'GROUP')) then
        return jsonb_build_object('error','wrong_level',
          'reason', 'A ' || lower(v_level) || ' cannot sit under a '
                    || lower(v_parent_level) || '. The grouping is three deep: '
                    || 'a group, its zones, their locations.');
      end if;
      select name into v_old_parent_name from op_node where id = v_old_parent;
    end if;

    update op_node
       set name = btrim(p_name),
           parent_id = case when v_level = 'GROUP' then parent_id
                            else coalesce(p_parent, parent_id) end,
           active = coalesce(p_active, active),
           updated_at = now()
     where id = p_id
    returning id into v_id;
  else
    if p_parent is null then
      v_level := 'GROUP';
    else
      select level into v_parent_level from op_node where id = p_parent;
      if v_parent_level is null then
        return jsonb_build_object('error','no_such_parent');
      end if;
      v_level := case v_parent_level when 'GROUP' then 'ZONE'
                                     when 'ZONE' then 'LOCATION' end;
      if v_level is null then
        return jsonb_build_object('error','too_deep',
          'reason','The grouping is three deep: a group, its zones, their locations. '
                   'A location has nothing under it.');
      end if;
    end if;

    insert into op_node (parent_id, level, name, source_ref)
    values (p_parent, v_level, btrim(p_name), 'added by an administrator')
    returning id into v_id;
  end if;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor,
          case when p_id is null then 'OP_NODE_ADDED'
               when v_new_parent_name is not null then 'OP_NODE_MOVED'
               else 'OP_NODE_CHANGED' end,
          'op_node', v_id::text,
          case when v_old is null then null
               else jsonb_build_object('name', v_old, 'under', v_old_parent_name) end,
          jsonb_build_object('name', btrim(p_name), 'active', p_active,
                             'under', v_new_parent_name));

  return jsonb_build_object('ok', true, 'id', v_id,
    'moved', v_new_parent_name,
    'note', case when v_new_parent_name is not null
                 then btrim(p_name) || ' now sits under ' || v_new_parent_name
                      || '. Its branches move with it.' end);
exception when unique_violation then
  return jsonb_build_object('error','already_there',
    'reason','There is already something called that in the same place. Two '
             'locations with one name under one zone is the duplication this '
             'grouping exists to remove.');
end $function$
;

CREATE OR REPLACE FUNCTION public.op_tree()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(g order by g->>'sort', g->>'name'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', grp.id, 'name', grp.name, 'sort', grp.sort, 'active', grp.active,
      'zones', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', z.id, 'name', z.name, 'active', z.active,
          'locations', coalesce((
            select jsonb_agg(jsonb_build_object(
              'id', l.id, 'name', l.name, 'active', l.active,
              'inUse', exists (select 1 from coverage_rule c where c.op_node_id = l.id))
              order by l.name)
            from op_node l where l.parent_id = z.id and l.level='LOCATION'), '[]'::jsonb))
          order by z.name)
        from op_node z where z.parent_id = grp.id and z.level='ZONE'), '[]'::jsonb)) as g
    from op_node grp where grp.level='GROUP') q
$function$
;

CREATE OR REPLACE FUNCTION public.op_zone_error(p_name text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select 'zone ' || p_name || ' is not one of your operating zones or locations. '
         'They are listed under Configuration, Locations'
         || coalesce(' - for example ' || (
              select string_agg(name, ', ')
                from (select name from op_node
                       where active and level = 'LOCATION' order by name limit 4) s), '');
$function$
;

CREATE OR REPLACE FUNCTION public.op_zone_id(p_name text)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select op_place(p_name, false);
$function$
;

CREATE OR REPLACE FUNCTION public.ops_alert_ack(p_actor uuid, p_id uuid)
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
      'reason','Only an administrator can take an operational alert.');
  end if;
  update ops_alert set acknowledged_by = p_actor, acknowledged_at = now()
   where id = p_id and resolved_at is null;
  return jsonb_build_object('ok', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.ops_alert_open(p_role text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'kind', a.kind, 'severity', a.severity,
           'title', a.title, 'detail', a.detail, 'action', a.action_hint,
           'since', a.opened_at, 'seen', a.last_seen_at,
           'times', a.occurrences, 'retry_at', a.retry_at,
           'acknowledged', a.acknowledged_at is not null)
         order by case a.severity when 'URGENT' then 0 when 'WARN' then 1 else 2 end,
                  a.opened_at), '[]'::jsonb)
  from ops_alert a
  where a.resolved_at is null
    and (p_role is null or a.for_role = p_role)
$function$
;

CREATE OR REPLACE FUNCTION public.ops_alert_raise(p_kind text, p_title text, p_dedupe_key text, p_severity text DEFAULT 'WARN'::text, p_detail text DEFAULT NULL::text, p_action_hint text DEFAULT NULL::text, p_retry_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_entity_type text DEFAULT NULL::text, p_entity_id uuid DEFAULT NULL::uuid, p_for_role text DEFAULT 'ADMIN'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;
begin
  insert into ops_alert (kind, severity, title, detail, action_hint, for_role,
                         entity_type, entity_id, dedupe_key, retry_at)
  values (p_kind, p_severity, p_title, p_detail, p_action_hint, p_for_role,
          p_entity_type, p_entity_id, p_dedupe_key, p_retry_at)
  on conflict (dedupe_key) where resolved_at is null
  do update set last_seen_at = now(),
                occurrences  = ops_alert.occurrences + 1,
                detail       = coalesce(excluded.detail, ops_alert.detail),
                retry_at     = coalesce(excluded.retry_at, ops_alert.retry_at),
                severity     = excluded.severity
  returning id into v_id;
  return v_id;
end $function$
;

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

CREATE OR REPLACE FUNCTION public.org_add_options(p_actor uuid, p_under uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_actor person; v_under person; v_chair uuid; v_wide boolean;
begin
  select * into v_actor from person where id = p_actor;
  if v_actor.id is null then
    return jsonb_build_object('error','not_permitted','reason','Who is asking?');
  end if;
  select * into v_under from person where id = p_under;
  if v_under.id is null then
    return jsonb_build_object('error','no_such_person');
  end if;
  if not org_may_add_under(p_actor, p_under) then
    return jsonb_build_object('error','not_permitted',
      'reason', v_under.full_name || ' is not somebody you manage.');
  end if;

  select h.chair_id into v_chair from chair_holder h
   where h.person_id = p_under and h.to_date is null
   order by h.is_primary desc limit 1;

  v_wide := v_actor.app_role = 'ADMIN'
            or coalesce(v_actor.department,'') = 'Human Resources';

  return jsonb_build_object(
    'underId', p_under,
    'underName', v_under.full_name,
    'mayCreate', v_wide,
    'mayRequest', true,

    'movable', coalesce((
      select jsonb_agg(jsonb_build_object(
               'personId', q.id, 'name', q.full_name,
               'employeeNo', q.employee_no,
               'managerName', (select m.full_name from person m where m.id = q.manager_id),
               'chair', (select ch.title from chair_holder h
                          join chair ch on ch.id = h.chair_id
                         where h.person_id = q.id and h.to_date is null
                         order by h.is_primary desc limit 1))
             order by q.full_name)
      from person q
     where q.employment_status = 'ACTIVE' and q.superseded_by is null
       and coalesce(q.employee_type,'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
       and q.id <> p_under
       and coalesce(q.manager_id, '00000000-0000-0000-0000-000000000000'::uuid) <> p_under
       and q.id <> p_actor
       and (v_wide or q.id is distinct from v_actor.manager_id)
       and (v_wide
            or (exists (select 1 from org_subtree(p_actor) t
                         where t.person_id = q.id and t.depth > 0)
                and exists (select 1 from org_subtree(p_actor) t
                             where t.person_id = p_under)))
       and p_under not in (select person_id from org_subtree(q.id))
    ), '[]'::jsonb),

    'chairs', coalesce((
      select jsonb_agg(jsonb_build_object('chairId', c.id, 'title', c.title,
                                          'code', c.code, 'level', c.level)
             order by c.title)
      from chair c
     where c.parent_id = v_chair
    ), (select coalesce(jsonb_agg(jsonb_build_object(
                 'chairId', c.id, 'title', c.title, 'code', c.code,
                 'level', c.level) order by c.title), '[]'::jsonb)
          from chair c where c.parent_id is not null)),

    'pending', coalesce((
      select jsonb_agg(jsonb_build_object(
               'requestId', r.id, 'name', r.full_name, 'email', r.work_email,
               'state', r.state, 'requestedAt', r.requested_at,
               'requestedBy', (select q.full_name from person q where q.id = r.requested_by))
             order by r.requested_at desc)
      from person_request r
     where r.manager_id = p_under and r.state in ('DRAFT','AWAITING_HR','AWAITING_ADMIN')
    ), '[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.org_assign_options(p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a person;
begin
  select * into a from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null then
    return jsonb_build_object('error','not_permitted','reason','Who is asking?');
  end if;

  -- The same words org_people_table and org_move_person use. If this ever
  -- diverges the screen will draw a dropdown nobody is allowed to use.
  if not (a.app_role = 'ADMIN' or coalesce(a.department,'') = 'Human Resources') then
    return jsonb_build_object('mayUse', false,
      'reason','Assigning people is the administrator''s and Human Resources''.');
  end if;

  return jsonb_build_object(
    'mayUse', true,
    'maySetRole', a.app_role = 'ADMIN',
    'designations', coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'title', d.title,
                                          'seniority', d.seniority)
                       order by d.seniority, d.title)
        from designation d), '[]'::jsonb),
    -- Free text in the column, so the list is what is already in use. A
    -- department nobody is in is a department that should not be offered.
    'departments', coalesce((
      select jsonb_agg(distinct btrim(p.department))
        from person p
       where p.employment_status = 'ACTIVE' and p.superseded_by is null
         and coalesce(btrim(p.department),'') <> ''), '[]'::jsonb),
    'chairs', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'code', c.code,
                                          'title', c.title, 'level', c.level,
                                          'seats', (select count(*) from chair_seating cs
                                                     where cs.chair_id = c.id))
                       order by c.title)
        from chair c), '[]'::jsonb),
    -- A place is a seating OF a chair, which is why it is not a free list:
    -- picking Mumbai only means something once the chair is known.
    'seatings', coalesce((
      select jsonb_agg(jsonb_build_object('id', cs.id, 'chairId', cs.chair_id,
                                          'label', cs.scope_label)
                       order by cs.scope_label)
        from chair_seating cs
       where coalesce(btrim(cs.scope_label),'') <> ''), '[]'::jsonb),
    -- CLIENT_CONTACT and SERVICE_ACCOUNT are deliberately not offered: a
    -- dropdown that can put them back undoes migrations 238 and 245.
    'employeeTypes', jsonb_build_array('EMPLOYEE','PARTNER','INTERN','CONTRACT'),
    'appRoles', jsonb_build_array('VIEWER','MANAGER','ADMIN'),
    'note','Pick from these. A designation or a chair that is not on the list '
        || 'does not exist yet, and spelling one into being is how the same '
        || 'job ends up recorded three different ways.');
end
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

CREATE OR REPLACE FUNCTION public.org_may_add_under(p_actor uuid, p_under uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p_actor is not null and p_under is not null
     and (p_under = p_actor
       or perf_may_set(p_actor, p_under)
       or exists (select 1 from person a where a.id = p_actor
                   and (a.app_role = 'ADMIN'
                     or coalesce(a.department,'') = 'Human Resources')));
$function$
;

CREATE OR REPLACE FUNCTION public.org_move_person(p_actor uuid, p_person uuid, p_new_manager uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_admin boolean; v_hr boolean;
  a person; s person; m person; v_old uuid;
begin
  select * into a from person where id = p_actor
     and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null then
    return jsonb_build_object('error','not_permitted','reason','Who is asking?');
  end if;

  select * into s from person where id = p_person
     and employment_status = 'ACTIVE' and superseded_by is null;
  if s.id is null then
    return jsonb_build_object('error','no_such_person');
  end if;

  v_admin := a.app_role = 'ADMIN';
  v_hr    := coalesce(a.department,'') = 'Human Resources';
  v_old   := s.manager_id;

  -- ------------------------------------------------ rule 3, first
  -- Checked before anything else, because "may I move myself" has a
  -- flattering answer if you ask it after "is this inside my subtree".
  if p_person = p_actor then
    return jsonb_build_object('error','not_permitted',
      'reason','You cannot move yourself. Ask the person you report to.');
  end if;
  if p_person = a.manager_id and not (v_admin or v_hr) then
    return jsonb_build_object('error','not_permitted',
      'reason','You cannot move the person you report to.');
  end if;

  -- ------------------------------------------------------ rules 1 and 2
  if not (v_admin or v_hr) then
    if not exists (select 1 from org_subtree(p_actor) t
                    where t.person_id = p_person and t.depth > 0) then
      return jsonb_build_object('error','not_permitted',
        'reason','That person is not in your team.');
    end if;
    if p_new_manager is not null
       and not exists (select 1 from org_subtree(p_actor) t
                        where t.person_id = p_new_manager) then
      return jsonb_build_object('error','not_permitted',
        'reason','You can only move somebody to a manager inside your own team.');
    end if;
  end if;

  -- --------------------------------------------- a manager must exist
  if p_new_manager is null then
    if not (v_admin or v_hr) then
      return jsonb_build_object('error','not_permitted',
        'reason','Taking somebody out of the line altogether is HR''s.');
    end if;
  else
    select * into m from person where id = p_new_manager
       and employment_status = 'ACTIVE' and superseded_by is null;
    if m.id is null then
      return jsonb_build_object('error','no_such_manager');
    end if;
  end if;

  -- ---------------------------------------------------------- rule 4
  if p_new_manager = p_person then
    return jsonb_build_object('error','would_loop',
      'reason','Somebody cannot report to themselves.');
  end if;
  if p_new_manager is not null
     and exists (select 1 from org_subtree(p_person) t
                  where t.person_id = p_new_manager) then
    return jsonb_build_object('error','would_loop',
      'reason', m.full_name || ' already reports to ' || s.full_name ||
                ', directly or through somebody else. That move would make '
                'the reporting line a ring.');
  end if;

  if v_old is not distinct from p_new_manager then
    return jsonb_build_object('ok', true, 'changed', false,
      'note','They already report there. Nothing changed.');
  end if;

  update person set manager_id = p_new_manager where id = p_person;

  insert into person_event (person_id, kind, note, at)
  values (p_person, 'REPORTING_CHANGED',
          coalesce((select full_name from person where id = v_old), 'nobody')
          || ' -> ' || coalesce(m.full_name, 'nobody'), now());

  insert into audit_entry (actor_id, action, entity_type, entity_ref,
                           old_value, new_value)
  values (p_actor, 'REPORTING_CHANGED', 'person', p_person::text,
          jsonb_build_object('managerId', v_old),
          jsonb_build_object('managerId', p_new_manager));

  return jsonb_build_object('ok', true, 'changed', true,
    'personId', p_person, 'from', v_old, 'to', p_new_manager,
    'note', s.full_name || ' now reports to ' ||
            coalesce(m.full_name, 'nobody') || '. Who can see whose numbers '
            'changed with them.');
end $function$
;

CREATE OR REPLACE FUNCTION public.org_people_table(p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a person;
  v_may boolean;
  v_rows jsonb;
  v_sum jsonb;
begin
  select * into a from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null then
    return jsonb_build_object('error','not_permitted','reason','Who is asking?');
  end if;

  -- The same question org_move_person asks, in the same words (migration
  -- 242's lesson). If this ever diverges, the table will offer a move the
  -- move itself refuses.
  v_may := a.app_role = 'ADMIN' or coalesce(a.department,'') = 'Human Resources';

  if not v_may then
    return jsonb_build_object(
      'mayUse', false,
      'reason', 'This list is every person in the company, so it is the '
             || 'administrator''s and Human Resources''. Your own team is '
             || 'the chart above.');
  end if;

  with staff as (
    -- Not every row in `person` is somebody who works here: the client-bank
    -- contacts (238) and the account the tool is administered from (243).
    -- Written the same way the thirteen functions 243 swept write it.
    select p.* from person p
     where p.employment_status = 'ACTIVE' and p.superseded_by is null
       and coalesce(p.employee_type,'EMPLOYEE')
           not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
  ), seat as (
    -- The primary chair, and the seating that chair was placed in. One row
    -- per person: somebody can hold two chairs and the table has one line.
    select distinct on (h.person_id)
           h.person_id, h.chair_id, h.seating_id, ch.title as chair, cs.scope_label
      from chair_holder h
      join chair ch on ch.id = h.chair_id
      left join chair_seating cs on cs.id = h.seating_id
     where h.to_date is null
     order by h.person_id, h.is_primary desc nulls last, ch.title
  ), cov as (
    -- Where somebody is, when the chair does not say. The coverage rules
    -- carry an operating node either directly or through the branch, and
    -- its name is a place ("Mumbai", "JHARKHAND (Firoz+ Crux)"). It is a
    -- rougher answer than the chair's and it is labelled as such on screen,
    -- because a rough answer presented as an exact one is worse than a gap.
    select distinct on (cr.person_id) cr.person_id, o.name as place
      from coverage_rule cr
      join op_node o on o.id = coalesce(cr.op_node_id,
             (select b.op_node_id from branch b where b.id = cr.branch_id))
     where cr.effective_to is null
     order by cr.person_id, o.name
  ), rep as (
    select manager_id as id, count(*)::int as n
      from staff where manager_id is not null group by 1
  ), flat as (
    select s.full_name,
           jsonb_build_object(
             'personId',    s.id,
             'name',        s.full_name,
             'employeeNo',  s.employee_no,
             'workEmail',   s.work_email,
             'mobile',      s.mobile,
             'designation', d.title,
             'designationId', s.designation_id,
             'department',  s.department,
             'chair',       seat.chair,
             'chairId',     seat.chair_id,
             'seatingId',   seat.seating_id,
             'location',    coalesce(seat.scope_label, cov.place),
             -- Which of the two answered, so the screen can say so rather
             -- than let a coverage area pass for a posting.
             'locationFrom', case
               when seat.scope_label is not null then 'chair'
               when cov.place is not null then 'coverage'
               else null end,
             'managerId',   s.manager_id,
             'reportsTo',   m.full_name,
             'reports',     coalesce(rep.n, 0),
             'employeeType', coalesce(s.employee_type,'EMPLOYEE'),
             'appRole',     s.app_role,
             'joinedOn',    s.joined_on,
             -- Nobody may be moved under themselves, and the actor may not
             -- move themselves at all. Every other refusal org_move_person
             -- makes is about a loop, which the screen works out from the
             -- managerId column it already has.
             'mayMove',     s.id <> p_actor,
             'mayEdit',     true,
             'maySetRole',  a.app_role = 'ADMIN' and s.id <> p_actor
           ) as line
      from staff s
      left join designation d on d.id = s.designation_id
      left join seat on seat.person_id = s.id
      left join cov  on cov.person_id  = s.id
      left join person m on m.id = s.manager_id
      left join rep on rep.id = s.id
  )
  select jsonb_agg(line order by full_name) into v_rows from flat;

  -- The counts the chart cannot show. Each is a filter on the screen, so
  -- the number and the list behind it are the same question asked twice.
  select jsonb_build_object(
           'people',        count(*)::int,
           'noManager',     count(*) filter (where s.manager_id is null)::int,
           'noChair',       count(*) filter (where seat.person_id is null)::int,
           'noDesignation', count(*) filter (where s.designation_id is null)::int,
           'noDepartment',  count(*) filter (where s.department is null)::int,
           'noLocation',    count(*) filter
             (where seat.scope_label is null and cov.person_id is null)::int)
    into v_sum
    from person s
    left join (select distinct on (h.person_id) h.person_id, cs.scope_label
                 from chair_holder h
                 join chair ch on ch.id = h.chair_id
                 left join chair_seating cs on cs.id = h.seating_id
                where h.to_date is null
                order by h.person_id, h.is_primary desc nulls last, ch.title) seat
      on seat.person_id = s.id
    left join (select distinct on (cr.person_id) cr.person_id
                 from coverage_rule cr
                 join op_node o on o.id = coalesce(cr.op_node_id,
                        (select b.op_node_id from branch b where b.id = cr.branch_id))
                where cr.effective_to is null
                order by cr.person_id) cov
      on cov.person_id = s.id
   where s.employment_status = 'ACTIVE' and s.superseded_by is null
     and coalesce(s.employee_type,'EMPLOYEE')
         not in ('CLIENT_CONTACT','SERVICE_ACCOUNT');

  return jsonb_build_object(
    'mayUse',  true,
    'asAdministrator', a.app_role = 'ADMIN',
    'asHumanResources', coalesce(a.department,'') = 'Human Resources',
    'people',  coalesce(v_rows, '[]'::jsonb),
    'summary', v_sum,
    'note',    'Everybody who works here, whether or not the chart can draw '
            || 'them. Changing who somebody reports to is recorded and '
            || 'changes who can read their numbers.');
end
$function$
;

CREATE OR REPLACE FUNCTION public.org_person_set(p_actor uuid, p_person uuid, p_fields jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a person; s person;
  v_admin boolean; v_hr boolean;
  v_bad jsonb := '[]'::jsonb;
  v_changed jsonb := '[]'::jsonb;
  v_old jsonb := '{}'::jsonb;
  v_new jsonb := '{}'::jsonb;
  v_has_desig boolean; v_desig uuid;
  v_has_dept  boolean; v_dept text;
  v_has_chair boolean; v_chair uuid;
  v_has_seat  boolean; v_seat uuid;
  v_has_type  boolean; v_type text;
  v_has_mob   boolean; v_mob text;
  v_has_mail  boolean; v_mail text;
  v_has_no    boolean; v_no text;
  v_has_join  boolean; v_join date;
  v_has_role  boolean; v_role text;
  v_chair_now uuid; v_seat_now uuid;
  v_target_chair uuid;
  v_move jsonb;
  t text;
begin
  select * into a from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null then
    return jsonb_build_object('error','not_permitted','reason','Who is asking?');
  end if;

  select * into s from person
   where id = p_person and employment_status = 'ACTIVE' and superseded_by is null;
  if s.id is null then
    return jsonb_build_object('error','no_such_person');
  end if;

  v_admin := a.app_role = 'ADMIN';
  v_hr    := coalesce(a.department,'') = 'Human Resources';

  if not (v_admin or v_hr) then
    return jsonb_build_object('error','not_permitted',
      'reason','Changing somebody''s designation, chair, place or department '
            || 'is the administrator''s and Human Resources''. Your own team '
            || 'is the chart above.');
  end if;

  -- The service account is not a person. 245 put it outside the staff list;
  -- this keeps it there.
  if coalesce(s.employee_type,'EMPLOYEE') in ('SERVICE_ACCOUNT','CLIENT_CONTACT') then
    return jsonb_build_object('error','not_staff',
      'reason', s.full_name || ' is not a member of staff.');
  end if;

  if p_fields is null or jsonb_typeof(p_fields) <> 'object' then
    return jsonb_build_object('error','nothing_to_set',
      'reason','Send the fields to change.');
  end if;

  -- Validate everything first. A form with three bad boxes must not save the
  -- other three and leave somebody guessing which took.
  v_has_desig := p_fields ? 'designationId';
  if v_has_desig then
    v_desig := nullif(btrim(coalesce(p_fields->>'designationId','')),'')::uuid;
    if v_desig is not null and not exists (select 1 from designation d where d.id = v_desig) then
      v_bad := v_bad || jsonb_build_object('field','designation',
        'reason','That designation does not exist. Pick one from the list.');
    end if;
  end if;

  v_has_dept := p_fields ? 'department';
  if v_has_dept then
    v_dept := nullif(btrim(coalesce(p_fields->>'department','')),'');
    if v_dept is not null and length(v_dept) > 80 then
      v_bad := v_bad || jsonb_build_object('field','department',
        'reason','A department name longer than eighty characters is a sentence.');
    end if;
  end if;

  v_has_chair := p_fields ? 'chairId';
  if v_has_chair then
    v_chair := nullif(btrim(coalesce(p_fields->>'chairId','')),'')::uuid;
    if v_chair is not null and not exists (select 1 from chair c where c.id = v_chair) then
      v_bad := v_bad || jsonb_build_object('field','chair',
        'reason','That chair does not exist.');
    end if;
  end if;

  select h.chair_id, h.seating_id into v_chair_now, v_seat_now
    from chair_holder h
   where h.person_id = p_person and h.is_primary and h.to_date is null
   limit 1;

  v_has_seat := p_fields ? 'seatingId';
  if v_has_seat then
    v_seat := nullif(btrim(coalesce(p_fields->>'seatingId','')),'')::uuid;
    v_target_chair := case when v_has_chair then v_chair else v_chair_now end;
    if v_seat is not null then
      if v_target_chair is null then
        v_bad := v_bad || jsonb_build_object('field','location',
          'reason','A place is a seating of a chair. Give them a chair first.');
      elsif not exists (select 1 from chair_seating cs
                         where cs.id = v_seat and cs.chair_id = v_target_chair) then
        v_bad := v_bad || jsonb_build_object('field','location',
          'reason','That place belongs to a different chair.');
      end if;
    end if;
  end if;

  v_has_type := p_fields ? 'employeeType';
  if v_has_type then
    v_type := nullif(btrim(coalesce(p_fields->>'employeeType','')),'');
    if v_type is null or v_type not in ('EMPLOYEE','PARTNER','INTERN','CONTRACT') then
      v_bad := v_bad || jsonb_build_object('field','employeeType',
        'reason','Employee, Partner, Intern or Contract.');
    end if;
  end if;

  v_has_mob := p_fields ? 'mobile';
  if v_has_mob then
    v_mob := nullif(btrim(coalesce(p_fields->>'mobile','')),'');
    if v_mob is not null then
      if person_mobile(v_mob) !~ '^[6-9][0-9]{9}$' then
        v_bad := v_bad || jsonb_build_object('field','mobile',
          'reason','An Indian mobile number: ten digits starting 6, 7, 8 or 9.');
      elsif exists (select 1 from person p where p.id <> p_person
                     and p.left_on is null
                     and person_mobile(p.mobile) = person_mobile(v_mob)) then
        v_bad := v_bad || jsonb_build_object('field','mobile',
          'reason','Somebody else already has that number.');
      end if;
    end if;
  end if;

  v_has_mail := p_fields ? 'workEmail';
  if v_has_mail then
    v_mail := lower(nullif(btrim(coalesce(p_fields->>'workEmail','')),''));
    if v_mail is not null then
      if v_mail !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-zA-Z]{2,}$' then
        v_bad := v_bad || jsonb_build_object('field','workEmail',
          'reason','That is not an e-mail address.');
      elsif exists (select 1 from person p where p.id <> p_person
                     and p.superseded_by is null and p.left_on is null
                     and lower(p.work_email) = v_mail) then
        v_bad := v_bad || jsonb_build_object('field','workEmail',
          'reason','Somebody else already has that address.');
      end if;
    end if;
  end if;

  v_has_no := p_fields ? 'employeeNo';
  if v_has_no then
    v_no := nullif(btrim(coalesce(p_fields->>'employeeNo','')),'');
    if v_no is not null then
      if v_no !~ '^[A-Za-z0-9][A-Za-z0-9/_-]{0,19}$' then
        v_bad := v_bad || jsonb_build_object('field','employeeNo',
          'reason','Letters, numbers, slash, dash or underscore. Twenty at most.');
      elsif exists (select 1 from person p where p.id <> p_person
                     and p.superseded_by is null
                     and lower(btrim(p.employee_no)) = lower(v_no)) then
        v_bad := v_bad || jsonb_build_object('field','employeeNo',
          'reason','Somebody else already has that employee number.');
      end if;
    end if;
  end if;

  v_has_join := p_fields ? 'joinedOn';
  if v_has_join then
    begin
      v_join := nullif(btrim(coalesce(p_fields->>'joinedOn','')),'')::date;
    exception when others then
      v_join := null;
      v_bad := v_bad || jsonb_build_object('field','joinedOn',
        'reason','A date, as 2026-10-07.');
    end;
    if v_join is not null and v_join > current_date then
      v_bad := v_bad || jsonb_build_object('field','joinedOn',
        'reason','That is in the future. A joining date that has not happened '
              || 'yet belongs on an offer, not on a person.');
    end if;
  end if;

  v_has_role := p_fields ? 'appRole';
  if v_has_role then
    v_role := upper(nullif(btrim(coalesce(p_fields->>'appRole','')),''));
    if not v_admin then
      v_bad := v_bad || jsonb_build_object('field','appRole',
        'reason','What somebody is allowed to DO is the administrator''s. '
              || 'Everything else on this row is yours.');
    elsif v_role is null or v_role not in ('VIEWER','MANAGER','ADMIN') then
      v_bad := v_bad || jsonb_build_object('field','appRole',
        'reason','Viewer, Manager or Admin.');
    elsif p_person = p_actor and v_role <> a.app_role::text then
      v_bad := v_bad || jsonb_build_object('field','appRole',
        'reason','You cannot change your own role. Ask another administrator.');
    end if;
  end if;

  if jsonb_array_length(v_bad) > 0 then
    return jsonb_build_object('error','invalid',
      'fields', v_bad,
      'reason','Nothing was saved. Put these right and send it again.');
  end if;

  -- The reporting line, first and by delegation. org_move_person owns every
  -- rule about who may move whom, refuses a ring, writes the person_event and
  -- writes the audit row. A second copy here is a second copy to keep in step.
  if p_fields ? 'managerId' then
    v_move := org_move_person(p_actor, p_person,
                nullif(btrim(coalesce(p_fields->>'managerId','')),'')::uuid);
    if v_move->>'error' is not null then
      return v_move;
    end if;
    if coalesce((v_move->>'changed')::boolean, false) then
      v_changed := v_changed || jsonb_build_object('field','manager',
        'to', v_move->>'to', 'note', v_move->>'note');
    end if;
  end if;

  if v_has_desig and s.designation_id is distinct from v_desig then
    v_old := v_old || jsonb_build_object('designationId', s.designation_id);
    v_new := v_new || jsonb_build_object('designationId', v_desig);
    update person set designation_id = v_desig where id = p_person;
    v_changed := v_changed || jsonb_build_object('field','designation',
      'from', (select d.title from designation d where d.id = s.designation_id),
      'to',   (select d.title from designation d where d.id = v_desig));
  end if;

  if v_has_dept and btrim(coalesce(s.department,'')) is distinct from coalesce(v_dept,'') then
    v_old := v_old || jsonb_build_object('department', s.department);
    v_new := v_new || jsonb_build_object('department', v_dept);
    update person set department = v_dept where id = p_person;
    v_changed := v_changed || jsonb_build_object('field','department',
      'from', s.department, 'to', v_dept);
  end if;

  if v_has_type and coalesce(s.employee_type,'EMPLOYEE') is distinct from v_type then
    v_old := v_old || jsonb_build_object('employeeType', s.employee_type);
    v_new := v_new || jsonb_build_object('employeeType', v_type);
    update person set employee_type = v_type where id = p_person;
    v_changed := v_changed || jsonb_build_object('field','employeeType',
      'from', s.employee_type, 'to', v_type);
  end if;

  if v_has_mob and s.mobile is distinct from v_mob then
    v_old := v_old || jsonb_build_object('mobile', s.mobile);
    v_new := v_new || jsonb_build_object('mobile', v_mob);
    -- A new number has not been proved to be theirs, so the proof stays with
    -- the old one rather than following them to the new one.
    update person set mobile = v_mob, mobile_verified_at = null where id = p_person;
    v_changed := v_changed || jsonb_build_object('field','mobile',
      'from', s.mobile, 'to', v_mob);
  end if;

  if v_has_mail and lower(coalesce(s.work_email,'')) is distinct from coalesce(v_mail,'') then
    v_old := v_old || jsonb_build_object('workEmail', s.work_email);
    v_new := v_new || jsonb_build_object('workEmail', v_mail);
    update person set work_email = v_mail where id = p_person;
    v_changed := v_changed || jsonb_build_object('field','workEmail',
      'from', s.work_email, 'to', v_mail);
  end if;

  if v_has_no and btrim(coalesce(s.employee_no,'')) is distinct from coalesce(v_no,'') then
    v_old := v_old || jsonb_build_object('employeeNo', s.employee_no);
    v_new := v_new || jsonb_build_object('employeeNo', v_no);
    update person set employee_no = v_no where id = p_person;
    v_changed := v_changed || jsonb_build_object('field','employeeNo',
      'from', s.employee_no, 'to', v_no);
  end if;

  if v_has_join and s.joined_on is distinct from v_join then
    v_old := v_old || jsonb_build_object('joinedOn', s.joined_on);
    v_new := v_new || jsonb_build_object('joinedOn', v_join);
    update person set joined_on = v_join where id = p_person;
    v_changed := v_changed || jsonb_build_object('field','joinedOn',
      'from', s.joined_on, 'to', v_join);
  end if;

  if v_has_role and s.app_role::text is distinct from v_role then
    v_old := v_old || jsonb_build_object('appRole', s.app_role);
    v_new := v_new || jsonb_build_object('appRole', v_role);
    update person set app_role = v_role::role_kind where id = p_person;
    insert into person_event (person_id, kind, note, at)
    values (p_person, 'ROLE_CHANGED', s.app_role::text || ' -> ' || v_role, now());
    v_changed := v_changed || jsonb_build_object('field','appRole',
      'from', s.app_role, 'to', v_role);
  end if;

  -- A chair is held, not owned: the old holding is closed rather than
  -- overwritten, so last year's answer to "who sat there" survives.
  if v_has_chair and v_chair_now is distinct from v_chair then
    update chair_holder
       set to_date = current_date
     where person_id = p_person and is_primary and to_date is null;
    if v_chair is not null then
      insert into chair_holder (chair_id, person_id, is_primary, from_date, seating_id)
      values (v_chair, p_person, true, current_date,
              case when v_has_seat then v_seat else null end);
    end if;
    v_old := v_old || jsonb_build_object('chairId', v_chair_now);
    v_new := v_new || jsonb_build_object('chairId', v_chair);
    v_changed := v_changed || jsonb_build_object('field','chair',
      'from', (select c.title from chair c where c.id = v_chair_now),
      'to',   (select c.title from chair c where c.id = v_chair));
    v_seat_now := null;
  elsif v_has_seat and v_seat_now is distinct from v_seat then
    if v_chair_now is null then
      null;
    else
      update chair_holder set seating_id = v_seat
       where person_id = p_person and is_primary and to_date is null;
      v_old := v_old || jsonb_build_object('seatingId', v_seat_now);
      v_new := v_new || jsonb_build_object('seatingId', v_seat);
      v_changed := v_changed || jsonb_build_object('field','location',
        'from', (select cs.scope_label from chair_seating cs where cs.id = v_seat_now),
        'to',   (select cs.scope_label from chair_seating cs where cs.id = v_seat));
    end if;
  end if;

  if jsonb_array_length(v_changed) = 0 then
    return jsonb_build_object('ok', true, 'changed', false, 'personId', p_person,
      'fields','[]'::jsonb,
      'note','Nothing was different. Nothing was written.');
  end if;

  if v_old <> '{}'::jsonb then
    insert into audit_entry (actor_id, action, entity_type, entity_ref,
                             old_value, new_value)
    values (p_actor, 'PERSON_ASSIGNED', 'person', p_person::text, v_old, v_new);

    select string_agg(x->>'field', ', ' order by x->>'field') into t
      from jsonb_array_elements(v_changed) x where x->>'field' <> 'manager';
    insert into person_event (person_id, kind, note, at)
    values (p_person, 'DETAILS_CHANGED', coalesce(t,'details'), now());
  end if;

  return jsonb_build_object('ok', true, 'changed', true, 'personId', p_person,
    'name', s.full_name, 'fields', v_changed,
    'note', s.full_name || ': ' ||
            coalesce((select string_agg(x->>'field', ', ' order by x->>'field')
                        from jsonb_array_elements(v_changed) x), 'nothing') ||
            ' updated.');
end
$function$
;

CREATE OR REPLACE FUNCTION public.org_person_set_many(p_actor uuid, p_people jsonb, p_fields jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid; o jsonb;
  v_done jsonb := '[]'::jsonb;
  v_failed jsonb := '[]'::jsonb;
  n_changed int := 0;
begin
  if p_people is null or jsonb_typeof(p_people) <> 'array'
     or jsonb_array_length(p_people) = 0 then
    return jsonb_build_object('error','nobody_chosen',
      'reason','Tick the people this applies to.');
  end if;
  -- A cap, because "everybody" ticked by accident is a hundred-row write with
  -- no undo. Sixty is more than any one gap on the list today.
  if jsonb_array_length(p_people) > 60 then
    return jsonb_build_object('error','too_many',
      'reason','Sixty people at a time. More than that is an import, not a tidy-up.');
  end if;

  for v_id in select (x #>> '{}')::uuid from jsonb_array_elements(p_people) x loop
    o := org_person_set(p_actor, v_id, p_fields);
    if o->>'error' is not null then
      -- One person's bad row must not stop the other forty-eight, and must
      -- not be silently dropped either.
      v_failed := v_failed || jsonb_build_object('personId', v_id,
        'name', (select full_name from person where id = v_id),
        'error', o->>'error', 'reason', o->>'reason', 'fields', o->'fields');
    else
      if coalesce((o->>'changed')::boolean, false) then n_changed := n_changed + 1; end if;
      v_done := v_done || jsonb_build_object('personId', v_id,
        'name', o->>'name', 'changed', coalesce((o->>'changed')::boolean,false));
    end if;
  end loop;

  return jsonb_build_object(
    'ok', jsonb_array_length(v_failed) = 0,
    'changed', n_changed,
    'asked', jsonb_array_length(p_people),
    'done', v_done, 'failed', v_failed,
    'note', n_changed || ' of ' || jsonb_array_length(p_people) || ' updated' ||
            case when jsonb_array_length(v_failed) > 0
                 then ', ' || jsonb_array_length(v_failed) || ' refused.'
                 else '.' end);
end
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

CREATE OR REPLACE FUNCTION public.org_seat_from_the_line(p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role role_kind; r record;
  v_pass int := 0; v_moved int; v_placed int := 0; v_made int := 0;
  v_seat uuid; v_detail jsonb := '[]'::jsonb; v_left jsonb := '[]'::jsonb;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Seating the org chart is an administrator''s to do.');
  end if;

  loop
    v_pass := v_pass + 1; v_moved := 0;
    for r in
      select h.id as holder_id, h.chair_id, pe.full_name, c.code as chair_code,
             ms.id as mgr_seating, ms.scope_label as place, mp.full_name as mgr_name
        from chair_holder h
        join person pe on pe.id = h.person_id
        join chair  c  on c.id  = h.chair_id
        join person mp on mp.id = pe.manager_id and mp.id <> pe.id
        join chair_holder mh on mh.person_id = mp.id and mh.to_date is null
        join chair_seating ms on ms.id = mh.seating_id
       where h.to_date is null and h.seating_id is null
         and pe.employment_status = 'ACTIVE' and pe.superseded_by is null
       order by c.code, pe.full_name
    loop
      select s.id into v_seat from chair_seating s
       where s.chair_id = r.chair_id
         and s.scope_label is not distinct from r.place
       order by s.id limit 1;

      if v_seat is null then
        insert into chair_seating (chair_id, scope_label, reports_to_seating_id, note)
        values (r.chair_id, r.place, r.mgr_seating,
                'Made by migration 219 from the reporting line, not from the '
                || 'source chart: ' || r.full_name || ' reports to ' || r.mgr_name
                || ', who sits in ' || coalesce(r.place, 'no particular place')
                || ', and this chair had no seat there.')
        returning id into v_seat;
        v_made := v_made + 1;
      end if;

      update chair_holder set seating_id = v_seat where id = r.holder_id;
      v_placed := v_placed + 1; v_moved := v_moved + 1;
      v_detail := v_detail || jsonb_build_object(
        'person', r.full_name, 'chair', r.chair_code,
        'place', coalesce(r.place, 'No particular place'), 'from', r.mgr_name);
    end loop;
    exit when v_moved = 0 or v_pass >= 12;
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object(
           'person', q.full_name, 'chair', q.code, 'why', q.why)
         order by q.code, q.full_name), '[]'::jsonb)
    into v_left
    from (
      select pe.full_name, c.code,
             case
               when pe.manager_id is null then 'no manager on record to sit beside'
               when not exists (select 1 from chair_holder mh
                                 where mh.person_id = pe.manager_id and mh.to_date is null)
                 then 'their manager holds no chair'
               else 'their manager has no place either'
             end as why
        from chair_holder h
        join person pe on pe.id = h.person_id
        join chair  c  on c.id  = h.chair_id
       where h.to_date is null and h.seating_id is null
         and pe.employment_status = 'ACTIVE' and pe.superseded_by is null) q;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'CHAIR_HOLDERS_SEATED_FROM_LINE', 'chair_holder', 'bulk',
          jsonb_build_object('passes', v_pass, 'placed', v_placed,
                             'seatings_made', v_made, 'left', jsonb_array_length(v_left)));

  return jsonb_build_object(
    'passes', v_pass, 'placed', v_placed, 'seatingsMade', v_made,
    'detail', v_detail, 'unplaced', jsonb_array_length(v_left), 'left', v_left);
end $function$
;

CREATE OR REPLACE FUNCTION public.org_subtree(p_person uuid)
 RETURNS TABLE(person_id uuid, depth integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with recursive down as (
    select p.id, 0 as depth
      from person p
     where p.id = p_person
       and p.employment_status = 'ACTIVE' and p.superseded_by is null
    union all
    select c.id, d.depth + 1
      from down d
      join person c on c.manager_id = d.id
     where d.depth < 12
       and c.employment_status = 'ACTIVE' and c.superseded_by is null)
  select id, depth from down;
$function$
;

CREATE OR REPLACE FUNCTION public.org_team_tree(p_actor uuid, p_root uuid DEFAULT NULL::uuid, p_cycle uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_root uuid; v_cycle uuid; v_rel text;
begin
  v_root := coalesce(p_root, p_actor);
  v_rel  := perf_rel(p_actor, v_root);
  if v_rel is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That person is not in your line.');
  end if;

  v_cycle := coalesce(p_cycle,
    (select id from perf_cycle
      where period_kind = 'MONTH' and period_start <= current_date
      order by period_start desc limit 1));

  return jsonb_build_object(
    'rootId', v_root,
    'cycleId', v_cycle,
    'mayAdd', org_may_add_under(p_actor, v_root),
    'people', coalesce((
      select jsonb_agg(jsonb_build_object(
               'personId', x.id,
               'name', x.full_name,
               'employeeNo', x.employee_no,
               'email', x.work_email,
               'managerId', x.manager_id,
               'depth', x.depth,
               'chair', x.chair,
               'department', x.department,
               'reports', x.reports,
               -- What may THIS viewer do to THIS person, decided here and
               -- not guessed by the screen. A tile that offers an action
               -- the server refuses is how the target box went wrong.
               'rel', perf_rel(p_actor, x.id),
               'maySet', perf_may_set(p_actor, x.id),
               'mayAddUnder', org_may_add_under(p_actor, x.id),
               'mayMove', case
                 when x.id = p_actor then false
                 when x.depth = 0 then false
                 else perf_may_set(p_actor, x.id)
                      or (select app_role from person where id = p_actor) = 'ADMIN'
                      or coalesce((select department from person where id = p_actor),'')
                         = 'Human Resources' end,
               'measures', x.measures,
               'filed', x.filed,
               'onTrack', x.on_track,
               -- The one number a tile shows: measures at or past target
               -- over measures with a target. Null rather than zero when
               -- there is nothing to be a fraction of.
               'progress', case when x.with_target = 0 then null
                                else round(100.0 * x.on_track / x.with_target, 0) end)
             order by x.depth, x.full_name)
      from (
        select p.id, p.full_name, p.employee_no, p.work_email, p.manager_id,
               t.depth, p.department,
               (select ch.title from chair_holder h join chair ch on ch.id = h.chair_id
                 where h.person_id = p.id and h.to_date is null
                 order by h.is_primary desc limit 1) as chair,
               (select count(*) from person r
                 where r.manager_id = p.id and r.employment_status = 'ACTIVE'
                   and r.superseded_by is null) as reports,
               (select count(*) from perf_assignment a
                 where a.person_id = p.id and a.cycle_id = v_cycle
                   and a.part_of_id is null) as measures,
               (select count(perf_value(a.id)) from perf_assignment a
                 where a.person_id = p.id and a.cycle_id = v_cycle
                   and a.part_of_id is null) as filed,
               (select count(*) from perf_assignment a
                 where a.person_id = p.id and a.cycle_id = v_cycle
                   and a.part_of_id is null and a.target_value is not null) as with_target,
               (select count(*) from perf_assignment a
                 where a.person_id = p.id and a.cycle_id = v_cycle
                   and a.part_of_id is null and a.target_value is not null
                   and perf_value(a.id) is not null
                   and ((perf_direction(a.unit) = 'CEILING'
                         and perf_value(a.id) <= a.target_value)
                     or (perf_direction(a.unit) = 'FLOOR'
                         and perf_value(a.id) >= a.target_value))) as on_track
          from org_subtree(v_root) t
          join person p on p.id = t.person_id
         -- The subtree is walked from the root, but the ANSWER is still
         -- filtered by what this viewer may see. A root they may read does
         -- not make everybody under it readable.
         where perf_may_see(p_actor, p.id)
      ) x), '[]'::jsonb));
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

CREATE OR REPLACE FUNCTION public.perf_assign_edit(p_actor uuid, p_in jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a perf_assignment; c perf_cycle; v_was jsonb; v_name text; v_cadence text;
begin
  select * into a from perf_assignment where id = (p_in->>'assignmentId')::uuid;
  if a.id is null then return jsonb_build_object('error','no_such_assignment'); end if;
  if not perf_may_set(p_actor, a.person_id) then
    return jsonb_build_object('error','not_permitted',
      'reason','A measure is changed by the person''s own manager or by an '
            || 'administrator -- and never by themselves.');
  end if;
  select * into c from perf_cycle where id = a.cycle_id;
  if current_date > c.assign_closes
     and not exists (select 1 from person where id = p_actor and app_role = 'ADMIN') then
    return jsonb_build_object('error','window_closed',
      'reason','Measures for ' || c.period_start || ' had to be settled by '
            || c.assign_closes || '. An administrator can still change them, '
            || 'and it is recorded.');
  end if;
  if a.part_of_id is not null and (p_in ? 'name') then
    return jsonb_build_object('error','is_a_split',
      'reason','That row is one client''s share of a measure, not a measure. '
            || 'Rename the measure it belongs to and every share follows.');
  end if;
  v_name := nullif(btrim(coalesce(p_in->>'name', a.name)), '');
  if v_name is null then
    return jsonb_build_object('error','no_name','reason','Give the measure a name.');
  end if;
  v_cadence := nullif(p_in->>'cadence','');
  if v_cadence is not null and v_cadence not in ('DAILY','WEEKLY','MONTHLY','QUARTERLY') then
    return jsonb_build_object('error','bad_cadence',
      'reason','A cadence is DAILY, WEEKLY, MONTHLY or QUARTERLY.');
  end if;
  if p_in ? 'rollsInto' and nullif(p_in->>'rollsInto','') is not null then
    if (p_in->>'rollsInto')::uuid = a.id then
      return jsonb_build_object('error','rolls_into_itself',
        'reason','A measure cannot climb into itself.');
    end if;
    if not exists (select 1 from perf_assignment x
                    where x.id = (p_in->>'rollsInto')::uuid
                      and x.person_id = p_actor) then
      return jsonb_build_object('error','not_your_measure',
        'reason','A measure climbs into one of your own. Pick one of yours, '
              || 'or leave it unlinked.');
    end if;
  end if;
  v_was := jsonb_build_object('name', a.name, 'unit', a.unit,
             'weight', a.weight_pct, 'cadence', a.cadence,
             'cadenceDay', a.cadence_day, 'rollsInto', a.rolls_into_id,
             'note', a.note);
  update perf_assignment set
    name        = v_name,
    unit        = case when p_in ? 'unit' then nullif(btrim(coalesce(p_in->>'unit','')),'') else unit end,
    weight_pct  = case when p_in ? 'weight' then nullif(p_in->>'weight','')::numeric else weight_pct end,
    cadence_day = case when p_in ? 'cadenceDay' then nullif(p_in->>'cadenceDay','')::int else cadence_day end,
    note        = case when p_in ? 'note' then nullif(btrim(coalesce(p_in->>'note','')),'') else note end,
    rolls_into_id = case when p_in ? 'rollsInto' then nullif(p_in->>'rollsInto','')::uuid else rolls_into_id end
   where id = a.id;
  if v_cadence is not null then
    execute format('update perf_assignment set cadence = %L where id = %L',
                   v_cadence, a.id);
  end if;
  if p_in ? 'name' then
    update perf_assignment set name = v_name where part_of_id = a.id;
  end if;
  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, 'PERF_KPI_CHANGED', 'perf_assignment', a.id::text, v_was, p_in);
  return jsonb_build_object('ok', true, 'assignmentId', a.id, 'name', v_name,
    'note', 'Changed. The target is set separately, so it has not moved.');
end $function$
;

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

