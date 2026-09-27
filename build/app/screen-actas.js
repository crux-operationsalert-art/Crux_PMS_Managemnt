/* ================================================================ act-as
   Looking at Crux as somebody else.

   This was in the v2 design and was never built. The design carries a
   PERSONAS model giving every chair its own navigation, and a seats()
   switcher whose confirmation reads "You are now acting as {chair}. Your
   tasks, escalations, reports and rights all follow the chair, not the
   person." What follows is that, for an administrator.

   The mechanism is deliberately not a pretend mode. There is no "view as"
   flag threaded through every screen, because a flag like that is a second
   implementation of permissions and it will drift from the first one --
   and the whole reason to look is to find out what somebody really sees.
   Instead the database mints a real session for that person. Every screen,
   every query, every refusal is the real one, because nothing in the tool
   knows the difference.

   What keeps that honest is the session row: auth_session.acting_actor_id
   records who opened it, and one ACTED_AS audit row names both people. So
   the view is indistinguishable from the real thing and the trail is not.

   Two hours, and a banner that does not go away.                        */
var AA = { on:false, o:null, open:false, q:"", tab:"people", busy:false, says:"" };

/* aaGet, aaSet and aaDrop are the guarded localStorage helpers defined up
   beside `var token`, where the first read happens. They are used here
   rather than localStorage directly for the same reason they exist there:
   losing the administrator's own token to an exception would strand them
   inside somebody else's session with no way back. */

/* The bar sits under the header on every screen, so there is never a page
   where you have forgotten whose desk you are looking at. */
function aaBar(){
  if (!me) return "";
  var acting = me.acting;
  if (acting) {
    return '<div class="aaband">' +
      '<div><b>You are looking at Crux as ' + esc(me.full_name) + '</b>' +
      (me.chair_title ? ' · ' + esc(me.chair_title) : '') +
      (me.employee_no ? ' · ' + esc(me.employee_no) : '') +
      '<div class="aasub">Opened by ' + esc(acting.by) + '. Anything done here is ' +
      'recorded as ' + esc(me.full_name) + ', with ' + esc(acting.by) +
      ' named against it in the audit trail. This ends on its own in two hours.</div></div>' +
      '<button class="btn" id="aastop">Stop and go back</button></div>';
  }
  if ((me.app_role || "") !== "ADMIN") return "";
  return '<div class="aapick">' +
    '<button class="btn" id="aaopen">Look at Crux as someone else</button>' +
    '<span class="mute">See exactly what a person or a chair sees, with their ' +
    'permissions, not a preview of them.</span>' +
    '<span id="aamsg"></span></div>' +
    (AA.open ? aaPanel() : "");
}

function aaPanel(){
  if (!AA.o) return '<div class="aabox"><p class="mute">Loading who there is…</p></div>';
  if (AA.o.error) return '<div class="aabox">' + msg("bad", AA.o.reason || AA.o.error) + '</div>';
  var q = AA.q.toLowerCase().replace(/[^a-z0-9]/g, "");
  var hit = function(s){ return !q || String(s || "").toLowerCase()
      .replace(/[^a-z0-9]/g, "").indexOf(q) > -1; };

  var body;
  if (AA.tab === "chairs") {
    var chairs = (AA.o.chairs || []).filter(function(c){ return hit(c.chair) || hit(c.code); });
    body = chairs.length
      ? '<div class="scroll"><table><tr><th>Chair</th><th>Who is in it</th><th></th></tr>' +
        chairs.map(function(c){
          var who = (c.holders || []).map(function(h){ return h.name; }).join(", ");
          return '<tr><td>' + esc(c.chair) +
            (c.inScheme ? ' <span class="pill warn">in the PLB scheme</span>' : '') +
            '</td><td class="mute">' + esc(who || "nobody") + '</td>' +
            '<td class="plact"><button class="btn" data-aachair="' + esc(c.chairId) + '"' +
            (Number(c.seated) ? '' : ' disabled') + '>Look as this chair</button></td></tr>';
        }).join("") + '</table></div>'
      : '<div class="empty">No chair matches that.</div>';
  } else {
    var people = (AA.o.people || []).filter(function(p){
      return hit(p.name) || hit(p.employeeNo) || hit(p.email) || hit(p.chair); });
    var shown = people.slice(0, 60);
    body = shown.length
      ? '<div class="scroll"><table><tr><th>Person</th><th>Chair</th><th>May do</th><th></th></tr>' +
        shown.map(function(p){
          return '<tr><td><b>' + esc(p.name) + '</b>' +
            (p.employeeNo ? ' <span class="mute">' + esc(p.employeeNo) + '</span>' : '') +
            '<div class="mute">' + esc(p.email || "no address") + '</div></td>' +
            '<td class="mute">' + esc(p.chair || "no chair") + '</td>' +
            '<td class="mute">' + esc(String(p.role || "").toLowerCase().replace(/_/g, " ")) + '</td>' +
            '<td class="plact"><button class="btn" data-aaperson="' + esc(p.personId) +
            '">Look as them</button></td></tr>';
        }).join("") + '</table></div>' +
        (people.length > shown.length
          ? '<p class="mute">' + esc(people.length - shown.length) +
            ' more match. Type a little more to narrow it.</p>' : '')
      : '<div class="empty">Nobody matches that.</div>';
  }

  return '<div class="aabox">' +
    '<div class="aatabs">' +
      '<button class="btn' + (AA.tab === "people" ? " primary" : "") + '" data-aatab="people">' +
        'A person</button>' +
      '<button class="btn' + (AA.tab === "chairs" ? " primary" : "") + '" data-aatab="chairs">' +
        'A chair</button>' +
      '<input id="aaq" placeholder="name, employee number, chair…" value="' + esc(AA.q) + '">' +
      '<button class="btn" id="aaclose">Cancel</button>' +
    '</div>' + body + '</div>';
}

function aaPaint(){
  var host = el("aabar");
  if (!host) return;
  var focused = document.activeElement;
  var keep = focused && focused.id === "aaq";
  var pos = keep && focused.selectionStart;
  host.innerHTML = aaBar();
  aaWire();
  if (keep && el("aaq")) {
    el("aaq").focus();
    try { el("aaq").setSelectionRange(pos, pos); } catch (e) { /* not every input allows it */ }
  }
}

function aaWire(){
  if (el("aaopen")) el("aaopen").onclick = async function(){
    AA.open = true; AA.says = "";
    aaPaint();
    if (!AA.o) { AA.o = await hrapi("/hr/act/targets"); aaPaint(); }
  };
  if (el("aaclose")) el("aaclose").onclick = function(){ AA.open = false; aaPaint(); };

  Array.prototype.forEach.call(document.querySelectorAll("[data-aatab]"), function(b){
    b.onclick = function(){ AA.tab = b.getAttribute("data-aatab"); aaPaint(); };
  });
  if (el("aaq")) el("aaq").oninput = function(){ AA.q = el("aaq").value; aaPaint(); };

  Array.prototype.forEach.call(document.querySelectorAll("[data-aaperson]"), function(b){
    b.onclick = function(){ aaGo({ personId: b.getAttribute("data-aaperson") }); };
  });
  Array.prototype.forEach.call(document.querySelectorAll("[data-aachair]"), function(b){
    b.onclick = function(){ aaGo({ chairId: b.getAttribute("data-aachair") }); };
  });

  if (el("aastop")) el("aastop").onclick = aaStop;
}

/* The admin's own token is put somewhere else BEFORE the borrowed one is
   installed. If the order were the other way round and the write failed,
   the way back would be gone. */
async function aaGo(body){
  if (AA.busy) return;
  AA.busy = true;
  var mine = token;
  var out = await hrapi("/hr/act/as", { method:"POST", body: body });
  AA.busy = false;
  if (out.error) {
    AA.o = AA.o || {};
    var box = el("aamsg");
    if (box) box.innerHTML = msg("bad", out.reason || out.error);
    return;
  }
  aaSet("cruxAdminToken", mine);
  token = out.token;
  aaSet("cruxToken", token);
  AA.open = false; AA.o = null; AA.q = "";
  location.hash = "#today";
  start(out.person);
}

async function aaStop(){
  var mine = aaGet("cruxAdminToken");
  if (!mine) { signOut(); return; }
  /* hand the borrowed session back rather than letting it idle out */
  try { await crux("/api/logout", { method:"POST" }); } catch (e) { /* it expires anyway */ }
  token = mine;
  aaSet("cruxToken", token);
  aaDrop("cruxAdminToken");
  var p = await crux("/api/me");
  if (p && p.id) { location.hash = "#today"; return start(p); }
  signOut();
}
