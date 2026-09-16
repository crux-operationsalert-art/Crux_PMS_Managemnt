-- =====================================================================
-- 95 · THE CUT-OVER CHECKS — attempted, not asserted.
--
-- IMPLEMENTATION.md section 7 asks for four verifications before cut-over.
-- Three of them can be run against the database and are run here; each writes
-- what actually happened, with the database's own error text, into
-- cutover_check, so the evidence outlives the session that produced it.
--
--   2 · constraint proof   W-01..W-04, the four known-bad writes
--   3 · storm regression   S-01, 100 identical attempts must make one row
--   4 · traceability       T-01/T-02, migrated rows walk back to the sheet
--
--   1 · recipient reconciliation needs stg.email_log loaded and is the one
--       check that cannot run here.
--
-- Every probe cleans up after itself, and a probe that unexpectedly SUCCEEDS
-- is a failure of the check whose row is deleted immediately.
-- =====================================================================
create table if not exists cutover_check (
  id          bigserial primary key,
  at          timestamptz not null default now(),
  check_name  text not null,
  expectation text not null,
  outcome     text not null,
  detail      text,
  result      text not null check (result in ('PASS','FAIL'))
);
comment on table cutover_check is
  'Evidence for the pre-cut-over checks: each known-bad write was attempted and the database refused it. A row here is what happened, not what was believed.';

-- The body of the checks is long and is applied as two migrations in the
-- ledger: crux_cutover_constraint_proof and crux_cutover_traceability_check_v2.
-- Re-running them is safe — each deletes its own previous rows first.
--
-- Result at the time of writing, 16 Sep 2026: seven checks, all PASS.
--
--   W-01 misspelt-domain person      refused   person_work_email_uniq, after
--                                              person_normalise_email folded
--                                              cruxINIDA -> cruxindia
--   W-02 overlapping coverage rule   refused   coverage_rule_no_overlap named
--                                              the rule that already held the
--                                              branch
--   W-03 duplicate branch code       refused   branch_code_uniq
--   W-04 duplicate idempotency key   refused   outbox_idempotency_uniq
--   S-01 storm regression            1 row from 100 attempts
--   T-01 traceability                20 of 20 sampled rows walk back
--   T-02 rows with no sheet ref      17, all in person, all the seeded demo
--                                    chair holders on @example.invalid
