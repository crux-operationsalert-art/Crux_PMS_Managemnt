/* ========================================================= matrix month
   The escalation matrix as a thing that goes OUT.

   The tool already held the matrix and chased the branches that were
   missing a level. What it had nowhere was the monthly act: the pack that
   goes to the client, who it went to, when, and what it said at the moment
   it left. A branch manager could fill in five levels for a year and never
   once be told whether the client had been sent them.

   Two entrances, because it is one question asked in two places. The
   dashboard says whether this month has gone out. The Escalation matrix
   screen is where it goes out from.

   Nothing here decides anything. matrix_month() says what may be seen,
   matrix_pack() says what would go and what is held back, matrix_send()
   says whether this person may send it -- and a branch with a blank level
   is named and kept back rather than sent with a gap, because a matrix
   with a hole in it reads as complete.                                  */
var MX = { period:null, month:null, open:null, pack:null, to:{}, says:"", busy:false };

function mxMonth(d){ d = d || new Date();
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1)).toISOString().slice(0,10); }

function mxMonthName(s){
  var d = new Date(s + "T00:00:00Z");
  return d.toLocaleString("en-GB", { month:"long", year:"numeric", timeZone:"UTC" });
}

/* A screen is published from one place and its service is deployed from
   another, and the two do not always land in the same minute. */
function mxMissing(r){
  return !!r && (r.error === "no_route" || r._status === 404);
}

/* ------------------------------------------------------ the dashboard line */
async function mxCardLoad(){
  var box = el("mxcard");
  if (!box) return;
  var m = await ops("/pack/month").catch(function(){ return null; });
  /* A chair with no client view gets no card at all, and neither does a
     dashboard whose service is not deployed yet. An empty box is better
     than a card that explains itself on somebody's first screen. */
  if (!m || m.error || !m.clients || !m.clients.length) { box.innerHTML = ""; return; }

  var late = m.clients.filter(function(c){ return !c.sentAt; });
  box.innerHTML = '<div class="card"><h2>This month’s escalation matrix</h2>' +
    '<div class="mxline' + (late.length ? ' due' : ' done') + '">' + esc(m.says) + '</div>' +
    (late.length
      ? '<ul class="mxlist">' + late.slice(0, 6).map(function(c){
          return '<li>' + esc(c.name) + ' <span class="mute">' + esc(c.ready) +
            ' of ' + esc(c.branches) + ' branches ready' +
            (c.incomplete ? ', ' + esc(c.incomplete) + ' with a missing level' : '') +
            '</span></li>'; }).join("") +
        (late.length > 6 ? '<li class="mute">and ' + (late.length - 6) + ' more</li>' : '') +
        '</ul>'
      : '') +
    '<div class="plbar"><button class="btn" onclick="location.hash=\'#matrix\'">' +
      (late.length ? 'Send this month’s matrix' : 'Open the matrix') + '</button></div></div>';
}

/* ------------------------------------------------- the section on #matrix */
async function mxMonthLoad(){
  if (!el("mxmonth")) return;
  if (!MX.period) MX.period = mxMonth();
  MX.month = await ops("/pack/month?period=" + MX.period);
  if (mxMissing(MX.month)) {
    el("mxmonth").innerHTML = msg("warn",
      "The monthly pack is published but the service behind it is not deployed " +
      "yet. The five levels below are live and can still be filled in; what " +
      "cannot be done yet is sending them.");
    return;
  }
  mxRender();
}

function mxRender(){
  var box = el("mxmonth");
  if (!box) return;
  var m = MX.month || {};
  var rows = m.clients || [];

  var picker = '<select id="mxperiod">';
  for (var i = 0; i < 12; i++) {
    var d = new Date(); d.setUTCDate(1); d.setUTCMonth(d.getUTCMonth() - i);
    var v = mxMonth(d);
    picker += '<option value="' + v + '"' + (v === MX.period ? ' selected' : '') + '>' +
      esc(mxMonthName(v)) + '</option>';
  }
  picker += '</select>';

  box.innerHTML =
    '<div class="card"><h2>What goes to the client this month</h2>' +
    '<div class="plbar">' + picker + '<span class="mute">' + esc(m.says || "") + '</span></div>' +
    (rows.length
      ? '<div class="scroll"><table>' +
        '<tr><th>Client</th><th>Ready</th><th>Held back</th><th>This month</th><th></th></tr>' +
        rows.map(mxRow).join("") + '</table></div>'
      : '<div class="empty">' + esc(m.says || "There is nothing to send.") + '</div>') +
    '<div id="mxmsg">' + MX.says + '</div></div>';
  mxWire();
}

function mxRow(c){
  var open = MX.open === c.clientId;
  return '<tr><td><b>' + esc(c.name) + '</b> <span class="mute">' + esc(c.code) + '</span>' +
      '<div class="mute">' + esc(c.branches) + ' branch(es) covered · ' +
        esc(c.recipients) + ' contact(s) on file</div></td>' +
    '<td>' + esc(c.ready) + '</td>' +
    '<td>' + (c.incomplete
      ? '<span class="pill bad">' + esc(c.incomplete) + '</span>'
      : '<span class="mute">none</span>') + '</td>' +
    '<td>' + (c.sentAt
      ? '<span class="pill ok">sent ' + esc(day(c.sentAt)) + '</span>' +
        '<div class="mute">' + esc(c.sentCount) + ' branch(es)' +
          (c.heldBack ? ', ' + esc(c.heldBack) + ' held back' : '') + '</div>'
      : '<span class="pill warn">not yet</span>') + '</td>' +
    '<td class="plact"><button class="btn" data-mxopen="' + esc(c.clientId) + '">' +
      (open ? 'Close' : 'Open') + '</button></td></tr>' +
    (open ? '<tr><td colspan="5">' + mxPack() + '</td></tr>' : '');
}

/* One client's pack, as it would go. Looking is not sending, so this draws
   the letter and then asks. */
function mxPack(){
  var p = MX.pack;
  if (!p) return '<p class="mute">Loading the pack…</p>';
  if (p.error) return msg("bad", p.reason || p.error);

  var rec = p.recipients || [];
  var ready = p.branches || [];
  var held = p.heldBack || [];
  var picked = rec.filter(function(r){ return MX.to[r.email]; }).length;
  var may = (MX.month || {}).maySend;

  return '<div class="mxpack">' +
    '<div class="mxsays">' + esc(p.says) + '</div>' +

    (rec.length
      ? '<h4 class="plh">Who it goes to</h4>' +
        '<div class="mxrecs">' + rec.map(function(r){
          return '<label class="mxrec"><input type="checkbox" data-mxto="' + esc(r.email) + '"' +
            (MX.to[r.email] ? ' checked' : '') + '> <b>' + esc(r.email) + '</b> ' +
            '<span class="mute">' + esc(r.kind.toLowerCase().replace(/_/g," ")) +
            (r.name ? ' · ' + esc(r.name) : '') + '</span></label>'; }).join("") + '</div>'
      : msg("warn", "This client has no contacts on file, so there is nobody to send it to. " +
                    "Add them on the client before sending."))  +

    (held.length
      ? '<h4 class="plh">Held back</h4>' +
        '<ul class="mxlist">' + held.map(function(b){
          return '<li>' + esc(b.name) + ' <span class="mute">' + esc(b.code) + ' · ' +
            esc(b.missing) + ' level(s) still blank</span></li>'; }).join("") + '</ul>'
      : '') +

    '<h4 class="plh">' + esc(ready.length) + ' branch(es) in the letter</h4>' +
    (ready.length
      ? '<div class="mxbranches">' + ready.map(mxBranch).join("") + '</div>'
      : '<div class="empty">Nothing is complete enough to send.</div>') +

    '<div class="plbar">' +
      (may
        ? '<button class="btn primary" id="mxsend"' +
            (picked && ready.length ? '' : ' disabled') + '>' +
            (picked && ready.length
              ? 'Send to ' + picked + ' recipient(s)'
              : !ready.length ? 'Nothing to send' : 'Choose at least one recipient') +
          '</button>'
        : '<span class="mute">Operations owns the matrix. You may read this and not send it.</span>') +
      (p.dispatch && p.dispatch.sentAt
        ? '<span class="mute">Already sent ' + esc(day(p.dispatch.sentAt)) +
          '. Sending again replaces the snapshot and is recorded.</span>'
        : '') +
    '</div></div>';
}

function mxBranch(b){
  return '<details class="mxb"><summary>' + esc(b.name) +
    ' <span class="mute">' + esc(b.code) +
    (b.usingClientDefault ? ' · using the client default' : '') + '</span></summary>' +
    '<table class="mxlv">' + (b.levels || []).map(function(l){
      return '<tr><td class="mxl">L' + esc(l.level) + '</td>' +
        '<td>' + esc(l.levelName || "") + '</td>' +
        '<td><b>' + esc(l.name || "—") + '</b></td>' +
        '<td>' + esc(l.mobile || "") + '</td>' +
        '<td>' + esc(l.email || "") + '</td></tr>'; }).join("") + '</table></details>';
}

/* ---------------------------------------------------------------- wiring */
function mxWire(){
  if (el("mxperiod")) el("mxperiod").onchange = async function(){
    MX.period = el("mxperiod").value;
    MX.open = null; MX.pack = null; MX.says = "";
    await mxMonthLoad();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-mxopen]"), function(b){
    b.onclick = async function(){
      var id = b.getAttribute("data-mxopen");
      if (MX.open === id) { MX.open = null; MX.pack = null; mxRender(); return; }
      MX.open = id; MX.pack = null; MX.says = ""; mxRender();
      var p = await ops("/pack/client/" + id + "?period=" + MX.period);
      if (MX.open !== id) return;
      MX.pack = p;
      /* The primary contact and its copies are the people this letter is
         for. They are ticked to start with, and every one of them can be
         un-ticked -- the default is a convenience, not a decision. */
      MX.to = {};
      (p.recipients || []).forEach(function(r){
        if (/PRIMARY|HEAD_OFFICE/.test(r.kind || "")) MX.to[r.email] = true;
      });
      mxRender();
    };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-mxto]"), function(b){
    b.onchange = function(){ MX.to[b.getAttribute("data-mxto")] = b.checked; mxRender(); };
  });

  if (el("mxsend")) el("mxsend").onclick = async function(){
    if (MX.busy) return;
    MX.busy = true; el("mxsend").disabled = true;
    var to = Object.keys(MX.to).filter(function(k){ return MX.to[k]; });
    var o = await ops("/pack/send", { method:"POST", body:{
      clientId: MX.open, period: MX.period, to: to } });
    MX.busy = false;
    MX.says = o.error ? msg("bad", o.reason || o.error) : msg("ok", o.note);
    MX.pack = null;
    await mxMonthLoad();
    if (MX.open) {
      MX.pack = await ops("/pack/client/" + MX.open + "?period=" + MX.period);
      mxRender();
    }
  };
}
