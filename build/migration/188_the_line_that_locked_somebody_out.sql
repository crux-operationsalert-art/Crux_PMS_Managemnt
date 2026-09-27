-- READY TO APPLY, NOT YET APPLIED. The MCP approval gate refused every
-- Supabase call while this was written, including a bare `select 1`, so
-- nothing here has run. Apply after 187.
--
-- Asserts app_page md5 = 71517ea6deba74aa8cdfd3356d344116 (369077 chars).
--
-- =====================================================================
-- 1. THE LINE THAT LOCKED SOMEBODY OUT
-- =====================================================================
-- Line 554 of the published page is the first statement in the script:
--
--     var token = localStorage.getItem("cruxToken") || "";
--
-- localStorage does not return null when a browser refuses it. It THROWS.
-- Private windows, blocked site data, some managed-device policies. And
-- because that line runs before anything else, the throw takes the entire
-- script with it: no function is ever defined, boot() never runs, the
-- Google button never renders. What is left on screen is the sign-in card,
-- which is static HTML, with a Sign in button wired to nothing.
--
-- That is indistinguishable from "sign-in is broken", and it explains the
-- one thing that did not fit: login_attempt has no failures. Not one. The
-- request was never made.
--
-- Three more sites do the same thing unguarded, at the two places a token
-- is stored after a successful sign-in and at sign-out. All four are now
-- routed through aaGet / aaSet / aaDrop, which catch and carry on. A
-- browser that will not remember the token still signs in; it just has to
-- sign in again next time, which is worth infinitely more than a page that
-- will not load.
--
-- =====================================================================
-- 2. ACTING AS A PERSON OR A CHAIR
-- =====================================================================
-- The screen for 187. A picker under the header for an administrator, and
-- a banner that does not go away while a borrowed seat is in use. See
-- build/app/screen-actas.js, which this file must stay byte-identical to.
--
-- =====================================================================
-- 3. THE DEAD vPeople
-- =====================================================================
-- vPeople is declared twice. JavaScript takes the later one, so the first
-- -- 1,517 characters -- has shipped on every page load since it was
-- written and can never run. The surviving one is a strict superset: same
-- two API calls, plus headcount, Move buttons and drag-to-reparent. The
-- dead one goes. Checked across all 29 screen functions; it is the only
-- duplicate.

do $mig$
declare
  h text; js text; css text; dead text;
  a int; b int; before_async int; after_async int; n int;
begin
  select html into h from app_page where slug = 'app';
  if md5(h) <> '71517ea6deba74aa8cdfd3356d344116' then
    raise exception 'app_page is not the row this was written against (md5 %)', md5(h);
  end if;
  before_async := (length(h) - length(replace(h, 'async function', ''))) / length('async function');

  -- ------------------------------------------- 1. guard every storage call
  n := (length(h) - length(replace(h, 'var token = localStorage.getItem("cruxToken") || "";', '')))
       / length('var token = localStorage.getItem("cruxToken") || "";');
  if n <> 1 then raise exception 'the storage read is not where it was: % of it', n; end if;

  h := replace(h, 'var token = localStorage.getItem("cruxToken") || "";',
'/* localStorage THROWS rather than returning null when a browser refuses it:' || E'\n' ||
'   a private window, blocked site data, a managed device. This is the first' || E'\n' ||
'   statement in the script, so an unguarded throw here took the whole file' || E'\n' ||
'   with it -- no functions defined, boot() never run, the Google button never' || E'\n' ||
'   rendered -- and left the static sign-in card on screen with a dead button.' || E'\n' ||
'   Nothing reached the server, which is why login_attempt recorded no failure.' || E'\n' ||
'   A browser that will not remember a token can still sign in. It just has to' || E'\n' ||
'   do it again next time. */' || E'\n' ||
'function aaGet(k){ try { return localStorage.getItem(k); } catch (e) { return null; } }' || E'\n' ||
'function aaSet(k, v){ try { localStorage.setItem(k, v); } catch (e) { /* memory only */ } }' || E'\n' ||
'function aaDrop(k){ try { localStorage.removeItem(k); } catch (e) { /* nothing to do */ } }' || E'\n' ||
'var token = aaGet("cruxToken") || "";');

  n := (length(h) - length(replace(h, 'localStorage.setItem("cruxToken", token);', '')))
       / length('localStorage.setItem("cruxToken", token);');
  if n <> 2 then raise exception 'expected two token writes, found %', n; end if;
  h := replace(h, 'localStorage.setItem("cruxToken", token);', 'aaSet("cruxToken", token);');

  n := (length(h) - length(replace(h, 'token=""; localStorage.removeItem("cruxToken"); me=null;', '')))
       / length('token=""; localStorage.removeItem("cruxToken"); me=null;');
  if n <> 1 then raise exception 'sign-out is not where it was: % of it', n; end if;
  h := replace(h, 'token=""; localStorage.removeItem("cruxToken"); me=null;',
                  'token=""; aaDrop("cruxToken"); aaDrop("cruxAdminToken"); me=null;');

  -- ------------------------------------------------- 2. the dead vPeople
  a := position('/* --------------------------------------------------------------- people */' || E'\n' ||
                'async function vPeople(){' in h);
  if a = 0 then raise exception 'the first vPeople is not where it was'; end if;
  b := position(E'\n' || '/* ------------------------------------------------------------ penalties */' in h);
  if b = 0 or b <= a then raise exception 'cannot bound the dead vPeople'; end if;
  dead := substring(h from a for b - a);
  if (length(dead) - length(replace(dead, 'function vPeople(', ''))) / length('function vPeople(') <> 1 then
    raise exception 'the block being removed does not hold exactly one vPeople';
  end if;
  if length(dead) <> 1517 then
    raise exception 'the dead block is % characters, expected 1517', length(dead);
  end if;
  h := overlay(h placing '' from a for length(dead));

  -- ------------------------------------------------------- 3. the style
  css :=
'/* Acting as somebody else. The band is not dismissible and does not scroll' || E'\n' ||
'   away: there must never be a screen where you have forgotten whose desk' || E'\n' ||
'   you are looking at. */' || E'\n' ||
'.aaband{display:flex;gap:14px;align-items:center;justify-content:space-between;' || E'\n' ||
'  flex-wrap:wrap;padding:9px clamp(12px,3vw,24px);background:var(--gold);' || E'\n' ||
'  color:var(--gold-ink);border-bottom:1px solid var(--line3);font-size:13px}' || E'\n' ||
'.aasub{opacity:.85;font-size:12px;line-height:1.5;max-width:70ch}' || E'\n' ||
'.aapick{display:flex;gap:10px;align-items:center;flex-wrap:wrap;' || E'\n' ||
'  padding:8px clamp(12px,3vw,24px);border-bottom:1px solid var(--line3);font-size:12.5px}' || E'\n' ||
'.aabox{border-bottom:1px solid var(--line3);padding:4px 0 10px}' || E'\n' ||
'.aatabs{display:flex;gap:8px;align-items:center;flex-wrap:wrap;padding:10px clamp(12px,3vw,24px)}' || E'\n' ||
'.aatabs input{min-width:240px;flex:1}' || E'\n' ||
'@media(max-width:700px){.aaband{align-items:flex-start}.aatabs input{min-width:0}}' || E'\n';

  n := (length(h) - length(replace(h, '.hebig{', ''))) / length('.hebig{');
  if n <> 1 then raise exception 'the style anchor is not unique: % of it', n; end if;
  h := replace(h, '.hebig{', css || '.hebig{');

  -- ------------------------------------------------------ 4. the host div
  n := (length(h) - length(replace(h, '<main id="view"></main>', ''))) / length('<main id="view"></main>');
  if n <> 1 then raise exception 'the host anchor is not unique: % of it', n; end if;
  h := replace(h, '<main id="view"></main>',
                  '<div id="aabar"></div>' || E'\n' || '<main id="view"></main>');

  -- --------------------------------------------------- 5. paint it on start
  n := (length(h) - length(replace(h, '  paintNav();' || E'\n' || '  window.onhashchange = route;', '')))
       / length('  paintNav();' || E'\n' || '  window.onhashchange = route;');
  if n <> 1 then raise exception 'start() is not shaped as expected: % matches', n; end if;
  h := replace(h, '  paintNav();' || E'\n' || '  window.onhashchange = route;',
                  '  paintNav();' || E'\n' || '  aaPaint();' || E'\n' || '  window.onhashchange = route;');

  -- ------------------------------------------------------- 6. the screen
  js := $js$
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

$js$;

  n := (length(h) - length(replace(h, 'async function vHR(){', ''))) / length('async function vHR(){');
  if n <> 1 then raise exception 'the screen anchor is not unique: % of it', n; end if;
  h := replace(h, 'async function vHR(){', js || E'\n' || 'async function vHR(){');

  -- ------------------------------------------------- what must still be true
  n := (length(h) - length(replace(h, 'async function vHR(){', ''))) / length('async function vHR(){');
  if n <> 1 then raise exception 'vHR is no longer declared exactly once as async: %', n; end if;
  n := (length(h) - length(replace(h, 'function vHR(){', ''))) / length('function vHR(){');
  if n <> 1 then raise exception 'there is more than one vHR, or one lost its async: %', n; end if;

  -- the whole point of part 3: exactly one vPeople now
  n := (length(h) - length(replace(h, 'function vPeople(', ''))) / length('function vPeople(');
  if n <> 1 then raise exception 'vPeople is declared % times, expected 1', n; end if;

  after_async := (length(h) - length(replace(h, 'async function', ''))) / length('async function');
  -- +3 from the screen, -1 for the dead vPeople that was removed
  if after_async <> before_async + 3 - 1 then
    raise exception 'async declarations went % to %, expected %',
      before_async, after_async, before_async + 2;
  end if;

  n := (length(h) - length(replace(h, 'localStorage.', ''))) / length('localStorage.');
  if n <> 3 then raise exception 'localStorage should be touched only inside the three guards, found %', n; end if;

  n := (length(h) - length(replace(h, 'function aaPaint(', ''))) / length('function aaPaint(');
  if n <> 1 then raise exception 'aaPaint is not declared exactly once: %', n; end if;
  n := (length(h) - length(replace(h, 'id="aabar"', ''))) / length('id="aabar"');
  if n <> 1 then raise exception 'the act-as bar is not hosted exactly once: %', n; end if;
  n := (length(h) - length(replace(h, '.aaband{', ''))) / length('.aaband{');
  if n <> 1 then raise exception 'the style is not in exactly once: %', n; end if;

  update app_page set html = h, updated_at = now() where slug = 'app';
end $mig$;
