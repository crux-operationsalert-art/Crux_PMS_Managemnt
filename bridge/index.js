// =====================================================================
// Crux - the WhatsApp sending device.
//
// This program holds a linked WhatsApp session and sends the messages the
// tool has queued. It runs on a machine the company owns: a laptop that
// stays on, or a spare Android through Termux.
//
// It is a stop-gap. The owner chose it knowingly while the Cloud API is
// approved, and it carries the risks that choice implies - see
// docs/MESSAGING.md. Everything here is written to make those risks
// smaller: it sends slowly, it stops at a daily ceiling, and when the
// link breaks it says so loudly in the tool rather than failing quietly.
//
// It talks to one endpoint and holds one secret. It can ask for work and
// report what happened, and nothing else - it cannot read a person, a
// case or a setting.
// =====================================================================
import { readFileSync, existsSync } from "node:fs";
import pkg from "whatsapp-web.js";
import qrTerminal from "qrcode-terminal";
import QRCode from "qrcode";

const { Client, LocalAuth } = pkg;

// ------------------------------------------------------------- settings
function loadEnv() {
  if (existsSync(".env")) {
    for (const line of readFileSync(".env", "utf8").split("\n")) {
      const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*)\s*$/);
      if (m && !process.env[m[1]]) process.env[m[1]] = m[2].trim();
    }
  }
}
loadEnv();

const URL_BASE = process.env.CRUX_WA_URL;
const API_KEY = process.env.CRUX_WA_KEY;
const TOKEN = process.env.CRUX_BRIDGE_TOKEN;
const SESSION_DIR = process.env.CRUX_SESSION_DIR || "./.wwebjs_auth";

if (!URL_BASE || !TOKEN) {
  console.error("Set CRUX_WA_URL and CRUX_BRIDGE_TOKEN. Copy .env.example to .env.");
  process.exit(1);
}

const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

// ------------------------------------------------------------ the tool
// Every call carries the bridge token. The publishable key only names the
// project; it grants nothing on its own.
async function call(path, body) {
  const u = URL_BASE + path + (API_KEY ? "?apikey=" + encodeURIComponent(API_KEY) : "");
  const r = await fetch(u, {
    method: "POST",
    headers: { "content-type": "application/json", "x-wa-bridge": TOKEN },
    body: JSON.stringify(body || {}),
  });
  const t = await r.text();
  if (!r.ok) throw new Error(path + ": " + r.status + " " + t.slice(0, 300));
  return t ? JSON.parse(t) : null;
}

// ------------------------------------------------------------- pacing
// The gap and the jitter come from the tool, so they can be changed
// without touching this machine. A message every ~14 to 23 seconds is
// what a person sending by hand looks like; sending faster is what gets
// a number flagged.
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let pacing = { gapSeconds: 14, jitterSeconds: 9 };
const gapMs = () =>
  (pacing.gapSeconds + Math.random() * pacing.jitterSeconds) * 1000;

// --------------------------------------------------------- the session
const client = new Client({
  authStrategy: new LocalAuth({ dataPath: SESSION_DIR }),
  puppeteer: {
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage"],
  },
});

let ready = false;

client.on("qr", async (qr) => {
  ready = false;
  log("Waiting to be linked. The code is also on the WhatsApp screen in Crux.");
  qrTerminal.generate(qr, { small: true });
  // Drawn here rather than in the browser: this string is a linking
  // credential, and it has no business being sent to a public QR-image
  // service so that somebody can look at it.
  let image = null;
  try { image = await QRCode.toDataURL(qr, { margin: 1, width: 320 }); }
  catch (e) { log("could not draw the code:", e.message); }
  try { await call("/bridge/qr", { qr, qrImage: image }); }
  catch (e) { log("could not hand the code to Crux:", e.message); }
});

client.on("authenticated", () => log("Linked."));

client.on("ready", async () => {
  ready = true;
  let phone = null;
  try { phone = "+" + client.info.wid.user; } catch { /* not fatal */ }
  log("Ready" + (phone ? " as " + phone : "") + ".");
  try { await call("/bridge/heartbeat", { state: "READY", phone }); } catch { /* next beat */ }
});

client.on("auth_failure", async (m) => {
  ready = false;
  log("Link refused:", m);
  try { await call("/bridge/heartbeat", { state: "STALE", detail: "Authentication failed: " + m }); }
  catch { /* the sweep will notice anyway */ }
});

client.on("disconnected", async (reason) => {
  ready = false;
  log("Disconnected:", reason);
  try { await call("/bridge/heartbeat", { state: "STALE", detail: "Disconnected: " + reason }); }
  catch { /* the sweep will notice anyway */ }
  // come back by itself rather than needing somebody to restart it
  setTimeout(() => client.initialize().catch((e) => log("restart failed:", e.message)), 15000);
});

// ---------------------------------------------------------- the sending
// A number has to be a WhatsApp account before anything is sent to it.
// Checking first turns "it vanished" into a recorded, permanent reason.
async function resolveChat(to) {
  const digits = String(to).replace(/[^0-9]/g, "");
  const id = await client.getNumberId(digits);
  return id ? id._serialized : null;
}

async function sendOne(m) {
  let chatId;
  try {
    chatId = await resolveChat(m.to);
  } catch (e) {
    return { ok: false, error: "lookup failed: " + e.message, permanent: false };
  }
  if (!chatId) {
    return { ok: false, error: "That number is not on WhatsApp.", permanent: true };
  }
  try {
    const sent = await client.sendMessage(chatId, m.body);
    return { ok: true, messageId: sent?.id?._serialized ?? null };
  } catch (e) {
    return { ok: false, error: e.message, permanent: false };
  }
}

// ------------------------------------------------------------ the loop
let stopping = false;

async function tick() {
  if (!ready) return;
  let work;
  try {
    work = await call("/bridge/claim", {});
  } catch (e) {
    log("could not ask for work:", e.message);
    return;
  }
  if (work?.error) { log("Crux refused:", work.error); return; }

  if (work.gapSeconds) {
    pacing = { gapSeconds: work.gapSeconds, jitterSeconds: work.jitterSeconds ?? 9 };
  }
  const list = work.messages || [];
  if (!list.length) {
    if (work.reason && work.reason !== "pacing") log("nothing to send:", work.reason);
    return;
  }

  log("sending " + list.length);
  for (const m of list) {
    if (stopping) break;
    const out = await sendOne(m);
    try {
      await call("/bridge/result", {
        id: m.id, ok: out.ok, messageId: out.messageId ?? null,
        error: out.error ?? null, permanent: !!out.permanent,
      });
    } catch (e) {
      log("could not report a result:", e.message);
    }
    if (!out.ok) log("failed:", out.error);
    await sleep(gapMs());
  }
}

async function heartbeat() {
  try {
    const r = await call("/bridge/heartbeat", { state: ready ? "READY" : "NEEDS_QR" });
    if (r?.gapSeconds) {
      pacing = { gapSeconds: r.gapSeconds, jitterSeconds: r.jitterSeconds ?? 9 };
    }
  } catch (e) {
    log("heartbeat failed:", e.message);
  }
}

// A break is reattempted, not surrendered to. The interval matches the
// retry the tool tells the administrator to expect.
async function main() {
  log("Starting. Session kept in " + SESSION_DIR);
  await client.initialize();

  setInterval(() => { tick().catch((e) => log("loop error:", e.message)); }, 10000);
  setInterval(() => { heartbeat().catch(() => {}); }, 45000);
}

for (const sig of ["SIGINT", "SIGTERM"]) {
  process.on(sig, async () => {
    stopping = true;
    log("Stopping. Telling Crux, so it does not think this is a break.");
    try { await call("/bridge/heartbeat", { state: "STALE", detail: "Stopped by hand." }); } catch { /* going anyway */ }
    try { await client.destroy(); } catch { /* going anyway */ }
    process.exit(0);
  });
}

main().catch((e) => { console.error(e); process.exit(1); });
