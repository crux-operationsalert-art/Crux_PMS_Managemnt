/* ------------------------------------------------------------- clients
   The design's screen: a rail of clients opening into the locations they
   have branches at, the client default matrix, the branches at the chosen
   location, and under any branch its full record.

   The panels the design shows that have nothing behind them yet -- the
   performance strip, visits, the RAG reason -- say what would fill them
   rather than showing a made-up number. An empty panel with a reason is
   the contract this app already keeps everywhere else.                  */
var clState = { clients: null, clientId: null, locationId: null, branchId: null, adding: false };

async function vClients(){
  if (!clState.clients) {
    var d = await api("/clients");
    if (d.error) {
      el("view").innerHTML = "<h1>Clients</h1>" + msg("bad", d.reason || d.error); return;
    }
    clState.clients = d.clients || [];
    clState.mayEdit = !!d.mayEdit;
  }
  var cs = clState.clients;
  if (!clState.clientId && cs.length) clState.clientId = cs[0].id;
  var client = cs.filter(function(c){ return c.id === clState.clientId; })[0] || null;
  var locs = client ? (client.locations || []) : [];
  if (client && !locs.filter(function(l){ return l.id === clState.locationId; }).length) {
    clState.locationId = locs.length ? locs[0].id : null;
  }
  var loc = locs.filter(function(l){ return l.id === clState.locationId; })[0] || null;

  var totalB = cs.reduce(function(s,c){ return s + Number(c.active_branches||0); }, 0);

  el("view").innerHTML =
    '<div class="page-head"><div><h1>Clients</h1>' +
    '<p class="mute">' + esc(cs.length) + ' clients, ' + esc(totalB) + ' active branches. ' +
    'Pick a client, then a location; the branches at that location are below. ' +
    'A branch takes its client, zone and region from the location, so none of ' +
    'those are ever asked for twice.</p></div>' +
    (clState.mayEdit && loc
      ? '<div><button class="btn primary" id="clAdd">Add a branch</button></div>' : '') +
    '</div><div id="clmsg"></div>' +

    '<div class="card"><h2>Client &middot; location</h2>' +
      (cs.length ? cs.map(function(c){
        var on = c.id === clState.clientId;
        return '<div class="opgrp"><div class="node">' +
          '<button class="btn' + (on ? ' primary' : '') + '" data-cl="'+esc(c.id)+'">' +
            esc(c.name) + '</button> ' +
          '<span class="mute">' + esc(c.code) + ' &middot; ' +
            esc(c.active_branches) + ' active' +
            (Number(c.branches) !== Number(c.active_branches)
              ? ' of ' + esc(c.branches) : '') + ' &middot; ' +
            esc((c.locations||[]).length) + ' locations' +
            (Number(c.default_levels) ? '' : ' &middot; no default matrix') +
          '</span></div>' +
          (on ? '<div class="opzone">' + (c.locations||[]).map(function(l){
              return '<button class="btn' + (l.id === clState.locationId ? ' primary' : '') +
                '" data-clloc="'+esc(l.id)+'">' + esc(l.name) +
                ' <span class="chip">' + esc(l.active) + '</span></button> ';
            }).join("") + '</div>' : '') +
        '</div>';
      }).join("") : '<div class="empty">No client has a branch you can see.</div>') +
    '</div>' +

    '<div id="clnew"></div><div id="clmatrix"></div><div id="clbranches"></div>';

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-cl]"), function(b){
    b.onclick = function(){
      clState.clientId = b.getAttribute("data-cl");
      clState.locationId = null; clState.branchId = null; clState.adding = false;
      vClients();
    };
  });
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-clloc]"), function(b){
    b.onclick = function(){
      clState.locationId = b.getAttribute("data-clloc");
      clState.branchId = null; clState.adding = false;
      vClients();
    };
  });
  if (el("clAdd")) el("clAdd").onclick = function(){ clNewBranch(client, loc); };

  if (client) clMatrix(client);
  if (client && loc) clBranches(client, loc);
}

async function clMatrix(client){
  var d = await api("/clients/" + encodeURIComponent(client.id) + "/matrix");
  if (d.error) { el("clmatrix").innerHTML = msg("bad", d.reason || d.error); return; }
  var lv = d.levels || [];
  el("clmatrix").innerHTML =
    '<div class="card"><h2>Client default matrix</h2>' +
    '<p class="mute">Used by any branch that has not entered its own. ' +
      (d.inheritCount
        ? esc(d.inheritCount) + ' active ' +
          (Number(d.inheritCount) === 1 ? 'branch inherits it' : 'branches inherit it') + '.'
        : 'Every active branch has its own.') +
      ' <b>' + esc(lv.length) + ' of 5 set.</b></p>' +
    (lv.length
      ? '<div class="scroll"><table><tr><th>Level</th><th>Role</th><th>Who</th>' +
        '<th>Mobile</th><th>E-mail</th></tr>' +
        lv.map(function(x){
          return '<tr><td>' + esc(x.level) + '</td><td>' + esc(x.level_name||"") + '</td>' +
            '<td>' + esc(x.name||"-") + '</td><td>' + esc(x.mobile||"") + '</td>' +
            '<td>' + esc(x.email||"") + '</td></tr>';
        }).join("") + '</table></div>'
      : '<div class="empty">This client has no default matrix. Every branch of it ' +
        'has to carry all five levels of its own, or escalations have nowhere to go.</div>') +
    '</div>';
}

async function clBranches(client, loc){
  el("clbranches").innerHTML = '<div class="card"><p class="mute">Loading branches...</p></div>';
  var d = await api("/clients/" + encodeURIComponent(client.id) +
                    "/location/" + encodeURIComponent(loc.id));
  if (d.error) { el("clbranches").innerHTML = msg("bad", d.reason || d.error); return; }
  var bs = d.branches || [];
  var done = bs.filter(function(b){ return Number(b.complete_levels) === 5; }).length;

  el("clbranches").innerHTML =
    '<div class="card"><h2>' + esc(loc.name) + ' &middot; branches</h2>' +
    '<p class="mute">' + esc(bs.length) + ' branches, ' + esc(done) +
      ' with all five escalation levels. A branch with fewer than five cannot be ' +
      'dispatched to -- the level that is missing is where an escalation would stop.</p>' +
    (bs.length
      ? '<div class="scroll"><table>' +
        '<tr><th>Branch</th><th>Code</th><th>Branch manager</th><th>Crux owner</th>' +
        '<th>Matrix</th></tr>' +
        bs.map(function(b){
          var pill = Number(b.complete_levels) === 5
            ? '<span class="pill ok">5 of 5</span>'
            : '<span class="pill warn">' + esc(b.complete_levels) + ' of 5</span>';
          return '<tr><td><button class="btn" data-clb="'+esc(b.id)+'">' + esc(b.name) +
              '</button>' + (b.status === 'ACTIVE' ? '' : ' <span class="chip">inactive</span>') +
              '</td><td>' + esc(b.code) + '</td>' +
            '<td>' + esc(b.manager || "-") + '</td>' +
            '<td>' + esc(b.owner || "-") + '</td>' +
            '<td>' + pill + '</td></tr>' +
            (clState.branchId === b.id
              ? '<tr><td colspan="5"><div id="clrec"></div></td></tr>' : '');
        }).join("") + '</table></div>'
      : '<div class="empty">No branch of this client at this location.</div>') +
    '</div>';

  Array.prototype.forEach.call(el("clbranches").querySelectorAll("[data-clb]"), function(b){
    b.onclick = function(){
      var id = b.getAttribute("data-clb");
      clState.branchId = (clState.branchId === id) ? null : id;
      clBranches(client, loc).then(function(){
        if (clState.branchId) clRecord(clState.branchId);
      });
    };
  });
  if (clState.branchId) clRecord(clState.branchId);
}

/* The full record, in the design's order: the matrix first, because that is
   what an escalation walks; then the two people; then the panels that are
   waiting on data, each saying what it is waiting for.                    */
async function clRecord(branchId){
  if (!el("clrec")) return;
  el("clrec").innerHTML = '<p class="mute">Loading the record...</p>';
  var d = await api("/clients/branch/" + encodeURIComponent(branchId));
  if (d.error) { el("clrec").innerHTML = msg("bad", d.reason || d.error); return; }
  var b = d.branch, lv = d.levels || [], ct = d.contacts || [], ow = d.owners || [];
  function who(role){
    var x = ct.filter(function(c){ return c.role === role; })[0];
    return x ? (esc(x.name) + (x.mobile || x.email
      ? ' <span class="mute">' + esc([x.mobile, x.email].filter(Boolean).join(" &middot; ")) + '</span>'
      : '')) : '<span class="mute">nobody recorded</span>';
  }
  el("clrec").innerHTML =
    '<div class="card"><h3>' + esc(b.name) + ' &middot; full record</h3>' +
    '<p class="mute">' + esc(b.client) + ' &middot; ' + esc(b.code) + ' &middot; ' +
      esc(b.location || "") + (b.zone ? ' &middot; ' + esc(b.zone) : '') +
      (b.opened_on ? ' &middot; on the master since ' + esc(day(b.opened_on)) : '') + '</p>' +

    '<h4>Escalation matrix</h4>' +
    (lv.length
      ? '<div class="scroll"><table><tr><th>Level</th><th>Role</th><th>Who</th>' +
        '<th>Mobile</th><th>E-mail</th><th>Source</th></tr>' +
        lv.map(function(x){
          return '<tr><td>' + esc(x.level) + '</td><td>' + esc(x.level_name||"") + '</td>' +
            '<td>' + esc(x.name||"-") + '</td><td>' + esc(x.mobile||"") + '</td>' +
            '<td>' + esc(x.email||"") + '</td><td>' +
            (x.inherited ? '<span class="chip">from the client</span>'
                         : '<span class="chip ok">its own</span>') + '</td></tr>';
        }).join("") + '</table></div>'
      : '<div class="empty">No level is set, and this client has no default to fall ' +
        'back on. An escalation raised here has nowhere to go.</div>') +

    '<h4>The people</h4>' +
    '<div class="cfgrow"><div><b>Branch manager</b><div>' + who('BRANCH_MANAGER') + '</div></div></div>' +
    '<div class="cfgrow"><div><b>Crux point of contact</b><div>' + who('CRUX_POC') + '</div></div></div>' +
    '<div class="cfgrow"><div><b>Crux owner</b><div>' +
      (ow.length ? ow.map(function(o){
          return esc(o.full_name) + ' <span class="mute">' + esc(o.employee_no||"") +
            (o.chair ? ' &middot; ' + esc(o.chair) : '') +
            (o.product ? ' &middot; ' + esc(o.product) : '') + '</span>';
        }).join('<br>')
        : '<span class="mute">nobody covers this branch. Assign it under Coverage &amp; handlers.</span>') +
      '</div></div></div>' +
    (b.address ? '<div class="cfgrow"><div><b>Address</b><div class="mute">' +
        esc(b.address) + '</div></div></div>' : '') +

    '<h4>Performance at this branch</h4>' +
    '<div class="empty">' + esc(d.notYet.performance) + '</div>' +
    '<h4>Visits</h4>' +
    '<div class="empty">' + esc(d.notYet.visits) + '</div>' +
    '<h4>RAG</h4>' +
    '<div class="empty">' + esc(d.notYet.rag) + '</div>' +

    (d.mayEdit ? '<button class="btn" id="cledit">Edit these details</button>' : '') +
    '<div id="cleditbox"></div></div>';

  if (el("cledit")) el("cledit").onclick = function(){ clEdit(b, ct); };
}

function clEdit(b, ct){
  function val(role, f){
    var x = ct.filter(function(c){ return c.role === role; })[0];
    return x && x[f] ? x[f] : "";
  }
  el("cleditbox").innerHTML =
    '<div class="card"><h3>Edit ' + esc(b.name) + '</h3>' +
    '<p class="mute">The name and address of the branch, and the two people on it. ' +
    'Replacing a person retires the old row rather than overwriting it, so who was ' +
    'the manager in March is still answerable later.</p>' +
    '<label>Branch name<br><input id="ceName" value="' + esc(b.name) + '"></label> ' +
    '<label>Address<br><input id="ceAddr" value="' + esc(b.address||"") + '"></label><br>' +
    '<label>Branch manager<br><input id="ceBm" value="' + esc(val('BRANCH_MANAGER','name')) + '"></label> ' +
    '<label>Mobile<br><input id="ceBmM" value="' + esc(val('BRANCH_MANAGER','mobile')) + '"></label> ' +
    '<label>E-mail<br><input id="ceBmE" value="' + esc(val('BRANCH_MANAGER','email')) + '"></label><br>' +
    '<label>Crux point of contact<br><input id="cePoc" value="' + esc(val('CRUX_POC','name')) + '"></label> ' +
    '<label>Mobile<br><input id="cePocM" value="' + esc(val('CRUX_POC','mobile')) + '"></label> ' +
    '<label>E-mail<br><input id="cePocE" value="' + esc(val('CRUX_POC','email')) + '"></label><br>' +
    '<button class="btn primary" id="ceGo">Save</button> ' +
    '<button class="btn" id="ceCancel">Cancel</button><div id="cemsg"></div></div>';
  el("ceCancel").onclick = function(){ el("cleditbox").innerHTML = ""; };
  el("ceGo").onclick = async function(){
    el("ceGo").disabled = true;
    var out = await api("/clients/branch/" + encodeURIComponent(b.id), { method:"PUT", body:{
      name: el("ceName").value, address: el("ceAddr").value,
      manager: { name: el("ceBm").value, mobile: el("ceBmM").value, email: el("ceBmE").value },
      poc:     { name: el("cePoc").value, mobile: el("cePocM").value, email: el("cePocE").value } } });
    el("ceGo").disabled = false;
    if (out.error) { el("cemsg").innerHTML = msg("bad", out.reason || out.error); return; }
    el("cleditbox").innerHTML = "";
    clState.clients = null;
    el("clmsg").innerHTML = msg("ok", "Saved.");
    vClients();
  };
}

function clNewBranch(client, loc){
  el("clnew").innerHTML =
    '<div class="card"><h2>New branch under ' + esc(loc.name) + '</h2>' +
    '<label>Branch name<br><input id="nbName"></label> ' +
    '<label>Branch code<br><input id="nbCode"></label> ' +
    '<label>Address<br><input id="nbAddr"></label><br>' +
    '<label>Branch manager<br><input id="nbBm"></label> ' +
    '<label>Mobile<br><input id="nbBmM"></label> ' +
    '<label>E-mail<br><input id="nbBmE"></label><br>' +
    '<button class="btn primary" id="nbGo">Save branch</button> ' +
    '<button class="btn" id="nbCancel">Cancel</button>' +
    '<p class="mute">Client, zone and region come from the location -- they are ' +
    'never asked again. The branch inherits ' + esc(client.name) + '&rsquo;s default ' +
    'matrix until it is given one of its own.</p><div id="nbmsg"></div></div>';
  el("nbCancel").onclick = function(){ el("clnew").innerHTML = ""; };
  el("nbGo").onclick = async function(){
    el("nbGo").disabled = true;
    var out = await api("/clients/branch", { method:"POST", body:{
      clientId: client.id, locationId: loc.id,
      name: el("nbName").value, code: el("nbCode").value, address: el("nbAddr").value,
      managerName: el("nbBm").value, managerMobile: el("nbBmM").value,
      managerEmail: el("nbBmE").value } });
    el("nbGo").disabled = false;
    if (out.error) { el("nbmsg").innerHTML = msg("bad", out.reason || out.error); return; }
    el("clnew").innerHTML = "";
    clState.clients = null;
    el("clmsg").innerHTML = msg("ok", out.name + " added.");
    vClients();
  };
}
/* ------------------------------------------------- history & audit trail
   Every write in this tool goes through one transaction helper, and that
   helper cannot commit an audit row without the change it describes. So
   this is not a log somebody remembered to write: it is the same
   transaction. That is why it can be shown as evidence.                  */
var hstAction = "";
async function vHistory(){
  var q = "/history?limit=300" + (hstAction ? "&action=" + encodeURIComponent(hstAction) : "");
  var d = await api(q);
  if (d.error) {
    el("view").innerHTML = "<h1>History</h1>" + msg("bad", d.reason || d.error); return;
  }
  var rows = d.rows || [], kinds = d.kinds || [];

  function detail(x){
    function pick(v){
      if (!v) return "";
      try { var o = (typeof v === "string") ? JSON.parse(v) : v;
            return Object.keys(o).slice(0,4).map(function(k){
              var val = o[k];
              if (val && typeof val === "object") val = JSON.stringify(val).slice(0,40);
              return k + " " + String(val === null ? "-" : val).slice(0,40);
            }).join(", ");
      } catch(e){ return String(v).slice(0,80); }
    }
    var a = pick(x.old_value), b = pick(x.new_value);
    return a && b ? esc(a) + ' &rarr; ' + esc(b) : esc(b || a || "");
  }

  el("view").innerHTML =
    '<div class="page-head"><div><h1>History &amp; audit trail</h1>' +
    '<p class="mute">' + esc(rows.length) + ' entries' +
      (d.mine && !d.isAdmin ? ' that you made' : '') +
      '. Every one of them was written inside the transaction that made the ' +
      'change, so nothing here can describe something that did not happen, and ' +
      'nothing that happened is missing.</p></div></div>' +
    '<div class="card"><h2>What kind</h2>' +
      '<button class="btn' + (hstAction ? '' : ' primary') + '" data-hst="">Everything</button> ' +
      kinds.map(function(k){
        return '<button class="btn' + (hstAction === k.action ? ' primary' : '') +
          '" data-hst="' + esc(k.action) + '">' + esc(k.action) +
          ' <span class="chip">' + esc(k.n) + '</span></button> ';
      }).join("") +
    '</div>' +
    '<div class="card"><h2>What happened</h2>' +
      (rows.length
        ? '<div class="scroll"><table>' +
          '<tr><th>When</th><th>Who</th><th>What</th><th>To what</th><th>Detail</th></tr>' +
          rows.map(function(x){
            return '<tr><td>' + esc(when(x.at)) + '</td>' +
              '<td>' + esc(x.actor || "the tool itself") +
                (x.employee_no ? ' <span class="mute">' + esc(x.employee_no) + '</span>' : '') + '</td>' +
              '<td>' + esc(x.action) + '</td>' +
              '<td>' + esc(x.entity_type || "") +
                (x.entity_ref ? ' <span class="mute">' + esc(x.entity_ref) + '</span>' : '') + '</td>' +
              '<td class="mute">' + detail(x) + '</td></tr>';
          }).join("") + '</table></div>'
        : '<div class="empty">Nothing matches that.</div>') +
    '</div>';

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-hst]"), function(b){
    b.onclick = function(){ hstAction = b.getAttribute("data-hst"); vHistory(); };
  });
}
