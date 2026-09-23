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
    'people is one chair here, not one per holder — 63 people hold Executive, and ' +
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
        'people in the chair changes — this is the reporting line, not their job.</p>' +
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
          (out.to || "nobody — it is the top of the tree") + ".");
        vPeople();
      };
    };
  });
}
