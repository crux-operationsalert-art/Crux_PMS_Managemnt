# Testing, while you upload

Work down this in order. The uploads are interleaved on purpose: each one
switches on the screens below it, so testing and loading are the same pass.

**Everything here was called for real before it was written down** — a
short-lived session, the database calling the deployed functions through
pg_net. Where a number appears below, it is what came back.

---

## 0. Before you start (5 minutes)

- [ ] Open the tool and sign in. You land on **Dashboard**.
- [ ] The top row reads: **✦ Ideathon** · MINE · Dashboard, My profile,
      Performance & appraisal, Visits & claims · WORK · OGL Assignment,
      Escalations, Clients, My team & structure · COMPANY · HR, Hiring &
      pending chairs, Joining, Penalty ledger, Coverage & handlers, Reports,
      History & audit trail, Messaging, Automations, Data setup, Settings.
- [ ] Click **Clients**. A second, quieter strip appears under the header
      (Clients · Escalation matrix). Same on **Reports** and **My team &
      structure**. That strip is how you reach the screens that are not in
      the top row.
- [ ] **Mail:** Messaging → **Send me a test**. One arrives at
      operations.alert@. *Checked 25 Sept 05:31 — sent 1, failed 0.*

---

## 1. The uploads, in this order

Each one: **Data setup → the kind → download the template → fill it →
upload → read the preview → apply.** A file with any error applies **zero**
rows, so a rejected file is safe to fix and send again.

Every template now comes down with an example row that the tool itself
accepts — that was not true before today, and it is worth one look before
you overwrite it.

### 1a. People — again, and first

- [ ] Download it. It comes down **already filled with all 103 staff**.
- [ ] Check the **department** column. 48 are a suggestion taken from the
      chair, never confirmed by anyone. It decides what each person can see.
- [ ] Six people have a **blank employee number** on purpose. Fill them or
      the file will not load.
- [ ] Upload → preview → apply.
- [ ] **Then:** HR → the department breakdown shows no "(not set)".

### 1b. Rates  ·  1c. Collections  ·  1d. KPI targets

- [ ] Rates. Then **Rate master**: the rate is listed, and **Export** on the
      card downloads exactly what is on screen.
- [ ] Collections, then KPI targets.
- [ ] **Then:** MIS dashboard stops saying "business_record has no rows" and
      shows a month. Achievement is a real percentage.
- [ ] **Compare with the month before** (top right) adds three columns once a
      second month is loaded.
- [ ] Name a view and **Save**. Reload the page, press **Open** — the
      grouping, month and comparison come back. The figures are read fresh;
      nothing is stored but the selection.

### 1e. Past performance  ·  1f. Opening balances

- [ ] Both. Then **10-day view** and **Reports** answer instead of explaining
      their emptiness.

### 1g. Holidays  ·  1h. SLA rules  ·  1i. Escalation matrix

- [ ] Holidays (73 already loaded — check before adding).
- [ ] SLA rules, then the Escalation matrix.
- [ ] **Then:** Escalation matrix → branches missing levels should fall.

> **If an upload says a zone does not exist, stop and tell me.** Four
> validators were checking the wrong tree — they wanted one of the six
> regions where you meant an operating zone like Pune or Mumbai. Fixed
> today, and every template's own example now passes. If it comes back, the
> fix did not hold somewhere I have not looked.

---

## 2. The screens, once there is data

All 28 endpoints answered 200 as an administrator on 25 Sept. What follows
is what only you can judge: whether the answer is *right*.

| Screen | What to check |
|---|---|
| Dashboard | The counts match what you believe about today |
| Clients | A client opens to its locations, branches and matrix |
| Escalation matrix | The five levels are the people you expect |
| Coverage & handlers | 1,128 rules. Pick a location, add a person, it holds |
| My team & structure | **Drag a chair onto its new manager.** Everything under it comes too. Dropping it inside its own subtree is refused |
| Org chart | Reads the same structure |
| My profile | Your chair, coverage and reporting line |
| Performance & appraisal | File a daily count. It should read back **as numbers, not as text** |
| Penalty ledger | Five of twelve rules still have no amount |
| Hiring / Joining / HR | Raise a hire, approve it, see it in Joining |
| Visits & claims | Log a visit. The branch contact updates |
| Ideathon | Raise one, then decide on it |
| Report access | Inherited vs granted, shown apart |
| History & audit trail | Every change above appears here |
| Automations | 49 designed, 46 live — and beside it what **actually** runs |
| Settings | Read down it once. Change what you disagree with |

---

## 3. What I know is still wrong

Stated so you do not have to find it.

- **Five penalty amounts are unset** (P-02 to P-05, P-07). Nothing fires
  until you set them, which is deliberate.
- **Ten people in the org chart do not exist in the tool** — Maruf Shaikh,
  Faizan Bagwan, Harshita Gupta, Pranish Khankal, Sneha Kadam, Piyush Singh,
  Sandhya Jaiswar, Jyostna Patil, Shiladitya, Vishal Pandey.
- **533 of the 636 rows in `person` are your clients' branch staff**, not
  yours. They hold no chair and see nothing, but every headcount counts them.
- **Arun Bodupali vs Virendra Pal** — they were recorded reporting to each
  other. Arun is now the top. Confirm or reverse it; it is in Review.
- **`api/routes/pms.ts` has a double-encoding bug** that `api` is too large
  to redeploy from here. A database trigger now unwraps it, so a filed daily
  count is stored correctly. The line should still be corrected.

## 4. Tell me

- Any error message that names something you know exists.
- Any screen that shows a number you cannot explain.
- Any upload refused for a reason that is not your file's fault.

Those three are the ones worth my time. Everything else you can probably
fix in Settings.
