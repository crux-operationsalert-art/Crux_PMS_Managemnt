/* ==================================================================== plb
   Performance & bonus — the PLB scheme.

   PLB = Target × Payout Factor × Consistency Factor.

   The scheme's own test, from the employee explainer: "If explaining any
   individual result needs more than this plus your own goal sheet, the
   design has failed its own test." So this screen shows the whole sum,
   not the answer: every KPI's target, actual and ratio, every monthly
   score and what it was built from, the curve, the dial, and the
   arithmetic written out as a sentence anyone can check by hand.

   Section 6.2 of the scorecard guide lists twelve things an employee must
   always be able to see and says that if any is missing, they have not
   been given a published result. plb_sheet() returns all twelve in one
   object so this screen cannot accidentally show eleven, and the checklist
   at the foot of the result says which are present.                     */
var PB = { q:null, data:null, quarter:null, tab:"mine", busy:false, open:null, reg:null };

function pbSay(box, kind, text){ var e = el(box); if (e) e.innerHTML = msg(kind, text); }
function pbNum(v, dp){ return v === null || v === undefined || v === "" ? "—"
  : Number(v).toFixed(dp === undefined ? 2 : dp); }
function pbMoney(v){ return v === null || v === undefined ? "—" : money(v); }

/* Which quarter, as its first day, and how to say it in Indian financial
   terms — a quarter beginning in October is Q3 of FY 2026-27. */
function pbQuarterStart(d){
  var x = d ? new Date(d) : new Date();
  return new Date(Date.UTC(x.getUTCFullYear(), x.getUTCMonth() - (x.getUTCMonth() % 3), 1))
    .toISOString().slice(0, 10);
}
function pbQuarterName(iso){
  if (!iso) return "";
  var y = Number(iso.slice(0,4)), m = Number(iso.slice(5,7));
  var fq = m === 4 ? 1 : m === 7 ? 2 : m === 10 ? 3 : 4;
  var fy = m >= 4 ? y : y - 1;
  return "Q" + fq + " FY " + fy + "-" + String(fy + 1).slice(2);
}
function pbMonths(iso){
  var out = [], y = Number(iso.slice(0,4)), m = Number(iso.slice(5,7));
  for (var i = 0; i < 3; i++) {
    var mm = m + i, yy = y + Math.floor((mm - 1) / 12);
    mm = ((mm - 1) % 12) + 1;
    out.push(yy + "-" + String(mm).padStart(2, "0") + "-01");
  }
  return out;
}
function pbMonthName(iso){
  return new Date(iso + "T00:00:00Z").toLocaleDateString("en-GB",
    { month:"short", year:"numeric", timeZone:"UTC" });
}

/* ------------------------------------------------------------- the entry */
async function vPlb(){
  if (!PB.quarter) PB.quarter = pbQuarterStart();
  var d = await plb("/plb/mine?quarter=" + PB.quarter);
  if (d.error) {
    el("view").innerHTML = "<h1>Performance &amp; bonus</h1>" +
      msg("bad", d.reason || d.error);
    return;
  }
  PB.data = d;
  /* Asked for by EVERYBODY, not only the people who run the scheme.
     plb_quarter is already scoped -- `where perf_rel(p_actor, p.id) is not
     null` -- so a manager gets their own line and nobody else's, and every
     row carries maySet. Gating the CALL on maySetUp was what locked a
     manager out of their own team's quarter: the data was always theirs to
     have, the screen simply never asked for it. */
  if (!PB.q) PB.q = await plb("/plb/quarter?quarter=" + PB.quarter);

  /* #plb/<personId> -- somebody arrived here from that person's tile under
     My team, meaning to score THEM. Open their sheet rather than leaving
     them on their own, which is what made this screen look as though it
     were asking a manager to self-evaluate their report.

     The id is a person; the panel wants a sheet. PB.q carries both for
     every sheet in the quarter, so the map is already here and needs no
     second call. If they hold no sheet this quarter, the screen is left
     as it was -- the manager panel below says so in its own words. */
  var want = (location.hash || "").split("/")[1];
  if (want && PB.q && !PB.open) {
    var row = (PB.q.sheets || []).filter(function(x){
      return x.personId === want; })[0];
    if (row) {
      /* PB.open is the sheet itself, as the Open button sets it -- not a
         wrapper around it. The panel reads PB.open.sheetId straight off. */
      var o = await plb("/plb/sheet/" + row.sheetId);
      if (!o.error && o.sheet) PB.open = o.sheet;
    }
  }
  pbRender();
}

/* ----------------------------------------------------------- the scheme */
function pbScheme(){
  return '<div class="card pbscheme">' +
    '<h2>How your bonus is worked out</h2>' +
    '<p class="pbformula">PLB&nbsp; = &nbsp;Target&nbsp; ×&nbsp; Payout Factor&nbsp; ×&nbsp; Consistency Factor</p>' +
    '<div class="pbthree">' +
      '<div><span class="pbstep">1</span><b>Target</b>' +
        '<p>20% of fixed cash salary a year. A quarter of it is in play each quarter.</p></div>' +
      '<div><span class="pbstep">2</span><b>Payout Factor</b>' +
        '<p>What your KPI results earn. 85% of target earns the full amount; ' +
        '115% and above earns 125%, the ceiling. Below 50% earns nothing.</p></div>' +
      '<div><span class="pbstep">3</span><b>Consistency Factor</b>' +
        '<p>How much of it is released. Your average monthly score divided by ten, ' +
        'floored at 0.30 — a bad quarter still pays 30% of what was earned.</p></div>' +
    '</div>' +
    '<p class="mute">The steepest climb is between 50 and 85, so closing a gap to ' +
    'acceptable is worth more per point than anything else. Between 85 and 95 the ' +
    'line flattens on purpose: you are already at full target and that band protects ' +
    'it. There is no cliff anywhere on the curve.</p>' +
    '</div>';
}

/* --------------------------------------------------------- the goal sheet */
/* OKR-SCORECARD-START
   -- Everything between this marker and OKR-SCORECARD-END is lifted
   verbatim by .github/build-tool.py and patched into the page. The markers
   exist so the code lives in ONE file: this screen is already inside
   app_page, so an addition to it has to be injected, and a copy kept in
   the build script to inject would be a second place to fix a bug in.

   =====================================================================
   The quarterly scorecard, in OKR shape.

   Not a second calculation. Every number on this card is one the scheme
   already computed and the table below already shows -- the same ratio,
   the same achievement, the same monthly points. What changes is the
   shape: an objective with key results under it, each key result carrying
   one score between 0 and 1, which is how an OKR scorecard reads and is
   not how a seven-column table reads.

   Two objectives, because the scheme has exactly two halves and says so:
   KPIs are what you deliver and carry all of Achievement; attributes are
   how you work and carry none of it. Putting them under one heading would
   be inventing a third thing.

   The score on a key result is the scheme's own ratio divided by a
   hundred. 1.00 is the target met. The scheme gives credit above that up
   to 1.50 and no further, so the bar is drawn against 1.50 and the line
   at target is marked -- a bar that fills at 1.00 and then stops moving
   would hide the difference between meeting a target and beating it.   */

function pbOkrBand(v){
  if (v === null || v === undefined) return { c:"none", w:"not yet scored" };
  if (v >= 1)    return { c:"good",  w:"met" };
  if (v >= 0.7)  return { c:"part",  w:"on track" };
  if (v >= 0.4)  return { c:"risk",  w:"at risk" };
  return { c:"short", w:"off track" };
}

/* A ring rather than a bar for the one headline number, and a ring drawn
   as an arc with a number in the middle of it -- the number is the thing
   being read; the ring is only how far round it is. */
function pbRing(pct, band){
  var p = pct === null || pct === undefined ? 0 : Math.max(0, Math.min(100, pct));
  var r = 34, c = 2 * Math.PI * r;
  return '<svg class="pbring ' + band.c + '" viewBox="0 0 80 80" width="80" height="80" ' +
      'role="img" aria-label="' + esc(pct === null || pct === undefined ? "not yet scored"
        : Math.round(pct) + " per cent, " + band.w) + '">' +
    '<circle class="pbrtrack" cx="40" cy="40" r="' + r + '" fill="none" stroke-width="7"/>' +
    '<circle class="pbrval" cx="40" cy="40" r="' + r + '" fill="none" stroke-width="7" ' +
      'stroke-linecap="round" transform="rotate(-90 40 40)" ' +
      'stroke-dasharray="' + (c * p / 100).toFixed(1) + ' ' + c.toFixed(1) + '"/>' +
    '<text class="pbrtx" x="40" y="45" text-anchor="middle">' +
      (pct === null || pct === undefined ? '&ndash;' : Math.round(pct) + '%') + '</text>' +
    '</svg>';
}

/* One key result. The bar runs to 1.50 because that is where the scheme
   stops counting, and the target line is drawn at two thirds of it. */
function pbKr(n, name, unit, score, left, right, weight, checks){
  var b = pbOkrBand(score);
  var w = score === null || score === undefined ? 0
        : Math.max(1.5, Math.min(100, (score / 1.5) * 100));
  return '<div class="pbkr">' +
    '<div class="pbkrh">' +
      '<span class="pbkrn">KR' + n + '</span>' +
      '<span class="pbkrname">' + esc(name) + '</span>' +
      (weight ? '<span class="pbkrw">weight ' + pbNum(weight, 0) + '%</span>' : '') +
      '<span class="pbkrs ' + b.c + '">' +
        (score === null || score === undefined ? '&ndash;' : score.toFixed(2)) +
        ' <i>' + esc(b.w) + '</i></span>' +
    '</div>' +
    '<div class="pbkrbar ' + b.c + '"><i style="width:' + w.toFixed(1) + '%"></i>' +
      '<u title="target"></u></div>' +
    '<div class="pbkrf">' + esc(left) +
      (right ? ' <span class="mute">&middot; ' + esc(right) : '') +
      (unit ? ' <span class="mute">' + esc(unit) + '</span>' : '') +
      (right ? '</span>' : '') + '</div>' +
    (checks && checks.length
      ? '<div class="pbchk">' + checks.map(function(c){
          return '<span class="pbchki' + (c.done ? ' on' : '') + '">' +
            '<b>' + esc(c.when) + '</b> ' + esc(c.what) + '</span>';
        }).join("") + '</div>'
      : '') +
    '</div>';
}

function pbOkr(s){
  var c = s.calc || {}, kpis = s.kpis || [], attrs = s.attributes || [];
  var months = (s.months || []).filter(function(m){ return !m.excluded; });
  var mn = pbMonths(s.quarter);

  /* Objective 1's score is Achievement, which the scheme already worked
     out as the weighted ratio across every measure. Recomputing it here
     from the same rows would be a second opinion about a number that is
     not in doubt. */
  var o1 = c.achievement === null || c.achievement === undefined
         ? null : Number(c.achievement) / 100;

  /* Objective 2 has no single figure in the scheme, because attributes
     are scored monthly and never quarterly. The mean of the months that
     were scored is the honest reading of it, and it says how many months
     that is rather than presenting one month as a quarter. */
  var ap = months.filter(function(m){ return m.attrPoints !== null && m.attrPoints !== undefined; });
  var o2 = ap.length
    ? ap.reduce(function(a, m){ return a + Number(m.attrPoints); }, 0) / ap.length / 10
    : null;

  var b1 = pbOkrBand(o1), b2 = pbOkrBand(o2);
  var hb = pbOkrBand(o1);

  var krs = kpis.map(function(k, i){
    var sc = k.ratio === null || k.ratio === undefined
           ? null : Math.min(Number(k.ratio) / 100, 1.5);
    var split = k.split || [];
    /* The monthly split IS the check-in cadence: the quarter divided into
       three promises rather than one. Where phasing has written a share,
       it is shown as the month's own number. */
    var checks = mn.map(function(iso, j){
      return { when: pbMonthName(iso).slice(0, 3),
               what: split[j] === null || split[j] === undefined
                     ? "not phased" : pbNum(split[j]),
               done: split[j] !== null && split[j] !== undefined };
    });
    return pbKr(i + 1, k.name, k.unit, sc,
      pbNum(k.actual) + " of " + pbNum(k.target),
      k.ratio === null ? "no actual yet" : pbNum(k.ratio, 1) + "% of target",
      k.weight, checks);
  }).join("");

  var akrs = attrs.map(function(a, i){
    var ms = a.milestones || [];
    var checks = mn.map(function(iso, j){
      return { when: pbMonthName(iso).slice(0, 3),
               what: ms[j] || (a.fixed ? "as published" : "not set"),
               done: !!ms[j] || a.fixed };
    });
    /* An attribute has no ratio of its own -- only the month's points,
       which cover all five together. So no per-attribute score is shown
       rather than one invented by dividing something by five. */
    var b = a.fixed ? { c:"none", w:"same for everyone" }
          : a.state === "APPROVED" ? { c:"good", w:"approved" }
          : a.proposal ? { c:"part", w:"waiting on your manager" }
          : { c:"risk", w:"you propose this" };
    return '<div class="pbkr">' +
      '<div class="pbkrh">' +
        '<span class="pbkrn">' + esc((a.unit || "").split(" ")[0] || ("A" + (i + 1))) + '</span>' +
        '<span class="pbkrname">' + esc(a.proposal || a.name) + '</span>' +
        '<span class="pbkrs ' + b.c + '"><i>' + esc(b.w) + '</i></span>' +
      '</div>' +
      (a.proposal && a.name !== a.proposal
        ? '<div class="pbkrf mute">' + esc(a.name) + '</div>' : '') +
      '<div class="pbchk">' + checks.map(function(x){
        return '<span class="pbchki' + (x.done ? ' on' : '') + '">' +
          '<b>' + esc(x.when) + '</b> ' + esc(x.what) + '</span>';
      }).join("") + '</div>' +
      '</div>';
  }).join("");

  return '<div class="card pbokr">' +
    '<div class="pbokrh">' +
      '<div>' +
        '<h2>Quarterly scorecard</h2>' +
        '<p class="plsub">' + esc(s.person || "") +
          (s.chair ? ' &middot; ' + esc(s.chair) : '') +
          ' &middot; ' + esc(pbQuarterName(s.quarter)) +
          ' &middot; ' + esc((s.status || "").toLowerCase()) + '</p>' +
      '</div>' +
      '<div class="pbokrring">' + pbRing(c.achievement, hb) +
        '<span class="pbokrw ' + hb.c + '">' + esc(hb.w) + '</span>' +
        '<span class="mute">Achievement</span></div>' +
    '</div>' +

    '<div class="pbstats">' +
      '<div class="pbstat"><span>Payout factor</span><b>' + pbNum(c.payoutFactor, 1) + '%</b>' +
        '<i>what Achievement converts to</i></div>' +
      '<div class="pbstat"><span>Monthly mean</span><b>' + pbNum(c.monthlyMean, 2) + '<u>/10</u></b>' +
        '<i>' + esc(months.length) + ' month' + (months.length === 1 ? '' : 's') +
        ' counted</i></div>' +
      '<div class="pbstat"><span>Consistency</span><b>' + pbNum(c.consistency, 3) + '</b>' +
        '<i>steady beats spiky</i></div>' +
      '<div class="pbstat pbpay"><span>Bonus as it stands</span><b>' +
        pbMoney(c.amount) + '</b><i>of ' + pbMoney(s.targetPlb) + ' target</i></div>' +
    '</div>' +

    '<div class="pbobj">' +
      '<div class="pbobjh"><span class="pbobjt">Objective 1</span>' +
        '<h3>Deliver the quarter</h3>' +
        '<span class="pbobjs ' + b1.c + '">' +
          (o1 === null ? '&ndash;' : o1.toFixed(2)) + ' <i>' + esc(b1.w) + '</i></span></div>' +
      '<p class="mute">The measures of your chair. 75% of each monthly score, and ' +
        'all of Achievement. 1.00 is the target met; the scheme counts up to 1.50 ' +
        'and no further.</p>' +
      (krs || '<p class="mute">No measures are on this sheet.</p>') +
    '</div>' +

    '<div class="pbobj">' +
      '<div class="pbobjh"><span class="pbobjt">Objective 2</span>' +
        '<h3>Work the way the scheme asks</h3>' +
        '<span class="pbobjs ' + b2.c + '">' +
          (o2 === null ? '&ndash;' : o2.toFixed(2)) + ' <i>' + esc(b2.w) + '</i></span></div>' +
      '<p class="mute">The five attributes. 25% of each monthly score and none of ' +
        'Achievement, so they change how you are scored and never what you are paid ' +
        'for delivering. ' +
        (ap.length
          ? 'The figure is the mean of ' + esc(ap.length) + ' scored month' +
            (ap.length === 1 ? '' : 's') + ' out of ten &mdash; attributes are scored ' +
            'monthly and never quarterly, so there is no other honest reading.'
          : 'No month has been scored yet, so there is no figure.') + '</p>' +
      (akrs || '<p class="mute">No attributes are on this sheet.</p>') +
    '</div>' +

    '<p class="mute pbokrf">Every number here is the scheme&rsquo;s own &mdash; the same ' +
      'ratio, the same Achievement, the same monthly points as the tables below. ' +
      'Nothing on this card is computed a second way.</p>' +
    '</div>';
}
/* OKR-SCORECARD-END */

function pbGoalSheet(s){
  var kpis = s.kpis || [], attrs = s.attributes || [];
  var rows = kpis.map(function(k, i){
    var split = (k.split || []).map(function(x){ return pbNum(x, 0) + "%"; }).join(" · ");
    return '<tr><td class="pbn">' + (i + 1) + '</td>' +
      '<td><b>' + esc(k.name) + '</b><div class="mute">' + esc(k.unit || "") + '</div></td>' +
      '<td class="num">' + pbNum(k.weight, 2) + '%</td>' +
      '<td class="num">' + pbNum(k.target) +
        (k.basisLevel ? '<div class="mute">Level ' + esc(k.basisLevel) +
          (k.basisNote ? ' · ' + esc(k.basisNote) : '') + '</div>' : '') + '</td>' +
      '<td class="mute">' + esc(split) + '</td>' +
      '<td class="num">' + pbNum(k.actual) + '</td>' +
      '<td class="num">' + (k.ratio === null ? '—' : pbNum(k.ratio, 1) + '%') +
        (k.ratio !== null && Number(k.ratio) > 150
          ? '<div class="mute">capped at 150%</div>' : '') + '</td></tr>';
  }).join("");

  var arows = attrs.map(function(a){
    var ms = (a.milestones || []).filter(function(x){ return x; });
    return '<tr><td><b>' + esc(a.name) + '</b><div class="mute">' + esc(a.unit || "") + '</div></td>' +
      '<td>' + (a.fixed
        ? '<span class="pill">same for everyone</span>'
        : (a.proposal
            ? '<b>' + esc(a.proposal) + '</b>' +
              (a.evidence ? '<div class="mute">Evidence: ' + esc(a.evidence) + '</div>' : '') +
              (ms.length ? '<ol class="pbms">' + ms.map(function(x){
                  return '<li>' + esc(x) + '</li>'; }).join("") + '</ol>' : '') +
              (a.overlapNote ? '<div class="pbgap">Overlap flagged — ' + esc(a.overlapNote) +
                '. An activity cannot count twice.</div>' : '') +
              (a.decidedNote ? '<div class="mute">' + esc(a.decidedNote) + '</div>' : '')
            : '<span class="pill warn">you propose this</span>')) + '</td>' +
      '<td>' + pbAttrState(a) + '</td>' +
      '<td class="plact">' + (a.fixed ? '' :
        '<button class="btn" data-pbattr="' + esc(a.kpiId) + '">' +
        (a.proposal ? 'Change' : 'Propose') + '</button>') + '</td></tr>';
  }).join("");

  return '<div class="card"><h2>Your goal sheet</h2>' +
    '<p class="plsub">' + esc(s.chair || "") + ' · ' + esc(pbQuarterName(s.quarter)) +
      ' · ' + esc((s.status || "").toLowerCase()) +
      (s.isDefault ? ' · <span class="pill warn">registry default</span>' : '') +
      ' · target ' + pbMoney(s.targetPlb) + '</p>' +
    (s.isDefault ? msg("warn", "No goal sheet reached you in time, so your chair's " +
      "standard sheet applies. You cannot be scored below what it produces.") : "") +
    '<h4 class="plh">KPIs — what you deliver · 75% of the monthly score, all of Achievement</h4>' +
    '<div class="scroll"><table>' +
      '<tr><th></th><th>Measure</th><th>Weight</th><th>Target</th>' +
      '<th>Monthly split</th><th>Actual</th><th>Ratio</th></tr>' + rows + '</table></div>' +
    '<h4 class="plh">Attributes — how you work · 25% of the monthly score, none of Achievement</h4>' +
    '<div class="scroll"><table><tr><th>Attribute</th><th>What it is</th>' +
      '<th>Where it stands</th><th></th></tr>' + arows + '</table></div>' +
    '<div id="pbattrpanel"></div><div id="pbattrmsg"></div>' +
    '<p class="mute">A-4 and A-5 are the only things in the whole scheme you choose. ' +
    'Three questions decide whether a proposal is admissible: is it externally verifiable, ' +
    'does it have a milestone for each month rather than one end date, and is it absent ' +
    'from your measure set. The third is checked automatically and flagged, not refused — ' +
    'your manager looks at it.</p>' +
    '<p class="mute">Your manager selects no KPI, adds none and removes none — they ' +
    'come from your chair\'s published measure set, identical for every seat of the ' +
    'chair. Only the target values differ.</p>' +
    (s.status === "ISSUED"
      ? '<p><button class="btn primary" id="pback">Acknowledge this sheet</button> ' +
        '<span class="mute">Not acknowledging changes nothing — it still operates, and ' +
        'the fact is simply recorded.</span></p><div id="pbackmsg"></div>'
      : (s.acknowledgedAt
          ? '<p class="mute">Acknowledged ' + esc(when(s.acknowledgedAt)) + '.</p>' : '')) +
    '</div>';
}

/* The four states an attribute can be in, said plainly. EMPTY is not an
   error -- it is a sentence not yet written. */
function pbAttrState(a){
  if (a.fixed) return '<span class="mute">fixed</span>';
  if (a.state === "APPROVED") return '<span class="pill ok">approved' +
    (a.approvedBy ? ' by ' + esc(a.approvedBy) : '') + '</span>';
  if (a.state === "PROPOSED") return '<span class="pill warn">waiting on your manager</span>';
  if (a.state === "RETURNED") return '<span class="pill bad">returned — propose again</span>';
  return '<span class="mute">nothing proposed</span>';
}

/* Proposing. Every field the admissibility test asks for is a field here, so
   a rejection for a missing milestone happens before the manager reads it. */
function pbAttrForm(kpiId){
  var s = PB.data.sheet, a = null;
  (s.attributes || []).forEach(function(x){ if (x.kpiId === kpiId) a = x; });
  if (!a) return;
  var ms = a.milestones || [];
  var v = function(x){ return x === null || x === undefined ? "" : esc(x); };
  el("pbattrpanel").innerHTML = '<div class="plform">' +
    '<h4 class="plh">' + esc(a.name) + '</h4>' +
    '<p class="mute">' + esc(a.unit || "") + '</p>' +
    '<label>What you are proposing<br><input id="pbap" style="min-width:420px" value="' +
      v(a.proposal) + '"></label>' +
    '<p class="mute">Q1 — externally verifiable. A certificate, a ticket, a sign-off, ' +
    'a document reference. Self-assessment is not evidence.</p>' +
    '<label>Evidence<br><input id="pbae" style="min-width:420px" value="' + v(a.evidence) + '"></label>' +
    '<p class="mute">Q2 — a milestone for each month, not one end date. Without them you ' +
    'score zero in the months before completion.</p>' +
    '<label>Month 1<br><input id="pbam1" style="min-width:320px" value="' + v(ms[0]) + '"></label> ' +
    '<label>Month 2<br><input id="pbam2" style="min-width:320px" value="' + v(ms[1]) + '"></label> ' +
    '<label>Month 3<br><input id="pbam3" style="min-width:320px" value="' + v(ms[2]) + '"></label>' +
    '<p><button class="btn primary" id="pbago">Propose</button> ' +
    '<button class="btn" id="pbacancel">Cancel</button></p></div>';
  el("pbacancel").onclick = function(){ el("pbattrpanel").innerHTML = ""; };
  el("pbago").onclick = async function(){
    if (await pbDo(el("pbago"), "/plb/attr/propose", {
          sheetId: s.sheetId, kpiId: kpiId,
          proposal: el("pbap").value, evidence: el("pbae").value,
          m1: el("pbam1").value, m2: el("pbam2").value, m3: el("pbam3").value }, "pbattrmsg"))
      setTimeout(pbReload, 900);
  };
}

/* ------------------------------------------------------------- disputes */
/* Ten working days, counted on the calendar of the place the person actually
   works in -- which is why the window closes on a different day in Pune than
   in Kolkata, and why the screen says which calendar it used. */
function pbDisputes(s, mine){
  var w = s.disputeWindow || {}, ds = s.disputes || [];
  if (!w.published && !ds.length) return "";
  /* Somebody running the scheme can have their own dispute card and
     somebody else's open at once, so the two cards cannot share ids. */
  var panel = mine ? "pbdpanel" : "pbmdpanel", box = mine ? "pbdmsg" : "pbmdmsg";

  var rows = ds.map(function(d){
    var stage = (d.stage || "").toLowerCase();
    return '<tr class="' + (d.overdue ? "pbover" : "") + '">' +
      '<td><b>' + esc(pbElement(d)) + '</b>' +
        '<div class="mute">' + esc(d.claimed) + '</div>' +
        '<div class="mute">Evidence: ' + esc(d.evidence) + '</div></td>' +
      '<td>' + esc(stage) + (d.outcome ? ' · ' + esc(d.outcome.toLowerCase().replace(/_/g," ")) : '') +
        (d.overdue ? '<div class="pbgap">overdue — your own time limits extend by the delay</div>' : '') +
        '</td>' +
      '<td class="mute">' + esc(pbClock(d)) + '</td>' +
      '<td class="num">' + (d.ringFenced ? pbMoney(d.ringFenced) : '—') + '</td>' +
      '<td>' + (d.response ? '<div>' + esc(d.response) + '</div><div class="mute">' +
          esc(d.respondedBy || "") + '</div>' : '<span class="mute">none yet</span>') +
        (d.escalateReason ? '<div class="pbgap">Escalated: ' + esc(d.escalateReason) + '</div>' : '') +
        (d.decision ? '<div class="pbsum">' + esc(d.decision) + ' — ' +
          esc(d.decidedBy || "") + '</div>' : '') + '</td>' +
      '<td class="plact">' + pbDisputeActions(d, mine) + '</td></tr>';
  }).join("");

  return '<div class="card"><h2>If you disagree</h2>' +
    (w.published
      ? '<p class="plsub">Published ' + esc(day(w.opensOn)) + ' · the window closes ' +
        esc(day(w.closesOn)) + ' · ten working days on the ' +
        esc(w.centre || "national") + ' calendar · ' +
        (w.open ? esc(w.workingDaysLeft) + ' working day(s) left' : 'closed') + '</p>'
      : '<p class="plsub">' + esc(w.why || "Not published yet") + '</p>') +
    '<p class="mute">Name one element and the figure you believe is right, with your ' +
    'evidence. You are paid at the undisputed level meanwhile — the contested part is ' +
    'ring-fenced, not withheld. Raising a dispute is not a ground for any adverse ' +
    'consequence and may not show up in any later score, attribute, gate or assessment.</p>' +
    (ds.length
      ? '<div class="scroll"><table><tr><th>What</th><th>Stage</th><th>Clock</th>' +
        '<th>Ring-fenced</th><th>Their answer</th><th></th></tr>' + rows + '</table></div>'
      : '') +
    '<div id="' + panel + '"></div>' +
    (mine && w.open
      ? '<p><button class="btn" id="pbdnew">Raise a dispute</button></p>'
      : '') +
    '<div id="' + box + '"></div></div>';
}

function pbElement(d){
  var n = { TARGET:"Target", ACTUAL:"Actual", WEIGHT:"Weight", MONTH_SCORE:"Monthly score",
    ACHIEVEMENT:"Achievement", PAYOUT_FACTOR:"Payout factor", MONTHLY_MEAN:"Monthly mean",
    CONSISTENCY:"Consistency factor", GATE:"Gate", TARGET_PLB:"Target PLB",
    AMOUNT:"The final figure", ARITHMETIC:"The arithmetic" }[d.element] || d.element;
  if (d.kpi) return n + " — " + d.kpi;
  if (d.month) return n + " — " + pbMonthName(String(d.month).slice(0,10));
  return n;
}

function pbClock(d){
  if (d.closedAt) return "closed " + day(d.closedAt);
  if (d.stage === "RAISED") return "they respond by " + day(d.respondDue);
  if (d.stage === "RESPONDED") return "you escalate by " + day(d.escalateDue);
  if (d.stage === "ESCALATED") return "decided by " + day(d.decideDue);
  return "";
}

function pbDisputeActions(d, mine){
  if (d.closedAt) return "";
  var b = [];
  if (mine && d.stage === "RESPONDED")
    b.push('<button class="btn" data-pbesc="' + esc(d.id) + '">Escalate</button>');
  if (mine && d.stage !== "DECIDED")
    b.push('<button class="btn" data-pbwd="' + esc(d.id) + '">Withdraw</button>');
  if (!mine && d.stage === "RAISED")
    b.push('<button class="btn primary" data-pbresp="' + esc(d.id) + '">Respond</button>');
  if (!mine && (d.stage === "ESCALATED" || d.stage === "RAISED"))
    b.push('<button class="btn" data-pbdec="' + esc(d.id) + '">Decide</button>');
  return b.join(" ");
}

/* ------------------------------------------------------- monthly scores */
function pbMonthTable(s){
  var months = pbMonths(s.quarter);
  var by = {};
  (s.months || []).forEach(function(m){ by[String(m.month).slice(0,10)] = m; });

  var rows = months.map(function(mi){
    var m = by[mi];
    if (!m) {
      return '<tr><td><b>' + esc(pbMonthName(mi)) + '</b></td>' +
        '<td colspan="5" class="mute">Not scored yet.</td></tr>';
    }
    if (m.excluded) {
      return '<tr><td><b>' + esc(pbMonthName(mi)) + '</b></td>' +
        '<td colspan="5" class="mute">Excluded — ' + esc(m.excludedWhy || "no score recorded") +
        '. The denominator reduces; you do not carry the omission.</td></tr>';
    }
    return '<tr><td><b>' + esc(pbMonthName(mi)) + '</b>' +
        (m.lockedAt ? '<div class="mute">locked</div>' : '') + '</td>' +
      '<td class="num">' + pbNum(m.kpiPoints, 1) + '</td>' +
      '<td class="num">' + pbNum(m.attrPoints, 1) + '</td>' +
      '<td class="num"><b>' + pbNum(m.monthlyScore, 2) + '</b></td>' +
      '<td class="mute">' + (m.selfKpi === null || m.selfKpi === undefined ? 'not submitted'
        : pbNum(m.selfKpi,1) + ' / ' + pbNum(m.selfAttr,1)) + '</td>' +
      '<td class="mute">' + esc(m.scoredBy || "") +
        (m.gapReason ? '<div class="pbgap">' + esc(m.gapReason) + '</div>' : '') +
        (m.needsCountersign
          ? (m.countersignAt
              ? '<div class="mute">countersigned by ' + esc(m.countersignBy || "") + '</div>'
              : '<div class="pbgap">above 7.5 — awaiting a countersignature</div>')
          : '') + '</td></tr>';
  }).join("");

  return '<div class="card"><h2>Your monthly scores</h2>' +
    '<p class="mute">Monthly score = (0.75 × KPI score) + (0.25 × Attribute score). ' +
    'Scores move in half-point steps against published anchors — a rubric applied, ' +
    'not an opinion formed.</p>' +
    '<div class="scroll"><table>' +
      '<tr><th>Month</th><th>KPI /10</th><th>Attributes /10</th><th>Monthly score</th>' +
      '<th>Your self-evaluation</th><th>Scored by</th></tr>' + rows + '</table></div>' +
    '<h4 class="plh">Submit a self-evaluation</h4>' +
    '<p class="mute">Free, optional, and worth doing: it puts your evidence in front of ' +
    'the assessor before the assessment instead of afterwards in a dispute. It does not ' +
    'bind your manager and is not averaged with their score. Skipping it costs you ' +
    'nothing and does not bar a dispute.</p>' +
    '<div class="plbar">' +
      '<select id="pbsm">' + months.map(function(mi){
        return '<option value="' + esc(mi) + '">' + esc(pbMonthName(mi)) + '</option>';
      }).join("") + '</select> ' +
      '<label>KPIs <input id="pbsk" type="number" min="0" max="10" step="0.5" style="width:80px"></label> ' +
      '<label>Attributes <input id="pbsa" type="number" min="0" max="10" step="0.5" style="width:80px"></label> ' +
      '<button class="btn" id="pbsgo">Submit</button>' +
    '</div><div id="pbselfmsg"></div></div>';
}

/* -------------------------------------------------------------- the result */
function pbResult(s){
  var c = s.calc || {}, r = s.result;
  var have = function(v){ return v !== null && v !== undefined; };
  var twelve = [
    ["Your goal sheet and its targets", (s.kpis||[]).length > 0],
    ["Each KPI's target, actual and ratio", (s.kpis||[]).some(function(k){ return have(k.ratio); })],
    ["The weights", (s.kpis||[]).every(function(k){ return have(k.weight); })],
    ["Achievement (A)", have(c.achievement)],
    ["The Payout Factor P(A)", have(c.payoutFactor)],
    ["Each Monthly Score", (s.months||[]).length > 0],
    ["Your average monthly score", have(c.monthlyMean)],
    ["The Consistency Factor (C)", have(c.consistency)],
    ["Any gate applied to you", true],
    ["Your Applicable Target PLB", have(s.targetPlb)],
    ["The final figure", have(c.amount)],
    ["The arithmetic, in full", !!s.arithmetic]
  ];
  var missing = twelve.filter(function(t){ return !t[1]; }).length;

  return '<div class="card"><h2>Your result</h2>' +
    (r && r.publishedAt
      ? '<p class="plsub">Published ' + esc(when(r.publishedAt)) +
        (r.certifiedBy ? ' · certified by ' + esc(r.certifiedBy) : '') + '</p>'
      : '<p class="plsub">Not yet certified — this is the sum as it stands today</p>') +
    '<div class="counters">' +
      '<div class="counter"><span>Achievement</span><b>' + pbNum(c.achievement, 1) + '%</b></div>' +
      '<div class="counter"><span>Payout factor</span><b>' + pbNum(c.payoutFactor, 1) + '%</b></div>' +
      '<div class="counter"><span>Monthly mean</span><b>' + pbNum(c.monthlyMean, 2) + '</b></div>' +
      '<div class="counter"><span>Consistency</span><b>' + pbNum(c.consistency, 3) + '</b></div>' +
      '<div class="counter pbpay"><span>You are paid</span><b>' + pbMoney(c.amount) + '</b></div>' +
      (Number(s.ringFenced || 0) > 0
        ? '<div class="counter"><span>Ring-fenced</span><b>' + pbMoney(s.ringFenced) + '</b></div>' +
          '<div class="counter pbpay"><span>Payable now</span><b>' + pbMoney(s.payableNow) + '</b></div>'
        : '') +
    '</div>' +
    '<p class="pbsum">' + esc(s.arithmetic || "") + '</p>' +
    '<h4 class="plh">What you must be able to see</h4>' +
    '<p class="mute">Section 6.2 of the scorecard guide. If any of these is missing, ' +
    'you have not been given a published result — say so.</p>' +
    '<ul class="pbcheck">' + twelve.map(function(t){
      return '<li class="' + (t[1] ? "on" : "off") + '">' + esc(t[0]) + '</li>';
    }).join("") + '</ul>' +
    (missing
      ? msg("warn", missing + " of the twelve are not yet present, so this is not a " +
        "published result. It becomes one when the quarter is certified.")
      : "") +
    '<p class="mute">You have ten working days from publication to dispute any element. ' +
    'The undisputed part is still paid on time — nothing is withheld whole. Raising a ' +
    'dispute is not a ground for any adverse consequence.</p>' +
    '</div>';
}

/* ------------------------------------------------------- the manager view */
/* ============================================ whose quarter is mine to run

   "as a manager I am still not able to change the KPIs for quarterly score
    card ... as well as Monthly targets"
   "I can still update and change my own targets, which is wrong. Only my One
    up should be able to do that and no one else."

   Both are the same defect, and it is migration 242's again: this card was
   drawn on `maySetUp` -- who RUNS the scheme, which is HR, Business
   Excellence and an administrator -- rather than on who manages the person
   whose sheet it is. So a manager with a team saw nothing at all, and an
   administrator saw every sheet including their OWN and could set their own
   target.

   plb_quarter has carried the right answer all along: every sheet comes back
   with `maySet`, which is perf_rel(you, them) in ('manage','admin') -- the
   same test the monthly side uses, and the one that answers 'self' for your
   own sheet and 'watch' for your manager's manager. So the screen asks that
   instead. One rule, read in one place.                                   */
function pbMine(){
  return ((PB.q || {}).sheets || []).filter(function(s){ return s.maySet; });
}
function pbMayIssue(p){
  /* The same question for somebody who has no sheet yet. */
  return p.rel === "manage" || p.rel === "admin";
}

function pbManager(){
  var q = PB.q;
  if (!q) return "";
  var mine = pbMine();
  /* Nobody sets their own quarter. perf_rel answers 'self' first, for
     administrators as much as for anybody, so a sheet of your own is simply
     not in `mine` -- and the row below says so where the Open button was. */
  var sheets = (q.sheets || []).filter(function(s){ return s.maySet || s.rel === "self"; });
  var pending = (q.inScheme || []).filter(function(p){ return !p.hasSheet && pbMayIssue(p); });

  var srows = sheets.length ? sheets.map(function(s){
    return '<tr><td><b>' + esc(s.person) + '</b><div class="mute">' +
        esc(s.employeeNo || "no employee number") + ' · ' + esc(s.chair) + '</div></td>' +
      '<td>' + esc((s.status || "").toLowerCase()) +
        (s.acknowledged ? '' : '<div class="mute">not acknowledged</div>') + '</td>' +
      '<td class="num">' + esc(s.monthsScored) + ' of 3</td>' +
      '<td>' + pbWaiting(s) + '</td>' +
      '<td class="num">' + pbMoney(s.targetPlb) + '</td>' +
      '<td class="num">' + (s.published ? pbMoney(s.amount)
        : (s.certified ? pbMoney(s.amount) + '<div class="mute">certified</div>' : '—')) + '</td>' +
      '<td class="plact">' + (s.maySet
        ? '<button class="btn" data-pbopen="' + esc(s.sheetId) + '">Open</button>'
        : '<span class="mute">your own &mdash; your manager&rsquo;s to set</span>') +
      '</td></tr>';
  }).join("") : '<tr><td colspan="7" class="mute">No goal sheet has been issued for this quarter.</td></tr>';

  var prows = pending.length ? pending.map(function(p){
    return '<tr><td><b>' + esc(p.person) + '</b><div class="mute">' +
        esc(p.employeeNo || "no employee number") + '</div></td>' +
      '<td>' + esc(p.chair) + '</td>' +
      '<td class="num">' + esc(p.kpiCount) + ' KPIs at ' +
        pbNum(100 / Number(p.kpiCount), 2) + '% each</td>' +
      '<td class="plact"><button class="btn primary" data-pbissue="' + esc(p.personId) +
        '" data-pbname="' + esc(p.person) + '">Issue a sheet</button></td></tr>';
  }).join("") : '<tr><td colspan="4" class="mute">Everyone in the scheme has a sheet for this quarter.</td></tr>';

  return '<div class="card"><h2>Running the quarter ' +
      '<span class="mute">&middot; ' +
      (mine.length ? mine.length + (mine.length === 1 ? ' sheet' : ' sheets') + ' yours to set'
                   : 'nobody&rsquo;s quarter is yours to set') + '</span></h2>' +
    '<p class="mute">You give your team no KPIs — theirs are designated in the registry, ' +
    'identical for every person in that chair. What you give them is three things: the ' +
    'target, the monthly split, and approval of their two growth attributes. Those three ' +
    'decide the whole result.</p>' +
    '<div id="pbmgrmsg"></div><div id="pbpanel"></div>' +
    '<h4 class="plh">Sheets issued</h4>' +
    '<div class="scroll"><table><tr><th>Who</th><th>Status</th><th>Months scored</th>' +
      '<th>Waiting on you</th><th>Target</th><th>Result</th><th></th></tr>' +
      srows + '</table></div>' +
    '<h4 class="plh">In the scheme, with no sheet yet</h4>' +
    '<div class="scroll"><table><tr><th>Who</th><th>Chair</th><th>Measure set</th><th></th></tr>' +
      prows + '</table></div>' +
    '<p class="mute">If nobody issues a sheet by day 15, the registry default applies and ' +
    'the person cannot be scored below what it produces. Your missing a deadline never ' +
    'costs them.</p></div>';
}

/* What is actually sitting on a manager's desk for this sheet. Three things
   block a quarter and each one is somebody pressing a button, so they are
   named rather than left to be discovered at Score Lock. */
function pbWaiting(s){
  var b = [];
  if (Number(s.attrsPending || 0))
    b.push('<span class="pill warn">' + esc(s.attrsPending) + ' attribute(s) to approve</span>');
  if (Number(s.needsCountersign || 0))
    b.push('<span class="pill warn">' + esc(s.needsCountersign) + ' to countersign</span>');
  if (Number(s.disputesOverdue || 0))
    b.push('<span class="pill bad">' + esc(s.disputesOverdue) + ' dispute(s) overdue</span>');
  else if (Number(s.disputesOpen || 0))
    b.push('<span class="pill">' + esc(s.disputesOpen) + ' dispute(s) open</span>');
  return b.length ? b.join(" ") : '<span class="mute">nothing</span>';
}

/* -------------------------------------------------- one sheet, for a manager */
/* Everything the three decisions need, on one panel. The Constitution says a
   manager selects no KPI and removes none -- those come from the registry --
   so what is editable here is exactly what is theirs: the Target PLB, each
   measure's target, the basis level it was set from, and the monthly split.
   The actual is the quarter-end fact, beside the target it is read against. */
function pbOpenSheet(){
  var s = PB.open;
  if (!s) return "";
  var months = pbMonths(s.quarter);
  var v = function(x){ return x === null || x === undefined ? "" : esc(x); };
  var arows = (s.kpis || []).map(function(k){
    var sp = k.split || [];
    return '<tr><td><b>' + esc(k.name) + '</b><div class="mute">' + esc(k.unit || "") + '</div></td>' +
      '<td class="num">' + pbNum(k.weight, 2) + '%</td>' +
      '<td><input class="pbtg" data-k="' + esc(k.kpiId) + '" type="number" step="0.01" value="' + v(k.target) + '"></td>' +
      '<td><input class="pbbl" data-k="' + esc(k.kpiId) + '" type="number" min="1" max="5" step="1" value="' + v(k.basisLevel) + '"></td>' +
      '<td class="pbsplit">' +
        '<input class="pbm1" data-k="' + esc(k.kpiId) + '" type="number" step="1" value="' + v(sp[0]) + '">' +
        '<input class="pbm2" data-k="' + esc(k.kpiId) + '" type="number" step="1" value="' + v(sp[1]) + '">' +
        '<input class="pbm3" data-k="' + esc(k.kpiId) + '" type="number" step="1" value="' + v(sp[2]) + '"></td>' +
      '<td><input class="pbact" data-k="' + esc(k.kpiId) + '" type="number" step="0.01" value="' + v(k.actual) + '"></td>' +
      '<td class="num">' + (k.ratio === null ? '—' : pbNum(k.ratio, 1) + '%') + '</td></tr>';
  }).join("");

  return '<div class="plform"><h4 class="plh">' + esc(s.person) + ' · ' +
      esc(pbQuarterName(s.quarter)) + '</h4>' +
    '<p class="mute">' + esc(s.chair) + ' · ' + esc((s.status||"").toLowerCase()) +
      (s.lockedAt ? ' · locked ' + esc(when(s.lockedAt)) : '') + '</p>' +
    '<h4 class="plh">The goal sheet — target, basis and split</h4>' +
    '<div class="plbar">' +
      '<label>Target PLB for the quarter <input id="pbtpq" type="number" step="1" min="0" ' +
        'value="' + v(s.targetPlb) + '" style="width:130px"></label>' +
      '<span class="mute">20% of fixed cash salary a year, a quarter of it in play now.</span>' +
    '</div>' +
    '<div class="scroll"><table>' +
      '<tr><th>Measure</th><th>Weight</th><th>Target</th><th>Basis</th>' +
      '<th>Split M1 / M2 / M3</th><th>Actual</th><th>Ratio</th></tr>' + arows + '</table></div>' +
    '<div class="plbar">' +
      '<button class="btn primary" id="pbsavegoal">Save the goal sheet</button>' +
      '<button class="btn" id="pbsaveact">Save actuals only</button>' +
      '<button class="btn" id="pbslock">Lock the sheet</button>' +
      '<span class="mute">Basis is the level the target was set from, 1 to 5. ' +
      'A split must be three numbers adding to 100, or left wholly empty.</span>' +
    '</div>' +
    '<h4 class="plh">Score a month</h4>' +
    '<div class="plbar">' +
      '<select id="pbmm">' + months.map(function(mi){
        return '<option value="' + esc(mi) + '">' + esc(pbMonthName(mi)) + '</option>';
      }).join("") + '</select> ' +
      '<label>KPIs <input id="pbmk" type="number" min="0" max="10" step="0.5" style="width:80px"></label> ' +
      '<label>Attributes <input id="pbma" type="number" min="0" max="10" step="0.5" style="width:80px"></label> ' +
      '<input id="pbmr" placeholder="Reason, if 2.0 or more from the self-evaluation" style="min-width:280px"> ' +
      '<button class="btn" id="pbmgo">Score</button>' +
      '<button class="btn" id="pbmlock">Lock the month</button>' +
    '</div>' +
    pbMgrAttributes(s) +
    pbMgrCountersign(s) +
    '<h4 class="plh">Close the quarter</h4>' +
    '<div class="plbar">' +
      '<button class="btn primary" id="pbcert">Certify</button>' +
      '<button class="btn" id="pbpub">Publish to the employee</button>' +
      '<button class="btn" id="pbclose">Close this panel</button>' +
    '</div>' +
    '<p class="pbsum">' + esc(s.arithmetic || "") + '</p>' +
    '<div id="pbformmsg"></div></div>' +
    pbDisputes(s, false);
}

/* What the employee proposed for A-4 and A-5, and the two buttons. The
   overlap flag is shown here in full: it is the thing the manager is being
   asked to judge, and s.4.3 calls it the most common rejection. */
function pbMgrAttributes(s){
  var open = (s.attributes || []).filter(function(a){ return !a.fixed && a.state === "PROPOSED"; });
  var done = (s.attributes || []).filter(function(a){ return !a.fixed && a.state !== "PROPOSED"; });
  if (!open.length && !done.length) return "";
  var row = function(a, live){
    var ms = (a.milestones || []).filter(function(x){ return x; });
    return '<tr><td><b>' + esc(a.name) + '</b></td>' +
      '<td>' + esc(a.proposal || "—") +
        (a.evidence ? '<div class="mute">Evidence: ' + esc(a.evidence) + '</div>' : '') +
        (ms.length ? '<ol class="pbms">' + ms.map(function(x){
            return '<li>' + esc(x) + '</li>'; }).join("") + '</ol>' : '') +
        (a.overlapNote ? '<div class="pbgap">Overlap against their own measure set — ' +
          esc(a.overlapNote) + '</div>' : '') + '</td>' +
      '<td>' + pbAttrState(a) + '</td>' +
      '<td class="plact">' + (live
        ? '<button class="btn primary" data-pbok="' + esc(a.kpiId) + '">Approve</button> ' +
          '<button class="btn" data-pbno="' + esc(a.kpiId) + '">Return</button>'
        : '') + '</td></tr>';
  };
  return '<h4 class="plh">Their two growth attributes</h4>' +
    '<div class="scroll"><table><tr><th>Attribute</th><th>Proposed</th>' +
      '<th>State</th><th></th></tr>' +
      open.map(function(a){ return row(a, true); }).join("") +
      done.map(function(a){ return row(a, false); }).join("") + '</table></div>' +
    '<div class="plbar"><input id="pbanote" placeholder="Reason, required when returning" ' +
      'style="min-width:380px"></div>';
}

/* 4.5: an attribute score above 7.5 needs a second pair of eyes before the
   month can lock. The button is only offered where it is actually needed. */
function pbMgrCountersign(s){
  var need = (s.months || []).filter(function(m){ return m.needsCountersign && !m.countersignAt; });
  if (!need.length) return "";
  return '<h4 class="plh">Awaiting a countersignature</h4>' +
    '<p class="mute">An attribute score above 7.5 out of 10 is checked, not waved through, ' +
    'and the month cannot lock until somebody other than the scorer has signed.</p>' +
    '<div class="plbar">' + need.map(function(m){
      var mi = String(m.month).slice(0,10);
      return '<button class="btn" data-pbcs="' + esc(mi) + '">' +
        esc(pbMonthName(mi)) + ' · ' + pbNum(m.attrPoints, 1) + '/10</button>';
    }).join(" ") + '</div>';
}

/* The manager's three decisions, read back off the panel in the shape
   plb_sheet_issue expects. A row is sent whether or not it changed: the
   function coalesces a null onto what is already stored, so sending a blank
   never wipes a value somebody else set. */
function pbTargets(){
  var out = [], bad = null;
  Array.prototype.forEach.call(el("view").querySelectorAll(".pbtg"), function(t){
    var k = t.getAttribute("data-k");
    var pick = function(cls){
      var e = el("view").querySelector("." + cls + '[data-k="' + k + '"]');
      return e && e.value !== "" ? Number(e.value) : null;
    };
    var m1 = pick("pbm1"), m2 = pick("pbm2"), m3 = pick("pbm3");
    var set = [m1, m2, m3].filter(function(x){ return x !== null; }).length;
    if (set && set < 3) bad = bad || "A monthly split needs all three months, or none.";
    if (set === 3 && Math.round(m1 + m2 + m3) !== 100) {
      bad = bad || "A monthly split must add to 100. One of these adds to " +
        Math.round(m1 + m2 + m3) + ".";
    }
    out.push({ kpi_id: k, target: t.value === "" ? null : Number(t.value),
      basis: pick("pbbl"), m1: m1, m2: m2, m3: m3 });
  });
  return bad ? { error: bad } : out;
}

/* ------------------------------------------------------------- the render */
function pbRender(){
  var d = PB.data, s = d.sheet;
  var qs = [];
  for (var i = -3; i <= 1; i++) {
    var base = new Date(PB.quarter + "T00:00:00Z");
    base.setUTCMonth(base.getUTCMonth() + i * 3);
    var iso = base.toISOString().slice(0,10);
    qs.push('<option value="' + iso + '"' + (iso === PB.quarter ? ' selected' : '') + '>' +
      pbQuarterName(iso) + '</option>');
  }

  el("view").innerHTML =
    '<div class="page-head"><div><h1>Performance &amp; bonus</h1>' +
    '<p class="mute">Your Performance Linked Bonus, and the whole sum behind it. ' +
    'Everything here is the calculation, not the answer — if explaining a result needs ' +
    'more than this page and your own goal sheet, the scheme has failed its own test.</p>' +
    '</div><div><select id="pbq">' + qs.join("") + '</select></div></div>' +
    '<div id="pbmsg"></div>' +
    pbScheme() +
    (s ? pbOkr(s) + pbGoalSheet(s) + pbMonthTable(s) + pbResult(s) + pbDisputes(s, true)
       : '<div class="card"><h2>Your goal sheet</h2>' +
         (d.inScheme
           ? '<div class="empty">No goal sheet has been issued to you for ' +
             esc(pbQuarterName(PB.quarter)) + ' yet. Your chair is ' + esc(d.chair || "") +
             '. If none reaches you by day 15, your chair\'s standard sheet applies ' +
             'automatically and you cannot be scored below what it produces.</div>'
           : '<div class="empty">' + esc(d.chair
               ? d.chair + ' is not one of the sixteen chairs in the PLB scheme.'
               : 'You are not seated in a chair, so there is no measure set to build a sheet from.') +
             ' The scheme covers Branch Manager level and above; the Board, the Managing ' +
             'Director, Legal &amp; Compliance and business partners are outside it entirely.</div>') +
         '</div>') +
    /* Drawn for anybody who has somebody to run a quarter FOR, not only for
       the people who run the scheme. pbMine() answers that question from the
       payload rather than from a role. */
    (pbMine().length || d.maySetUp ? pbManager() : "");

  if (PB.open && el("pbpanel")) el("pbpanel").innerHTML = pbOpenSheet();
  pbWire();
}

/* ------------------------------------------------------------- the wiring */
async function pbDo(btn, path, body, box){
  if (PB.busy) return null;
  PB.busy = true; if (btn) btn.disabled = true;
  var out = await plb(path, { method:"POST", body: body });
  PB.busy = false; if (btn) btn.disabled = false;
  if (out.error) { pbSay(box || "pbmsg", "bad", out.reason || out.error); return null; }
  pbSay(box || "pbmsg", "ok", out.note || "Done.");
  return out;
}
async function pbReload(){
  PB.q = null;
  if (PB.open) {
    var o = await plb("/plb/sheet/" + PB.open.sheetId);
    PB.open = o && o.sheet ? o.sheet : null;
  }
  await vPlb();
}

function pbWire(){
  var q = el("pbq");
  if (q) q.onchange = async function(){ PB.quarter = q.value; PB.q = null; PB.open = null; await vPlb(); };

  if (el("pback")) el("pback").onclick = async function(){
    if (await pbDo(el("pback"), "/plb/acknowledge",
          { sheetId: PB.data.sheet.sheetId }, "pbackmsg"))
      setTimeout(pbReload, 800);
  };

  if (el("pbsgo")) el("pbsgo").onclick = async function(){
    if (await pbDo(el("pbsgo"), "/plb/self", {
          sheetId: PB.data.sheet.sheetId, month: el("pbsm").value,
          kpi: Number(el("pbsk").value), attr: Number(el("pbsa").value) }, "pbselfmsg"))
      setTimeout(pbReload, 900);
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pbissue]"), function(b){
    b.onclick = function(){ pbIssueForm(b.getAttribute("data-pbissue"), b.getAttribute("data-pbname")); };
  });
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pbopen]"), function(b){
    b.onclick = async function(){
      var o = await plb("/plb/sheet/" + b.getAttribute("data-pbopen"));
      if (o.error) { pbSay("pbmgrmsg", "bad", o.reason || o.error); return; }
      PB.open = o.sheet; pbRender();
    };
  });

  if (el("pbclose")) el("pbclose").onclick = function(){ PB.open = null; pbRender(); };

  /* ---- attributes: the employee proposes, the manager decides ---- */
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pbattr]"), function(b){
    b.onclick = function(){ pbAttrForm(b.getAttribute("data-pbattr")); };
  });
  var decide = function(sel, approve){
    Array.prototype.forEach.call(el("view").querySelectorAll(sel), function(b){
      b.onclick = async function(){
        var note = el("pbanote") ? el("pbanote").value : "";
        if (!approve && !String(note).trim()) {
          pbSay("pbformmsg", "bad", "Returning a proposal says why, so it can be fixed " +
            "rather than guessed at. Put the reason in the box.");
          return;
        }
        if (await pbDo(b, "/plb/attr/decide", {
              sheetId: PB.open.sheetId, kpiId: b.getAttribute(approve ? "data-pbok" : "data-pbno"),
              approve: approve, note: note }, "pbformmsg"))
          setTimeout(pbReload, 900);
      };
    });
  };
  decide("[data-pbok]", true);
  decide("[data-pbno]", false);

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pbcs]"), function(b){
    b.onclick = async function(){
      if (await pbDo(b, "/plb/countersign",
            { sheetId: PB.open.sheetId, month: b.getAttribute("data-pbcs") }, "pbformmsg"))
        setTimeout(pbReload, 900);
    };
  });

  /* ---- disputes ---- */
  if (el("pbdnew")) el("pbdnew").onclick = function(){ pbDisputeForm(); };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pbwd]"), function(b){
    b.onclick = async function(){
      if (!confirm("Withdraw this dispute?\n\nNothing follows from having raised it.")) return;
      if (await pbDo(b, "/plb/dispute/withdraw",
            { disputeId: b.getAttribute("data-pbwd") }, "pbdmsg"))
        setTimeout(pbReload, 900);
    };
  });
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pbesc]"), function(b){
    b.onclick = function(){ pbTextForm("pbdpanel", "Escalate",
      "Say why the response is not accepted. The Functional Head decides in writing.",
      async function(text){
        return await pbDo(b, "/plb/dispute/escalate",
          { disputeId: b.getAttribute("data-pbesc"), why: text }, "pbdmsg");
      }); };
  });
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pbresp]"), function(b){
    b.onclick = function(){ pbTextForm("pbmdpanel", "Respond",
      "In writing, with reasons and evidence. A response that cites no evidence is not a " +
      "response, and the clock keeps running.",
      async function(text){
        return await pbDo(b, "/plb/dispute/respond",
          { disputeId: b.getAttribute("data-pbresp"), response: text }, "pbmdmsg");
      }); };
  });
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pbdec]"), function(b){
    b.onclick = function(){ pbTextForm("pbmdpanel", "Decide",
      "The decision is in writing, with reasons. Nobody who made an earlier decision in " +
      "this matter can decide it again.",
      async function(text, outcome){
        return await pbDo(b, "/plb/dispute/decide",
          { disputeId: b.getAttribute("data-pbdec"), outcome: outcome, decision: text }, "pbmdmsg");
      }, ["UPHELD","PARTLY_UPHELD","REJECTED"]); };
  });

  if (el("pbmgo")) el("pbmgo").onclick = async function(){
    if (await pbDo(el("pbmgo"), "/plb/score", {
          sheetId: PB.open.sheetId, month: el("pbmm").value,
          kpi: Number(el("pbmk").value), attr: Number(el("pbma").value),
          reason: el("pbmr").value }, "pbformmsg"))
      setTimeout(pbReload, 900);
  };
  if (el("pbmlock")) el("pbmlock").onclick = async function(){
    if (!confirm("Lock " + pbMonthName(el("pbmm").value) + " for " + PB.open.person +
      "?\n\nAfter this, changing the score needs a logged correction naming who " +
      "changed it and why.")) return;
    if (await pbDo(el("pbmlock"), "/plb/score/lock",
          { sheetId: PB.open.sheetId, month: el("pbmm").value }, "pbformmsg"))
      setTimeout(pbReload, 900);
  };

  if (el("pbsavegoal")) el("pbsavegoal").onclick = async function(){
    var t = pbTargets();
    if (t.error) { pbSay("pbformmsg", "bad", t.error); return; }
    if (await pbDo(el("pbsavegoal"), "/plb/issue", {
          personId: PB.open.personId, quarter: PB.open.quarter,
          targetPlb: Number(el("pbtpq").value || 0), targets: t }, "pbformmsg"))
      setTimeout(pbReload, 900);
  };
  if (el("pbslock")) el("pbslock").onclick = async function(){
    if (!confirm("Lock " + PB.open.person + "'s goal sheet?\n\nAfter this the KPIs, " +
      "the weights and the targets are frozen for the quarter.")) return;
    if (await pbDo(el("pbslock"), "/plb/lock", { sheetId: PB.open.sheetId }, "pbformmsg"))
      setTimeout(pbReload, 900);
  };

  if (el("pbsaveact")) el("pbsaveact").onclick = async function(){
    var ins = el("view").querySelectorAll(".pbact"), ok = true;
    el("pbsaveact").disabled = true;
    for (var i = 0; i < ins.length; i++) {
      var v = ins[i].value;
      if (v === "") continue;
      var out = await plb("/plb/actual", { method:"POST", body:{
        sheetId: PB.open.sheetId, kpiId: ins[i].getAttribute("data-k"), actual: Number(v) } });
      if (out.error) { pbSay("pbformmsg", "bad", out.reason || out.error); ok = false; break; }
    }
    el("pbsaveact").disabled = false;
    if (ok) { pbSay("pbformmsg", "ok", "Actuals recorded."); setTimeout(pbReload, 900); }
  };

  if (el("pbcert")) el("pbcert").onclick = async function(){
    if (!confirm("Certify " + PB.open.person + "'s quarter?\n\nThis freezes the KPI " +
      "source data. After it, a target cannot change at all.")) return;
    if (await pbDo(el("pbcert"), "/plb/certify", { sheetId: PB.open.sheetId }, "pbformmsg"))
      setTimeout(pbReload, 1100);
  };
  if (el("pbpub")) el("pbpub").onclick = async function(){
    if (await pbDo(el("pbpub"), "/plb/publish", { sheetId: PB.open.sheetId }, "pbformmsg"))
      setTimeout(pbReload, 1100);
  };
}

function pbIssueForm(personId, name){
  el("pbpanel").innerHTML = '<div class="plform">' +
    '<h4 class="plh">Issue a goal sheet to ' + esc(name) + '</h4>' +
    '<p class="mute">The KPIs and their weights come from the registry — you select ' +
    'none and set none. What you set here is the Target PLB for the quarter: 20% of ' +
    'fixed cash salary a year, a quarter of it in play now. Targets and the monthly ' +
    'split are set once the sheet exists.</p>' +
    '<label>Target PLB for this quarter<br>' +
      '<input id="pbtp" type="number" step="1" min="0" placeholder="e.g. 50000"></label> ' +
    '<p><button class="btn primary" id="pbigo">Issue</button> ' +
    '<button class="btn" id="pbicancel">Cancel</button></p><div id="pbformmsg"></div></div>';
  el("pbicancel").onclick = function(){ el("pbpanel").innerHTML = ""; };
  el("pbigo").onclick = async function(){
    if (await pbDo(el("pbigo"), "/plb/issue", {
          personId: personId, quarter: PB.quarter,
          targetPlb: Number(el("pbtp").value || 0) }, "pbformmsg"))
      setTimeout(pbReload, 1100);
  };
}

/* A dispute names one element, the figure believed right, and the evidence.
   The element list is the twelve things s.6.2 says must be visible -- you can
   only dispute something you were shown. */
function pbDisputeForm(){
  var s = PB.data.sheet;
  var kopts = (s.kpis || []).map(function(k){
    return '<option value="' + esc(k.kpiId) + '">' + esc(k.name) + '</option>'; }).join("");
  var mopts = pbMonths(s.quarter).map(function(mi){
    return '<option value="' + esc(mi) + '">' + esc(pbMonthName(mi)) + '</option>'; }).join("");
  el("pbdpanel").innerHTML = '<div class="plform">' +
    '<h4 class="plh">Raise a dispute</h4>' +
    '<div class="plbar">' +
      '<select id="pbdel">' +
        '<option value="ACTUAL">An actual on one measure</option>' +
        '<option value="TARGET">A target on one measure</option>' +
        '<option value="WEIGHT">A weight on one measure</option>' +
        '<option value="MONTH_SCORE">A monthly score</option>' +
        '<option value="ACHIEVEMENT">Achievement</option>' +
        '<option value="PAYOUT_FACTOR">The payout factor</option>' +
        '<option value="MONTHLY_MEAN">The monthly mean</option>' +
        '<option value="CONSISTENCY">The consistency factor</option>' +
        '<option value="GATE">A gate applied to me</option>' +
        '<option value="TARGET_PLB">My target PLB</option>' +
        '<option value="AMOUNT">The final figure</option>' +
        '<option value="ARITHMETIC">The arithmetic</option>' +
      '</select>' +
      '<select id="pbdk">' + kopts + '</select>' +
      '<select id="pbdm" style="display:none">' + mopts + '</select>' +
      '<label>The figure you say is right <input id="pbdv" type="number" step="0.01" style="width:120px"></label>' +
    '</div>' +
    '<label>What you believe is right, and why<br>' +
      '<input id="pbdc" style="min-width:460px"></label>' +
    '<label>Your evidence<br><input id="pbde" style="min-width:460px"></label>' +
    '<p class="mute">Where the claim is an actual or a target on one measure, the tool works ' +
    'out what it is worth and ring-fences exactly that. The rest is paid on time.</p>' +
    '<p><button class="btn primary" id="pbdgo">Raise it</button> ' +
    '<button class="btn" id="pbdcancel">Cancel</button></p></div>';

  var sync = function(){
    var v = el("pbdel").value;
    el("pbdk").style.display = (v === "ACTUAL" || v === "TARGET" || v === "WEIGHT") ? "" : "none";
    el("pbdm").style.display = (v === "MONTH_SCORE") ? "" : "none";
  };
  el("pbdel").onchange = sync; sync();
  el("pbdcancel").onclick = function(){ el("pbdpanel").innerHTML = ""; };
  el("pbdgo").onclick = async function(){
    var v = el("pbdel").value;
    if (await pbDo(el("pbdgo"), "/plb/dispute", {
          sheetId: s.sheetId, element: v,
          kpiId: (v === "ACTUAL" || v === "TARGET" || v === "WEIGHT") ? el("pbdk").value : null,
          month: v === "MONTH_SCORE" ? el("pbdm").value : null,
          claimed: el("pbdc").value,
          claimedValue: el("pbdv").value === "" ? null : Number(el("pbdv").value),
          evidence: el("pbde").value }, "pbdmsg"))
      setTimeout(pbReload, 1000);
  };
}

/* One box, one button, and where a decision is being made, the outcome
   beside it. Used for responding, escalating and deciding, because all
   three are the same shape: writing, with reasons. */
function pbTextForm(into, title, help, send, outcomes){
  el(into).innerHTML = '<div class="plform">' +
    '<h4 class="plh">' + esc(title) + '</h4>' +
    '<p class="mute">' + esc(help) + '</p>' +
    (outcomes ? '<div class="plbar"><select id="pbtout">' + outcomes.map(function(o){
        return '<option value="' + esc(o) + '">' + esc(o.toLowerCase().replace(/_/g," ")) +
          '</option>'; }).join("") + '</select></div>' : '') +
    '<label>In writing<br><input id="pbtt" style="min-width:520px"></label>' +
    '<p><button class="btn primary" id="pbtgo">' + esc(title) + '</button> ' +
    '<button class="btn" id="pbtcancel">Cancel</button></p></div>';
  el("pbtcancel").onclick = function(){ el(into).innerHTML = ""; };
  el("pbtgo").onclick = async function(){
    if (await send(el("pbtt").value, el("pbtout") ? el("pbtout").value : null))
      setTimeout(pbReload, 1000);
  };
}
