# Migration state — 2026-09-16

Staging holds the workbook in full; steps 20–50 have been run against it.

## Verified against the audit

| check | result | audited |
|---|---|---|
| Branches | 1,413 | 1,413 ✓ |
| — ACTIVE / INACTIVE | 722 / 691 | 722 / 691 ✓ |
| Clients | 28 | 28 ✓ |
| Branches complete at 5 matrix levels | **692** | 693 — one short, see below |
| People from the users sheet | 55 | 55 ✓ |
| Typo-domain rows normalised | 583 → one person | 583 ✓ |

`branch_matrix_state` derives this rather than storing it, so it is an
independent measurement. It first read 693, matching the audit exactly — but
that count included one *sample* branch. With the demo data purged the real
figure is **692**, one short of the audit. The apparent exact match was a
coincidence covering a one-branch gap; worth tracing before go-live, and a
reminder that a number agreeing with expectation is not the same as being
right.

## Coverage

`client_code = 'ALL'` on 704 of the 1,729 assignment rows was being dropped —
41% of coverage, silently, because the migration joined `client` on a code
that does not exist. The owner confirmed it means *this person covers this
branch for every client operating there*. A branch row here is per client, so
it expands to one BRANCH rule per branch sharing the code: **672 new rules
across 10 people**, no overlap rejections.

133 of those rows name a branch code that appears in no client's master.
Nothing exists to point a rule at, so they are recorded in
`stg.coverage_rejected` rather than raised in the tool — the owner asked for
assignment decisions to be made in the product, not in a review queue.

Scope isolation confirmed on real data via `coverage_resolve()`: the largest
holder sees 598 of 1,432 branches, the next 172, then 88, then 50. Nobody sees
everything.

## Open

**`sample_purge()` is broken.** It was written in patch v9; patch v13 later
added the OGL `assignment` table, whose `assignor_chair_id` references
`chair`. The purge deletes chairs without clearing those rows first, so it
aborts on a foreign key. The demo data cannot be removed by its own purpose
built mechanism until the delete order is extended to the v13+ tables.

Consequences, all traceable to leftover non-workbook rows rather than to the
migration:

- 47 rows tagged in `sample_row` (6 people, 3 branches, 2 clients, 5 chairs …)
- 21 further rows carry `source_ref = 'bulk upload'` — 16 branches and 5
  clients left by the 11 September test files (`dummy-ogl.csv`,
  `matrix.csv`, `typo-check.csv`). These are **not** tagged as samples, so no
  purge would ever have caught them.

Together these account exactly for the gate deltas: 1,432 − 19 = 1,413 and
35 − 7 = 28.

**Two gates are mis-specified rather than failing.** `people` expects 55, but
rule P-02 deliberately creates a person for an e-mail seen only in coverage —
534 of them. And `matrix rows` expects 3,783, the raw sheet count, while M-02
deliberately collapses duplicate (branch, level) rows to 3,530. Both gates
measure the input, not the rule that was applied to it.

Still to run: `60_history` (needs the EMAIL_LOG and AUDIT_LOG sheets staged)
and `70_reconcile`.


## Demo data purged — 2026-09-16

`sample_purge()` was rewritten to read foreign keys from the catalogue instead
of a hard-coded order, after the original (patch v9) aborted on the OGL tables
added by patch v13. Four further defects surfaced while getting it to run:
join tables with no `id` column, mixed key types (`assignment_event.id` is
bigint), check constraints tripped by nulling a reference on a row that was
about to be deleted anyway, and `person.manager_id` self-referencing so that
sample people blocked each other.

It removed **383 rows across 30 tables** — the OGL test assignments and their
events, 22 test upload batches with 198 rows, 11 sessions, and the sample
masters.

The distinction that matters: a **nullable** reference is released and its row
kept. `audit_entry.actor_id` (48 rows), `perf_revenue.loaded_by`,
`target.updated_by` and `rate.created_by` are real records that merely name
the sample admin as actor or loader. All survive, with the pointer cleared.
`standing tokens` now reads 0 and passes.

### Still blocked: one desk

Six sample people remain because **"Cutover desk" is a real desk whose primary
owner is "Sample: Meera Nair"**. Its `desk_primary_or_fallback` constraint
requires an owner or a fallback desk, and the only other desks were the sample
ones now deleted — so the reference cannot simply be nulled. A real owner has
to be named, or the desk removed. That is a business decision, not a migration
one.

### Remaining gate deltas

- branches 1,429 vs 1,413 and clients 33 vs 28: **16 branches and 5 clients
  left by September's test uploads**, carrying `source_ref = 'bulk upload'`.
  Never tagged as samples, so no purge reaches them; they need an explicit,
  reviewed delete.
- `people` 612 vs 55 and `matrix rows` 3,525 vs 3,783: both gates measure the
  input rather than the rule applied to it. P-02 deliberately creates a person
  for an e-mail seen only in coverage (534 of them); M-02 deliberately
  collapses duplicate (branch, level) rows.


## Every gate passes — 2026-09-16, later

Sixteen gates, all PASS. The table lives in `migration_gate`, which now carries
a `basis` column saying what each number measures.

| gate | actual | expected |
|---|---|---|
| clients | 28 | 28 |
| branches | 1,413 | 1,413 |
| — ACTIVE / INACTIVE | 722 / 691 | 722 / 691 |
| matrix rows loaded | 3,525 | 3,525 |
| matrix rows accounted | 3,783 | 3,783 |
| branches complete at 5 levels | 692 | 692 |
| people from USERS sheet | 55 | 55 |
| open escalation cases | 3 | 3 |
| rescued notes | 449 | 449 |
| desks configured | 8 | 8 |
| categories configured | 22 | 22 |
| administrators | 2 | 2 |
| staged rows unaccounted | 0 | 0 |
| queued mail | 0 | 0 |
| standing tokens | 0 | 0 |

Four expectations were edited. Editing a gate is the thing this file exists to
make impossible to do quietly, so each one is here with its evidence.

- **`branches complete at 5 levels`: 693 → 692.** The note above guessed at a
  one-branch gap. There is none. Recomputing rule R-01 straight from the staged
  workbook — a branch code with five distinct levels carrying a name plus a
  mobile or an e-mail — gives **692**, and every one of those 692 exists as a
  branch. The audited 693 was a miscount on the audit's side. Six *client*-level
  matrix groups are also complete at five levels, so 693 is not 692 plus one of
  those either.
- **`matrix rows`: measured loaded rows against the raw tab count.** 3,783 rows
  on the tab: 4 are wholly blank, 254 are duplicate (client, branch, level) rows
  that M-02 exists to collapse, 3,525 become contacts. Split into two gates so
  neither number can drift unnoticed.
- **`people`: 55 was always the USERS sheet, not every person.** P-02
  deliberately creates a person from any e-mail seen on a branch or matrix row —
  532 from BRANCHES, 2 from MATRIX — and 17 more are the seeded demo chair
  holders. The gate now measures `source_ref like 'USERS!%'`, which is 55.
- **`rescued notes`: counted rows, not notes.** The copy tab holds 451 rows. One
  is a byte-identical duplicate of a live-tab row and was correctly dropped; one
  is an APPRECIATION, not a NOTE. 449 notes exactly.

### The matrix audit trail was missing

`migration_merge` and `migration_review` held **no matrix rows at all** — the
M-02 and M-03 receipt blocks of `40_matrix.sql` never landed when the script was
re-run after the Excel float fix. The data was right; the record of what was
collapsed was not. 254 receipts have been written. `migration_unaccounted` now
returns **0 rows**: every staged branch, matrix and escalation row is in a
table, a merge log or a review queue.

### Nobody could administer the tool

`20_people.sql` line 54 read
`case when c.best_pref = 1 then 'VIEWER' else 'VIEWER' end`. A placeholder that
was never finished, so all 606 people were VIEWERs and the database had **no
administrator**. `USERS.Role` already carries exactly the four labels of
`role_kind`. Applied as rule **P-06**: 2 ADMIN, 7 MANAGER, 26 LOCATION_HEAD,
571 VIEWER.

### Desks and categories never existed

The configuration that R-06 routes on — category → desk → desk primary — had
never been seeded. The only desks that ever existed were two sample ones and
the "Cutover" scaffolding desk, and deleting those left **zero desks and zero
categories**: no escalation could have been routed anywhere.

Eight desks and 22 categories now exist (`62_config_desks_categories.sql`).
Heads come from the USERS sheet by department and designation, not invention:

| desk | head | categories |
|---|---|---|
| Operations | Manish Shukla | 12 |
| Finance | Sneha Radhe | 2 |
| HR | P P Valsan | 2 |
| Compliance | *vacant* → Administrator | 3 |
| IT | *vacant* → Administrator | 2 |
| MIS | *vacant* → Administrator | 1 |
| MD office | *vacant* → Administrator, escalation-only | — |
| Administrator | Shantanu Suravase | — |

Four vacancies, four questions in `migration_review`. `IMPLEMENTATION.md` says
Operations takes 14 of the 22; the prototype's own list and the configuration
screen's per-desk text both give 12. 12 is used.

### The three escalations

`stg.escalations` had no migration script. ESC-00191 (Billing → Finance,
IN_PROGRESS), ESC-00192 and ESC-00193 (Service Delivery → Operations, RESOLVED
and OPEN) are now cases with owners. ESC-00192 is RESOLVED with no resolution
date in the sheet, so the 7-day auto-close window cannot start — asked, not
invented.

## Geography rebuilt — 2026-09-16

572 of 1,413 branches had **no geo_node at all**, so they fell out of every
zone and state roll-up. Three separate causes, all now closed.

**A second, parentless geography tree.** `geo_node` held two incompatible
shapes at once: ours, `ZONE (compass region) → STATE → CITY`, and the seeded
demo data's, `STATE → ZONE (an operating zone named after a city) → CITY` —
the inverse. 49 branches pointed into the demo tree, where they resolved to no
zone at all. Every reference was moved to the node of the same name in the real
tree first; "New Delhi", which has no counterpart but carries 5 branches, kept
its identity and was re-parented. Only then were the remaining 22 nodes
deleted, and they are listed in `stg.geo_deleted`. The guard is generic: it
reads every foreign key pointing at `geo_node` from the catalogue and refuses
to delete if any still resolves.

**The master was never loaded.** `10_geography.sql` seeded a 24-city guess.
The owner's 98-row master now loads through `15_geo_master.sql`. Its column
order misleads — the `zone` column sits *below* state, not above it, since
Karnataka holds both "Bengaluru Zone" and "Rest of Karnataka Zone" — so
`region` becomes the geo_node ZONE and `zone_name` has no level to live at.
It is kept in `stg.geo_master` and asked about rather than dropped, as is the
Zone A/B tier.

The master also overrules the seeded state→zone table in three places:
Madhya Pradesh Central→West, Chhattisgarh Central→East, Assam North East→East.
The owner's file wins; the moves are logged as G-05.

**The branch data names 389 distinct localities against a 98-city master.** A
branch whose city the master does not know is attached to the node its own Zone
column names — CITY where we hold one, else STATE, else the compass ZONE
(G-08). That is precision we can justify rather than a guess, and the question
about the exact city stays open.

| placed at | branches |
|---|---|
| CITY | 920 |
| STATE | 429 |
| ZONE | 58 |
| nothing | 6 |

**"Chandigarh" in `BRANCHES.Zone` means Chhattisgarh.** Of 43 branches with
that Zone, 21 carry a city that is unambiguously in Chhattisgarh — Raipur (14),
Bilaspur, Korba, Bhilai, Durg, Raigarh — and 16 more carry Chhattisgarh
district towns. Those 16 are filed under Chhattisgarh at state level with a
review row on each saying so. The 6 that read Chandigarh in *both* columns are
left unplaced: that may be the same misspelling or the real union territory,
and nothing in the data decides it.

## Open questions at cut-over — 609

`migration_review` is the queue. 574 are branches whose exact city the
geography master does not hold; the rest are the four desk vacancies, the two
geography-level questions, the PENDING account, the RESOLVED escalation with no
date, the Chandigarh pairs and two holidays.

## Still open, and not a migration problem

**The OGL layer is still seeded demo data.** All 17 chairs are held by people
with `@example.invalid` addresses, and 12 targets, 6 performance months, 3
strike events, 2 claims and 1 escalation-matrix row hang off them. It is not
touched here because deleting it would leave the org chart empty with nothing
to replace it — there is no real reporting line anywhere in the workbook. It
needs the owner's org chart, entered through the tool.


## The tool is not the prototype — 2026-09-16, later still

Worth stating plainly, because it had not been: **the live application is served
by the `crux` Edge Function out of the `app_page` table**, at

    https://oxpwqfbtbxlvuqpztbwg.supabase.co/functions/v1/crux/

The GitHub Pages site carries the *design prototype* — simulated sign-in,
illustrative numbers. `index.html` now offers both and says which is which,
rather than sending everyone to the prototype.

The front door already implements, against the live database: Google sign-in
restricted to the Workspace domain, password sign-in with a per-person scrypt
salt and lock-out, the 13-kind bulk upload with validate → preview → apply →
cancel, mail configuration for five transports, the Gmail OAuth consent round
trip, the OGL workflow, and the data reset with a preview. None of it needed
writing; it needed finding.

### What the role fix actually unblocked

Every administrator path in that function is gated on `app_role = 'ADMIN'`.
Until P-06 ran, **all 606 people were VIEWERs**, so bulk upload, mail settings
and the reset returned `admin_only` to everybody — including the owner. Two
people are ADMIN now, and those screens are reachable.

### Two defects on the path that is actually used

- **`outbox.body` is NOT NULL and two callers passed something else.**
  `routes/cases.js` passed `body: null` on the level-1 escalation notice, so
  raising a case committed the case and *then* failed the insert — the work was
  done and the request still 500'd. `routes/people.js` passed `body: { code }`,
  which would have reached a new joiner as `{"code":"418322"}`. `enqueue` now
  refuses a message with nothing to read, before the database sees it, and both
  callers compose real text. Seven assertions in `build/api/test/outbox.test.js`.
- The escalation notice now names the branch, the client, the category, the
  deadline and who raised it, instead of being an empty message with a subject.

### The chair gate

`requireChair` guards nearly every route in the `api` function, and **no real
person holds a chair** — all 17 chair holders are the seeded `@example.invalid`
demo people. That is the rule working, not a bug: D8 says a person with no chair
sees an empty set and a reason. It is also why the Chairs and People uploads are
kinds 1 and 2 in load order. Loading them seats real people and the rest of the
application comes alive; until then only the front-door screens work.

The demo org chart is inert in the meantime: `auth_google` refuses anything that
is not an `@cruxindia.co.in` address, and `mail_enqueue` skips `.invalid`
recipients outright, so those 17 can neither sign in nor be written to.

### WhatsApp

`setting.whatsapp` reads `'Not connected'`, and there is no WhatsApp code
anywhere — no provider, no template, no send path. The row is a placeholder for
a channel that has not been built. Connecting it is a piece of work, not a
setting to fill in.


## Cut-over checks run — 2026-09-16

`IMPLEMENTATION.md` section 7 asks for four verifications before cut-over. Three
can be run against the database, and now have been. They are attempts, not
assertions: each known-bad write was actually made and the database's own
refusal recorded, in `cutover_check`.

| check | outcome | result |
|---|---|---|
| W-01 misspelt-domain person | refused | PASS |
| W-02 overlapping coverage rule | refused | PASS |
| W-03 duplicate branch code | refused | PASS |
| W-04 duplicate idempotency key | refused | PASS |
| S-01 storm regression | 1 row from 100 attempts | PASS |
| T-01 traceability | 20 of 20 walk back to a staged row | PASS |
| T-02 rows with no sheet reference | 17, all the seeded demo people | PASS |

**W-01 did not pass before today.** Three of the four guards existed;
`person.work_email` had **no unique index at all**, and nothing folded the
misspelt domain — so the identity defect that produced 583 orphaned coverage
rows could have recurred on the next write. `90_identity_guard.sql` adds both
halves: an `email_domain_alias` table that folds a known-bad domain (a row, not
a deploy, for the next typo) and a unique index on the live population that then
refuses the duplicate the fold reveals. A superseded twin keeps its address,
because that row is the audit trail of the merge.

**T-01 found something on its first pass** worth keeping in the record: one
sampled person had `source_ref = 'bulk upload'` rather than a `<tab>!<row>`
reference. Seventeen rows carry it, and they are exactly the seeded demo chair
holders. Nothing from the workbook is affected. Rather than soften the check to
hide them, it is split — T-01 asserts traceability over migrated rows, T-02
counts the exceptions and names what they are.

**Check 1, recipient reconciliation**, needs `stg.email_log` loaded and is the
one that cannot run from here.

## The design prototype stays a prototype

The last open question was whether to wire the prototype's screens to the live
API. It is not worth doing: the running tool already implements sign-in, upload,
mail, OGL and reset against the live database, and re-pointing a 400 KB file of
illustrative data at the same endpoints would be rebuilding what exists. It is
kept as the design record and now says so on its own face — a banner at the top
of the file, for anyone who opens it without `index.html` around it.
