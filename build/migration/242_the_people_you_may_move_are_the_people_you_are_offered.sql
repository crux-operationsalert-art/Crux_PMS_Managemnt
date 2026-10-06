-- The people you may move are the people you are offered (242)
--
-- "Drag and drop function in the my team and structure isn't working and
-- plus I don't have an option to add existing team member."
--
-- The second half first, because it explains the first.
--
-- The option IS there. The + on a tile opens a panel with two tabs, and the
-- first is "Somebody already here". It was empty for almost everybody, and
-- a tab that is always empty is indistinguishable from a tab that does not
-- exist.
--
-- It was empty because org_add_options builds that list with
-- perf_may_set(p_actor, q.id), which is TRUE only for the actor's direct
-- reports. org_move_person -- the thing that actually does the move -- is
-- far wider: a manager may move anybody in their whole subtree, and an
-- administrator or Human Resources may move anybody at all.
--
-- So the list and the gate disagreed, in the direction nobody notices:
--
--   a manager with reports two steps down   could move them, was not offered them
--   Human Resources                         could move anybody, was offered nobody
--   an administrator                        could move anybody, was offered nobody
--
-- 234's own comment on that list says "an option that is always refused is
-- not an option". True, and this is its mirror: an option that would be
-- allowed and is never offered is a feature nobody can find.
--
-- This rewrites the list so it asks the same questions org_move_person
-- asks, in the same order, and nothing else changes. Specifically it does
-- NOT touch perf_rel or perf_may_set: who may set a person's TARGETS is a
-- separate question from who may re-parent them on the org chart, and
-- migration 241 has just finished putting the first one back.
--
-- ON THE DRAGGING. mayMove on a tile already names ADMIN and HR correctly,
-- so the gesture is armed where it should be. What the gesture cannot do is
-- work on a touchscreen: HTML5 drag-and-drop fires no events for a finger,
-- in any browser, and no amount of fixing the handler changes that. The
-- panel this migration repairs IS the other way to do it -- pick the person
-- from a list and press the button -- which is why the two halves of the
-- complaint have one fix.

create or replace function org_add_options(p_actor uuid, p_under uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
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

  -- The same two roles org_move_person checks first, read once.
  v_wide := v_actor.app_role = 'ADMIN'
            or coalesce(v_actor.department,'') = 'Human Resources';

  return jsonb_build_object(
    'underId', p_under,
    'underName', v_under.full_name,
    'mayCreate', v_wide,
    'mayRequest', true,

    -- Somebody who already works here, and whom org_move_person would
    -- actually let this person move under p_under. Every clause below is
    -- one org_move_person asks, so the list cannot offer a move that is
    -- then refused, and cannot withhold one that would be allowed.
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
       and coalesce(q.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
       -- not the person they would be moved under, and not already there
       and q.id <> p_under
       and coalesce(q.manager_id, '00000000-0000-0000-0000-000000000000'::uuid) <> p_under
       -- rule 3: nobody moves themselves, and nobody moves their own
       -- manager unless they are an administrator or HR
       and q.id <> p_actor
       and (v_wide or q.id is distinct from v_actor.manager_id)
       -- rules 1 and 2: an ordinary manager works inside their own subtree,
       -- and may only move somebody to a manager inside it. p_under is
       -- fixed here, so the second is asked once, outside the loop.
       and (v_wide
            or (exists (select 1 from org_subtree(p_actor) t
                         where t.person_id = q.id and t.depth > 0)
                and exists (select 1 from org_subtree(p_actor) t
                             where t.person_id = p_under)))
       -- and the move must not turn the line into a circle
       and p_under not in (select person_id from org_subtree(q.id))
    ), '[]'::jsonb),

    -- The chairs a report of this person would plausibly sit in: the ones
    -- reporting to their own chair. If their chair has no children below
    -- it, offering nothing would be worse than offering everything.
    --
    -- Copied from 234 unchanged. A first draft of this file rewrote both
    -- this and `pending` from memory and got the columns, the states and
    -- the join wrong in each. Nothing below the movable list is this
    -- migration's business.
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
  'actor may move under that person -- asked with the same questions '
  'org_move_person asks, so the list and the gate agree -- the chairs a '
  'report would sit in, whether this actor can create outright or must ask '
  'HR, and anything already queued for that manager.';

-- ------------------------------------------------------------- the guard
do $guard$
declare
  v_adm uuid; v_hr uuid; n_adm int; n_hr int; n_all int;
begin
  select id into v_adm from person
   where app_role = 'ADMIN' and employment_status = 'ACTIVE' and superseded_by is null
   limit 1;
  select id into v_hr from person
   where coalesce(department,'') = 'Human Resources'
     and employment_status = 'ACTIVE' and superseded_by is null
     and app_role is distinct from 'ADMIN'
   limit 1;

  select count(*) into n_all from person
   where employment_status = 'ACTIVE' and superseded_by is null
     and coalesce(employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT';

  -- The floor is half, not "everybody but two". A first draft asserted
  -- n_all - 2 and failed on the live database at 101 of 104 -- correctly.
  -- Three people are missing and all three should be: the administrator
  -- themselves, and the two people ABOVE them, because moving your own
  -- manager underneath you closes the reporting line into a ring. How many
  -- that comes to depends on how deep the actor sits, so a guard that
  -- counts it exactly is a guard that breaks when somebody is promoted.
  --
  -- The exact claim -- that the list and org_move_person agree, person by
  -- person -- is build/test/test_offer.sql, which attempts all 96 moves
  -- rather than restating the predicate. What is asserted here is only
  -- that the bug being fixed is gone: HR and an administrator were offered
  -- NOBODY, and are now offered most of the company.
  if v_adm is not null then
    select jsonb_array_length(org_add_options(v_adm, v_adm)->'movable') into n_adm;
    if n_adm < n_all / 2 then
      raise exception 'Migration 242: an administrator is offered % of % people',
        n_adm, n_all;
    end if;
    raise notice 'an administrator is offered % of % people', n_adm, n_all;
  end if;

  if v_hr is not null then
    select jsonb_array_length(org_add_options(v_hr, v_hr)->'movable') into n_hr;
    if n_hr < n_all / 2 then
      raise exception 'Migration 242: Human Resources is offered % of % people',
        n_hr, n_all;
    end if;
    raise notice 'Human Resources is offered % of % people', n_hr, n_all;
  end if;

  -- Nobody is ever offered themselves, whoever they are.
  if v_adm is not null and exists (
      select 1 from jsonb_array_elements(org_add_options(v_adm, v_adm)->'movable') m
       where (m->>'personId')::uuid = v_adm) then
    raise exception 'Migration 242: an administrator is offered themselves';
  end if;

  raise notice 'the list of people you may move now asks what org_move_person asks';
end $guard$;
