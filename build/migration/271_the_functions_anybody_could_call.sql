-- The functions, the table and the view anybody holding the public key
-- could use
--
-- Found while building 270, by asking the database rather than the files:
-- 27 SECURITY DEFINER functions in public could be executed by anon -- the
-- role the publishable key carries, which is in the source of every page.
-- A SECURITY DEFINER function runs as its owner, so whatever it does, anon
-- could do through /rest/v1/rpc. And most of these take the actor as an
-- argument: perf_cycle_extend(p_actor, ...), org_person_set(p_actor, ...),
-- partner_file_set(p_actor, ...), person_escalation_raise(p_actor, ...).
-- Pass the administrator's id and you are the administrator. Among them was
-- this session's own perf_window_sweep (269), which raises escalations and
-- queues mail for any date it is given.
--
-- How they came to be open: the project's default privileges grant EXECUTE
-- on every new function in public to anon and authenticated, and PostgreSQL
-- grants it to PUBLIC on top. 333 functions have it revoked by hand, as 240
-- did for perf_assign_edit; these were the ones written since without the
-- revoke. A rule that depends on remembering is a rule that is forgotten.
--
-- Nothing legitimate reaches them that way. Measured before this file:
--   * the page sends the publishable key only to the edge functions
--     (functions/v1); it never calls /rest/v1 at all;
--   * every edge function calls the database with the service-role key or
--     the database owner's connection, and both keep their access;
--   * no row-level-security policy and no view calls any of the 22.
--
-- Left open, on purpose, and named in the proof below:
--   schema_snapshot  read by .github/workflows/snapshot-schema.yml with the
--                    publishable key; it returns the schema, never a row;
--   app_is_admin, app_person_id, app_scope_clients, app_subtree
--                    the predicates the row-level-security policies call.
--                    A policy runs as the caller, so the caller must be able
--                    to execute them; they answer about the caller, not
--                    about anybody they are told to be.
--
-- The same question asked of tables and views found two more:
--   window_miss    269's record of missed windows. A new table gets anon's
--                  full rights by default and row-level security is off
--                  until somebody turns it on, which 269 did not: anybody
--                  could read who missed what, or write a row that tells
--                  the sweep a window was already escalated.
--   plb_goal_kpi   the view over every goal sheet's KPIs. A view runs as its
--                  owner unless it is told otherwise, and the owner passes
--                  row-level security -- so the policies on plb_goal_kpi_all
--                  stopped nothing, and the view is simple enough to be
--                  written through. Every target and actual, readable and
--                  changeable with the public key.
-- (migration_gate also answers to anon, and is safe: it runs as the caller.)
-- Closed the general way rather than by name: every table in public with
-- row-level security off, and every view that runs as its owner, loses
-- anon's and authenticated's rights. The services keep theirs.
--
-- And the defaults are turned round, so the next function, table or view is
-- closed until somebody grants it: whatever has to be reachable from outside
-- is the exception, and is granted by name.
do $do$
declare r record; n int := 0;
begin
  for r in
    select p.oid::regprocedure as fn
      from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'public' and p.prosecdef and p.prokind = 'f'
       and p.proname in (
         'org_assign_options','org_people_table','org_person_set','org_person_set_many',
         'partner_file_get','partner_file_may_set','partner_file_set',
         'perf_assign_remove','perf_cycle_extend','perf_direction_of','perf_kpis_set',
         'perf_mapping','perf_window_sweep',
         'person_escalation_act','person_escalation_list','person_escalation_raise',
         'person_escalation_route',
         'plb_kpi_months','plb_kpi_part_set','plb_runs_scheme',
         'plb_sheet_measure_options','plb_sheet_measures_set')
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.fn);
    execute format('grant execute on function %s to service_role', r.fn);
    n := n + 1;
  end loop;
  raise notice 'Migration 271: % function(s) closed to the public key.', n;
end
$do$;

do $do$
declare r record; n_t int := 0; n_v int := 0;
begin
  for r in
    select c.oid::regclass as rel, c.relkind
      from pg_class c join pg_namespace s on s.oid = c.relnamespace
     where s.nspname = 'public'
       and (   (c.relkind in ('r','p') and not c.relrowsecurity)
            or (c.relkind in ('v','m')
                and not coalesce(c.reloptions @> array['security_invoker=true'], false)))
       and (   has_table_privilege('anon', c.oid, 'select,insert,update,truncate')
            or has_table_privilege('authenticated', c.oid, 'select,insert,update,truncate'))
  loop
    execute format('revoke all on %s from anon, authenticated', r.rel);
    if r.relkind in ('r','p') then n_t := n_t + 1; else n_v := n_v + 1; end if;
  end loop;
  -- and 269's table gets the row-level security it should have had
  alter table public.window_miss enable row level security;
  -- and the view reads as the person asking, whoever is given it later
  alter view public.plb_goal_kpi set (security_invoker = true);
  raise notice 'Migration 271: % table(s) and % view(s) closed to the public key.', n_t, n_v;
end
$do$;

-- The next one is closed by default. Per-schema entries can only ADD to the
-- global default, which is where PUBLIC's EXECUTE comes from, so PUBLIC is
-- revoked globally for functions the owner creates, and anon and
-- authenticated in public. service_role keeps its grant from the per-schema
-- entry the project already has.
alter default privileges for role postgres revoke execute on functions from public;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;

-- --------------------------------------------------------------- the proof
do $guard$
declare v_open text; v_cut text;
begin
  select string_agg(p.proname, ', ' order by p.proname) into v_open
    from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.prosecdef and p.prokind = 'f'
     and (has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('authenticated', p.oid, 'execute'))
     and p.proname not in ('schema_snapshot',
                           'app_is_admin','app_person_id','app_scope_clients','app_subtree');
  if v_open is not null then
    raise exception 'Migration 271: still callable with the public key: %', v_open;
  end if;

  select string_agg(p.proname, ', ' order by p.proname) into v_cut
    from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.prosecdef and p.prokind = 'f'
     and not has_function_privilege('service_role', p.oid, 'execute')
     and p.proname in ('perf_window_sweep','perf_mapping','org_person_set',
                       'person_escalation_raise','plb_sheet_measures_set');
  if v_cut is not null then
    raise exception 'Migration 271: the services lost a function they call: %', v_cut;
  end if;
  select string_agg(c.relname, ', ' order by c.relname) into v_open
    from pg_class c join pg_namespace s on s.oid = c.relnamespace
   where s.nspname = 'public'
     and (   (c.relkind in ('r','p') and not c.relrowsecurity)
          or (c.relkind in ('v','m')
              and not coalesce(c.reloptions @> array['security_invoker=true'], false)))
     and (   has_table_privilege('anon', c.oid, 'select,insert,update,truncate')
          or has_table_privilege('authenticated', c.oid, 'select,insert,update,truncate'));
  if v_open is not null then
    raise exception 'Migration 271: still open to the public key with nothing guarding it: %', v_open;
  end if;
  if not has_table_privilege('service_role', 'public.window_miss', 'select,insert')
     or not has_table_privilege('service_role', 'public.plb_goal_kpi', 'select') then
    raise exception 'Migration 271: the services lost a table they use.';
  end if;
  if not has_function_privilege('anon', 'public.schema_snapshot()', 'execute') then
    raise exception 'Migration 271: the schema snapshot workflow can no longer read the schema.';
  end if;
  raise notice 'Migration 271: no privileged function answers to the public key but the five named, and no unguarded table or view.';
end
$guard$;
