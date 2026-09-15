-- ============================================================================
-- 99_verify.sql — is the Supabase database actually in the state we think?
--
-- Run this against an EXISTING database before trusting it:
--   psql "$SUPABASE_DB_URL" -f build/supabase/99_verify.sql
--
-- It only reads. It never creates, alters or drops anything, so it is safe to
-- run against live. Every row prints expected vs actual and a verdict.
-- A FAIL is a stop: fix it before loading masters, not after.
-- ============================================================================

\pset border 2
\echo '=== Crux database verification ==================================='

with checks as (

  -- Schema ------------------------------------------------------------------
  -- Baseline is schema.sql + patch v3/v4 + migration 00-70 + rls + auth_storage
  -- (78 tables, RLS on 35). build/supabase/applied/patch-v5..v9 add the rest
  -- (upload_*, sample_row, app_setting cascade, etc.) and are expected to be
  -- applied too -- see build/supabase/applied/README.md. A number lower than
  -- 120 / 120 here means v5-v9 are genuinely missing, not stale expectations.
  select 1 as ord, 'Tables present' as check,
         '>= 120 (78 baseline + patch v5-v9)' as expected,
         count(*)::text as actual,
         count(*) >= 120 as ok
  from information_schema.tables
  where table_schema = 'public' and table_type = 'BASE TABLE'

  union all
  select 2, 'Constraints all validated', '0 unvalidated (public schema only)',
         count(*)::text || ' unvalidated',
         count(*) = 0
  from pg_constraint con
  join pg_class c on c.oid = con.conrelid
  join pg_namespace n on n.oid = c.relnamespace
  where not con.convalidated and n.nspname = 'public'

  -- Row-level security ------------------------------------------------------
  union all
  select 3, 'Tables with RLS enabled', '>= 120 (patch v7 forces it on all)',
         count(*)::text, count(*) >= 120
  from pg_tables where schemaname = 'public' and rowsecurity

  union all
  select 4, 'RLS policies exist', 'more than 0',
         count(*)::text, count(*) > 0
  from pg_policies where schemaname = 'public'

  -- The tables that carry the four defects ----------------------------------
  union all
  select 5, 'Outbox idempotency key is UNIQUE',
         'unique index present',
         coalesce(string_agg(i.indexrelid::regclass::text, ', '), 'MISSING'),
         count(*) > 0
  from pg_index i
  join pg_class c on c.oid = i.indrelid
  where c.relname = 'outbox' and i.indisunique
    and pg_get_indexdef(i.indexrelid) ilike '%idempotency%'

  union all
  select 6, 'Person identity key is employee_no, not e-mail',
         'unique on employee_no',
         case when count(*) > 0 then 'present' else 'MISSING' end,
         count(*) > 0
  from pg_index i
  join pg_class c on c.oid = i.indrelid
  where c.relname = 'person' and i.indisunique
    and pg_get_indexdef(i.indexrelid) ilike '%employee_no%'

  union all
  select 7, 'Coverage overlaps refused at write time',
         'exclusion/unique constraint OR a before-write trigger on coverage_rule',
         case when count(*) > 0 then 'present' else 'MISSING' end,
         count(*) > 0
  from (
    select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid
    where c.relname = 'coverage_rule' and con.contype in ('x', 'u')
    union all
    select 1 from pg_trigger where tgrelid = 'coverage_rule'::regclass and not tgisinternal
  ) enforcement

  -- Helpers the API and RLS both depend on ----------------------------------
  union all
  select 8, 'working_hours_after() present',
         'present',
         case when count(*) > 0 then 'present' else 'MISSING' end,
         count(*) > 0
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where p.proname = 'working_hours_after'

  union all
  select 9, 'Sign-in gate trigger present',
         'present',
         case when count(*) > 0 then 'present' else 'MISSING' end,
         count(*) > 0
  from pg_trigger where tgname ilike '%auth_gate%' and not tgisinternal

  -- Storage -----------------------------------------------------------------
  union all
  select 10, 'Storage buckets, none public',
         '4 buckets, 0 public',
         (select count(*)::text from storage.buckets) || ' buckets, '
           || (select count(*)::text from storage.buckets where public) || ' public',
         (select count(*) from storage.buckets) = 4
           and (select count(*) from storage.buckets where public) = 0
)
select ord as "#", check as "Check", expected as "Expected", actual as "Actual",
       case when ok then 'PASS' else 'FAIL' end as "Verdict"
from checks order by ord;

\echo ''
\echo '=== Holidays: the silent-wrong-TAT check =========================='
-- The old tool read an empty holiday table, so the exclusion never fired and
-- every TAT was quietly wrong. An empty result here is a go-live blocker.
select count(*) filter (where extract(year from holiday_date) = 2026) as holidays_2026,
       count(*) filter (where coalesce(is_confirmed, true) = false) as unconfirmed,
       case when count(*) filter (where extract(year from holiday_date) = 2026) = 0
            then 'BLOCKER — no 2026 holidays. Every TAT will be wrong.'
            else 'ok' end as verdict
from holiday;

\echo ''
\echo '=== Row counts against the audited source ========================='
-- Expected figures are from the 26-tab export, recorded in PROJECT_STATE.md §1.
-- Zeroes are correct before the masters are loaded; after loading they must match.
select 'branch' as table, count(*) as actual, 1413 as expected_after_load from branch
union all select 'client', count(*), 28 from client
union all select 'person', count(*), 55 from person
union all select 'escalation', count(*), 3 from escalation
union all select 'escalation_matrix_row', count(*), 3783 from escalation_matrix_row;

\echo ''
\echo '=== Queued mail — must be 0 before go-live ========================'
-- 1,892 sends went to one person for one case. If anything is queued here on a
-- fresh database, the seed loaded something it should not have.
select count(*) as queued, count(*) filter (where attempts > 0) as attempted,
       case when count(*) = 0 then 'ok' else 'STOP — investigate before deploying the worker' end as verdict
from outbox where sent_at is null;

\echo ''
\echo '=== MANUAL CHECK — cannot be scripted ============================='
\echo 'Run these two lines yourself and confirm the first is DENIED:'
\echo '    set role anon; select * from person limit 1;   -- expect: permission denied'
\echo '    reset role;'
\echo ''
\echo 'If that select returns rows, RLS is not protecting you. Stop and fix'
\echo '01_rls.sql before anyone signs in.'
