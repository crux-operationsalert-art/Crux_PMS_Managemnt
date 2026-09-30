/* ====================================================================== team
   My team — the people tree, in the shape of the attached org-chart design.

   The design is a sample of the UI and UX, not of the content: its cards
   carry chairs and level frameworks, these carry the people who actually
   hold them and what they have filed this month. What is taken from it is
   the language — a paper surface, hairline connectors drawn in CSS rather
   than SVG, a serif name over a small-caps chair, tiny outlined tags, and
   depth shown by tinting the top edge of a card rather than by indenting.

   What the tool already had under "My team" was a second drawing of the
   CHAIR tree, which is what "Structure" is for. This is the other tree:
   who reports to whom. It is worth being exact about the difference,
   because person.manager_id is what every visibility rule since migration
   218 is built on. Dragging a card here changes who can read whose
   numbers. That is why nothing on this screen decides anything: every
   card arrives from org_team_tree carrying its own mayMove and maySet,
   and every drop is refused or allowed by org_move_person.             */

var TM = { tree:null, cycle:null, shut:{}, sel:null, drag:null, over:null,
           busy:false, says:"", detail:null, detailFor:null, addTo:null };

async function vPeople(){
  el("view").innerHTML = '<p class="mute">Loading&hellip;</p>';
  TM.tree = await perfApi("/perf/team/tree");
  tmRender();
}

/* Everything below hangs off one flat list of people with a depth and a
   managerId. Building the parent map here rather than asking the server
   for nested JSON keeps the move cheap: after a drag only one row's
   managerId changes, and the tree redraws from the same array.          */
function tmKids(people){
  var by = {};
  people.forEach(function(p){
    var k = p.managerId || "_root";
    (by[k] = by[k] || []).push(p);
  });
  return by;
}

function tmRoot(t){
  var people = t.people || [];
  for (var i = 0; i < people.length; i++) if (people[i].depth === 0) return people[i];
  return people[0] || null;
}

/* ------------------------------------------------------- one card
   Status never travels as colour alone: the bar carries a number and a
   word beside it, so the card reads the same in greyscale and to somebody
   who does not see red and green apart.                                */
function tmCard(p){
  var d = Math.min(5, (p.depth || 0) + 1);
  var pct = p.progress;
  var band = pct === null || pct === undefined ? "none"
           : pct >= 100 ? "good" : pct >= 50 ? "part" : "short";
  var word = { good:"on target", part:"part way", short:"behind", none:"nothing filed" }[band];

  var tags = [];
  if (p.reports) tags.push('<span class="tmtg n">' + p.reports + ' report' +
                           (p.reports === 1 ? '' : 's') + '</span>');
  if (p.measures) tags.push('<span class="tmtg">' + p.filed + '/' + p.measures + ' filed</span>');
  if (!p.measures) tags.push('<span class="tmtg d">no measures</span>');
  if (p.rel === "self") tags.push('<span class="tmtg v">you</span>');

  return '<div class="tmcard d' + d + (TM.sel === p.personId ? ' sel' : '') +
      (TM.over === p.personId ? ' over' : '') + '"' +
      ' data-tm="' + esc(p.personId) + '"' +
      (p.mayMove ? ' draggable="true"' : '') + '>' +
    '<div class="tmnm">' + esc(p.name) + '</div>' +
    '<div class="tmch">' + esc(p.chair || "no chair") + '</div>' +
    (p.employeeNo ? '<div class="tmno">' + esc(p.employeeNo) + '</div>' : '') +
    '<div class="tmbar ' + band + '"><i style="width:' +
      (pct === null || pct === undefined ? 0 : Math.max(2, Math.min(100, pct))) +
      '%"></i></div>' +
    '<div class="tmpc ' + band + '">' +
      (pct === null || pct === undefined ? esc(word)
        : esc(pct) + '% &middot; ' + esc(word)) + '</div>' +
    (tags.length ? '<div class="tmtags">' + tags.join("") + '</div>' : '') +
    '</div>';
}

function tmBranch(by, key){
  var kids = by[key] || [];
  if (!kids.length) return "";
  return '<ul>' + kids.map(function(p){
    var mine = by[p.personId] || [];
    var shut = TM.shut[p.personId];
    return '<li>' +
      (mine.length
        ? '<button class="tmtog" data-tmtog="' + esc(p.personId) + '">' +
            (shut ? '+' : '&minus;') + '</button>'
        : '') +
      tmCard(p) +
      (mine.length && !shut ? tmBranch(by, p.personId) : '') +
      '</li>';
  }).join("") + '</ul>';
}

function tmRender(){
  var t = TM.tree;
  if (!t || t.error) {
    el("view").innerHTML = '<h1>My team</h1>' +
      msg("bad", (t && (t.reason || t.error)) || "The team could not be read.");
    return;
  }
  var people = t.people || [];
  var root = tmRoot(t);
  if (!root) {
    el("view").innerHTML = '<h1>My team</h1>' +
      '<div class="empty">Nobody reports to you, so there is no team to draw. ' +
      'Your own measures are on Performance &amp; appraisal.</div>';
    return;
  }
  var by = tmKids(people);

  var n = people.length - 1;
  var head = '<div class="page-head"><div><h1>My team</h1>' +
    '<p class="mute">' +
      (n ? esc(n) + ' ' + (n === 1 ? 'person' : 'people') + ' below you. ' : '') +
      'Drag a card onto another to change who they report to. ' +
      'That changes who can see their numbers, so every move is recorded.' +
    '</p></div></div>';

  var bar = '<div class="tmbarrow">' +
    '<button class="btn" id="tmexp">Expand all</button> ' +
    '<button class="btn" id="tmcol">Collapse all</button> ' +
    '<span class="mute tmkey">' +
      '<span class="tmsw good"></span> on target ' +
      '<span class="tmsw part"></span> part way ' +
      '<span class="tmsw short"></span> behind ' +
      '<span class="tmsw none"></span> nothing filed' +
    '</span></div>';

  el("view").innerHTML = head + bar +
    '<div class="card tmwrap"><div class="tmoc">' +
      '<ul><li>' +
        ((by[root.personId] || []).length
          ? '<button class="tmtog" data-tmtog="' + esc(root.personId) + '">' +
              (TM.shut[root.personId] ? '+' : '&minus;') + '</button>'
          : '') +
        tmCard(root) +
        (TM.shut[root.personId] ? '' : tmBranch(by, root.personId)) +
      '</li></ul>' +
    '</div></div>' +
    (TM.sel ? tmPanel() : '') +
    '<div id="pfmsg">' + TM.says + '</div>';

  tmWire();
}

/* ------------------------------------- what a manager does with a person
   Only the actions that exist are offered. A button that opens nothing is
   worse than no button: it tells somebody the tool does a thing it does
   not, and they stop trusting the ones that work. PIP and a formal
   warning are named here as not built rather than drawn and dead.       */
function tmPanel(){
  var p = (TM.tree.people || []).filter(function(x){ return x.personId === TM.sel; })[0];
  if (!p) return "";
  var can = p.maySet;

  var acts = can
    ? '<div class="tmacts">' +
        '<button class="btn" data-tmgo="targets">Set this month&rsquo;s targets</button>' +
        '<button class="btn" data-tmgo="score">Monthly review and score</button>' +
        '<button class="btn" data-tmgo="quarter">Quarterly scorecard</button>' +
        '<button class="btn" data-tmgo="task">Ask them for something</button>' +
      '</div>' +
      '<p class="mute tmsoon">Not built yet, and not drawn as though it were: ' +
      'a formal warning, a PIP with its planned reviews, and raising an ' +
      'escalation about a person rather than a case.</p>'
    : '<p class="mute">You can see how ' + esc(p.name.split(" ")[0]) +
      ' is doing. Setting their targets and scoring them belongs to the ' +
      'person they report to.</p>';

  var det = TM.detailFor === p.personId ? TM.detail : null;

  return '<div class="card tmpanel">' +
    '<h2>' + esc(p.name) +
      ' <span class="mute">&middot; ' + esc(p.chair || "no chair") + '</span></h2>' +
    '<p class="mute">' +
      (p.measures
        ? esc(p.filed) + ' of ' + esc(p.measures) + ' measures filed this month' +
          (p.progress === null || p.progress === undefined ? ''
            : ', ' + esc(p.onTrack) + ' at or past target')
        : 'No measures are set for them this month.') +
    '</p>' +
    acts +
    '<h3 class="tmh3">Measure by measure</h3>' +
    (det === null
      ? '<p class="mute">' +
        '<button class="btn" id="tmload">Show each measure</button></p>'
      : det.error
        ? msg("warn", det.reason || det.error)
        : tmMeasures(det)) +
    '</div>';
}

function tmMeasures(d){
  var ms = d.measures || [];
  if (!ms.length) return '<div class="empty">Nothing is assigned to them this month.</div>';
  return '<div class="scroll"><table><thead><tr>' +
      '<th>Measure</th><th>Target</th><th>Where they are</th><th></th>' +
    '</tr></thead><tbody>' + ms.map(function(m){
      return '<tr><td><b>' + esc(m.name) + '</b>' +
          '<div class="mute">' + esc(pfUnit(m.unit)) + '</div></td>' +
        '<td>' + (m.target === null || m.target === undefined
          ? '<span class="mute">none</span>' : pfNum(m.target)) + '</td>' +
        '<td>' + (m.value === null || m.value === undefined
          ? '<span class="mute">nothing filed</span>' : pfNum(m.value)) + '</td>' +
        '<td style="min-width:150px">' + pfMeter(m.value, m.target, m.direction) + '</td></tr>';
    }).join("") + '</tbody></table></div>';
}

/* ------------------------------------------------------------- wiring */
function tmWire(){
  if (el("tmexp")) el("tmexp").onclick = function(){ TM.shut = {}; tmRender(); };
  if (el("tmcol")) el("tmcol").onclick = function(){
    TM.shut = {};
    (TM.tree.people || []).forEach(function(p){
      if (p.depth > 0 || p.reports) TM.shut[p.personId] = true; });
    tmRender();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmtog]"), function(b){
    b.onclick = function(e){
      e.stopPropagation();
      var id = b.getAttribute("data-tmtog");
      if (TM.shut[id]) delete TM.shut[id]; else TM.shut[id] = true;
      tmRender();
    };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tm]"), function(c){
    var id = c.getAttribute("data-tm");

    c.onclick = function(){
      TM.sel = TM.sel === id ? null : id;
      TM.detail = null; TM.detailFor = null;
      tmRender();
    };

    /* A drag is only armed where the server said mayMove. The drop is
       still checked again by org_move_person -- this only stops the
       gesture being offered where it would certainly be refused. */
    c.ondragstart = function(e){
      TM.drag = id;
      try { e.dataTransfer.setData("text/plain", id); } catch (err) {}
      e.dataTransfer.effectAllowed = "move";
      c.classList.add("dragging");
    };
    c.ondragend = function(){ TM.drag = null; TM.over = null; tmRender(); };

    c.ondragover = function(e){
      if (!TM.drag || TM.drag === id) return;
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";
      if (TM.over !== id) { TM.over = id; c.classList.add("over"); }
    };
    c.ondragleave = function(){ if (TM.over === id) { TM.over = null; c.classList.remove("over"); } };

    c.ondrop = async function(e){
      e.preventDefault();
      var moved = TM.drag; TM.drag = null; TM.over = null;
      if (!moved || moved === id) { tmRender(); return; }
      await tmMove(moved, id);
    };
  });

  if (el("tmload")) el("tmload").onclick = async function(){
    el("tmload").disabled = true;
    TM.detailFor = TM.sel;
    TM.detail = await perfApi("/perf/org?cycle=" + encodeURIComponent(TM.tree.cycleId) +
                              "&person=" + encodeURIComponent(TM.sel));
    tmRender();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmgo]"), function(b){
    b.onclick = function(){
      var where = b.getAttribute("data-tmgo");
      /* These live on Performance & appraisal and on the scheme screen.
         Sending somebody there is honest; rebuilding them here would be a
         second implementation of a thing that already works. */
      location.hash = (where === "quarter" || where === "score") ? "#plb" : "#perf";
      if (typeof route === "function") route();
    };
  });
}

async function tmMove(personId, managerId){
  if (TM.busy) return;
  TM.busy = true;
  TM.says = msg("info", "Moving&hellip;");
  tmRender();

  var o = await perfApi("/perf/team/move",
    { method:"POST", body:{ personId: personId, managerId: managerId } });
  TM.busy = false;

  if (o && o.error) {
    /* would_loop is not a fault the person made -- it is the tool
       refusing to turn the reporting line into a ring. It reads as an
       explanation, not as an error. */
    TM.says = msg(o.error === "would_loop" ? "warn" : "bad",
      o.reason || o.error);
    tmRender();
    return;
  }

  TM.says = msg("good", (o && o.note) || "Moved.");
  TM.tree = await perfApi("/perf/team/tree");
  tmRender();
}
