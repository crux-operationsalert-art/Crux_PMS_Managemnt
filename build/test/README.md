# Running the database code before it is applied

`./build/test/run.sh` builds a throwaway Postgres 16, applies migrations
190–199, and runs 87 assertions against them. It does not touch Supabase.

```
== 87 passed, 0 failed
```

It exists because `CREATE OR REPLACE FUNCTION` returning success is not a
test. plpgsql checks syntax when a function is created and **nothing at all**
about the functions its body calls. This project has already paid once for
believing otherwise: `person_merge_plan` was created calling a
`person_merge_side` that did not exist yet, and the database accepted it
without a word. Every assertion below runs the code.

## What the first run found

Five defects, none of which any amount of reading had caught.

**1. Two constraints on `perf_assignment` contradicted each other.** The
table's CHECK defines a split by `part_of_id` and says nothing about
`split_ref`; the unique indexes defined it by `split_ref`. So a measure split
by a *label* rather than by a row in another table — "walk-ins", "over the
counter", a client the tool does not hold — passed the CHECK and then
collided with its own parent, and the person splitting it would have been
told their KPI already existed. Fixed in migration 199, which keys both
indexes on `part_of_id`, the thing the CHECK, the trigger and `perf_value()`
all already use, and adds a CHECK that a split must be identifiable by
something.

**2. `perf_file` raised where everything else answers.** The trigger that
stops a number being filed against a measure that has parts does its job by
raising, so the refusal came out of the service as a 500 with a Postgres
sentence in it, in a codebase where every other refusal is a worded answer.
`perf_file` now asks the same question first and answers it; the trigger goes
back to being the backstop for callers that never came through the function.

**3. A shadowed alias.** The fix for (2) was first written
`select 1 from perf_assignment c where c.part_of_id = ...`, and `c` is
already declared as the cycle in that function. plpgsql resolves a query
alias against the declared names first, so it failed at run time with
*record "c" has no field "part_of_id"* — a `CREATE OR REPLACE` away from
production and invisible to every check short of calling it.

**4. A split had no rhythm.** `perf_due` read the cadence off the row, and a
split created under a parent has none — so a measure split by client, which
is the ordinary case and the one the owner asked for by name, fell through to
the month-end default and nobody was reminded of it for four weeks. The
cadence now falls back to the parent's.

**5. `perf_kpi_score` named one reason where two applied.** A measure with
neither a target nor a filing said only "nothing filed yet", which sends a
manager to chase a number for a measure they never set a target on. It now
names every reason that applies.

## What the run also proved about this repository, and what was done about it

**`build/migration` could not rebuild the database.** Forty-five of its 111
`.sql` files carry no executable SQL. From 134 onwards they are notes
recording what was applied through the MCP tool, headed
`-- Applied as: <migration name>`, and the SQL itself was never written back.
`build/schema.sql` is a design document rather than DDL — it has two `UNIQUE`
table constraints over expressions, which Postgres does not accept and never
did.

Counting `build/schema.sql`, both patch files and every migration file
together, the repository could create 120 of the live project's 155 tables
and 110 of its 311 function names. Two hundred and one functions, better than
half a megabyte of them, were in no file here at all. The concrete cost
showed up in this very work: `perf_cycle_open` calls `plb_wd_after`, which
migration 168 announces in a comment and defines nowhere, so its signature
had to be guessed.

**That is now fixed, and this script is the proof.** `build/schema/` holds a
generated baseline of the live schema, written back by
`.github/workflows/snapshot-schema.yml` and never retyped by hand.
`run.sh` builds a blank Postgres, loads that directory and nothing else — no
`build/schema.sql`, no fixture standing in for what was missing, no migration
applied on top — and runs the assertions against the result. It counts what
it built, and the counts match the live project object for object: 155
tables, 314 functions, 20 views, 328 indexes, 11 triggers, 52 policies.

`fixture_live_shape.sql` was the stand-in for all of that and is gone. So is
the two-cluster arrangement it needed. `build/schema/REGENERATE.md` says how
to make the baseline again; `build/migration/README.md` says why it exists.

## What run.sh also checks

plpgsql validates the syntax of a function body at `CREATE` and does not
check that the functions the body calls exist. That is how `person_merge_plan`
came to call `person_merge_side`, which was never there. Nothing in a load
can catch it, so `run.sh` checks it once, against everything that loaded,
after the rebuild.
