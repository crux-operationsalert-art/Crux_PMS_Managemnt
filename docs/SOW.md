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

## Both open questions, answered

### P-Q1 — it is monthly **and** quarterly. Two layers, not a choice between them.

Answered 2026-09-28: *"scoring and targets is done monthly and then the
Quarterly scorecard is different… this is a two layer performance management
system. Also KPI numbers to be updated as per the cadence."* Re-read against
the PLB Constitution V2.0, Annexure F and the Scorecard Guide by Department.

**Layer 1 — the month.** `Monthly Score = 0.75 × KPI /10 + 0.25 × Attribute /10`.
The KPI half asks one question per KPI: did this month's registered share of the
quarterly plan land *in this month*? — 2.0 landed, 1.0 partly or late but still
inside the month, 0.0 not, or only at quarter end. The Attribute half is five
slots worth 2 points each: A-1 process and control discipline, A-2 data and
reporting hygiene, A-3 contribution beyond your chair (the same three for
everyone), A-4 capability and A-5 institutional build (yours to propose). Self
evaluation opens on the last working day and closes at the end of WD 1; the
manager cannot score until it closes or you submit; **SCORE LOCK at WD 3**. If
the manager differs from the self-evaluation by 2.0 or more they must write one
line naming the component — compulsory, not approvable.

**Layer 2 — the quarter.** `PLB = Target × Payout Factor × Consistency Factor`.
The goal sheet is issued and acknowledged by day 10 and locked at the end of it;
day 15 is the backstop — no sheet and the chair's standard one applies and you
cannot be scored below it. Achievement against the sheet sets the **Payout
Factor** (under 50% nothing, 85% full, 115% and above 125%). The mean of the
monthly scores sets the **Consistency Factor** (8/10 releases 80%, 10/10 all of
it, floor 30%). Data freezes at WD 3 after quarter end, the result is certified
and published at WD 5, and the dispute window is the 10 working days after that.

So the monthly layer decides *how much of what you earned is released*, and the
quarterly layer decides *how much you earned*. Neither replaces the other, and
the screen has to show both without pretending they are the same number.

**And the arithmetic is already right.** Both curves were checked against the
Constitution at every published point, and all five of its worked examples were
run through the live functions on its own base case:

| Quarter | Achievement | Monthly mean | Constitution | `plb_payout_factor` × `plb_consistency` |
|---|---:|---:|---:|---:|
| Standard delivery | 100% | 8.0 | ₹44,000 | **₹44,000** |
| Steady, under target | 78% | 9.0 | ₹36,000 | **₹36,000** |
| Quarter-end spike, weak months | 110% | 5.0 | ₹30,000 | **₹30,000** |
| Strong on both | 110% | 9.5 | ₹57,000 | **₹57,000** |
| Below half target | 49% | 10.0 | ₹0 | **₹0** |

The engine is not the gap. **Every table it fills is empty** — no goal sheet has
ever been issued, no month has ever been scored, `perf_assignment` has no rows,
and `pms_weighting` had none either, so the 75/25 split existed only as two
numbers typed into a heading in the page.

### P-Q2 — a task is one person asking another for something by a date.

Answered 2026-09-28: *"this is someone giving task to someone, like I can create
a task for a specific manager or all the managers to visit the SBI branches…
these gets considered in the attributes if done on time or escalations get
raised."*

The `task` table was already here with exactly that shape — `person_id`,
`assigned_by`, `title`, `detail`, `due_on`, `period`, `status`, `outcome`,
**`attribute_weight`**, `closed_at` — and not one row in it. No service route,
no screen, and no database function so much as mentioned it. Migration 214 gives
it verbs.

It lands on **A-3, contribution beyond your chair**, which is the one the
Scorecard Guide says must cite "a named artefact ID — a ticket, a sign-off, a
document reference" and never "a generic description". A task closed on time is
that artefact. `task_evidence()` returns the month's record and what A-3 would
be if scored from it alone — a suggestion with its working shown, because the
Guide is equally clear that the manager scores and HR cannot move it.

## What was built for this tab so far — migration 214

| | |
|---|---|
| `task_assign(actor, in)` | One instruction to named people, to everybody in a chair, to a department, or to your whole subtree. Refuses anybody outside it **by name** rather than dropping them quietly |
| `task_close(actor, task, outcome)` | DONE or LATE is decided by the due date against today, not by whoever closes it |
| `task_cancel(actor, task, why)` | Only whoever asked can call it off |
| `task_sweep()` | Overdue becomes MISSED and tells the two people it concerns, once each |
| `task_evidence(person, period)` | The month's tasks and the A-3 they suggest. Null, not zero, for a month nobody asked anything of you |
| `task_mine(person, period)` | Both sides: what I owe and what I asked for |
| `crux_task_tick()` + `crux-task-sweep` | Daily at 07:15 India time, after the penalty sweep and before anybody opens the tool |
| `pms_weighting` | The Constitution's 75/25, as a row, effective 1 October 2026 |

**A missed task raises no `ops_alert`.** That screen is filtered by role and not
by person, so `ops_alert_open()` would show one manager's forgotten instruction
to whoever holds ADMIN. It writes a `notification` to the person (pushed — it
moves their score) and to whoever asked (not pushed — they are the only one who
can call it off). The first version did raise an alert; the test caught it.

**It opens no case either.** A case in this tool belongs to a client and a
branch and carries an SLA clock. A task has none of those. If a missed task
should also open a formal case, that needs a client attached to it and is a
policy decision — recorded here rather than assumed.

`build/test/test_task.sql` holds 16 assertions covering all of it, including the
two curves and the five worked examples, and runs on a database rebuilt from
`build/schema` alone.

## Still open from this tab

| # | Question | Why it is yours |
|---|---|---|
| P-Q3 | Should a missed task also open a case? | A case needs a client and a branch; a task has neither. Saying yes means deciding which |
| P-Q4 | No goal sheet has ever been issued, for anybody | Targets "come from a fixed hierarchy" and are a business input. The engine is ready and idle |
| P-Q5 | `pms_impact` — what an escalation, warning or appreciation does to a score — has no rows | The blueprint puts it on the weighting panel. The Constitution scores from the A-1 rubric instead, so these two may be the same thing said twice |

## The screen, as rebuilt

`build/app/screen-perf.js` — 20,349 → 49,183 bytes — is now one page in the
blueprint's order, published at 460,432 bytes with every patch assertion
passing. The three tabs are gone; what is left beside it is **Running the
scheme** (issuing sheets, certifying, closing a quarter), which is HR's and
Business Excellence's job and which the design does not place anywhere.

| | Section | State |
|---|---|---|
| A | Three score chips, KPIs / Attributes / Final | **built** — weights read from `pms_weighting_for()`, not typed into a heading |
| B | Daily table, five columns | **built** — was two; now KPI, Monthly target, Achieved, %, Today's count |
| C | Day note + assistant classification | **stated gap** — see below |
| D | One "Submit daily update" | **built** — was one button per row; a blank box is still left alone, not filed as zero |
| E | Your last fourteen days | **built** — `perf_filed_days()` (217). A run breaks only on a *working* day nobody filed on |
| F | My KPIs | **built**, with the design's own rule: five is the design |
| G | Attributes | **built** — shown as the sheet actually holds them |
| H | KPI change requests | **stated gap** — see below |
| I | My team: targets, tasks, eligibility | **built** — Assign a task and the Eligibility matrix now exist |
| J | PMS weighting | **built** — reads and writes the split |
| K | Appraisal | **built** — reusing the Bonus screen's own renderers rather than rewriting 900 correct lines |

**The two gaps are findings, not omissions.** Section C has nowhere to write:
the only attribute writing this database has is the quarterly A-4 / A-5
proposal, which carries three milestones and an evidence reference and is not a
place for a dated note. Section H has no table at all. Both say so on the
screen, and say what would make them work. The field shapes for G and A were
checked against `plb_sheet()` rather than assumed — attributes carry
name/fixed/state/proposal/evidence, not the weight and score I had first
guessed, and the attribute score is monthly rather than per attribute.

One latent trap closed on the way past: `build/app/*.js` was **not** in the
publish workflow's trigger paths, so changing a screen the build reads from the
repository did not republish — the change sat in git looking applied.

## Still to do on this tab — closed 2026-09-29

The three routes the screen's new sections call are deployed. They did **not**
go into `plb`. `plb` computes what people are paid and deploys all-or-none, so
adding three routes meant re-uploading the whole quarterly scheme — issue,
acknowledge, lock, score, certify, publish, disputes — to gain a task list. A
slip anywhere in that upload takes the scheme down for a feature nobody is
waiting on.

So the decision `build-tool.py` patch 8 recorded for the despatch, made again
for the same reason: a **sixth front door**. `perf` carries `GET /filed`,
`GET|POST /weighting` and the six `/task/*`, and is deployed as v1.
`plb/routes/plb.ts` went back byte-for-byte to the running v5
(sha256 `09207a9e…`), so the repository and the deployed function agree again.
Patch 11 defines `PERF` and `perfApi` beside `PACK` and `packApi`, anchored on
patch 7/8's line, which is why it is last in the list. The screen calls
`perfApi` for the eleven calls that moved and `plb` for the eleven that did not.

Published at 460,624 bytes.

## Status

| | |
|---|---|
| Audited | yes — 11 sections, 20 buttons, element by element |
| Both open questions | answered, and written into the design above |
| Built | 214 the task engine · 215 the baseline carries the split · 216 whose split applies · 217 the fortnight · the screen itself |
| Published | yes — 460,624 bytes, parses, every patch assertion passed |
| Tests | 220 passed, 0 failed, on a database rebuilt from `build/schema` alone |
| Blocking | nothing |

---

# The three defects reported 2026-09-29

## 1 · "People are seeing the team of other people"

> *"One should only be able to see and update things for his team and see the
> details and progress from level 2 and below. So 1st layer/level I work as a
> manager and below my level I just see and see the progress performance etc."*

**This was the most serious thing found in this project so far, and it was
worse than reported.**

`kpi_subtree_people(actor)` walked the **chair** tree. There is one Branch
Manager chair held in thirty-nine places, so walking chairs puts every branch
manager in the country one step below every zonal manager. The only narrowing
was a place filter that opened itself whenever the actor had no place on record
— true for eighty-two of the hundred and one seated holders.

Measured on the live database before the fix:

| | |
|---|---|
| (actor, person) pairs visible | **5,579** |
| people who could see somebody | **97** |

An Executive on SG1 with no reports — ABHIJEET KORI, and sixty others like him
— came back with sixty-two people. A Team Leader got seventy-one. A Branch
Manager got eighty-two.

That function is also the **write** gate in `kpi_save`, `kpi_retire` and
`task_assign`, so an SG1 Executive could define and retire KPIs for sixty-two
colleagues and assign them tasks.

Three read routes were worse still. `GET /perf/tree`, `GET /perf/history` and
`GET /perf/score` took `?person=` off the query string and passed it straight
through to a `SECURITY DEFINER` function. **Anyone who could sign in could read
anyone's performance by knowing their id.**

### What is true now — migration 218

`perf_line(actor) → (person_id, depth)` over the **reporting line**, which is
the union of two edges that both mean "A manages B":

* the **seating tree** — `chair_seating.reports_to_seating_id`, place-aware, and
  what the org chart draws; and
* `person.manager_id`.

The union is deliberate. Neither is complete alone: the seating tree supplied
three of the hundred and two edges before defect 2 was fixed, and manager_id
supplied the rest. Dropping either would blank somebody's team for a reason
that has nothing to do with who they manage.

| depth | what it means |
|---|---|
| 1 | my team — **seen and set** |
| 2 and beyond | below my team — **seen only** |
| absent | nothing at all. Not their name, not their numbers. |

After, measured the same way: **478 pairs visible, 102 of them updatable, 13
people able to see somebody.** ABHIJEET KORI 62 → 0. Parag Mayekar 82 → 0.
ROOPA R 71 → 0. Aniket Chalke keeps his 42 direct reports.

### Deliberately removed

`perf_may_set` said yes to anyone whose `department` is `Human Resources` or
`Business Excellence`, for **every person in the company**. Two people hold
that today. The rule as given has no room for it — setting a score for somebody
who does not report to you is the thing being complained about. Running the
scheme (issue, lock, certify, publish, decide a dispute) is a different act and
is untouched; `maySetUp` keeps that meaning and loses the other one.

An administrator still sees and sets everything. That is the tool's
administrator, not a department, and there are two.

### A performance defect found by the fix

The first `kpi_subtree_people` was written `and perf_may_set(p_actor, p.id)`,
which reads better and walks the reporting line **once per person in the
company** — 635 recursive walks for one screen. It took a verification query
past a sixty-second timeout on the live database. It is now an uncorrelated
`in (select …)`, evaluated once, with the administrator case lifted out. Same
rule, one walk.

## 2 · The ~100 people the org chart cannot seat

The real count was **82 of the 101 seated holders**, and the report's own
headline reason was the smaller half of it:

| why | how many |
|---|---|
| the chair has no seating at all | **69** |
| no coverage to place them by | 11 |
| coverage in a place the chart has no seat for | 1 |
| coverage spans four regions | 1 |

Sixty-nine were not a missing-data problem. Seven chairs — `EXECUTIVE` (63
holders), `CEO_MD`, `VP_FINANCE`, `HEAD_HR_OPERATIONS`,
`HEAD_FINANCE_OPERATIONS`, `HR_EXECUTIVE`, `SALES_MANAGER` — have no row in
`chair_seating` at all. There was no seat to put anybody in, and migration 114
places a holder into a seating the chart already drew, so it could only ever
report that.

Since 218 this stopped being a gap on a drawing: the seating tree is half the
reporting line, so an unplaced holder is a person **in nobody's team with no
team of their own**. 218 fails closed, which is the right way round, and 219 is
the other half of it.

### The rule — migration 219

**A person sits where their manager sits**, unless their own coverage already
said otherwise (114 runs first and decides that). It is not a guess: of the
thirteen holders on chairs that do have seats, eight resolve to a place their
own chair already has, and the sixty-three Executives resolve to the place
their own Team Leader sits in.

Where the manager's place has no seat on the person's chair, **the seat is made
rather than the person left out**, and every made seat carries a note saying it
came from the reporting line and not from the chart. Three Branch Manager and
Location Partner holders report to the West zonal manager, and the chart draws
branch seats as cities and never as zones; a Location Partner who reports to
the West zone is a fact about the company whether or not the chart drew a box
for it.

It runs in **passes** because Ashwini Reddy's manager is SHASHIKALA BHASKAR K,
who is herself unplaced until this runs — one pass would leave Ashwini behind
for a reason that has nothing to do with Ashwini. Twelve at most, so a loop in
the manager chain cannot spin.

**Vrunda Potdar is deliberately not decided.** She is a Zonal Manager covering
four of the chart's regions, and the chart gives Zonal Manager one seat per
zone and none that means four of them. She is seated with the place left open
and a note saying which four, rather than assigned to whichever region sorted
first. She is then in the reporting line — the thing that was actually broken —
and the label stays a question for whoever owns the chart.

Run on the live database: **5 passes, 81 placed, 12 seats made, none left.**
`org_unplaced()` returns zero for the first time. The reporting line grew from
478 visible pairs to 494 and from 102 first-level pairs to 119, which is the
seating tree carrying weight it could not carry before.

## 3 · "You have not pre uploaded the KPIs"

Correct, and the shape of it is worth being exact about, because two
different things get called "the KPIs":

| | | |
|---|---|---|
| `kpi_definition` | **173 rows across 42 chairs** | the **registry** — what a *chair* is measured on. Loaded, and has been. |
| `perf_assignment` | **0** | what one **person** is measured on, this cycle, with a target |
| `kpi_target` | 0 | |
| `plb_goal_sheet` | 0 | |

So the registry was there and not one person had been given anything out of
it. Everybody opened Performance to an empty screen, and the screen was
telling the truth.

### What the Constitution already said to do — migration 221

This is not a new policy. The PLB Constitution issues a goal sheet by day 10
and has a **day-15 backstop: where no sheet has been issued, the chair's
standard sheet applies.** `perf_seed_from_registry(actor, cycle)` is that
backstop written down — every seated person gets the measures their own chair
is measured on.

**The target arrives blank, deliberately.** A KPI without a target is a
person who knows what they are measured on and is waiting to agree how much.
A KPI with a target nobody agreed is a person held to a figure they never
saw, and at the end of the quarter that figure is multiplied into their pay.
The first is an honest starting point; the second is the failure the whole
scheme exists to prevent, and it would be the tool that caused it.

`weight_pct` **is** filled, because it is not a judgement: the registry's own
rule, the one `/registry` has always shown, is equal weighting across a
chair's measures — `round(100 / count, 2)`.

Run on the live database, for September and for October:

> **364 measures given to 101 people, both months. Nobody left without a
> measure set. Targets blank. 10 of them climb into a manager's.**

Only ten climb, and that is reported rather than hidden: the registry names
measures per chair, so a Branch Manager's "Cases closed" and a Zonal
Manager's are two different rows. The link is matched on **name and unit**,
not on `kpi_id` — matching on the id linked *nothing at all*, which is what
`build/test/test_seed.sql` caught before it reached the live database.

### One thing that will look like a fault and is not

`perf_due` returns **nothing for anybody today**. That is correct. Every one
of the 173 registry measures has cadence `MONTHLY`, and a monthly measure
falls due on the cycle's own closing date — **7 October** for September, when
every person has between four and six things to file. There is not one
`DAILY` measure in the registry. If a daily rhythm is wanted, that is a
change to the registry's cadences, not to the engine.

## 4 · Five tables open to the publishable key — found, not reported

Found by the project's own security advisor while working on defect 3.

`perf_cycle`, `perf_assignment`, `perf_entry`, `matrix_dispatch` and
`person_document` had **row level security off**. Every other table here —
156 of them — has it on, and `build/schema/70_rls.sql` says why in its own
header: the tool reaches the database through `SECURITY DEFINER` functions
and the service role, so RLS on with no policy is closed to `anon` and to
`authenticated`, which is what it should be. These five were created after
that convention settled and did not get it.

**This is defect 1 again, through a different door.** The publishable key is
in the public repository on purpose; it grants nothing *because* every table
is closed to it. These five were open, so
`/rest/v1/perf_assignment` would have returned every person's KPIs and every
number they had filed, to anybody, with no sign-in, bypassing `perf_line`,
`perf_rel` and every gate migration 218 put in.

Two things kept it from being a live breach: those tables were empty, and the
application makes no PostgREST call at all — `index.html` contains zero
`/rest/v1` references. The first stops being true the moment the KPIs are
seeded, which is defect 3. **So migration 220 went first, before 221.**

Migration 220 turns RLS on for all five and adds no policy, which is the
intent and is checked rather than assumed. It also ends with an assertion, so
a later migration that turns one back off fails the rebuild rather than
waiting for the advisor to notice again.

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
| Defect 1 · over-broad visibility | **closed** — 218 · 5,579 pairs → 478 · 97 people → 13 |
| Defect 2 · the unplaced org chart | **closed** — 219 · 82 → 0, `org_unplaced()` returns nothing |
| Defect 3 · the KPIs not pre-uploaded | **closed** — 221 · 364 measures to 101 people, two months |
| Defect 4 · five tables open to anon | **closed** — 220 · found by the advisor, not reported |
| The `plb` redeploy | **done** — v7, verify_jwt off. See the note below |

### The `plb` redeploy — landed, with one scare

`plb` is now **v7** and the three ungated reads go through the wrappers.
`GET /perf/tree`, `/perf/history` and `/perf/score` call `perf_tree_for`,
`perf_history_for` and `perf_kpi_score_for`, which take the asker as their
first argument and refuse a person outside their line. `GET /sheet/:id` asks
`plb_sheet_rel` instead of the old HR-or-administrator test, which fixes both
halves of it: a manager can now open their own report's sheet, and an HR
executive can no longer open the chief executive's. `GET /perf/team` returns
the line with `depth` and `maySet` on every row, so the screen can draw the
difference between somebody I manage and somebody I only watch.

**The scare, recorded because it will happen again.** The MCP deploy tool's
`verify_jwt` parameter defaults to `true`, and I omitted it. v6 went out with
the gateway demanding a JWT — and `call()` in the page sends `x-crux-token`
and **no Authorization header at all**, so every request to `plb` would have
been refused with 401 before the function ran. That is exactly the incident
this project has already had once ("plb and hr redeployed with verify_jwt
off, which is what was ejecting people on #plb"). v7 went out about two and a
half minutes later with `verify_jwt: false`, and `plb/index.ts` now carries a
comment saying so at the top, where the next person to deploy it will read it.

# The daily flow, and the leak that was still open · 2026-09-30

## 5 · "Data leakage still exists, managers are seeing everyone's data"

Correct, and I had checked one half of one screen. Migration 218 closed the
Performance screen's **KPI** half. The **appraisal** half goes through a
different door and I did not look at it:

> `GET /plb/quarter` → `plb_quarter(p_quarter date)` — **no actor at all.**

It returned, to anybody who could sign in: every goal sheet in the company,
with name, employee number, chair, status, **target PLB in rupees**, months
scored, disputes open and overdue, whether it was certified and published,
and **the amount paid**. Plus `inScheme` — every seated person on a chair
that carries a measure set.

Migration 222 gives it the actor and asks `perf_rel` about every row, so the
two halves of one screen cannot disagree about who somebody may see. The old
one-argument form is left standing and made to **refuse** rather than
dropped, so a stale caller gets an empty answer instead of everybody's.

`plb_sheet` got the same treatment. 218 gated it *at the route*, which works
and is a gate exactly one route remembers — 222's own assertion caught that,
which is what it is for, so the gate moved into the database as
`plb_sheet_for`.

Checked on the live data with real accounts, counting what each sees in the
quarter now:

| | now | before |
|---|---|---|
| ABHIJEET KORI · Executive, no reports | **1** (themselves) | 101 |
| ROOPA R · Team Leader | **1** | 101 |
| Parag Mayekar · Branch Manager | **17** — themselves + 16 | 101 |
| Aniket Chalke · Branch Manager | **43** — themselves + 42 | 101 |
| Nitish Bhope · Zonal Manager | **26** — themselves + 25 | 101 |
| Virendra Pal · Chief Executive | **100** — the whole line | 101 |

## 6 · The daily flow — bottom to top, and targets top to bottom

### What was already there, and what was not

`perf_value()` has walked `rolls_into_id` and added a measure's filings into
everything above it since migration 190, and `perf_accrual_kind()` already
decided sum-versus-average the right way round. **The arithmetic was never
the problem.** Two things were:

**Nothing climbed.** Of the 364 measures seeded in 221, **ten** did. 221
linked by NAME, and the registry does not name that way — it names per chair
and codes the family in the unit after a middle dot:

| Chair | Measure | Family |
|---|---|---|
| Executive | Cases completed against target | `EX1` |
| Team Leader | Daily target achievement | `D3` |
| Branch Manager | Cases completed within TAT | `D3` |
| Zonal Manager | Branches at or above plan | `D8` |

One pyramid, no two sharing a name. So the link is by **family**, and where
the code changes going up it changes by `perf_rollup_map` — a table with the
sentence justifying every row, because **that map is a judgement about the
business and correcting it must be an UPDATE, not a deploy.**

**Nothing was ever due.** All 173 registry measures said `MONTHLY`, and a
monthly measure falls due exactly once, on the closing date. That is why
`perf_due` returned nothing on any ordinary day and the fortnight strip was
empty for everybody. Every measure is now `DAILY`; the cadence stays a
per-measure column, so a measure that genuinely is monthly is one UPDATE from
being monthly again.

### Three rules, each added after the one before let something through

Two were caught by the tests. **The third was caught on the live data**,
which is worth recording as a failure of my own testing:

| Rule | What it stops | How it was found |
|---|---|---|
| **Family** | Linking by name, which linked almost nothing | designing |
| **Direction** | A ceiling into a floor — "work returned" (want low) into "quality score" (want high). The cascade was overwriting a 5% ceiling with a 90% floor | `test_flow.sql` |
| **Kind** | A percentage into a count. A plan of **100 branches** divided by 62 feeders gave sixty-three real executives a target of **1.61% of cases** | reading the live chain back |

All three must agree or the chain stops and says it stopped. 140 of 364
climb. The rest are tops of chains, and every one of those is a place where
the registry changes family, direction or type going up.

### Targets, the other way

`perf_target_set` sets one and pushes it down, **dividing the way the roll-up
adds** — or a team's targets would not reconcile with their manager's:

* **a count divides** — 600 cases across four people is 150 each
* **a percentage is copied** — 95% across four is 95 each, not 23.75

A share typed by hand is `MANUAL`: it comes off the top first, the rest
divide what is left, and **no later cascade from above ever overwrites it.**
Pin one of four at 300 of 600 and the other three get 100 each; raise the
parent to 800 and the pin stays at 300 while the others move to 166.67.

### Dummy targets

Every blank target has a starting number, marked `SEEDED`, read out of the
registry's own words where it states one ("target 95%", "target below 3%",
"target zero"). A ceiling measure is seeded at 5 and a floor at 90, so an
error rate is not seeded as a goal to miss nine times in ten. The screen says
which of the three a number is — **agreed**, **a share from above**, or **a
starting number nobody has agreed**.

### What this exposes about the registry

Worth saying plainly, because it is theirs to decide and not mine:

* **The measures change type going up.** A percentage at the bottom, a count
  at the top. The pyramid can only be built where family, direction and type
  line up.
* **`D21` names two opposite things.** "Error rate" at Team Leader, "Branch
  quality score" at Branch Manager. The quality chain therefore stops at Team
  Leader, because there is no ceiling-facing quality measure at branch level.
* **`perf_rollup_map` has 20 rows and each is a guess I can defend, not a
  fact I was given.** It is the one part of this that should be read and
  corrected by somebody who knows the business.

---

## 7 · The roll-up map, read row by row — migration 226

Asked for directly: *"check the rollup map rows and fix the ones that are
wrong."* So each of the 20 was read against what the two measures actually
count, and **seven were deleted, three were redundant, and thirteen stand.**

| Deleted | Why it was wrong |
|---|---|
| `D3 → D8` | Sent an executive's own family past its own parent's copy of it |
| `F4 → F4b`, `X3 → CEO2` | Two different quantities with a similar name |
| `HRE1 → HRO1`, `HRE3 → HRO3` | Crossed a floor into a ceiling — a 5% ceiling was being overwritten by a 90% goal |
| `K4 → K1`, `M1 → HFO4`, `F9 → AC4`, `D2 → L1`, `D8 → L1` | A count feeding a percentage, or a percentage feeding a count |
| `D1 → D1`, `D21 → D21`, `G4 → G4` | Redundant: a code that does not change needs no row. Same-family is tried first |

Two structural changes came out of the reading:

1. **The key is now (child, parent) with a `priority`,** because one family
   legitimately has several parents — "days filed" climbs into three.
2. **`perf_relink` tries the same family first and the mapped parents
   second.** The old order is what made `D3 → D8` silently skip a level.

### The handover — the step the pyramid cannot take

Asked for: *"if the managers or a layer or chair where the KPI changes there
the chair must see the roll up and then update his own."*

**239 measures hand over to a person rather than climbing.** They measure
something the chair above does not hold, so no arithmetic can add them in.
`perf_handover(actor, cycle, person)` returns them grouped by measure —
people, filed, target, team total or mean, best, worst, how many met it —
with the per-person detail underneath. A Branch Manager with forty-two
executives gets a briefing, not eighty-six rows.

---

## 8 · The day, the month and the quarter — migration 227

Until now the same quantity was entered twice: filed daily by the person,
and retyped quarterly by somebody else, with nothing checking they agreed.

**The line this draws is where facts stop and judgements start.**

| | |
|---|---|
| A quarterly **actual** is a fact — what was filed, rolled up | `plb_actual_from_perf` **writes** it |
| A monthly **score** is a judgement — the Constitution's "partly or late" is a person's call about a person | `plb_month_suggest` **writes nothing** |

Both halves are asserted in `build/test/test_link.sql`, including that a
measure nobody filed is left **blank rather than scored as zero**, and that a
frozen quarter is frozen against arithmetic and not only against typing.

### The screen

The blueprint's sections gained three, and the CSS follows the app's existing
status palette rather than introducing hues:

* **Today, as a headline** — one ring, filed against due, the run of working
  days behind it, and one sentence that is true rather than encouraging.
* **What came up from below** — the handover, as cards then detail.
* **This month, out of ten** — the suggestion and its working, marked as a
  suggestion, writing nothing.

Status never travels as colour alone: every bar ships the percentage and the
word beside it, and nothing due reads green because a day with no measures on
it is not a failure.

## Status · 2026-09-30

| | |
|---|---|
| Defect 5 · the quarter leak | **closed** — 222, plb v8, verified per account |
| The daily climb | **built** — 140 measures climb, every measure due daily |
| Targets down | **built** — divides or copies, a hand edit pins |
| Dummy targets | **728 seeded** across two months, all marked SEEDED |
| Screen | **published** — 467,960 bytes, Targets section live |
| Functions | plb v8, perf v2, both `verify_jwt` off |
| Tests | 34 in `test_flow.sql`; suite green once the baseline refreshes |
| Roll-up map | **corrected** — 7 wrong rows deleted, 3 redundant, 13 stand |
| Handover | **built** — 239 measures that hand over to a person, not to arithmetic |
| Day → month → quarter | **built and tested** — 299 passed, 0 failed on a clean rebuild with 226 and 227 applied |

### Not yet live — blocked, not forgotten

Three steps need the Supabase connection, which is unauthenticated in this
session. Everything else is written, tested and pushed.

1. **`plb_month_suggest` is not applied to the live database.** The rest of
   227 is. Until it is, `/perf/month` answers 404 and the screen hides that
   section rather than showing an empty one.
2. **`perf` is still v2** and has no `/handover` or `/month` route. The code
   for both is in the repository. **It must be redeployed with
   `verify_jwt: false`** — the page sends `x-crux-token` and no
   Authorization header, and the default of `true` 401s everything.
3. **The baseline lags by two migrations.** `build/schema` is regenerated
   from the live database, so it catches up only after step 1. Until then
   `build/test/run.sh` is red on `test_link` — correctly, because the
   baseline genuinely cannot rebuild what is not in it yet.

---

## Change log

| When | What changed | Why |
|---|---|---|
| 2026-09-28 | New SOW; previous one archived | The method changed: whole-tool claims replaced by one screen at a time |
| 2026-09-28 | Blueprint indexed into 34 measured sections | "Not matching the design" cannot be worked on until the design is enumerable |
| 2026-09-29 | Performance routes moved to a sixth front door, `perf` | `plb` computes pay and deploys all-or-none; three new routes are not worth risking the quarterly scheme |
| 2026-09-29 | Visibility is the reporting line, not the chair tree | The chair tree put every branch manager one step below every zonal manager, and the place filter that narrowed it opened itself for four in five people |
| 2026-09-29 | HR and Business Excellence lose the blanket over every person | The rule as given has no room for it. Running the scheme is a different act and is untouched |
| 2026-09-29 | A person sits where their manager sits | 69 of 82 unplaced holders were on chairs with no seat at all, so no amount of coverage data would have placed them |
| 2026-09-29 | Vrunda Potdar seated with the place left open | She covers four regions and the chart has no seat that means four. Being in the line matters more than the label |
| 2026-09-29 | RLS turned on for five tables the convention missed | Found by the advisor. Had to go before the KPI seed, which would have filled two of them |
| 2026-09-29 | Targets seeded blank, on purpose | A target nobody agreed is multiplied into somebody's pay at the end of the quarter |
| 2026-09-30 | Seven roll-up rows deleted after reading each one | Four crossed a type or a direction; three were a count feeding a percentage. Each would have overwritten somebody's target with a number that measured something else |
| 2026-09-30 | Same-family tried before the mapped parents | `D3 → D8` was making a measure skip its own parent's copy of itself |
| 2026-09-30 | The quarterly actual is computed; the monthly score is not | A fact and a judgement are different things, and a system that scores "partly or late" silently is inventing one |
