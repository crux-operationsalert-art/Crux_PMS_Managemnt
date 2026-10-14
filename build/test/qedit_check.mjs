// The quarter, edited in the mapping panel's Quarterly tab.
//
// "Quarterly: the same journey and UI as Monthly, M1 | M2 | M3 instead of
// one target." Until 14 Oct the tab only SHOWED the months, and the quarter
// was changed from a second card on the person's OWN quarter -- which nobody
// may edit. This loads build/app/screen-perf.js itself and asserts what the
// tab offers, and exactly what it would send.
//
//   /opt/node22/bin/node build/test/qedit_check.mjs

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
const mod = new Function("el", "esc", "msg", "day", "plb", "perfApi", "api", "money",
  "when", "route", "pbOkr", "pbWire", "scope", `
${src}
return { PF, pfMapQuarterly, pfMapQBody, pfMapQDraft, setMe: function(x){ me = x; } };`)(
  () => null, esc, (k, t) => (t ? '<div class="msg ' + k + '">' + t + "</div>" : ""),
  (d) => String(d ?? ""), async () => ({}), async () => ({}), async () => ({}),
  (n) => "₹" + n, (s) => String(s), () => {}, () => "", () => {}, null);
const { PF, pfMapQuarterly, pfMapQBody, setMe } = mod;
setMe({ app_role: "MANAGER", department: "Operations" });

// One finished month and two to come, a count and a level.
const months = (a, b, c) => [
  { month: "2020-01-01", share: 0, implied: a, target: a, filed: 9 },
  { month: "2031-02-01", share: 0, implied: b, target: b, filed: null },
  { month: "2031-03-01", share: 0, implied: c, target: c, filed: null }];
const Q = { sheetId: "s1", maySet: true, measures: [
  { goalKpiId: "g1", kpiId: "k1", name: "Cases", unit: "COUNT", kind: "SUM",
    weight: 60, quarterly: 30, direction: "LOWER", suggests: "HIGHER",
    months: months(10, 10, 10), parts: [] },
  { goalKpiId: "g2", kpiId: "k2", name: "Accuracy", unit: "%", kind: "LEVEL",
    weight: 40, quarterly: 95, direction: null, suggests: "HIGHER",
    months: months(95, 95, 95), parts: [] }] };
function open(maySet) {
  PF.map = { tab: "quarterly", data: { sheetId: "s1", maySet: true }, q: Q,
             qopts: { maySet, why: maySet ? null : "That sheet is locked.",
                      measures: [{ kpiId: "k3", name: "Spare", kind: "SUM" }] },
             qd: null, hist: null, histOpen: false, qsub: null, qsays: "" };
  return pfMapQuarterly();
}

let h = open(true);
ok("a count's months still to come are typed, M2 and M3",
   h.includes('data-pfmqm="0:1"') && h.includes('data-pfmqm="0:2"'));
ok("a finished month is not typed into, and shows what was achieved",
   !h.includes('data-pfmqm="0:0"') && h.includes("pfmpast"));
ok("a level is one box, every month held to it",
   h.includes('data-pfmqtg="1"') && !h.includes('data-pfmqm="1:'));
ok("weights, Remove, a measure to add and Save are all there",
   h.includes('data-pfmqw="0"') && h.includes("data-pfmqdrop") &&
   h.includes('id="pfmqadd"') && h.includes('id="pfmqsave"'));

let b = pfMapQBody();
ok("untouched, the split is not sent and the stored one stands",
   !("m1" in b[0]) && b[0].target === 30, JSON.stringify(b[0]));
ok("the manager's direction is sent back, not wiped",
   b[0].direction === "LOWER" && b[1].direction === "", JSON.stringify(b));

PF.map.qd[0].m = [10, 20, 30]; PF.map.qd[0].touched = true;
b = pfMapQBody();
ok("typed months become the quarter -- the three added up",
   b[0].target === 60, JSON.stringify(b[0]));
ok("and the shares, which come to exactly a hundred",
   b[0].m1 === 16.67 && b[0].m2 === 33.33 && b[0].m3 === 50 &&
   Math.round((b[0].m1 + b[0].m2 + b[0].m3) * 100) === 10000, JSON.stringify(b[0]));
PF.map.qd[0].m = [1, 1, 1];
b = pfMapQBody();
ok("a third each still adds to a hundred, not 99.99",
   Math.round((b[0].m1 + b[0].m2 + b[0].m3) * 100) === 10000, JSON.stringify(b[0]));
PF.map.qd[0].m = [0, 0, 0];
b = pfMapQBody();
ok("a count asked to be nought is a target of nought, with no split",
   b[0].target === 0 && !("m1" in b[0]), JSON.stringify(b[0]));
PF.map.qd[1].target = "97";
ok("a level sends the level typed", pfMapQBody()[1].target === "97");

h = open(false);
ok("when the server says no, nothing is typed into",
   !h.includes("data-pfmqw") && !h.includes("data-pfmqm") && !h.includes('id="pfmqsave"'));
ok("and it says why", h.includes("That sheet is locked."));

ok("there is one door onto a quarter: the old editor is gone",
   !/function pfQEditor\(/.test(src) && !/id="pfqedit"/.test(src));

console.log("");
if (fails.length) { fails.forEach((f) => console.log("FAIL  " + f));
  console.log(`-- the quarter: ${pass} passed, ${fails.length} failed`); process.exit(1); }
console.log(`-- the quarter: ${pass} passed, 0 failed`);
