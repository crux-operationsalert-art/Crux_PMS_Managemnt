# Statement of Work — make the data live, and say how far along this is

Living document. Updated as decisions are made, not after.

Last updated: 2026-09-28.
Previous SOW (scope enforcement and measure sets, closed 2026-09-27):
`docs/SOW_2026-09-27_scope_and_measure_sets.md`.

---

## Objective

Two things were asked for, in one message:

1. **"This should make the MIS and Reporting live as well as performance pages."**
   The monthly business workbook (`Full_Data.xlsx`) and the operating structure
   document (`Crux_Operating_Structure_Recommendation.html`) were supplied.
   Load them so the screens that read them stop being empty.

2. **"What's the completion %?"** — answered below, with the arithmetic shown
   rather than asserted.

The complaint behind both — *"I have already provided everything, still nothing
is live"* — was correct. `business_record` held **zero rows**. Every screen
built on it was working perfectly and showing nothing.

## Scope and boundaries

**In scope**

* Parse and load all 4,202 rows of the business workbook into `business_record`.
* Resolve the workbook's own names for places, clients and people onto the rows
  this database already holds, and make that mapping a table rather than a
  script.
* Whatever else stands between "the data is in the database" and "a person sees
  it on their screen".
* Read the operating structure document and close the measure-set gaps it
  exposes.
* An honest completion figure.

**Out of scope, and why**

* **The rate column in the workbook.** Revenue = MTD × Rate exactly in all
  4,202 rows: the sheet derives Rate, it does not carry it. Loading it into the
  rate master would turn an arithmetic artefact into a commercial policy. MTD
  and Revenue load; Rate does not.
* **The 392 city names the geography master does not have.** Each one is a
  question only Crux can answer (which city, or which "Rest of <state>"). They
  are asked, one per branch, in `migration_review`.
* **Guessing coverage.** 82 of the 104 operating staff have no coverage rule at
  all. That is a business fact, not a bug, and inventing rules would fabricate
  who is responsible for what.

## Inputs

| Input | What it is | Where it went |
|---|---|---|
| `Full_Data.xlsx` | 4,202 rows · 79 month-ends Jan 2020 → Sep 2026 · 35 locations · 37 clients · 21 people | `stg.bl_dim`, `stg.bl_fact`, `stg.bl_own` → `business_record` |
| `Crux_Operating_Structure_Recommendation.html` | 70 chair dossiers, each with Responsibility, Information flow, Accountabilities, Tasks, **Measured on**, Authority and Clearance levels | measure sets → `kpi_definition` |

The workbook's figures are **not** in this repository. It holds client-by-month
revenue and the rates implied by it. The repository is public; the migrations
carry the mapping logic and none of the numbers.

## Assumptions

* The workbook's month-end date is the period. The last row is dated
  2026-09-24, not a month end; it is treated as September 2026 all the same.
* Where two workbook lines land on the same (period, client, place) — the two
  Lucknow lines, the two Nagpur lines, and `BOM MSME Post` / `BOM MSME POST` —
  they are summed, and the owner of the larger half keeps the row.
* A branch's own address says where the branch is. Its `op_node_id` does not:
  the operating location "Mumbai" holds branches in Pune, Kolhapur, Satara,
  Sangli, Ahmedabad, Surat, Nagpur, Rajkot, Solapur and Vadodara.
* Where city names nest, the longer one wins — NAVI MUMBAI over MUMBAI, NEW
  DELHI over DELHI, BHILAI over DURG-BHILAI.

## Deliverables

| # | Deliverable | State |
|---|---|---|
| 211 | `business_import_alias`, `business_import_run()`, 4,186 business records | applied, verified |
| 212 | `branch_place_from_address()`, `branch_without_place`, 2,006 branches placed | applied, verified |
| 213 | 58 measures for the 15 chairs that had none | applied, verified |

## Methodology

**Getting 4,202 rows into a database this container cannot reach.** The
Supabase host is refused by the egress proxy (403 on CONNECT), so `psql`,
`pg_dump` and `curl` are all unavailable; the only channel is the MCP
`execute_sql` call. Raw INSERTs came to 385 KB. Indexing the dimensions and
sending `(date, location, client, mtd, revenue)` as a single delimited literal
per chunk brought it to 76 KB in five statements.

**Proving it arrived intact.** Sending data by retyping it invites exactly one
kind of error, so nothing was taken on trust. Six independent sums were computed
from the source file before sending and compared after each chunk:

| Check | Source file | Database |
|---|---|---|
| rows | 4,202 | 4,202 |
| Σ MTD | 1,757,393 | 1,757,393 |
| Σ revenue | 543,738,015 | 543,738,015 |
| Σ (date index × MTD) | 86,113,626 | 86,113,626 |
| Σ (location index × revenue) | 10,394,156,270 | 10,394,156,270 |
| Σ (client index × MTD) | 44,798,694 | 44,798,694 |
| distinct (date, location, client) | 4,202 | 4,202 |

All six matched, and each of the five chunks matched its own running subtotal on
the way. The weighted sums are there because three plain totals can agree while
rows sit under the wrong keys; a weighted sum cannot.

**Naming things.** The workbook says "Bengaluru + Rest Of Karnataka + Kerela",
"NAGPUR (YASH)", "BOB Car Loan +". The database says Bengaluru, Nagpur, BOB CAR
LOAN+. That translation is now a table — `business_import_alias`, 93 rows — and
not a `CASE` statement inside a one-off script, so next month's workbook needs
no new decision. Three of the 93 are guesses and say so.

## Decisions made, and why

| # | Decision | Why |
|---|---|---|
| D1 | Keep the workbook out of the repository | Public repo; the file is client-by-month revenue and implied rates |
| D2 | Load MTD and Revenue, not Rate | Revenue = MTD × Rate exactly in all 4,202 rows; the sheet derives Rate |
| D3 | `day10` and `target` stay 0 | Neither is in the workbook. The MIS goes on saying "No targets are set for this period", which is true |
| D4 | Match "Yash Desai" → `yash.desai` (EMP-0039) | Edit distance 1, same department. Flagged as a guess |
| D5 | Match "Shiva Kumar" → `Shivakumar V` (EMP-0029) | Covers Bengaluru and Chennai, which is exactly what the workbook gives Shiva Kumar. Flagged as a guess |
| D6 | Load Mahesh More's 106 rows with **no owner** | Nobody in this database is called that, and nothing is close. The money is counted; the credit is not |
| D7 | Place branches from their address, not their `op_node_id` | `op_node_id` is filled and wrong (see Assumptions) |
| D8 | Leave 574 branches in no city | A branch in the wrong city is worse than a branch in no city: the first is a number somebody will act on |
| D9 | Leave the Finance Executive chair with no measures | The design document's own entry reads "To be defined" under a track called "Undefined — scope pending" |
| D10 | Write measure *units* but no accountability codes | "Measured on" says what is measured, not in what and under which code. Inventing codes would make the file look more sourced than it is |

## Open questions — these are yours, not mine

| # | Question | Where it appears | Blocks |
|---|---|---|---|
| Q1 | 392 city names are not in the geography master (Adityapur, Saraikela, …) | 599 rows in `migration_review`; `branch_without_place`; Alerts | 574 branches, and therefore 1,187 business records, reaching nobody |
| Q2 | 82 of 104 operating staff have no coverage rule | measurable, not yet alerted | Those people see an empty MIS |
| Q3 | Is Mahesh More an employee, a former employee, or a partner? | `migration_review` | 106 records have no owner |
| Q4 | GOA → Panaji, JHARKHAND → Rest of Jharkhand, PUNJAB → Ludhiana | `migration_review` | 180 records sit in a guessed place |
| Q5 | The rate master is readable by everyone who can open Reports | Alerts screen | 30 people can read every client's rate |
| Q6 | `ADMIN_TABS` is declared and never read | Alerts screen | Messaging sits with HR, Data setup with MIS |
| Q7 | 47 people in Operations may assign coverage and cannot open the screen that does it | Alerts screen | The `api` function cannot be screen-gated until this is settled |

## Risks and known limitations

* **`api` is not gated by screen.** Its routes scope their reads, but it does
  not run `requireScreen`. Blocked on Q7.
* **`api` deployability is untested.** At 108 KB it is near the size an Edge
  Function deploy will carry, and a failed deploy leaves the previous version
  running rather than breaking anything.
* **The three guessed places** are load-bearing for 180 records.
* **`business_import_run()` is idempotent but destructive on conflict**: a
  re-run overwrites a period's figures rather than adding to them. That is
  correct for re-importing a corrected workbook and wrong for importing a
  partial one.

## Validation

| Claim | How it was checked | Result |
|---|---|---|
| The workbook arrived intact | six weighted and unweighted sums, per chunk and in total | pass |
| Every workbook name resolves | `business_import_alias`: 37/37 clients, 35/35 places, 20/21 people | pass, one known miss |
| Money in = money out | `business_import_run()` raises unless Σ MTD and Σ revenue match staging exactly | pass |
| The ten-day view carries it | `seam.tenday_snapshot`: 4,186 rows, 79 periods | pass |
| Branch placement invents nothing | only unambiguous address matches; 574 left alone and alerted | pass |
| Every design chair has measures | 33 of the 34 chairs the design reduces to; `kpi_registry_gap` = 0 | pass |
| The repository still rebuilds the database | `./build/test/run.sh` on a blank Postgres, baseline only | pass |

```
./build/test/run.sh
  tables 161  functions 321  views 22  indexes 335  triggers 11  policies 53
  every function the bodies call is present
  driver: 10 passed, 0 failed
  the navigation and the database agree on all 262 of them
  170 passed, 0 failed
```

The rebuilt database holds every function the live one does except the eight
`schema_snapshot*` functions, which are the snapshotter itself and are left out
of its own output on purpose (209). Nothing else differs.

---

## Completion — the answer, with the arithmetic

**About 85% of the software. About 60% of the data. Roughly 75% of a tool that
works for everybody, up from roughly 55% this morning.**

The reason it felt like nothing was live is that the most visible part —
business numbers — was at zero, and one empty screen reads like a broken
system.

### What is built and carrying real data

| Area | Measure | State |
|---|---|---|
| Database | 161 tables, 329 functions, 22 views, rebuildable from the repo alone | **100%** |
| Screens | 20 screens in the access policy, navigation and services reading the one table | **100%** |
| Scope enforcement | `ops` gates all 18 routes on `requireScreen` | **95%** — `api` still ungated (Q7) |
| Org structure | 154 chairs · 494 accountabilities · 21 capability tracks · 105 clearance levels | **95%** |
| KPI registry | 173 measures over 42 chairs; registry gap 0 | **97%** — 1 chair the design itself leaves blank |
| Performance engine | `perf_month` 8,404 rows, cycle running, PLB engine built | **90%** |
| People | 639 people, 104 operating staff, chairs seated | **90%** |
| Clients & branches | 68 clients, 3,987 branches, 1,241 coverage rules, 433 rates | **85%** |
| **Business data** | **4,186 records · 79 months · Jan 2020 → Sep 2026 · ₹54.4 crore** | **was 0%, now 100% of what was supplied** |

### What is not finished, and what it is waiting on

| Gap | Size | Waiting on |
|---|---|---|
| Branches with no city | 574 of 3,987 | Q1 — 392 city names |
| Business records nobody's coverage reaches | 1,187 of 4,186 | Q1 |
| Operating staff with no coverage rule | 82 of 104 | Q2 |
| Operating staff who can see business on the MIS | 12 of 104 | Q1 + Q2 |
| Records with no owner | 106 of 4,186 | Q3 |
| Policy decisions surfaced and not taken | 3 | Q5, Q6, Q7 |
| `api` screen gating | 1 function | Q7 |

### Read that honestly

For **operations.alert@cruxindia.co.in** the tool is complete today: the
administrator's scope is every chair and every branch, so MIS, Reports, the
ten-day view and the performance pages are all populated, all 79 months of them.

For **everybody else** it is gated by two things Crux owns and I cannot invent:
which city 392 branches are in, and who covers what. Answer those and the same
screens light up for the other 92 people without another line of code.

The engineering that remains is small — one Edge Function to gate, three policy
questions to settle. The distance left is data, and most of it is 392 lines
long.

## Current status and next actions

* 211, 212, 213 applied to `oxpwqfbtbxlvuqpztbwg` and verified.
* Baseline regeneration and `build/test/run.sh` follow the push.
* Next, in the order that buys the most: **Q1** (392 cities → 574 branches →
  1,187 records → most of the workforce), then **Q2**, then **Q7** (which
  unblocks gating `api`).

## Change log

| When | What changed | Why |
|---|---|---|
| 2026-09-28 | Business workbook loaded (211) | `business_record` was empty; every screen reading it was blank |
| 2026-09-28 | Branch geography derived from addresses (212) | 2,580 branches had no place, so no coverage reached any business record |
| 2026-09-28 | Measure sets for 15 chairs (213) | The operating structure document gives measures for all 70 chairs; 15 had none |
| 2026-09-28 | Workbook CSV removed from `build/migration/masters/` | Public repo; the file carries revenue and implied rates |
| 2026-09-28 | Previous SOW archived | Its two tasks closed; this is a new statement of work, not an edit to that one |
