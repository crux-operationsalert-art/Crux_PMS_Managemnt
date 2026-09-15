# NEXT STEPS — instructions for Claude Code (or Claude chat)

Hand this file to Claude Code with the repository open. It is written to be executed
top to bottom. Everything before Step 7 runs without a domain name.

**Read first:** `PROJECT_STATE.md` (what exists and why), `AWS_INFRASTRUCTURE.md`
(the decisions), `build/supabase/DEPLOY.md` (phase 1), `RUNBOOK.md` (operations).
Do not re-derive decisions those files already record. If something here contradicts
them, they win — and say so rather than silently choosing.

---

## 0. Assumptions taken on the owner's instruction to move forward

These were open questions. They are now defaults. Each is reversible; where reversal
is expensive it says so.

| # | Decision | Taken as | Reversal cost |
|---|---|---|---|
| 1 | Region | `ap-south-1` (Mumbai) | High — move before data lands, not after |
| 2 | Account age | Assume **over 12 months**, so no free tier. Budget stands at ~$287/mo | None |
| 3 | Network | **Create a new VPC.** Do not attach to anything existing | Low, before RDS |
| 4 | API hosting | **EC2** (`t3.small`, one per environment) | Low — the API is a plain Node process |
| 5 | Domain | **Deferred.** Use the ALB DNS name; Route 53 + ACM are Step 7 | Low |
| 6 | IAM | One `crux-admin` human; everything else is a role | Low |

State these back to the owner at the end of the run, as a list, so they can veto.

---

## 1. Verify the account before creating anything

```bash
aws sts get-caller-identity
aws configure get region                 # expect ap-south-1
aws service-quotas get-service-quota --service-code vpc --quota-code L-F678F1CE   # VPCs per region
aws rds describe-db-instances --region ap-south-1                                  # expect empty
```

Stop and report if: the account already has RDS instances, the identity is a root
user, or the region is not `ap-south-1`. Do not create resources under a root user.

---

## 2. Write the CloudFormation templates

Create `build/aws/` with four stacks, in this order. Separate stacks, not one — so a
mistake in the app layer never forces the network or the database to be replaced.

1. `10-network.yml` — VPC `10.40.0.0/16`; two public and two private subnets across
   `ap-south-1a` / `ap-south-1b`; internet gateway; one NAT gateway (single, not
   per-AZ — this is a cost decision, note it); route tables; three security groups:
   `sg-alb` (443 from the internet), `sg-api` (8080 from `sg-alb` only),
   `sg-db` (5432 from `sg-api` only). **No security group may allow 0.0.0.0/0 on 5432.**
2. `20-data.yml` — RDS PostgreSQL 15.6, `db.t4g.medium`, **Multi-AZ**, storage
   encrypted with a customer-managed KMS key, 35-day automated backups, deletion
   protection on, in the private subnets. Master credentials in Secrets Manager with
   rotation. Plus the S3 buckets: `crux-migration-<acct>` (versioned, 30-day
   lifecycle), `crux-uploads-<acct>` (versioned, block all public access).
3. `30-app.yml` — one EC2 `t3.small` per environment in a private subnet, instance
   role granting only: read its own secret, read/write its two buckets, write
   CloudWatch logs. An ALB in the public subnets. No SSH key — SSM Session Manager only.
4. `40-observability.yml` — CloudWatch log groups (30-day retention), alarms on
   RDS free storage, CPU, connection count, ALB 5xx, and **outbox depth** (see below).

Parameterise `Environment` (`prod` | `staging`) and deploy each stack twice.
Tag everything `Project=crux`, `Environment=`, `ManagedBy=cloudformation`.

Validate before deploying:

```bash
for f in build/aws/*.yml; do aws cloudformation validate-template --template-body "file://$f"; done
```

Deploy prod first, confirm, then staging with the same templates.

---

## 3. The outbox alarm is not optional

`build/api/outbox.js` and the mail counters exist because a mail storm is what
started this rebuild. Create a CloudWatch alarm on the two numbers
`/api/ops/mail` returns — queue depth and sends-in-last-hour — and page on them.
An alarm on CPU would not have caught the original incident. This one would.

---

## 4. Load the schema

Run from the EC2 instance via SSM (the database is not publicly reachable, which is
correct — do not "temporarily" make it public):

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f build/schema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f build/schema-patch-v3.sql
for f in build/migration/*.sql; do psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$f"; done
```

Order matters and is fixed. Then check the gates — **all ten must read PASS**:

```sql
select * from migration_gate order by code;
select * from migration_unaccounted;      -- must be empty
select * from migration_open_questions;   -- must be empty
```

Expected gate values: 28 · 1,413 · 722/691 · 3,783 · 693 · 55 · 3 · 449 · 0 queued
mail · 0 standing tokens. **A gate that fails is a stop, not a warning.** Report the
failing code and the row count it saw; do not adjust the gate to make it pass.

Then the one check that matters most:

```sql
set role anon; select * from person;      -- must return: permission denied
reset role;
```

---

## 5. Deploy the API

`build/api/` is Express + Postgres, no ORM — **keep it that way**. An ORM upserting
around the unique indexes would undo the migration's duplicate resolution.

- Environment from Secrets Manager, never a `.env` in the image.
- Run under systemd with `Restart=always`; logs to CloudWatch.
- Health check at `/healthz` returning 200 only when the database answers.
- Confirm `worker.js` runs on exactly **one** instance. Two workers both chasing
  `next_chase_at` will double-send. If you scale the API, split the worker out.

Then add the endpoint the app is now waiting for:

```
POST /admin/migrate/:stage
  stage ∈ preflight | schema | export | load | verify | cutover
  body  { confirm: true }  — or { confirm: "CUTOVER" } for the cutover stage
  → 200 { ok:true,  lines:[ "…", "…" ] }
  → 4xx { ok:false, error:"one sentence a non-engineer can act on", lines:[…] }
```

`lines` is what the screen prints into its log, one string per line, in order.
Back it with `build/api/migrate.js`. Rules the UI already assumes and the endpoint
must honour server-side — **do not rely on the client to enforce them**:

- Stages 1–5 are idempotent and safe to re-run.
- Re-running a stage invalidates every stage after it.
- `cutover` refuses unless row counts **and** content checksums match on all 41 tables.
- Admin only; every stage writes an audit row with the actor.

---

## 6. Point the app at the API

`Crux App v2.dc.html` reads `window.CRUX_API_BASE`. When it is unset the app runs on
its built-in sample data — that fallback is deliberate, keep it. Set it in the served
page and the migration screen becomes live with no other change.

Then wire the modules **one at a time against a loaded pilot database**:
escalations first, then matrix. Not all at once. After each module, re-run that
module's screens and confirm no blank states and no `undefined` reaching the UI.

⚠️ The preview intermittently serves a stale compiled copy. **Force a reload before
treating any finding as a real defect** — several apparent failures in earlier
sessions were stale-runtime artefacts.

---

## 7. Domain and TLS — only when the owner supplies the name

Blocked on: the domain name, and who currently hosts its DNS. Until then the ALB DNS
name works for the pilot. When supplied:

1. Route 53 hosted zone (or delegate from the current host).
2. ACM certificate in `ap-south-1`, DNS validation.
3. ALB HTTPS listener; redirect 80 → 443; HSTS.
4. Workspace SSO redirect URIs updated to the real host — `auth.js` matches an
   existing person and **never creates one**; keep that.

---

## 8. What to hand back

A short report, in this order: the six assumptions with anything you changed and why;
stack names and their outputs; the gate table as it actually read; confirmation that
`set role anon` was denied; the migration endpoint's response to a `preflight` call;
and the monthly cost estimate against the $300–500 ceiling.

---

## Still open — needs the owner, not code

1. **Domain name and current DNS host.** Blocks Step 7 only.
2. **A higher-resolution logo.** The header and login panel now carry
   `assets/crux-logo.png` and `assets/crux-logo-light.png`, derived from a 300×98
   GIF — the only usable file supplied. They are fine at the sizes used and will
   visibly degrade if enlarged or printed. Do not scale them up to fill a space;
   ask for a vector or 1000px+ original instead.
3. **The zone duplicate.** Two zone names appeared in all 13 months on the same
   clients. Either a mid-year rename that kept receiving entries, or genuinely
   separate books. Only Crux can answer whether to merge them. Recorded in
   `migration_open_questions`; the migration will not pass its gate while it is open.
4. **The single-administrator reopen path.** Every offline filing older than 24 hours
   routes through one person. When he is on leave, nothing moves. A deliberate
   decision — worth revisiting after a month of real volume.
