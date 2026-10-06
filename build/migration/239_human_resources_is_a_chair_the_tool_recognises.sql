-- Human Resources is a chair the tool recognises (239)
--
-- The complaint was "team member assignments is still not working for Admin
-- or HR". Two different causes wearing one symptom.
--
-- HR. perf_rel answers 'self', 'admin', 'manage' or 'watch'. An
-- administrator is named; HR is not. So P P Valsan, who runs Human
-- Resources, gets 'manage' over the one person who reports to him and
-- 'watch' over the other hundred -- and perf_may_set, which is the gate on
-- setting a KPI, a target, or pulling a quarter's actuals, is false for all
-- hundred. kpi_subtree_people has the same hole: it names ADMIN and stops.
--
-- That is not a small inconvenience. HR is the function that seats a joiner,
-- opens a cycle, and repairs an assignment when the manager who set it has
-- left. A tool that will not let HR touch anybody's measures is a tool that
-- requires an administrator for every ordinary personnel act.
--
-- ADMIN with direct reports. perf_rel already returns 'admin' for every
-- person, so the database was never the limit here. The limit is in the
-- route (/plb/perf/team), which falls back to "everybody" only when the
-- administrator has NO reports. Shantanu Suravase has nine, so he saw nine
-- and nothing else. That is fixed in the edge function, not here, and is
-- noted so the two halves of one answer are findable from each other.
--
-- WHAT THIS DOES NOT DO. It does not give HR a wider VIEW. perf_may_see is
-- `perf_rel is not null`, which was already true for HR over everybody
-- through 'watch', and stays exactly as true. The change is to SETTING, and
-- every set already writes an audit_entry naming the actor -- so "HR changed
-- this, not the manager" remains answerable afterwards.
--
-- The new relation is its own word, 'hr', rather than folding HR into
-- 'admin', so an audit entry can still say which of the two acted. Six
-- places in the database ask whether a relation may set -- perf_may_set and
-- five that write the list out by hand -- and all six are widened below by
-- a sweep over the text rather than by a list of names. The seventh reader
-- is the screen, which is in the application and changes alongside it.

-- -------------------------------------------------------------- perf_rel
-- Order matters and is unchanged: self first, so nobody is their own
-- manager by virtue of a role; then administrator; then HR; then the
-- reporting line.
create or replace function perf_rel(p_actor uuid, p_person uuid)
returns text language sql stable security definer set search_path to 'public'
as $function$
  select case
    when p_actor is null or p_person is null then null
    when p_actor = p_person then 'self'
    when exists (select 1 from person a
                  where a.id = p_actor and a.app_role = 'ADMIN'
                    and a.employment_status = 'ACTIVE' and a.superseded_by is null) then 'admin'
    when exists (select 1 from person a
                  where a.id = p_actor
                    and coalesce(a.department,'') = 'Human Resources'
                    and a.employment_status = 'ACTIVE' and a.superseded_by is null) then 'hr'
    else (select case when l.depth = 1 then 'manage' else 'watch' end
            from perf_line(p_actor) l where l.person_id = p_person)
  end
$function$;

-- ---------------------------------------------------------- perf_may_set
create or replace function perf_may_set(p_actor uuid, p_person uuid)
returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(perf_rel(p_actor, p_person) in ('manage','admin','hr'), false)
$function$;

-- --------------------------------------------------- kpi_subtree_people
-- The same sentence as perf_rel, said about a set rather than a pair.
create or replace function kpi_subtree_people(p_actor uuid)
returns table(person_id uuid) language sql stable security definer set search_path to 'public'
as $function$
  select p.id
    from person p
   where p.employment_status = 'ACTIVE'
     and p.superseded_by is null
     and coalesce(p.employee_type, 'EMPLOYEE') <> 'CLIENT_CONTACT'
     and p.id <> p_actor
     and (exists (select 1 from person a
                   where a.id = p_actor
                     and (a.app_role = 'ADMIN'
                       or coalesce(a.department,'') = 'Human Resources')
                     and a.employment_status = 'ACTIVE'
                     and a.superseded_by is null)
          or p.id in (select l.person_id from perf_line(p_actor) l
                       where l.depth = 1))
$function$;

-- ------------------------------------------- every other place it is said
-- The relation list is written out by hand in several functions besides
-- perf_may_set, each deciding whether somebody may SET rather than read:
-- plb_quarter's maySet column, plb_actual_from_perf's refusal,
-- plb_sheet_for's and plb_month_suggest's maySet, and perf_tree_for's --
-- which reads ('self','manage','admin') because a person files their own
-- figures even though they do not set their own target.
--
-- A first draft of this file named two of those five. It named two because
-- a survey of perf_rel's callers had shown the text next to the first
-- perf_rel( in each body, and in the other three the list is written
-- somewhere else entirely. So this does not name any of them: it rewrites
-- every function whose source carries the list, which is the same set the
-- guard at the foot refuses to let through.
--
-- The pattern is the tail of the list, "'manage','admin')", not the whole
-- expression -- so the leading 'self' in perf_tree_for survives untouched
-- and nobody gains the right to set their own by a careless replace.
--
-- Substituting into live source, rather than retyping the function, is also
-- deliberate. An earlier draft retyped plb_actual_from_perf from memory and
-- silently dropped its frozen-data check and its handling of a measure
-- nothing was filed against. A substitution changes the characters it names
-- and leaves every other character alone.
do $relist$
declare
  r record;
  v_src text;
  v_n int := 0;
  v_old constant text := $q$'manage','admin')$q$;
  v_new constant text := $q$'manage','admin','hr')$q$;
begin
  for r in
    select p.proname,
           pg_get_function_identity_arguments(p.oid) as args,
           pg_get_function_result(p.oid) as ret,
           p.prosrc, p.provolatile, p.prosecdef, l.lanname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      join pg_language l on l.oid = p.prolang
     where n.nspname = 'public'
       and l.lanname in ('sql','plpgsql')
       and position(v_old in p.prosrc) > 0
  loop
    -- The language is carried through rather than assumed: plb_quarter is
    -- plain SQL and plb_actual_from_perf is plpgsql, and a body put back
    -- under the wrong one is a syntax error at best.
    -- SECURITY DEFINER is carried through, never asserted. Writing it in
    -- unconditionally would hand the definer's rights to any function in
    -- the set that did not have them, which is a privilege change wearing
    -- the clothes of a text substitution.
    v_src := replace(r.prosrc, v_old, v_new);
    execute format(
      'create or replace function %I(%s) returns %s language %s %s %s '
      'set search_path to ''public'' as %L',
      r.proname, r.args, r.ret, r.lanname,
      case r.provolatile when 's' then 'stable'
                         when 'i' then 'immutable'
                         else '' end,
      case when r.prosecdef then 'security definer' else 'security invoker' end,
      v_src);
    v_n := v_n + 1;
    raise notice '  relation list widened in %(%)', r.proname, r.args;
  end loop;

  -- Five carry it today. A sixth appearing later is not a failure -- the
  -- sweep is on the text, not on a list of names, so it would be caught
  -- too. Zero means either this has already run or the functions have been
  -- rewritten; the first is fine and the second needs a person.
  if v_n = 0 then
    if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and position(v_new in p.prosrc) > 0) then
      raise notice 'relation list already carries hr; nothing to widen';
    else
      raise exception 'Migration 239: no function carries the relation list, '
                      'and none carries the widened one either. Those '
                      'functions have been rewritten and must be re-read.';
    end if;
  else
    raise notice 'relation list widened in % function(s)', v_n;
  end if;
end $relist$;

-- The refusal wording on plb_actual_from_perf still names only two of the
-- three. Said again now that HR is one of them.
do $wording$
declare v_src text; v_old text; v_new text;
begin
  -- Doubled quotes, twice over: the function body held in prosrc already
  -- escapes its own apostrophes, and this file escapes those again. No
  -- apostrophe is introduced on the HR clause, so there is nothing here to
  -- get wrong a third time.
  v_old := 'is the reporting manager''''s, or ';
  v_new := 'is the reporting manager''''s, or Human Resources, or ';
  select prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'plb_actual_from_perf';
  if position(v_old in v_src) > 0 then
    execute 'create or replace function plb_actual_from_perf(p_actor uuid, p_sheet uuid) '
         || 'returns jsonb language plpgsql security definer '
         || 'set search_path to ''public'' as '
         || quote_literal(replace(v_src, v_old, v_new));
  else
    raise notice 'Migration 239: the refusal wording on plb_actual_from_perf '
                 'has changed; left as it is rather than guessed at.';
  end if;
end $wording$;

-- ------------------------------------------------------------- the guard
do $guard$
declare
  v_hr uuid; v_admin uuid; v_other uuid; n int;
begin
  -- app_role is an enum, so it is compared with IS DISTINCT FROM rather
  -- than coalesced to an empty string, which is not a member of the type.
  select id into v_hr from person
   where coalesce(department,'') = 'Human Resources'
     and employment_status = 'ACTIVE' and superseded_by is null
     and app_role is distinct from 'ADMIN'
   limit 1;
  select id into v_admin from person
   where app_role = 'ADMIN' and employment_status = 'ACTIVE' and superseded_by is null
   limit 1;
  select id into v_other from person
   where employment_status = 'ACTIVE' and superseded_by is null
     and coalesce(employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
     and coalesce(department,'') <> 'Human Resources'
     and app_role is distinct from 'ADMIN'
   limit 1;

  if v_hr is null or v_admin is null or v_other is null then
    raise notice 'Migration 239: no HR / admin / ordinary person to test against; '
                 'the function bodies are in place but unproven on data.';
  else
    -- HR may now set for somebody who does not report to them.
    if not perf_may_set(v_hr, v_other) then
      raise exception 'Migration 239: HR still may not set for an ordinary person';
    end if;
    -- And still may not set their own.
    if perf_may_set(v_hr, v_hr) then
      raise exception 'Migration 239: HR may set their own measures. '
                      'Nobody sets their own, including HR.';
    end if;
    if perf_may_set(v_admin, v_admin) then
      raise exception 'Migration 239: an administrator may set their own measures';
    end if;
    -- An ordinary person gained nothing. Said as the invariant rather than
    -- as an example: the set they may set for is exactly their own depth-1
    -- line, no wider and no narrower.
    --
    -- A first draft of this asserted instead that an ordinary person may
    -- not set for an administrator, and it failed on the live database --
    -- correctly. Operations Alert holds ADMIN and reports to Manish Shukla,
    -- so Manish setting for them is the reporting line working, not a
    -- leak. An example is not an invariant.
    select count(*) into n
      from person p
     where p.employment_status = 'ACTIVE' and p.superseded_by is null
       and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
       and perf_may_set(v_other, p.id)
         <> exists (select 1 from perf_line(v_other) l
                     where l.person_id = p.id and l.depth = 1);
    if n > 0 then
      raise exception 'Migration 239: for an ordinary person, may-set and the '
                      'depth-1 line disagree about % person/people', n;
    end if;
    if perf_rel(v_hr, v_other) <> 'hr' then
      raise exception 'Migration 239: perf_rel(hr, other) is %, expected hr',
        perf_rel(v_hr, v_other);
    end if;
    -- The subtree followed. Counted against everybody else rather than
    -- against a number, so this says the same true thing on the live
    -- database and on a test cluster with five rows in it.
    select count(*) into n
      from person p
     where p.employment_status = 'ACTIVE' and p.superseded_by is null
       and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
       and p.id <> v_hr
       and not exists (select 1 from kpi_subtree_people(v_hr) s
                        where s.person_id = p.id);
    if n > 0 then
      raise exception 'Migration 239: % active person/people are still outside '
                      'HR''s KPI subtree', n;
    end if;
    if exists (select 1 from kpi_subtree_people(v_hr) s where s.person_id = v_hr) then
      raise exception 'Migration 239: HR is inside their own subtree';
    end if;
  end if;

  -- Every place that asks whether a relation may set now knows the word.
  -- If a sixth appears later and does not, this names it.
  -- The closing bracket is load-bearing: the rewritten tests read
  -- ('manage','admin','hr'), which still CONTAINS 'manage','admin' and would
  -- match a looser pattern forever.
  select count(*) into n from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and p.prosrc like '%''manage'',''admin'')%';
  if n > 0 then
    raise exception 'Migration 239: % function(s) still test for manage/admin '
                    'without hr. Find them with: select proname from pg_proc '
                    'where prosrc like ''%%''''manage'''',''''admin'''')%%'';', n;
  end if;

  -- Nobody's VIEW widened: perf_may_see is unchanged and was already true
  -- for HR over everybody through 'watch'.
  if (select prosrc from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
       where ns.nspname = 'public' and p.proname = 'perf_may_see')
     not like '%is not null%' then
    raise exception 'Migration 239: perf_may_see is no longer a null test';
  end if;

  raise notice 'hr may set and may not set its own; admin unchanged; '
               'ordinary people unchanged; no manage/admin test left behind';
end $guard$;
