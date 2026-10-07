/* Can somebody actually GET to it?
 * ============================================================================
 *
 * Three times in one week a change passed the build, passed every test, was
 * committed, was published -- and reached no screen:
 *
 *   1. The quarterly rebuild went into build/app/screen-plb.js, of which only
 *      the blocks between two markers are ever injected. The rest of that file
 *      is dead. The fix was written in the dead part.
 *
 *   2. Patch 18's sentinel was `function vPerf(`, a string app_page already
 *      carried. The build answered "already in app_page; skipped" on every run
 *      for as long as the patch existed.
 *
 *   3. The monthly-shaped quarterly card WAS built, and was only reachable from
 *      a sub-tab called "Running the scheme". The owner opened Performance &
 *      appraisal, as they had been told to, and saw the old table. They said
 *      "basically nothing I had asked is done", and they were right.
 *
 * Every one of those is the same failure, and no test could catch any of them,
 * because a test proves a FUNCTION is correct and says nothing about whether a
 * person can get to it. A unit test on pfQuarterCard would have passed in all
 * three cases.
 *
 * So this is not a test of behaviour. It is a test of REACHABILITY, run over
 * the published index.html -- the actual artefact a person loads -- and it
 * asks the only question those three failures had in common:
 *
 *     starting from the screen the owner is told to open,
 *     is there a path of calls that reaches this?
 *
 * Each entry in FEATURES names the screen, because "it is in the file" and
 * "it is on the page you are looking at" are different claims and only the
 * second one is worth anything.
 */
import { readFileSync } from "node:fs";

const page = readFileSync(new URL("../../index.html", import.meta.url), "utf8");

/* ---------------------------------------------------------------- the map
 * Every function defined at column 0, and the text of its body -- taken as
 * everything up to the next column-0 definition. That is approximate, and it
 * is approximate in the safe direction: a body that runs on too far can only
 * ever make something look MORE reachable than it is, and the suite is here
 * to catch the opposite. Where it matters, the assertions below name the
 * endpoint as well, which no amount of over-reach invents.
 */
const DEF = /^(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\(/gm;
const defs = [];
for (let m; (m = DEF.exec(page)); ) defs.push({ name: m[1], at: m.index });
defs.sort((a, b) => a.at - b.at);

const body = new Map();
defs.forEach((d, i) => {
  const end = i + 1 < defs.length ? defs[i + 1].at : page.length;
  /* A name defined twice is itself a defect worth knowing about, so the
     bodies are joined rather than one silently winning. */
  body.set(d.name, (body.get(d.name) || "") + page.slice(d.at, end));
});

const names = [...body.keys()];
const calls = new Map();
for (const n of names) {
  const src = body.get(n);
  const out = new Set();
  for (const other of names) {
    if (other === n) continue;
    /* Called, referenced as a handler, or put in a table -- all three are
       ways of getting there, so a plain word-boundary match is right. */
    if (new RegExp("\\b" + other.replace(/\$/g, "\\$") + "\\b").test(src)) out.add(other);
  }
  calls.set(n, out);
}

function reach(from) {
  const seen = new Set([from]);
  const q = [from];
  while (q.length) for (const n of calls.get(q.pop()) || []) {
    if (!seen.has(n)) { seen.add(n); q.push(n); }
  }
  return seen;
}

const textOf = (set) => [...set].map((n) => body.get(n) || "").join("\n");

/* ------------------------------------------------------------- the claims
 *
 * `from`  the screen a person opens. Not "somewhere in the bundle".
 * `needs` the endpoints that must be reachable from it, because a renderer
 *         that is reachable but asks nothing is a renderer drawing a blank.
 * `why`   the sentence this is here to keep true. Written as the owner said
 *         it, so that a failure reads as a broken promise and not as a
 *         broken assertion.
 */
const FEATURES = [
  { fn: "pfQuarterCard", from: "vPerf",
    needs: ["/plb/kpi/months"],
    why: '"FOrmat/UI/UX of monthly score card is good ... use the same for '
       + '[the quarterly] too" -- on the page called Performance & appraisal, '
       + 'which is the page they open. It was built on another screen once '
       + 'and that is exactly the failure this file exists for.' },

  { fn: "pfQMeasure", from: "vPerf", needs: [],
    why: "the quarter drawn per measure, three months each" },

  { fn: "pfQParts", from: "vPerf",
    needs: ["/plb/kpi/parts"],
    why: '"add sub KPIs in both monthly and the quaterly" -- reachable from '
       + 'the measure a person is reading, not two tabs away. The live '
       + 'database had nought sub-KPIs on it while this was unreachable.' },

  { fn: "pfQEditor", from: "vPerf",
    needs: ["/plb/sheet/measures"],
    why: '"still not able to edit/update KPIs of quaterly scorecard"' },

  { fn: "pfQWire", from: "vPerf", needs: [],
    why: "a panel whose handlers were never wired is a panel of dead buttons" },

  { fn: "pfEditForm", from: "vPerf",
    needs: ["/plb/perf/edit"],
    why: '"not able to edit/update KPIs before assiging targets"' },

  { fn: "tmPartnerForm", from: "vTeamScreen",
    needs: ["/perf/partner"],
    why: "the file HR holds on a Business Associate" },

  { fn: "tmEscal", from: "vTeamScreen",
    needs: ["/perf/escalate"],
    why: '"Raise an escalation about a person, not only a case"' },

  { fn: "tmEditForm", from: "vTeamScreen",
    needs: ["/perf/team/set"],
    why: "editing designation, chair, location and department in All people" },
];

const fail = [];

for (const f of FEATURES) {
  if (!body.has(f.from)) {
    fail.push(`${f.from} is not a function on the published page at all, so `
            + `nothing can be reachable from it.`);
    continue;
  }
  if (!body.has(f.fn)) {
    fail.push(`${f.fn} is not on the published page. ${f.why}`);
    continue;
  }
  const seen = reach(f.from);
  if (!seen.has(f.fn)) {
    fail.push(`${f.fn} is on the page but NOTHING on ${f.from} reaches it. `
            + `It is published and unreachable, which is the same as absent `
            + `to the person looking at ${f.from}. ${f.why}`);
    continue;
  }
  const src = textOf(seen);
  for (const ep of f.needs) {
    if (!src.includes(ep)) {
      fail.push(`${f.fn} is reachable from ${f.from} but ${ep} is never asked `
              + `for anywhere on that path, so it can only draw a blank. ${f.why}`);
    }
  }
}

/* ------------------------------------------------- the routes themselves
 * Patch 18 rewired #pms to the rebuilt screen and was skipped on every build
 * for as long as it existed. The assertion is on the published page, which is
 * the only place the answer is not a matter of opinion.
 */
if (/\bpms\s*:\s*vPms\b/.test(page)) {
  fail.push("#pms still opens vPms, the screen the Performance rebuild "
          + "replaced. Patch 18 did not take.");
}

/* A screen named in the router that does not exist is a tab that throws when
   somebody clicks it. */
const runMap = page.match(/var run = \{([\s\S]{0,1200}?)\}\[t\];/);
if (!runMap) {
  fail.push("The router's screen table could not be found on the published "
          + "page, so no route could be checked at all.");
} else {
  for (const m of runMap[1].matchAll(/(\w+)\s*:\s*(v\w+)/g)) {
    if (!body.has(m[2])) {
      fail.push(`The route #${m[1]} opens ${m[2]}, which is not defined on `
              + `the published page.`);
    }
  }
}

if (fail.length) {
  console.error("reach_check: " + fail.length + " feature(s) cannot be reached\n");
  fail.forEach((f, i) => console.error("  " + (i + 1) + ". " + f + "\n"));
  process.exit(1);
}
console.log("reach_check ok -- " + FEATURES.length
          + " features reachable from the screen they belong on");
