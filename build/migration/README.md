# The migrations, and why they were not enough

## What was wrong

These numbered files are the narrative of how the database was built. They
are good at that. They were never a build.

Measured on 27 September 2026 against the live project, and counting
`build/schema.sql`, both patch files and all 111 `.sql` files in this
directory together, the repository could create:

* **120 of the 155 tables**
* **110 of the 311 function names** — 201 functions, better than half a
  megabyte of definition, existed in no file in this repository at all

Forty-five of the 111 files here contain no executable SQL whatsoever. They
describe a change in prose; the SQL that made it went to Supabase through an
API call and was never written back.

This is not a theoretical complaint. It has cost real work three times:

* `next_ref` had to be recovered from the live project with
  `pg_get_functiondef` when the local test harness would not build without it.
* `working_hours_after` had to be recovered the same way, and then its
  `numeric` overload had to be found by experiment.
* `person_merge_side` turned out not to exist at all. `person_merge_plan`
  called it and had been applied anyway, because plpgsql checks the syntax of
  a function body at `CREATE` and does not check that the functions it calls
  are there.

A repository in that state does not lose anything while the live project is
up. It loses everything the moment it is not.

## What fixes it

`build/schema/` — a complete, generated baseline of the live schema, written
back into the repository by `.github/workflows/snapshot-schema.yml` and never
retyped by hand. `build/schema/REGENERATE.md` says how to make it again and
how to rebuild a database from it.

The baseline is the answer to *what is the database*. These files stay as the
answer to *why*.

## The rule, from here on

1. **Every change to the database is a file here, with its SQL in it**, and
   it is applied *from* that file. A migration whose SQL only exists in an API
   call has not been written down.
2. **Then regenerate the baseline.** Push a touch to
   `.github/workflows/snapshot-schema.yml`, or run *Snapshot the schema* from
   the Actions tab. If the baseline commit shows nothing, the migration did
   not do what its file says it did.
3. **A file that is only prose is fine, and is named so.** Some of these are
   genuinely notes — an investigation, a decision, a count. What is not fine
   is a file that reads as though it applied SQL and carries none.

## Two files that were applied outside this rule, and are now recorded

* `201_the_tenth_of_the_month.sql` — two `alter type … add value` statements.
  `ALTER TYPE … ADD VALUE` could not be sent through the migration API at the
  time, so it went through `execute_sql` and never reached
  `supabase_migrations.schema_migrations`. It has now been inserted there
  under version `20260927120201`, with its statements, so the ledger and the
  file agree.
* `203_the_database_can_describe_itself.sql` — recorded under version
  `20260927160203`, its statements taken from the catalogue so that what the
  ledger holds is exactly what the database is running.

## What is where

| | |
|---|---|
| `build/schema/` | the generated baseline — what the database **is** |
| `build/migration/*.sql` | the numbered history — **why** it is that |
| `build/migration/masters/` | reference data the migrations load |
| `build/migration/org/` | the operating structure, and the scripts that made it |
| `build/test/` | a throwaway Postgres, the baseline, and the assertions |
| `build/supabase/functions/` | the edge functions |
| `build/app/` | the screens spliced into `app_page` at publish time |
