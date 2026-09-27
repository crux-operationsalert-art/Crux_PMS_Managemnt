# The baseline, and how to make it again

Everything in this directory except `00_extensions.sql`, `load.sh` and this
file is generated. Do not edit a generated file. Change the database with a
migration, then regenerate, and the change arrives here on its own.

## What is here

| file | what it holds |
|---|---|
| `00_extensions.sql` | hand-written. Extensions and schemas, written so a plain Postgres loads it. |
| `05_types.sql` | the enums |
| `08_sequences.sql` | the sequences |
| `09_staging.sql` | the `stg` schema the legacy spreadsheets landed in, and the five normalisers two views call |
| `10_tables.sql` | columns and defaults, nothing else |
| `11_sequence_owners.sql` | which column owns which sequence |
| `20_keys.sql` | primary keys and uniques |
| `21_checks.sql` | check constraints |
| `22_foreign_keys.sql` | foreign keys |
| `30_indexes.sql` | the indexes no constraint owns |
| `40_functions_1..4.sql` | every function and procedure |
| `50_views.sql` | `public` and `seam` |
| `60_triggers.sql` | the triggers |
| `70_rls.sql` | row level security, and the policies |
| `75_grants.sql` | what `anon`, `authenticated` and `service_role` may touch |
| `80_comments.sql` | what the database says about itself |
| `90_cron.sql` | the scheduled jobs |
| `95_access_policy.sql` | who may open what — the only rows the baseline carries |
| `load.sh` | loads them in the one order that works |

## To regenerate

Push anything to `main` that touches
`.github/workflows/snapshot-schema.yml`, or run **Snapshot the schema** from
the Actions tab. The job asks the database what it is and commits the answer.
Nothing is retyped by hand at any point, which is the only reason to trust it.

It calls one function, `public.schema_snapshot()`, added by
`build/migration/203_the_database_can_describe_itself.sql`. That function is
read-only, reads only the system catalogues, and returns no row of anybody's
data.

## To rebuild a database from it

```sh
build/schema/load.sh "postgres://…"
```

`build/test/run.sh` does exactly this against a throwaway cluster and then
runs the assertions, so the claim that this directory can rebuild the
database is tested rather than asserted.

## On the grant

`schema_snapshot()` is granted to `anon`, so the workflow can call it with
the publishable key — the same key the tool itself uses and the same key that
sits in the open in `publish-tool.yml`. What comes back is exactly what the
job then commits to this public repository, so the grant exposes nothing the
commit does not.

If this repository is ever made private, that reasoning stops holding. Two
lines change it:

```sql
revoke execute on function public.schema_snapshot() from anon;
grant  execute on function public.schema_snapshot() to service_role;
```

and in `snapshot-schema.yml`, replace `$ANON` in the two request headers with
`${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}` and add that repository secret.

## What this does not cover

* **Data,** with one exception. This is the shape, plus `95_access_policy.sql`
  — the five `access_*` tables, which are configuration and not data: nobody's
  name is in them, they are the same in every environment, and with them empty
  `access_may_open()` answers false for everybody and the rebuilt tool opens
  for nobody. Everything else — the KPI registry, the upload kinds, the
  templates, the holidays — is loaded by the numbered migrations and by
  `build/migration/masters`.
* **`auth`, `storage` and the other Supabase-owned schemas.** They are
  Supabase's to create. Only the `auth_gate` trigger reaches into `auth`, and
  it is in `60_triggers.sql`.
* **The edge functions.** They live in `build/supabase/functions`.
* **The application.** It is one row of `app_page`, and
  `.github/workflows/publish-tool.yml` is how it reaches the world.
