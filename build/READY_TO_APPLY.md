# Status — 27 Sep, everything applied

Nothing is waiting. The monthly PMS and the monthly escalation matrix are
both live in the database, both services are deployed, and the screens
publish from `.github/build-tool.py`.

## Applied to the database

| Migration | What it adds |
|---|---|
| `190_the_monthly_kpi_cycle.sql` | `perf_cycle` — the period and its two windows |
| `191_assigning_a_kpi_for_a_month.sql` | `perf_assignment`, its indexes, the `cadence` column discovered from `kpi_definition`, the edges trigger |
| `192_filing_a_number.sql` | `perf_entry`, and the trigger refusing an entry on a measure that has parts |
| `193_how_a_number_climbs.sql` | `perf_accrual_kind`, `perf_value`, `perf_due` |
| `194_setting_and_filing.sql` | `perf_cycle_open`, `perf_may_set`, `perf_assign`, `perf_assign_bulk`, `perf_carry_forward`, `perf_file` |
| `195_what_a_manager_sees.sql` | `perf_node`, `perf_tree`, `perf_history`, `perf_kpi_score` |
| `196_the_matrix_that_goes_out.sql` | `matrix_dispatch`, `matrix_scope_branches`, `matrix_client_view`, `matrix_pack`, `matrix_month`, `matrix_send` |
| `197_the_reminder_on_the_cadence.sql` | `perf_due` on the working-day clock, `perf_roll_forward`, `perf_reminder_sweep`, the `PERF_REMINDERS` job |
| `198_the_matrix_nudge.sql` | `matrix_nudge_sweep`, the `MATRIX_NUDGE` job |
| `199_a_split_without_an_id_is_still_a_split.sql` | replaces two unique indexes that contradicted the table's own CHECK |
| `200_adds_is_a_default_nobody_set.sql` | the accrual precedence, and 46 registry rows corrected to `REPLACES` |
| `201_the_tenth_of_the_month.sql` | `DAY_OF_MONTH` and `MONTH_END` added to `kpi_cadence` |
| `202_my_tab.sql` | `person.address`, `person.emergency_contact`, `person_document`, `request_responder`, `request_raise`, `request_action`, `request_strike_sweep`, `my_desk`, the `REQUEST_STRIKES` job |

Three cron jobs are scheduled: `crux-perf-reminders` at 04:00 UTC,
`crux-matrix-nudge` at 04:30 and `crux-request-strikes` at 05:00 — all
before the working day in India rather than during it.

`perf_value()` holds the one rule that makes a roll-up correct — counts and
rupees accumulate, a percentage or a score is a level — and applies it at all
three joins: across days, across a person's own splits, and across a team.

## Deployed

| Function | Version | What changed |
|---|---|---|
| `plb` | v5 | 12 `/perf/*` routes |
| `pack` | v1 | new: the monthly matrix despatch, four routes |
| `hr` | v5 | `/hr/desk`, `/hr/desk/request`, `/hr/desk/request/action` |
| `ops` | v6, untouched | — |

`pack` is a fifth front door and the reason is worth keeping: `api` is at the
size an Edge Function deploy will carry, and `ops` serves six screens that
work. Adding one route to `ops` means re-uploading all of it, and a slip
anywhere in that upload takes Places, Reports, MIS, the rate master, report
access and automations down to add one thing. A new door costs one more URL
and risks nothing that is already running.

## Published

Nine patches in `.github/build-tool.py` now. The first five detect
themselves as already in `app_page` and skip; 6 and 7 carry the two new
screens; 8 is the difference between the despatch's first version and its own
front door, because patch 7 is all-or-nothing on one sentinel and the page had
already taken it.

## How it was checked

`./build/test/run.sh` builds a throwaway Postgres 16, applies 190–202 and runs
**120 assertions, 0 failures**. It found five defects that reading had not —
`build/test/README.md` lists them, and the worst would have made `perf_file`
answer a 500 with a Postgres sentence in it.

Then the monthly cycle was run against the **live** project inside a
transaction that rolled itself back: open a cycle, assign a KPI, file two
numbers, refuse the manager filing on somebody's behalf, read the tree, score
it, check what is due on a Sunday. That found two more, which are 200 and 201.

Both screens were driven in Chromium against stubbed routes, signed in as a
Branch Manager, with zero page errors — including the case where the routes
answer 404, so the screens say "published but not deployed yet" rather than
inventing a reason.

---

## Still not done

- **Scope enforced in the services, not just the nav.** The per-chair
  navigation is live (FE 18→8, TL 18→9, BM 18→14, Partner 18→15, HR 19→17,
  Admin 21→21), but hiding a screen is not a permission check. `buildScope()`
  runs on every `api`, `ops` and `pack` request and the scope *level* it
  carries is still unused, and nothing reconciles the navigation against the
  endpoints. `ops/routes/mis.ts` and `auto.ts` have not been read for this.
- **A measure set for every seated chair.** The registry reaches 12 of 104
  seated chairs. The monthly model makes that a default rather than the
  answer, and `/perf/measures` falls back to the whole catalogue and says so
  rather than pretending — but a chair with no set still starts its manager
  from a long list.
- **Back-testing the roll-up on dummy months**, so the six-month history has
  something in it before the real months accumulate.
- **The second sign-in door.** A one-time code to the work address, so Google
  is not the only way in. 635 active people, zero password hashes.
- **The automatic escalation at the third strike.** The strikes are counted
  and everybody is told; nothing opens a case. The only case-creating
  function here is `ogl_case_create`, which is about OGL verification and
  means something else.
- **Uploading a document.** `person_document` records what HR has seen. There
  is no file store behind it yet, and the screen says so rather than showing
  a control that does nothing.
- **The repository cannot rebuild the database.** 51 of 106 migration files
  carry no executable SQL — from 134 on they are notes headed `Applied as:`.
  This has now cost time three times: `plb_wd_after`, `working_hours_after`
  and `next_ref` all had to be recovered from the live project rather than
  read from a file. `build/test/README.md` has the one query that fixes it.
