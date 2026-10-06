// Signing in as somebody forgets the last person's screens.
//
// "when Admin uses 'Look at Crux as someone else', this should actually log
//  in the admin to that person's account and use it as that person."
//
// The session was already theirs. What was not was the screens: twelve
// module-level state objects survived the swap, and vPerf only re-reads the
// team `if (!PF.team)`, so the administrator's team stayed on screen under
// the other person's name.
//
// Two things are checked here and they are different claims:
//
//   1. forgetScreens() actually restores a changed object to what it held
//      at the first sign-in -- run, not read;
//   2. the LIST it works from covers every screen that exists. That is the
//      one that rots: somebody adds a screen next month and the list says
//      nothing. So the list is compared against every `var XX = {` in
//      build/app/.
//
//   /opt/node22/bin/node build/test/forget_check.mjs

import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const appDir = join(here, "..", "app");
const build = readFileSync(join(here, "..", "..", ".github", "build-tool.py"), "utf8");

let pass = 0;
const fails = [];
function ok(name, cond, saw) {
  if (cond) { pass++; console.log("PASS  " + name); }
  else { fails.push(name + (saw === undefined ? "" : "  -- saw: " + saw)); }
}

// ------------------------------------------------- the patch is still there
const listed = (build.match(/var SCREEN_STATE = \[([^\]]*)\]/) || [])[1];
ok("the build applies a patch that names the screens to forget",
   !!listed, String(listed));
const names = (listed || "").split(",").map((s) => s.trim().replace(/"/g, ""))
  .filter(Boolean);

ok("forgetScreens is called as the first thing start() does",
   /forgetScreens\(\);\\n'\s*\n\s*'\s*me = person/.test(build) ||
   /forgetScreens\(\);[\s\S]{0,200}me = person/.test(build));

// ------------------------------------------------- the list covers the app
const found = new Set();
for (const f of readdirSync(appDir)) {
  if (!f.endsWith(".js") || f.startsWith("_")) continue;
  const src = readFileSync(join(appDir, f), "utf8");
  for (const m of src.matchAll(/^var ([A-Z][A-Za-z0-9_]{1,4}) = \{/gm)) {
    // HELP is a written guide, not something a session fetched.
    if (m[1] === "HELP") continue;
    found.add(m[1]);
  }
}
const missing = [...found].filter((n) => !names.includes(n)).sort();
ok("every screen that keeps what it fetched is on the list",
   missing.length === 0, missing.join(", "));
ok("and the list names nothing that does not exist",
   names.filter((n) => !found.has(n)).length === 0,
   names.filter((n) => !found.has(n)).join(", "));
ok("the list is not empty and covers at least ten screens",
   names.length >= 10, String(names.length));

// ----------------------------------------------------- and it actually works
// The patch body is lifted out of build-tool.py and run, so this tests the
// code that will be published rather than a copy of it.
const body = (build.match(
  /'(\/\* Every screen that keeps what it fetched\. \*\/\\n'[\s\S]*?)'\n\s*'async function start/) || [])[1];
ok("the patch body can be read back out of the build", !!body);

if (body) {
  // Un-escape the Python string concatenation back into JavaScript.
  const js = body.split("\\n'").join("\n").replace(/^'/, "").replace(/\n\s*'/g, "\n")
    .split("\\n").join("\n");
  const win = {
    PF: { period: null, team: null, who: null, sel: {} },
    TM: { tree: null, view: "chart", shut: {} },
    PB: { q: null, data: null, tab: "mine" },
    AA: { o: null, open: false, q: "" },
    HE: {}, HRA: {}, MG: {}, MX: {}, MY: {}, PL: {}, QH: {}, TD: {},
  };
  const mod = new Function("window", js + "\nreturn { forgetScreens, SCREEN_STATE };")(win);

  // First call: the snapshot, and it changes nothing.
  mod.forgetScreens();
  ok("the first sign-in only takes the snapshot",
     win.PF.team === null && win.TM.view === "chart");

  // Somebody uses the tool.
  win.PF.team = [{ name: "the administrator's report" }];
  win.PF.who = "somebody";
  win.PF.sel = { a: true };
  win.TM.tree = { people: [1, 2, 3] };
  win.TM.view = "table";
  win.PB.data = { sheet: "the administrator's" };
  win.AA.open = true;

  // Acting as somebody else.
  mod.forgetScreens();
  ok("the team of the person who was signed in before is gone",
     win.PF.team === null, JSON.stringify(win.PF.team));
  ok("and the person they had open",
     win.PF.who === null && JSON.stringify(win.PF.sel) === "{}");
  ok("and the chart", win.TM.tree === null);
  ok("and a tab they had switched to goes back to its default",
     win.TM.view === "chart", win.TM.view);
  ok("and the goal sheet", win.PB.data === null);
  ok("and the act-as panel is shut", win.AA.open === false);

  // The objects are the SAME objects: every screen file closes over them,
  // so replacing them would leave the screens writing into an orphan.
  const before = win.PF;
  win.PF.team = [1];
  mod.forgetScreens();
  ok("the state objects are reset in place, never replaced",
     win.PF === before, "a new object was handed back");

  ok("a screen the snapshot never saw is left alone rather than broken",
     (() => {
       win.ZZ = { kept: true };
       mod.forgetScreens();
       return win.ZZ.kept === true;
     })());
}

console.log("");
if (fails.length) {
  fails.forEach((f) => console.log("FAIL  " + f));
  console.log(`-- forgetting: ${pass} passed, ${fails.length} failed`);
  process.exit(1);
}
console.log(`-- forgetting: ${pass} passed, 0 failed`);
