# Status — 27 Sep, late

Two large pieces landed this session: the **monthly PMS** and the **monthly
escalation matrix**. Both are written, parse-checked, driven in a browser, and
committed. Neither is fully live: the database half is partly applied and the
two Edge Functions have not been redeployed, because the Supabase MCP approval
gate shut partway through and has stayed shut.

What follows is exactly what is applied, what is not, and the order to finish
in. Nothing below is speculative — every file named exists in the repository
and every check named was actually run.

---

## Applied to the database

| Migration | What it adds | State |
|---|---|---|
| `190_the_monthly_kpi_cycle.sql` | `perf_cycle` — the period and its two windows | **applied** |
| `191_assigning_a_kpi_for_a_month.sql` | `perf_assignment`, its indexes, the `cadence` column discovered from `kpi_definition`, and the `perf_assignment_edges` trigger | **applied** (as 191, 191b, 191c) |
| `192_filing_a_number.sql` | `perf_entry`, unique on (assignment, day), and the trigger refusing an entry on a measure that has parts | **applied** |
| `193_how_a_number_climbs.sql` | `perf_accrual_kind`, `perf_value`, `perf_due` | **applied** (as 193a/b/c) |

`perf_value()` is where the one rule that makes a roll-up correct lives:
counts and rupees accumulate, a percentage or a score is a level. It applies
that rule at all three joins — across days, across a person's own splits, and
across a team — because getting it wrong at any one of them is how 93% and
88% become 286%.

## Not applied — the gate shut here

| Migration | What it adds |
|---|---|
| `194_setting_and_filing.sql` | `perf_cycle_open`, `perf_may_set`, `perf_assign`, `perf_assign_bulk`, `perf_carry_forward`, `perf_file` |
| `195_what_a_manager_sees.sql` | `perf_node`, `perf_tree`, `perf_history`, `perf_kpi_score` |
| `196_the_matrix_that_goes_out.sql` | `matrix_dispatch`, `matrix_scope_branches`, `matrix_client_view`, `matrix_pack`, `matrix_month`, `matrix_send` |
| `197_the_reminder_on_the_cadence.sql` | a corrected `perf_due` on the working-day clock, `perf_roll_forward`, `perf_reminder_sweep`, the `PERF_REMINDERS` job |
| `198_the_matrix_nudge.sql` | `matrix_nudge_sweep`, the `MATRIX_NUDGE` job. Depends on 196 |
| `199_a_split_without_an_id_is_still_a_split.sql` | replaces two unique indexes on `perf_assignment` that contradicted the table's own CHECK |

**All ten now run, and 87 assertions pass against them** — `./build/test/run.sh`
builds a throwaway Postgres 16, applies 190–199 and exercises them. That run
found five defects that reading had not, including one that would have made
`perf_file` return a 500 and one that would have refused a legitimate split.
`build/test/README.md` lists them.

Apply them in that order. 194 and 195 are already split into chunks small
enough for the gate in the file itself; 196 is three sections separated by
comment rules and can be applied in three calls if a whole-file call is
refused.

**One thing to check on 194.** `perf_cycle_open` calls
`plb_wd_after(s, 5, null)` — the working-day helper from migration 168 — and
the call was written from the live signature, but the gate closed before it
could be re-read. If 194 fails on an ambiguous or undefined function, that
line is why, and the fix is a cast on the third argument.

## Not deployed

| Function | Change | Checked |
|---|---|---|
| `plb` → v5 | 12 `/perf/*` routes in `routes/plb.ts` | parses clean |
| `ops` → v7 | `routes/pack.ts` mounted at `/api/pack`, four routes | parses clean |

`api` is at the size an Edge Function deploy will carry and takes neither.
That is why the matrix despatch routes are on `ops` rather than beside the
rest of the matrix.

## Not published

The front end is applied at publish time by `.github/build-tool.py`, which is
the lever that works while Supabase is unreachable — GitHub Pages serves
`index.html`, and the workflow rebuilds it from `app_page` and re-applies
every patch on the way past. Seven patches now; the first five detect
themselves as already in `app_page` and skip.

| Patch | What it does |
|---|---|
| 6. one Performance screen | folds the two Performance nav entries into one, keeps `#pms` and `#plb` as sub-tabs, and splices in `build/app/screen-perf.js` |
| 7. the matrix that goes out | the dashboard line, the month section on `#matrix`, and `build/app/screen-matrix-month.js` |

Pushing any of `.github/workflows/publish-tool.yml`, `.github/tool-shim.html`,
`.github/build-tool.py` or `.github/app-page.sha` triggers the publish. The
last two commits touched `build-tool.py`, so the next push publishes both
screens — **and they will call routes that are not deployed yet.** Deploy
`plb` and `ops` first, or the Performance screen will report the period as
unopened and the matrix section will be empty.

---

## Verified without the database

Both screens were driven in Chromium against stubbed routes, signed in as a
Branch Manager.

**Performance** — one nav entry, three sub-tabs (This month / Appraisal /
Bonus); the due-today card; the tree expanding from two rows to five across a
split and a team contribution; the team face appearing because `/perf/team`
returned people; the assignment form with its cadence list and its "climbs
into" list both built from what came back rather than from a guess. Zero page
errors.

**Escalation matrix** — the dashboard line; the client table with one client
sent and one not; the pack opening with the primary and head-office contacts
ticked and the CC not; the held-back branch named; five levels a branch; and
the send posting exactly the two addresses that were ticked. Zero page errors.

Three things that only showed up on screen, all now fixed in the patch:

- `button{min-height:46px}` and `button:hover{background:var(--blue)}` in the
  base sheet also catch a disclosure triangle, and `button:hover` outranks a
  plain class — so the "+" turned into a 46px navy block mid-click.
- `input{width:100%;min-height:44px}` also catches a checkbox. Every tick in
  the tool is a 44px square for this reason.
- `.chip` paints itself with `var(--ink2)`, which the stylesheet uses once and
  defines nowhere, so the colour is inherited — white on white inside a
  selected tab. Still undefined everywhere else, where chips happen to sit on
  light backgrounds and inherit something readable by luck.

---

## Still not done

- **Scope enforced in the services, not just the nav.** The per-chair
  navigation is live and the audit measured it (FE 18→8, TL 18→9, BM 18→14,
  Partner 18→15, HR 19→17, Admin 21→21), but hiding a screen is not a
  permission check. `buildScope()` runs on every `api` and `ops` request and
  the scope *level* it carries is still unused, and nothing reconciles the
  navigation against the endpoints. `ops/routes/mis.ts` and `auto.ts` have
  not been read for this.
- **A measure set for every seated chair.** The registry reaches 12 of 104
  seated chairs. The monthly model makes that a default rather than the
  answer — a manager sets the measures each month — but a chair with no set
  still starts its manager from a blank list, and `/perf/measures` falls back
  to the whole catalogue and says so rather than pretending.
- **Reminders on the cadence.** `perf_due()` knows what is owed today; nothing
  yet puts that in the outbox on the morning it is owed.
- **The second sign-in door.** A one-time code to the work address, so Google
  is not the only way in. 635 active people, zero password hashes.
- **Back-testing the roll-up on dummy months.** The owner asked for deletable
  sample months so the six-month history has something in it before the real
  months accumulate.
