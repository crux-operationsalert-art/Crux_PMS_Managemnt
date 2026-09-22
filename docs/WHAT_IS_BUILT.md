# What is built, what runs by itself, and what is yours to set

Written 2026-09-22 from the live database, not from the design documents. Every
count in it came from a query, not from memory.

Three questions are answered here, in this order:

1. **What runs on its own**, how often, and what stops it.
2. **What you can change as an administrator** — and, separately, what was
   designed to be changeable but has no screen yet.
3. **What is fixed in code**, deliberately or otherwise.

Then: **what is left to build**, and **what is yours to do**.

---

## 1 · Where the system lives

| Piece | What it is |
|---|---|
| **The application** | One row of `app_page` in the database. A screen change is an update, not a deployment. GitHub Pages serves a copy, republished by a workflow. |
| **The database** | Supabase Postgres, 190 functions, row-level security on every table that carries a person. |
| **Six front doors** | `crux` (the app and most of the API), `api`, `mail`, `org`, `wa`, `dbprobe`. None of them holds a key the browser can see. |
| **The sending device** | `bridge/` — a small program on a laptop or phone that holds the WhatsApp session. Temporary, until the Cloud API is approved. |

Eleven screens: Today, Escalations, Matrix, OGL, Performance, People, Org chart,
Penalties, Data setup, Mail, WhatsApp.

---

## 2 · What runs by itself

Seven scheduled jobs. Every one is idempotent — running it twice does the work
once — and every one checks `job_config` before doing anything, so an
administrator can stop any of them without touching code.

| Job | How often | What it does | Currently |
|---|---|---|---|
| `AUTO_CLOSE` | every 15 min | A resolved escalation closes itself seven days later. | on |
| `SLA_SWEEP` | every 15 min | Marks an SLA at risk or breached from the clock. A paused clock does not move toward breach. | on |
| `OGL_SWEEP` | every 15 min | Sub-TATs, escalation routing, the strike clock. | on |
| `MAIL_DRAIN` | every minute | Sends what is queued, within the daily cap. | on |
| `WA_DRAIN` | every minute | The same for WhatsApp — and deliberately does nothing while a linked device is the provider, so the server cannot race the devices. | on |
| `WA_BRIDGE_SWEEP` | every minute | Notices a sending device that has stopped checking in and raises an urgent alert. | on |
| `PENALTY_SWEEP` | 01:30 nightly | Charges P-01 and P-06 where they apply. **Charges nothing today: every penalty rule is inactive.** | on |

Two things that run on an event rather than a clock: an outbox row mirrors
itself to WhatsApp when the mirror setting says to, and a coverage rule that
overlaps an existing one is refused at write time rather than resolved later.

---

## 3 · What you can change, today, from a screen

| Where | What |
|---|---|
| **Mail** | Provider, sender address and name, reply-to, the Google client id and secret, connect and disconnect, daily cap, a test send. |
| **WhatsApp** | Provider (Meta, Twilio, or a linked device), sender, token, daily cap, country code, what gets mirrored, a test send. Add and retire sending devices, see the code to scan, take an alert. |
| **Org chart** | Where a chair holder sits: one button that places everyone whose coverage says plainly where they are, and a picker per person for the rest. |
| **Data setup** | Load any of the thirteen file kinds, download its template, see the preview, apply or cancel, and read the history of what was loaded. |
| **Escalations, OGL, Performance** | The day-to-day: raise, act, resolve, allocate, submit, file a daily count. |

## 3b · What was designed to be changeable — but has no screen yet

This is the honest half. **71 settings exist in `app_setting`**, each with a
plain-language line written to be shown to you, each marked `editable_by =
ADMIN`. Only the Mail and WhatsApp subsets are reachable from a screen. The rest
can only be changed by someone with database access.

| Group | Settings | Example of what is in it |
|---|---|---|
| Clocks | 22 | Working day start and end, Saturday and its hours, auto-close days, chase hours, the bell-curve bands, the mail cap. |
| Performance and appraisal | 15 | Window open and close, self-review deadline, probation floor, team share, the monthly cap, what an escalation or a warning costs. |
| WhatsApp | 13 | Provider and sender, plus the pacing: gap, jitter, burst, per-device daily limit, retry minutes, stale seconds. |
| Mail | 12 | Sender, provider, the OAuth values. |
| OGL | 7 | Sub-TAT minutes, escalation step, pause cap, the strike window. |
| Sign-in | 2 | Workspace domain, Google client id. |

Likewise these config tables have no editing screen: `penalty_rule` (the
Penalties screen **shows** the seven rules but cannot edit them, though HR and
Finance are meant to), `job_config` (no jobs screen), `category` (22 rows),
`desk` (8), `sla_rule` (2), `client_view_policy` (7), `pms_curve_band` (5).

**A Configuration screen is the single biggest gap between what is built and
what you can actually run.** It is next.

---

## 4 · What is fixed in code, and why

### Fixed on purpose — these are the guarantees

These are not settings because making them settings would let somebody switch
off the thing that prevents the original defects.

| Rule | Where it lives |
|---|---|
| An outbox row is unique by template + recipient + entity + scope. | `mail_enqueue`. This is what makes a second e-mail storm impossible. |
| A penalty cannot be charged twice for the same miss. | `penalty_no_duplicate`, now with nulls treated as equal. |
| A penalty's amount is copied when it fires. | `penalty_sweep`. Editing a rule never rewrites what has already been charged. |
| Nobody sets their own KPI target. | A check constraint, not a UI convention. |
| Two coverage rules may not overlap. | `coverage_no_overlap`, refused at write time. |
| One person, one primary chair. | `person_one_primary_chair`. |
| A branch code is unique within a client. | `branch_code_uniq`. |
| An e-mail is normalised before any comparison. | `person_normalise_email`, with the misspelt-domain fold built in. |
| A disabled job must say who disabled it and why. | `job_disable_needs_reason`. |
| Evidence is mandatory on a penalty. | Not null, so a dispute is arguable on fact. |

### Fixed, and arguably should not be

Stated plainly so you can decide, not buried:

- **The fourteen days in P-06** is a number in `penalty_sweep`, not read from
  the rule's `cutoff_spec`. Editing the rule's wording will not change the
  clock.
- **The rule's `frequency` and `cutoff_spec` are descriptive.** The sweep
  dispatches on the rule's code. Five of the seven rules have no sweep logic at
  all yet.
- **Five levels makes a matrix complete** — a literal in `matrix_complete`.
  That matches the decision, but it is code, not configuration.
- **The map from geography to a place on the org chart** — Pune and Thane
  pulled out of the West, Central having no seat — is written into
  `geo_seat_scope`. When the chart grows a Central chair, this needs editing.
- **Five failed attempts abandons a WhatsApp message**; the bridge polls every
  10 seconds, beats every 45, and waits 15 before reconnecting. Those are in
  `bridge/index.js`, not settings. The pacing that matters — gap, jitter,
  burst, daily limit, retry — *is* settings.

---

## 5 · What is still to build

Done since this was written: the Configuration screen, the escalation action
set, and KPIs. What is left, in the order I intend to do it:

1. **E-mail templates.** `template` is empty; every send composes its text at
   the call site. That works and is readable, but it means changing the
   wording of a chase is a code change rather than an edit.
2. **The penalty sweep for P-02 to P-05 and P-07.** Two of the seven fire
   today. The other five are recorded rules with no logic behind them, and
   the screen says so on each one.
3. **The client portal** — account-free, mandatory, not started.
4. **Print-exact outputs**: MIS register, monthly summary, scorecard, warning
   letters.
5. **The six AI features** behind a monthly cap. `ai_key` and `ai_call` exist
   and are empty.
6. **Redeploying `api`.** Two fixes sit in the repository waiting for it: the
   duplicated PMS cap key, and reading `auto_close_days` rather than a literal
   seven. Both are covered in the database meanwhile, and the migration says
   how.

## 6 · What is yours to do

### Before anything else

- **Connect Gmail.** Mail → set the client id and secret → Connect. Nothing has
  ever been sent; **six test messages are queued and will go out on connect**,
  all to `operations.alert@cruxindia.co.in`, so nobody else sees them.
- **Link a WhatsApp device**, or leave WhatsApp off. If you link one: add the
  device, copy the token once, run `npm start` in `bridge/` on the machine, and
  scan the code when the urgent alert appears.

### The uploads, in this order

Chairs → People → Geography → Clients and branches → Assignments → Rates →
Collections → KPI targets → Past performance → Opening balances → Holidays →
SLA rules → Escalation matrix.

A file with any error applies **zero** rows, so a rejected file is safe to fix
and send again. Two notes:

- The Clients and branches file now takes an optional **`opened_on`**. Blank is
  fine; it only starts the fourteen-day matrix clock.
- **Assignments is the file that matters most for scope.** Only 15 people have
  any coverage today, and coverage is what decides whose work a person sees.

### Decisions only you can make

| # | Decision | Why it is yours |
|---|---|---|
| 1 | **The five missing penalty amounts** (P-02 to P-05, P-07). | They were never published. They are seeded at zero and inactive; nothing fires until you set them. |
| 2 | **When to switch the penalty rules on.** | Turning on P-01 before KPIs exist would charge everyone for not filing a count the tool never asked for. |
| 3 | **Where 31 chair holders sit.** | 26 have no coverage loaded; 5 branch managers cover more than one place. The Assignments upload answers most of it; the org chart has a picker for the rest. |
| 4 | **Ten people named in the structure chart do not exist in the tool at all** — no person row, so no account, no chair, nothing. | Checked name by name: Maruf Shaikh (Accounts), Faizan Bagwan and Harshita Gupta (Accounts Executives), Pranish Khankal, Sneha Kadam, Piyush Singh and Sandhya Jaiswar (Central Collections), Jyostna Patil (Finance Executive), Shiladitya (Regional Manager, North East & East), Vishal Pandey (Technology). They are in the chart and in no USERS row. Either the People upload creates them, or the chart names people who have left. Two more are a linkage question rather than a missing person: P P Valsan is named on Assurance, Risk & Compliance but seated on Head — Human Resources, and Varsha Sonawane is named on Team Leaders (Pune) but not linked to that seat. Two Regional Manager seats say **TO BE HIRED**, which is a fact rather than a gap. |
| 5 | **Whether `operations.alert@` holds a chair.** | It is the sending address. Today it is a person row with an ADMIN role and no seat. |
| 6 | **The EMAIL_LOG and AUDIT_LOG staging load.** | The M-01 reconciliation is armed and waiting on it; it is the last check that cannot pass. |
