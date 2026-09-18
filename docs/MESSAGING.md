# Getting things out of the building

Two channels, same discipline. Both are configured by an administrator in the
tool; neither can be configured by anyone else, and neither ever shows a
secret back to the person who pasted it.

| | Mail | WhatsApp |
|---|---|---|
| screen | **Mail** | **WhatsApp** |
| function | `crux` (`/api/mail/*`) | `wa` |
| queue | `outbox` | `wa_outbox` |
| budget | `mail_budget` | `wa_budget` |
| drain | `crux_mail_tick()`, every minute | `crux_wa_tick()`, every minute |
| switch | `job_config.MAIL_DRAIN` | `job_config.WA_DRAIN` |

## What an administrator does

**Mail** — pick a provider (Resend, SendGrid, Brevo, Postmark) and paste its
API key, or connect your own Gmail mailbox through the consent flow. SMTP and
app passwords are not possible here and the screen says so: this runs as an
edge function, which may make an HTTPS request and nothing else, so there is
no socket to port 587 for an app password to go to.

**WhatsApp** — pick Meta's Cloud API or Twilio.

- *Meta*: put the **Phone Number ID** in From and a permanent access token in
  Token. Leave Account blank.
- *Twilio*: put the sending number in From as `whatsapp:+14155238886`, the
  **Account SID** in Account, and the auth token in Token.

Then **Send me a test** on either screen. It queues the message and pushes it
straight out, so the answer on screen is the real answer rather than a
hopeful one.

## Rules both channels keep

- **Nothing sends until a sender is configured.** `wa_claim` returns nothing
  while `ready` is false, so an unconfigured tool holds its messages instead
  of losing them. The queue depth is on the screen.
- **One message per thing that happened.** The idempotency key is derived
  from template + recipient + entity + scope, so a hundred triggers firing
  produce one message. This was regression-tested: 100 attempts, 1 row.
- **A daily cap.** Whatever else goes wrong, the tool cannot send more than
  the cap in a day.
- **Back off, then say why.** Five attempts with widening gaps, then
  `ABANDONED` with the provider's own error kept against the row. A message
  that cannot be delivered ends somewhere an administrator can see it.
- **The key goes in and never comes out.** `wa_status` and `mail_status`
  answer *whether* a secret is set, never what it is. A blank token field
  means "leave the one you have"; only **Forget the token** clears it, so a
  half-filled form cannot disconnect you.

## How WhatsApp gets its traffic

It mirrors the mail outbox. Rather than edit every function that notifies
somebody — `ogl_notify` passes its template key as a variable, so there is no
fixed list to enumerate — a trigger on `outbox` insert queues the same
message to WhatsApp when the recipient is a person with a mobile number.

The mirror carries the e-mail's own idempotency key as its scope, so the
storm protection that stops a hundred triggers becoming a hundred e-mails
also stops them becoming a hundred WhatsApp messages. The subject becomes the
first line; block tags become line breaks before the rest of the markup is
stripped, so a paragraph does not run into the next one.

`whatsapp_mirror` controls it, on the WhatsApp screen: `all` (the default),
`off`, or a comma-separated list of template keys.

A mirror failure can never stop an e-mail being queued — the trigger swallows
its own errors on purpose.

## Numbers

`wa_e164` is what makes `9021469966`, `90497 05664`, `+91 90497 05664`,
`09049705664` and Excel's `8104660689.0` one recipient. Without it the
idempotency key would not hold and somebody would be messaged several times.
The country code prefixed to a bare ten-digit number is configurable and
defaults to 91.

Today **39 of 606 people have a mobile on record**, so that is who WhatsApp
can currently reach. A missing mobile no longer blocks the People upload; it
is recorded as a question for HR instead.

## The 24-hour window

Outside the 24 hours after somebody messages you first, WhatsApp only accepts
a template you have had approved. Free text works inside that window.
`wa_outbox` carries `template_name`, `template_lang` and `template_vars` for
that reason, and the Meta transport sends a template message when a row names
one. Nothing the tool queues today names one — that is a deliberate gap, to be
filled once the business has templates registered.

## Provider failures, in words

The WhatsApp screen translates the codes that actually come back, and keeps
the provider's own text underneath. The ones worth knowing:

| Code | What it means | What to do |
|---|---|---|
| Twilio `572002`, `21608` | Trial account: it will only message verified numbers, or numbers that have joined your sandbox | Have the recipient send the sandbox join phrase, or upgrade the account |
| Twilio `63007` | The From number is not a WhatsApp sender | Use the sandbox number `whatsapp:+14155238886` until your own is approved |
| Twilio `20003` | Credentials refused | Check the Account SID and auth token |
| Twilio `63016`, Meta `131047` | More than 24 hours since that person messaged you | Free text is refused; an approved template is required |
| Meta `190` | Access token expired or not permanent | Generate a permanent system-user token |
| Meta `131030` | App is in development mode | Add the number to the allowed list, or take the app live |
| Meta `131026`, `133010` | Undeliverable | The number is not on WhatsApp, or the sender is not registered |
| Meta `100` | Bad parameter | Usually the wrong value in From — it is the numeric **Phone Number ID**, not the phone number |

## Why not WhatsApp Web with a QR code?

It is a real technique — Puppeteer or `whatsapp-web.js` driving a headless
browser against web.whatsapp.com — and it is the wrong choice here, for three
separate reasons.

**It cannot run in this architecture.** Supabase Edge Functions are short-lived
Deno isolates. They can make an HTTPS request and nothing else: no browser, no
persistent filesystem for a session profile, no process that stays alive
holding a websocket for days. Running it would mean standing up and paying for
a separate always-on server whose only job is to keep one browser logged in.

**It is against WhatsApp's terms.** Unofficial automation is explicitly
prohibited, and the enforcement is a ban on the number. For a company number
that staff rely on for escalation alerts, losing it is worse than not having
the channel.

**It breaks quietly.** The session drops, the QR needs rescanning by a human,
and a WhatsApp update breaks the library. An alerting channel that silently
stops is worse than one that was never switched on.

The Cloud API is the supported route: no QR, no browser, a permanent token,
and failures that come back as codes you can read. Twilio is the quicker start
and costs more per message.
