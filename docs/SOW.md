# Statement of Work — the tab-by-tab audit against the blueprint

Living document. Updated as decisions are made, not after.

Last updated: 2026-09-28.

Previous SOWs, closed:
* `docs/SOW_2026-09-28_make_the_data_live.md` — load the workbook, place the branches, answer the completion %.
* `docs/SOW_2026-09-27_scope_and_measure_sets.md` — enforce scope in the services; give every seated chair a measure set.

---

## Objective

*"Still not matching the original design. So lets do one tab at a time or one
process at a time."*

Stop making claims about the whole tool. Take one screen, put the blueprint and
the running tool side by side, list every difference, fix what should be fixed,
and record what was deliberately not. Then the next screen. A screen is not
"done" until every element the blueprint has is accounted for — present,
deliberately absent with a reason, or listed as an open question.

## Scope and boundaries

**In scope**

* `Crux App v2.dc.html` — the design blueprint at the repository root, 1,112,870
  bytes, of which **474,875 bytes is template markup** across 34 screen
  sections. This is the authority. Where it and the tool disagree, it is right.
* `index.html` / `app_page` — the running tool.
* The services behind each screen (`ops`, `api`, `crux`) where a screen is
  wrong because the data behind it is wrong.

**Out of scope, and why**

* The prototype's illustrative numbers. The blueprint's sign-in is simulated and
  its figures are invented; the shape is the contract, not the values.
* `docs/Crux Rebuild Blueprint.dc.html` (124 KB) — an earlier, smaller file,
  superseded by v2.
* Re-litigating the completion percentage. It is in the previous SOW.

## Inputs — the index of the design

Every screen in the blueprint is an `<sc-if value="{{ isX }}">` section. This is
all 34 of them, in file order, with what each one actually contains. Counts are
measured, not estimated.

| # | Section | bytes | buttons | tables | loops | fields | Built tool |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | `isSignin` | 2,048 | 5 | 0 | 0 | 0 | sign-in |
| 2 | `isSignup` | 7,206 | 8 | 0 | 5 | 1 | sign-in |
| 3 | `isPassword` | 1,630 | 3 | 0 | 0 | 2 | sign-in |
| 4 | `isActivate` | 3,236 | 2 | 0 | 0 | 6 | sign-in |
| 5 | `isForgot` | 4,186 | 5 | 0 | 1 | 1 | sign-in |
| 6 | `isDesk` | 3,220 | 3 | 0 | 3 | 0 | shell |
| 7 | `isMobile` | 22,043 | 17 | 0 | 11 | 11 | shell |
| 8 | **`isDash`** | 18,813 | 9 | 1 | 8 | 0 | `today` |
| 9 | `isEsc` | 10,281 | 4 | 1 | 6 | 0 | `cases` |
| 10 | **`isOgl`** | 53,401 | 30 | 0 | 26 | 40 | `ogl` |
| 11 | `isOrg` | 46,303 | 19 | 1 | 30 | 3 | `org` (under `people`) |
| 12 | `isAuto` | 16,356 | 10 | 0 | 9 | 7 | `auto` |
| 13 | `isPms` | 28,439 | 14 | 1 | 10 | 7 | `perf` |
| 14 | `isProfile` | 3,516 | 3 | 0 | 3 | 0 | `profile` |
| 15 | `isVisits` | 5,311 | 3 | 1 | 2 | 0 | `visits` |
| 16 | `isIdeathon` | 3,760 | 2 | 0 | 3 | 0 | `ideas` |
| 17 | `isHr` | 4,878 | 1 | 1 | 3 | 0 | `hr` |
| 18 | `isAppraisal` | 7,197 | 6 | 0 | 1 | 2 | `pms` (under `perf`) |
| 19 | `isHRHere` | 20,459 | 18 | 0 | 12 | 3 | `hr` |
| 20 | `isAudit` | 3,702 | 1 | 0 | 2 | 1 | `history` |
| 21 | `isHiring` | 12,087 | 8 | 0 | 6 | 2 | `hiring` |
| 22 | `isMsg` | 6,268 | 5 | 0 | 2 | 0 | `mail` |
| 23 | `isJoin` | 7,564 | 5 | 0 | 4 | 0 | `joining` |
| 24 | `isClients` | 23,967 | 13 | 1 | 8 | 4 | `clients` |
| 25 | `isPeople` | 16,564 | 8 | 0 | 7 | 18 | `people` |
| 26 | `isPenalties` | 9,205 | 7 | 1 | 4 | 0 | `penalties` |
| 27 | `isAccess` | 8,842 | 7 | 0 | 5 | 1 | `access` (under `reports`) |
| 28 | **`isMis`** | 48,009 | 27 | 5 | 23 | 0 | `mis` (under `reports`) |
| 29 | `isTen` | 9,598 | 3 | 1 | 5 | 0 | `tenday` (under `reports`) |
| 30 | `isSetup` | 29,619 | 17 | 4 | 12 | 0 | `data` |
| 31 | `isCoverage` | 8,034 | 4 | 2 | 3 | 0 | `coverage` |
| 32 | `isRates` | 7,957 | 5 | 1 | 2 | 0 | `rates` (under `reports`) |
| 33 | `isReports` | 1,822 | 1 | 0 | 1 | 0 | `reports` |
| 34 | `isConfig` | 12,572 | 6 | 0 | 5 | 6 | `config` |
| | **total** | **474,875** | **285** | **21** | **224** | **115** | |

## What already matches

Checked first, so the audit does not start by re-proving it:

* **All 20 navigation tabs exist**, under the right keys. The blueprint's keys
  and the tool's differ in spelling only — `dash`/`today`, `escalations`/`cases`,
  `pms`/`perf`, `ideathon`/`ideas`, `join`/`joining`, `audit`/`history`,
  `msg`/`mail`, `setup`/`data`.
* **The grouping matches**: Ideathon alone and first, then *Mine*
  (Dashboard, My profile, Performance, Visits & claims), *Work* (OGL Assignment,
  Escalations, Clients, My team & structure), *Company* (the other eleven).
* **The colour and button contract** is already measured and recorded in
  `docs/DESIGN-CONTRACT.md`.

Two label differences found on the first pass, both in the tool's favour or
neutral — held for the relevant tab rather than changed here:

| key | blueprint | tool |
|---|---|---|
| `pms` | Performance & appraisal | Performance |
| `coverage` | Coverage & handlers | Places, coverage & owners |

## Methodology — what "audited" means for one tab

For each tab, in this order:

1. **Extract** the blueprint section verbatim: every button label, every column
   heading, every loop, every field, every empty-state sentence.
2. **Extract** the same from `index.html` for the matching route.
3. **Diff them element by element** and classify each difference:
   * *missing* — the blueprint has it, the tool does not;
   * *extra* — the tool has it, the blueprint does not;
   * *different* — both have it, and they disagree;
   * *deliberate* — a difference with a reason, recorded here.
4. **Check the data path**: a control that exists but reads an empty table is
   not built. Every list is run against the live database.
5. **Fix**, then **re-diff**, then record the counts.

A tab is closed when the difference list is empty or every remaining line has a
reason next to it.

## Deliverables

One section per tab, appended below as each is closed: what differed, what was
changed, what was left and why, and the re-measured counts.

## Assumptions

* The blueprint is the contract for *shape*: which controls exist, what they are
  called, what columns a table has, what a screen says when it has nothing to
  show. It is not the contract for its own invented numbers.
* Where the blueprint shows a control the live data cannot yet feed, the control
  is still built and shows its own empty state. A missing control and an honest
  empty state are different failures, and only the first is mine.

## Risks and known limitations

* **475 KB of markup across 34 sections.** At one tab per pass this is real
  work; the index above exists so progress is countable rather than felt.
* **`app_page` is the tool.** Every change ships through
  `.github/build-tool.py`, whose patches assert exact occurrence counts. A patch
  whose anchor has moved fails loudly rather than silently — which is the
  intent, but it means edits land in the order the patches run.
* **`api` cannot be assumed redeployable** (108 KB, untested). A screen whose fix
  needs an `api` change carries that risk.

## Status

| | |
|---|---|
| Index of the design | **built — 34 sections, 474,875 bytes, counted** |
| Tab mapping | **confirmed — all 20 routes present** |
| Tabs audited | 0 of 34 |
| Awaiting | which tab to open first |

## Change log

| When | What changed | Why |
|---|---|---|
| 2026-09-28 | New SOW; previous one archived | The method changed: whole-tool claims replaced by one screen at a time |
| 2026-09-28 | Blueprint indexed into 34 measured sections | "Not matching the design" cannot be worked on until the design is enumerable |
