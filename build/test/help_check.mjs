// The floating question mark -- checked as a rule, not as a picture.
//
// The panel itself is layout and a screenshot would settle it. What a
// screenshot would NOT settle is the rule that decides which paragraphs
// come off the screen, and that rule runs on every screen in the tool
// including the ones this repository has never had the text of. Get it
// wrong in the generous direction and an error message disappears into a
// panel nobody opens; get it wrong in the mean direction and the clutter
// stays.
//
// So the rule is asserted here against the shapes it will actually meet:
// a label, a unit hint, a long explanation, an error, an empty state, and
// a paragraph inside a form the person is typing into.
//
// The code under test is read out of build/app/screen-help.js at run time
// rather than copied, so this cannot pass against a stale copy.
//
//   /opt/node22/bin/node build/test/help_check.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "app", "screen-help.js"), "utf8");

let pass = 0;
const fails = [];
function ok(name, cond, saw) {
  if (cond) { pass++; console.log("PASS  " + name); }
  else { fails.push(name + (saw === undefined ? "" : "  -- saw: " + saw)); }
}

// ------------------------------------------------- a very small fake DOM
// Only what the module touches: closest(), textContent, getAttribute,
// setAttribute, style.display, and querySelectorAll over a flat list.
class FakeNode {
  constructor(text, { cls = "", inside = "" } = {}) {
    this._text = text;
    this.cls = cls;
    this.inside = inside;          // a selector string the ancestor matches
    this.attrs = {};
    this.style = {};
    this.innerHTML = text;
  }
  get textContent() { return this._text; }
  getAttribute(k) { return this.attrs[k] ?? null; }
  setAttribute(k, v) { this.attrs[k] = v; }
  closest(sel) {
    // sel is a comma list; match if this node's declared ancestor is named
    return sel.split(",").map((s) => s.trim()).some((s) => this.inside === s)
      ? {} : null;
  }
}

const esc = (s) => String(s ?? "")
  .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  .replace(/"/g, "&quot;");

// The module as a module: evaluate it with the globals it reaches for
// stubbed, and hand back the functions worth asserting on.
const harness = `
${src.replace(/\(function qhBoot\(\)\{[\s\S]*?\}\)\(\);/, "/* boot skipped */")}
return { qhIsProse, qhCollect, qhBody, HELP, HELP_JOURNEY, QH };
`;

let mod;
try {
  const nodes = { view: null };
  const stubEl = (id) => nodes[id] ?? null;
  mod = new Function("el", "esc", "document", "window", "currentTab", "LABEL",
                     "setTimeout", "clearTimeout", harness)(
    stubEl, esc,
    { readyState: "complete", addEventListener() {}, createElement: () => ({ style: {}, classList: { toggle() {} }, setAttribute() {} }), body: { appendChild() {} } },
    {},
    () => "perf",
    { perf: "Performance & appraisal" },
    () => {}, () => {},
  );
} catch (e) {
  console.log("FAIL  screen-help.js would not evaluate: " + e.message);
  process.exit(1);
}

const { qhIsProse, qhBody, HELP, HELP_JOURNEY, QH } = mod;

// ------------------------------------------------------------- the rule
const LONG = "A measure with no target is not scored and does not drag the "
  + "average down, it is left out and says so, which is why a blank is "
  + "better than a nought.";
const SHORT = "weight 33.3%";
const MEDIUM = "One filing per day, carrying every figure.";

ok("a long explanation is prose and comes off the screen",
   qhIsProse(new FakeNode(LONG)) === true);
ok("a short label is not",
   qhIsProse(new FakeNode(SHORT)) === false);
ok("and nor is a one-line hint",
   qhIsProse(new FakeNode(MEDIUM)) === false, MEDIUM.length + " chars");

ok("the boundary is 100 characters, not 99",
   qhIsProse(new FakeNode("x".repeat(99))) === false
   && qhIsProse(new FakeNode("x".repeat(100))) === true);

ok("a long paragraph inside an open form stays where it is",
   qhIsProse(new FakeNode(LONG, { inside: ".plform" })) === false);
ok("and so does one inside the panel itself, which cannot eat its own tail",
   qhIsProse(new FakeNode(LONG, { inside: ".qhpanel" })) === false);

const already = new FakeNode(LONG);
already.setAttribute("data-qh", "1");
ok("one already moved is not moved twice",
   qhIsProse(already) === false);

// Whitespace: a paragraph of 400 spaces is not 400 characters of prose.
ok("padding is not length",
   qhIsProse(new FakeNode("   " + "x".repeat(40) + "   ".repeat(40))) === false);

// ------------------------------------- what the rule must never swallow
// These are the three classes the tool uses to SAY something, and the
// selector must not reach them at all. Asserted against the selector
// string rather than the function, because the mistake would be made
// there.
const sel = (src.match(/querySelectorAll\(("|')([^"']+)\1\)/) || [])[2] || "";
ok("the selector names the paragraph classes it means to collect",
   sel.includes("p.mute"), sel);
ok("and never reaches .msg, which is how the tool reports a failure",
   !sel.includes(".msg"), sel);
ok("nor .empty, which is a screen saying why it has nothing on it",
   !sel.includes(".empty"), sel);

// --------------------------------------------------------- the writing
ok("every screen in HELP has a purpose and at least two steps",
   Object.keys(HELP).every((k) => HELP[k].t && HELP[k].w && HELP[k].s.length >= 2),
   Object.keys(HELP).filter((k) => !(HELP[k].s || []).length >= 2).join(","));

ok("the two scoring screens carry the journey, and no others do",
   Object.keys(HELP).filter((k) => HELP[k].j).sort().join(",") === "perf,plb",
   Object.keys(HELP).filter((k) => HELP[k].j).join(","));

ok("the journey runs day, month, quarter, then the money",
   HELP_JOURNEY.length === 4
   && /day/i.test(HELP_JOURNEY[0][0]) && /month/i.test(HELP_JOURNEY[1][0])
   && /quarter/i.test(HELP_JOURNEY[2][0])
   && /bonus/i.test(HELP_JOURNEY[3][1]));

ok("Performance says in as many words that you do not set your own",
   HELP.perf.s.some((s) => /cannot set your own/i.test(s)));

// ------------------------------------------------------- the panel body
QH.moved = [];
let body = qhBody();
ok("the panel names the screen it is open on",
   body.includes("Performance &amp; appraisal"), body.slice(0, 120));
ok("and offers a way out of itself",
   body.includes('id="qhclose"'));
ok("with nothing collected, it does not head an empty section",
   !body.includes("Also on this screen"));

QH.moved = ["Something long that was on the screen."];
body = qhBody();
ok("with something collected, it is headed and shown",
   body.includes("Also on this screen")
   && body.includes("Something long that was on the screen."));

// A screen with no written entry must still open rather than break.
mod.QH.moved = [];
const other = new Function("el", "esc", "document", "window", "currentTab",
                           "LABEL", "setTimeout", "clearTimeout", harness)(
  () => null, esc,
  { readyState: "complete", addEventListener() {} }, {},
  () => "somethingNobodyWrote", {}, () => {}, () => {});
ok("a screen with no written guide still opens and says so",
   /no written guide/i.test(other.qhBody()));

// --------------------------------------------------------------- report
console.log("");
if (fails.length) {
  fails.forEach((f) => console.log("FAIL  " + f));
  console.log(`-- help: ${pass} passed, ${fails.length} failed`);
  process.exit(1);
}
console.log(`-- help: ${pass} passed, 0 failed`);
