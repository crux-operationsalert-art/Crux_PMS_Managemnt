# The WhatsApp sending device

This holds a linked WhatsApp session and sends what Crux has queued. It runs
on a machine you own that stays on.

**It is a stop-gap.** It was chosen knowingly while the Cloud API is approved.
Read *WhatsApp Web, and what it costs* in `docs/MESSAGING.md` before
relying on it — the short version is that unofficial automation is against
WhatsApp's terms and the penalty is a ban on the number.

Everything here exists to make that risk smaller: it sends slowly, it stops at
a daily ceiling, and when the link breaks it says so in the tool rather than
failing quietly.

## Setting it up

**1. Add the device in Crux.** WhatsApp screen → *Add a sending device*. Give
it a name you will recognise. You are shown a token **once** — copy it now. If
you lose it, retire the device and add another.

**2. Install.** Node 18 or newer, on the machine that will stay on.

```
cd bridge
npm install
cp .env.example .env      # then paste the token into CRUX_BRIDGE_TOKEN
npm start
```

**3. Link it.** A QR code appears in the terminal, and at the same moment an
urgent alert appears in Crux; press **Show the code** on the WhatsApp screen
to see the same code there. On the phone that owns the
company number: **WhatsApp → Settings → Linked devices → Link a device**, and
scan. The code changes about every minute; if it expires, a new one appears.

That is the only step that needs a human. Once linked, the session persists in
`.wwebjs_auth/` and survives restarts.

## Running it properly

Keep it running. On a laptop:

```
# macOS / Linux, survives logout
nohup npm start > bridge.log 2>&1 &
```

For something that restarts on boot, use `pm2`, a systemd unit, or Task
Scheduler on Windows. On a spare Android, Termux with `pkg install nodejs`
works; iOS cannot run it.

**More than one device is fine and is the point.** Add a second — a laptop and
a spare phone — and whichever is online takes the work. Neither is
special and nothing is duplicated: a message is claimed by exactly one device.

## What it does when things go wrong

| | |
|---|---|
| The link drops | It tells Crux immediately, raises an **urgent** alert naming the device, and reconnects by itself after 15 seconds. Queued messages wait; nothing is lost. |
| It stops checking in | Crux notices within about two and a half minutes and raises the same alert. |
| A message fails | It goes back in the queue and is retried in 5 minutes. After five attempts it is abandoned with the reason kept against it. |
| The number is not on WhatsApp | Abandoned immediately, saying so. Retrying would never help. |
| The daily ceiling is reached | It stops for the day. The queue holds. |

## The pacing

A message every 14–23 seconds per device, at most 4 taken per poll, at most
180 a day per device. Sending faster than a person plausibly would is what
gets a number flagged.

Those numbers live in Crux (`whatsapp_web_*` settings), not here, so they can
be changed without touching this machine. The bridge picks up the new values
on its next heartbeat.

## What it can reach

One endpoint, with one token. It can ask for work and report what happened.
It cannot read a person, a case, a client or a setting. If the machine is lost,
retire the device in Crux and the token stops working.

Never commit `.env` or `.wwebjs_auth/` — the first is the token, the second is
a logged-in WhatsApp session.
