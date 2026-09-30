-- A manager asks for a joiner, and HR makes the account (234)
--
-- The question this answers is "how would the managers add their team
-- members", and the honest answer up to now was: they could not. person_add
-- refuses anybody who is not HR or an administrator, and it is right to.
-- Creating a person creates an ACCOUNT -- an identity that can sign in, be
-- paid, hold a chair and read other people's numbers. That is not a thing a
-- branch manager should be able to do at four in the afternoon because
-- somebody started on Monday.
--
-- But "the manager cannot do it" is not the same as "the manager cannot
-- start it". There are two different things behind the + on a tile and they
-- should not be confused with each other:
--
--   MOVING somebody who already works here under a different manager is an
--   org decision. The identity already exists; nothing is created. The
--   manager owns that, and org_move_person (229) already does it.
--
--   ADDING somebody who does not work here yet is an HR decision, because
--   it makes an account. The manager owns the ASK; HR owns the ACCOUNT.
--
-- So the + offers both, and this migration builds the second: a request the
-- manager files and HR turns into a person. The table for it has been in the
-- schema since the beginning -- person_request, with its approval states, its
-- reject-reason constraint, its finance columns, and a foreign key from
-- onboarding pointing at it -- and in all that time not one function has ever
-- written a row into it. It was designed and never built. This builds it.
--
-- The one rule that matters here: a request is not an account. Approving it
-- calls person_add, which runs every one of its own checks again, under the
-- APPROVER's authority and not the requester's. Nothing here is a back door
-- into person_add; it is a queue in front of it.

-- ----------------------------------------------- who may add under whom
-- Written once, so the + on the tile, the request, and the move all agree.
--
-- Two differences from perf_may_set, both deliberate. It is false for SELF by
-- design, which is right for targets -- nobody sets their own -- and wrong
-- here, because adding somebody to your own team is the ordinary case and the
-- one the + exists for. And it does not know about HR, which is right for
-- targets and wrong here for the same reason mayMove on a tile already spells
-- HR and the administrator out: the people who hold the org chart must be
-- able to act anywhere on it, or the ones who can are only the ones with a
-- team, and HR has no team.
create or replace function org_may_add_under(p_actor uuid, p_under uuid)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $function$
  select p_actor is not null and p_under is not null
     and (p_under = p_actor
       or perf_may_set(p_actor, p_under)
       or exists (select 1 from person a where a.id = p_actor
                   and (a.app_role = 'ADMIN'
                     or coalesce(a.department,'') = 'Human Resources')));
$function$;

comment on function org_may_add_under(uuid,uuid) is
  'True when this actor may put somebody under that person: their own team, '
  'a team they already manage, or anywhere at all if they are HR or an '
  'administrator. Unlike perf_may_set it is true for self, because adding '
  'to your own team is the ordinary case.';

-- ------------------------------------------------- what the + offers
-- One call, so the panel does not have to guess which of the two paths is
-- open to this person, nor go fishing for a list of people to move.
create or replace function org_add_options(p_actor uuid, p_under uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_actor person; v_under person; v_chair uuid;
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

  return jsonb_build_object(
    'underId', p_under,
    'underName', v_under.full_name,
    -- HR and an administrator can skip the queue, because for them the
    -- queue would only be a queue of one behind themselves.
    'mayCreate', v_actor.app_role = 'ADMIN'
                 or coalesce(v_actor.department,'') = 'Human Resources',
    'mayRequest', true,

    -- Somebody who already works here. Only people this actor may move,
    -- and not the ones already reporting to p_under, and never p_under's
    -- own line upwards -- org_move_person would refuse those as a loop and
    -- an option that is always refused is not an option.
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
       and q.id <> p_under
       and coalesce(q.manager_id, '00000000-0000-0000-0000-000000000000'::uuid) <> p_under
       and perf_may_set(p_actor, q.id)
       and p_under not in (select person_id from org_subtree(q.id))
    ), '[]'::jsonb),

    -- The chairs a report of this person would plausibly sit in: the ones
    -- reporting to their own chair. If their chair has no children below
    -- it, offering nothing would be worse than offering everything.
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

    -- What is already in the queue for this person, so nobody files the
    -- same joiner twice on Monday and Tuesday.
    'pending', coalesce((
      select jsonb_agg(jsonb_build_object(
               'requestId', r.id, 'name', r.full_name, 'email', r.work_email,
               'state', r.state, 'requestedAt', r.requested_at,
               'requestedBy', (select q.full_name from person q where q.id = r.requested_by))
             order by r.requested_at desc)
      from person_request r
     where r.manager_id = p_under and r.state in ('DRAFT','AWAITING_HR','AWAITING_ADMIN')
    ), '[]'::jsonb));
end $function$;

comment on function org_add_options(uuid,uuid) is
  'What the + button on a tile may offer: people already employed who this '
  'actor may move under that person, the chairs a report would sit in, '
  'whether this actor can create outright or must ask HR, and anything '
  'already queued for that manager.';

-- ------------------------------------------------------- the manager asks
create or replace function person_request_open(p_actor uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
end $function$;

comment on function person_request_open(uuid,jsonb) is
  'A manager asks for somebody who does not work here yet. It creates a '
  'request, never a person: the account is HR''s to make.';

-- ------------------------------------------------------ what is in the queue
create or replace function person_request_list(p_actor uuid,
                                               p_state text default null)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
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
end $function$;

comment on function person_request_list(uuid,text) is
  'The joiner queue. HR sees all of it; a manager sees their own asks and '
  'anything asked for a team they manage.';

-- ------------------------------------------------------ HR makes the account
create or replace function person_request_decide(p_actor uuid, p_request uuid,
                                                 p_decision text,
                                                 p jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
end $function$;

comment on function person_request_decide(uuid,uuid,text,jsonb) is
  'HR turns a manager''s ask into an account, or refuses it with a reason. '
  'Approving calls person_add under the approver''s authority, so every '
  'check it makes is made again.';

-- --------------------------------------------- the tile knows about its +
-- org_team_tree already said whether the ROOT could be added to. Every tile
-- needs it, not just the top one, or the + can only ever appear in one place.
create or replace function org_team_tree(p_actor uuid, p_root uuid default null,
                                         p_cycle uuid default null)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
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
end $function$;

comment on function org_team_tree(uuid,uuid,uuid) is
  'The team as tiles: who is under this root, what each holds this cycle, '
  'how far through their targets they are, and -- decided per person, not '
  'per screen -- what this viewer may do to each of them.';

-- ------------------------------------------------------------- the gate
-- Same as 228: SECURITY DEFINER functions that take an actor must never be
-- callable by an unauthenticated role, or the actor argument IS the bypass.
revoke execute on function org_may_add_under(uuid,uuid) from public, anon, authenticated;
revoke execute on function org_add_options(uuid,uuid) from public, anon, authenticated;
revoke execute on function person_request_open(uuid,jsonb) from public, anon, authenticated;
revoke execute on function person_request_list(uuid,text) from public, anon, authenticated;
revoke execute on function person_request_decide(uuid,uuid,text,jsonb) from public, anon, authenticated;
revoke execute on function org_team_tree(uuid,uuid,uuid) from public, anon, authenticated;

do $guard$
declare n int;
begin
  select count(*) into n from pg_proc
   where proname in ('org_may_add_under','org_add_options','person_request_open',
                     'person_request_list','person_request_decide');
  if n <> 5 then
    raise exception 'Migration 234 left % of 5 functions behind', n;
  end if;

  -- The one that would be silently wrong: the tree not carrying mayAddUnder
  -- means the + never appears and nobody notices, because nothing errors.
  if position('mayAddUnder' in
       (select prosrc from pg_proc where proname = 'org_team_tree')) = 0 then
    raise exception 'Migration 234 did not put mayAddUnder on the tiles';
  end if;

  -- And the one that would be quietly dangerous.
  if exists (select 1 from information_schema.role_routine_grants
              where routine_name in ('org_add_options','person_request_open',
                                     'person_request_decide','org_team_tree')
                and grantee in ('anon','PUBLIC')) then
    raise exception 'Migration 234 left a joiner function open to anon';
  end if;
end $guard$;
