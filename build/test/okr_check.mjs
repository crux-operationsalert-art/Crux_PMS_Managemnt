// The quarterly scorecard, in OKR shape -- checked as arithmetic, not as a
// picture.
//
// This card shows the numbers behind somebody's bonus, so what could go
// quietly wrong is not the layout but the denominators: a mean taken over
// months that were EXCLUDED, a ratio not capped where the scheme caps it, a
// band boundary off by one, a bar drawn wider than its own track. None of
// those would look wrong on screen. Each is asserted here against numbers
// chosen so that getting it wrong changes the string.
//
// The code under test is read out of build/app/screen-plb.js at run time
// rather than copied, so this can never pass against a stale copy of the
// thing it is testing -- the same reason .github/build-tool.py lifts the
// block from that file instead of restating it.
//
//   /opt/node22/bin/node build/test/okr_check.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "app", "screen-plb.js"), "utf8");
const a = src.indexOf("/* OKR-SCORECARD-START");
const b = src.indexOf("/* OKR-SCORECARD-END */");
if (a < 0 || b < 0 || b < a) {
  console.log("FAIL  the OKR markers are gone from screen-plb.js, so neither");
  console.log("      this check nor the build can find the block.");
  process.exit(1);
}
const block = src.slice(a, b);

// The handful of helpers the block leans on. The real ones live in the page;
// these match their shapes, which is all the card uses of them.
const helpers = `
function esc(s){ return String(s === null || s === undefined ? "" : s)
  .replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;"); }
function pbNum(v, dp){ return v === null || v === undefined || v === ""
  ? "\\u2014" : Number(v).toFixed(dp === undefined ? 2 : dp).replace(/\\.00$/,""); }
function pbMoney(v){ return v === null || v === undefined ? "\\u2014" : "\\u20b9" + v; }
function pbQuarterName(iso){ return "Q " + iso; }
function pbMonths(iso){
  var out=[], y=+iso.slice(0,4), m=+iso.slice(5,7);
  for (var i=0;i<3;i++){ var mm=m+i, yy=y+Math.floor((mm-1)/12); mm=((mm-1)%12)+1;
    out.push(yy+"-"+String(mm).padStart(2,"0")+"-01"); }
  return out;
}
function pbMonthName(iso){ return new Date(iso+"T00:00:00Z")
  .toLocaleDateString("en-GB",{month:"short",year:"numeric",timeZone:"UTC"}); }
`;

// A module does not hoist a declaration out of eval, so the block is
// compiled in its own scope and the four functions handed back.
const { pbOkrBand, pbOkr } = new Function(
  helpers + block + "\n return { pbOkrBand: pbOkrBand, pbOkr: pbOkr };")();

let fails = 0;
function is(name, got, want) {
  if (got === want) console.log("PASS  " + name);
  else {
    console.log("FAIL  " + name + "\n      got  " + JSON.stringify(got) +
                "\n      want " + JSON.stringify(want));
    fails++;
  }
}
function has(name, hay, needle) {
  if (String(hay).indexOf(needle) >= 0) console.log("PASS  " + name);
  else {
    console.log("FAIL  " + name + " -- missing " + JSON.stringify(needle));
    fails++;
  }
}

// ------------------------------------------------------------ the bands
is("1.00 is met", pbOkrBand(1).w, "met");
is("0.99 is only on track", pbOkrBand(0.99).w, "on track");
is("0.70 is the on-track floor", pbOkrBand(0.70).w, "on track");
is("0.69 is at risk", pbOkrBand(0.69).w, "at risk");
is("0.39 is off track", pbOkrBand(0.39).w, "off track");
is("nothing scored is not zero", pbOkrBand(null).w, "not yet scored");

// -------------------------------------------------------- a whole sheet
const sheet = {
  person: "Test Person", chair: "Branch Manager", quarter: "2026-10-01",
  status: "ISSUED", targetPlb: 120000,
  calc: { achievement: 72.4, payoutFactor: 84.8, monthlyMean: 7.2,
          consistency: 0.93, amount: 94636.8 },
  kpis: [
    // met exactly
    { kpiId: "k1", name: "Cases completed", unit: "cases", weight: 40,
      target: 300, actual: 300, ratio: 100, split: [100, 100, 100] },
    // beaten well past the cap: the scheme stops giving credit at 150
    { kpiId: "k2", name: "Collections", unit: "INR", weight: 40,
      target: 1000000, actual: 1800000, ratio: 180, split: [null, null, null] },
    // nothing filed, which is not the same as zero
    { kpiId: "k3", name: "Quality score", unit: "%", weight: 20,
      target: 90, actual: null, ratio: null, split: [90, 90, 90] },
  ],
  attributes: [
    { kpiId: "a1", name: "A-1 Ownership", unit: "A-1", fixed: true,
      milestones: [null, null, null], state: null, proposal: null },
    { kpiId: "a4", name: "A-4 Contribution", unit: "A-4", fixed: false,
      proposal: "Run the branch induction", state: "APPROVED",
      milestones: ["Draft", "Pilot", "Rolled out"] },
  ],
  months: [
    { month: "2026-10-01", attrPoints: 8, kpiPoints: 7, excluded: false },
    { month: "2026-11-01", attrPoints: 6, kpiPoints: 7, excluded: false },
    // an excluded month must not drag the mean down
    { month: "2026-12-01", attrPoints: 0, kpiPoints: 0, excluded: true },
  ],
};

const out = pbOkr(sheet);

has("the headline ring carries Achievement", out, ">72%<");
has("and the word beside it, never colour alone", out, "on track");
has("Objective 1 scores Achievement over 100", out, "0.72 <i>on track</i>");
// (8 + 6) / 2 / 10 = 0.70, and the excluded month is not in it
has("Objective 2 is the mean of SCORED months", out, "0.70 <i>on track</i>");
has("and it says how many months that is", out, "mean of 2 scored months");
has("a measure beaten past the cap reads 1.50", out, "1.50 <i>met</i>");
has("a measure met exactly reads 1.00", out, "1.00 <i>met</i>");
has("a measure with no actual is not scored zero", out, "no actual yet");
has("phasing shows as the month's own number", out, "<b>Oct</b> 100");
has("and an unphased month says so in words", out, "<b>Oct</b> not phased");
has("an attribute's milestones are its check-ins", out, "<b>Dec</b> Rolled out");
has("a fixed attribute is not given a score", out, "same for everyone");
has("the bonus as it stands is shown", out, "₹94636.8");

// A bar wider than its track is how a capped number stops looking capped.
const widths = (out.match(/width:([\d.]+)%/g) || [])
  .map((w) => parseFloat(w.slice(6)));
is("no bar is drawn wider than its track",
   widths.filter((w) => w > 100).length, 0);

// An empty sheet is an ordinary state on day one of a quarter, and the card
// must render rather than throw on it.
let bare = "";
try {
  bare = pbOkr({ quarter: "2026-10-01", calc: {}, kpis: [], attributes: [],
                 months: [] });
} catch (e) {
  bare = "THREW: " + e.message;
}
has("a sheet with nothing on it yet still draws", bare, "No measures are on this sheet");
has("and says there is no figure rather than showing 0.00",
    bare, "No month has been scored yet");

console.log(fails ? "\n" + fails + " FAILED"
                  : "\nthe scorecard: every assertion passed");
process.exit(fails ? 1 : 0);
