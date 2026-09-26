# Statement of Work — PMS round two

Living document. Updated as decisions are made; the Decision log at the foot
records what changed and why.

## Objective

Four things the owner asked for on 26 Sep 2026, after the PLB scheme went
live:

1. Attribute proposals and approvals (A-4, A-5).
2. The ten-working-day dispute window.
3. Replace the sample location chairs from the operating-structure
   recommendation with the real geography already loaded.
4. An "add a person" path that carries every field the tool needs, and that
   cannot be got wrong by hand.

## Scope

In scope: the `plb` engine and edge function, the Performance & bonus screen,
`chair_seating` / `chair_holder`, `person_request` / `person`, and the
validation around them.

Out of scope, unless it turns out to block the above: the older daily-filing
appraisal (`vPms`, `pms_*` tables), payroll integration, and anything that
changes what a person is actually paid without a human pressing a button.

## Inputs

- `Crux_Operating_Structure_Recommendation_1.html` — 70 chairs. The owner has
  now said its **location chairs were samples to represent the org chart**, so
  its six scope labels (North, North East & East, South, West, Pune, Thane,
  "other West locations") are not the geography to build on.
- `op_node` — the real operating geography: **15 zones, 37 locations**.
- `coverage_rule` — who actually runs which place today: **38 open
  BRANCH_MANAGER rules over 37 locations, held by 18 people**.
- `CRUX_PLB_Scorecard_Guide_by_Department.pdf` — s.5 attributes, s.6.2 the
  twelve visible things, s.7 the dispute window.
- `CRUX_PLB_Employee_Explainer.pdf` — the five worked examples.
- `holiday` / `holiday_applies` — the working-day calendar the dispute window
  has to count on.

## Findings that change the work

The org chart and the operating data disagree, and the disagreement decides
who is in the bonus scheme:

| Who runs a place | Seated as | Count |
|---|---|---|
| Branch Manager chair | in the PLB scheme | 8 |
| Location Partner / Franchisee Partner | outside the scheme, correctly — the documents put business partners outside it | 5 |
| Team Leader / Supervisor | outside | 1 (Varsha Sonawane) |
| Zonal Manager | in, at a different chair | 1 (Vrunda Potdar) |
| no chair at all | invisible to the scheme | 3 (Manoj Batham, who runs 7 places; Shyam Sundar Kalta; Vinayak Patil) |

Three of the eleven people seated in the Branch Manager chair run no location
at all. Indore carries four open branch-manager rules where it should carry
one.

**Decision:** the structural work is done automatically; the seating of a
named person into a chair that puts them in a bonus scheme is not. The screen
will show each disagreement with its evidence and a button, and a person will
press it.

## Assumptions

- A-4 and A-5 are proposed by the employee and approved by the manager; A-1 to
  A-3 are fixed and need no approval. (Scorecard guide s.5.)
- The dispute window is ten **working** days from publication, counted on the
  holiday calendar for the person's own location.
- A dispute names one element; the undisputed remainder is still paid on time.
- Raising a dispute is never a ground for an adverse consequence, so nothing
  in the model lets a dispute change anyone's score by itself.

## Deliverables

- Migration 168: attributes and disputes in the engine.
- Migration 169: the screen for both.
- Migration 170: geography-derived seatings.
- Migration 171: the add-person gate and its screen.
- Migrations 176-178: the employee-number backfill, and the two latent hazards
  it exposed (an upload matching a retired person; nineteen upload functions
  open to `anon`).
- Migrations 179-184: merging two records of one person -- the plan, the act,
  the duplicate finder, and the screen.
- `plb` edge function at v3+, `hr` at v2; `build/app/screen-plb.js`,
  `build/app/screen-hr-add.js` and `build/app/screen-hr-merge.js` kept
  byte-identical to what `app_page` holds.

## Validation

Every migration asserts its anchors before writing and re-reads the row after.
Screen changes are proved by comparing the md5 of the spliced block against
the source file. The published page's JavaScript is parsed with `node --check`
after each publish.

## Status

All four delivered and live, plus the backfill and the merge that followed
from them.

| # | What | Where it is |
|---|---|---|
| 1 | Attribute proposals and approvals | Live. Migrations 168, 170, 171; `plb` v3 |
| 2 | The dispute window | Live. Migrations 169, 170, 171 |
| 3 | Geography-driven seatings | Live. Migrations 172, 172b. 274 seatings from `op_node`; `plb_unseated()` lists the five people who need a decision |
| 4 | Add a person | Live. Migrations 173, 173b, 174, 174b, 174c, 175, 175b; new `hr` edge function at v1 |
| 5 | Employee-number backfill | Done. Migration 176: eleven resolved into six mints, two merges, three non-people. 177 and 178 close what it exposed |
| 6 | Merge two records of one person | Live. Migrations 179-184; `hr` at v2. Two real merges are queued for the owner to decide: Ananya Gawade and Vinayak Jondale |

## Decision log

| When | Decision | Why |
|---|---|---|
| 26 Sep | Add the PLB scheme beside the older appraisal screen rather than replace it | The older screen is a different scheme with live data |
| 26 Sep | Pin the `issue` route's jsonb parameter with `$5::text` | postgres.js serialises a JS array as a Postgres array literal, so `[]` arrived as `{}` |
| 26 Sep | Geography-driven seatings are generated; putting a named person in one is not | Seating someone in the Branch Manager chair puts them in a bonus scheme |
| 26 Sep | `person_check()` lives in the database, and both the screen and the writer call it | A validator the applier does not share drifts; this codebase has paid for that on rates and on client codes |
| 26 Sep | HR may not create an administrator | HR can create people. If HR could also set app_role freely, "who may make an admin" would be settled by a dropdown nobody had thought about |
| 26 Sep | Add-person lives in a new `hr` edge function, not in `api` | `api` owns the older request queue and is at the deploy size limit |
| 26 Sep | A merge is planned before it is acted on, and the plan is generated from `pg_constraint` | A hand-written list of tables is correct the day it is written and silently wrong the first time somebody adds one |
| 26 Sep | A seat that loses a merge is closed with today's date, never deleted | Where somebody sat is a fact |
| 26 Sep | The merged-away record is superseded, kept and readable, and keeps its old employee number | The uniqueness rule excludes superseded rows, so the survivor can take that number in the same transaction |
| 26 Sep | Where one side of a merge is blank and the other is not, the side with a value is pre-selected | Defaulting to the survivor everywhere keeps a blank over a fact and says nothing |
| 26 Sep | The two real merges are left for the owner | Vinayak Jondale is a PARTNER record and an EMPLOYEE record in the Branch Manager chair, which is in the bonus scheme. That is a business decision, not a tidy-up |

## Open questions

- **Vinayak Jondale.** EMP-0041, PARTNER, in Location Partner / Franchisee
  Partner; and a second record, no employee number, EMPLOYEE, LOCATION_HEAD,
  in Branch Manager -- which is in the PLB scheme. Merging decides which
  employment type and which chair survive, and therefore whether this person
  is in the bonus scheme. Needs the owner.
- **Ananya Gawade.** EMP-0019 with a work address, and a second record with a
  gmail address, Operations, designation Executive, in Field Executives /
  Verifiers. The survivor should almost certainly be EMP-0019 taking the
  other's department and designation, but it is still somebody's decision.
- `plb_unseated()` and `person_without_number()` exist and are correct, but no
  screen shows them yet.
