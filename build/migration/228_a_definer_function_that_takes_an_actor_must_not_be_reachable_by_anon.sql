-- =====================================================================
-- 228 · A SECURITY DEFINER function that takes the actor as an argument
--       must not be reachable with the publishable key
--
-- Found by the Supabase security advisor while verifying 226 and 227, not
-- by a test. Thirty SECURITY DEFINER functions were executable by `anon`
-- and `authenticated`.
--
-- The publishable key is public on purpose -- it is in this repository and
-- it identifies the project and grants nothing on its own. That is only
-- true while nothing reachable by `anon` grants anything. These did.
--
-- WHY THIS IS THE WHOLE VISIBILITY PROBLEM AGAIN
--
-- The pattern the work of 218-226 established is that a function decides
-- for itself whether the caller may see what they asked for:
--
--     perf_org_rollup(p_actor, p_cycle, p_person)
--       -> perf_rel(p_actor, p_person) must not be null
--
-- That gate is sound when p_actor is the signed-in person, which is what
-- the Edge Function passes. It is worth nothing when the CALLER supplies
-- p_actor, because then they simply pass the id of somebody who is allowed
-- and read whatever they like. With the key being public, "the caller" is
-- anybody on the internet.
--
-- The same shape appears on writes, which is worse than a read:
--
--     task_assign(p_actor, p_in)      -- set a task as anyone, to anyone
--     task_close(p_actor, p_task, …)  -- close somebody else's task
--     perf_seed_targets(p_actor, …)   -- re-seed every target in a cycle
--
-- And on reads that need no actor at all because they never had a gate --
-- the gate lives in the route, which anon does not go through:
--
--     task_mine(p_person, p_period)   -- anybody's tasks
--     task_evidence(p_person, …)      -- anybody's evidence
--     perf_filed_days(p_person, …)    -- anybody's filing record
--     pms_weighting_for(p_person, …)  -- one person's pay split
--
-- This is migration 222's lesson (plb_quarter listing every person to
-- whoever asked) applied to everything the advisor found, rather than to
-- the one function somebody happened to notice.
--
-- WHAT KEEPS ITS GRANTS, AND WHY
--
-- app_is_admin, app_person_id, app_subtree and app_scope_clients are named
-- inside 32, 20, 16 and 5 RLS policies respectively. Revoking them would
-- not tighten anything -- it would break every policy that calls them. It
-- is also unnecessary: each reports the CALLER'S OWN identity or scope,
-- taking no argument, so there is no other person to ask about.
--
-- schema_snapshot() keeps its grant because .github/workflows/
-- snapshot-schema.yml calls it over PostgREST with the publishable key and
-- nothing else, and it returns the shape of the database and no row of
-- anybody's data. Its helpers do not keep theirs: schema_snapshot is
-- SECURITY DEFINER, so it calls them as its owner.
--
-- Nothing here changes what the application can do. Every Edge Function
-- connects as the database owner over SUPABASE_DB_URL, not as anon.
--
-- REVOKE FROM PUBLIC, NOT ONLY FROM anon AND authenticated
--
-- The first draft of this migration said `from anon, authenticated` and
-- changed nothing at all: EXECUTE had been granted to PUBLIC, which anon
-- is a member of, so there was no direct grant to take away. The guard at
-- the foot of this file is what caught it -- it asks whether anon can
-- still call them rather than whether a revoke statement ran.
-- =====================================================================

-- ------------------------------------------------- writes, with an actor
-- The caller supplied the actor, so the gate inside was decorative.
revoke all on function perf_seed_targets(uuid, uuid)        from public, anon, authenticated;
revoke all on function task_assign(uuid, jsonb)             from public, anon, authenticated;
revoke all on function task_close(uuid, uuid, text)         from public, anon, authenticated;
revoke all on function task_cancel(uuid, uuid, text)        from public, anon, authenticated;

-- ---------------------------------------------- writes, with no actor at all
-- A scheduled job's entry point is not a public endpoint.
revoke all on function business_import_run()                from public, anon, authenticated;
revoke all on function crux_task_tick()                     from public, anon, authenticated;
revoke all on function task_sweep()                         from public, anon, authenticated;
revoke all on function branch_place_from_address()          from public, anon, authenticated;
revoke all on function access_policy_questions()            from public, anon, authenticated;

-- ------------------------------------------- reads about a named person
-- Each of these answers "tell me about this person" and none of them asks
-- who is doing the asking.
revoke all on function perf_org_rollup(uuid, uuid, uuid)    from public, anon, authenticated;
revoke all on function perf_filed_days(uuid, integer, date) from public, anon, authenticated;
revoke all on function task_mine(uuid, text)                from public, anon, authenticated;
revoke all on function task_evidence(uuid, text)            from public, anon, authenticated;
revoke all on function pms_weighting_for(uuid, date)        from public, anon, authenticated;
revoke all on function access_level_of(uuid)                from public, anon, authenticated;
revoke all on function access_may_open(uuid, text)          from public, anon, authenticated;
revoke all on function access_screens(uuid)                 from public, anon, authenticated;
revoke all on function kpi_registry_completeness()          from public, anon, authenticated;

-- ------------------------------------------------ the snapshot's helpers
-- schema_snapshot() itself keeps its grant; it is SECURITY DEFINER and so
-- reaches these as its owner without anybody else being able to.
revoke all on function schema_snapshot_cron()               from public, anon, authenticated;
revoke all on function schema_snapshot_funcs(integer, integer) from public, anon, authenticated;
revoke all on function schema_snapshot_grants()             from public, anon, authenticated;
revoke all on function schema_snapshot_part(text)           from public, anon, authenticated;
revoke all on function schema_snapshot_part2(text)          from public, anon, authenticated;
revoke all on function schema_snapshot_policy()             from public, anon, authenticated;
revoke all on function schema_snapshot_stg()                from public, anon, authenticated;

-- ------------------------------------------------ two views that bypass RLS
-- Flagged ERROR by the advisor. Both are diagnostics for an administrator
-- -- branches with no place, chairs with no measures -- and both read
-- through their owner's rights, so anyone able to select them reads past
-- every policy on the tables beneath.
revoke all on branch_without_place                          from public, anon, authenticated;
revoke all on kpi_registry_gap                              from public, anon, authenticated;

-- ------------------------------------------------------------ the guard
-- The advisor found this; no test would have. So the rule becomes a test:
-- any SECURITY DEFINER function that takes a uuid first argument and is
-- reachable by anon is the bypass shape, and there must be none.
do $$
declare v_bad text;
begin
  select string_agg(p.proname, ', ' order by p.proname) into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prosecdef
     and has_function_privilege('anon', p.oid, 'execute')
     and p.pronargs > 0
     and (select t.typname from pg_type t where t.oid = p.proargtypes[0]) = 'uuid';
  if v_bad is not null then
    raise exception
      'These take an actor or a person and anybody may call them: %', v_bad;
  end if;
end $$;
