// The two mail switches, as the administrator sees them (270).
//
// "Add that pause and unpause button for admin ... And same but different
//  button for normal internal mails too" -- 16 Oct. This loads
// build/app/screen-mail-pause.js (the Mail screen's two cards) and
// build/app/screen-matrix-month.js (the matrix Send), stubs what the page
// provides, and asserts what an administrator is shown and what a press
// sends to the server.
//
//   /opt/node22/bin/node build/test/mailpause_check.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const read = (f) => readFileSync(join(here, "..", "app", f), "utf8");
let pass = 0; const fails = [];
const ok = (n, c, saw) => { if (c) { pass++; console.log("PASS  " + n); }
                            else fails.push(n + (saw === undefined ? "" : "  -- saw: " + saw)); };
const esc = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
  .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const msg = (k, t) => (t ? '<div class="msg ' + k + '">' + esc(t) + "</div>" : "");

// ------------------------------------------------------------- the cards
let buttons = [], confirmSays = null, confirmAnswer = true, sent = [], boxes = {};
const doc = { querySelectorAll: () => buttons };
const el = (id) => boxes[id] || (boxes[id] = { innerHTML: "" });
const crux = async (path, o) => { sent.push({ path, body: o && o.body });
                                  return { ok: true, note: "done" }; };
const confirmFn = (t) => { confirmSays = t; return confirmAnswer; };
const M = new Function("esc", "when", "msg", "el", "crux", "confirm", "document",
  `${read("screen-mail-pause.js")}\nreturn { mpCard, mpConfirm, mpWire, mpIsPaused };`)(
  esc, (s) => "when:" + s, msg, el, crux, confirmFn, doc);

const both = { pause: {
  internal: { paused: true, heldMail: 12, heldWhatsapp: 721, since: "2026-10-16", by: "Ops <Admin>" },
  client:   { paused: true, heldMail: 0, heldWhatsapp: 0 } } };
let h = M.mpCard(both);
ok("both switches are drawn, as two different cards",
   (h.match(/class="card mpcard/g) || []).length === 2 &&
   h.includes("Internal mail") && h.includes("Client escalation matrix"), h.length);
ok("both say Paused, and offer Unpause",
   (h.match(/>Paused</g) || []).length === 2 && (h.match(/data-mpto="on"/g) || []).length === 2 &&
   h.includes("Unpause internal mail") && h.includes("Unpause client escalation matrix"));
ok("the internal card says how much is waiting, e-mail and WhatsApp",
   h.includes("12 e-mails and 721 WhatsApp copies waiting"));
ok("a switch holding nothing says so", h.includes("Nothing is waiting."));
ok("who changed it is escaped", h.includes("Ops &lt;Admin&gt;") && !h.includes("<Admin>"));

h = M.mpCard({ pause: { internal: { paused: false }, client: { paused: true } } });
ok("internal on and client paused are drawn apart",
   h.includes("Pause internal mail") && h.includes('data-mpkind="internal" data-mpto="off"') &&
   h.includes("Unpause client escalation matrix") && h.includes(">Sending<"));
h = M.mpCard({ pause: { internal: { paused: true } } });
ok("a switch the server did not describe is drawn as paused, as the database reads it",
   h.includes("Unpause client escalation matrix") && M.mpIsPaused(undefined));
ok("an older server with no switches draws no cards rather than wrong ones",
   M.mpCard({ ready: true }) === "" && M.mpCard(null) === "");

ok("unpausing internal mail says what will be released before it is pressed",
   M.mpConfirm("internal", both.pause.internal).includes("12 e-mails and 721 WhatsApp copies"));
ok("unpausing the matrix says it opens sending to clients",
   /client branches/.test(M.mpConfirm("client", {})));

// ---------------------------------------------------------- the presses
const btn = (kind, to) => ({ disabled: false, onclick: null,
  getAttribute: (a) => (a === "data-mpkind" ? kind : a === "data-mpto" ? to : null) });
let reloaded = 0;
buttons = [btn("internal", "on"), btn("client", "off")];
M.mpWire(both, () => { reloaded++; });
confirmAnswer = false; sent = [];
await buttons[0].onclick();
ok("an Unpause the administrator does not confirm sends nothing",
   sent.length === 0 && /Unpause internal mail/.test(confirmSays || ""));
confirmAnswer = true; sent = [];
await buttons[0].onclick();
ok("a confirmed Unpause asks the server for internal, paused false",
   sent.length === 1 && sent[0].path === "/api/mail/pause" &&
   sent[0].body.kind === "internal" && sent[0].body.paused === false, JSON.stringify(sent));
confirmSays = null; sent = [];
await buttons[1].onclick();
ok("Pause needs no confirm, and asks for client, paused true -- a different switch",
   confirmSays === null && sent.length === 1 &&
   sent[0].body.kind === "client" && sent[0].body.paused === true, JSON.stringify(sent));
ok("the server's own words are shown beside the switch",
   boxes["mpmsg-client"] && boxes["mpmsg-client"].innerHTML.includes("done"));

// ------------------------------------------------- the matrix, when paused
const X = new Function("el", "esc", "msg", "day", "packApi",
  `${read("screen-matrix-month.js")}\nreturn { MX, mxPack };`)(
  () => null, esc, msg, (d) => String(d), async () => ({}));
X.MX.pack = { says: "2 branches ready", recipients: [{ email: "a@bank.in", kind: "PRIMARY" }],
              branches: [{ name: "B1", code: "1", levels: [] }], heldBack: [] };
X.MX.to = { "a@bank.in": true };
X.MX.month = { maySend: true, clientMailPaused: true };
h = X.mxPack();
ok("while client mail is paused, the matrix offers no Send, and says why",
   !h.includes('id="mxsend"') && h.includes("Sending is paused") &&
   h.includes("paused by the administrator"));
X.MX.month = { maySend: true, clientMailPaused: false };
h = X.mxPack();
ok("and unpaused, Send is back", h.includes('id="mxsend"') && !h.includes("Sending is paused"));
X.MX.month = { maySend: false, clientMailPaused: true };
h = X.mxPack();
ok("a chair that may not send is still told it is Operations' to send",
   h.includes("Operations owns the matrix"));

if (fails.length) { for (const f of fails) console.log("FAIL  " + f); }
console.log(`-- mail switches: ${pass} passed, ${fails.length} failed`);
process.exit(fails.length ? 1 : 0);
