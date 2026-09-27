# Status

**Three sign-in fixes are LIVE** — published 27 Sep (473ce37, dd309e0),
applied at publish time by `.github/build-tool.py` because Supabase could not
be reached. Hard-refresh (Ctrl/Cmd + Shift + R) to get past the cached copy.

1. **The Google button was losing a race.** `boot()` tested for the GSI
   library exactly once, and the library is loaded `async defer`, so on a
   cold cache the else branch ran and wrote *"Google sign-in is still
   loading, or is not configured yet."* as a **final** answer with no retry.
   That is the sentence on the screen recording. It now waits up to eight
   seconds. Reproduced by serving the library 2.5s late: live page no button,
   patched page button renders.
2. **The password box could never work** — 635 active people, zero password
   hashes — and Chrome had autofilled WORK E-MAIL with the company name,
   "Crux Risk Management Pvt Ltd", which was being sent and refused. It now
   refuses a non-address before the round trip and says why nobody can sign
   in that way.
3. **The unguarded `localStorage` read** (below), which killed the whole
   script when a browser refuses site data.

**If Google still fails after this**, the last frame of the recording shows
the account chooser opening and then a blank `accounts.google.com/gsi/transform`
popup. That is Google refusing the handshake, and the usual cause is the
origin not being listed on the OAuth client. Check that
`https://crux-operationsalert-art.github.io` is an **Authorized JavaScript
origin** on client `1064617222271-tj4d14h5ngegc4la0b0i5f3u472q4ps0`. Only
someone with the Google Cloud console can see or change that.

Everything else below is still written, verified and not applied.

# Written, verified, not yet applied

The Supabase MCP approval gate refused every call while this was built —
including a bare `select 1` — so nothing below has touched the project.
Everything here is finished and tested as far as it can be without the
database. Applying it is four steps and should take a couple of minutes.

## Apply in this order

1. **`build/migration/187_act_as_a_person_or_a_chair.sql`**
   Adds `auth_session.acting_actor_id`, rewrites `auth_whoami` (which also
   fixes the header showing `ADMIN`/`VIEWER` where a chair belongs — it
   never returned `chair_title` or `department`), adds `auth_act_targets()`
   and `auth_act_as()`. Both new functions are revoked from `anon` and
   `authenticated`.

2. **Redeploy the `hr` edge function to v4** from
   `build/supabase/functions/hr/` (`index.ts`, `shim.ts`, `routes/hr.ts`).
   Two new routes: `GET /hr/act/targets`, `POST /hr/act/as`. The route file
   parses cleanly under esbuild.

3. **`build/migration/188_the_line_that_locked_somebody_out.sql`**
   Asserts app_page md5 `71517ea6deba74aa8cdfd3356d344116` (369,077 chars)
   before touching anything. Guards the four unguarded `localStorage`
   calls, removes the dead `vPeople`, and splices in the act-as bar.

   The storage guards in it are now also applied at publish time, so the
   live page already has them. 188 puts them in the source where they
   belong; once it lands, the publish-time patch detects them and becomes a
   no-op, and can then be deleted from `build-tool.py`.

4. **Bump `.github/app-page.sha`** to whatever 188 leaves, and push. The
   workflow republishes `index.html`.

## The sign-in bug, reproduced and fixed

Line 554 of the published page is the **first statement in the script**:

```js
var token = localStorage.getItem("cruxToken") || "";
```

`localStorage` does not return `null` when a browser refuses it — it
**throws**. Private windows, blocked site data, some managed-device
policies. Because that line runs before anything else, the throw takes the
whole script with it: no function is ever defined, `boot()` never runs, the
Google button never renders. What is left is the sign-in card, which is
static HTML, with a Sign in button wired to nothing.

**Reproduced in Chromium with site data blocked**, against the page that was
live: one error, `The operation is insecure.`, and `el("go").onclick`
undefined — the Sign in button has no handler and `boot()` never runs, so the
Google button never renders either. Function declarations hoist, so
`window.boot` still exists, which is why it looks like a working page rather
than a broken one.

It is the only explanation that fits the one piece of evidence that did not:
**`login_attempt` records no failures at all.** Not one. The request was
never made.

After the fix, same test: button wired, `boot()` ran, **zero errors**. With
storage working, patched and unpatched behave identically — app opens, 21 nav
links, no errors.

Three further sites do the same thing unguarded — both places a token is
stored after a successful sign-in, and sign-out. All four now go through
`aaGet` / `aaSet` / `aaDrop`, which catch and carry on. A browser that
will not remember the token still signs in; it just has to sign in again
next time, which is worth more than a page that will not load.

## What was verified without the database

Migration 188 was **simulated end to end** against the published
`index.html` — every assertion it makes was run locally and passed:

| Check | Result |
|---|---|
| `async function vHR(){` | 1 |
| `function vHR(){` total | 1 |
| `function vPeople(` | 1 (was 2) |
| async declarations | +2 (+3 from the screen, −1 dead vPeople) |
| `localStorage.` | 3 — only inside the three guards |
| `aaPaint` declared | 1 |
| `id="aabar"` | 1 |
| Both script blocks under `node --check` | pass |

Then the simulated page was **driven in Chromium**, signed in as three
different people:

| As | Picker | Banner | Header | Page errors |
|---|---|---|---|---|
| Operations Alert (ADMIN) | shown | — | Operations Alert / Administrator | 0 |
| Ananya Gawade (VIEWER) | **hidden** | — | Ananya Gawade / **Executive** | 0 |
| Acting as Vinayak Jondale | hidden | shown, with Stop | Vinayak Jondale / **Branch Manager** | 0 |

The picker was opened and driven: 2 people listed, 2 chairs listed, the
chair with nobody in it **disabled**, and typing `ananya` narrowed the list
to one. The header showing a chair rather than `ADMIN` is the `auth_whoami`
fix — the page had always asked for `chair_title`; it had never been given
one.

## Still not done

- **The second sign-in door.** A one-time code to the work address, so
  Google is not the only way in. Nobody has a password — 635 active people,
  zero hashes — so `/api/login` cannot succeed for anyone, and there is no
  Activate control even though the activation e-mail tells people to use
  one. Guarding `localStorage` removes the likely cause of the lockout; it
  does not remove the single point of failure.
- **Folding bonus into the one Performance screen.** The nav shows two
  Performance entries where the design has one.
- **Per-chair navigation.** The design gives every chair its own nav list;
  the build shows one flat nav to everybody. See
  `build/AUDIT_design_vs_built.md`.
