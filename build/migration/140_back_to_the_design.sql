-- Back to the design: what had drifted, measured rather than argued about.
--
-- The reference is "Crux App v2.dc.html" in the root of this repo -- the
-- blueprint. docs/DESIGN-CONTRACT.md holds the measurements and the commands
-- to re-take them.
--
-- Applied in four parts, because one tool call carries one migration:
--
--   140a_the_button_hierarchy_the_design_actually_has
--   140b_the_navigation_the_design_specifies
--   140c_a_family_screen_must_still_be_reachable
--   140d_numbers_line_up_as_the_blueprint_sets_them
--
-- 140a - THE BUTTONS. Counting every <button> in the blueprint: 65 white with
-- a #d8d5cd border, 54 white with a blue border and blue text, 43 filled blue,
-- 25 destructive as a white outline with #a03f18 text, 4 filled green. Filled
-- terracotta does not appear once -- there it is an accent, the rule under the
-- header and the badge on a tab. The tool had it as the DEFAULT button, so
-- every primary action on every screen was a solid terracotta block and every
-- destructive action a solid darker one. That is the loudest single reason the
-- tool did not look like the design even where the structure matched.
-- Nine colours were invented alongside it -- three greens, two ambers, a third
-- dark rust. The blueprint's green is #2f7355 on a #f4faf6 tint, pressed
-- #255c44; its amber #8a6d1f on #fdfaf2 with ink #7a5f18; and a status panel
-- always borders with its own colour, never a lightened one.
--
-- 140b - THE NAVIGATION. The blueprint's own definition, and its own reason:
--   navGroups = [ { label:'',        keys:['ideathon'] },
--                 { label:'Mine',    keys:['dash','profile','pms','visits'] },
--                 { label:'Work',    keys:['ogl','escalations','clients','people'] },
--                 { label:'Company', keys:['hr','hiring','join','penalties','coverage',
--                                          'reports','audit','msg','auto','setup','config'] } ]
--   "Grouped navigation -- ten flat tabs was too many to scan. Ideathon sits
--    first and apart, because it is an invitation rather than a duty."
-- The tool had five groups of its own invention -- Work, Standing, Numbers,
-- Keep -- Ideathon buried tenth inside Standing, and ten labels trimmed:
-- Today, Performance, People, Hiring, History, Penalties, Coverage, MIS,
-- Configuration, Mail. Every one says less than the blueprint's. "Penalties"
-- is a subject; "Penalty ledger" is a thing you can open.
--
-- 140c - A REGRESSION IN 140b, caught by rendering the page in a real browser
-- rather than by reading it. currentTab() bounces any tab not in TABS back to
-- Today, and TABS was built from NAV alone, so taking the seven family screens
-- out of the top row made all seven unreachable. The empty sub-strip is how it
-- showed up.
--
-- 140d - NUMBERS, below.

-- The JavaScript 140d inserts, verbatim:

/* The blueprint sets a quantity right-aligned, in the monospace face -- its
   headcount, span, target, achieved, amount, mtd, gap, share and pace columns
   all do it. The tool defines td.num for exactly that and then used it zero
   times in 271 cells, so every number in every table read as prose.
   Which column holds quantities is a property of the data, not of the screen,
   so it is decided here once instead of being marked up 271 times: a column
   counts when every filled cell in it reads as a number and nothing in it is
   a control. Re-run on every render, because most tables are redrawn in
   place without the route changing. */
var NUM_RE = /^[\u20B9$]?\s*-?[\d,]+(\.\d+)?\s*%?$/;
var NUM_SKIP = /year|date|ref\b|^no\.?$/i;
var numBusy = false;
function numberColumns(){
  var host = el("view"); if (!host) return;
  var tables = host.querySelectorAll("table"), t, i, j;
  for (t = 0; t < tables.length; t++) {
    var tb = tables[t];
    if (tb.getAttribute("data-num")) continue;
    tb.setAttribute("data-num", "1");
    var rows = tb.rows, width = 0;
    for (i = 0; i < rows.length; i++) width = Math.max(width, rows[i].cells.length);
    for (j = 0; j < width; j++) {
      var head = "", filled = 0, numeric = 0, ok = true;
      for (i = 0; i < rows.length && ok; i++) {
        var c = rows[i].cells[j]; if (!c) continue;
        var v = (c.textContent || "").trim();
        if (c.tagName === "TH") { head = v; continue; }
        if (c.querySelector("button,a,input,select,textarea")) { ok = false; break; }
        if (!v || v === "\u2014" || v === "-") continue;
        filled++; if (NUM_RE.test(v)) numeric++;
      }
      if (!ok || !filled || numeric !== filled || NUM_SKIP.test(head)) continue;
      for (i = 0; i < rows.length; i++) {
        var cc = rows[i].cells[j]; if (cc) cc.className += (cc.className ? " " : "") + "num";
      }
    }
  }
}
function watchNumbers(){
  var host = el("view"); if (!host || !window.MutationObserver) return;
  new MutationObserver(function(){
    if (numBusy) return;
    numBusy = true;
    try { numberColumns(); } finally { numBusy = false; }
  }).observe(host, { childList: true, subtree: true });
  numberColumns();
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", watchNumbers);
else watchNumbers();

-- ---------------------------------------------------------------------
-- VERIFIED before and after publishing:
--
--   * the live page serves 200 through the crux function at 235,786 bytes,
--     carrying the new nav, the shine pill, the sub-strip and the TABS fix,
--     and none of the nine invented colours.
--   * rendered headless in Chromium, signed in as an ADMIN: the nav comes out
--     as four groups in the blueprint's order -- Ideathon alone with its pill,
--     then Mine (Dashboard, My profile, Performance & appraisal, Visits &
--     claims), Work (OGL Assignment, Escalations, Clients, My team &
--     structure) and Company (ten). No console errors beyond the API calls the
--     sandbox blocks.
--   * on #matrix the strip reads "Clients | Escalation matrix" with the second
--     underlined, which is what proved 140c was needed and then that it worked.
--   * a MIS table rendered with seven columns marked exactly four of them
--     numeric -- Branches, Target, Achieved, % -- and left Client, Owner and
--     the button column alone.
