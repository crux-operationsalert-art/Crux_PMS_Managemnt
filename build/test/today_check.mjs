// The dashboard -- checked as arithmetic and as a rule, not as a picture.
//
// A screenshot settles the layout. What a screenshot does not settle is
// whether the doughnut's arcs add up to the circle, whether a bar can be
// drawn wider than its own track when somebody beats a target by 300%,
// whether the three states are decided once or in four places that can
// drift, and whether a number the database returned as null is printed as
// a nought. Each of those is a wrong figure that looks perfectly fine.
//
// The code under test is read out of build/app/screen-today.js at run time
// rather than copied, so this cannot pass against a stale copy.
//
//   /opt/node22/bin/node build/test/today_check.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "app", "screen-today.js"), "utf8");

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
return { tdState, tdNum, tdBar, tdDonut, tdTile, TD_WORD, TD_TOKEN };
`;
const mod = new Function("el", "esc", "msg", "money", "api", "crux", "plb",
                         "scope", "mxCardLoad", harness)(
  () => null, esc, (k, t) => t ?? "", (n) => "₹" + n,
  null, null, null, null, null);

const { tdState, tdNum, tdBar, tdDonut, TD_WORD, TD_TOKEN } = mod;

// ------------------------------------------------------- the three states
ok("100% is on target, and so is beating it",
   tdState(100) === "ok" && tdState(142) === "ok");
ok("99% is part of the way, not on target",
   tdState(99) === "part");
ok("70% is the floor of part of the way",
   tdState(70) === "part" && tdState(69.9) === "behind");
ok("no target is its own state, not behind",
   tdState(null) === "none" && tdState(undefined) === "none",
   tdState(null) + "/" + tdState(undefined));
ok("nought filed against a target is behind, not nothing",
   tdState(0) === "behind");

ok("every state has a word and a colour",
   Object.keys(TD_WORD).every((k) => TD_WORD[k] && TD_TOKEN[k]));

// --------------------------------------------------------------- numbers
ok("a null figure is an em dash, never a nought",
   tdNum(null) === "—" && tdNum(undefined) === "—" && tdNum("") === "—",
   [tdNum(null), tdNum(undefined), tdNum("")].join(" "));
ok("and so is something that is not a number",
   tdNum("not a number") === "—");
ok("a nought that was filed IS printed",
   tdNum(0) === "0");
ok("figures are grouped the Indian way",
   tdNum(1234567) === "12,34,567", tdNum(1234567));
ok("a percentage keeps one decimal when asked and none when not",
   tdNum(96.44, 1) === "96.4" && tdNum(96.44) === "96");

// ------------------------------------------------------------- the bars
const width = (html) => Number((html.match(/width:([\d.]+)%/) || [])[1]);
ok("a bar at 42% is 42% wide", width(tdBar(42, "part")) === 42);
ok("a bar never runs past its own track, however far past target somebody is",
   width(tdBar(315, "ok")) === 100, tdBar(315, "ok"));
ok("and never runs backwards",
   width(tdBar(-20, "behind")) === 0);
ok("no target draws no bar rather than a full one",
   width(tdBar(null, "none")) === 0 && width(tdBar(undefined, "none")) === 0);

// ----------------------------------------------------------- the doughnut
// The arcs must account for the whole circle: every segment's share, plus
// the gaps between them, is the circumference. If they do not, the picture
// says something different from the counts under it.
function arcs(html) {
  return [...html.matchAll(/stroke-dasharray="([\d.]+) ([\d.]+)"/g)]
    .map((m) => Number(m[1]));
}
const C = 2 * Math.PI * 42;

let d = tdDonut({ ok: 3, part: 1, behind: 1 }, 5);
let a = arcs(d);
ok("three states draw three arcs", a.length === 3, a.length);
ok("and those arcs plus their gaps are the whole circle",
   Math.abs(a.reduce((x, y) => x + y, 0) + 3 * 2 - C) < 0.05,
   a.reduce((x, y) => x + y, 0).toFixed(2) + " + gaps vs " + C.toFixed(2));
ok("the middle of the ring reads the share on target",
   d.includes("<b>60%</b>"), (d.match(/<b>[^<]*<\/b>/) || [])[0]);

d = tdDonut({ ok: 4, part: 0, behind: 0 }, 4);
a = arcs(d);
ok("a state nobody is in draws no arc", a.length === 1, a.length);
ok("and one arc alone has no gap nicked out of it",
   Math.abs(a[0] - C) < 0.05, a[0].toFixed(2) + " vs " + C.toFixed(2));
ok("all on target reads 100%", d.includes("<b>100%</b>"));

d = tdDonut({ ok: 0, part: 0, behind: 7 }, 7);
ok("none on target reads 0%, not an em dash", d.includes("<b>0%</b>"));

// The legend is the secondary encoding the low-contrast middle step
// depends on, so it has to carry words AND counts for every state.
ok("the legend names every state in words",
   ["on target", "part of the way", "behind"].every((w) => d.includes(w)));
ok("and carries the count beside each",
   /<b>7<\/b>/.test(d), d.slice(d.indexOf("tdleg")));

// --------------------------------------------------- text wears text tokens
// A number is text. If the percentage beside a bar were painted in the
// bar's own colour, the low-contrast middle step would become unreadable
// text rather than a readable mark.
ok("the figure beside a bar is not painted in the series colour",
   !/class="num ' \+ TD_TOKEN/.test(src),
   (src.match(/class="num[^"]*"/g) || []).join(" "));
ok("and the state is on the element as a word, not only as a colour",
   /title="' \+ esc\(TD_WORD\[st\]\)/.test(src));

// ------------------------------------------- one rule, decided in one place
ok("the thresholds are written once",
   (src.match(/pct >= 100/g) || []).length === 1
   && (src.match(/pct >= 70/g) || []).length === 1);
ok("no screen code names the tool's own status colours for a data mark",
   !/var\(--green\)|var\(--gold\)|var\(--terra\)/.test(src),
   (src.match(/var\(--(green|gold|terra)\)/g) || []).join(" "));

console.log("");
if (fails.length) {
  fails.forEach((f) => console.log("FAIL  " + f));
  console.log(`-- dashboard: ${pass} passed, ${fails.length} failed`);
  process.exit(1);
}
console.log(`-- dashboard: ${pass} passed, 0 failed`);
