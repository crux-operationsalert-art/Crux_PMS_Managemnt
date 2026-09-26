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
  if (d.maySetUp && !PB.q) PB.q = await plb("/plb/quarter?quarter=" + PB.quarter);
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
    return '<tr><td><b>' + esc(a.name) + '</b><div class="mute">' + esc(a.unit || "") + '</div></td>' +
      '<td>' + (a.fixed
        ? '<span class="pill">same for everyone</span>'
        : (a.proposal ? esc(a.proposal)
                      : '<span class="pill warn">you propose this</span>')) + '</td></tr>';
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
    '<div class="scroll"><table><tr><th>Attribute</th><th>What it is</th></tr>' +
      arows + '</table></div>' +
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
        (m.gapReason ? '<div class="pbgap">' + esc(m.gapReason) + '</div>' : '') + '</td></tr>';
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
function pbManager(){
  var q = PB.q;
  if (!q) return "";
  var sheets = q.sheets || [], pending = (q.inScheme || []).filter(function(p){ return !p.hasSheet; });

  var srows = sheets.length ? sheets.map(function(s){
    return '<tr><td><b>' + esc(s.person) + '</b><div class="mute">' +
        esc(s.employeeNo || "no employee number") + ' · ' + esc(s.chair) + '</div></td>' +
      '<td>' + esc((s.status || "").toLowerCase()) +
        (s.acknowledged ? '' : '<div class="mute">not acknowledged</div>') + '</td>' +
      '<td class="num">' + esc(s.monthsScored) + ' of 3</td>' +
      '<td class="num">' + pbMoney(s.targetPlb) + '</td>' +
      '<td class="num">' + (s.published ? pbMoney(s.amount)
        : (s.certified ? pbMoney(s.amount) + '<div class="mute">certified</div>' : '—')) + '</td>' +
      '<td class="plact"><button class="btn" data-pbopen="' + esc(s.sheetId) + '">Open</button></td></tr>';
  }).join("") : '<tr><td colspan="6" class="mute">No goal sheet has been issued for this quarter.</td></tr>';

  var prows = pending.length ? pending.map(function(p){
    return '<tr><td><b>' + esc(p.person) + '</b><div class="mute">' +
        esc(p.employeeNo || "no employee number") + '</div></td>' +
      '<td>' + esc(p.chair) + '</td>' +
      '<td class="num">' + esc(p.kpiCount) + ' KPIs at ' +
        pbNum(100 / Number(p.kpiCount), 2) + '% each</td>' +
      '<td class="plact"><button class="btn primary" data-pbissue="' + esc(p.personId) +
        '" data-pbname="' + esc(p.person) + '">Issue a sheet</button></td></tr>';
  }).join("") : '<tr><td colspan="4" class="mute">Everyone in the scheme has a sheet for this quarter.</td></tr>';

  return '<div class="card"><h2>Running the quarter</h2>' +
    '<p class="mute">You give your team no KPIs — theirs are designated in the registry, ' +
    'identical for every person in that chair. What you give them is three things: the ' +
    'target, the monthly split, and approval of their two growth attributes. Those three ' +
    'decide the whole result.</p>' +
    '<div id="pbmgrmsg"></div><div id="pbpanel"></div>' +
    '<h4 class="plh">Sheets issued</h4>' +
    '<div class="scroll"><table><tr><th>Who</th><th>Status</th><th>Months scored</th>' +
      '<th>Target</th><th>Result</th><th></th></tr>' + srows + '</table></div>' +
    '<h4 class="plh">In the scheme, with no sheet yet</h4>' +
    '<div class="scroll"><table><tr><th>Who</th><th>Chair</th><th>Measure set</th><th></th></tr>' +
      prows + '</table></div>' +
    '<p class="mute">If nobody issues a sheet by day 15, the registry default applies and ' +
    'the person cannot be scored below what it produces. Your missing a deadline never ' +
    'costs them.</p></div>';
}

/* -------------------------------------------------- one sheet, for a manager */
function pbOpenSheet(){
  var s = PB.open;
  if (!s) return "";
  var months = pbMonths(s.quarter);
  var arows = (s.kpis || []).map(function(k){
    return '<tr><td><b>' + esc(k.name) + '</b></td>' +
      '<td class="num">' + pbNum(k.target) + '</td>' +
      '<td><input class="pbact" data-k="' + esc(k.kpiId) + '" type="number" step="0.01" ' +
        'value="' + (k.actual === null || k.actual === undefined ? '' : esc(k.actual)) +
        '" style="width:110px"></td></tr>';
  }).join("");

  return '<div class="plform"><h4 class="plh">' + esc(s.person) + ' · ' +
      esc(pbQuarterName(s.quarter)) + '</h4>' +
    '<p class="mute">' + esc(s.chair) + ' · ' + esc((s.status||"").toLowerCase()) +
      ' · target ' + pbMoney(s.targetPlb) + '</p>' +
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
    '<h4 class="plh">Quarter-end actuals</h4>' +
    '<div class="scroll"><table><tr><th>Measure</th><th>Target</th><th>Actual</th></tr>' +
      arows + '</table></div>' +
    '<div class="plbar">' +
      '<button class="btn" id="pbsaveact">Save actuals</button>' +
      '<button class="btn primary" id="pbcert">Certify the quarter</button>' +
      '<button class="btn" id="pbpub">Publish to the employee</button>' +
      '<button class="btn" id="pbclose">Close</button>' +
    '</div>' +
    '<p class="pbsum">' + esc(s.arithmetic || "") + '</p>' +
    '<div id="pbformmsg"></div></div>';
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
    (s ? pbGoalSheet(s) + pbMonthTable(s) + pbResult(s)
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
    (d.maySetUp ? pbManager() : "");

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

  if (el("pbsaveact")) el("pbsaveact").onclick = async function(){
    var ins = el("view").querySelectorAll(".pbact"), ok = true;
    for (var i = 0; i < ins.length; i++) {
      var v = ins[i].value;
      if (v === "") continue;
      var out = await plb("/plb/actual", { method:"POST", body:{
        sheetId: PB.open.sheetId, kpiId: ins[i].getAttribute("data-k"), actual: Number(v) } });
      if (out.error) { pbSay("pbformmsg", "bad", out.reason || out.error); ok = false; break; }
    }
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
