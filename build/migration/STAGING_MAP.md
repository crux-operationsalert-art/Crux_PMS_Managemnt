# Workbook → `stg` mapping

The authoritative source is the 26-tab datastore export (9.5 MB xlsx, kept
outside git — see `.gitignore`). This file records the column mapping used to
stage it, and the three decisions that were not obvious.

Row counts below were measured from the workbook and match the audited figures
in `PROJECT_STATE.md` §1 exactly.

## Decisions

**1. `stg.branches.code` ← `BranchCode`, not `BranchID`.**
`BranchCode` repeats across the sheet — 1,196 distinct values for 1,413 rows —
which is what the audit recorded as "217 branches without a code". But
`(ClientID, BranchCode)` is **unique for all 1,413 rows**, and the schema's
constraint is `unique (client_id, code)`. So the human code survives and no row
is lost to `on conflict do nothing`.

**2. Branch references are resolved from `BranchID` to `BranchCode` while
staging.** `BRANCH_ASSIGNMENTS`, `ESCALATION_MATRIX`, `ESCALATIONS` and
`USERS.ScopeBranchIDs` all reference branches by `BranchID` (`BR-00170`), but
`50_coverage.sql` joins `branch b on b.code = btrim(a.branch_code)`. Staging
therefore translates through a BranchID→BranchCode map built from `BRANCHES`.
Without this every coverage join silently produces nothing.

**3. `stg.clients.code` ← `ClientID`, not `ClientCode`.** `BRANCHES.ClientID`
and `BRANCH_ASSIGNMENTS.ClientID` both carry `CLI-00007`, and the migration
joins `client cl on cl.code = btrim(b.client_code)`. `ClientCode` is the short
trading name (BOM, SBI) and is not the key anything references.

## Mapping

| stg table | sheet | rows | columns (stg ← sheet) |
|---|---|---|---|
| `clients` | CLIENTS | 28 | code←ClientID, name←ClientName, status←Status, primary_email←ClientEmail, cc_email←ClientCC, ho_email←HeadOfficeEmail, ho_cc_email←HeadOfficeCC, notes←Notes, zones←null |
| `branches` | BRANCHES | 1,413 | client_code←ClientID, code←BranchCode, name←BranchName, address←Address, zone←Zone, city←Location, state←null, status←Status, bm_name←BranchManagerName, bm_mobile←BranchManagerMobile, bm_email←BranchManagerEmail, poc_email←CruxPOCEmail, updated_at←UpdatedAt, dublicate←null |
| `branch_assignments` | BRANCH_ASSIGNMENTS | 1,729 | user_email←PersonEmail, branch_code←**resolve(BranchID)**, client_code←ClientID, role←AssignmentRole, created_at←CreatedAt |
| `users` | USERS | 55 | name←Name, email←Email, role←Role, designation←Designation, department←Department, manager_email←Manager, scope_client←ScopeClientIDs, scope_zone←ScopeZones, scope_state←ScopeLocations, scope_branch←**resolve(ScopeBranchIDs)**, status←Status, access_token←AccessToken, created_at←CreatedAt |
| `matrix` | ESCALATION_MATRIX | 3,783 | client_code←ClientID, branch_code←**resolve(BranchID)**, level←Level, level_name←LevelName, name←ContactName, mobile←Mobile, email←Email, updated_by←UpdatedBy, updated_at←UpdatedAt |
| `escalations` | ESCALATIONS | 3 | ref←EscalationID, client_code←ClientID, branch_code←**resolve(BranchID)**, category←Category, raised_by←CreatedBy, against←AgainstEmail, description←Description, status←Status, resolved_at←ClosureDate, created_at←CreatedAt, strike_count←null |
| `escalation_events` | ESCALATION_HISTORY | 378 | ref←EscalationID, at←Timestamp, actor_email←User, kind←Field, note←Note |
| `people_events` | PEOPLE_EVENTS | 26 | person_email←PersonEmail, at←Timestamp, kind←Type, note←Notes, actor_email←IssuedBy |
| `people_events_copy` | Copy of PEOPLE_EVENTS | 451 | same as above |
| `targets` | TARGETS | 102 | person_email←PersonEmail, period←MonthKey, metric←Category, value←TargetValue |
| `email_log` | EMAIL_LOG | 2,229 | at←Timestamp, idempotency_key←IdempotencyKey, template_key←Type, recipient←ToAddr, state←Status, error←Error, entity_ref←MessageRef |
| `audit_log` | AUDIT_LOG | 5,913 | at←Timestamp, actor_email←User, action←Action, entity_type←Entity, entity_ref←EntityID, old_value←OldValue, new_value←NewValue |
| `settings` | SETTINGS | 54 | key←Key, value←Value, updated_at←UpdatedAt |
| `sheet4` | Sheet4 | 11 | c1..c6 ← first six columns |
| `holidays` | HOLIDAYS | **0** | — |
| `warnings` | WARNINGS | **0** | — |

`row_no` is the 1-based spreadsheet row number in every case, so a review row
can point back at the source line.

## The two empty sheets

`HOLIDAYS` and `WARNINGS` are empty in the source, exactly as the audit found.
An empty holiday table is a **go-live blocker**: the old tool read it, the
working-hours exclusion never fired, and every TAT was silently wrong. Holidays
must be loaded through Data setup → Bulk upload before the tool is relied on.
