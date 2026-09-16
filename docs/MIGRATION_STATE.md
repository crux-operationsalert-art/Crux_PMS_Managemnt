# Migration state — 2026-09-16

Staging holds the workbook in full; steps 20–50 have been run against it.

## Verified against the audit

| check | result | audited |
|---|---|---|
| Branches | 1,413 | 1,413 ✓ |
| — ACTIVE / INACTIVE | 722 / 691 | 722 / 691 ✓ |
| Clients | 28 | 28 ✓ |
| Branches complete at 5 matrix levels | 693 | 693 ✓ |
| People from the users sheet | 55 | 55 ✓ |
| Typo-domain rows normalised | 583 → one person | 583 ✓ |

`693` is derived by `branch_matrix_state`, never stored, so it is an
independent reproduction of the audited figure rather than a copied number.

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
