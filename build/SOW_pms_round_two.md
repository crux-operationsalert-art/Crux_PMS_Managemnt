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
- `plb` edge function at v3+; `build/app/screen-plb.js` kept byte-identical to
  what `app_page` holds.

## Validation

Every migration asserts its anchors before writing and re-reads the row after.
Screen changes are proved by comparing the md5 of the spliced block against
the source file. The published page's JavaScript is parsed with `node --check`
after each publish.

## Status

In progress. 1 and 2 first, then 3, then 4.

## Decision log

| When | Decision | Why |
|---|---|---|
| 26 Sep | Add the PLB scheme beside the older appraisal screen rather than replace it | The older screen is a different scheme with live data |
| 26 Sep | Pin the `issue` route's jsonb parameter with `$5::text` | postgres.js serialises a JS array as a Postgres array literal, so `[]` arrived as `{}` |
| 26 Sep | Geography-driven seatings are generated; putting a named person in one is not | Seating someone in the Branch Manager chair puts them in a bonus scheme |
