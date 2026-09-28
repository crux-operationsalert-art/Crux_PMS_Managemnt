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

---

# Tab 1 — Performance (`pms`) · audited 2026-09-28

## What the blueprint says this screen is

One route, `pms`, labelled **"Performance & appraisal"**, rendered from two
sections that are both on it — `isPms` (28,439 bytes) and `isAppraisal` (7,197).
**35,636 bytes, 20 buttons, 1 table, 11 loops, 9 fields, one screen, no
sub-tabs.** `isAppraisal:true` is set inside the same `route === 'pms'` branch;
it is not a separate destination.

In order down the page:

| | Section | What it holds |
|---|---|---|
| A | Header | "Performance", a note, and three score chips: **KPIs · weight**, **Attributes · weight**, **Final · out of 10** |
| B | Daily update | Cadence note, filing window and its penalty; a table with **KPI · Monthly target · Achieved · % · Today's count**, each row carrying its category, its cadence and note, who set it, and "achieved of target" |
| C | Anything else about today · optional | A free-text note that counts towards Attributes; an assistant that proposes **Files as** and a **Heading**, with its reason, both overridable; **On your record this month** listing what has already been filed |
| D | Submit daily update | One submission for the whole day, not one per KPI |
| E | Your last fourteen days | Fourteen day cells with a streak note and a legend |
| F | My KPIs · 3 mandatory, 2 optional | Who set them, **Request a KPI change**, per-KPI **Edit this KPI** / **Remove** / **Save**, sub-categories under each with their own target and achieved, **Add a KPI**, **Undo my changes**, and the rule in words: *"Five is the design: three mandatory, two optional."* |
| G | Attributes · everything beyond the KPIs | Each attribute's name, source, weight and score; an **Open note · today** box and **Add to my record** |
| H | KPI change requests · N with HR | The queue: who, their chair, its state, the KPI, from → to, why, who raised it and when, and the action |
| I | My team · targets, tasks and eligibility | Per person: last month, this month, and **Set targets** / **Assign a task** / **Eligibility matrix** |
| J | PMS weighting · Admin and HR | The KPI/Attributes split, the eligibility default when a gate is missed, and what an escalation, warning or appreciation does to a score — **Open weighting** |
| K | Appraisal · this month | Window, basis and clock; **stage**; the self-lock note; KPI, Attributes and Final out of 10; contribution; the evidence list with each item's effect; the gate note and **Ask HR for an exception**; self-evaluation and **Save my self-evaluation**; **Send the review request**; **Accept my score** / **Dispute it**; *"Why should HR reopen your window?"* and **Send the request to HR** |

## What the tool has

**Three screens, not one.** `FAMILY` in `index.html:812` puts three routes under
Performance — `perf` "This month", `pms` "Appraisal", `plb` "Bonus" — a sub-tab
row the blueprint does not have. Two of the three are titled "Performance"
(`index.html:2816` and `:4351`) and the third "Performance & bonus" (`:1839`).
The design's single screen was built three times, in three passes, and never
joined up.

## The difference list

| | Blueprint section | Verdict | Where it is now |
|---|---|---|---|
| A | Header + three score chips | **different** | The numbers exist as a *table* on Bonus ("Your monthly scores": Month, KPI /10, Attributes /10, Monthly score). The three chips at the head of Performance do not exist |
| B | Daily table, 5 columns | **different** | `perf` "Due today" has the KPI name, its cadence and its target — **2 of 5 columns**. No Achieved, no %, no category, no "set by" |
| C | Day note + assistant classification | **missing** | Nowhere. `/attr/propose` exists in the `plb` service and nothing calls it from here |
| D | One "Submit daily update" | **different** | `perf` files one KPI at a time; `pms` has a single "File" for all figures. Neither is the blueprint's single daily submission |
| E | Your last fourteen days | **missing** | Nowhere. `/perf/history` exists and is unused |
| F | My KPIs, with edit, sub-categories, request and undo | **different** | `pms` has "Add a KPI" and a mandatory/optional chip. No "Request a KPI change", no "Edit this KPI", no "Undo my changes", no sub-categories, and it is on a different tab |
| G | Attributes + Open note | **different** | Bonus has "Attributes — how you work · 25% of the monthly score" read-only. No "Open note · today", no "Add to my record" |
| H | KPI change requests with HR | **missing** | Nowhere |
| I | My team: targets, tasks, eligibility | **different** | `perf` team tab does bulk assign and "Carry last month forward". No "Set targets", no "Assign a task", no "Eligibility matrix", no last-month/this-month column |
| J | PMS weighting | **missing** | Nowhere on this screen. `pms_cfg` exists in the database |
| K | Appraisal | **different** | Bonus has Acknowledge, "If you disagree", "Submit a self-evaluation" and "Your result" — framed around the quarterly bonus scheme, not the monthly appraisal. No stage, no evidence list with effects, no "Accept my score", no exception request |

**Four sections missing outright. Seven present but different. None matching.**

Of the blueprint's 20 button labels on this screen, three appear in the tool —
`Save`, `Remove`, `Add a KPI`, and two of those are generic. **Seventeen do
not**: Request a KPI change · Edit this KPI · Undo my changes · Add to my
record · Submit daily update · Set targets · Assign a task · Eligibility
matrix · Open weighting · Ask HR for an exception · Save my self-evaluation ·
Send the review request · Accept my score · Dispute it · Send the request to HR
(and the two whose label the blueprint computes).

## What is behind it, and does work

The screen is the gap, not the engine. The `plb` Edge Function already serves
32 routes for exactly this: `/perf/tree`, `/perf/due`, `/perf/file`,
`/perf/score`, `/perf/history`, `/perf/measures`, `/perf/assign`,
`/perf/assign/bulk`, `/perf/carry`, `/perf/team`, `/self`, `/acknowledge`,
`/dispute` (+ respond, decide, escalate, withdraw), `/attr/propose`,
`/attr/decide`, `/certify`, `/countersign`, `/score`, `/score/lock`,
`/quarter`, `/registry`. The database carries `pms_cfg`, `pms_cap_shadow`,
`plb_payout_factor`, `perf_history` and 173 measure definitions.

So most of section C, E, G, H, J and K is a screen calling endpoints that are
already there — not new engineering underneath.

## Decisions for this tab

| # | Decision | Why |
|---|---|---|
| P1 | Rebuild Performance as **one** screen, in the blueprint's order A→K | The blueprint sets `isAppraisal` inside `route === 'pms'`. Three tabs is not a styling difference, it is a different information architecture |
| P2 | Keep the three existing routes alive as redirects | Links, bookmarks and the mobile bar already point at them; breaking those to match a layout would trade one defect for another |
| P3 | Build every section, including the four missing ones, with honest empty states | A control that is absent and a control that says "nothing yet" are different failures, and only the first is mine |
| P4 | Restore the blueprint's label, **"Performance & appraisal"** | It is the design's word and it describes the merged screen |

## Open questions from this tab

| # | Question | Why it is yours |
|---|---|---|
| P-Q1 | The blueprint's appraisal is **monthly**; the built bonus scheme is **quarterly** with a 10-working-day dispute window | Both are real designs. Which cadence governs the score a person accepts or disputes is a policy call, not a layout one |
| P-Q2 | "Assign a task" — the blueprint shows the button, and nothing behind it says what a task is here | No table in the database answers to it. It may be the Ideathon's sponsor task, or a new thing |

## Status

| | |
|---|---|
| Audited | yes — 11 sections, 20 buttons, element by element |
| Fixed | not yet |
| Next | P1 and P3, in the blueprint's order, shipped through `.github/build-tool.py` |

---

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
| Tabs audited | 1 of 34 — Performance |
| Awaiting | nothing — Performance is audited, the fix is next |

## Change log

| When | What changed | Why |
|---|---|---|
| 2026-09-28 | New SOW; previous one archived | The method changed: whole-tool claims replaced by one screen at a time |
| 2026-09-28 | Blueprint indexed into 34 measured sections | "Not matching the design" cannot be worked on until the design is enumerable |
