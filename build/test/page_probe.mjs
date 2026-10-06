// Press every control on the PUBLISHED page, in a real browser.
//
// This is the instrument that settled the owner's P1 -- "set KPI is still
// not working and just like that most of the Buttons in PMS are not
// working". Reading pfWire would have said the buttons were fine, and they
// were: every one wired, every one clickable, no JavaScript error. The
// writes were being refused by the database, and the clock was why.
//
// It is NOT in build/test/run.sh, because it needs Chromium and a copy of
// the published page, and the suite has to run anywhere. It is here because
// "measure the real page" is part of the method, and a method that lives
// only in a document is a method nobody runs.
//
//   npm i playwright
//   git show origin/main:index.html > /tmp/published.html
//   node build/test/page_probe.mjs /tmp/published.html            # window open
//   SHUT=1 node build/test/page_probe.mjs /tmp/published.html     # window shut
//   AS_HR=1 SHUT=1 node build/test/page_probe.mjs /tmp/published.html
//
// Every call to *.supabase.co is answered from the table below, so nothing
// touches the live services and nothing has to be signed in to.

import { chromium } from "playwright";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";

const PAGE = process.argv[2];
if (!PAGE) {
  console.error("usage: node build/test/page_probe.mjs <published index.html>");
  process.exit(2);
}
const html = readFileSync(PAGE, "utf8");
const SHUT = !!process.env.SHUT;
const AS_HR = !!process.env.AS_HR;

const ME = {
  id: "11111111-1111-1111-1111-111111111111",
  full_name: "Probe Manager", work_email: "probe@cruxindia.co.in",
  app_role: "MANAGER",
  department: AS_HR ? "Human Resources" : "Operations",
  chair_title: "Zonal Manager", employee_no: "EMP-0001",
  scope_level: AS_HR ? "hr" : "manager",
  screens: ["today","perf","plb","people","cases","ogl","clients","matrix",
            "mis","reports","config","hr","joining","access","hiring",
            "profile","places","coverage","history","kpis","desk"],
};

const CYCLE = {
  id: "22222222-2222-2222-2222-222222222222",
  period_start: "2026-10-01", period_kind: "MONTH",
  assign_opens: "2026-10-01",
  assign_closes: SHUT ? "2026-09-07" : "2026-10-08",
  entry_closes: "2026-11-06",
  assign_open: !SHUT, entry_open: true, state: "OPEN",
};

const M = {
  assignmentId: "33333333-3333-3333-3333-333333333331",
  kpiId: "44444444-4444-4444-4444-444444444441",
  name: "Cases completed", unit: "COUNT", cadence: "DAILY",
  target: 100, value: 42, pct: 42, direction: "UP",
  rollsInto: null, split: null, parts: [], team: [],
  maySet: true, mine: true, kind: "SUM",
};

const TEAM = [
  { personId: "55555555-5555-5555-5555-555555555551", name: "A Report",
    employeeNo: "EMP-0002", department: "Operations", depth: 1,
    maySet: true, chair: "Branch Manager" },
  { personId: "55555555-5555-5555-5555-555555555552", name: "B Report",
    employeeNo: "EMP-0003", department: "Operations", depth: 1,
    maySet: true, chair: "Branch Manager" },
  { personId: "55555555-5555-5555-5555-555555555553", name: "C Watched",
    employeeNo: "EMP-0043", department: "Operations", depth: 2,
    maySet: false, chair: "Executive" },
];

const ROUTES = [
  [/\/crux\/api\/config/,          { googleClientId: "" }],
  [/\/crux\/api\/me/,              ME],
  [/\/plb\/plb\/perf\/cycle/,      { period: "2026-10-01", kind: "MONTH",
                                     cycle: CYCLE, mayOpen: true, note: null }],
  [/\/plb\/plb\/perf\/team/,       { people: TEAM }],
  [/\/plb\/plb\/perf\/tree/,       { cycle: CYCLE, person: { id: ME.id, name: ME.full_name },
                                     rel: "self", maySet: false, says: null, measures: [M] }],
  [/\/plb\/plb\/perf\/due/,        { due: [M], on: null }],
  [/\/plb\/plb\/perf\/score/,      { achievement: 71.5, counted: 3, skipped: 0,
                                     says: null, measures: [M] }],
  [/\/plb\/plb\/mine/,             { quarter: "2026-10-01", sheet: null,
                                     chair: "Zonal Manager", inScheme: true, maySetUp: false }],
  [/\/perf\/perf\/weighting/,      { mine: { kpiPercent: 75, attrPercent: 25,
                                     effectiveFrom: "2026-10-01", scope: "everybody",
                                     applies: true, note: null }, all: null, maySet: false }],
  [/\/perf\/perf\/task\/mine/,     { period: "2026-10", owed: [], set: [] }],
  [/\/perf\/perf\/filed/,          { days: [], filedDays: 9, workingDays: 14,
                                     run: 3, from: "2026-09-23", to: "2026-10-06" }],
  [/\/perf\/perf\/org/,            { person: { id: ME.id, name: ME.full_name },
                                     rel: "self", teamSize: 2, measures: [M] }],
  [/\/perf\/perf\/handover/,       { rel: "self", from: [], summary: {}, note: null }],
  [/\/perf\/perf\/month/,          { month: "2026-10", suggested: 8, outOf: 10,
                                     rows: [], note: null }],
  [/\/perf\/perf\/measures/,       { catalogue: [{ id: M.kpiId, name: M.name, unit: "COUNT",
                                       cadence: "DAILY", accrual: "SUM", mandatory: false,
                                       kind: "SUM" }],
                                     mine: [{ assignmentId: M.assignmentId, name: M.name,
                                       unit: "COUNT", split: null }],
                                     chairId: null, note: null }],
];

const unstubbed = new Set();
const server = createServer((_req, res) => {
  res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
  res.end(html);
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const origin = "http://127.0.0.1:" + server.address().port;

const browser = await chromium.launch(
  process.env.CHROME ? { executablePath: process.env.CHROME } : {});
const page = await browser.newPage();

const errors = [];
page.on("pageerror", (e) => errors.push("UNCAUGHT  " + e.message));
page.on("console", (m) => { if (m.type() === "error") errors.push("CONSOLE   " + m.text()); });

await page.route("**://*.supabase.co/**", (route) => {
  const url = route.request().url();
  for (const [re, body] of ROUTES) {
    if (re.test(url)) {
      return route.fulfill({ status: 200, contentType: "application/json",
                             body: JSON.stringify(body) });
    }
  }
  unstubbed.add(url.replace(/^https:\/\/[^/]+\/functions\/v1/, "").split("?")[0]);
  return route.fulfill({ status: 200, contentType: "application/json", body: "{}" });
});
await page.route("**://accounts.google.com/**", (r) =>
  r.fulfill({ status: 200, contentType: "application/javascript", body: "" }));
await page.addInitScript(() => {
  try { localStorage.setItem("cruxToken", "probe"); } catch (e) {}
});

await page.goto(origin + "/#perf", { waitUntil: "load" });
await page.waitForTimeout(4000);

async function look(label) {
  const o = await page.evaluate(() => {
    const v = document.getElementById("view");
    const ctl = [];
    for (const b of v.querySelectorAll("button")) {
      ctl.push({ key: b.id || [...b.attributes].filter((a) => a.name.startsWith("data-"))
                   .map((a) => a.name).join(",") || "(none)",
                 text: (b.textContent || "").trim().replace(/\s+/g, " ").slice(0, 32),
                 wired: !!b.onclick, disabled: b.disabled });
    }
    return { bytes: v.innerHTML.length, ctl,
             shut: [...v.querySelectorAll(".pfshut")]
               .map((p) => p.textContent.trim().replace(/\s+/g, " ").slice(0, 120)) };
  });
  const dead = o.ctl.filter((c) => !c.wired && !c.disabled);
  console.log(`\n== ${label}  (${o.bytes} bytes, ${o.ctl.length} buttons, ${dead.length} unwired)`);
  for (const c of o.ctl) {
    console.log("   " + (c.wired ? "wired   " : c.disabled ? "disabled" : "UNWIRED ") +
                " " + c.key.padEnd(22) + " “" + c.text + "”");
  }
  for (const s of o.shut) console.log("   explained: " + s);
  return dead.length;
}

let dead = await look(
  `${AS_HR ? "HR" : "a manager"}, the window ${SHUT ? "SHUT" : "open"}`);

if (await page.locator("[data-pfwho]").count()) {
  await page.locator("[data-pfwho]").first().click();
  await page.waitForTimeout(800);
  dead += await look("with a team member open");
}

if (unstubbed.size) {
  console.log("\nnot stubbed (answered {}): " + [...unstubbed].join(", "));
}
console.log("\nerrors: " + (errors.length ? "" : "none"));
for (const e of errors) console.log("  " + e);

await browser.close();
server.close();
if (errors.length || dead) process.exit(1);
