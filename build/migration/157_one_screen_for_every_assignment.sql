-- 157_one_screen_for_every_assignment.sql
--
-- The Places screen rebuilt. The old one could show coverage and rename a
-- place; it could not add or remove a client at a place, could not edit a
-- branch, could not seat a Branch or Zonal Manager, could not assign a whole
-- place in one go, and could not price anything. All of that lives here now,
-- in four tabs on one detail card, against a tree that is the master.
--
-- Three things this migration is careful about:
--   * it replaces exactly one block, between two markers it asserts are
--     present once each and in order, rather than trusting a byte offset;
--   * it adds CSS and removes none, because .opzone and .oploc turned out to
--     belong to the org tree on another screen, not to this one;
--   * it checks afterwards that the entry point the router calls still
--     exists and that the five functions the old block defined are gone.

do $mig$
declare
  v_html text;
  v_a    int;
  v_b    int;
  v_js   text := $PLACES2$/* ==================================================================== places
   Places, coverage & owners.

   One screen for the whole question of where the work is: the operating
   grouping and how to move a place inside it, who runs each place, who
   handles which client there, what that client is priced at, which branches
   sit there, which cities answer to it, and what a file is allowed to call
   it.

   It is a master and a detail rather than one long scroll, because the scroll
   could not carry branches: Mumbai alone has 1,665 of them. The tree is the
   master, one place opens on the right, and the branch list is a search.   */
var PL = { over:null, opt:null, sel:null, det:null, tab:"clients",
           q:"", bq:"", bclient:"", pick:{}, busy:false };

function plSay(box, kind, text){ var e = el(box); if (e) e.innerHTML = msg(kind, text); }
function plRole(r){ return r ? r.charAt(0) + r.slice(1).toLowerCase().replace(/_/g," ") : ""; }

async function vCoverage(){
  if (!PL.over) {
    PL.over = await ops("/places");
    if (PL.over.error) {
      el("view").innerHTML = "<h1>Places, coverage &amp; owners</h1>" +
        msg("bad", PL.over.reason || PL.over.error); PL.over = null; return;
    }
  }
  if (!PL.opt) PL.opt = await ops("/places/options");
  plRender();
}

/* --------------------------------------------------------------- the tree */
function plTree(){
  var d = PL.over, q = PL.q.trim().toLowerCase();
  var out = "", hits = 0;
  (d.groups || []).forEach(function(g){
    var zones = (g.zones || []).map(function(z){
      var locs = (z.locations || []).filter(function(l){
        return !q || l.name.toLowerCase().indexOf(q) >= 0 ||
               z.name.toLowerCase().indexOf(q) >= 0 ||
               (l.cities || []).join(" ").toLowerCase().indexOf(q) >= 0;
      });
      if (!locs.length && q && z.name.toLowerCase().indexOf(q) < 0) return "";
      hits += locs.length;
      return '<div class="plzone">' +
        '<div class="plz' + (PL.sel === z.id ? ' on' : '') + '" data-open="' + esc(z.id) + '">' +
          '<b>' + esc(z.name) + '</b>' +
          (z.active ? '' : ' <span class="chip">off</span>') +
          '<span class="plnums">' + esc(z.branches || 0) + '</span>' +
        '</div>' +
        locs.map(function(l){
          return '<div class="pll' + (PL.sel === l.id ? ' on' : '') + '" data-open="' + esc(l.id) + '">' +
            esc(l.name) + (l.active ? '' : ' <span class="chip">off</span>') +
            (Number(l.unassigned || 0)
              ? ' <span class="pill warn">' + esc(l.unassigned) + '</span>' : '') +
            (Number(l.managers || 0)
              ? ' <span class="pill ok">' + esc(l.managers) + '</span>' : '') +
            '<span class="plnums">' + esc(l.branches || 0) + '</span></div>';
        }).join("") + '</div>';
    }).join("");
    if (!zones) return;
    out += '<div class="plgrp"><h3>' + esc(g.name) + '</h3>' + zones + '</div>';
  });
  return out || '<div class="empty">Nothing matches &ldquo;' + esc(PL.q) + '&rdquo;.</div>';
}

/* ------------------------------------------------------------- the detail */
function plPersonPicker(id, pre){
  var people = (PL.opt && PL.opt.people) || [];
  return '<select id="' + id + '">' + (pre || '') +
    people.map(function(p){
      return '<option value="' + esc(p.id) + '">' + esc(p.name) +
        ' — ' + esc(p.employeeNo || "no number") +
        (p.chair ? ' — ' + esc(p.chair) : '') + '</option>';
    }).join("") + '</select>';
}

function plClientsTab(){
  var d = PL.det, rows = d.clients || [];
  var head =
    '<div class="plbar">' +
      '<button class="btn primary" id="plassignall">Assign this whole place to someone</button> ' +
      '<button class="btn" id="plassignsome">Assign the ticked clients</button> ' +
      '<button class="btn" id="pladdclient">Add a client here</button>' +
    '</div><div id="plcmsg"></div><div id="plpanel"></div>';

  if (!rows.length) {
    return head + '<div class="empty">No client has an active branch at ' + esc(d.name) +
      ' yet. &ldquo;Add a client here&rdquo; moves that client’s unplaced branches onto ' +
      'this place — nothing is created and nothing is deleted.</div>';
  }
  return head + '<div class="scroll"><table>' +
    '<tr><th class="pltk"></th><th>Client</th><th>Branches</th><th>Handlers</th>' +
    '<th>Rate</th><th></th></tr>' +
    rows.map(function(c){
      var hs = c.handlers || [];
      return '<tr><td class="pltk"><input type="checkbox" class="pltick" data-c="' +
        esc(c.clientId) + '"' + (PL.pick[c.clientId] ? ' checked' : '') + '></td>' +
        '<td class="plcl"><b>' + esc(c.name) + '</b><br><span class="mute">' +
        esc(c.code) + '</span></td>' +
        '<td class="num">' + esc(c.branches) + '</td>' +
        '<td>' + (hs.length
          ? hs.map(function(h){
              return esc(h.name) + ' <span class="mute">' + esc(h.employeeNo || "") +
                (h.role && h.role !== "HANDLER" ? ' · ' + esc(plRole(h.role)) : '') +
                (h.product ? ' · ' + esc(h.product) : '') +
                (h.from ? ' · from ' + esc(day(h.from)) : '') + '</span>' +
                ' <button class="btn" data-endrule="' + esc(h.ruleId) + '" data-who="' +
                esc(h.name) + '" data-what="' + esc(c.name) + '">End</button>';
            }).join('<br>')
          : '<span class="mute">nobody</span>') + '</td>' +
        '<td class="plrt">' + (c.rate
          ? '<b>' + esc(c.rate.value) + '</b> <span class="mute">' + esc(c.rate.currency || "INR") +
            '<br>from ' + esc(day(c.rate.from)) +
            (c.rate.to ? ' to ' + esc(day(c.rate.to)) : ' onwards') + '</span>'
          : '<span class="mute">not priced</span>') + '</td>' +
        '<td class="plact"><button class="btn" data-assign1="' + esc(c.clientId) + '" data-cname="' +
          esc(c.name) + '">Assign</button> ' +
          '<button class="btn" data-rate="' + esc(c.clientId) + '" data-cname="' +
          esc(c.name) + '">Rate</button> ' +
          '<button class="btn" data-drop="' + esc(c.clientId) + '" data-cname="' +
          esc(c.name) + '">Remove</button></td></tr>';
    }).join("") + '</table></div>';
}

function plPeopleTab(){
  var d = PL.det;
  var mans = d.managers || [], seat = d.seated || [];
  return '<div class="plbar">' +
      '<button class="btn primary" id="plsetrole">Set who runs this place</button> ' +
      '<button class="btn" id="plseat">Seat someone in a chair here</button>' +
    '</div><div id="plcmsg"></div><div id="plpanel"></div>' +
    '<h4 class="plh">Who runs this place</h4>' +
    '<p class="mute">The day-to-day answer: a Zonal Manager, a Branch Manager or a ' +
    'Location head, for the whole place or for one client at it. Ending it is a ' +
    'date, never a delete.</p>' +
    (mans.length
      ? '<div class="scroll"><table><tr><th>Role</th><th>Who</th><th>For</th><th>From</th><th></th></tr>' +
        mans.map(function(m){
          return '<tr><td><b>' + esc(plRole(m.role)) + '</b></td><td>' + esc(m.name) +
            ' <span class="mute">' + esc(m.employeeNo || "") + '</span></td><td>' +
            esc(m.client || "the whole place") + '</td><td>' + esc(day(m.from)) + '</td>' +
            '<td><button class="btn" data-endrule="' + esc(m.ruleId) + '" data-who="' +
            esc(m.name) + '" data-what="' + esc(plRole(m.role)) + '">End</button></td></tr>';
        }).join("") + '</table></div>'
      : '<div class="empty">Nobody is recorded as running ' + esc(d.name) + '.</div>') +
    '<h4 class="plh">Seated here by chair</h4>' +
    '<p class="mute">The job, which is a different thing. A chair seated at this ' +
    'place appears on the org chart; who runs the place today is above.</p>' +
    (seat.length
      ? '<div class="scroll"><table><tr><th>Chair</th><th>Who</th><th>From</th><th></th></tr>' +
        seat.map(function(s){
          return '<tr><td><b>' + esc(s.chair) + '</b>' +
            (s.primary ? ' <span class="chip">primary</span>' : '') + '</td><td>' +
            esc(s.name) + ' <span class="mute">' + esc(s.employeeNo || "") + '</span></td><td>' +
            esc(day(s.from)) + '</td><td><button class="btn" data-unseat="' + esc(s.holderId) +
            '" data-who="' + esc(s.name) + '" data-what="' + esc(s.chair) +
            '">End</button></td></tr>';
        }).join("") + '</table></div>'
      : '<div class="empty">No chair is seated at ' + esc(d.name) + '.</div>');
}

function plBranchTab(){
  var d = PL.det;
  var clients = d.clients || [];
  return '<div class="plbar">' +
      '<input id="plbq" placeholder="Search a code or a name" value="' + esc(PL.bq) + '"> ' +
      '<select id="plbc"><option value="">Every client here</option>' +
        clients.map(function(c){
          return '<option value="' + esc(c.clientId) + '"' +
            (PL.bclient === c.clientId ? ' selected' : '') + '>' + esc(c.name) + '</option>';
        }).join("") + '</select> ' +
      '<button class="btn" id="plbgo">Search</button> ' +
      '<button class="btn primary" id="plbadd">Add a branch here</button>' +
    '</div><div id="plcmsg"></div><div id="plpanel"></div><div id="plblist">' +
    '<div class="empty">Search, or press Search with the box empty to list the first 200.</div></div>';
}

function plRatesTab(){
  var d = PL.det, rows = (d.clients || []);
  return '<div class="plbar"><button class="btn primary" id="plnewrate">' +
      'Set a rate for a client here</button></div>' +
    '<div id="plcmsg"></div><div id="plpanel"></div>' +
    '<p class="mute">A rate is never overwritten. Setting one end-dates the version ' +
    'in force the day before the new one starts, so a report for a closed month ' +
    'still reads the rate that was valid then. A rate that would start on or ' +
    'before the one in force is refused rather than silently reordered.</p>' +
    (rows.length
      ? '<div class="scroll"><table><tr><th>Client</th><th>Rate</th><th>From</th>' +
        '<th>To</th><th>Why</th><th></th></tr>' +
        rows.map(function(c){
          var r = c.rate;
          return '<tr><td><b>' + esc(c.name) + '</b> <span class="mute">' + esc(c.code) +
            '</span></td><td class="num">' + (r ? esc(r.value) : '<span class="mute">—</span>') +
            '</td><td>' + (r ? esc(day(r.from)) : '') + '</td><td>' +
            (r ? (r.to ? esc(day(r.to)) : '<span class="mute">onwards</span>') : '') +
            '</td><td class="mute">' + (r ? esc(r.reason || "") : '') + '</td>' +
            '<td><button class="btn" data-rate="' + esc(c.clientId) + '" data-cname="' +
            esc(c.name) + '">' + (r ? 'New version' : 'Set a rate') + '</button></td></tr>';
        }).join("") + '</table></div>'
      : '<div class="empty">No client has a branch here, so there is nothing to price.</div>');
}

function plDetail(){
  var d = PL.det;
  if (!d) {
    return '<div class="card"><div class="empty">Pick a zone or a location on the left ' +
      'to see who runs it, who handles which client there, what it is priced at and ' +
      'which branches sit on it.</div></div>';
  }
  var tabs = [["clients","Clients & handlers"],["people","Who runs it"],
              ["branches","Branches"],["rates","Rates"]];
  var body = PL.tab === "people" ? plPeopleTab()
           : PL.tab === "branches" ? plBranchTab()
           : PL.tab === "rates" ? plRatesTab() : plClientsTab();
  var under = (d.under && d.under !== d.name) ? d.under : "";
  var lineBits = [(d.level === "LOCATION" ? "Location" : "Zone") +
                  (under ? " in " + under : "")];
  var nb = Number(d.branches || 0);
  lineBits.push(nb + (nb === 1 ? " branch" : " branches"));
  if (!d.active) { lineBits.push("retired"); }
  return '<div class="card"><h2>' + esc(d.name) + '</h2>' +
    '<p class="plsub">' + esc(lineBits.join(" · ")) + '</p>' +
    '<div class="pltabs">' + tabs.map(function(t){
      return '<button class="pltab' + (PL.tab === t[0] ? ' on' : '') +
        '" data-tab="' + t[0] + '">' + esc(t[1]) + '</button>';
    }).join("") + '</div>' + body + '</div>';
}

/* ------------------------------------------------------------- the render */
function plRender(){
  var d = PL.over;
  var nBr = 0, nLoc = 0, nUn = 0;
  (d.groups || []).forEach(function(g){ (g.zones || []).forEach(function(z){
    (z.locations || []).forEach(function(l){
      nLoc++; nBr += Number(l.branches || 0); nUn += Number(l.unassigned || 0);
    });
  }); });

  el("view").innerHTML =
    '<div class="page-head"><div><h1>Places, coverage &amp; owners</h1>' +
    '<p class="mute">Where the work is, who runs it, who handles which client ' +
    'there, what it is priced at, and what a file may call it. One screen, ' +
    'because a rate, a branch and a handler all have to mean the same place by ' +
    'the same name.</p></div></div>' +
    '<div class="counters">' +
      '<div class="counter"><span>Branches placed</span><b>' + esc(nBr) + '</b></div>' +
      '<div class="counter"><span>Locations</span><b>' + esc(nLoc) + '</b></div>' +
      '<div class="counter"><span>Clients unassigned</span><b>' + esc(nUn) + '</b></div>' +
      '<div class="counter"><span>Branches unplaced</span><b>' +
        esc(d.unplacedBranches || 0) + '</b></div>' +
      '<div class="counter"><span>Cities unaligned</span><b>' +
        esc(d.unalignedCities || 0) + '</b></div>' +
    '</div>' +
    (d.mayEdit ? '' : msg("warn",
      "You can see the grouping but not change it. The administrator owns it.")) +
    '<div id="plmsg"></div>' +
    '<div class="plwrap">' +
      '<div class="plside"><div class="card">' +
        '<h2>The operating grouping</h2>' +
        '<p><input id="plq" placeholder="Find a place or a city" value="' + esc(PL.q) + '"></p>' +
        (d.mayEdit ? '<p><button class="btn" id="pladdzone">Add a zone</button> ' +
          '<button class="btn" id="pladdloc">Add a location</button> ' +
          '<button class="btn" id="plmove">Move the open place</button></p>' : '') +
        '<div class="pltree">' + plTree() + '</div>' +
      '</div></div>' +
      '<div class="plmain">' + plDetail() + '</div>' +
    '</div>' +
    plCitiesCard() + plAliasCard();

  plWire();
}

function plCitiesCard(){
  var d = PL.over, cities = d.cities || [];
  var places = d.places || [];
  var unaligned = cities.filter(function(c){ return !c.resolves; });
  var show = PL.allCities ? cities : unaligned;
  return '<div class="card"><h2>Cities the geography knows</h2>' +
    '<p class="mute">A city is where a branch physically is. An operating zone is ' +
    'who runs it. They are different trees, and this is the only place the link ' +
    'between them is visible — a city aligned to nothing is not an error, it is a ' +
    'question nobody has answered yet.</p>' +
    '<p><button class="btn" id="plcityall">' +
      (PL.allCities ? 'Show only the ' + esc(unaligned.length) + ' unaligned'
                    : 'Show all ' + esc(cities.length)) + '</button></p>' +
    (show.length
      ? '<div class="scroll"><table><tr><th>Place</th><th>What</th><th>Branches</th>' +
        '<th>Answers to</th><th></th></tr>' +
        show.map(function(c){
          return '<tr' + (c.resolves ? '' : ' class="warnrow"') + '><td>' + esc(c.name) +
            '</td><td class="mute">' + esc(c.level === "STATE" ? "state" : "city") +
            (c.under ? ' in ' + esc(c.under) : '') + '</td><td class="num">' +
            esc(c.branches || 0) + '</td><td>' +
            (d.mayEdit
              ? '<select data-city="' + esc(c.id) + '"><option value="">not aligned</option>' +
                places.map(function(p){
                  return '<option value="' + esc(p.id) + '"' +
                    (p.name === c.opZone ? ' selected' : '') + '>' + esc(p.name) +
                    ' (' + esc(p.level.toLowerCase()) + ')</option>';
                }).join("") + '</select>'
              : (c.resolves ? esc(c.resolves) : '<span class="mute">not aligned</span>')) +
            '</td><td class="mute">' +
            (c.opZone && !c.resolves
              ? 'says &ldquo;' + esc(c.opZone) + '&rdquo;, which is no longer a place'
              : (c.resolves ? '' : 'nothing places it')) + '</td></tr>';
        }).join("") + '</table></div>'
      : '<div class="empty">Every city the geography knows answers to an operating zone.</div>') +
    '<div id="citymsg"></div></div>';
}

function plAliasCard(){
  var d = PL.over, aliases = d.aliases || [], places = d.places || [];
  return '<div class="card"><h2>Spellings a file may use</h2>' +
    '<p class="mute">What a written form means, when it is not what this tree calls ' +
    'the place. A row here, never a deploy — the next odd spelling an upload meets ' +
    'is added below. A spelling may not shadow a real name.</p>' +
    (aliases.length
      ? '<div class="scroll"><table><tr><th>A file writes</th><th></th><th>It means</th>' +
        '<th>Why</th><th></th></tr>' +
        aliases.map(function(a){
          return '<tr><td>' + esc(a.writtenAs) + '</td><td>&rarr;</td><td>' +
            esc(a.resolves || a.means) +
            (a.resolves ? '' : ' <span class="pill warn">means nothing now</span>') +
            '</td><td class="mute">' + esc(a.note || "") + '</td><td>' +
            (d.mayEdit ? '<button class="btn" data-alrm="' + esc(a.writtenAs) +
              '">Remove</button>' : '') + '</td></tr>';
        }).join("") + '</table></div>'
      : '<div class="empty">No spellings are taught. Every file must name a place ' +
        'exactly as this tree calls it.</div>') +
    (d.mayEdit
      ? '<p><label>A file writes<br><input id="alwritten" placeholder="e.g. New Delhi"></label> ' +
        '<label>It means<br><input id="almeans" list="alplaces" placeholder="e.g. Delhi">' +
        '<datalist id="alplaces">' +
        places.map(function(p){ return '<option value="' + esc(p.name) + '">'; }).join("") +
        '</datalist></label> ' +
        '<label>Why<br><input id="alnote" placeholder="optional"></label> ' +
        '<button class="btn primary" id="algo">Teach it</button></p>'
      : '') +
    '<div id="aliasmsg"></div></div>';
}

/* ------------------------------------------------------------- the wiring */
async function plReload(keepTab){
  PL.over = await ops("/places");
  if (PL.sel) {
    var d = await ops("/places/place/" + PL.sel);
    PL.det = d && !d.error ? d : null;
  }
  if (!keepTab) PL.tab = PL.tab || "clients";
  plRender();
}

function plEach(sel, fn){
  Array.prototype.forEach.call(el("view").querySelectorAll(sel), fn);
}

async function plDo(btn, path, body, box){
  if (PL.busy) return null;
  PL.busy = true; if (btn) btn.disabled = true;
  var out = await ops(path, { method:"POST", body: body });
  PL.busy = false; if (btn) btn.disabled = false;
  if (out.error) { plSay(box || "plmsg", "bad", out.reason || out.error); return null; }
  plSay(box || "plmsg", "ok", out.note || "Done.");
  return out;
}

function plWire(){
  var d = PL.over;

  /* ----------------------------------------------------------- the tree */
  var q = el("plq");
  if (q) {
    q.oninput = function(){
      PL.q = q.value;
      var t = el("view").querySelector(".pltree");
      if (t) t.innerHTML = plTree();
      plWireTree();
    };
  }
  plWireTree();

  if (el("pladdzone")) el("pladdzone").onclick = function(){ plNodeForm("zone"); };
  if (el("pladdloc"))  el("pladdloc").onclick  = function(){ plNodeForm("location"); };
  if (el("plmove"))    el("plmove").onclick    = function(){ plMoveForm(); };

  /* ---------------------------------------------------------- the tabs */
  plEach("[data-tab]", function(b){
    b.onclick = function(){ PL.tab = b.getAttribute("data-tab"); plRender(); };
  });

  /* ------------------------------------------------------ clients tab */
  plEach(".pltick", function(c){
    c.onchange = function(){ PL.pick[c.getAttribute("data-c")] = c.checked; };
  });
  if (el("plassignall")) el("plassignall").onclick = function(){ plAssignForm(null); };
  if (el("plassignsome")) el("plassignsome").onclick = function(){
    var ids = Object.keys(PL.pick).filter(function(k){ return PL.pick[k]; });
    if (!ids.length) { plSay("plcmsg","warn","Tick the clients first."); return; }
    plAssignForm(ids);
  };
  plEach("[data-assign1]", function(b){
    b.onclick = function(){ plAssignForm([b.getAttribute("data-assign1")], b.getAttribute("data-cname")); };
  });
  if (el("pladdclient")) el("pladdclient").onclick = function(){ plAddClientForm(); };
  plEach("[data-drop]", function(b){
    b.onclick = async function(){
      var nm = b.getAttribute("data-cname");
      if (!confirm("Take " + nm + " off " + PL.det.name + "?\n\nIts branches are not " +
        "deleted - they go back to waiting to be placed, and the screen counts them.")) return;
      if (await plDo(b, "/places/client",
            { clientId: b.getAttribute("data-drop"), nodeId: PL.sel, attach: false }, "plcmsg"))
        setTimeout(function(){ plReload(true); }, 900);
    };
  });
  plEach("[data-endrule]", function(b){
    b.onclick = async function(){
      if (!confirm("End " + b.getAttribute("data-who") + " on " +
        b.getAttribute("data-what") + "?\n\nThe rule is dated to today, never deleted - " +
        "who covered what last month is how an escalation is argued about later.")) return;
      if (await plDo(b, "/places/role/end", { ruleId: b.getAttribute("data-endrule") }, "plcmsg"))
        setTimeout(function(){ plReload(true); }, 700);
    };
  });

  /* ------------------------------------------------------- people tab */
  if (el("plsetrole")) el("plsetrole").onclick = function(){ plRoleForm(); };
  if (el("plseat")) el("plseat").onclick = function(){ plSeatForm(); };
  plEach("[data-unseat]", function(b){
    b.onclick = async function(){
      if (!confirm("End " + b.getAttribute("data-who") + " in " +
        b.getAttribute("data-what") + " here?")) return;
      if (await plDo(b, "/places/chair/end", { holderId: b.getAttribute("data-unseat") }, "plcmsg"))
        setTimeout(function(){ plReload(true); }, 700);
    };
  });

  /* ----------------------------------------------------- branches tab */
  if (el("plbgo")) el("plbgo").onclick = plBranchSearch;
  if (el("plbq")) el("plbq").onkeydown = function(e){ if (e.key === "Enter") plBranchSearch(); };
  if (el("plbadd")) el("plbadd").onclick = function(){ plBranchForm(null); };

  /* -------------------------------------------------------- rates tab */
  if (el("plnewrate")) el("plnewrate").onclick = function(){ plRateForm(null, null); };
  plEach("[data-rate]", function(b){
    b.onclick = function(){ plRateForm(b.getAttribute("data-rate"), b.getAttribute("data-cname")); };
  });

  /* ---------------------------------------------------------- cities */
  if (el("plcityall")) el("plcityall").onclick = function(){
    PL.allCities = !PL.allCities; plRender();
  };
  plEach("[data-city]", function(s){
    s.dataset.was = s.value;
    s.onchange = async function(){
      s.disabled = true;
      var out = await ops("/places/city", { method:"POST",
        body:{ cityId: s.getAttribute("data-city"), placeId: s.value || null } });
      s.disabled = false;
      if (out.error) {
        plSay("citymsg","bad", out.reason || out.error); s.value = s.dataset.was; return;
      }
      s.dataset.was = s.value;
      plSay("citymsg","ok", out.note || "Aligned.");
      PL.over = await ops("/places");
    };
  });

  /* ------------------------------------------------------- spellings */
  if (el("algo")) el("algo").onclick = async function(){
    if (await plDo(el("algo"), "/places/alias", {
          writtenAs: el("alwritten").value, means: el("almeans").value,
          note: el("alnote").value }, "aliasmsg"))
      setTimeout(function(){ plReload(true); }, 900);
  };
  plEach("[data-alrm]", function(b){
    b.onclick = async function(){
      if (!confirm("Remove the spelling “" + b.getAttribute("data-alrm") +
        "”?\n\nA file that uses it will be refused unless the tree already " +
        "calls something that.")) return;
      if (await plDo(b, "/places/alias/remove",
            { writtenAs: b.getAttribute("data-alrm") }, "aliasmsg"))
        setTimeout(function(){ plReload(true); }, 700);
    };
  });
}

function plWireTree(){
  plEach("[data-open]", function(e){
    e.onclick = async function(){
      PL.sel = e.getAttribute("data-open");
      PL.pick = {}; PL.bq = ""; PL.bclient = "";
      var d = await ops("/places/place/" + PL.sel);
      PL.det = d && !d.error ? d : null;
      plRender();
    };
  });
}

/* ------------------------------------------------------------- the forms */
function plPanel(title, body){
  el("plpanel").innerHTML = '<div class="plform"><h4 class="plh">' + esc(title) + '</h4>' +
    body + '<div id="plformmsg"></div></div>';
  el("plpanel").scrollIntoView({ behavior:"smooth", block:"nearest" });
  if (el("plcancel")) el("plcancel").onclick = function(){ el("plpanel").innerHTML = ""; };
}

function plAssignForm(clientIds, oneName){
  var what = oneName ? oneName
           : (clientIds ? clientIds.length + " ticked client(s)" : "every client here");
  var prods = (PL.opt && PL.opt.products) || [];
  plPanel("Assign " + what + " at " + PL.det.name,
    '<p class="mute">One rule for the place, not one per branch. Anything they ' +
    'already cover is left alone, so pressing it twice is harmless.</p>' +
    '<label>Who<br>' + plPersonPicker("plawho") + '</label> ' +
    '<label>Product<br><input id="plaprod" list="plaprods" placeholder="optional">' +
      '<datalist id="plaprods">' +
      prods.map(function(p){ return '<option value="' + esc(p) + '">'; }).join("") +
      '</datalist></label> ' +
    '<label>Effective from<br><input id="plafrom" type="date"></label> ' +
    '<p><button class="btn primary" id="plago">Assign</button> ' +
    '<button class="btn" id="plcancel">Cancel</button></p>');
  el("plago").onclick = async function(){
    if (await plDo(el("plago"), "/places/assign", {
          nodeId: PL.sel, personId: el("plawho").value,
          clientIds: clientIds || null,
          product: el("plaprod").value, from: el("plafrom").value || null }, "plformmsg"))
      setTimeout(function(){ PL.pick = {}; plReload(true); }, 1100);
  };
}

function plAddClientForm(){
  var list = (PL.det && PL.det.clientsNotHere) || [];
  if (!list.length) {
    plPanel("Add a client here",
      '<div class="empty">Every active client already has a branch at ' + esc(PL.det.name) +
      '.</div><p><button class="btn" id="plcancel">Close</button></p>');
    return;
  }
  plPanel("Add a client to " + PL.det.name,
    '<p class="mute">A client is at a place because its branches are. This moves that ' +
    'client’s branches that are waiting to be placed onto ' + esc(PL.det.name) +
    '. Nothing is created and nothing is deleted — a client with no waiting ' +
    'branch will say so rather than pretending.</p>' +
    '<label>Client<br><select id="placlient">' +
      list.map(function(c){
        return '<option value="' + esc(c.id) + '">' + esc(c.name) + ' — ' + esc(c.code) +
          ' — ' + esc(c.unplaced) + ' branch(es) waiting</option>';
      }).join("") + '</select></label>' +
    '<p><button class="btn primary" id="placgo">Add</button> ' +
    '<button class="btn" id="plcancel">Cancel</button></p>');
  el("placgo").onclick = async function(){
    if (await plDo(el("placgo"), "/places/client",
          { clientId: el("placlient").value, nodeId: PL.sel, attach: true }, "plformmsg"))
      setTimeout(function(){ plReload(true); }, 1100);
  };
}

function plRoleForm(){
  var roles = (PL.over && PL.over.roles) || [];
  var clients = (PL.det && PL.det.clients) || [];
  plPanel("Who runs " + PL.det.name,
    '<p class="mute">The day-to-day answer. Setting the same role again replaces the ' +
    'holder: the previous one is end-dated, never removed.</p>' +
    '<label>Role<br><select id="plrrole">' +
      roles.map(function(r){
        return '<option value="' + esc(r.key) + '">' + esc(r.label) + '</option>';
      }).join("") + '</select></label> ' +
    '<label>Who<br>' + plPersonPicker("plrwho") + '</label> ' +
    '<label>For<br><select id="plrclient"><option value="">the whole place</option>' +
      clients.map(function(c){
        return '<option value="' + esc(c.clientId) + '">' + esc(c.name) + '</option>';
      }).join("") + '</select></label> ' +
    '<label>From<br><input id="plrfrom" type="date"></label>' +
    '<p><button class="btn primary" id="plrgo">Set</button> ' +
    '<button class="btn" id="plcancel">Cancel</button></p>');
  el("plrgo").onclick = async function(){
    if (await plDo(el("plrgo"), "/places/role", {
          nodeId: PL.sel, personId: el("plrwho").value, role: el("plrrole").value,
          clientId: el("plrclient").value || null,
          from: el("plrfrom").value || null }, "plformmsg"))
      setTimeout(function(){ plReload(true); }, 1100);
  };
}

function plSeatForm(){
  var chairs = (PL.opt && PL.opt.chairs) || [];
  plPanel("Seat someone in a chair at " + PL.det.name,
    '<p class="mute">This is the job, not who runs the place today. It appears on the ' +
    'org chart. Both are real and they are different things.</p>' +
    '<label>Who<br>' + plPersonPicker("plswho") + '</label> ' +
    '<label>Chair<br><select id="plschair">' +
      chairs.map(function(c){
        return '<option value="' + esc(c.id) + '">' + esc(c.title) + '</option>';
      }).join("") + '</select></label> ' +
    '<label><input type="checkbox" id="plsprim"> make this their primary chair</label>' +
    '<p><button class="btn primary" id="plsgo">Seat</button> ' +
    '<button class="btn" id="plcancel">Cancel</button></p>');
  el("plsgo").onclick = async function(){
    if (await plDo(el("plsgo"), "/places/chair", {
          personId: el("plswho").value, chairId: el("plschair").value,
          place: PL.det.name, primary: el("plsprim").checked }, "plformmsg"))
      setTimeout(function(){ plReload(true); }, 1100);
  };
}

function plRateForm(clientId, cname){
  var clients = (PL.det && PL.det.clients) || [];
  plPanel(cname ? "Rate for " + cname + " at " + PL.det.name : "Set a rate at " + PL.det.name,
    '<p class="mute">The version in force is end-dated the day before this one starts. ' +
    'A closed month still reads the rate that was valid then.</p>' +
    (clientId ? '' :
      '<label>Client<br><select id="plrtclient">' +
        clients.map(function(c){
          return '<option value="' + esc(c.clientId) + '">' + esc(c.name) + '</option>';
        }).join("") + '</select></label> ') +
    '<label>Rate<br><input id="plrtval" type="number" step="0.01" min="0"></label> ' +
    '<label>From<br><input id="plrtfrom" type="date"></label> ' +
    '<label>To (optional)<br><input id="plrtto" type="date"></label> ' +
    '<label>Why<br><input id="plrtwhy" placeholder="e.g. revised on renewal"></label>' +
    '<p><button class="btn primary" id="plrtgo">Set the rate</button> ' +
    '<button class="btn" id="plcancel">Cancel</button></p>');
  el("plrtgo").onclick = async function(){
    if (await plDo(el("plrtgo"), "/places/rate", {
          clientId: clientId || el("plrtclient").value, nodeId: PL.sel,
          value: el("plrtval").value, from: el("plrtfrom").value,
          to: el("plrtto").value || null, reason: el("plrtwhy").value }, "plformmsg"))
      setTimeout(function(){ plReload(true); }, 1300);
  };
}

function plBranchForm(row){
  var clients = (PL.det && PL.det.clients) || [];
  var all = (PL.opt && PL.opt.clients) || [];
  var list = clients.length ? clients.map(function(c){
    return { id:c.clientId, name:c.name, code:c.code }; }) : all;
  plPanel(row ? "Edit " + row.name : "Add a branch at " + PL.det.name,
    '<p class="mute">A branch is never deleted. A code that has gone is switched off, ' +
    'so coverage, escalations and history that name it keep pointing somewhere.</p>' +
    '<label>Client<br><select id="plbcl">' +
      list.map(function(c){
        return '<option value="' + esc(c.id) + '"' +
          (row && row.client_id === c.id ? ' selected' : '') + '>' + esc(c.name) + '</option>';
      }).join("") + '</select></label> ' +
    '<label>Code<br><input id="plbcode" value="' + esc(row ? row.code : "") + '"></label> ' +
    '<label>Name<br><input id="plbname" value="' + esc(row ? row.name : "") + '"></label> ' +
    '<label>Address<br><input id="plbaddr" value="' + esc(row ? (row.address || "") : "") + '"></label> ' +
    (row ? '<label><input type="checkbox" id="plbact"' +
             (row.status === "ACTIVE" ? " checked" : "") + '> active</label>' : '') +
    '<p><button class="btn primary" id="plbsave">Save</button> ' +
    '<button class="btn" id="plcancel">Cancel</button></p>');
  el("plbsave").onclick = async function(){
    var body = { id: row ? row.id : null, clientId: el("plbcl").value,
                 code: el("plbcode").value, name: el("plbname").value,
                 nodeId: PL.sel, address: el("plbaddr").value };
    if (row) body.active = el("plbact").checked;
    if (await plDo(el("plbsave"), "/places/branch", body, "plformmsg")) {
      el("plpanel").innerHTML = "";
      plBranchSearch();
      PL.over = await ops("/places");
    }
  };
}

async function plBranchSearch(){
  PL.bq = el("plbq") ? el("plbq").value : "";
  PL.bclient = el("plbc") ? el("plbc").value : "";
  el("plblist").innerHTML = '<div class="empty">Looking&hellip;</div>';
  var d = await ops("/places/branches?node=" + encodeURIComponent(PL.sel) +
    (PL.bclient ? "&client=" + encodeURIComponent(PL.bclient) : "") +
    (PL.bq ? "&q=" + encodeURIComponent(PL.bq) : "") + "&limit=200");
  if (d.error) { el("plblist").innerHTML = msg("bad", d.reason || d.error); return; }
  var rows = d.rows || [];
  el("plblist").innerHTML =
    '<p class="mute">' + esc(d.total) + ' branch(es) here' +
    (Number(d.total) > Number(d.shown)
      ? '; showing the first ' + esc(d.shown) + '. Narrow the search to see the rest.' : '.') +
    '</p>' +
    (rows.length
      ? '<div class="scroll"><table><tr><th>Code</th><th>Name</th><th>Client</th>' +
        '<th>Status</th><th></th></tr>' +
        rows.map(function(b){
          return '<tr><td class="mono">' + esc(b.code) + '</td><td>' + esc(b.name) +
            (b.address ? '<br><span class="mute">' + esc(b.address) + '</span>' : '') +
            '</td><td>' + esc(b.client) + '</td><td>' +
            (b.status === "ACTIVE" ? '<span class="pill ok">active</span>'
                                   : '<span class="pill">off</span>') +
            '</td><td><button class="btn" data-bedit="' + esc(b.id) + '">Edit</button></td></tr>';
        }).join("") + '</table></div>'
      : '<div class="empty">Nothing here matches.</div>');
  Array.prototype.forEach.call(el("plblist").querySelectorAll("[data-bedit]"), function(btn){
    btn.onclick = function(){
      var r = rows.filter(function(x){ return x.id === btn.getAttribute("data-bedit"); })[0];
      if (r) plBranchForm(r);
    };
  });
}

function plNodeForm(what){
  var d = PL.over;
  var parents = (d.places || []).filter(function(p){
    return p.level === (what === "zone" ? "GROUP" : "ZONE"); });
  plPanel("Add a " + what,
    '<label>Under<br><select id="plnparent">' +
      parents.map(function(p){
        return '<option value="' + esc(p.id) + '">' + esc(p.name) + '</option>';
      }).join("") + '</select></label> ' +
    '<label>Name<br><input id="plnname" placeholder="What the business calls it"></label>' +
    '<p><button class="btn primary" id="plngo">Add</button> ' +
    '<button class="btn" id="plcancel">Cancel</button></p>');
  el("plngo").onclick = async function(){
    if (await plDo(el("plngo"), "/places/node",
          { name: el("plnname").value, parentId: el("plnparent").value }, "plformmsg"))
      setTimeout(function(){ plReload(true); }, 900);
  };
}

function plMoveForm(){
  if (!PL.det) { plSay("plmsg","warn","Open a place on the left first."); return; }
  var d = PL.over;
  var want = PL.det.level === "LOCATION" ? "ZONE" : "GROUP";
  var parents = (d.places || []).filter(function(p){ return p.level === want; });
  if (!parents.length) { plSay("plmsg","warn","There is nowhere to move it to."); return; }
  plPanel("Move " + PL.det.name,
    '<p class="mute">Everything under it moves with it, including its branches. This is ' +
    'the edit that used to say ok and do nothing.</p>' +
    '<label>Under<br><select id="plmparent">' +
      parents.map(function(p){
        return '<option value="' + esc(p.id) + '">' + esc(p.name) + '</option>';
      }).join("") + '</select></label>' +
    '<p><button class="btn primary" id="plmgo">Move</button> ' +
    '<button class="btn" id="plcancel">Cancel</button></p>');
  el("plmgo").onclick = async function(){
    if (await plDo(el("plmgo"), "/places/node",
          { id: PL.sel, name: PL.det.name, parentId: el("plmparent").value }, "plformmsg"))
      setTimeout(function(){ plReload(true); }, 1100);
  };
}

$PLACES2$;
  v_css  text := $NEWCSS$.plwrap{display:grid;grid-template-columns:300px 1fr;gap:16px;align-items:start}
.plside .card{margin-bottom:0}
.pltree{max-height:620px;overflow:auto;border-top:1px solid var(--line3)}
.plgrp{padding:8px 0;border-bottom:1px solid var(--line3)}
.plgrp>h3{padding:0 15px 4px}
.plzone{margin:2px 0}
.plz,.pll{display:flex;align-items:baseline;gap:6px;cursor:pointer;padding:5px 15px;font-size:12.5px}
.plz{font-size:13px}
.pll{padding-left:30px;color:var(--body)}
.plz:hover,.pll:hover{background:var(--panel)}
.plz.on,.pll.on{background:var(--blue);color:#fff}
.plz.on .chip,.pll.on .chip,.plz.on .pill,.pll.on .pill{border-color:rgba(255,255,255,.6);color:#fff}
.plnums{margin-left:auto;font-family:var(--mono);font-size:11.5px;color:var(--mute)}
.plz.on .plnums,.pll.on .plnums{color:#fff}
.pltabs{display:flex;flex-wrap:wrap;gap:0;border-bottom:1px solid var(--line3);padding:0 15px}
.pltab{appearance:none;border:none;background:none;color:var(--body);font-size:13px;padding:11px 14px;cursor:pointer;min-height:auto;border-bottom:2px solid transparent}
.pltab:hover{background:var(--panel);color:var(--ink)}
.pltab.on{color:var(--ink);font-weight:600;border-bottom-color:var(--blue);background:none}
.plbar{padding:14px 15px 4px;display:flex;flex-wrap:wrap;gap:8px;align-items:center}
.plbar input,.plbar select{min-height:38px}
.pltk{width:26px;padding-right:0}
.plcl{min-width:150px}
.plact{white-space:nowrap;text-align:right}
.plact .btn{margin-left:4px}
.plrt{white-space:nowrap}
.plsub{margin:-4px 15px 0;color:var(--mute);font-size:13px}
.plh{margin:16px 15px 4px;font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:var(--mute)}
.plform{margin:12px 15px;padding:14px;border:1px solid var(--blue);background:var(--panel)}
.plform h4{margin:0 0 8px;font-family:var(--serif);font-weight:400;font-size:16px;text-transform:none;letter-spacing:0;color:var(--ink);padding:0}
@media(max-width:900px){.plwrap{grid-template-columns:1fr}.pltree{max-height:300px}}
$NEWCSS$;
  v_anchor constant text := 'tr.warnrow td{background:var(--gold-bg)}' || chr(10);
  v_mark   text;
  v_before int;
  v_after  int;
begin
  select html into v_html from app_page where slug = 'app' for update;
  if v_html is null then raise exception 'no app_page row'; end if;
  v_before := length(v_html);

  -- the block to replace, found by its two ends, each of which must be unique
  if (select count(*) from regexp_matches(v_html, 'async function vCoverage\(\)', 'g')) <> 1 then
    raise exception 'vCoverage marker is not unique';
  end if;
  if (select count(*) from regexp_matches(v_html, '/\* People, again', 'g')) <> 1 then
    raise exception 'People marker is not unique';
  end if;
  v_a := position('async function vCoverage()' in v_html);
  v_b := position('/* People, again' in v_html);
  if v_a = 0 or v_b = 0 or v_b <= v_a then
    raise exception 'markers missing or out of order: a=% b=%', v_a, v_b;
  end if;
  if position('.plwrap{' in v_html) > 0 then
    raise exception 'the new screen is already spliced in';
  end if;
  if position(v_anchor in v_html) = 0 then
    raise exception 'the CSS anchor is gone';
  end if;

  v_html := substr(v_html, 1, v_a - 1) || v_js || substr(v_html, v_b);
  v_html := replace(v_html, v_anchor, v_anchor || v_css);

  -- what must be true afterwards
  if position('async function vCoverage()' in v_html) = 0 then
    raise exception 'the router entry point did not survive';
  end if;
  foreach v_mark in array array['function covPanel(', 'function clientTable(',
                                  'function handlerCell(', 'function parentPicker(',
                                  'function placePicker('] loop
    if position(v_mark in v_html) > 0 then
      raise exception 'the old screen left % behind', v_mark;
    end if;
  end loop;
  foreach v_mark in array array['function plDetail(', 'function plPeopleTab(',
                                  'function plBranchTab(', 'function plRatesTab(',
                                  'function plClientsTab(', '.plwrap{', '.plsub{',
                                  '.plact{', 'ops("/places'] loop
    if position(v_mark in v_html) = 0 then
      raise exception 'the new screen is missing %', v_mark;
    end if;
  end loop;

  update app_page set html = v_html, updated_at = now() where slug = 'app';
  v_after := length(v_html);
  raise notice 'app_page: % -> % bytes (% js, % css)',
    v_before, v_after, length(v_js), length(v_css);
end
$mig$;

-- ---------------------------------------------------------------------------
-- 157b. The splice above was bounded by 'async function vCoverage()', which is
-- the first function of the old screen but not its first byte: its banner
-- comment and its one module-level variable sat above the cut and survived.
-- covOpts is referenced exactly once in the whole page -- its own declaration.

do $mig$
declare
  v_html text;
  v_dead text := '/* --------------------------------------------------- coverage & handlers
   Who covers which client, where -- and the place you change it. Assigning
   somebody writes one coverage rule per branch of that client at that
   location; the screen never says so, because the work is talked about as
   "Aniket covers BOM in Mumbai", not as 381 rules.                        */
var covOpts = null;
';
  v_before int;
begin
  select html into v_html from app_page where slug = 'app' for update;
  v_before := length(v_html);
  if position(v_dead in v_html) = 0 then
    raise exception 'the dead header is not there as written';
  end if;
  if (select count(*) from regexp_matches(v_html, '\mcovOpts\M', 'g')) <> 1 then
    raise exception 'covOpts is used somewhere, so it is not dead';
  end if;
  v_html := replace(v_html, v_dead, '');
  if (select count(*) from regexp_matches(v_html, '\mcovOpts\M', 'g')) <> 0 then
    raise exception 'covOpts survived';
  end if;
  if position('/* ==================================================================== places' in v_html) = 0 then
    raise exception 'the new banner went with it';
  end if;
  update app_page set html = v_html, updated_at = now() where slug = 'app';
  raise notice 'app_page: % -> % bytes', v_before, length(v_html);
end
$mig$;

-- ---------------------------------------------------------------------------
-- 157c. Same cause, second casualty: the 150-era banner for this screen, which
-- described a scope two migrations out of date and was sitting directly on top
-- of the banner that replaced it.

do $mig$
declare
  v_html text;
  v_dead text := $D$/* ==================================================================== places
   Places, coverage & owners.

   The design's screen is "Coverage, owners & rates"; the tool had drifted to a
   screen that showed only the second half of the question. The owner's
   instruction closes the rest: the operating grouping was editable on Settings
   but a location could not be MOVED to the right zone, the cities the
   geography tree knows were shown nowhere at all, and the handlers lived on a
   third screen. Three places to look and no way to see that they disagreed --
   which is how a rate for "Kolkata" came to price a different place from the
   branch for "Kolkata".

   So this is one screen: where the work is, who handles it, which cities
   answer to it, and what a file may call it. The Settings copy is gone.   */
$D$;
  v_before int;
  v_n int;
begin
  select html into v_html from app_page where slug = 'app' for update;
  v_before := length(v_html);
  v_n := (length(v_html) - length(replace(v_html, v_dead, ''))) / length(v_dead);
  if v_n <> 1 then
    raise exception 'the stale banner appears % times, expected once', v_n;
  end if;
  v_html := replace(v_html, v_dead, '');
  if position('One screen for the whole question of where the work is' in v_html) = 0 then
    raise exception 'the live banner went with it';
  end if;
  if position('async function vCoverage()' in v_html) = 0 then
    raise exception 'the entry point went with it';
  end if;
  update app_page set html = v_html, updated_at = now() where slug = 'app';
  raise notice 'app_page: % -> % bytes, removed %', v_before, length(v_html), length(v_dead);
end
$mig$;
