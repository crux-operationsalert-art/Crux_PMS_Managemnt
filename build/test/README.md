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

## The stronger check: the same database, or only the same counts?

Matching counts are not matching definitions. So the rebuilt database and the
live project were fingerprinted object by object — the text Postgres itself
prints for each one, hashed — and compared.

| | |
|---|---|
| tables, columns, types, defaults, generated | `7b397118668975b1061eef6a217b9201` **identical** |
| constraints (keys, uniques, checks, foreign keys) | `3b431d4d932d6b5adcb3473202ddce75` **identical** |
| indexes | `9efe75facc4d78a4c0c12917fa9231c0` **identical** |
| functions, all 314, whole definitions | `595bea1e0d4418d7a98b5abb877071d6` **identical** |
| triggers | `d4b2e65fc9c411df3975ed7e655ac11e` **identical** |
| policies | `25f45305460353531c939c2460f546f2` **identical** |
| views | 19 of 20 identical |

Two things had to be got right for that comparison to mean anything, and both
were wrong on the first attempt:

* **Sort under `collate "C"`.** A local cluster and Supabase do not order text
  the same way, so `string_agg(… order by definition)` over an identical set
  of functions produced two different hashes. The set was never different;
  the sort was.
* **Leave out `t_ok`.** The assertions create it, so it is in the rebuilt
  database and not in the live one.

**The one view that differs is `migration_gate`, and the difference is the
deparser talking to itself.** Live prints
`SELECT 'matrix rows loaded'::text,`; the rebuilt copy prints
`SELECT 'matrix rows loaded'::text AS text,`. `pg_get_viewdef` adds column
aliases to the second and later branches of a `UNION` when it writes the
definition out; creating the view from that text makes those aliases real,
and they are printed back the next time. The view's own column names come
from the first branch, which is untouched, and both copies report the same
six columns with the same types:

```
gate text, actual bigint, expected integer, delta bigint, result text, basis text
```

So it is the same view. It is worth knowing about because it means the
baseline will not converge to byte-equality with a database rebuilt from it,
and that is a property of `pg_get_viewdef`, not a fault in the baseline.

To do the comparison again, run this against both and compare the rows:

```sql
select 'functions', md5(string_agg(d, E'\n' order by d collate "C")) from (
  select pg_get_functiondef(p.oid) d from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f','p')
     and p.proname not like 'schema\_snapshot%' and p.proname <> 't_ok') q
union all
select 'views', md5(string_agg(d, E'\n' order by d collate "C")) from (
  select n.nspname||'.'||c.relname||'|'||pg_get_viewdef(c.oid, true) d
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public','seam') and c.relkind = 'v') q;
```

## Two migrations the harness deliberately does not run

`build/test/run.sh` loads `build/schema` and nothing else, so no migration runs
in it at all. Two of them could not, even if it did, and the reason is worth
knowing before somebody "fixes" it:

* **204** seeds the access table from the published tool's own `SCREENS`. The
  harness checks that seed a better way — `check_access_matches_nav.py` reads
  `index.html` and compares all 262 (level, screen) pairs against the rows.
* **206** ends by asserting that *no seated chair is without a measure set*.
  That is an assertion about the live registry. The fixture in `test_scope.sql`
  deliberately seats three chairs and leaves them empty, because a detector
  nobody has watched fail is not a detector — so running 206 here would fail on
  the very state the test exists to create.

What the harness asserts instead is that the detector works: `kpi_registry_gap`
names a seated chair with no measures, stops naming it the moment it has one,
and the unique index refuses the same measure twice on one chair.
