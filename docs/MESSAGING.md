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

## WhatsApp Web, and what it costs

The Cloud API is the supported route and it is where this ends up. Until the
company's number is approved for it, WhatsApp goes out through a linked
device: a small program (`bridge/`) that holds a WhatsApp Web session on a
machine the company owns, asks the tool for work, and sends it.

The owner chose this knowingly, as a stop-gap. These are the costs, stated
rather than buried:

**It is against WhatsApp's terms.** Unofficial automation is prohibited and the
enforcement is a ban on the number. That is the whole risk; nothing below
removes it, it is only made less likely.

**It needs a machine that stays on.** A laptop or a spare Android through
Termux. Either is fine, and more than one can run at once — they take work from
the same queue and never take the same message twice.

**It needs a person now and then.** When the session drops, somebody has to
scan a QR code on the phone that owns the number.

### What the tool does about each of those

*Pace.* Messages leave one at a time, with a gap of about fourteen seconds plus
a random extra up to nine, a ceiling of four per poll, and a hard limit of 180
a day per device — well under what a person could plausibly send by hand. The
numbers are settings (`whatsapp_web_*`), so they can be lowered without
touching the device.

*Breaks.* When a device drops its link, or simply stops checking in for two and
a half minutes, the tool raises an **urgent alert for the administrator** that
says what happened and when it will be reattempted — five minutes by default.
The device restarts itself; the alert clears on its own when the link comes
back. Messages are held in the queue meanwhile, never lost.

*Scanning.* A device that needs linking raises an urgent alert too, and the QR
is shown on the WhatsApp screen under **Show the code**. The device draws that
picture itself and sends it; the linking string never goes to a third party to
be rendered.

*Blast radius.* A device holds one secret and can reach four endpoints: ask for
work, report a result, say it is alive, hand over a QR. It cannot read a
person, a case, or a setting. Retiring a device kills its token and returns
anything it was holding to the queue.

When the Cloud API is approved, switch the provider on the WhatsApp screen and
retire the devices. Nothing else changes — the queue, the templates, the caps
and the audit trail are the same either way.
