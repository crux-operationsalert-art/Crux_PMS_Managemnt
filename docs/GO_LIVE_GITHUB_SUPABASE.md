# GO LIVE — GitHub + Supabase

**Read this before writing any code. All of it.**

This project already contains a finished application. The last handover was
misread as "build the app" and a different application was produced instead.
This file exists to make that impossible to repeat.

---

## RULE ZERO — DO NOT BUILD AN APPLICATION

The application exists. It is `Crux App v2.dc.html` — one file, 12,800 lines,
13 chairs, 115 tabs, 35 forms, 265 buttons, audit-passed with zero orphans and
zero blank screens. Every screen is resolved down to copy, permissions, empty
states and edge cases, against a 26-tab audit of the real workbook.

**Your job is to deploy it, not to write it.**

If at any point you find yourself doing any of the following, you have gone
wrong — stop and re-read this file:

- Running `create-react-app`, `next`, `vite`, or any scaffolder
- Creating `src/`, `pages/`, `app/`, or `components/`
- Writing a screen, a form, a table or a nav that already exists in the app
- "Porting", "migrating", "modernising" or "re-implementing" the frontend
- Introducing TypeScript, an ORM, Tailwind, or a component library
- Deciding the single-file app is unmaintainable and splitting it up

None of that is wanted. The frontend ships as-is, as static files.

> The word "port" in `GO_LIVE_PLAN.md` Step 5 is what caused the earlier
> rebuild. It has been corrected. If any older document tells you to rebuild
> screens, **this file wins.**

---

## What ships

Six static files. That is the entire frontend.

```
Crux App v2.dc.html      the application
support.js               its runtime — do not edit, do not replace
config.js                the API origin. The only file that differs per environment
crux-data.js             the data seam + seed data
org-data.js              live org structure (window.CRUX_ORG)
automations.js           job definitions
assets/crux-logo.png     navy, for light grounds
assets/crux-logo-light.png  knockout, for the dark login panel
```

Plus the backend, which also already exists: `build/api/` — Express + Postgres,
13 files, no ORM. `build/api/README.md` maps each file to the defect it answers.

**Keep it without an ORM.** An ORM upserting around the unique indexes would
undo the duplicate resolution those indexes exist to enforce.

---

## The job, in order

### Step 1 — repo

```bash
git init && git add -A && git commit -m "Crux operating tool — audited prototype + backend"
```

`.gitignore` must contain `.env` **before** the first commit. No connection
string, key or password enters the repo, a commit message, or a screenshot.

Commit the files exactly as they are. Do not reformat, do not run a linter over
the application file, do not "clean up" the inline styles — they are inline on
purpose so screens paint immediately.

### Step 2 — verify the Supabase database that already exists

A database has already been created. Check it before trusting it:

```bash
export SUPABASE_DB_URL='postgresql://postgres:…@db.….supabase.co:5432/postgres'
psql "$SUPABASE_DB_URL" -f build/supabase/99_verify.sql
```

That prints a check table with expected vs actual and a verdict per row. It only
reads, so it is safe against live. **Every row must read PASS.** Then run the two
manual lines it prints at the end and confirm the `anon` select is *denied*.

If rows FAIL, the database is incomplete rather than wrong — apply what is
missing, in this order, and re-verify:

```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f build/schema.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f build/schema-patch-v3.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f build/schema-patch-v4.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f build/supabase/01_rls.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f build/supabase/02_auth_storage.sql
```

`ON_ERROR_STOP=1` is not optional — without it psql continues past a failed
statement and leaves a half-built schema that looks fine.

Do not re-run a file that already applied cleanly unless the verify says its
objects are missing. Report the verify table back verbatim.

### Step 3 — deploy the API

`build/supabase/DEPLOY.md` §6 has the environment variables. Two things it is
worth repeating:

- **Not Lambda.** The daily filing burst opens more connections than the
  instance holds and the pooler starts refusing. Fly, Render or a small EC2.
- **`worker.js` runs on exactly one instance.** Two workers both chasing
  `next_chase_at` will double-send. That is the failure that started this whole
  rebuild — 1,892 sends to one person for one case.

Health check at `/healthz`, 200 only when the database answers.

The API must serve the seam's four operations per table, and **scope must be
enforced in the query**:

```
GET    /api/:table?col=v&col=v   → rows        (repeated param = "in this set")
POST   /api/:table               → inserted row
PATCH  /api/:table/:id           → updated row
DELETE /api/:table/:id           → ok
```

The prototype demonstrates correct scope semantics but proves nothing about
enforcement. A branch manager who can see another branch's filings means
`coverage_rule` is wrong, not the API.

### Step 4 — point the app at the API

Edit **one line** in `config.js`:

```js
window.CRUX_API_BASE = 'https://api.your-host';
```

That is the whole integration. `crux-data.js` swaps its in-memory adapter for
the HTTP one at load, every screen reads live data, and the readiness check's
`adapter` row flips to pass. **No screen, view model or calculation changes.**
If you are editing anything else to connect the database, stop.

Leave it empty and the app runs on seed data — keep that behaviour, it is how
the thing gets demoed.

### Step 5 — host the frontend

Any static host: GitHub Pages, Netlify, Cloudflare Pages, or the same box as the
API. It is static files; there is no build step. Serve the directory.

Set `CORS_ORIGINS` on the API to the frontend origin.

### Step 6 — load the masters through the product

Not by SQL. **Data setup → Bulk upload** has a template per master, and each
upload is validated against the ones before it. `DEPLOY.md` §5 has the load
order — it matters.

Two that bite:

- **`is_assigned_handler` on exactly one row per client × location.** The MIS
  final count reads those rows and nothing else. If none is set, every MIS
  total reads zero — correctly, and confusingly.
- **Holidays are a go-live blocker.** The old tool read an empty holiday table,
  so the working-hours exclusion never fired and every TAT was silently wrong.

### Step 7 — run the five audits a prototype cannot

`APPLICATION_AUDIT_LOG.md` §E lists five checks marked NOT TESTABLE IN CURRENT
ENVIRONMENT: permission enforcement, penetration, idempotency, interruption
recovery, and performance at volume. All five become testable once the API is
up. Run them before anyone relies on the tool.

One known item from measurement: ~850 ms per screen render, because thirteen
screens share one template. Every view model runs in 0–2 ms, so it is DOM
reconciliation, not logic. It is acceptable for the pilot. **Do not fix it by
rebuilding the app** — revisit only if the pilot complains.

---

## The admin's two functions — both already built

The user asked for these. Neither needs new code.

**Update details.** Data setup → Bulk upload, plus in-place admin editing.
Every correction goes through `CruxDB.insert/update/remove`, which writes a
change-log entry alongside the change: who, when, before, after, why. Export the
change log; it is the audit record and doubles as a seed-correction script.

**Move everything to AWS.** Data setup → Move to AWS. Six stages, already wired
to `POST /admin/migrate/:stage` and backed by `build/api/migrate.js`. It is live
whenever `CRUX_API_BASE` is set; mount the route on the API when the AWS
instance exists:

```js
app.use('/admin/migrate', require('./migrate'));
```

Stages 1–5 are idempotent and safe to run and re-run **while the business keeps
working on Supabase**. Only stage 6 changes where writes go, and it will not
unlock until row counts *and* content checksums match on every table.

**AWS credentials are not available yet, and nothing here waits on them.**
Phase 1 is complete without a single AWS resource. `AWS_INFRASTRUCTURE.md` and
`NEXT_STEPS_FOR_CLAUDE_CODE.md` hold phase 2 for when the account is handed over;
ignore both for now.

---

## Claude Code, not Claude chat

Code, for all of the above: it has a filesystem, runs `git`, `psql` and `npm`,
and can execute the verification. Chat has none of those — fine for questions
about the decisions, wrong for doing the work.

Open the repo **with these files in it** and start at Step 1. Do not describe
the app to a fresh session and ask it to produce one.

---

## What to report back

1. The `99_verify.sql` table, verbatim, and whether the `anon` select was denied.
2. Anything you applied to the database and why the verify said it was needed.
3. The API host, and confirmation that exactly one worker is running.
4. The three sign-in refusals tested: personal address, unknown work address,
   inactive person. Each gives a different message on purpose.
5. Three sign-ins at different levels, each seeing only its own subtree.
6. Confirmation that no file outside `config.js` was changed to connect the
   database.

---

## Still needs the owner, not code

1. **The zone duplicate.** Two zone names appear in all 13 months on the same
   clients — a mid-year rename that kept receiving entries, or two genuinely
   separate books. Only Crux can say. Recorded in `migration_open_questions`;
   the migration gate stays shut while it is open.
2. **Agreed commercial rates.** All 153 are currently derived (revenue ÷ MTD),
   so they restate revenue rather than validate it. This is the most likely
   source of false confidence in the numbers.
3. **Domain name and current DNS host.** Only blocks TLS and the real sign-in
   redirect; everything above works on the host's default URL.
4. **A higher-resolution logo.** The two in `assets/` came from a 300×98 GIF —
   fine at header size, they will not survive enlargement or print.
