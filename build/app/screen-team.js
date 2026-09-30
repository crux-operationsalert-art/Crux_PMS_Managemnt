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
           busy:false, says:"", detail:null, detailFor:null, addTo:null,
           conduct:null, conductFor:null, form:null };

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
        '<button class="btn" data-tmform="warn">Issue a warning</button>' +
        '<button class="btn" data-tmform="pip">Put on a PIP</button>' +
      '</div>'
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
    tmConduct() +
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


/* ------------------------------------- warnings, and the plan if there is one
   Two different shapes, drawn differently on purpose. A warning is a
   dated line that never changes. A plan is a live thing with reviews
   that are either held or overdue, and the overdue ones are the whole
   point of booking them as rows.                                       */
function tmConduct(){
  var c = TM.conductFor === TM.sel ? TM.conduct : null;
  if (!c) {
    return '<p class="tmsoon"><button class="btn" id="tmconduct">' +
      'Warnings and improvement plan</button></p>';
  }
  if (c.error) return msg("warn", c.reason || c.error);

  var ws = c.warnings || [];
  var warn = !ws.length
    ? '<p class="mute">No warning has been issued.</p>'
    : '<ul class="tmwarn">' + ws.map(function(w){
        return '<li><span class="tmlvl ' + esc((w.level||"").toLowerCase()) + '">' +
          esc(w.level) + '</span> <b>' + esc(w.subject) + '</b>' +
          '<div class="mute">' + esc((w.issuedAt||"").slice(0,10)) +
          ' &middot; ' + esc(w.issuedBy || "") + '</div>' +
          (w.detail ? '<div>' + esc(w.detail) + '</div>' : '') + '</li>';
      }).join("") + '</ul>';

  var p = c.plan;
  var plan;
  if (!p) {
    plan = '<p class="mute">Not on an improvement plan.</p>';
  } else {
    var rs = p.reviews || [];
    var due = rs.filter(function(r){ return r.overdue; }).length;
    var held = rs.filter(function(r){ return r.heldAt; }).length;
    plan = '<div class="tmplan">' +
      '<div class="tmplanh"><b>' + esc(p.state) + '</b> ' +
        '<span class="mute">' + esc(p.startsOn) + ' to ' + esc(p.endsOn) + '</span>' +
        (due ? ' <span class="tmover">' + due + ' review' +
               (due === 1 ? '' : 's') + ' overdue</span>' : '') +
      '</div>' +
      '<p><b>Concern.</b> ' + esc(p.concern) + '</p>' +
      '<p><b>What improvement looks like.</b> ' + esc(p.expectation) + '</p>' +
      (p.support ? '<p><b>Support.</b> ' + esc(p.support) + '</p>' : '') +
      (p.outcome ? '<p><b>Outcome.</b> ' + esc(p.outcome) + '</p>' : '') +
      '<div class="scroll"><table><thead><tr>' +
        '<th>#</th><th>Due</th><th>Held</th><th>Judgement</th><th></th>' +
      '</tr></thead><tbody>' + rs.map(function(r){
        return '<tr' + (r.overdue ? ' class="tmoverrow"' : '') + '>' +
          '<td>' + esc(r.seq) + '</td>' +
          '<td>' + esc(r.dueOn) + (r.overdue ? ' <span class="tmover">overdue</span>' : '') + '</td>' +
          '<td>' + (r.heldAt ? esc(r.heldAt.slice(0,10)) : '<span class="mute">not yet</span>') + '</td>' +
          '<td>' + (r.judgement ? esc(r.judgement.replace(/_/g," ").toLowerCase()) : '') +
            (r.note ? '<div class="mute">' + esc(r.note) + '</div>' : '') + '</td>' +
          '<td class="plact">' + (!r.heldAt && c.mayAct
            ? '<button class="btn" data-tmhold="' + esc(r.id) + '">Hold it</button>' : '') +
          '</td></tr>';
      }).join("") + '</tbody></table></div>' +
      (c.mayAct && (p.state === "OPEN" || p.state === "EXTENDED")
        ? '<p><button class="btn" data-tmform="close">Close the plan</button> ' +
          '<span class="mute">' + held + ' of ' + rs.length + ' reviews held.</span></p>'
        : '') +
      '</div>';
  }

  return '<h3 class="tmh3">Warnings</h3>' + warn +
         '<h3 class="tmh3">Improvement plan</h3>' + plan +
         (TM.form ? tmForm() : '');
}

/* One form, three shapes. Each field is what the database will refuse
   without, so the refusal happens here where it costs nothing.        */
function tmForm(){
  var f = TM.form;
  if (f === "warn") {
    return '<div class="tmfm"><h4>Issue a warning</h4>' +
      '<p><label>Level <select id="tmwlevel">' +
        '<option value="VERBAL">Verbal</option>' +
        '<option value="WRITTEN" selected>Written</option>' +
        '<option value="FINAL">Final</option></select></label></p>' +
      '<p><label>What it is about<br><input id="tmwsub" class="pfin" ' +
        'style="width:100%" placeholder="Numbers not filed for six working days"></label></p>' +
      '<p><label>Detail<br><textarea id="tmwdet" rows="3" style="width:100%"></textarea></label></p>' +
      '<p><button class="btn primary" id="tmwsave">Issue it</button> ' +
      '<button class="btn" id="tmfcancel">Cancel</button> ' +
      '<span class="mute">A warning is never edited afterwards.</span></p></div>';
  }
  if (f === "pip") {
    return '<div class="tmfm"><h4>Open an improvement plan</h4>' +
      '<p><label>The concern<br><textarea id="tmpcon" rows="2" style="width:100%" ' +
        'placeholder="Cases completed has been under half of target for two months"></textarea></label></p>' +
      '<p><label>What improvement looks like<br><textarea id="tmpexp" rows="2" ' +
        'style="width:100%" placeholder="At or above 90% of the monthly target for two consecutive months"></textarea></label></p>' +
      '<p><label>Support offered<br><textarea id="tmpsup" rows="2" style="width:100%"></textarea></label></p>' +
      '<p><label>Ends on <input id="tmpend" type="date"></label> ' +
      '<label>Review every <input id="tmpev" class="pfin" type="number" value="14" ' +
        'style="width:70px"> days</label></p>' +
      '<p><button class="btn primary" id="tmpsave">Open it</button> ' +
      '<button class="btn" id="tmfcancel">Cancel</button> ' +
      '<span class="mute">The reviews are booked now, not remembered later.</span></p></div>';
  }
  if (f === "close") {
    return '<div class="tmfm"><h4>Close the plan</h4>' +
      '<p><label>Outcome <select id="tmcst">' +
        '<option value="MET">Met</option>' +
        '<option value="NOT_MET">Not met</option>' +
        '<option value="EXTENDED">Extended</option>' +
        '<option value="WITHDRAWN">Withdrawn</option></select></label></p>' +
      '<p><label>Why<br><textarea id="tmcnote" rows="3" style="width:100%"></textarea></label></p>' +
      '<p><button class="btn primary" id="tmcsave">Close it</button> ' +
      '<button class="btn" id="tmfcancel">Cancel</button> ' +
      '<span class="mute">Met or not met needs a reason.</span></p></div>';
  }
  if (f && f.indexOf("hold:") === 0) {
    return '<div class="tmfm"><h4>Hold this review</h4>' +
      '<p><label>How it is going <select id="tmhj">' +
        '<option value="ON_TRACK">On track</option>' +
        '<option value="AT_RISK">At risk</option>' +
        '<option value="OFF_TRACK">Off track</option></select></label></p>' +
      '<p><label>Note<br><textarea id="tmhnote" rows="3" style="width:100%"></textarea></label></p>' +
      '<p><button class="btn primary" id="tmhsave">Record it</button> ' +
      '<button class="btn" id="tmfcancel">Cancel</button></p></div>';
  }
  return "";
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
      /* Somebody else's warnings must not stay on screen under this
         person's name, and a half-typed form must not follow them. */
      TM.conduct = null; TM.conductFor = null; TM.form = null;
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

  /* ------------------------------------ warnings and the improvement plan */
  async function tmConductLoad(){
    TM.conductFor = TM.sel;
    TM.conduct = await perfApi("/perf/conduct?person=" + encodeURIComponent(TM.sel));
    tmRender();
  }

  if (el("tmconduct")) el("tmconduct").onclick = function(){
    el("tmconduct").disabled = true; tmConductLoad();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmform]"), function(b){
    b.onclick = function(){
      TM.form = b.getAttribute("data-tmform");
      /* Opening a form needs the panel underneath it, so the conduct is
         loaded first if it has not been. */
      if (TM.conductFor !== TM.sel) tmConductLoad(); else tmRender();
    };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmhold]"), function(b){
    b.onclick = function(){ TM.form = "hold:" + b.getAttribute("data-tmhold"); tmRender(); };
  });

  if (el("tmfcancel")) el("tmfcancel").onclick = function(){ TM.form = null; tmRender(); };

  async function tmSend(path, body, good){
    if (TM.busy) return;
    TM.busy = true;
    var o = await perfApi(path, { method:"POST", body: body });
    TM.busy = false;
    if (o && o.error) { TM.says = msg("bad", o.reason || o.error); tmRender(); return; }
    TM.says = msg("good", (o && o.note) || good);
    TM.form = null;
    await tmConductLoad();
    /* A warning or a plan does not change a number, but the tile's own
       counts come from the same call, so the tree is refreshed too. */
    TM.tree = await perfApi("/perf/team/tree");
    tmRender();
  }

  if (el("tmwsave")) el("tmwsave").onclick = function(){
    tmSend("/perf/warn", { personId: TM.sel,
      level: el("tmwlevel").value, subject: el("tmwsub").value,
      detail: el("tmwdet").value, aboutKind: "CONDUCT" }, "Issued.");
  };

  if (el("tmpsave")) el("tmpsave").onclick = function(){
    tmSend("/perf/pip", { personId: TM.sel,
      concern: el("tmpcon").value, expectation: el("tmpexp").value,
      support: el("tmpsup").value,
      endsOn: el("tmpend").value || null,
      reviewEveryDays: el("tmpev").value || 14 }, "Opened.");
  };

  if (el("tmcsave")) el("tmcsave").onclick = function(){
    var p = TM.conduct && TM.conduct.plan;
    if (!p) return;
    tmSend("/perf/pip/close", { planId: p.id,
      state: el("tmcst").value, note: el("tmcnote").value }, "Closed.");
  };

  if (el("tmhsave")) el("tmhsave").onclick = function(){
    tmSend("/perf/pip/review", { reviewId: TM.form.slice(5),
      judgement: el("tmhj").value, note: el("tmhnote").value }, "Recorded.");
  };

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
