/* =============================================================== hr-ends
   What the tool knows it cannot see.

   Two functions had been sitting in the database, correct and invisible,
   since the day they were written -- plb_unseated() and
   person_without_number(). Correct and invisible is very nearly the same
   as absent, so this is the screen that makes them somebody's problem.

   The number at the top is the one that had never been stated anywhere.
   The KPI registry was written against the chair catalogue in the
   recommended operating structure; the people and geography loaded
   afterwards seat people in a different set. The two overlap in two
   chairs. So the scheme can score about a tenth of the company -- not
   score them badly, not score them zero: there is nothing for the engine
   to read. Nothing was broken to cause that and nothing will announce it,
   which is exactly why it goes at the top of a screen.

   This card only reports. Giving a chair a measure set decides who is in
   the bonus scheme, and that is the owner's decision on the KPIs screen,
   one chair at a time.                                                  */
var HE = { d:null, o:null, err:"", open:false };

function heHost(d){
  HE.d = d;
  if (d && d.isHr && !HE.o && !HE.err) setTimeout(heLoad, 0);
  return '<div id="hecard">' + heCard(d) + '</div>';
}

async function heLoad(){
  var o = await hrapi("/hr/loose-ends");
  if (o.error) { HE.err = o.reason || o.error; } else { HE.o = o; }
  heRepaint();
}

function heRepaint(){
  var host = el("hecard");
  if (!host) return;
  host.innerHTML = heCard(HE.d);
  heWire();
}

function heNum(n){ return n === null || n === undefined ? "—" : String(n); }

/* Somebody who needs a decision is listed above somebody who does not,
   because a list that mixes them is a list nobody finishes. */
function heWho(rows, wanted){
  var r = (rows || []).filter(function(x){ return !!x.needsDecision === wanted; });
  if (!r.length) return "";
  return r.map(function(x){
    return '<tr><td><b>' + esc(x.person) + '</b>' +
      (x.employeeNo ? ' <span class="mute">' + esc(x.employeeNo) + '</span>' : '') +
      (x.email ? '<div class="mute">' + esc(x.email) + '</div>' : '') + '</td>' +
      '<td>' + esc(x.chairs || "no chair at all") + '</td>' +
      '<td>' + esc(x.placeList || "") + '</td>' +
      '<td class="mute">' + esc(x.why) + '</td></tr>';
  }).join("");
}

function heCard(d){
  if (!d || !d.isHr) return "";
  if (HE.err) {
    return '<div class="card"><h2>Loose ends</h2>' + msg("bad", HE.err) + '</div>';
  }
  if (!HE.o) {
    return '<div class="card"><h2>Loose ends</h2>' +
      '<p class="mute">Working out what the scheme can and cannot see…</p></div>';
  }
  var o = HE.o, reach = o.reach || {};
  var short = (o.chairs || []).filter(function(c){ return !Number(c.measures); });

  var chairRows = (o.chairs || []).map(function(c){
    var has = Number(c.measures) > 0;
    return '<tr><td>' + esc(c.chair) + '</td>' +
      '<td class="num">' + heNum(c.seated) + '</td>' +
      '<td>' + (has
        ? esc(c.measures) + ' measure(s)'
        : '<span class="pill warn">no measure set</span>') + '</td></tr>';
  }).join("");

  var needs = heWho(o.unseated, true);
  var fine  = heWho(o.unseated, false);

  var numbers = (o.withoutNumber || []).map(function(x){
    return '<tr><td><b>' + esc(x.person) + '</b>' +
      (x.email ? '<div class="mute">' + esc(x.email) + '</div>' : '') + '</td>' +
      '<td>' + esc(x.chair || "no chair") + '</td>' +
      '<td>' + esc(x.needs) +
        (x.twinNumber ? '<div class="mute">' + esc(x.twin) + ' holds ' +
          esc(x.twinNumber) + '</div>' : '') + '</td>' +
      '<td class="mute">' + esc(x.why) + '</td></tr>';
  }).join("");

  var gap = Number(reach.people || 0) - Number(reach.measured || 0);

  return '<div class="card"><h2>Loose ends</h2>' +

    '<div class="hereach">' +
      '<div class="hebig">' + heNum(reach.measured) + ' / ' + heNum(reach.people) + '</div>' +
      '<div><b>active people the bonus scheme can score</b>' +
      '<p class="mute">' + esc(reach.says || "") + '</p></div>' +
    '</div>' +

    (gap > 0
      ? '<h4 class="plh">Chairs people are actually sitting in</h4>' +
        '<p class="mute">' + esc(short.length) + ' of these ' +
        esc((o.chairs || []).length) + ' carry no measure set, and ' +
        esc((o.spare || []).length) + ' measure sets are written for chairs ' +
        'nobody is in. The registry was built on one chair catalogue and the ' +
        'people were loaded into another; nothing mapped the two together.</p>' +
        '<div class="scroll"><table><tr><th>Chair</th><th>People in it</th>' +
        '<th>Measures</th></tr>' + chairRows + '</table></div>'
      : '') +

    ((o.spare || []).length
      ? '<p><button class="btn" id="hespare">' +
        (HE.open ? 'Hide' : 'Show') + ' the ' + esc((o.spare || []).length) +
        ' measure sets nobody is in</button></p>' +
        (HE.open
          ? '<div class="scroll"><table><tr><th>Chair</th><th>Measures</th></tr>' +
            (o.spare || []).map(function(c){
              return '<tr><td>' + esc(c.chair) + '</td><td class="num">' +
                esc(c.measures) + '</td></tr>'; }).join("") +
            '</table></div>'
          : '')
      : '') +

    '<h4 class="plh">Runs a place, and nothing measures them</h4>' +
    (needs || fine
      ? '<div class="scroll"><table><tr><th>Person</th><th>Chair</th><th>Place</th>' +
        '<th>Why they are on this list</th></tr>' + needs + fine + '</table></div>' +
        (needs
          ? '<p class="mute">The rows above the partners need a decision: either the ' +
            'chair they sit in gets a measure set, or they are seated somewhere that ' +
            'already has one. Doing nothing leaves somebody running a place with ' +
            'nothing recorded against them.</p>'
          : '')
      : '<div class="empty">Everybody who runs a place sits in a chair with a measure ' +
        'set, or is a partner and outside the scheme by design.</div>') +

    '<h4 class="plh">No employee number</h4>' +
    '<p class="mute">Past performance, KPI targets and Assignments all join people by ' +
    'employee number with no fallback to a name. Somebody without one has their rows ' +
    'dropped, and nothing says so.</p>' +
    (numbers
      ? '<div class="scroll"><table><tr><th>Person</th><th>Chair</th><th>Needs</th>' +
        '<th>Why</th></tr>' + numbers + '</table></div>'
      : '<div class="empty">Everybody who should have an employee number has one.</div>') +

    '</div>';
}

function heWire(){
  if (el("hespare")) el("hespare").onclick = function(){
    HE.open = !HE.open;
    heRepaint();
  };
}
