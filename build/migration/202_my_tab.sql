-- My profile, as the design draws it.
--
-- The design's screen is three things, and its own subtitle says which:
-- "Your details, your tasks, and anything you need from another department."
-- The build had the first two and nothing at all of the third.
--
-- The third is not a missing button. It is a whole loop the schema was
-- already shaped for and nothing has ever used:
--
--   raisable      (id, kind, ref, raised_by, about_person, department, body)
--                 kind is ESCALATION | WARNING | APPRECIATION | ASSISTANCE.
--                 An assistance request is a raisable. 0 rows.
--   request_task  (raisable_id, responder_id, due_at, actioned_at,
--                  strike_count, escalated_case_id)
--                 The design: "Becomes a task in the responder's profile. If
--                 it is not actioned, an escalation is raised automatically
--                 against them under the three-strike policy." 0 rows.
--
-- Two tables, both empty, both exactly the right shape. This fills them.
--
-- What is NOT done here, and is said rather than faked: the automatic
-- escalation at the third strike. The only case-creating function in this
-- database is ogl_case_create, which is about OGL verification -- it wants a
-- client code, a zone and a branch, and means something else entirely.
-- Pointing a stale assistance request at it would put a wrong row in the
-- escalation ledger, which is worse than a strike that is only counted.
-- The strikes ARE counted, the responder and their manager are both told,
-- and the count is on the screen.

-- ------------------------------------------------- two fields the design has
-- The Contact card asks for an address and an emergency contact, and the
-- design's own HR block measures completeness across both. There was nowhere
-- to put either, so "Amit Kulkarni has changed his address" -- a task in the
-- design's own list -- could not have been raised, let alone approved.
alter table person add column if not exists address text;
alter table person add column if not exists emergency_contact text;

comment on column person.address is
  'Changed through the profile change-request path, never typed straight in: HR approves and then the record moves.';

-- ------------------------------------------------------------- documents
-- Four kinds, because the design names four. A person with no row for a kind
-- has not been asked for it yet, which is a different thing from being asked
-- and not having produced it -- so absence is its own state and is not stored.
create table if not exists person_document (
  id          uuid primary key default gen_random_uuid(),
  person_id   uuid not null references person(id) on delete cascade,
  kind        text not null check (kind in
                ('ID_PROOF','ADDRESS_PROOF','QUALIFICATION','BANK_DETAILS')),
  state       text not null default 'WITH_HR' check (state in
                ('WITH_HR','VERIFIED','REVISION_REQUESTED','WITH_ACCOUNTS')),
  note        text,
  updated_by  uuid references person(id),
  updated_at  timestamptz not null default now(),
  constraint person_document_once unique (person_id, kind)
);

comment on table person_document is
  'One row per document a person has actually produced. No row means it has not been asked for -- which the screen says, rather than showing a blank that reads as missing.';

revoke all on table person_document from public, anon, authenticated;

-- ------------------------------------------------------- who answers for it
--
-- The design's form picks a DEPARTMENT, not a person, which is right: the
-- person raising it should not have to know who is on duty. So the department
-- has to resolve to somebody, and it has to resolve to somebody who is not
-- the person asking.
--
-- The head of the department first, then whoever there has least on their
-- plate. Fewest OPEN tasks, not fewest tasks ever -- otherwise the person who
-- answers promptly is rewarded with all of it.
create or replace function public.request_responder(p_dept text, p_not uuid default null)
returns uuid language sql stable security definer set search_path to 'public' as $fn$
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
$fn$;

-- ----------------------------------------------------------------- raising
create or replace function public.request_raise(p_actor uuid, p_in jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
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
    -- Two different emptinesses, and they need different answers.
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

  -- Six working hours, on the responder's clock rather than the asker's,
  -- because it is the responder the deadline is about.
  v_due := working_hours_after(now(), 6::numeric, person_centre(v_to));
  v_ref := next_ref('REQ');

  insert into raisable (kind, ref, raised_by, department, body, created_at)
  values ('ASSISTANCE', v_ref, p_actor, v_dept,
          -- the type and the thing itself, joined the way the screen joins
          -- anything else: a middot. Two hyphens are how this codebase writes
          -- an aside in a COMMENT, and they read as a typo on a screen.
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
end $fn$;

-- ---------------------------------------------------------------- actioning
create or replace function public.request_action(
  p_actor uuid, p_task uuid, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
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
end $fn$;

revoke all on function public.request_responder(text, uuid) from public, anon, authenticated;
revoke all on function public.request_raise(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.request_action(uuid, uuid, text) from public, anon, authenticated;

-- ----------------------------------------------------------- the strikes
-- Swept once a morning. A strike is recorded, the responder is told, and
-- their manager is told from the second one -- because the first is a busy
-- day and the third is a pattern, and only one of those is the manager's
-- business.
create or replace function public.request_strike_sweep(p_on date default current_date)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
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
end $fn$;

insert into job_config (job_key, enabled, cron, reason)
values ('REQUEST_STRIKES', true, '0 5 * * *',
        'One strike a day against a request that is past its time and still '
        || 'unanswered, up to three. The responder is told every time; their '
        || 'manager from the second, because the first is a busy day and the '
        || 'third is a pattern.')
on conflict (job_key) do nothing;

create or replace function public.crux_request_strike_tick()
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
begin
  if not coalesce((select enabled from job_config where job_key='REQUEST_STRIKES'), false) then
    return jsonb_build_object('skipped', 'REQUEST_STRIKES is switched off.');
  end if;
  return request_strike_sweep();
end $fn$;

-- ------------------------------------------------------------- the screen
--
-- One call, because the screen is one page and four round trips to draw it
-- is four chances for half of it to arrive.
--
-- The three cards are the design's three: Employment, Contact, Documents.
-- A field nobody has filled in comes back null and the screen says "not
-- recorded", which is the truth; a document nobody has asked for is absent
-- from the list rather than shown as missing, because those are different.
create or replace function public.my_desk(p_person uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare p person%rowtype; cyc uuid;
begin
  select * into p from person where id = p_person;
  if p.id is null then return jsonb_build_object('error','no_such_person'); end if;
  select id into cyc from perf_cycle
   where period_kind = 'MONTH' and period_start = date_trunc('month', current_date)::date;

  return jsonb_build_object(
    'person', jsonb_build_object('personId', p.id, 'name', p.full_name),

    'employment', jsonb_build_array(
      jsonb_build_object('label','Employee number', 'value', p.employee_no, 'field', null),
      jsonb_build_object('label','Chair', 'value',
        (select string_agg(ch.title, ' · ' order by h.is_primary desc, ch.title)
           from chair_holder h join chair ch on ch.id = h.chair_id
          where h.person_id = p.id and h.to_date is null), 'field', null),
      jsonb_build_object('label','Reports to', 'value',
        (select m.full_name || coalesce(' (' || m.employee_no || ')','')
           from person m where m.id = p.manager_id), 'field', null),
      jsonb_build_object('label','Department', 'value', p.department, 'field','department'),
      jsonb_build_object('label','Date of joining', 'value',
        case when p.joined_on is null then null else to_char(p.joined_on,'FMDD FMMon YYYY') end,
        'field', null),
      jsonb_build_object('label','Employment type', 'value',
        coalesce(p.employee_type,'EMPLOYEE'), 'field', null)),

    'contact', jsonb_build_array(
      jsonb_build_object('label','Mobile', 'value', p.mobile, 'field','mobile'),
      jsonb_build_object('label','Work e-mail', 'value', p.work_email, 'field','work_email'),
      jsonb_build_object('label','Address', 'value', p.address, 'field','address'),
      jsonb_build_object('label','Emergency contact', 'value', p.emergency_contact,
        'field','emergency_contact')),

    'documents', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'kind', k.kind, 'label', k.label,
               'state', d.state, 'note', d.note,
               'updatedAt', d.updated_at) order by k.n), '[]'::jsonb)
        from (values (1,'ID_PROOF','ID proof'), (2,'ADDRESS_PROOF','Address proof'),
                     (3,'QUALIFICATION','Qualification'), (4,'BANK_DETAILS','Bank details'))
               as k(n, kind, label)
        left join person_document d on d.person_id = p.id and d.kind = k.kind),

    -- what I asked other people for, and where it got to
    'raised', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'ref', rz.ref, 'department', rz.department, 'body', rz.body,
               'raisedAt', rz.created_at, 'dueAt', t.due_at,
               'actionedAt', t.actioned_at, 'strikes', t.strike_count,
               'responder', w.full_name) order by rz.created_at desc), '[]'::jsonb)
        from raisable rz
        join request_task t on t.raisable_id = rz.id
        join person w on w.id = t.responder_id
       where rz.raised_by = p_person and rz.kind = 'ASSISTANCE'),

    -- and what other people are waiting on me for
    'onMe', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'taskId', t.id, 'ref', rz.ref, 'department', rz.department,
               'body', rz.body, 'from', f.full_name, 'raisedAt', rz.created_at,
               'dueAt', t.due_at, 'strikes', t.strike_count,
               'overdue', now() > t.due_at) order by t.due_at), '[]'::jsonb)
        from request_task t
        join raisable rz on rz.id = t.raisable_id
        join person f on f.id = rz.raised_by
       where t.responder_id = p_person and t.actioned_at is null),

    'dueToday', case when cyc is null then '[]'::jsonb else perf_due(p_person) end,

    'says', 'Edits are not live. HR approves, then the record changes, and your old '
         || 'and new values sit side by side on their task until it does.');
end $fn$;

revoke all on function public.request_strike_sweep(date) from public, anon, authenticated;
revoke all on function public.crux_request_strike_tick() from public, anon, authenticated;
revoke all on function public.my_desk(uuid) from public, anon, authenticated;
