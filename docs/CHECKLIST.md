# Your checklist

Tick these off in order. Nothing later works properly until the ones above it
are done. Anything not on this list is not yours to do.

---

## 1. Turn on e-mail

- [x] Sign in to Google as **operations.alert@cruxindia.co.in**
- [x] Open <https://script.new>, name it `Crux mail relay`
- [x] Paste in all of `mailer/crux-mail.gs`, save
- [x] Run `makeSecret` → allow when Google asks → copy the long string it prints
- [x] Run `selfTest` → check a mail arrives in operations.alert@
- [x] **Deploy → New deployment → Web app**, Execute as **Me**, access **Anyone** → copy the `/exec` URL
- [x] In Crux: **Mail → Provider → Apps Script relay**, paste the URL and the secret, **Save the relay**
- [x] Press **Check the link** — it must say it sends as operations.alert@cruxindia.co.in
- [x] Press **Send me a test**

Full steps with screenshots-worth of detail: `mailer/README.md`.

> **Done — mail is live.** Nine messages have gone out through the relay as
> operations.alert@cruxindia.co.in.

---

## 2. Turn on WhatsApp — or skip it

Skip this if you would rather wait for the paid route. Nothing breaks.

- [ ] **WhatsApp → Add a sending device**, name it, copy the token (shown once)
- [ ] On the laptop or spare phone: `cd bridge`, `npm install`, put the token in `.env`, `npm start`
- [ ] A red alert appears in Crux — press **Show the code** and scan it with the phone that owns the company number

---

## 3. Upload the masters, in this order

Each one: **Data setup → choose the kind → download the template → fill it →
upload → check the preview → apply.** A file with any error loads **nothing**,
so a rejected file is safe to fix and send again.

- [x] 1 Chairs — loaded, see the note below
- [x] 2 People — loaded
- [x] 3 Geography — loaded
- [x] 4 Clients and branches — loaded
- [ ] 5 Assignments  ← **the important one, and it comes pre-filled**
- [ ] 6 Rates
- [ ] 7 Collections
- [ ] 8 KPI targets
- [ ] 9 Past performance
- [ ] 10 Opening balances
- [ ] 11 Holidays
- [ ] 12 SLA rules
- [ ] 13 Escalation matrix

Three notes:

- **Your chairs file needs one fix before you send it again.** Every title with
  a dash in it arrived with its last two letters missing — `Head – Operations`
  came in as `Head _ Operatio`. Whatever wrote that file cut the titles short
  because a dash counts as three bytes and it only allowed for one. The tool
  read the file exactly as given; the 34 damaged titles have been repaired in
  place, so there is nothing for you to do unless you upload that same file
  again. If you do, save it from Excel as **CSV UTF-8**, or replace the dashes
  with a plain hyphen first.
- **Geography: `region` is the tree, `zone` is yours.** `region` (East, West,
  North, South, Central, North East) is the top of the geography tree — states
  and cities hang off it. `zone` is the operating zone a place is served from
  (Kolkata, Amaravati, Pune) and repeats down the file, one row per city.
  Loading your file moves five states to the region you put them in — Assam to
  North East, Bihar and Jharkhand to North, Chhattisgarh to West, Andaman to
  East. All 139 branches on them stay attached, and each move is listed under
  **Review** so you can see it and undo it.
- **The Assignments template downloads already filled in.** All 59 client and
  location pairs that have branches, with a suggested handler on 21 of them
  carried across from who covers those branches today, and the handler's
  manager as a starting location head. The notes at the bottom of the file say
  where every filled-in value came from. Correct it and add the 38 blanks.
- **One word, two meanings — now separated.** Your *operating* zone (Mumbai,
  Amaravati, Patna) is who runs a place. The *region* (East, West, North,
  South, Central, North East) is where it is on the map. Geography defines
  both; Clients, Assignments and everything after it use the operating zone.
  Your seven zones now exist under **Configuration → Locations** and can be
  renamed or added to there.
- **Assignments decides who sees what.** Only 15 people have coverage today, so
  most screens are empty for most people until this file lands.
- Clients and branches has a new optional **`opened_on`** column. Blank is fine.

---

## 4. Decide six things

- [ ] **The five missing penalty amounts** — P-02 to P-05 and P-07 were never
      published. Set them in **Configuration → Penalty rules**, or leave them.
      Nothing fires until you do.
- [ ] **When to switch the penalty rules on.** Not before KPIs exist, or
      everyone gets charged for not filing a count nobody asked them for.
- [ ] **Ten people in the org chart do not exist in the tool** — Maruf Shaikh,
      Faizan Bagwan, Harshita Gupta, Pranish Khankal, Sneha Kadam, Piyush
      Singh, Sandhya Jaiswar, Jyostna Patil, Shiladitya, Vishal Pandey. Either
      add them in the People upload, or the chart names people who have left.
- [ ] **Where 31 chair holders sit.** Most of it is answered by the Assignments
      upload. For the rest: **Org chart → pick the chair → choose the place.**
- [ ] **Does `operations.alert@` hold a chair?** Today it is an admin account
      with no seat. That is fine if deliberate.
- [ ] **The EMAIL_LOG and AUDIT_LOG staging files.** One cut-over check is
      waiting on them and cannot pass without them.

---

## 5. Before you tell anyone to use it

- [ ] Open **Configuration** and read down it once. Every number the tool runs
      on is there, each with a line saying what it does.
- [ ] Change the ones you disagree with.
- [ ] Check **Configuration → What runs by itself** — seven jobs, all on.

---

*Longer version, if you ever want it: `docs/WHAT_IS_BUILT.md`. You should not
need it to get running.*
