# What's actually live vs. what this bundle shipped

Pulled verbatim from `supabase_migrations.schema_migrations.statements` on the
live `crux` project (`oxpwqfbtbxlvuqpztbwg`, ap-south-1) on 2026-09-15, because
`99_verify.sql` didn't read clean against this bundle's files — the database
turned out to be *ahead* of the repo, not behind it or wrong.

## What happened

`build/schema.sql` was applied to Supabase as four separate migrations, not
one file: `crux_schema_base` → `crux_schema_v2` → `crux_schema_v21` →
`crux_schema_identity_pms`. Then `schema-patch-v3.sql` and `schema-patch-v4.sql`
applied exactly as this repo has them, then `migration/00`→`70` exactly as
this repo has them, then `01_rls.sql` and `02_auth_storage.sql` exactly as
this repo has them. **Up to that point everything lines up.**

After that, six more migrations were applied directly against Supabase and
never written back into this repo:

| File here | Live migration | What it does |
|---|---|---|
| `20260910142808_crux_schema_patch_v5.sql` | `crux_schema_patch_v5` | `daily_count` gets a `values jsonb` column so one filing can carry several KPIs; loosens the old single-KPI NOT NULLs; `person`/`person_request` gain an `employee_type` check (EMPLOYEE/PARTNER/INTERN/CONTRACT); seeds three PMS timing settings. |
| `20260910145155_crux_schema_patch_v6_pms_cascade.sql` | `crux_schema_patch_v6_pms_cascade` | Migrates `setting` rows into `app_setting` (the admin-facing table with plain-language labels) and seeds the full PMS cadence/cascade settings — window open/close, self-eval deadline, dispute/exception hours, escalation attribute cost. |
| `20260910145437_crux_pms_score_unscored_is_null.sql` | `crux_pms_score_unscored_is_null` | Replaces `pms_cycle_score()` so a cycle with no KPI/Attribute components yet returns nulls instead of zeros — an unscored cycle no longer looks like a zero score. |
| `20260910150000_crux_schema_patch_v7_lock_postgrest.sql` | `crux_schema_patch_v7_lock_postgrest` | Revokes insert/update/delete/truncate from `anon`/`authenticated` on every table (the API is the only writer), forces RLS on ~40 tables that hadn't had it forced, and pins `search_path` on the security-definer-adjacent functions. |
| `20260910151321_crux_schema_patch_v8_bulk_upload.sql` | `crux_schema_patch_v8_bulk_upload` | Adds `upload_kind`/`upload_batch`/`upload_row`/`upload_column` — the templates and load-order table behind Data setup → Bulk upload. `load_order` here matches `DEPLOY.md` §5 exactly. |
| `20260911032936_crux_schema_patch_v9_sample_data.sql` | `crux_schema_patch_v9_sample_data` | Adds `sample_row` + `sample_seed()`/`sample_purge()`/`sample_count()`. Every row currently in the database (23 people, 19 branches, 7 clients, etc.) is tagged demo data from `sample_seed()`, safe to remove with `select * from sample_purge();` before loading real masters. **Nothing live right now is real production data.** |

`crux_schema_base.sql`, `crux_schema_v2.sql`, `crux_schema_v21.sql` and
`crux_schema_identity_pms.sql` are also included here verbatim, as applied.

## This directory is NOT the whole story — corrected 2026-09-15

The migration ledger stops at v9, but **the live database does not.** A large
body of later work — `schema-patch-v10` through `v22` in the first attempt's
repo — was applied to this database *without* going through
`supabase_migrations`, so none of it appears in the ledger this directory was
built from. Verified live: **120 tables, 143 functions, `pg_cron` installed
with two active jobs.** The OGL module (`verification_case`, `assignment`,
`sla_*`, `ogl_transition_rule`), the bulk-upload system (`upload_kind`,
`upload_batch`, `upload_row`, `upload_column`), `ref_counter`, `app_page`,
`login_attempt` and `strike_event` all come from that unrecorded work.

Treat the **live catalogue** as the source of truth for schema, not this
directory and not `build/schema.sql`. Both are behind.

## What this means for `99_verify.sql`

Row 1 ("Tables present: 78") and row 3 ("RLS enabled: 35") read FAIL only
because the live schema has grown past those numbers (120 tables, RLS forced
on all of them by v7) — that is progress, not drift, and the checks' expected
values are stale. Row 2's "1 unvalidated constraint" is
`realtime.messages.messages_payload_exclusive`, a Supabase-internal table,
not an application constraint.

Row 7 ("Coverage overlaps refused at write time") reads FAIL only because the
check looks for an exclusion/unique constraint on `coverage_rule`. The actual
enforcement is a `BEFORE INSERT OR UPDATE` trigger, `coverage_rule_no_overlap`,
calling `coverage_no_overlap()` — added in one of `v2`/`v21`/`identity_pms`.
It is present and working; the check is looking for the wrong mechanism.
