/* --------------------------------------------------- coverage & handlers
   Who covers which client, where — and the place you change it. Assigning
   somebody writes one coverage rule per branch of that client at that
   location; the screen never says so, because the work is talked about as
   "Aniket covers BOM in Mumbai", not as 381 rules.                        */
var covOpts = null;
async function vCoverage(){
  var d = await api("/coverage");
  if (d.error) {
    el("view").innerHTML = "<h1>Coverage &amp; handlers</h1>" +
      msg("bad", d.reason || d.error); return;
  }
  if (!covOpts) covOpts = await api("/coverage/options");
  var rows = d.rows || [];
  var byLoc = {};
  rows.forEach(function(x){ (byLoc[x.location] = byLoc[x.location] || []).push(x); });
  var names = Object.keys(byLoc).sort();

  var nBranch = 0, nCovered = 0, nPairs = rows.length, nOpen = 0;
  rows.forEach(function(x){
    nBranch += Number(x.branches || 0);
    if ((x.handlers || []).length) nCovered += Number(x.branches || 0); else nOpen++;
  });

  var head =
    '<div class="page-head"><div><h1>Coverage &amp; handlers</h1>' +
    '<p class="mute">Every location, every client that has a branch there, and ' +
    'who handles it. ' + esc(nCovered) + ' of ' + esc(nBranch) + ' branches are ' +
    'covered across ' + esc(nPairs) + ' client-and-location pairs' +
    (nOpen ? '; <b>' + esc(nOpen) + '</b> pairs have nobody on them.' : '.') +
    '</p></div></div>' +
    (d.mayAssign ? '' : msg("warn",
      "You can see coverage here but not change it. Operations and the administrator assign it.")) +
    '<div id="covmsg"></div><div id="covpanel"></div>';

  var cards = names.map(function(loc){
    var list = byLoc[loc];
    var zone = list[0].zone;
    var open = list.filter(function(x){ return !(x.handlers || []).length; }).length;
    return '<div class="card"><h2>' + esc(loc) +
      (zone ? ' <span class="chip">' + esc(zone) + '</span>' : '') +
      (open ? ' <span class="pill warn">' + esc(open) + ' unassigned</span>' : '') +
      '</h2><div class="scroll"><table>' +
      '<tr><th>Client</th><th>Branches</th><th>Handler</th><th>Product</th>' +
      '<th>From</th><th></th></tr>' +
      list.map(function(x){
        var hs = x.handlers || [];
        var who = hs.length ? hs.map(function(h){
            return esc(h.name) + ' <span class="mute">' + esc(h.employee_no || "") +
              (h.chair ? ' · ' + esc(h.chair) : '') + ' · ' +
              esc(h.branches) + (Number(h.branches) === 1 ? ' branch' : ' branches') +
              '</span>';
          }).join('<br>') : '<span class="mute">nobody</span>';
        var prod = hs.map(function(h){ return h.product || ""; })
          .filter(function(v, i, a){ return v && a.indexOf(v) === i; }).join(", ");
        var from = hs.length && hs[0].from ? day(hs[0].from) : "";
        var btn = d.mayAssign
          ? '<button class="btn" data-covassign="1" data-loc="' + esc(x.location_id) +
              '" data-locname="' + esc(x.location) + '" data-client="' + esc(x.client_id) +
              '" data-clientname="' + esc(x.client) + '">Assign</button>' +
            hs.map(function(h){
              return ' <button class="btn" data-covend="1" data-loc="' + esc(x.location_id) +
                '" data-client="' + esc(x.client_id) + '" data-person="' + esc(h.person_id) +
                '" data-personname="' + esc(h.name) + '" data-clientname="' + esc(x.client) +
                '" data-locname="' + esc(x.location) + '">End ' + esc(h.name.split(" ")[0]) +
                '</button>';
            }).join("")
          : '';
        return '<tr><td>' + esc(x.client) + '</td><td>' + esc(x.branches) + '</td><td>' + who +
          '</td><td>' + esc(prod) + '</td><td>' + esc(from) + '</td><td>' + btn + '</td></tr>';
      }).join("") + '</table></div></div>';
  }).join("");

  el("view").innerHTML = head +
    (names.length ? cards : '<div class="card"><div class="empty">' +
      'No branch sits at a location yet. Load Clients and branches under Data setup.' +
      '</div></div>');

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-covassign]"), function(b){
    b.onclick = function(){ covPanel(b); };
  });
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-covend]"), function(b){
    b.onclick = async function(){
      if (!confirm("End " + b.getAttribute("data-personname") + " on " +
        b.getAttribute("data-clientname") + " at " + b.getAttribute("data-locname") +
        "?\n\nThe rules are dated to today, never deleted — who covered what last " +
        "month is how an escalation is argued about later.")) return;
      b.disabled = true;
      var out = await api("/coverage/end", { method:"POST", body:{
        locationId: b.getAttribute("data-loc"),
        clientId:   b.getAttribute("data-client"),
        personId:   b.getAttribute("data-person") } });
      b.disabled = false;
      if (out.error) { el("covmsg").innerHTML = msg("bad", out.reason || out.error); return; }
      el("covmsg").innerHTML = msg("ok", out.branches + " branches released.");
      vCoverage();
    };
  });
}

/* The picker. 636 people and nobody can hold an employee number in their
   head — which is the whole reason the spreadsheet did not work — so the
   list is names, with the number and the chair beside each one.          */
function covPanel(b){
  var people = (covOpts && covOpts.people) || [];
  var products = (covOpts && covOpts.products) || [];
  var loc = b.getAttribute("data-loc"), client = b.getAttribute("data-client");
  el("covpanel").innerHTML =
    '<div class="card"><h2>Assign a handler</h2>' +
    '<p class="mute">' + esc(b.getAttribute("data-clientname")) + ' at ' +
      esc(b.getAttribute("data-locname")) + '. Every active branch of that client ' +
      'at that location is covered by this, and anything they already cover is ' +
      'left alone.</p>' +
    '<label>Who<br><select id="covwho">' +
      people.map(function(p){
        return '<option value="' + esc(p.id) + '">' + esc(p.full_name) +
          ' — ' + esc(p.employee_no || "no number") +
          (p.chair ? ' — ' + esc(p.chair) : '') + '</option>';
      }).join("") + '</select></label> ' +
    '<label>Product<br><input id="covprod" list="covprods" placeholder="optional">' +
      '<datalist id="covprods">' +
      products.map(function(p){ return '<option value="' + esc(p.product || p) + '">'; }).join("") +
      '</datalist></label> ' +
    '<label>Effective from<br><input id="covfrom" type="date"></label> ' +
    '<button class="btn primary" id="covgo">Assign</button> ' +
    '<button class="btn" id="covcancel">Cancel</button>' +
    '<div id="covpanelmsg"></div></div>';
  el("covpanel").scrollIntoView({ behavior:"smooth", block:"nearest" });
  el("covcancel").onclick = function(){ el("covpanel").innerHTML = ""; };
  el("covgo").onclick = async function(){
    el("covgo").disabled = true;
    var out = await api("/coverage", { method:"POST", body:{
      locationId: loc, clientId: client,
      personId: el("covwho").value,
      product: el("covprod").value,
      effectiveFrom: el("covfrom").value || null } });
    el("covgo").disabled = false;
    if (out.error) {
      el("covpanelmsg").innerHTML = msg("bad", out.reason || out.error); return;
    }
    el("covpanel").innerHTML = "";
    el("covmsg").innerHTML = msg("ok", out.branches
      ? out.branches + " branches assigned."
      : "Nothing to do — they already covered every branch there.");
    vCoverage();
  };
}
