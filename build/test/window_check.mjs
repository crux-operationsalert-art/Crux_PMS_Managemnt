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
         pfSaid, pfTeamSection, pfPersonPanel, pfMapMayEdit, pfWatchBlock,
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
        pfSaid, pfPersonPanel, pfMapMayEdit, pfTeamSection, setMe } = mod;

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
// The person panel IS the Performance mapping panel now (pfMeasureAdmin and
// its Set-a-KPI button were deleted with the journey it replaced). Whether
// its controls are offered is answered by the SERVER (migration 259,
// perf_mapping.mayEdit), with the same test the writers refuse on. What is
// asserted here is that the screen follows that answer and nothing else.
const ROWS = [{ assignmentId: "a1", name: "Cases", unit: "COUNT", weight: 100,
                target: 10, cadence: "MONTHLY", parts: [] }];
function mapping(maySet, mayEdit) {
  PF.map = { tab: "monthly", draft: ROWS.map((r) => Object.assign({}, r)),
             data: { maySet, mayEdit, rel: maySet ? "manage" : "watch",
                     person: { name: "Manish Shukla" }, measures: ROWS,
                     rules: { min: 3, max: 5, cap: 5, count: 1 } },
             hist: null, histOpen: false, row: null, sub: null, says: "" };
  return pfPersonPanel();
}
const CONTROLS = ["data-pfmw=", "data-pfmt=", "data-pfmedit", "data-pfmrm",
                  "data-pfmsub", 'id="pfmsave"'];

setMe(MANAGER); PF.cycle = SHUT;
let shut = mapping(true, false);
ok("with the window shut, the mapping offers no box, Edit, Remove, + or Save",
   CONTROLS.every((c) => !shut.includes(c)),
   CONTROLS.filter((c) => shut.includes(c)).join(","));
ok("and the reason is there instead, where Save would have been",
   shut.includes("pfshut") && shut.includes("2026-09-07"));

PF.cycle = OPEN;
const open = mapping(true, true);
ok("with the window open, all of them are offered again",
   CONTROLS.every((c) => open.includes(c)),
   CONTROLS.filter((c) => !open.includes(c)).join(","));
ok("and no shut note is drawn", !open.includes("pfshut"));

// The administrator's exception lives in perf_mapping, which answers
// mayEdit true for them after the window. The screen does not repeat it.
setMe(ADMIN); PF.cycle = SHUT;
ok("an administrator past the window is offered what the server says",
   mapping(true, true).includes('id="pfmsave"'));

setMe(MANAGER);
const reader = mapping(false, false);
ok("somebody who only reads is told whose they are, not that the month is shut",
   !reader.includes("pfshut") && CONTROLS.every((c) => !reader.includes(c)));

const mayBody = (src.match(/function pfMapMayEdit\(\)\{[\s\S]*?\n\}/) || [""])[0];
ok("the mapping asks the server and does not test the clock for itself",
   /mayEdit/.test(mayBody) && !/assign_open|assign_closes|app_role/.test(mayBody),
   mayBody.slice(0, 120));
ok("and every monthly control reads that one answer",
   (src.match(/var may = pfMapMayEdit\(\);/g) || []).length === 3 &&
   !/PF\.map\.data\.maySet;/.test(src));
PF.map = null;

// ------------------------------------- and so does the live team card
// This is the one that caught the author out: there used to be a SECOND,
// dead drawing of the team card, and the window rule landed in that one.
// So the assertion is made against the function the screen actually calls,
// and the dead copy is gone.
setMe(MANAGER);
PF.team = [{ personId: "p1", name: "Manish Shukla", chair: "Zonal Manager" }];
PF.watch = []; PF.wider = []; PF.sel = {}; PF.who = null; PF.form = null;
PF.taskForm = null; PF.elig = false; PF.find = "";

PF.cycle = OPEN;
const openCard = pfTeamSection();
ok("inside the window the team card offers bulk and carry-forward",
   openCard.includes('id="pfbulk"') && openCard.includes('id="pfcarry"'));

PF.cycle = SHUT;
const shutCard = pfTeamSection();
ok("outside it, neither is offered",
   !shutCard.includes('id="pfbulk"') && !shutCard.includes('id="pfcarry"'));
ok("and the card says why", shutCard.includes("pfshut"));
// Asking somebody for a task is not giving them a measure, and task_assign
// carries no window guard, so it must not be hidden with the others.
ok("but asking for a task is not a measure and stays",
   shutCard.includes('id="pftaskall"') && shutCard.includes('id="pfelig"'));

ok("there is only one drawing of the team card",
   (src.match(/function pfTeamSection\(/g) || []).length === 1 &&
   !/function pfTeam\(\)/.test(src));

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
