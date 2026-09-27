/* ================================================================== perf
   The monthly cycle: what I am measured on, what I owe today, and — if
   anybody reports to me — what my team is doing about theirs.

   One screen, two faces, because they are the same thing seen from either
   end. A branch manager files their own numbers AND sets their team's; a
   field executive only ever does the first. The second face appears when
   the database says somebody reports to you, not when a role says you are
   a manager — those are different questions and only one of them is true
   about a particular Tuesday.

   Nothing here computes a number. Every value on this screen comes from
   perf_value() through perf_tree(), which owns the one rule that makes a
   roll-up correct: counts and rupees accumulate, a percentage or a score
   is a level. A second opinion about somebody's performance is the last
   thing a screen should hold.                                          */
var PF = { period:null, cycle:null, tab:"mine", tree:null, due:null, team:null,
           who:null, open:{}, measures:null, measuresFor:null, form:null,
           sel:{}, busy:false, says:"" };

function pfMonth(d){ d = d || new Date();
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1)).toISOString().slice(0,10); }

function pfMonthName(s){
  var d = new Date(s + "T00:00:00Z");
  return d.toLocaleString("en-GB", { month:"long", year:"numeric", timeZone:"UTC" });
}

function pfNum(v, unit){
  if (v === null || v === undefined || v === "") return "—";
  var n = Number(v);
  if (!isFinite(n)) return esc(v);
  var s = Math.abs(n) >= 1000 ? n.toLocaleString("en-IN") : String(Math.round(n * 100) / 100);
  return esc(s) + (unit ? ' <span class="mute">' + esc(unit) + '</span>' : '');
}

/* A bar is a claim about proportion, so it stops at 100 even when the
   number does not -- and the figure beside it still says 143%. */
function pfBar(pct){
  if (pct === null || pct === undefined) return '';
  var w = Math.max(0, Math.min(100, Number(pct)));
  var tone = pct >= 95 ? "ok" : pct >= 75 ? "warn" : "bad";
  return '<div class="pfbar"><i class="' + tone + '" style="width:' + w + '%"></i></div>';
}

/* A screen is published from one place and its service is deployed from
   another, and the two do not always land in the same minute. When the
   routes are not there yet the gateway answers no_route, and this screen
   says that rather than inventing a reason of its own -- "the period has
   not been opened" would send somebody looking for HR about a deploy. */
function pfMissing(r){
  return !!r && (r.error === "no_route" || r._status === 404);
}

/* --------------------------------------------------------------- the shell */
async function vPerf(){
  if (!PF.period) PF.period = pfMonth();
  var c = await plb("/plb/perf/cycle?period=" + PF.period);
  if (pfMissing(c)) {
    el("view").innerHTML = '<h1>Performance</h1>' +
      msg("warn", "This screen is published but the service behind it is not " +
        "deployed yet, so there is nothing to show. Nothing is wrong with your " +
        "account and nothing has been lost. Appraisal and Bonus, above, still work.");
    return;
  }
  PF.cycle = c.cycle || null;
  PF.mayOpen = !!c.mayOpen;
  if (!PF.team) {
    var t = await plb("/plb/perf/team");
    PF.team = t.error ? [] : (t.people || []);
  }
  await pfLoadMine();
  pfRender();
}

async function pfLoadMine(){
  if (!PF.cycle) { PF.tree = null; PF.due = null; return; }
  var r = await Promise.all([
    plb("/plb/perf/tree?cycle=" + PF.cycle.id),
    plb("/plb/perf/due"),
  ]);
  PF.tree = r[0]; PF.due = (r[1] || {}).due || [];
}

function pfRender(){
  var head = '<div class="page-head"><div><h1>Performance</h1>' +
    '<p class="mute">What you are measured on this period, what you owe today, and ' +
    'where your numbers land once they have climbed.</p></div>' +
    '<div class="pfperiod">' + pfPeriodPicker() + '</div></div>';

  if (!PF.cycle) {
    el("view").innerHTML = head +
      '<div class="card"><h2>' + esc(pfMonthName(PF.period)) + ' has not been opened</h2>' +
      '<p class="mute">A period has to be opened before anybody can be given a KPI for it. ' +
      'Opening it sets two dates: the last day a manager may set targets, and the last day ' +
      'numbers may still be filed.</p>' +
      (PF.mayOpen
        ? '<p><button class="btn primary" id="pfopen">Open ' + esc(pfMonthName(PF.period)) + '</button></p>'
        : '<div class="empty">HR, Business Excellence or an administrator opens a period.</div>') +
      '<div id="pfmsg">' + PF.says + '</div></div>';
    pfWire();
    return;
  }

  var tabs = '<div class="pftabs">' +
    '<button class="btn' + (PF.tab === "mine" ? " primary" : "") + '" data-pftab="mine">Mine</button>' +
    (PF.team.length
      ? '<button class="btn' + (PF.tab === "team" ? " primary" : "") + '" data-pftab="team">' +
        'My team <span class="chip">' + esc(PF.team.length) + '</span></button>'
      : '') +
    '</div>';

  el("view").innerHTML = head + pfWindowBanner() + tabs +
    (PF.tab === "team" ? pfTeam() : pfMine()) +
    '<div id="pfmsg">' + PF.says + '</div>';
  pfWire();
}

function pfPeriodPicker(){
  var opts = "";
  for (var i = 0; i < 12; i++) {
    var d = new Date(); d.setUTCDate(1); d.setUTCMonth(d.getUTCMonth() - i);
    var v = pfMonth(d);
    opts += '<option value="' + v + '"' + (v === PF.period ? ' selected' : '') + '>' +
      esc(pfMonthName(v)) + '</option>';
  }
  return '<select id="pfperiod">' + opts + '</select>';
}

function pfWindowBanner(){
  var c = PF.cycle;
  var bits = [];
  bits.push(c.assign_open
    ? 'KPIs may be set until <b>' + day(c.assign_closes) + '</b>'
    : 'The window for setting KPIs closed on ' + day(c.assign_closes));
  bits.push(c.entry_open
    ? 'numbers may be filed until <b>' + day(c.entry_closes) + '</b>'
    : 'filing closed on ' + day(c.entry_closes));
  return '<div class="pfwin' + (c.entry_open ? '' : ' shut') + '">' +
    bits.join(' · ') + '</div>';
}

/* ------------------------------------------------------------------ mine */
function pfMine(){
  var t = PF.tree || {};
  if (t.says) {
    return '<div class="card"><h2>' + esc(pfMonthName(PF.period)) + '</h2>' +
      '<div class="empty">' + esc(t.says) + '</div></div>';
  }
  var measures = t.measures || [];
  return pfDueCard() +
    '<div class="card"><h2>What you are measured on</h2>' +
    (measures.length
      ? '<div class="pftree">' + measures.map(function(m){ return pfNode(m, 0, false); }).join("") + '</div>'
      : '<div class="empty">Nothing has been set for you this period.</div>') +
    '</div>';
}

function pfDueCard(){
  var due = PF.due || [];
  if (!PF.cycle.entry_open) return "";
  if (!due.length) {
    return '<div class="card"><h2>Due today</h2>' +
      '<div class="empty">Nothing is due from you today. What you file and when is set ' +
      'with your KPI, not by this screen.</div></div>';
  }
  var rows = due.map(function(d){
    return '<tr><td><b>' + esc(d.name) + '</b>' +
      (d.split ? ' <span class="mute">' + esc(d.split) + '</span>' : '') +
      '<div class="mute">' + esc(String(d.cadence || "").toLowerCase().replace(/_/g," ")) +
      (d.target ? ' · target ' + pfNum(d.target, d.unit) : '') + '</div></td>' +
      '<td><input class="pfin" data-pffile="' + esc(d.assignmentId) + '" type="number" step="any" ' +
        'placeholder="' + (d.alreadyFiled ? 'filed — change it' : 'today’s number') + '"></td>' +
      '<td class="plact"><button class="btn" data-pffileb="' + esc(d.assignmentId) + '">' +
        (d.alreadyFiled ? 'Change' : 'File') + '</button></td></tr>';
  }).join("");
  return '<div class="card"><h2>Due today</h2>' +
    '<p class="mute">The number is for today. Filing it tomorrow does not make it ' +
    'tomorrow’s number.</p>' +
    '<div class="scroll"><table>' + rows + '</table></div></div>';
}

/* One node, and its parts and its team under it. Depth is only indentation;
   the shape comes from the database. */
function pfNode(m, depth, isTeam){
  var id = m.assignmentId;
  var kids = (m.parts || []).length + (m.team || []).length;
  var isOpen = !!PF.open[id];
  var who = m.person
    ? '<span class="pfwho">' + esc(m.person.name) +
      (m.person.chair ? ' <span class="mute">' + esc(m.person.chair) + '</span>' : '') + '</span>'
    : '';

  var head = '<div class="pfrow" style="padding-left:' + (depth * 18) + 'px">' +
    (kids
      ? '<button class="pftog" data-pfopen="' + esc(id) + '">' + (isOpen ? '−' : '+') + '</button>'
      : '<span class="pftog pfnone"></span>') +
    '<span class="pfname">' + (isTeam ? who : esc(m.split || m.name)) +
      (isTeam ? '' : (m.splitKind ? ' <span class="chip">' + esc(m.splitKind.toLowerCase()) + '</span>' : '')) +
    '</span>' +
    '<span class="pfval">' + pfNum(m.value, m.unit) + '</span>' +
    '<span class="pftgt">' + (m.target ? 'of ' + pfNum(m.target) : '<span class="mute">no target</span>') + '</span>' +
    '<span class="pfpct">' + (m.pct === null || m.pct === undefined ? '' : esc(m.pct) + '%') + '</span>' +
    '<span class="pfmeter">' + pfBar(m.pct) + '</span>' +
    '</div>';

  var body = "";
  if (isOpen) {
    body = (m.parts || []).map(function(p){ return pfNode(p, depth + 1, false); }).join("") +
           (m.team  || []).map(function(p){ return pfNode(p, depth + 1, true);  }).join("");
  }
  return head + body;
}

/* ------------------------------------------------------------------ team */
function pfTeam(){
  var rows = PF.team.map(function(p){
    var open = PF.who === p.personId;
    return '<tr><td><b>' + esc(p.name) + '</b>' +
      (p.employeeNo ? ' <span class="mute">' + esc(p.employeeNo) + '</span>' : '') +
      '<div class="mute">' + esc(p.chair || "no chair") + '</div></td>' +
      '<td class="plact">' +
        '<label class="pfsel"><input type="checkbox" data-pfsel="' + esc(p.personId) + '"' +
          (PF.sel[p.personId] ? ' checked' : '') + '> select</label>' +
        '<button class="btn" data-pfwho="' + esc(p.personId) + '">' +
          (open ? 'Hide' : 'Open') + '</button></td></tr>' +
      (open ? '<tr><td colspan="2">' + pfPersonPanel() + '</td></tr>' : '');
  }).join("");

  var n = Object.keys(PF.sel).filter(function(k){ return PF.sel[k]; }).length;

  return '<div class="card"><h2>Setting your team’s KPIs</h2>' +
    '<p class="mute">A KPI you give somebody climbs into one of yours. Pick which one ' +
    'as you set it — that link is what makes the numbers add up to a branch, and a ' +
    'branch to a zone.</p>' +
    '<div class="plbar">' +
      '<button class="btn primary" id="pfbulk"' + (n ? '' : ' disabled') + '>' +
        (n ? 'Give the same KPIs to ' + n + ' selected' : 'Select people to assign in bulk') + '</button>' +
      '<button class="btn" id="pfcarry"' + (n ? '' : ' disabled') + '>Carry last month forward</button>' +
    '</div>' +
    '<div class="scroll"><table>' + rows + '</table></div>' +
    (PF.form ? pfForm() : '') +
    '</div>';
}

function pfPersonPanel(){
  var t = PF.whoTree;
  if (!t) return '<p class="mute">Loading…</p>';
  if (t.error) return msg("bad", t.reason || t.error);
  var ms = t.measures || [];
  return '<div class="pfpanel">' +
    (ms.length
      ? '<div class="pftree">' + ms.map(function(m){ return pfNode(m, 0, false); }).join("") + '</div>'
      : '<div class="empty">' + esc(t.says || "Nothing set for them this period.") + '</div>') +
    '<p><button class="btn" id="pfadd">Set a KPI for ' + esc(t.person.name) + '</button></p>' +
    '</div>';
}

/* ------------------------------------------------------------ the form */
function pfForm(){
  var f = PF.form, cat = (PF.measures || {}).catalogue || [], mine = (PF.measures || {}).mine || [];
  if (!PF.measures) return '<div class="plform"><p class="mute">Loading the measures…</p></div>';

  var cads = {};
  cat.forEach(function(k){ if (k.cadence) cads[k.cadence] = 1; });
  var cadOpts = Object.keys(cads).sort().map(function(c){
    return '<option value="' + esc(c) + '"' + (f.cadence === c ? ' selected' : '') + '>' +
      esc(c.toLowerCase().replace(/_/g, " ")) + '</option>'; }).join("");

  return '<div class="plform">' +
    '<h4 class="plh">' + (f.bulk ? 'The same KPI for everyone selected' : 'A KPI for ' + esc(f.name)) + '</h4>' +
    '<div class="hragrid">' +
      '<label class="hrafield"><span>Measure</span><select data-pff="kpiId">' +
        '<option value="">— choose —</option>' +
        cat.map(function(k){
          return '<option value="' + esc(k.id) + '"' + (f.kpiId === k.id ? ' selected' : '') + '>' +
            esc(k.name) + (k.unit ? ' (' + esc(k.unit) + ')' : '') + '</option>'; }).join("") +
      '</select></label>' +
      '<label class="hrafield"><span>Target</span>' +
        '<input data-pff="target" type="number" step="any" value="' + esc(f.target || "") + '"></label>' +
      '<label class="hrafield"><span>Weight %</span>' +
        '<input data-pff="weight" type="number" step="any" value="' + esc(f.weight || "") + '"></label>' +
      '<label class="hrafield"><span>They file</span><select data-pff="cadence">' +
        '<option value="">— as the measure says —</option>' + cadOpts + '</select></label>' +
      '<label class="hrafield"><span>On which day</span>' +
        '<input data-pff="cadenceDay" type="number" min="1" max="28" ' +
        'placeholder="10 for the 10th, 5 for Friday" value="' + esc(f.cadenceDay || "") + '"></label>' +
      '<label class="hrafield"><span>Climbs into</span><select data-pff="rollsInto">' +
        '<option value="">— nothing yet —</option>' +
        mine.map(function(m){
          return '<option value="' + esc(m.assignmentId) + '"' +
            (f.rollsInto === m.assignmentId ? ' selected' : '') + '>' +
            esc(m.name) + (m.split ? ' · ' + esc(m.split) : '') + '</option>'; }).join("") +
      '</select></label>' +
    '</div>' +
    (PF.measures.note ? '<div class="plsub">' + msg("warn", PF.measures.note) + '</div>' : '') +
    '<p class="mute">A measure with no target is not scored and does not drag the average ' +
    'down — it is left out and says so. Leave it blank if you genuinely have not set one ' +
    'yet, rather than putting a nought in.</p>' +
    '<div class="plbar">' +
      '<button class="btn primary" id="pfsave">' +
        (f.bulk ? 'Give it to everyone selected' : 'Set it') + '</button>' +
      '<button class="btn" id="pfcancel">Cancel</button>' +
    '</div></div>';
}

/* The catalogue a manager picks from. Asked for one person, it comes back
   as that chair's measure set rather than as every measure in the company,
   which is the difference between choosing and searching. Cached per
   person, because the one thing worse than a long list is a long list that
   is fetched again every time the form is drawn. */
async function pfMeasuresFor(personId){
  var key = personId || "all";
  if (PF.measuresFor === key && PF.measures) return;
  PF.measures = null; PF.measuresFor = key; pfRender();
  var q = "/plb/perf/measures?cycle=" + PF.cycle.id +
          (personId ? "&person=" + encodeURIComponent(personId) : "");
  var m = await plb(q);
  /* A second click while the first was in flight wins; this one is stale. */
  if (PF.measuresFor !== key) return;
  PF.measures = m;
  pfRender();
}

/* ---------------------------------------------------------------- wiring */
function pfWire(){
  if (el("pfperiod")) el("pfperiod").onchange = async function(){
    PF.period = el("pfperiod").value; PF.tree = null; PF.who = null;
    PF.whoTree = null; PF.says = ""; PF.measures = null; PF.measuresFor = null;
    el("view").innerHTML = '<p class="mute">Loading…</p>';
    await vPerf();
  };

  if (el("pfopen")) el("pfopen").onclick = async function(){
    var o = await plb("/plb/perf/cycle/open", { method:"POST", body:{ period: PF.period } });
    PF.says = o.error ? msg("bad", o.reason || o.error) : msg("ok", o.note);
    await vPerf();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pftab]"), function(b){
    b.onclick = function(){ PF.tab = b.getAttribute("data-pftab"); pfRender(); };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pfopen]"), function(b){
    b.onclick = function(){
      var k = b.getAttribute("data-pfopen");
      PF.open[k] = !PF.open[k];
      pfRender();
    };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pfsel]"), function(b){
    b.onchange = function(){ PF.sel[b.getAttribute("data-pfsel")] = b.checked; pfRender(); };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pfwho]"), function(b){
    b.onclick = async function(){
      var id = b.getAttribute("data-pfwho");
      if (PF.who === id) { PF.who = null; PF.whoTree = null; PF.form = null; pfRender(); return; }
      PF.who = id; PF.whoTree = null; PF.form = null; pfRender();
      PF.whoTree = await plb("/plb/perf/tree?cycle=" + PF.cycle.id + "&person=" + id);
      pfRender();
    };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pffileb]"), function(b){
    b.onclick = async function(){
      if (PF.busy) return;
      var id = b.getAttribute("data-pffileb");
      var box = el("view").querySelector('[data-pffile="' + id + '"]');
      if (!box || box.value === "") return;
      PF.busy = true; b.disabled = true;
      var o = await plb("/plb/perf/file", { method:"POST", body:{
        assignmentId: id, asOf: new Date().toISOString().slice(0,10), value: box.value } });
      PF.busy = false;
      PF.says = o.error ? msg("bad", o.reason || o.error) : msg("ok", o.note);
      await pfLoadMine(); pfRender();
    };
  });

  if (el("pfadd")) el("pfadd").onclick = async function(){
    PF.form = { personId: PF.who, name: (PF.whoTree.person || {}).name, bulk:false };
    pfRender();
    await pfMeasuresFor(PF.who);
  };

  if (el("pfbulk")) el("pfbulk").onclick = async function(){
    PF.form = { bulk:true };
    pfRender();
    /* No one person, so no one chair: the whole catalogue, which is the
       honest answer when the same measure is going to several chairs. */
    await pfMeasuresFor(null);
  };

  if (el("pfcarry")) el("pfcarry").onclick = async function(){
    var who = Object.keys(PF.sel).filter(function(k){ return PF.sel[k]; });
    var done = 0, said = [];
    for (var i = 0; i < who.length; i++) {
      var o = await plb("/plb/perf/carry", { method:"POST",
        body:{ cycleId: PF.cycle.id, personId: who[i] } });
      if (o.error) said.push(o.reason || o.error); else done += (o.copied || 0);
    }
    PF.says = said.length ? msg("bad", said.join(" "))
                          : msg("ok", done + " measure(s) carried forward. The targets are blank " +
                                "on purpose — last month’s number is not this month’s promise.");
    PF.whoTree = null; pfRender();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pff]"), function(f){
    f.onchange = function(){ PF.form[f.getAttribute("data-pff")] = f.value; };
  });

  if (el("pfcancel")) el("pfcancel").onclick = function(){ PF.form = null; pfRender(); };

  if (el("pfsave")) el("pfsave").onclick = async function(){
    if (PF.busy) return;
    var f = PF.form;
    if (!f.kpiId) { PF.says = msg("bad", "Choose a measure first."); pfRender(); return; }
    PF.busy = true; el("pfsave").disabled = true;
    var body = { cycleId: PF.cycle.id, kpiId: f.kpiId, target: f.target,
                 weight: f.weight, cadence: f.cadence, cadenceDay: f.cadenceDay,
                 rollsInto: f.rollsInto };
    var o;
    if (f.bulk) {
      o = await plb("/plb/perf/assign/bulk", { method:"POST", body:{
        cycleId: PF.cycle.id,
        people: Object.keys(PF.sel).filter(function(k){ return PF.sel[k]; }),
        measures: [body] } });
    } else {
      body.personId = f.personId;
      o = await plb("/plb/perf/assign", { method:"POST", body: body });
    }
    PF.busy = false;
    PF.says = o.error ? msg("bad", o.reason || o.error) : msg("ok", o.note || "Set.");
    PF.form = null; PF.whoTree = null; PF.measures = null; PF.measuresFor = null;
    if (PF.who) PF.whoTree = await plb("/plb/perf/tree?cycle=" + PF.cycle.id + "&person=" + PF.who);
    pfRender();
  };
}
