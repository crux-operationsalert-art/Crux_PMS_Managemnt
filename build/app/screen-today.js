/* =====================================================================
   The dashboard.

   The reference the owner gave is cruxindia/crux-console, and what makes
   that page work is not its colours. It is the order:

     a row of stat tiles, each one number with a coloured edge and a
     one-line qualifier under it;
     then a wide panel of detail beside a narrow one that summarises it;
     then the things waiting to be done.

   Every figure is a number somebody filed, shown at the size of its
   importance, and nothing on the page is a paragraph.

   This takes that order and draws it in THIS tool's tokens -- green,
   gold, terra, blue, ink -- rather than importing the console's navy. The
   console also inlines 200KB of Chart.js; this does not. A doughnut of
   three states and a row of progress bars are two arcs and a div each,
   and a charting library is not worth a third of the page weight to draw
   them.

   WHAT IT SHOWS, and why in this order. The old dashboard led with
   escalations and OGL -- other people's work arriving. The scheme the
   company is about to run on is measured monthly and paid quarterly, so
   the first thing a person needs on opening the tool is whether they have
   filed today and whether they are on track. The operational counts keep
   their place, lower down, where they were.
   ===================================================================== */

var TD = { data:null, err:null };

/* ------------------------------------------------------------ numbers */
function tdNum(v, dp){
  if (v === null || v === undefined || v === "") return "—";
  var n = Number(v);
  if (!isFinite(n)) return "—";
  return n.toLocaleString("en-IN", {
    minimumFractionDigits: dp || 0, maximumFractionDigits: dp === undefined ? 0 : dp });
}

/* The one rule the whole page colours by: a measure is on target, part of
   the way there, or behind. Said once so the tile, the bar, the doughnut
   and the legend cannot disagree about one measure. */
function tdState(pct){
  if (pct === null || pct === undefined) return "none";
  if (pct >= 100) return "ok";
  if (pct >= 70)  return "part";
  return "behind";
}
var TD_WORD  = { ok:"on target", part:"part of the way", behind:"behind", none:"no target set" };

/* The three states wear three colours, and those colours are NOT the
   tool's --green/--gold/--terra.

   Those three were tried first and fail the only test that matters for a
   doughnut: --gold #8a6d1f and --terra #b4562f are 9.6 apart to a reader
   with full colour vision and 1.8 apart to a reader with deuteranopia,
   which is to say the middle segment and the behind segment are one
   segment. The tool's palette is deliberately muted and no three steps of
   it separate; these are stepped out until they do -- 30.3 and 24.7 on the
   worst adjacent pair.
   
   The light middle step sits below 3:1 against the panel, so it is never
   the only thing saying what a figure means: the legend carries the words
   and the counts, and the table under it carries every measure by name
   with its own percentage. */
var TD_TOKEN = { ok:"ok", part:"part", behind:"behind", none:"none" };

/* ---------------------------------------------------------- the tiles */
function tdTile(label, value, sub, token){
  return '<div class="tdk tdk-' + esc(token || "none") + '">' +
    '<span class="edge" aria-hidden="true"></span>' +
    '<div class="k">' + esc(label) + '</div>' +
    '<div class="v">' + value + '</div>' +
    '<div class="s">' + esc(sub || "") + '</div></div>';
}

/* A bar that stops at its own track however large the number is, and
   carries the figure beside it rather than inside it -- a number printed
   on a coloured fill is a number somebody cannot read at 60%. */
function tdBar(pct, token){
  var w = pct === null || pct === undefined ? 0 : Math.max(0, Math.min(100, pct));
  return '<div class="tdbar"><i class="' + esc(token) + '" style="width:' +
    w.toFixed(0) + '%"></i></div>';
}

/* Three arcs on one circle. Not a library: a doughnut of three states is
   stroke-dasharray, and the legend under it carries the words -- nobody
   reads this by colour alone. */
function tdDonut(counts, total){
  var r = 42, c = 2 * Math.PI * r, at = 0;
  var segs = ["ok","part","behind"].filter(function(k){ return counts[k] > 0; });
  /* A 2px gap of surface between neighbouring arcs. Two fills that touch
     read as one fill, and that is exactly the failure this scale was
     re-stepped to avoid; the gap makes the boundary structural as well as
     chromatic. Only drawn when there is more than one arc, because a
     single arc has no neighbour and would just be a circle with a nick in
     it. */
  var gap = segs.length > 1 ? 2 : 0;
  var arcs = segs.map(function(k){
    var frac = counts[k] / total;
    var len = Math.max(0, c * frac - gap);
    var s = '<circle class="seg" cx="50" cy="50" r="' + r + '" ' +
      'stroke="var(--c-' + TD_TOKEN[k] + ')" ' +
      'stroke-dasharray="' + len.toFixed(2) + ' ' + (c - len).toFixed(2) + '" ' +
      'stroke-dashoffset="' + (-(c * at) - gap / 2).toFixed(2) + '"></circle>';
    at += frac;
    return s;
  }).join("");
  var pct = Math.round(100 * (counts.ok || 0) / total);
  return '<div class="tddonut">' +
    '<svg viewBox="0 0 100 100" role="img" aria-label="' +
      esc(counts.ok + " of " + total + " measures on target") + '">' +
      '<circle class="trk" cx="50" cy="50" r="' + r + '"></circle>' + arcs +
    '</svg>' +
    '<div class="mid"><b>' + pct + '%</b><span>on target</span></div></div>' +
    '<ul class="tdleg">' + ["ok","part","behind"].map(function(k){
      return '<li><span class="dot ' + TD_TOKEN[k] + '"></span>' +
        esc(TD_WORD[k]) + '<b>' + (counts[k] || 0) + '</b></li>';
    }).join("") + '</ul>';
}

/* ----------------------------------------------------------- the page */
function tdRender(){
  var d = TD.data;
  if (!d) { el("view").innerHTML = '<p class="mute">Loading…</p>'; return; }

  var me = d.me || {}, cases = d.cases || {}, ogl = d.ogl || {}, mx = d.mx || {};
  var tree = d.tree || {}, due = d.due || [], mine = d.mine || {};

  var ms = (tree.measures || []).filter(function(m){ return m.state !== "WITHDRAWN"; });
  var counts = { ok:0, part:0, behind:0, none:0 };
  ms.forEach(function(m){ counts[tdState(m.pct)]++; });
  var scored = counts.ok + counts.part + counts.behind;

  var open  = (cases.cases || []).filter(function(c){ return c.status !== "CLOSED"; }).length;
  var risky = (ogl.assignments || []).filter(function(a){
    return a.sla_status === "AT_RISK" || a.sla_status === "BREACHED"; }).length;
  var gaps  = (mx.branches || []).length;

  var dueToday = due.length;
  var filedToday = due.filter(function(x){ return x.alreadyFiled; }).length;
  var fileTok = !dueToday ? "none" : filedToday >= dueToday ? "ok"
              : filedToday ? "part" : "behind";

  var sheet = mine.sheet || null;
  var ach = sheet && sheet.calc ? sheet.calc.achievement : null;

  /* ------------------------------------------------------------ tiles */
  var tiles =
    tdTile("Filed today",
      '<span class="num">' + filedToday + '</span><span class="of">/' + dueToday + '</span>',
      dueToday ? (filedToday >= dueToday ? "nothing outstanding" : "still to file")
               : "nothing due today",
      fileTok) +
    tdTile("On target",
      '<span class="num">' + counts.ok + '</span><span class="of">/' + (scored || 0) + '</span>',
      scored ? "measures with a target" : "no target set yet",
      scored && counts.ok >= scored ? "ok" : counts.behind ? "behind" : "part") +
    tdTile("Quarter to date",
      '<span class="num">' + (ach === null || ach === undefined ? "—" : tdNum(ach, 1) + "%") + '</span>',
      sheet ? "achievement on the goal sheet" : "no goal sheet this quarter",
      ach === null || ach === undefined ? "none" : ach >= 100 ? "ok" : ach >= 80 ? "part" : "behind") +
    tdTile("Escalations open", '<span class="num">' + open + '</span>',
      open ? "waiting on your chair" : "none open", open ? "behind" : "ok") +
    tdTile("OGL at risk", '<span class="num">' + risky + '</span>',
      risky ? "at risk or already breached" : "every assignment inside its time",
      risky ? "part" : "ok");

  /* -------------------------------------------- my measures, in detail */
  var rows = ms.map(function(m){
    var st = tdState(m.pct);
    return '<tr><td><b>' + esc(m.name) + '</b>' +
        (m.unit ? ' <span class="mute">(' + esc(m.unit) + ')</span>' : '') + '</td>' +
      '<td class="r num">' + tdNum(m.value) + '</td>' +
      '<td class="r num">' + (m.target === null || m.target === undefined
        ? '<span class="mute">not set</span>' : tdNum(m.target)) + '</td>' +
      /* The figure beside the bar is ink, never the bar's own colour: a
         number is text and wears a text token. The bar carries the state,
         and the word for that state is on the bar's title so it is not
         carried by colour alone. */
      '<td class="tdprog">' + tdBar(m.pct, TD_TOKEN[st]) +
        '<span class="num" title="' + esc(TD_WORD[st]) + '">' +
        (m.pct === null || m.pct === undefined ? "—" : tdNum(m.pct, 0) + "%") +
        '</span></td></tr>';
  }).join("");

  var measures = ms.length
    ? '<div class="card"><h3>How my measures are going' +
        '<span class="sub">' + esc(tree.period || "") + '</span></h3>' +
      '<div class="scroll"><table class="tdt"><thead><tr>' +
        '<th>Measure</th><th class="r">Filed</th><th class="r">Target</th>' +
        '<th>Against target</th></tr></thead><tbody>' + rows + '</tbody></table></div></div>'
    : '<div class="card"><h3>How my measures are going</h3>' +
      '<div class="empty">' + esc(tree.says ||
        "Nothing has been set for you this period. Your manager sets your measures.") +
      '</div></div>';

  var donut = scored
    ? '<div class="card tdside"><h3>Where they stand</h3>' + tdDonut(counts, scored) + '</div>'
    : '';

  /* ------------------------------------------------- what is waiting */
  var waits = [];
  if (dueToday > filedToday) waits.push([dueToday - filedToday,
    "figure(s) still to file today", "#perf"]);
  if (open)  waits.push([open,  "escalation(s) open on your chair", "#cases"]);
  if (risky) waits.push([risky, "OGL assignment(s) at risk or breached", "#ogl"]);
  if (gaps)  waits.push([gaps,  "branch(es) missing an escalation level", "#matrix"]);

  var waiting = '<div class="card"><h3>Waiting on you</h3>' +
    (waits.length
      ? '<ul class="tdwait">' + waits.map(function(w){
          return '<li><b class="num">' + w[0] + '</b>' + esc(w[1]) +
            '<a href="' + w[2] + '">Open</a></li>'; }).join("") + '</ul>'
      : '<div class="empty">Nothing is waiting on your chair right now.</div>') +
    '</div>';

  /* ------------------------------------------------------- the quarter */
  var quarter = '<div class="card tdside"><h3>This quarter</h3>' +
    (sheet
      ? '<dl class="tdq">' +
          '<dt>Achievement</dt><dd class="num">' +
            (ach === null || ach === undefined ? "—" : tdNum(ach, 1) + "%") + '</dd>' +
          '<dt>Target bonus</dt><dd class="num">' +
            (sheet.targetPlb ? money(sheet.targetPlb) : "—") + '</dd>' +
          '<dt>As it stands</dt><dd class="num">' +
            (sheet.calc && sheet.calc.amount != null ? money(sheet.calc.amount) : "—") + '</dd>' +
          '<dt>Months scored</dt><dd class="num">' +
            ((sheet.months || []).filter(function(m){ return m.kpiPoints != null; }).length) +
            '<span class="of">/3</span></dd>' +
        '</dl>' +
        '<p><a class="btn" href="#perf">See the scorecard</a></p>'
      : '<div class="empty">No goal sheet has been issued for this quarter.</div>') +
    '</div>';

  el("view").innerHTML =
    '<div class="page-head"><div><h1>Dashboard</h1><div class="lede">' +
      esc(me.primaryChair ? me.primaryChair.title : "No chair held") + '</div></div></div>' +
    (TD.err || "") +
    '<div class="tdkpis">' + tiles + '</div>' +
    '<div class="tdgrid tdg2">' + measures + donut + '</div>' +
    '<div class="tdgrid tdg11">' + waiting + quarter + '</div>' +
    '<div id="mxcard"></div>';

  if (typeof mxCardLoad === "function") mxCardLoad();
}

async function vToday(){
  el("view").innerHTML = '<p class="mute">Loading…</p>';
  TD = { data:null, err:null };

  var first = await Promise.all([
    api("/people/me"), api("/cases"), crux("/api/ogl"),
    api("/matrix/incomplete"),
    plb("/plb/perf/cycle?period=" + new Date().toISOString().slice(0, 8) + "01")
  ]);
  var me = first[0], cases = first[1], ogl = first[2], mx = first[3], cyc = first[4];
  scope = me;

  /* Every one of these can come back refused, and the refusal carries the
     reason. Showing zeros without it is what made this screen look broken. */
  var refused = [me, cases, ogl, mx, cyc]
    .map(function(x){ return x && (x.reason || x.empty); })
    .filter(function(t, i, a){ return t && a.indexOf(t) === i; });
  var noChair = !me || !me.chairs || !me.chairs.length;
  TD.err = refused.length
    ? msg("warn", refused.join("  ")) +
      (noChair
        ? '<p class="mute">A chair is what the tool resolves your view from — ' +
          'which branches, which cases, whose scores. Nobody holds one yet, so ' +
          'these panels have nothing to draw. Load <b>Chairs</b> and then ' +
          '<b>People</b> under Data setup and they fill in.</p>'
        : "")
    : "";

  var cycleId = cyc && cyc.cycle && cyc.cycle.id;
  var second = await Promise.all([
    cycleId ? plb("/plb/perf/tree?cycle=" + encodeURIComponent(cycleId)) : Promise.resolve({}),
    plb("/plb/perf/due"),
    plb("/plb/mine")
  ]);

  TD.data = {
    me: me, cases: cases, ogl: ogl, mx: mx,
    tree: second[0] && second[0].error ? {} : second[0],
    due: (second[1] && second[1].due) || [],
    mine: second[2] && second[2].error ? {} : second[2]
  };
  tdRender();
}
