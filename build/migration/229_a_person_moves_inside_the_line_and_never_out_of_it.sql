-- =====================================================================
-- 229 · The people tree: moving somebody, and reading a team at a glance
--
-- Asked for: "sort the Org chart ... with drag and drop functionality to
-- change the reporting, with + button to add a person ... see everyones
-- target achivement progress with a progress bar on their tile."
--
-- The chart the tool already had is the CHAIR tree -- org_chart(), the
-- structure document. This is the other one: who reports to whom, which is
-- person.manager_id, and which is what every visibility rule in migrations
-- 218 to 226 is actually built on. Dragging a tile changes that column, so
-- it changes who can see whom. That makes it the most dangerous write in
-- the tool and the one that most needs its rules in the database rather
-- than in a screen.
--
-- THE FOUR RULES A MOVE OBEYS
--
--   1. A manager may move anybody INSIDE their own subtree. Re-hanging one
--      of your people under one of your other people is ordinary work.
--   2. HR and an administrator may move anybody. Running the structure is
--      their job, and somebody has to be able to move a person between two
--      managers who cannot see each other.
--   3. Nobody moves themselves, and nobody moves their own manager. Both
--      are how a person promotes themselves out of being managed.
--   4. A move that would make somebody their own ancestor is refused. The
--      new manager must not sit in the moved person's subtree, or the line
--      becomes a ring and every recursive walk over it runs until the
--      depth guard stops it.
--
-- Rule 4 is not hypothetical: perf_line already carries a twelve-pass
-- guard because a loop was reachable. This stops one being created.
-- =====================================================================

-- ------------------------------------------------ the subtree of a person
-- Needed by the cycle check and by the tree read, so it is written once.
-- Depth 0 is the person themselves.
create or replace function org_subtree(p_person uuid)
returns table(person_id uuid, depth int)
language sql
stable security definer
set search_path to 'public'
as $function$
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
$function$;

comment on function org_subtree(uuid) is
  'Everybody at or below one person in the reporting line, with depth. '
  'Depth 0 is the person. Twelve levels, for the same reason perf_line '
  'stops at twelve: a line that loops must end the walk rather than the '
  'database session.';

-- ------------------------------------------------------------- the move
create or replace function org_move_person(p_actor uuid, p_person uuid,
                                           p_new_manager uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_role role_kind; v_dept text; v_admin boolean; v_hr boolean;
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
end $function$;

comment on function org_move_person(uuid,uuid,uuid) is
  'Re-parents one person in the reporting line. A manager may move anybody '
  'inside their own subtree; HR and an administrator may move anybody. '
  'Nobody moves themselves or the person they report to, and a move that '
  'would make somebody their own ancestor is refused. Visibility is built '
  'on this column, so every move is audited.';

-- ------------------------------------------------------- the team, read
-- One call behind the tiles: who is under me, what each holds, and how far
-- through their targets they are, so a progress bar needs no second trip.
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
    'mayAdd', perf_may_set(p_actor, v_root) or v_root = p_actor,
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
  'The reporting line below one person, as tiles: chair, direct reports, '
  'and how many measures are at or past target this cycle. Every node says '
  'what this viewer may do to it, so a screen never offers an action the '
  'database will refuse.';

revoke all on function org_subtree(uuid)                  from public, anon, authenticated;
revoke all on function org_move_person(uuid,uuid,uuid)    from public, anon, authenticated;
revoke all on function org_team_tree(uuid,uuid,uuid)      from public, anon, authenticated;
