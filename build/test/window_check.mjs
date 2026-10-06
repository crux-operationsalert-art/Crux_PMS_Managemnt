// The clock, and what the screen offers once it has run out.
//
// "PMS is not ready, set KPI is still not working and just like that most of
//  the Buttons in PMS are not working."
//
// Measured first, in a browser: every control on Performance & appraisal is
// wired and clickable, there is no JavaScript error, and the writes were
// being refused by the DATABASE. perf_cycle_open sets assign_closes five
// working days after the first of the month, and perf_assign,
// perf_assign_edit and perf_assign_remove all answer window_closed after it
// for anybody but an administrator -- so for about three weeks in four the
// screen offered four KPI controls and every one refused.
//
// That is migration 242's defect said about the clock: a control that is
// always refused is worse than no control.
//
// What is asserted here is the rule the screen now applies, run rather than
// read, and that every KPI control reads it. The code under test is loaded
// out of build/app/screen-perf.js, so this cannot pass against a stale copy.
//
//   /opt/node22/bin/node build/test/window_check.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "app", "screen-perf.js"), "utf8");

let pass = 0;
const fails = [];
function ok(name, cond, saw) {
  if (cond) { pass++; console.log("PASS  " + name); }
  else { fails.push(name + (saw === undefined ? "" : "  -- saw: " + saw)); }
}

const esc = (s) => String(s ?? "")
  .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  .replace(/"/g, "&quot;");

const harness = `
${src}
return { PF, pfSetWindowOpen, pfMayExtend, pfShutHere, pfReopenForm,
         pfSaid, pfTeamSection, pfPersonPanel, pfMeasureAdmin,
         setMe: function(x){ me = x; } };
`;
let me = null;
const mod = new Function(
  "el", "esc", "msg", "day", "plb", "perfApi", "api", "money", "when",
  "route", "pbOkr", "pbWire", "scope",
  harness)(
  () => null, esc,
  /* The real msg() puts the kind on the element, and whether a refusal
     reads as a warning or as a fault is one of the things asserted. */
  (k, t) => (t ? '<div class="msg ' + k + '">' + t + "</div>" : ""),
  (d) => String(d ?? ""),
  async () => ({}), async () => ({}), async () => ({}),
  (n) => "₹" + n, (s) => String(s), () => {}, () => "", () => {}, null);

const { PF, pfSetWindowOpen, pfMayExtend, pfShutHere, pfReopenForm,
        pfSaid, pfPersonPanel, pfMeasureAdmin, setMe } = mod;

const OPEN  = { id: "c1", period_start: "2026-10-01", assign_closes: "2026-10-08",
                entry_closes: "2026-11-06", assign_open: true, entry_open: true };
const SHUT  = Object.assign({}, OPEN, { assign_closes: "2026-09-07",
                assign_open: false });

const MANAGER = { app_role: "MANAGER", department: "Operations" };
const ADMIN   = { app_role: "ADMIN",   department: null };
const HR      = { app_role: "MANAGER", department: "Human Resources" };
const BIZEX   = { app_role: "MANAGER", department: "Business Excellence" };

// ------------------------------------------------------------- the rule
PF.cycle = OPEN; setMe(MANAGER);
ok("inside the window a manager may set a KPI", pfSetWindowOpen() === true);

PF.cycle = SHUT;
ok("outside it they may not", pfSetWindowOpen() === false);

setMe(ADMIN);
ok("an administrator may still set outside it, because perf_assign lets them",
   pfSetWindowOpen() === true);

PF.cycle = null; setMe(MANAGER);
ok("with no cycle at all nothing may be set", pfSetWindowOpen() === false);

// ---------------------------------------------------- who may reopen it
PF.cycle = SHUT;
for (const [who, name, may] of [[MANAGER, "a manager", false],
                                [ADMIN, "an administrator", true],
                                [HR, "Human Resources", true],
                                [BIZEX, "Business Excellence", true]]) {
  setMe(who);
  ok(`${name} ${may ? "may" : "may not"} reopen a shut month`,
     pfMayExtend() === may);
}
setMe(null);
ok("and nobody signed in may not", pfMayExtend() === false);

// The three are the same three perf_cycle_open and perf_cycle_extend ask
// for. 242's rule: the offer and the write ask the same question.
ok("the screen names the same three the database names",
   /ADMIN/.test(src) && /Human Resources/.test(src) &&
   /Business Excellence/.test(src));

// ------------------------------------- the explanation stands in its place
setMe(MANAGER); PF.cycle = SHUT; PF.period = "2026-09-01";
const note = pfShutHere("Setting a KPI for Manish Shukla");
ok("the shut note names the control it replaced",
   note.includes("Setting a KPI for Manish Shukla"), note.slice(0, 90));
ok("and the date the window closed", note.includes("2026-09-07"));
ok("and tells a manager who can reopen it",
   /HR, Business Excellence or an administrator/.test(note));
setMe(HR);
ok("and tells HR they can do it themselves",
   /You can reopen the month/.test(pfShutHere("x")));

// ------------------------------------------ every KPI control reads the rule
setMe(MANAGER); PF.cycle = SHUT;
PF.whoTree = { person: { name: "Manish Shukla" },
               measures: [{ assignmentId: "a1", name: "Cases", unit: "COUNT" }] };
const panel = pfPersonPanel();
ok("with the window shut, Set a KPI is not offered",
   !panel.includes('id="pfadd"'), panel.slice(0, 120));
ok("and the reason is there instead", panel.includes("pfshut"));

const admin = pfMeasureAdmin(PF.whoTree.measures);
ok("nor Edit", !admin.includes("data-pfedit"));
ok("nor Remove", !admin.includes("data-pfrm"));
ok("and that card says why too", admin.includes("pfshut"));

PF.cycle = OPEN;
ok("with the window open, Set a KPI is offered again",
   pfPersonPanel().includes('id="pfadd"'));
ok("and so are Edit and Remove",
   pfMeasureAdmin(PF.whoTree.measures).includes("data-pfedit") &&
   pfMeasureAdmin(PF.whoTree.measures).includes("data-pfrm"));

setMe(ADMIN); PF.cycle = SHUT;
ok("an administrator is still offered all three outside the window",
   pfPersonPanel().includes('id="pfadd"') &&
   pfMeasureAdmin(PF.whoTree.measures).includes("data-pfrm"));

// ------------------------------------------------------ the reopen form
setMe(HR); PF.cycle = SHUT; PF.reopen = { until: "2026-10-20", why: "" };
const form = pfReopenForm();
ok("the reopen form cannot be sent past the day filing closes",
   form.includes('max="2026-11-06"'), form.slice(0, 200));
ok("and asks for the reason the database insists on",
   form.includes("pfreopenwhy"));
ok("and says the change is recorded", /recorded/.test(form));

// ----------------------------------------------- the refusal reads as one
setMe(MANAGER);
const said = pfSaid({ error: "window_closed", reason: "KPIs for 2026-09-01 had to be set by 2026-09-07." });
ok("a window_closed refusal is a warning, not a fault",
   said.includes("warn") && said.includes("2026-09-07"), said.slice(0, 120));
ok("and a manager is not told to do something they cannot",
   !said.includes("You can reopen"));
setMe(HR);
ok("while HR is told they can reopen it",
   pfSaid({ error: "window_closed", reason: "x" }).includes("You can reopen"));

// ------------------------------------------------- one rule, decided once
ok("the window question is asked in exactly one place",
   (src.match(/function pfSetWindowOpen\(/g) || []).length === 1 &&
   (src.match(/assign_open !== false/g) || []).length === 1,
   String((src.match(/assign_open !== false/g) || []).length));
ok("and no KPI control tests the clock for itself",
   !/assign_open\s*\?/.test(src.replace(/bits\.push\(c\.assign_open[\s\S]*?\n/, "")));

console.log("");
if (fails.length) {
  fails.forEach((f) => console.log("FAIL  " + f));
  console.log(`-- the window: ${pass} passed, ${fails.length} failed`);
  process.exit(1);
}
console.log(`-- the window: ${pass} passed, 0 failed`);
