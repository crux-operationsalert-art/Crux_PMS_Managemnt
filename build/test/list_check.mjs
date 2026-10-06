// All people -- the flat list, checked as rules rather than as a picture.
//
// A screenshot settles whether the table looks right. What it does not
// settle is whether the manager picker can offer a move that closes the
// reporting line into a ring, whether a filter chip counts the same people
// it then shows, whether searching reaches the columns somebody would
// search by, and -- the one that made this screen necessary at all --
// whether the list is drawn for the two people who manage nobody.
//
// That last one is a real defect that was sitting in the file: tmRender
// returned EARLY with "Nobody reports to you, so there is no team to draw"
// whenever no row had depth 0. The administrator and Human Resources are
// exactly the two people with no reports, and exactly the two allowed to
// see this list, so a guard written for the manager case would have hidden
// it from everybody entitled to it.
//
// The code under test is read out of build/app/screen-team.js at run time
// rather than copied, so this cannot pass against a stale copy.
//
//   /opt/node22/bin/node build/test/list_check.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "app", "screen-team.js"), "utf8");

let pass = 0;
const fails = [];
function ok(name, cond, saw) {
  if (cond) { pass++; console.log("PASS  " + name); }
  else { fails.push(name + (saw === undefined ? "" : "  -- saw: " + saw)); }
}

const esc = (s) => String(s ?? "")
  .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  .replace(/"/g, "&quot;");

// A page just real enough for the render to run against: one #view whose
// innerHTML is kept, and nothing else matching anything.
const drawn = { view: "" };
const fakeEl = (id) => {
  if (id !== "view") return null;
  return {
    set innerHTML(v) { drawn.view = v; },
    get innerHTML() { return drawn.view; },
    querySelectorAll: () => [],
  };
};

const harness = `
${src}
return { TM, TM_GAPS, tmGapTest, tmBelow, tmRows, tmTable, tmRepForm,
         tmListRow, tmRender, tmTabs, tmMayList, tmRoot, tmKids };
`;
const mod = new Function("el", "esc", "msg", "perfApi", "pfUnit", "pfNum",
                         "pfMeter", "route", "api", "crux", harness)(
  fakeEl, esc, (k, t) => String(t ?? ""), async () => ({}),
  (u) => String(u), (n) => String(n), () => "", () => {}, null, null);

const { TM, TM_GAPS, tmGapTest, tmBelow, tmRows, tmRepForm, tmRender,
        tmTabs, tmMayList } = mod;

// A small company with every gap in it once.
//   Anita  -> Bharat -> Chetan -> Deepa
//   Anita  -> Esha
//   Farhan reports to nobody and has nobody            (the invisible one)
//   Gita holds no chair, has no designation, no place  (the unfinished one)
const PEOPLE = [
  { personId:"a", name:"Anita Rao",  employeeNo:"EMP-1", workEmail:"anita@x.invalid",
    designation:"Managing Director", chair:"MD", location:"Pune",
    locationFrom:"chair", department:"Operations",
    managerId:null, reportsTo:null, reports:2, mayMove:false },
  { personId:"b", name:"Bharat Shah", employeeNo:"EMP-2", workEmail:"bharat@x.invalid",
    designation:"Zonal Manager", chair:"Zonal Manager", location:"Mumbai",
    locationFrom:"chair", department:"Operations",
    managerId:"a", reportsTo:"Anita Rao", reports:1, mayMove:true },
  { personId:"c", name:"Chetan Iyer", employeeNo:"EMP-3", workEmail:"chetan@x.invalid",
    designation:"Branch Manager", chair:"Branch Manager", location:"Nagpur",
    locationFrom:"coverage", department:"Operations",
    managerId:"b", reportsTo:"Bharat Shah", reports:1, mayMove:true },
  { personId:"d", name:"Deepa Nair", employeeNo:"EMP-4", workEmail:"deepa@x.invalid",
    designation:"Executive", chair:"Executive", location:"Nagpur",
    locationFrom:"chair", department:"Operations",
    managerId:"c", reportsTo:"Chetan Iyer", reports:0, mayMove:true },
  { personId:"e", name:"Esha Kulkarni", employeeNo:"EMP-5", workEmail:"esha@x.invalid",
    designation:"Executive", chair:"Executive", location:"Pune",
    locationFrom:"chair", department:null,
    managerId:"a", reportsTo:"Anita Rao", reports:0, mayMove:true },
  { personId:"f", name:"Farhan Qureshi", employeeNo:"EMP-6", workEmail:"farhan@x.invalid",
    designation:"Executive", chair:"Executive", location:"Pune",
    locationFrom:"chair", department:"Operations",
    managerId:null, reportsTo:null, reports:0, mayMove:true },
  { personId:"g", name:"Gita Menon", employeeNo:null, workEmail:null,
    designation:null, chair:null, location:null, locationFrom:null,
    department:null, managerId:"b", reportsTo:"Bharat Shah",
    reports:0, mayMove:true },
];

const SUMMARY = { people:7, noManager:2, noChair:1, noDesignation:1,
                  noDepartment:2, noLocation:1 };

function load(over) {
  TM.tbl = Object.assign({
    mayUse:true, asAdministrator:true, asHumanResources:false,
    people: PEOPLE, summary: SUMMARY,
  }, over || {});
  TM.tq = ""; TM.tonly = ""; TM.tsort = "name"; TM.tedit = null;
  TM.view = "table"; TM.says = ""; TM.shut = {}; TM.sel = null;
}
load();

// ----------------------------------------------- everybody below somebody
ok("the people below somebody are the whole subtree, not one step of it",
   JSON.stringify(Object.keys(tmBelow("a")).sort()) ===
   JSON.stringify(["b", "c", "d", "e", "g"]),
   Object.keys(tmBelow("a")).sort().join(","));
ok("a leaf has nobody below them",
   Object.keys(tmBelow("d")).length === 0);
ok("somebody outside the line is not below anybody",
   !tmBelow("a").f && Object.keys(tmBelow("f")).length === 0);

// Data can be wrong. A ring in manager_id must not hang the browser.
TM.tbl.people = [
  { personId:"x", name:"X", managerId:"y", reports:1, mayMove:true },
  { personId:"y", name:"Y", managerId:"x", reports:1, mayMove:true },
];
let rang = false;
try {
  const t = setTimeout(() => { rang = true; }, 0);
  tmBelow("x");
  clearTimeout(t);
  ok("a ring in the reporting data does not hang the page", true);
} catch (e) {
  ok("a ring in the reporting data does not hang the page", false, e.message);
}
load();

// ------------------------------------------------------- the picker
// The one refusal org_move_person makes that the screen can predict
// exactly. Offering it and having it refused is the defect migration 242
// was written for.
const forB = tmRepForm(PEOPLE[1]);
ok("the picker never offers somebody themselves",
   !/value="b"/.test(forB));
ok("nor anybody below them, at any depth",
   !/value="c"/.test(forB) && !/value="d"/.test(forB) && !/value="g"/.test(forB),
   forB.match(/value="[a-z]"/g).join(" "));
ok("and does offer everybody it safely can",
   /value="a"/.test(forB) && /value="e"/.test(forB) && /value="f"/.test(forB));
ok("the manager they already have is the one selected",
   /value="a" selected/.test(forB));
ok("nobody-at-all is an option, and it is the empty one",
   /<option value="">/.test(forB) && /top of the company/.test(forB));

const forA = tmRepForm(PEOPLE[0]);
ok("somebody at the top is offered nobody from their own line",
   !/value="b"/.test(forA) && !/value="e"/.test(forA),
   (forA.match(/value="[a-z]"/g) || []).join(" "));
ok("but is still offered the people outside it",
   /value="f"/.test(forA));

// --------------------------------------------------------- the chips
for (const g of TM_GAPS) {
  if (!g.key) continue;
  load();
  TM.tonly = g.key;
  const n = tmRows().length;
  ok(`the "${g.label}" chip shows the ${SUMMARY[g.key]} people it counted`,
     n === SUMMARY[g.key], String(n));
}
load();
ok("everybody is the whole list, not a filter",
   tmGapTest("") === null && tmRows().length === PEOPLE.length);

// -------------------------------------------------------- the search
load(); TM.tq = "nagpur";
ok("searching reaches the location column",
   tmRows().length === 2);
load(); TM.tq = "EMP-6";
ok("and the employee number",
   tmRows().length === 1 && tmRows()[0].personId === "f");
load(); TM.tq = "bharat shah";
ok("and who somebody reports to, not only their own name",
   tmRows().map((p) => p.personId).sort().join(",") === "b,c,g",
   tmRows().map((p) => p.personId).join(","));
load(); TM.tq = "ANITA";
ok("and does not care about case",
   tmRows().map((p) => p.personId).sort().join(",") === "a,b,e",
   tmRows().map((p) => p.personId).join(","));
load(); TM.tq = "nobody called this";
ok("and finds nothing when there is nothing",
   tmRows().length === 0);

// Neither half gives this answer on its own: "Executive" is three people
// and "no manager" is two, and only one person is both.
load(); TM.tq = "executive"; TM.tonly = "noManager";
ok("the search and the chip narrow together, not instead of each other",
   tmRows().length === 1 && tmRows()[0].personId === "f",
   tmRows().map((p) => p.personId).join(","));

// --------------------------------------------------------- the sort
load(); TM.tsort = "designation";
let order = tmRows().map((p) => p.personId);
ok("a missing value sorts last however the column is read",
   order[order.length - 1] === "g", order.join(","));
load(); TM.tsort = "reports";
ok("sorting by reports puts the biggest team first",
   tmRows()[0].personId === "a", tmRows().map((p) => p.reports).join(","));
load(); TM.tsort = "name";
ok("and the default is alphabetical",
   tmRows()[0].personId === "a" && tmRows()[6].personId === "g",
   tmRows().map((p) => p.name).join(" | "));

// ------------------------------------------- the list reaches the two
// people who manage nobody
load();
TM.tree = { people: [] };            // nobody reports to the administrator
drawn.view = "";
tmRender();
ok("somebody who manages nobody is still shown the list",
   /All people/.test(drawn.view) && /Anita Rao/.test(drawn.view),
   drawn.view.slice(0, 120));

TM.view = "chart";
drawn.view = "";
tmRender();
ok("and on the chart they are told where the list is rather than left empty",
   /Nobody reports to you/.test(drawn.view) && /All people/.test(drawn.view));

// A manager who is neither does not get the tab at all: a tab strip with
// one tab on it is furniture.
TM.tbl = { mayUse:false, reason:"Your own team is the chart above." };
ok("a manager is not offered a list they may not read",
   !tmMayList() && tmTabs() === "");
TM.view = "table";
TM.tree = { people: [{ personId:"b", name:"Bharat Shah", depth:0, reports:1,
                       chair:"Zonal Manager", progress:null, measures:0,
                       filed:0, mayMove:false, maySet:true, rel:"self" }] };
drawn.view = "";
tmRender();
ok("and asking for it draws their chart instead of an empty table",
   !/All people/.test(drawn.view) && /Bharat Shah/.test(drawn.view));

// A refusal is never silently an empty company.
TM.tbl = { mayUse:false };
ok("a refusal without a list is not mistaken for a list with nobody in it",
   !tmMayList());

// ------------------------------------------------- said, not only coloured
ok("a gap is written in words, never left as an empty cell",
   /class="tmgap">not set/.test(src) && /class="tmgap">nobody/.test(src));
ok("a coverage area is labelled as one rather than passed off as a posting",
   /from what they cover/.test(src));
ok("the chart and the list read the same move",
   (src.match(/perfApi\("\/perf\/team\/move"/g) || []).length === 1,
   String((src.match(/perfApi\("\/perf\/team\/move"/g) || []).length));

console.log("");
if (fails.length) {
  fails.forEach((f) => console.log("FAIL  " + f));
  console.log(`-- all people: ${pass} passed, ${fails.length} failed`);
  process.exit(1);
}
console.log(`-- all people: ${pass} passed, 0 failed`);
