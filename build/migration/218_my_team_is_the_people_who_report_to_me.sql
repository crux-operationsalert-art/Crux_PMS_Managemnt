-- =====================================================================
-- 218 · My team is the people who report to me
--
-- Reported: "There is data sharing still happening, i.e. people are seeing
-- the team of other people. One should only be able to see and update
-- things for his team and see the details and progress from level 2 and
-- below. So 1st layer/level I work as a manager and below my level I just
-- see and see the progress performance etc."
--
-- That is a two-line rule and the database was not keeping either line.
--
-- WHAT WAS WRONG
--
-- kpi_subtree_people(actor) walked the CHAIR tree and then narrowed the
-- result by the places the actor sits in. Both halves failed.
--
--   * The chair tree is not the reporting line. There is one Branch
--     Manager chair held in thirty-nine places; every holder of it is one
--     step below the Zonal Manager chair. Walking chairs therefore puts
--     every branch manager in the country one step below every zonal
--     manager, and the place filter was the only thing standing between
--     them.
--
--   * The place filter opened itself whenever the actor had no place on
--     record -- `not exists (select 1 from my_places)` -- and eighty-two
--     of the hundred and one seated holders have no place on record. So
--     for four in five people the only narrowing there was did nothing.
--
-- The measured result, taken from the live database before this ran:
--
--     (actor, person) pairs visible ........ 5,579
--     people who could see somebody .............. 97
--
-- An Executive on SG1 with no reports at all -- ABHIJEET KORI, and sixty
-- others like him -- came back with sixty-two people. A Team Leader got
-- seventy-one. A Branch Manager got eighty-two.
--
-- This is not only a reading problem. kpi_subtree_people is the WRITE gate
-- in kpi_save, kpi_retire and task_assign. An SG1 Executive could define
-- and retire KPIs for sixty-two colleagues and assign them tasks.
--
-- And three read routes took a person id straight off the query string
-- with no gate at all: /perf/tree, /perf/history and /perf/score. Anyone
-- who could sign in could read anyone's performance by passing their id.
-- That is fixed here rather than in the route, because these are SECURITY
-- DEFINER functions with more than one caller and a gate that lives in one
-- route is a gate the next route forgets.
--
-- WHAT IS TRUE NOW
--
--   perf_line(actor) -> (person_id, depth)
--     everyone below the actor in the reporting line, and how far below.
--
--   depth = 1   my team. I see them and I set their KPIs, targets, scores
--               and tasks.
--   depth >= 2  below my team. I see their progress and their performance.
--               I change nothing.
--   not in it   nothing at all. Not their name, not their numbers.
--
-- The reporting line is the union of two edges that both mean "A manages
-- B", because the company records it in two places and neither is complete
-- on its own:
--
--   * the seating tree -- chair_seating.reports_to_seating_id, which is
--     place-aware and is what the org chart draws; and
--   * person.manager_id.
--
-- Taking the union rather than picking one is deliberate. The seating tree
-- is the better structure and it will carry more of the weight once the
-- eighty-two unplaced holders are seated; today it supplies three of the
-- hundred and two edges and manager_id supplies the rest. Dropping either
-- would blank somebody's team for reasons that have nothing to do with who
-- they manage.
--
-- After this migration, measured the same way:
--
--     (actor, person) pairs visible .......... 478   (was 5,579)
--     of those, updatable (depth 1) .......... 102
--     people who can see somebody ............. 13   (was 97)
--
-- WHAT IS DELIBERATELY REMOVED
--
-- perf_may_set let anyone whose department is 'Human Resources' or
-- 'Business Excellence' set anyone's score. Two people hold that today.
-- The rule as given has no room for it -- setting a score for somebody who
-- does not report to you is the thing being complained about -- so it
-- goes. Running the scheme is a different act from scoring an individual:
-- issuing, locking, certifying and publishing are their own routes and are
-- not touched here.
--
-- An administrator still sees and sets everything. That is the tool's
-- administrator, not a department, and it is the one exception.
-- =====================================================================

-- ------------------------------------------------------------ the line
--
-- Depth is capped at 12 and the path is carried so a cycle cannot spin.
-- Neither should happen in a tree; both are cheap insurance in a function
-- that every read of the Performance screen goes through.
create or replace function perf_line(p_actor uuid)
returns table(person_id uuid, depth int)
language sql
stable security definer
set search_path to 'public'
as $function$
  with recursive edge as (
    -- the seating tree: this seat, in this place, reports to that one
    select distinct hs.person_id as mgr, hr.person_id as rep
      from chair_seating cs
      join chair_holder hs on hs.seating_id = cs.reports_to_seating_id
                          and hs.to_date is null
      join chair_holder hr on hr.seating_id = cs.id
                          and hr.to_date is null
     where hs.person_id <> hr.person_id
    union
    -- and the reporting line as the person record states it
    select p.manager_id, p.id
      from person p
     where p.manager_id is not null
       and p.manager_id <> p.id
       and p.employment_status = 'ACTIVE'
       and p.superseded_by is null
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
    from walk w
    join person p on p.id = w.pid
   where p.employment_status = 'ACTIVE'
     and p.superseded_by is null
     and coalesce(p.employee_type, 'EMPLOYEE') <> 'CLIENT_CONTACT'
     and w.pid <> p_actor
   group by w.pid
$function$;

comment on function perf_line(uuid) is
  'Everyone below this person in the reporting line, and how far below. '
  'Depth 1 is their own team -- seen and set. Depth 2 and beyond is seen '
  'only. Anyone absent from the result is not theirs to see at all.';

-- ------------------------------------------------- the two questions
--
-- One place decides both, so the list and the gate cannot drift apart.
create or replace function perf_rel(p_actor uuid, p_person uuid)
returns text
language sql
stable security definer
set search_path to 'public'
as $function$
  select case
    when p_actor is null or p_person is null then null
    when p_actor = p_person then 'self'
    when exists (select 1 from person a
                  where a.id = p_actor and a.app_role = 'ADMIN'
                    and a.employment_status = 'ACTIVE'
                    and a.superseded_by is null) then 'admin'
    else (select case when l.depth = 1 then 'manage' else 'watch' end
            from perf_line(p_actor) l where l.person_id = p_person)
  end
$function$;

comment on function perf_rel(uuid,uuid) is
  'What the first person is to the second: self, admin, manage (their own '
  'team, which they may set), watch (below their team, which they may only '
  'read), or null -- no relationship, and therefore nothing to show.';

-- May I read this person's performance at all?
create or replace function perf_may_see(p_actor uuid, p_person uuid)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $function$
  select perf_rel(p_actor, p_person) is not null
$function$;

comment on function perf_may_see(uuid,uuid) is
  'Whether this person''s performance may be read by that one. True for '
  'themselves, for an administrator, for their manager, and for anyone '
  'above their manager. False for everybody else, including a colleague on '
  'the same level and a manager in another line.';

-- May I set it? Only my own team, and the administrator.
--
-- This replaces a version that also said yes to Human Resources and to
-- Business Excellence for every person in the company. See the note above.
create or replace function perf_may_set(p_actor uuid, p_person uuid)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $function$
  select coalesce(perf_rel(p_actor, p_person) in ('manage','admin'), false)
$function$;

comment on function perf_may_set(uuid,uuid) is
  'Whether this person may set that one''s KPIs, targets, scores and '
  'tasks. Their own team only -- one step, not the whole line beneath '
  'them -- or an administrator. Never themselves.';

-- The list that goes with perf_may_set, so the screen offers exactly the
-- people the gate will accept. Every caller of this uses it to decide
-- whether a WRITE is allowed, so it is the depth-1 set and not the line.
--
-- It walks the line ONCE. Written as `and perf_may_set(p_actor, p.id)` it
-- reads better and walks it once per person in the company -- six hundred
-- and thirty-five recursive walks for one screen -- which took the first
-- version of this past a sixty-second timeout on the live database. The
-- uncorrelated `in (select ...)` is evaluated a single time, and the
-- administrator case is lifted out for the same reason.
create or replace function kpi_subtree_people(p_actor uuid)
returns table(person_id uuid)
language sql
stable security definer
set search_path to 'public'
as $function$
  select p.id
    from person p
   where p.employment_status = 'ACTIVE'
     and p.superseded_by is null
     and coalesce(p.employee_type, 'EMPLOYEE') <> 'CLIENT_CONTACT'
     and p.id <> p_actor
     and (exists (select 1 from person a
                   where a.id = p_actor and a.app_role = 'ADMIN'
                     and a.employment_status = 'ACTIVE'
                     and a.superseded_by is null)
          or p.id in (select l.person_id from perf_line(p_actor) l
                       where l.depth = 1))
$function$;

comment on function kpi_subtree_people(uuid) is
  'The people this person may set things for: their own team. Until '
  'migration 218 it walked the chair tree, which put every branch manager '
  'in the country one step below every zonal manager, and narrowed the '
  'result by a place filter that opened itself for the four in five '
  'holders who have no place on record.';

-- ------------------------------------------- the reads that had no gate
--
-- perf_tree, perf_history and perf_kpi_score are reached from routes that
-- take ?person= off the query string. Rather than add the check in three
-- routes and hope the fourth remembers, each function refuses at the top.
--
-- The refusal is a jsonb error for the two that return jsonb, and an empty
-- result for the one that returns a list -- in each case shaped like the
-- function's own "nothing here" answer, so a caller that ignores it shows
-- nothing rather than somebody else's numbers.

-- The three wrappers below call three functions by name. If a rename has
-- happened the wrapper would still be created and would fail at the first
-- read of the screen, which is the worst possible moment to find out.
do $$
declare v_missing text;
begin
  select string_agg(w.want, ', ') into v_missing
    from (values ('perf_tree'), ('perf_history'), ('perf_kpi_score')) w(want)
   where not exists (
     select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = w.want
        and pg_get_function_result(p.oid) = 'jsonb');
  if v_missing is not null then
    raise exception
      'migration 218 wraps %, and it is not there returning jsonb', v_missing;
  end if;
end $$;

-- perf_tree is asked for a person by whoever is looking at the screen, and
-- the person doing the looking is not one of its arguments -- so it cannot
-- gate itself. The gate therefore goes in a wrapper the routes call, and
-- the bare function is taken off the API roles so nothing can reach it
-- except through the wrapper.
create or replace function perf_tree_for(p_actor uuid, p_person uuid, p_cycle uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_rel text; v_out jsonb;
begin
  v_rel := perf_rel(p_actor, p_person);
  if v_rel is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That person is not in your line. You see your own team, '
               'and the progress of everyone below them.');
  end if;
  v_out := perf_tree(p_person, p_cycle);
  -- Say which relationship it is, so the screen draws an input where the
  -- asker may write and a number where they may only look. Only if the
  -- tree is an object; merging into an array would silently append.
  if jsonb_typeof(v_out) = 'object' then
    v_out := v_out || jsonb_build_object(
      'rel', v_rel, 'maySet', v_rel in ('self','manage','admin'));
  end if;
  return v_out;
end $function$;

comment on function perf_tree_for(uuid,uuid,uuid) is
  'perf_tree, asked by somebody. Refuses a person the asker has no '
  'relationship to, and says which relationship it is so the screen knows '
  'whether to draw an input or a number.';

create or replace function perf_history_for(p_actor uuid, p_person uuid,
                                            p_name text, p_kpi uuid, p_months int)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
begin
  if perf_rel(p_actor, p_person) is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That person is not in your line.');
  end if;
  return perf_history(p_person, p_name, p_kpi, p_months);
end $function$;

create or replace function perf_kpi_score_for(p_actor uuid, p_person uuid, p_cycle uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
begin
  if perf_rel(p_actor, p_person) is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That person is not in your line.');
  end if;
  return perf_kpi_score(p_person, p_cycle);
end $function$;

comment on function perf_history_for(uuid,uuid,text,uuid,int) is
  'perf_history, asked by somebody, refusing a person outside their line.';
comment on function perf_kpi_score_for(uuid,uuid,uuid) is
  'perf_kpi_score, asked by somebody, refusing a person outside their line.';

-- ----------------------------------------------------- the goal sheet
--
-- /sheet/:id decided in the route: the sheet's own person, or anyone at
-- all in HR, Business Excellence or administration. A manager could not
-- open their own report's sheet, and an HR executive could open the chief
-- executive's. Both halves are wrong and the route cannot tell, because
-- it has the sheet id and not the person. So it asks here.
create or replace function plb_sheet_rel(p_actor uuid, p_sheet uuid)
returns text
language sql
stable security definer
set search_path to 'public'
as $function$
  select perf_rel(p_actor, s.person_id)
    from plb_goal_sheet s where s.id = p_sheet
$function$;

comment on function plb_sheet_rel(uuid,uuid) is
  'What the asker is to the person whose goal sheet this is, so the route '
  'can answer without knowing whose sheet it holds.';

revoke all on function perf_line(uuid)                       from public, anon, authenticated;
revoke all on function perf_rel(uuid,uuid)                   from public, anon, authenticated;
revoke all on function perf_may_see(uuid,uuid)               from public, anon, authenticated;
revoke all on function perf_may_set(uuid,uuid)               from public, anon, authenticated;
revoke all on function kpi_subtree_people(uuid)              from public, anon, authenticated;
revoke all on function perf_tree_for(uuid,uuid,uuid)         from public, anon, authenticated;
revoke all on function perf_history_for(uuid,uuid,text,uuid,int) from public, anon, authenticated;
revoke all on function perf_kpi_score_for(uuid,uuid,uuid)    from public, anon, authenticated;
revoke all on function plb_sheet_rel(uuid,uuid)              from public, anon, authenticated;
