/* ==================================================================== places
   Places, coverage & owners.

   The design's screen is "Coverage, owners & rates"; the tool had drifted to a
   screen that showed only the second half of the question. The
   owner's instruction closes the rest: the operating grouping was editable on
   Settings but a location could not be MOVED to the right zone, the cities the
   geography tree knows were shown nowhere at all, and the handlers lived on a
   third screen. Three places to look and no way to see that they disagreed --
   which is how a rate for "Kolkata" came to price a different place from the
   branch for "Kolkata".

   So this is one screen: where the work is, who handles it, which cities
   answer to it, and what a file may call it. The Settings copy is gone.   */
async function vCoverage(){
  var d = await ops("/places");
  if (d.error) {
    el("view").innerHTML = "<h1>Places, coverage &amp; owners</h1>" +
      msg("bad", d.reason || d.error); return;
  }
  if (!covOpts) covOpts = await ops("/places/handlers");

  var groups = d.groups || [], cities = d.cities || [], aliases = d.aliases || [];
  var places = d.places || [];

  var nBranch = 0, nUnassigned = 0, nLoc = 0, nPairs = 0;
  groups.forEach(function(g){ (g.zones || []).forEach(function(z){
    (z.locations || []).forEach(function(l){
      nLoc++; nBranch += Number(l.branches || 0);
      nUnassigned += Number(l.unassigned || 0);
      nPairs += (l.clients || []).length;
    });
  }); });

  /* ------------------------------------------------ a place you can move to */
  function parentPicker(node, level, currentId){
    var want = level === "LOCATION" ? "ZONE" : "GROUP";
    var opts = places.filter(function(p){ return p.level === want; });
    if (!opts.length) return "";
    return '<select class="mv" data-opmove="' + esc(node.id) + '" ' +
      'data-opmovename="' + esc(node.name) + '">' +
      opts.map(function(p){
        return '<option value="' + esc(p.id) + '"' +
          (p.id === currentId ? ' selected' : '') + '>' + esc(p.name) + '</option>';
      }).join("") + '</select>';
  }

  function handlerCell(x){
    var hs = x.handlers || [];
    if (!hs.length) return '<span class="mute">nobody</span>';
    return hs.map(function(h){
      return esc(h.name) + ' <span class="mute">' + esc(h.employeeNo || "") +
        (h.chair ? ' &middot; ' + esc(h.chair) : '') + ' &middot; ' +
        esc(h.branches) + (Number(h.branches) === 1 ? ' branch' : ' branches') +
        (h.product ? ' &middot; ' + esc(h.product) : '') + '</span>';
    }).join('<br>');
  }

  function clientTable(l){
    var list = l.clients || [];
    if (!list.length) {
      return '<div class="empty">No active client has a branch here yet.</div>';
    }
    return '<div class="scroll"><table>' +
      '<tr><th>Client</th><th>Branches</th><th>Handler</th><th>From</th><th></th></tr>' +
      list.map(function(x){
        var hs = x.handlers || [];
        var from = hs.length && hs[0].from ? day(hs[0].from) : "";
        var btn = d.mayAssign
          ? '<button class="btn" data-covassign="1" data-loc="' + esc(l.id) +
              '" data-locname="' + esc(l.name) + '" data-client="' + esc(x.clientId) +
              '" data-clientname="' + esc(x.name) + '">Assign</button>' +
            hs.map(function(h){
              return ' <button class="btn" data-covend="1" data-loc="' + esc(l.id) +
                '" data-client="' + esc(x.clientId) + '" data-person="' + esc(h.personId) +
                '" data-personname="' + esc(h.name) + '" data-clientname="' + esc(x.name) +
                '" data-locname="' + esc(l.name) + '">End ' +
                esc(String(h.name).split(" ")[0]) + '</button>';
            }).join("")
          : '';
        return '<tr><td>' + esc(x.name) + ' <span class="mute">' + esc(x.code) +
          '</span></td><td class="num">' + esc(x.branches) + '</td><td>' +
          handlerCell(x) + '</td><td>' + esc(from) + '</td><td>' + btn + '</td></tr>';
      }).join("") + '</table></div>';
  }

  var tree = groups.map(function(g){
    return '<div class="card"><h2>' + esc(g.name) +
      (g.active ? '' : ' <span class="chip">off</span>') +
      (d.mayEdit ? ' <button class="btn" data-opadd="' + esc(g.id) +
        '" data-opwhat="zone">Add a zone</button>' : '') + '</h2>' +
      (g.zones || []).map(function(z){
        return '<div class="opzone"><h3>' + esc(z.name) +
          (z.active ? '' : ' <span class="chip">off</span>') +
          ' <span class="mute">' + esc(z.branches || 0) + ' branches</span>' +
          ((z.cities || []).length
            ? ' <span class="chip">' + esc(z.cities.length) + ' cities</span>' : '') +
          (d.mayEdit
            ? ' <button class="btn" data-opadd="' + esc(z.id) + '" data-opwhat="location">Add a location</button>' +
              ' <button class="btn" data-opedit="' + esc(z.id) + '" data-opname="' + esc(z.name) + '">Rename</button>' +
              ' <button class="btn" data-opoff="' + esc(z.id) + '" data-opon="' + (z.active ? "1" : "0") + '">' +
              (z.active ? 'Switch off' : 'Switch on') + '</button>' +
              ' <span class="mute">under ' + parentPicker(z, "ZONE", g.id) + '</span>'
            : '') +
          '</h3>' +
          ((z.cities || []).length
            ? '<p class="mute">Cities answering to the zone itself: ' +
              z.cities.map(esc).join(", ") + '</p>' : '') +
          (z.locations || []).map(function(l){
            return '<div class="oploc"><h4>' + esc(l.name) +
              (l.active ? '' : ' <span class="chip">off</span>') +
              ' <span class="mute">' + esc(l.branches || 0) + ' branches</span>' +
              (Number(l.unassigned || 0)
                ? ' <span class="pill warn">' + esc(l.unassigned) + ' unassigned</span>' : '') +
              (d.mayEdit
                ? ' <button class="btn" data-opedit="' + esc(l.id) + '" data-opname="' + esc(l.name) + '">Rename</button>' +
                  ' <button class="btn" data-opoff="' + esc(l.id) + '" data-opon="' + (l.active ? "1" : "0") + '">' +
                  (l.active ? 'Switch off' : 'Switch on') + '</button>' +
                  ' <span class="mute">under ' + parentPicker(l, "LOCATION", z.id) + '</span>'
                : '') +
              '</h4>' +
              ((l.cities || []).length
                ? '<p class="mute">Cities: ' + l.cities.map(esc).join(", ") + '</p>' : '') +
              clientTable(l) + '</div>';
          }).join("") + '</div>';
      }).join("") + '</div>';
  }).join("");

  /* ------------------------------------------------------------- the cities */
  function placePicker(city){
    return '<select data-city="' + esc(city.id) + '">' +
      '<option value="">not aligned</option>' +
      places.map(function(p){
        return '<option value="' + esc(p.id) + '"' +
          (p.name === city.opZone ? ' selected' : '') + '>' +
          esc(p.name) + ' (' + esc(p.level.toLowerCase()) + ')</option>';
      }).join("") + '</select>';
  }
  var cityRows = cities.map(function(c){
    return '<tr' + (c.resolves ? '' : ' class="warnrow"') + '><td>' + esc(c.name) +
      '</td><td class="mute">' + esc(c.level === "STATE" ? "state" : "city") +
      (c.under ? ' in ' + esc(c.under) : '') + '</td><td class="num">' +
      esc(c.branches || 0) + '</td><td>' +
      (d.mayEdit ? placePicker(c)
                 : (c.resolves ? esc(c.resolves) : '<span class="mute">not aligned</span>')) +
      '</td><td class="mute">' +
      (c.opZone && !c.resolves
        ? 'says &ldquo;' + esc(c.opZone) + '&rdquo;, which is no longer a place'
        : (c.resolves ? '' : 'nothing places it')) + '</td></tr>';
  }).join("");

  /* ----------------------------------------------------------- the spellings */
  var aliasRows = aliases.map(function(a){
    return '<tr><td>' + esc(a.writtenAs) + '</td><td>&rarr;</td><td>' +
      esc(a.resolves || a.means) +
      (a.resolves ? '' : ' <span class="pill warn">means nothing now</span>') +
      '</td><td class="mute">' + esc(a.note || "") + '</td><td>' +
      (d.mayEdit ? '<button class="btn" data-alrm="' + esc(a.writtenAs) + '">Remove</button>' : '') +
      '</td></tr>';
  }).join("");

  el("view").innerHTML =
    '<div class="page-head"><div><h1>Places, coverage &amp; owners</h1>' +
    '<p class="mute">Where the work is, who handles it, which cities answer to ' +
    'it, and what a file may call it. One screen, because a rate, a branch and ' +
    'a handler all have to mean the same place by the same name.</p>' +
    '<p class="mute">' + esc(nBranch) + ' branches across ' + esc(nLoc) +
    ' locations and ' + esc(nPairs) + ' client-and-location pairs' +
    (nUnassigned ? '; <b>' + esc(nUnassigned) + '</b> pairs have nobody on them' : '') +
    '. ' + esc(Number(d.unalignedCities || 0)) + ' of ' + esc(cities.length) +
    ' cities are not aligned to an operating zone' +
    (Number(d.unplacedBranches || 0)
      ? '; <b>' + esc(d.unplacedBranches) + '</b> active branches sit at no location at all' : '') +
    '.</p></div></div>' +
    (d.mayEdit ? '' : msg("warn",
      "You can see the grouping here but not change it. The administrator owns it.")) +
    (d.mayAssign ? '' : msg("warn",
      "You can see coverage but not assign it. Operations and the administrator do that.")) +
    '<div id="covmsg"></div><div id="covpanel"></div>' +
    (groups.length ? tree
      : '<div class="card"><div class="empty">' + esc(d.emptyWhy || "") + '</div></div>') +

    '<div class="card"><h2>Cities the geography knows</h2>' +
    '<p class="mute">A city is where a branch physically is. An operating zone ' +
    'is who runs it. They are different trees and this is the only place the ' +
    'link between them is visible — a city aligned to nothing is not an ' +
    'error, it is a question nobody has answered yet.</p>' +
    (cities.length
      ? '<div class="scroll"><table>' +
        '<tr><th>Place</th><th>What</th><th>Branches</th><th>Answers to</th><th></th></tr>' +
        cityRows + '</table></div>'
      : '<div class="empty">The geography tree is empty. Load Geography under Data setup.</div>') +
    '<div id="citymsg"></div></div>' +

    '<div class="card"><h2>Spellings a file may use</h2>' +
    '<p class="mute">What a written form means, when it is not what this tree ' +
    'calls the place. A row here, never a deploy — the next odd spelling an ' +
    'upload meets is added below. A spelling may not shadow a real name.</p>' +
    (aliases.length
      ? '<div class="scroll"><table>' +
        '<tr><th>A file writes</th><th></th><th>It means</th><th>Why</th><th></th></tr>' +
        aliasRows + '</table></div>'
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

  /* ---------------------------------------------------------------- handlers */
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-covassign]"), function(b){
    b.onclick = function(){ covPanel(b); };
  });
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-covend]"), function(b){
    b.onclick = async function(){
      if (!confirm("End " + b.getAttribute("data-personname") + " on " +
        b.getAttribute("data-clientname") + " at " + b.getAttribute("data-locname") +
        "?\n\nThe rules are dated to today, never deleted - who covered what last " +
        "month is how an escalation is argued about later.")) return;
      b.disabled = true;
      var out = await ops("/places/coverage/end", { method:"POST", body:{
        locationId: b.getAttribute("data-loc"),
        clientId:   b.getAttribute("data-client"),
        personId:   b.getAttribute("data-person") } });
      b.disabled = false;
      if (out.error) { el("covmsg").innerHTML = msg("bad", out.reason || out.error); return; }
      el("covmsg").innerHTML = msg("ok", out.branches + " branches released.");
      vCoverage();
    };
  });

  /* ---------------------------------------------------------- the grouping */
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-opadd]"), function(b){
    b.onclick = async function(){
      var what = b.getAttribute("data-opwhat");
      var name = prompt("Name the new " + what + ".", "");
      if (name === null || !name.trim()) return;
      b.disabled = true;
      var out = await ops("/places/node", { method:"POST",
        body:{ name: name.trim(), parentId: b.getAttribute("data-opadd") } });
      b.disabled = false;
      if (out.error) { el("covmsg").innerHTML = msg("bad", out.reason || out.error); return; }
      vCoverage();
    };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-opedit]"), function(b){
    b.onclick = async function(){
      var was = b.getAttribute("data-opname");
      var name = prompt("Rename it. Everything already pointing at it follows " +
        "the new name - it is the same thing, called something else.", was);
      if (name === null || !name.trim() || name.trim() === was) return;
      b.disabled = true;
      var out = await ops("/places/node", { method:"POST",
        body:{ id: b.getAttribute("data-opedit"), name: name.trim() } });
      b.disabled = false;
      if (out.error) { el("covmsg").innerHTML = msg("bad", out.reason || out.error); return; }
      vCoverage();
    };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-opoff]"), function(b){
    b.onclick = async function(){
      var on = b.getAttribute("data-opon") === "1";
      if (on && !confirm("Switch it off? It stops being offered for new " +
        "assignments. Nothing that already names it changes.")) return;
      b.disabled = true;
      var out = await ops("/places/node/retire", { method:"POST",
        body:{ id: b.getAttribute("data-opoff"), active: !on } });
      b.disabled = false;
      if (out.error) { el("covmsg").innerHTML = msg("bad", out.reason || out.error); return; }
      if (out.note) el("covmsg").innerHTML = msg("warn", out.note);
      setTimeout(vCoverage, out.note ? 1600 : 0);
    };
  });

  /* The move. This is the thing that did not work: the old save took a parent
     on an edit and dropped it, so the screen offered a move that never
     happened. It reloads afterwards, because a move changes where the branches
     under it are counted.                                                   */
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-opmove]"), function(s){
    s.dataset.was = s.value;
    s.onchange = async function(){
      var to = s.options[s.selectedIndex].text;
      if (!confirm("Move " + s.getAttribute("data-opmovename") + " under " + to +
        "?\n\nEverything under it moves with it, including its branches.")) {
        s.value = s.dataset.was; return;
      }
      s.disabled = true;
      var out = await ops("/places/node", { method:"POST", body:{
        id: s.getAttribute("data-opmove"),
        name: s.getAttribute("data-opmovename"),
        parentId: s.value } });
      s.disabled = false;
      if (out.error) {
        el("covmsg").innerHTML = msg("bad", out.reason || out.error);
        s.value = s.dataset.was; return;
      }
      el("covmsg").innerHTML = msg("ok", out.note || "Moved.");
      setTimeout(vCoverage, 900);
    };
  });

  /* ------------------------------------------------------------- the cities */
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-city]"), function(s){
    s.dataset.was = s.value;
    s.onchange = async function(){
      s.disabled = true;
      var out = await ops("/places/city", { method:"POST", body:{
        cityId: s.getAttribute("data-city"), placeId: s.value || null } });
      s.disabled = false;
      if (out.error) {
        el("citymsg").innerHTML = msg("bad", out.reason || out.error);
        s.value = s.dataset.was; return;
      }
      s.dataset.was = s.value;
      el("citymsg").innerHTML = msg("ok", out.note || "Aligned.");
    };
  });

  /* ---------------------------------------------------------- the spellings */
  if (el("algo")) {
    el("algo").onclick = async function(){
      el("algo").disabled = true;
      var out = await ops("/places/alias", { method:"POST", body:{
        writtenAs: el("alwritten").value,
        means: el("almeans").value,
        note: el("alnote").value } });
      el("algo").disabled = false;
      if (out.error) {
        el("aliasmsg").innerHTML = msg("bad", out.reason || out.error); return;
      }
      el("aliasmsg").innerHTML = msg("ok", out.note || "Taught.");
      setTimeout(vCoverage, 900);
    };
  }
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-alrm]"), function(b){
    b.onclick = async function(){
      if (!confirm("Remove the spelling “" + b.getAttribute("data-alrm") +
        "”?\n\nA file that uses it will be refused unless the tree already " +
        "calls something that.")) return;
      b.disabled = true;
      var out = await ops("/places/alias/remove", { method:"POST",
        body:{ writtenAs: b.getAttribute("data-alrm") } });
      b.disabled = false;
      if (out.error) { el("aliasmsg").innerHTML = msg("bad", out.reason || out.error); return; }
      vCoverage();
    };
  });
}

/* The picker. Nobody can hold an employee number in their head - which is the
   whole reason the spreadsheet did not work - so the list is names, with the
   number and the chair beside each one.                                    */
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
        return '<option value="' + esc(p.id) + '">' + esc(p.name) +
          ' - ' + esc(p.employeeNo || "no number") +
          (p.chair ? ' - ' + esc(p.chair) : '') + '</option>';
      }).join("") + '</select></label> ' +
    '<label>Product<br><input id="covprod" list="covprods" placeholder="optional">' +
      '<datalist id="covprods">' +
      products.map(function(p){ return '<option value="' + esc(p) + '">'; }).join("") +
      '</datalist></label> ' +
    '<label>Effective from<br><input id="covfrom" type="date"></label> ' +
    '<button class="btn primary" id="covgo">Assign</button> ' +
    '<button class="btn" id="covcancel">Cancel</button>' +
    '<div id="covpanelmsg"></div></div>';
  el("covpanel").scrollIntoView({ behavior:"smooth", block:"nearest" });
  el("covcancel").onclick = function(){ el("covpanel").innerHTML = ""; };
  el("covgo").onclick = async function(){
    el("covgo").disabled = true;
    var out = await ops("/places/coverage", { method:"POST", body:{
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
      : (out.note || "Nothing to do - they already covered every branch there."));
    vCoverage();
  };
}

