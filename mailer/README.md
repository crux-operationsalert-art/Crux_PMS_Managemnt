# The mail relay

Crux sends e-mail through a small Google Apps Script that runs in the
`operations.alert@cruxindia.co.in` account. This is the same mechanism the
internship programme has been using, and it works for a reason worth knowing:

**Apps Script is already allowed to send as the account it runs as.** There is
no OAuth client to register, no client secret to paste, and no refresh token
that quietly expires after six months of disuse. One browser consent, once.

The script holds no data and no templates. Crux keeps the queue, the retries,
the daily cap and the idempotency key that makes a second copy impossible. The
script sends what it is handed.

## Setting it up — four steps, about five minutes

Do this **signed in as `operations.alert@cruxindia.co.in`**. Whichever account
deploys the script is the address every message comes from.

**1. Make the script.**
Open <https://script.new>. Name it `Crux mail relay`. Delete what is in
`Code.gs` and paste all of `crux-mail.gs`. Save.

> **Check the paste landed whole.** The file is 107 lines and its last line is
> `// ===== END OF FILE =====`. If that line is not at the bottom of the
> editor, the copy was cut short and Apps Script will say
> *"SyntaxError: Unexpected end of input"* — which means the file ended before
> it should have, not that anything in it is wrong. Copy it again from
> [the raw file](https://raw.githubusercontent.com/crux-operationsalert-art/Crux_PMS_Managemnt/main/mailer/crux-mail.gs)
> — that page is plain text, so Ctrl+A then Ctrl+C takes all of it.

**2. Make the secret.**
Function dropdown → `makeSecret` → Run. Google asks for authorisation the
first time: choose the account → **Advanced** → **Go to Crux mail relay
(unsafe)** → **Allow**. That wording is what Google shows for any script it
has not reviewed; this is your own code and every line of it is in this
repository.

Open **Execution log** and copy the long string it printed. That is the shared
secret. It is shown once here and stored in the script's own properties.

**3. Prove it can send, before Crux is involved.**
Function dropdown → `selfTest` → Run. A message arrives in
`operations.alert@`. If it does not, stop here: nothing downstream will work
and the log says why.

**4. Deploy it.**
**Deploy → New deployment → ⚙ → Web app.**

- Description: `Crux mail relay`
- Execute as: **Me**
- Who has access: **Anyone**

Deploy, and copy the URL ending in `/exec`.

> "Anyone" is how a web app is reachable without a Google sign-in. The URL on
> its own does nothing: every request must carry the secret, and a request
> without it is refused before anything is read.

## Pointing Crux at it

On the **Mail** screen, as an administrator:

1. Provider: **Apps Script relay**
2. Relay URL: the `/exec` URL from step 4
3. Relay secret: the string from step 2
4. **Save**, then **Check the link.**

Check the link asks the script who it is. It answers with the real sending
address and the real remaining quota for today, from Google — not from what
you typed. If that address is not `operations.alert@cruxindia.co.in`, the
script was deployed from the wrong account; redeploy it from the right one.

Then **Send a test**. The queue drains within a minute either way.

## What it costs and what it limits

| | |
|---|---|
| Daily ceiling | 1,500 recipients a day on Workspace, 100 on a consumer account. Crux's own cap is 1,500 and stops first. |
| Speed | One message per call. Crux drains fifty a minute, which is well inside the quota and deliberately unhurried. |
| Attachments | Not supported here yet. Nothing Crux sends today has one. |
| A provider reference | There is none. `GmailApp` returns no message id, and inventing one would be worse than having none. The copy in Sent is the record on Google's side; Crux keeps its own row on the other. |

## If you change the script later

Editing the code does **not** change what the deployed URL serves. Apps Script
serves the version you deployed. After an edit: **Deploy → Manage deployments
→ ✏️ → Version: New version → Deploy.** The URL stays the same.

## If the secret leaks

Anyone holding the URL and the secret can send as the company. To cut it off:
run `makeSecret` again — the old secret stops working the moment the new one
is written — and paste the new one into Crux.
