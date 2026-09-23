-- Coverage & handlers, and a chair you can move.
--
-- Applies the two screens to the one row of app_page that IS the application.
-- The navigation entry, the route, and the two screen functions. vPeople is
-- appended rather than swapped in place: a later function declaration wins in
-- JavaScript, so this overrides the one the cut-over shipped without having to
-- match its old text exactly and risk half-replacing it.
--
-- Run the "Publish the tool" workflow afterwards, or wait for the nightly one,
-- so index.html in this repository catches up with the page.
do $$
declare v_body text; v_new text; v_js text;
begin
  select body into v_body from app_page where slug = 'app';
  if v_body is null then raise exception 'no app page'; end if;
  if position('{ label:"Keep",       items:[ ["config","Configuration"],' in v_body) = 0 then
    raise exception 'the navigation anchor is not there';
  end if;
  if position('whatsapp:vWhats, config:vConfig}[t];' in v_body) = 0 then
    raise exception 'the route anchor is not there';
  end if;
  if position(E'\nboot();\n</script>' in v_body) = 0 then
    raise exception 'the tail anchor is not there';
  end if;

  v_js := $js$
/* --------------------------------------------------- coverage & handlers
   Who covers which client, where -- and the place you change it. Assigning
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
              (h.chair ? ' &middot; ' + esc(h.chair) : '') + ' &middot; ' +
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
        "?\n\nThe rules are dated to today, never deleted -- who covered what last " +
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
   head -- which is the whole reason the spreadsheet did not work -- so the
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
          ' -- ' + esc(p.employee_no || "no number") +
          (p.chair ? ' -- ' + esc(p.chair) : '') + '</option>';
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
      : "Nothing to do -- they already covered every branch there.");
    vCoverage();
  };
}

async function vPeople(){
  var r = await Promise.all([api("/people/org"), api("/people/team")]);
  var chairs = r[0].chairs || [], team = r[1].team || [];
  var byParent = {};
  chairs.forEach(function(c){ (byParent[c.parent_id||"root"] = byParent[c.parent_id||"root"] || []).push(c); });
  var mayMove = !!me && me.app_role === "ADMIN";

  function branch(key){
    var kids = byParent[key] || [];
    if (!kids.length) return "";
    return '<ul class="tree">' + kids.map(function(c){
      var st = c.vacant ? '<span class="pill bad">vacant</span>'
             : c.overdue_days > 0 ? '<span class="pill warn">'+c.overdue_days+'d overdue</span>' : '';
      var held = Number(c.headcount || 0);
      var many = held > 1 ? '<span class="chip">'+held+' hold this chair</span>' : '';
      var mv = mayMove
        ? ' <button class="btn" data-move="'+esc(c.id)+'" data-movetitle="'+esc(c.title)+'">Move</button>'
        : '';
      return '<li><div class="node"><span class="t">'+esc(c.title)+'</span>' +
        '<span class="mute">'+esc(c.full_name || "-")+'</span>'+st+many+mv+'</div>' +
        branch(c.id) + '</li>';
    }).join("") + '</ul>';
  }

  el("view").innerHTML =
    '<div class="page-head"><div><h1>People</h1>' +
    '<p class="mute">' + esc(chairs.length) + ' chairs. A chair shared by several ' +
    'people is one chair here, not one per holder -- 63 people hold Executive, and ' +
    'drawing it 63 times is what used to stop this page opening.' +
    (mayMove ? ' Move re-parents a chair; everything under it comes with it.' : '') +
    '</p></div></div>' +
    '<div id="pplmsg"></div>' +
    '<div class="card"><h2>Your team</h2>' +
      (team.length ? '<div class="scroll"><table><tr><th>Chair</th><th>Who</th><th>State</th></tr>' +
        team.map(function(t){
          return '<tr><td>'+esc(t.title)+'</td><td>'+esc(t.full_name||"-")+'</td>' +
            '<td>'+esc(t.state||"")+'</td></tr>'; }).join("") + '</table></div>'
        : '<div class="empty">Nobody reports to your chair.</div>') + '</div>' +
    '<div class="card"><h2>The structure</h2>' +
      (chairs.length ? branch("root") : '<div class="empty">No chairs loaded yet.</div>') +
      '<div id="pplmove"></div></div>';

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-move]"), function(b){
    b.onclick = function(){
      var id = b.getAttribute("data-move"), title = b.getAttribute("data-movetitle");
      /* A chair cannot go under itself or under anything beneath it. The
         server refuses it too; offering it here would only be a trap.     */
      var under = {}; (function walk(k){
        (byParent[k] || []).forEach(function(c){ under[c.id] = 1; walk(c.id); });
      })(id); under[id] = 1;
      var pick = chairs.filter(function(c){ return !under[c.id]; })
        .sort(function(a, z){ return a.title < z.title ? -1 : 1; });
      el("pplmove").innerHTML =
        '<div class="card"><h3>Move ' + esc(title) + '</h3>' +
        '<p class="mute">Everything underneath it moves with it. Nothing about the ' +
        'people in the chair changes -- this is the reporting line, not their job.</p>' +
        '<label>Report to<br><select id="mvto">' +
          '<option value="">(the top of the tree)</option>' +
          pick.map(function(c){
            return '<option value="'+esc(c.id)+'">'+esc(c.title)+'</option>'; }).join("") +
        '</select></label> ' +
        '<button class="btn primary" id="mvgo">Move it</button> ' +
        '<button class="btn" id="mvcancel">Cancel</button><div id="mvmsg"></div></div>';
      el("pplmove").scrollIntoView({ behavior:"smooth", block:"nearest" });
      el("mvcancel").onclick = function(){ el("pplmove").innerHTML = ""; };
      el("mvgo").onclick = async function(){
        el("mvgo").disabled = true;
        var out = await api("/people/chair/" + encodeURIComponent(id) + "/move",
          { method:"POST", body:{ parentId: el("mvto").value || null } });
        el("mvgo").disabled = false;
        if (out.error) { el("mvmsg").innerHTML = msg("bad", out.reason || out.error); return; }
        el("pplmove").innerHTML = "";
        el("pplmsg").innerHTML = msg("ok", out.title + " now reports to " +
          (out.to || "nobody -- it is the top of the tree") + ".");
        vPeople();
      };
    };
  });
}
$js$;

  v_new := replace(v_body,
    '{ label:"Keep",       items:[ ["config","Configuration"],',
    '{ label:"Keep",       items:[ ["coverage","Coverage"], ["config","Configuration"],');
  v_new := replace(v_new,
    'whatsapp:vWhats, config:vConfig}[t];',
    'whatsapp:vWhats, config:vConfig, coverage:vCoverage}[t];');
  v_new := replace(v_new, E'\nboot();\n</script>', v_js || E'\nboot();\n</script>');

  if position('coverage:vCoverage' in v_new) = 0 then raise exception 'route not added'; end if;
  if position('["coverage","Coverage"]' in v_new) = 0 then raise exception 'nav not added'; end if;
  if position('async function vCoverage(){' in v_new) = 0 then raise exception 'screen not added'; end if;
  if length(v_new) <= length(v_body) then raise exception 'the page did not grow'; end if;

  update app_page set body = v_new, updated_at = now() where slug = 'app';
end $$;
