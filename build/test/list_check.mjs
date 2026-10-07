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
return { TM, TM_GAPS, TM_BULK, tmGapTest, tmBelow, tmRows, tmTable,
         tmRepOpts, tmEditForm, tmSeatOpts, tmBulkBar,
         tmListRow, tmRender, tmTabs, tmMayList, tmRoot, tmKids };
`;
const mod = new Function("el", "esc", "msg", "perfApi", "pfUnit", "pfNum",
                         "pfMeter", "route", "api", "crux", harness)(
  fakeEl, esc, (k, t) => String(t ?? ""), async () => ({}),
  (u) => String(u), (n) => String(n), () => "", () => {}, null, null);

const { TM, TM_GAPS, TM_BULK, tmGapTest, tmBelow, tmRows, tmRepOpts,
        tmEditForm, tmSeatOpts, tmBulkBar, tmListRow, tmRender,
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
    managerId:null, reportsTo:null, reports:2, mayMove:false, mayEdit:true },
  { personId:"b", name:"Bharat Shah", employeeNo:"EMP-2", workEmail:"bharat@x.invalid",
    designation:"Zonal Manager", chair:"Zonal Manager", location:"Mumbai",
    locationFrom:"chair", department:"Operations",
    managerId:"a", reportsTo:"Anita Rao", reports:1, mayMove:true, mayEdit:true },
  { personId:"c", name:"Chetan Iyer", employeeNo:"EMP-3", workEmail:"chetan@x.invalid",
    designation:"Branch Manager", chair:"Branch Manager", location:"Nagpur",
    locationFrom:"coverage", department:"Operations",
    managerId:"b", reportsTo:"Bharat Shah", reports:1, mayMove:true, mayEdit:true },
  { personId:"d", name:"Deepa Nair", employeeNo:"EMP-4", workEmail:"deepa@x.invalid",
    designation:"Executive", chair:"Executive", location:"Nagpur",
    locationFrom:"chair", department:"Operations",
    managerId:"c", reportsTo:"Chetan Iyer", reports:0, mayMove:true, mayEdit:true },
  { personId:"e", name:"Esha Kulkarni", employeeNo:"EMP-5", workEmail:"esha@x.invalid",
    designation:"Executive", chair:"Executive", location:"Pune",
    locationFrom:"chair", department:null,
    managerId:"a", reportsTo:"Anita Rao", reports:0, mayMove:true, mayEdit:true },
  { personId:"f", name:"Farhan Qureshi", employeeNo:"EMP-6", workEmail:"farhan@x.invalid",
    designation:"Executive", chair:"Executive", location:"Pune",
    locationFrom:"chair", department:"Operations",
    managerId:null, reportsTo:null, reports:0, mayMove:true, mayEdit:true },
  { personId:"g", name:"Gita Menon", employeeNo:null, workEmail:null,
    designation:null, chair:null, location:null, locationFrom:null,
    department:null, managerId:"b", reportsTo:"Bharat Shah",
    reports:0, mayMove:true, mayEdit:true },
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
  TM.tpick = {}; TM.tsays = ""; TM.tfail = null;
  /* What org_assign_options hands back. Two chairs, and a place on each,
     so "a place belongs to a chair" can be checked rather than assumed. */
  TM.opts = {
    mayUse: true, maySetRole: true,
    designations: [{ id:"d1", title:"Branch Manager", seniority:30 },
                   { id:"d2", title:"Executive", seniority:60 }],
    departments: ["Operations", "Human Resources"],
    chairs: [{ id:"c1", code:"BM", title:"Branch Manager", level:"BRANCH" },
             { id:"c2", code:"ZM", title:"Zonal Manager", level:"ZONE" }],
    seatings: [{ id:"s1", chairId:"c1", label:"Mumbai" },
               { id:"s2", chairId:"c1", label:"Pune" },
               { id:"s3", chairId:"c2", label:"West" }],
    employeeTypes: ["EMPLOYEE","PARTNER","INTERN","CONTRACT"],
    appRoles: ["VIEWER","MANAGER","ADMIN"],
  };
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
  { personId:"x", name:"X", managerId:"y", reports:1, mayMove:true, mayEdit:true },
  { personId:"y", name:"Y", managerId:"x", reports:1, mayMove:true, mayEdit:true },
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
const forB = tmRepOpts(PEOPLE[1]);
ok("the picker never offers somebody themselves",
   !/value="b"/.test(forB));
ok("nor anybody below them, at any depth",
   !/value="c"/.test(forB) && !/value="d"/.test(forB) && !/value="g"/.test(forB),
   forB.match(/value="[a-z]"/g).join(" "));
ok("and does offer everybody it safely can",
   /value="a"/.test(forB) && /value="e"/.test(forB) && /value="f"/.test(forB));
ok("the manager they already have is the one selected",
   /value="a" selected/.test(forB));
const editB = tmEditForm(PEOPLE[1]);
ok("nobody-at-all is an option, and it is the empty one",
   /<option value="">/.test(editB) && /top of the company/.test(editB));

const forA = tmRepOpts(PEOPLE[0]);
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

// ===================================================================
// The editor (migration 248). 244 built the list that finds the gaps and
// did not write one; this is the half that closes them, and the owner's
// sentence is the specification: "I am able to update and change the
// managers, but nothing else designation, chair, location, department
// and other important aspects."
// ===================================================================
load();
const ed = tmEditForm(PEOPLE[6]);          // Gita: no chair, no designation
for (const [what, id] of [["designation","tmedesig"], ["department","tmedept"],
                          ["chair","tmechair"], ["location","tmeseat"],
                          ["employee type","tmetype"], ["employee number","tmeno"],
                          ["work e-mail","tmemail"], ["mobile","tmemob"],
                          ["joining date","tmejoin"]]) {
  ok(`the row opens onto a box for ${what}`, ed.includes(`id="${id}"`));
}
ok("and the reporting line is one control inside it, not the whole of it",
   /id="tmrepsel"/.test(ed) && /data-tmsave="g"/.test(ed));

// The one field HR may not set. A box that is always refused is worse than
// no box -- that is migration 242, said about a form instead of a chart.
ok("the role box is drawn only where the row says it may be",
   !/id="tmerole"/.test(ed));
const edRole = tmEditForm(Object.assign({}, PEOPLE[6], { maySetRole:true }));
ok("and is drawn where it says it may",
   /id="tmerole"/.test(edRole));

// A place belongs to a chair. Offering Pune under a chair that has no Pune
// seat is an offer org_person_set refuses.
ok("the places offered are the ones on the chair that is picked",
   /value="s1"/.test(tmSeatOpts("c1")) && /value="s2"/.test(tmSeatOpts("c1")) &&
   !/value="s3"/.test(tmSeatOpts("c1")));
ok("a chair with no places says so rather than offering none in silence",
   /no places on it/.test(tmSeatOpts("c9")));
ok("and no chair at all offers no place",
   !/value="s/.test(tmSeatOpts("")));

// What the person already has is what the form opens on. A form that
// opens blank reads as "this is empty" and saves away whatever was there.
const edB = tmEditForm(Object.assign({}, PEOPLE[1],
  { designationId:"d1", chairId:"c1", seatingId:"s2", department:"Operations" }));
ok("the form opens on what the person already has",
   /value="d1" selected/.test(edB) && /value="c1" selected/.test(edB) &&
   /value="s2" selected/.test(edB) && /value="Operations"/.test(edB));

// ------------------------------------------------------- the bulk bar
load();
ok("there is no bulk bar until a gap is being worked through",
   tmBulkBar(tmRows()) === "");
load(); TM.tonly = "noDesignation";
let bar = tmBulkBar(tmRows());
ok("a gap chip brings up the one field that gap is about",
   /id="tmbval"/.test(bar) && /value="d1"/.test(bar) && /Designation/.test(bar));
ok("and nothing can be set until somebody is ticked",
   /id="tmbgo"[^>]*disabled/.test(bar), bar.match(/id="tmbgo"[^>]*>/)[0]);
TM.tpick = { g:true };
bar = tmBulkBar(tmRows());
ok("ticking somebody arms it, and it says how many",
   !/id="tmbgo"[^>]*disabled/.test(bar) && /Set for 1/.test(bar));
load(); TM.tonly = "noDepartment";
ok("a department can be picked from the ones in use or typed new",
   /list="tmdepts2"/.test(tmBulkBar(tmRows())));
load(); TM.tonly = "noLocation";
ok("a place is refused in bulk, because a place belongs to a chair",
   /one person at a time/.test(tmBulkBar(tmRows())) &&
   !/id="tmbval"/.test(tmBulkBar(tmRows())));

// The tick column appears with the chip and not before it: "the same change
// to all of these" is only a question once a gap is on screen.
load();
ok("there is no tick box until a gap is being worked through",
   !/data-tmpick/.test(tmListRow(PEOPLE[6])));
TM.tonly = "noChair";
ok("and one for every row once there is",
   /data-tmpick="g"/.test(tmListRow(PEOPLE[6])));

// One write, one set of rules. The screen must not have grown a second way
// to change a reporting line beside org_move_person.
ok("every change goes through org_person_set, and the line through nothing new",
   (src.match(/perfApi\("\/perf\/team\/set"/g) || []).length === 1 &&
   (src.match(/perfApi\("\/perf\/team\/set-many"/g) || []).length === 1);

console.log("");
if (fails.length) {
  fails.forEach((f) => console.log("FAIL  " + f));
  console.log(`-- all people: ${pass} passed, ${fails.length} failed`);
  process.exit(1);
}
console.log(`-- all people: ${pass} passed, 0 failed`);
