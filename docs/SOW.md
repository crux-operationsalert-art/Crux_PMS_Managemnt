# Statement of Work — the two remaining tasks

Living document. Updated as decisions are made, not after.

Last updated: 2026-09-27.

---

## Objective

Close the last two open items on the Crux build:

* **#13 — Enforce scope in the services, not just the nav.**
* **#18 — Give every seated chair a measure set.**

## Scope and boundaries

**In scope**

* The `ops` Edge Function and every route in it.
* The database: a single table of who may open what, and the functions that
  read it.
* `auth_whoami`, so the front end and the services answer from the same rows.
* The KPI registry for the chairs people are actually sitting in.

**Out of scope, and why**

* **The `api` Edge Function.** It is at the size an Edge Function deploy will
  carry and cannot be redeployed. Its routes already scope their reads
  (`req.scope.branches()`, `subtreeIds`, `clientView`, `mayWriteChair`), so it
  is not where the gap is. Anything it would still need is recorded below
  under *Known limitations* rather than silently skipped.
* **Merging the duplicate chairs** (see Findings). That changes the org chart
  and the reporting lines, and it is the owner's decision, not mine.
* **Changing what each level is allowed to see.** The task is to enforce the
  rule that exists. Where the rule itself looks wrong, it is flagged, not
  quietly rewritten.

## Inputs and sources

| | |
|---|---|
| `index.html`, `var SCREENS` / `CHAIR_LEVEL` / `UNDER` / `myLevel()` | the eight-level access table the design specifies, as built |
| `build/supabase/functions/ops/**` | verified byte-identical to live `ops` v6 before any change |
| `chair`, `chair_holder`, `chair_measure`, `kpi_definition` | the seating and the registry |
| `coverage_rule`, `coverage_resolve()` | what a person covers |
| `business_record`, `seam.tenday_snapshot` | what MIS reads |

## Findings that shape the work

**F1 — The front end says so itself.** Above `var SCREENS` in the published
tool:

> It decides what appears in the navigation and what `currentTab()` will open.
> It is **NOT** the permission check. Every service decides for itself and
> refuses in its own words; hiding a screen stops somebody wandering into it
> and does nothing about somebody typing the URL.

The second half of that sentence is not true of `ops`. Four of its six route
files check only `requireChair` — that the caller holds *a* chair, any chair.

**F2 — What `ops` actually leaves open to any chair holder.** A field
executive's token reaches all of it:

| route | what comes back today |
|---|---|
| `GET /api/rates` | every client's commercial rate, all 433 versions |
| `GET /api/access` | 1,000 active people with department, chair and coverage counts |
| `GET /api/access/person/:id` | anyone's coverage and explicit grants |
| `GET /api/access/joining` | every in-flight hire and every unactivated account |
| `GET /api/auto` | job configuration, cron lines, last errors |
| `GET /api/mis` | every row of `business_record`, unfiltered |
| `GET /api/mis/tenday` | every location's ten-day position |
| `GET /api/mis/reports` | company-wide row counts, labelled "Your coverage" |

**F3 — The scope level is carried and never used.** `buildScope` returns
`chairs`, `chairIds`, `subtreeIds`, `clientView` and `isAdmin`. It does not
carry the eight-level scope the design defines, so no service can check it.

**F4 — Two parallel sets of chairs.** The KPI registry was written against the
*function* chairs; the people were seated in a different set. Only two chairs
are both seated and measured:

| seated and measured | seated, no measures | measured, nobody seated |
|---|---|---|
| BRANCH_MANAGER (11 people, 4) | EXECUTIVE (63), TEAM_LEADER (9), LOCATION_PARTNER (7), ZONAL_MANAGER (2), and 8 more with 1 each | OPS, FIN, RM, BZ, ACC, BD, BEX, BID, CCM, CS, ENG, GRC, MIS, TEC (15 chairs, 58 measures) |
| AVP (1 person, 3) | | |

**89 of the 101 seated people sit in a chair with no measure set.** Several of
the unmeasured chairs have an obvious counterpart that is measured —
`Head — Operations` / `Operations Head`, `Head — Finance Operations` /
`Finance Head` — which is why this is partly a mapping problem and not only an
authoring one.

**F6 — What enforcement actually changed, counted.** Every active person,
every gated route, asked of `access_may_open()` after the change. Before it,
all 104 reached all eleven:

| route group | reaches it now | levels |
|---|---|---|
| `coverage` (Places, coverage & owners) | 4 of 104 | admin |
| `hr` | 6 of 104 | admin, hr |
| `auto` (Automations) | 8 of 104 | admin, finance, hr |
| `joining` | 28 of 104 | admin, branch, hr, partner |
| `access`, `mis`, `rates`, `reports`, `tenday` | 30 of 104 | admin, branch, finance, hr, partner |
| `ideas`, `visits` | 104 of 104 | everybody, as before |

Seventy-four people lost the rate master alone. No screen anybody could
*reach* has been taken away: the gate is the navigation's own table, so the
change is only to what a typed URL does.

**F7 — A permission for a group that cannot open the screen.** `places.ts`
carries `mayAssign`, which lets Operations assign coverage. No Operations
chair carries `coverage` in `SCREENS`, so Operations cannot open the screen
that permission is for. Either the permission is vestigial or the policy is
missing a row; both are one line, and neither is mine to choose.

**F5 — Every one of those chairs already says what it is answerable for.**
`chair_measure` holds 501 statements across 152 chairs, 3 to 6 for each of the
twelve. That is the source the measure sets are written from; nothing is
invented.

## Assumptions

* A1. The eight-level table in the published tool is the intended policy. It
  is enforced as written.
* A2. A chair's measures belong to that chair. Copying the wording of a
  counterpart chair's measure onto a seated chair is not a merge and changes
  no reporting line.
* A3. `business_record` is keyed by `(client_id, geo_node_id)`, not by branch,
  so "your coverage" for MIS means the (client, geography) pairs the person's
  coverage resolves to. It is empty today (0 rows), so this is enforced before
  there is anything to leak rather than after.

## Deliverables

1. `build/migration/204_*.sql` — the access table, the functions that read it,
   and `auth_whoami` returning the caller's level and screens.
2. `build/supabase/functions/ops/**` — every route gated by the screen it
   serves; MIS filtered to coverage; the people list filtered to the subtree.
3. A front-end patch so the nav asks the server what it may open and falls
   back to its own table only if the server does not say.
4. `build/migration/205_*.sql` — a measure set for each of the twelve seated
   chairs that has none, written from that chair's own statements.
5. A standing check that reports a seated chair with no measure set, so this
   cannot regress quietly.
6. Tests in `build/test/` that run against the rebuilt database.

## Methodology

One table in the database says what each level may open. `auth_whoami` returns
it; `ops` reads it; the nav prefers it. Two copies of a policy drift, so there
is one copy and two readers.

Each route names the screen it serves. The gate is the same function the nav
calls, so a change to the policy moves both at once.

## Decision log

| # | Decision | Why |
|---|---|---|
| D1 | The policy lives in the database, not in each service | Two hard-coded copies is the failure this task exists to fix |
| D2 | `auth_whoami` carries it, not a new endpoint | `auth_whoami` is a database function; adding to it needs no Edge Function redeploy, and `api` cannot be redeployed |
| D3 | Enforce the existing policy exactly; flag what looks wrong | Rewriting the policy while implementing it hides the change |
| D4 | Do not merge the duplicate chairs | Changes the org chart; the owner's call |
| D5 | Measures written from each chair's own `chair_measure` statements | The chair has already said what it is answerable for |
| D6 | Reuse a counterpart chair's wording where one exists | Two names for one number is worse than one |
| D7 | The baseline carries the five `access_*` tables' ROWS | Without them a rebuilt database answers false for everybody; that is configuration, not data (207, 208) |
| D8 | The snapshot regenerates when a migration lands, not only when the workflow changes | Regenerating by hand is the step a person forgets |

## Risks

| | risk | handling |
|---|---|---|
| R1 | `ops` has been refused by the deploy bundler before | The repo was verified byte-identical to live v6 first, so a refusal leaves v6 running and loses nothing |
| R2 | Tightening a route breaks a screen somebody uses today | The gate is the nav's own table, so any screen a person can currently *reach* stays reachable |
| R3 | A chair title not in the table | Falls back to department, then to the smallest list. A person the tool cannot place sees less, not more — same rule the nav already uses |
| R4 | New measures change somebody's live appraisal | Measures are definitions; a score needs a target and a filing, and neither is created here |

## Validation and acceptance

* V1. Every `ops` route refuses a caller whose level does not carry its screen,
  with a reason in words.
* V2. `person_may_open()` agrees with the published tool's `allowed()` for
  every (level, screen) pair — checked by test, not by eye.
* V3. MIS returns only rows inside the caller's coverage.
* V4. Every seated chair has at least three active measures.
* V5. `build/test/run.sh` still rebuilds from `build/schema` and passes.

## Status

| | |
|---|---|
| Findings F1–F5 | established against the live project |
| **#13** | **done.** Migrations 204 and 205 applied; `ops` v7 deployed and verified byte-identical to this repository; build-tool patch 10 written |
| **#18** | **done.** Migration 206 applied: 14 of 14 seated chairs carry a measure set, 0 people without, registry 65 → 115 active measures |

### What was actually delivered

| | |
|---|---|
| `build/migration/204_one_table_says_who_may_open_what.sql` | the access table, `access_level_of`, `access_screens`, `access_may_open`, and the two auth functions returning them |
| `build/migration/205_the_ten_day_view_carries_its_keys.sql` | `seam.tenday_snapshot` carries `client_id` and `geo_node_id` |
| `build/migration/206_a_measure_set_for_every_seated_chair.sql` | 50 measures across 12 chairs, a unique index so none can be authored twice, `kpi_registry_gap` and `kpi_registry_completeness()` |
| `build/supabase/functions/ops/**` (v7) | `requireScreen` on all 40 routes; MIS, ten-day and Reports cut to coverage; the people list to the subtree |
| `.github/build-tool.py` patch 10 | the navigation prefers the server's list |
| `build/test/test_scope.sql` | 29 assertions |
| `build/test/check_access_matches_nav.py` | 262 (level, screen) pairs, page against database |

### Acceptance, against V1–V5

| | |
|---|---|
| V1 every ops route refuses out of scope, in words | done — `requireScreen`, 40 routes, 11 distinct screens |
| V2 `person_may_open()` agrees with the page's `allowed()` | done — 262 pairs, checked by script, not by eye |
| V3 MIS returns only rows inside the caller's coverage | done — and the pair test proves the failure mode it avoids |
| V4 every seated chair has at least three measures | done — 3 to 6 each, asserted by the migration itself |
| V5 `build/test/run.sh` still passes | verified after the baseline regenerated |

## Known limitations, carried forward

**`api` is not gated by screen, and the reason is a decision, not the deploy.**
Its `/api/coverage` route serves the `coverage` screen, which only `analytics`
carries — while the service's own `mayAssign` check grants coverage assignment
to Operations, 47 people, none of whom can open it. That is F7. Enforcing the
navigation's rule on `api` would take a screen away from those 47 on the
strength of a policy that may simply be a row short, so the gate is written and
tested and waits on the answer. Every `api` route already scopes its **data**
(`req.scope.branches()`, `subtreeIds`, `clientView`, `mayWriteChair`); what it
does not have is the screen gate.

Whether `api` can be redeployed at all is still untested. It is 108KB against
`ops`'s 80KB, which deployed. The belief that it cannot has shaped two
decisions — it is why `pack` exists — and it is folklore, not measurement. It
is worth one probe the next time there is a reason to touch `api`.

## The three questions, and where they now live

They are on the **Alerts screen**, raised by `access_policy_questions()`
(migration 210), INFO rather than WARN because the tool is not broken —
somebody has to decide something. Each carries the line that settles it, and
each resolves itself, with a note, the moment the fix is applied.

| | who it affects | the one line |
|---|---|---|
| The rate master follows Reports | 30 people can read every client's rate | `update access_screen_parent set parent = 'config' where screen = 'rates';` |
| `ADMIN_TABS` is declared and never read | Messaging to HR, Data setup to MIS | `delete from access_level_screen where (level, screen) in (('hr','mail'), ('analytics','data'));` |
| Operations may assign coverage, and cannot open the screen | 47 people | `insert into access_level_screen (level, screen) values ('branch','coverage');` — or `mayAssign` is vestigial and should go |

## Verification, in the end

| | |
|---|---|
| The policy, against the page | 262 (level, screen) pairs, by script |
| The policy, against real people | every active person, every gated route |
| The scoping, as SQL | the pair test: two records of four, not four |
| The scoping, through the driver | `postgres@3.4.5`, same options as `ops/shim.ts` — `text[]` arrives as a JavaScript array, `uuid[]` pairs arrive as pairs, and `'rate'` does not match `'rates'` |
| The deployed service | all nine files byte-identical to this repository |
| The whole database | rebuilt from `build/schema` and nothing else |

```
./build/test/run.sh
  tables 160  functions 319  views 21  indexes 334  triggers 11  policies 52
  every function the bodies call is present
  driver: 10 passed, 0 failed
  the navigation and the database agree on all 262 of them
  170 passed, 0 failed
```
