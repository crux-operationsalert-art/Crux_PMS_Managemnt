// The Daily update: every KPI, with its sub-KPIs under it.
//
// "I (reportee) can currently see only KPIs (that too not all) and even the
//  sub KPIs are looking like KPIs and not sub KPIs like the way I (as
//  managers) can see" -- 16 Oct. The card drew only what /perf/due returned
// for today, so a measure with sub-KPIs vanished (it is never filed itself)
// and each sub-KPI arrived as a row of its own, its label printed twice.
// This loads build/app/screen-perf.js and asserts what a reportee sees.
//
//   /opt/node22/bin/node build/test/daily_check.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "app", "screen-perf.js"), "utf8");
let pass = 0; const fails = [];
const ok = (n, c, saw) => { if (c) { pass++; console.log("PASS  " + n); }
                            else fails.push(n + (saw === undefined ? "" : "  -- saw: " + saw)); };
const esc = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
  .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const { PF, pfDaily } = new Function("el", "esc", "msg", "day", "plb", "perfApi", "api",
  "money", "when", "route", "pbOkr", "pbWire", "scope",
  `${src}\nreturn { PF, pfDaily };`)(
  () => null, esc, (k, t) => (t ? '<div class="msg ' + k + '">' + t + "</div>" : ""),
  (d) => String(d ?? ""), async () => ({}), async () => ({}), async () => ({}),
  (n) => "₹" + n, (s) => String(s), () => {}, () => "", () => {}, null);

PF.cycle = { entry_open: true, entry_closes: "2026-11-06" };
PF.tree = { measures: [
  { assignmentId: "rev", name: "Branch revenue", unit: "rupees · R6", target: 3697650, value: 0,
    cadence: "DAILY", parts: [
      { assignmentId: "p1", name: "SBI", split: "SBI", target: 1336500, value: 0, cadence: "DAILY" },
      { assignmentId: "p2", name: "BOM", split: "BOM", target: 412500, value: 0, cadence: "DAILY" },
      { assignmentId: "p3", name: "IDBI Bank", split: "IDBI Bank", target: 990000, value: 0, cadence: "WEEKLY" }] },
  { assignmentId: "tat", name: "Turnaround time", unit: "hours", target: 48, cadence: "DAILY", parts: [] },
  { assignmentId: "q", name: "Branch quality", unit: "% score", target: 95, cadence: "MONTHLY", parts: [] }] };
PF.due = [
  { assignmentId: "p1", name: "SBI", split: "SBI", cadence: "DAILY", target: 1336500 },
  { assignmentId: "p2", name: "BOM", split: "BOM", cadence: "DAILY", target: 412500 },
  { assignmentId: "tat", name: "Turnaround time", cadence: "DAILY", target: 48 },
  { assignmentId: "late", name: "Set after the page loaded", cadence: "DAILY", target: 5 }];

let h = pfDaily();
const boxes = (h.match(/data-pffile="([^"]+)"/g) || []).map((x) => x.split('"')[1]);
ok("the measure made of sub-KPIs is shown, as a measure", h.includes("Branch revenue") &&
   h.includes("pfmderived") && h.includes("Made up of 3 sub-KPIs"));
ok("and is not given a box of its own -- it adds itself up", !boxes.includes("rev"), boxes.join(","));
ok("its sub-KPIs sit under it, marked as sub-KPIs, not as KPIs",
   (h.match(/class="pfmsub"/g) || []).length === 3 && (h.match(/pfmsubmark/g) || []).length === 3);
ok("a sub-KPI's name is printed once, not twice", !/SBI\s*<span class="mute">SBI/.test(h) &&
   !h.includes("SBI SBI"));
ok("what is due today gets a box, and only that", boxes.slice().sort().join(",") === "late,p1,p2,tat",
   boxes.join(","));
ok("a KPI not due today is still listed, and says so", h.includes("Branch quality") &&
   (h.match(/not due today/g) || []).length === 2);
ok("something due that the scorecard did not draw still gets its box", boxes.includes("late"));
ok("one Submit for the day", (h.match(/id="pfsubmitday"/g) || []).length === 1);
const notes = (h.match(/data-pfnote="([^"]+)"/g) || []).map((x) => x.split('"')[1]);
ok("every number has a details box beside it, and nothing else does",
   notes.slice().sort().join(",") === boxes.slice().sort().join(","), notes.join(","));
ok("and the details go with the number when the day is submitted",
   /data-pfnote="' \+ id \+ '"/.test(src) && /note: \(function\(id\)/.test(src));

PF.due = [];
h = pfDaily();
ok("with nothing due, every KPI is still there, and no Submit", h.includes("Branch revenue") &&
   h.includes("Turnaround time") && !h.includes('id="pfsubmitday"') && h.includes("Nothing is due from you today"));

PF.tree = { measures: [] };
ok("with nothing set, it says the manager sets them", pfDaily().includes("Your manager sets your KPIs"));

console.log("");
if (fails.length) { fails.forEach((f) => console.log("FAIL  " + f));
  console.log(`-- the daily update: ${pass} passed, ${fails.length} failed`); process.exit(1); }
console.log(`-- the daily update: ${pass} passed, 0 failed`);
