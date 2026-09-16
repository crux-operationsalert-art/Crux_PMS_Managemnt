# Go-live checklist

Two tracks that do not block each other. Yours needs the tool and your own
company's decisions; mine needs the code. Where one genuinely waits on the
other it says so.

**The tool:** <https://crux-operationsalert-art.github.io/crux_pms_managemnt/>

That page *is* the tool. It is not a copy and not a menu — it loads the
application out of the database and hands the browser over to it, so there is
still one copy of the application and this is where it opens.

Sign in with your **@cruxindia.co.in** Google account. Two accounts are
administrators — `operations.alert@` and `shantanu.suravase@` — and only an
administrator sees Load a file, Settings and Empty the tool.

### One thing to do first, in Google Cloud Console

Google Sign-In checks which website is asking. The OAuth client knows about the
Supabase address and not the GitHub one, so until you add it the sign-in button
will not appear.

1. <https://console.cloud.google.com/apis/credentials>, same project the client
   id `1064617222271-…apps.googleusercontent.com` belongs to
2. Open that OAuth 2.0 Client ID
3. Under **Authorized JavaScript origins**, Add URI:
   `https://crux-operationsalert-art.github.io`
4. Save. It takes a minute or two to take effect.

Leave **Authorized redirect URIs** alone. That list is for connecting Gmail, and
its callback is still the Supabase address — the Mail screen prints the exact
string to use.

<details><summary>Why the Supabase link I gave you earlier did not open</summary>

Typing a Supabase function address into a browser sends no project key with the
request, and the gateway can refuse it before the application ever runs — so the
page never appears and the address bar tells you nothing. A page can send that
key; an address bar cannot. That is what the new front door does, and it is why
it works where the raw link did not.
</details>

Signing in does not create anybody. An address that is not on the people master
is refused, by design.

---

## Your track

### 1 · Bulk uploads — do these first, in this order

Load order is not advice. Assignments reference people *and* branches; the
escalation matrix references people, clients and geography. Loading out of order
means rows that reference nothing.

Each kind has a template: **Load a file → choose the kind → download the
template** (it is generated from `upload_column`, so it is always current).
Then upload, read the preview, and apply. **A file with any error applies zero
rows** — there is no partial load, so a rejected file is safe to fix and retry.

| # | Kind | What it needs | Note |
|---|---|---|---|
| 1 | **Chairs** | code, title, level, who each chair reports to | **Do this one first — see below** |
| 2 | **People** | names, employee numbers, chairs, managers, contacts | **Second — see below** |
| 3 | Geography | groups, regions, zones, locations | 98 rows already loaded from your master |
| 4 | Clients and branches | client and branch master with codes | 28 clients, 1,413 branches already loaded |
| 5 | Assignments | client × location × handler × W.E.F. | |
| 6 | Rates | agreed rate per client and location, with W.E.F. | |
| 7 | Collections | collected and billed per client, location, month | |
| 8 | KPI targets | monthly targets per person and KPI | |
| 9 | Past performance | MTD achieved, revenue, collections by month | |
| 10 | Opening balances | live escalations, OGL assignments, claims at cutover | 3 escalations already migrated |
| 11 | Holidays | festival dates for the year ahead | RBI 2026 list is ready to load |
| 12 | SLA rules | needs Clients and Geography loaded | |
| 13 | Escalation matrix | needs People, Clients, Geography | 3,525 contacts already loaded |

**Why Chairs and People come first, and why it matters more than it looks.**
Almost every screen beyond the front door asks "which chair do you hold?" before
it shows anything, because a person's view is resolved from their chair and
their coverage — not from their job title. Right now **no real person holds a
chair**: the 17 chairs in the database are the seeded demo org chart with
`@example.invalid` holders. So today those screens correctly show an empty state
with a reason. Upload Chairs, then People, and they fill in.

The demo holders are inert until then — they cannot sign in (wrong domain) and
cannot be e-mailed (`.invalid` addresses are skipped) — and your Chairs upload
replaces them.

### 2 · Sender e-mail

**Settings → Three ways, and what each one needs.** Pick one:

- **A transactional provider** — Resend, SendGrid, Brevo or Postmark. You need
  an API key and a domain you can add DNS records to. Best deliverability, and
  it does not depend on anyone's mailbox.
- **Gmail, through your own Google Cloud project** — paste the OAuth client id
  and client secret, then click through consent on the mailbox that should send.
  No DNS, but sends are subject to that mailbox's Gmail limits.
- **Nothing yet** — the queue holds intact. Messages are not lost and no attempt
  is burned; they go out when a transport is set.

Then set **from address**, **from name**, **reply-to**, and the **daily cap**
(1,500 today).

Keys go in and never come back out. The status screen answers *whether* a secret
is set, never what it is.

> **Two escalations become due on 18 September.** ESC-00191 (Billing, Finance)
> and ESC-00193 (Service Delivery, Operations) came across from the tracker with
> no response deadline, so they would have sat open forever. Their clock now
> starts at cut-over rather than at their August activity — chasing people for a
> window that elapsed before the tool existed would be unfair and would look
> broken. If mail is connected by then, they will chase on 18 September. If you
> would rather they did not, resolve or close them first.

### 3 · Prove it sends, before it matters

**Send a test message.** It queues one and pushes it straight out rather than
waiting for the scheduler, so the answer on screen is the real answer — including
the provider's own error text if it fails.

### 4 · Dry runs and logic checks

- **Recent messages** — every send with its provider reference, or the failure
  text and when it will be retried.
- **Jobs** — each scheduled job can be re-run by hand. The monthly dispatch has a
  dry run that reports who *would* receive it and who is blocked, without sending.
- **Empty the tool** — shows you exactly what it would delete, per table, before
  you confirm. It is the one action that cannot be undone.
- Raise a test escalation once Chairs and People are in: check that the category
  picked the right desk, that the level-1 contact got a readable message, and
  that the chase deadline respects working hours and holidays.

### 5 · The questions only you can answer — 609 of them

`migration_review` is the queue.

- **574 branches** whose exact city the geography master does not hold. They are
  filed at state or zone level so nothing is lost from reporting; naming the
  city makes them precise.
- **22 branches** whose Zone column read "Chandigarh" but whose towns are in
  Chhattisgarh. 16 are filed under Chhattisgarh with the reasoning recorded;
  6 read Chandigarh in both columns and are waiting on you.
- **4 desk vacancies** — IT, Compliance, MIS and the MD office have no head in
  the USERS sheet. They fall back to the Administrator desk until you name
  someone. The MD office has two candidates and the sheet marks neither primary.
- **1 escalation** — ESC-00192 is RESOLVED with no resolution date, so its 7-day
  auto-close window cannot start.
- **1 account** — `admin@cruxindia.co.in` is PENDING in the sheet; the tool only
  has ACTIVE and INACTIVE.
- **2 geography questions** — whether the operating zone (Bengaluru Zone, Rest of
  Karnataka Zone, 18 more) should become a real level, and whether the Zone A/B
  city tier should drive rates or is reporting only.

### 6 · WhatsApp — not yet, and not a setting

`setting.whatsapp` reads "Not connected" and there is no WhatsApp code anywhere:
no provider, no template, no send path. The row is a placeholder for a channel
that has not been built. Nothing you do on the Settings screen will connect it.
Decide whether you want it, and it becomes a piece of work — a business-API
provider, a number, and approved message templates.

---

## My track

- [x] Every reconciliation gate passes — 16 of 16
- [x] Roles applied from the USERS sheet, so administrators exist (P-06)
- [x] Desks and categories configured — 8 desks, 22 categories
- [x] The three live escalations migrated
- [x] Geography rebuilt — 1,407 of 1,413 branches placed
- [x] The generic `/api/<table>` endpoint written, ported and deployed
- [x] The API's source committed, instead of existing only as a deployment
- [x] `outbox.body` defect fixed — raising a case no longer 500s after committing
- [x] The activation e-mail is a sentence, not a JSON blob
- [x] Pages entry point separates the tool from the design prototype
- [x] The fourth identity guard — the misspelt-domain person is now refused
- [x] Constraint proof: all four known-bad writes attempted, all four refused
- [x] Storm regression: 100 identical attempts, one row
- [x] Traceability: 20 of 20 sampled rows walk back to their sheet row
- [x] The design prototype is kept as the design and says so on its own face
- [x] The strike clock reads the owner's RBI list per banking centre
- [x] The migrated escalations have a response deadline, starting at cut-over
- [x] Recipient reconciliation written and armed — `select recipient_reconciliation();`
- [ ] EMAIL_LOG and AUDIT_LOG staging — **waiting on you**, files handed over.
      This is the only thing left on my track, and it is the input to the
      reconciliation above.

### The cut-over checks, as run

| check | outcome |
|---|---|
| W-01 misspelt-domain person | refused |
| W-02 overlapping coverage rule | refused |
| W-03 duplicate branch code | refused |
| W-04 duplicate idempotency key | refused |
| S-01 storm regression | 1 row from 100 attempts |
| T-01 traceability | 20 of 20 |
| T-02 rows with no sheet reference | 17, all seeded demo people |
| R-03 holiday clock is location-aware | behaved |
| M-01 recipient reconciliation | not attempted — needs EMAIL_LOG |

The evidence is in the `cutover_check` table, with the database's own error text
on each refusal, so it outlives this session. W-01 is the one that did not pass
before today: `person.work_email` had no unique index at all.

### Not verified from this session

This environment's egress proxy refuses `supabase.co`, so I cannot call the
deployed functions. Everything above was checked against the database directly
or through the deploy bundler, which resolves every import and compiles every
file. The HTTP behaviour of the routes has not been exercised against the live
function — **your first sign-in is also the first real test of it.** If something
answers oddly, the error text is deliberately specific; send it to me verbatim.
