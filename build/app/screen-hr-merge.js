/* ============================================================== hr-merge
   Two records, one person.

   A merge is the least reversible thing in this tool, so the screen is
   built around looking before acting rather than around acting quickly.
   Nothing is assumed about which record is right: both sides are laid out
   with what each one carries, and the person deciding picks a side per
   field, picks the seat that survives, reads what would move, and then
   types the name of the record being merged away.

   The plan comes from the database, not from here. It reads pg_constraint
   at run time, so it knows about every table that points at a person --
   including any added after this screen was written -- and it describes
   exactly the eleven fields person_merge() can set, no more and no fewer.
   The screen offers a choice for each of those eleven and for nothing
   else, because a field shown without a choice is a field quietly lost.

   One default is not neutral, and it is deliberate: where the survivor's
   value is blank and the merged-away record has one, the merged-away one
   is pre-selected. The alternative default keeps a blank over a fact and
   says nothing, which is how a merge loses a department.               */
var MG = { d:null, pairs:null, open:null, plan:null, choices:{},
           confirm:"", busy:false, says:"" };

/* vHR hands the overview over on every draw, the same way it does for the
   add-person card, because only vHR knows whether this viewer is HR. */
function mgHost(d){ MG.d = d; return '<div id="mgcard">' + mgCard(d) + '</div>'; }

function mgBlank(v){ return v === null || v === undefined || v === ""; }

/* Which side each field comes from. The winner unless nothing was chosen
   and the winner has nothing to lose -- see the note at the top. */
function mgPick(field, lv, wv){
  var c = MG.choices[field];
  if (c === "loser" || c === "winner") return c;
  return (mgBlank(wv) && !mgBlank(lv)) ? "loser" : "winner";
}

function mgRow(label, field, lv, wv){
  var same = String(mgBlank(lv) ? "" : lv) === String(mgBlank(wv) ? "" : wv);
  var on = mgPick(field, lv, wv);
  var cell = function(side, v){
    return '<td class="mgcell' + (!same && on === side ? " mgon" : "") + '">' +
      (same
        ? '<span class="mute">' + esc(mgBlank(v) ? "—" : v) + '</span>'
        : '<label><input type="radio" name="mg_' + esc(field) + '" value="' + side + '"' +
          (on === side ? " checked" : "") + ' data-mgfield="' + esc(field) + '"> ' +
          esc(mgBlank(v) ? "—" : v) + '</label>') +
      '</td>';
  };
  return '<tr><td class="mute">' + esc(label) + '</td>' +
    cell("loser", lv) + cell("winner", wv) + '</tr>';
}

function mgSeat(c, who){
  return '<label class="mgseat"><input type="radio" name="mgseat" value="' +
    esc(c.holderId) + '"' + (MG.choices.keepChairHolderId === c.holderId ? " checked" : "") +
    ' data-mgseat="' + esc(c.holderId) + '"> ' +
    '<b>' + esc(c.chair) + '</b>' + (c.at ? ' · ' + esc(c.at) : '') +
    (c.inScheme ? ' <span class="pill warn">in the PLB scheme</span>' : '') +
    '<div class="mute">' + esc(who) + (c.from ? ' · since ' + day(c.from) : '') + '</div></label>';
}

/* One person holds one primary chair. If both sides hold one the database
   refuses the merge until a seat is named, so the screen asks first rather
   than letting somebody type a name and then be told no. */
function mgSeatNeeded(){
  var p = MG.plan;
  if (!p || !p.ok) return false;
  var n = ((p.loser || {}).chairs || []).filter(function(c){ return c.primary; }).length +
          ((p.winner || {}).chairs || []).filter(function(c){ return c.primary; }).length;
  return n > 1 && !MG.choices.keepChairHolderId;
}

/* ------------------------------------------------------------- the list */
function mgCard(d){
  if (!d || !d.isHr) return "";
  var box = '<div id="mgmsg">' + MG.says + '</div>';
  var pairs = MG.pairs;
  if (pairs === null) {
    return '<div class="card"><h2>Two records, one person</h2>' +
      '<p class="mute">Two live records of one person split their history: half the ' +
      'performance rows join to one and half to the other, and neither total is ' +
      'anybody\'s.</p>' +
      '<p><button class="btn" id="mgload">Look for duplicates</button></p>' + box + '</div>';
  }
  if (!pairs.length) {
    return '<div class="card"><h2>Two records, one person</h2>' +
      '<div class="empty">No two live records share a name. That is the whole check ' +
      'this does — it compares names with case, spacing and punctuation set aside, so ' +
      'it will not catch a duplicate recorded under a different spelling.</div>' +
      '<p><button class="btn" id="mgload">Look again</button></p>' + box + '</div>';
  }
  var rows = pairs.map(function(p, i){
    return '<tr><td><b>' + esc(p.name) + '</b></td>' +
      '<td>' + mgSide(p.sides[0]) + '</td><td>' + mgSide(p.sides[1]) + '</td>' +
      '<td class="plact"><button class="btn" data-mgopen="' + i + '">Compare</button></td></tr>';
  }).join("");
  return '<div class="card"><h2>Two records, one person</h2>' +
    '<p class="mute">Two live records whose names match once case, spacing and ' +
    'punctuation are set aside. Neither is automatically the right one — merging ' +
    'decides which chair, which employment type and which contact details survive.</p>' +
    '<div class="scroll"><table><tr><th>Name</th><th>One record</th><th>The other</th>' +
    '<th></th></tr>' + rows + '</table></div>' +
    '<div id="mgpanel"></div>' + box + '</div>';
}

function mgSide(s){
  return '<div>' + esc(s.employeeNo || "no employee number") + '</div>' +
    '<div class="mute">' + esc(s.email || "no address") + '</div>' +
    '<div class="mute">' + esc((s.chairs || []).map(function(c){
      return c.chair + (c.inScheme ? " (in the scheme)" : ""); }).join(", ") || "no chair") +
    '</div>' +
    '<div class="mute">' + esc(s.type || "") +
      (Number(s.perfRows) ? " · " + s.perfRows + " performance rows" : "") +
      (Number(s.places) ? " · " + s.places + " place(s)" : "") +
      (Number(s.reports) ? " · " + s.reports + " report(s)" : "") + '</div>';
}

/* ------------------------------------------------------- the comparison */
function mgPanel(){
  var p = MG.plan;
  if (!p) return '<div class="plform"><p class="mute">Working out what would move…</p></div>';
  if (p.error) {
    return '<div class="plform">' + msg("bad", p.reason || p.error) +
      '<p><button class="btn" id="mgcancel">Close</button></p></div>';
  }
  if (!p.ok) {
    return '<div class="plform">' + msg("bad",
      (p.blockers || []).map(function(b){ return b.says; }).join(" ") ||
      "That pair cannot be merged.") +
      '<p><button class="btn" id="mgcancel">Close</button></p></div>';
  }
  var l = p.loser, w = p.winner;
  var seats = (l.chairs || []).map(function(c){ return mgSeat(c, l.name); })
        .concat((w.chairs || []).map(function(c){ return mgSeat(c, w.name); })).join("");

  var moves = (p.moves || []).map(function(m){
    return '<tr><td>' + esc(m.table) + '</td><td class="mute">' + esc(m.column) + '</td>' +
      '<td class="num">' + esc(m.rows) + '</td><td class="mute">' + esc(m.action) + '</td></tr>';
  }).join("");

  var clashes = (p.collisions || []).map(function(c){
    return '<li><b>' + esc(c.table) + '</b> — ' + esc(c.says) +
      '<div class="mute">unique on ' + esc(c.uniqueOn) + '</div></li>';
  }).join("");

  var needSeat = mgSeatNeeded();
  var ready = MG.confirm === l.name && !needSeat;

  return '<div class="plform">' +
    '<h4 class="plh">Which record survives, and what it keeps</h4>' +
    '<p class="mute">The left column is the record being merged away. Pick a side for ' +
    'anything the two disagree on; where they already agree there is nothing to choose. ' +
    'Where one side is blank and the other is not, the side that has something is ' +
    'already picked.</p>' +
    '<div class="scroll"><table>' +
      '<tr><th></th><th>' + esc(l.name) + '<div class="mute">merged away</div></th>' +
      '<th>' + esc(w.name) + '<div class="mute">survives</div></th></tr>' +
      mgRow("Name", "fullName", l.name, w.name) +
      mgRow("Employee number", "employeeNo", l.employeeNo, w.employeeNo) +
      mgRow("Work e-mail", "workEmail", l.email, w.email) +
      mgRow("Personal e-mail", "personalEmail", l.personalEmail, w.personalEmail) +
      mgRow("Mobile", "mobile", l.mobile, w.mobile) +
      mgRow("They are a", "employeeType", l.type, w.type) +
      mgRow("May do", "appRole", l.role, w.role) +
      mgRow("Department", "department", l.department, w.department) +
      mgRow("Designation", "designationId", l.designation, w.designation) +
      mgRow("Joined", "joinedOn", l.joinedOn, w.joinedOn) +
      mgRow("Reports to", "managerId", l.manager, w.manager) +
    '</table></div>' +
    '<p class="mute">The employee number is the one to look at twice: every performance ' +
    'upload joins people by it. The merged-away record keeps whatever number it had, ' +
    'harmlessly — a superseded row is outside the uniqueness rule.</p>' +
    '<p><button class="btn" id="mgswap">Swap which one survives</button></p>' +

    (seats
      ? '<h4 class="plh">The seat that survives</h4>' +
        '<p class="mute">One person holds one primary chair, so only one of these stays ' +
        'open. The others are closed with today\'s date — never deleted, because where ' +
        'somebody sat is a fact.</p>' +
        '<div class="mgseats">' + seats + '</div>'
      : '') +

    '<h4 class="plh">What would move</h4>' +
    (moves
      ? '<div class="scroll"><table><tr><th>Table</th><th>Column</th><th>Rows</th>' +
        '<th></th></tr>' + moves + '</table></div>'
      : '<div class="empty">Nothing points at the record being merged away.</div>') +

    (clashes
      ? '<h4 class="plh">Where the two would land on each other</h4>' +
        '<ul class="mgclash">' + clashes + '</ul>'
      : '') +

    '<h4 class="plh">This cannot be undone</h4>' +
    '<p class="mute">The merged-away record is kept and stays readable, but everything ' +
    'that pointed at it will point at the survivor, its sign-ins are revoked, and there ' +
    'is no unmerge. To go ahead, type <b>' + esc(l.name) + '</b>.</p>' +
    (needSeat ? msg("warn", "Both of them hold a primary chair. Say which seat survives " +
      "before merging; the other is closed with today's date, not deleted.") : "") +
    '<div class="plbar">' +
      '<input id="mgconfirm" placeholder="' + esc(l.name) + '" style="min-width:280px" ' +
        'value="' + esc(MG.confirm) + '">' +
      '<button class="btn primary" id="mggo"' + (ready ? "" : " disabled") + '>Merge</button>' +
      '<button class="btn" id="mgcancel">Cancel</button>' +
    '</div></div>';
}

/* ------------------------------------------------------------ the wiring */
async function mgLoadPlan(){
  MG.plan = null; mgRepaint();
  var o = MG.open;
  var p = await hrapi("/hr/merge/plan", { method:"POST",
    body:{ loserId: o.loserId, winnerId: o.winnerId } });
  /* the panel belongs to the pair that was open when the answer arrives,
     not to whatever is open now -- two clicks race otherwise */
  if (!MG.open || MG.open.loserId !== o.loserId || MG.open.winnerId !== o.winnerId) return;
  MG.plan = p;
  mgRepaint();
}

function mgRepaint(){
  var host = el("mgcard");
  if (!host) return;
  var focused = document.activeElement;
  var keep = focused && focused.id === "mgconfirm";
  host.innerHTML = mgCard(MG.d);
  if (MG.open && el("mgpanel")) el("mgpanel").innerHTML = mgPanel();
  mgWire();
  if (keep && el("mgconfirm")) {
    el("mgconfirm").focus();
    try { el("mgconfirm").setSelectionRange(MG.confirm.length, MG.confirm.length); }
    catch (e) { /* not every browser allows it on every input */ }
  }
}

function mgWire(){
  if (el("mgload")) el("mgload").onclick = async function(){
    MG.says = "";
    var o = await hrapi("/hr/duplicates");
    MG.pairs = o.error ? [] : (o.pairs || []);
    if (o.error) MG.says = msg("bad", o.reason || o.error);
    mgRepaint();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-mgopen]"), function(b){
    b.onclick = function(){
      var p = MG.pairs[Number(b.getAttribute("data-mgopen"))];
      /* person_duplicates() returns the heavier record first -- the one more
         rows already point at. It is offered as the survivor because merging
         into the emptier one moves more rows, not because it is more real,
         and Swap is right there. */
      MG.open = { loserId: p.sides[1].personId, winnerId: p.sides[0].personId };
      MG.choices = {}; MG.confirm = ""; MG.says = "";
      mgLoadPlan();
    };
  });

  if (el("mgswap")) el("mgswap").onclick = function(){
    var o = MG.open;
    MG.open = { loserId: o.winnerId, winnerId: o.loserId };
    MG.choices = {}; MG.confirm = ""; MG.says = "";
    mgLoadPlan();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-mgfield]"), function(f){
    f.onchange = function(){
      MG.choices[f.getAttribute("data-mgfield")] = f.value;
      mgRepaint();
    };
  });
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-mgseat]"), function(f){
    f.onchange = function(){
      MG.choices.keepChairHolderId = f.getAttribute("data-mgseat");
      mgRepaint();
    };
  });

  if (el("mgconfirm")) el("mgconfirm").oninput = function(){
    MG.confirm = el("mgconfirm").value;
    var go = el("mggo");
    var want = MG.plan && MG.plan.loser ? MG.plan.loser.name : null;
    if (go) go.disabled = !(MG.confirm === want && !mgSeatNeeded());
  };

  if (el("mgcancel")) el("mgcancel").onclick = function(){
    MG.open = null; MG.plan = null; MG.choices = {}; MG.confirm = "";
    mgRepaint();
  };

  if (el("mggo")) el("mggo").onclick = async function(){
    if (MG.busy) return;
    MG.busy = true; el("mggo").disabled = true;
    var out = await hrapi("/hr/merge", { method:"POST", body:{
      loserId: MG.open.loserId, winnerId: MG.open.winnerId,
      choices: MG.choices, confirm: MG.confirm } });
    MG.busy = false;
    if (out.error) {
      MG.says = msg("bad", out.reason || out.error);
      mgRepaint();
      return;
    }
    MG.says = msg("ok", out.note);
    MG.open = null; MG.plan = null; MG.choices = {}; MG.confirm = ""; MG.pairs = null;
    mgRepaint();
  };
}
