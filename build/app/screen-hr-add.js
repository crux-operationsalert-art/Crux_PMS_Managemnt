/* ================================================================ hr-add
   Adding a person.

   The rule this screen is built to: a person added here cannot be added
   wrong. Not "is warned about" -- cannot. Every field is checked by
   person_check() in the database, which is the same function person_add()
   calls before it writes, so the form and the writer cannot disagree. The
   screen never decides anything itself; it asks, and it shows the answer.

   It checks as you type rather than on submit, because the alternative is
   finding the second problem only after fixing the first. And it shows
   warnings beside errors, in a different colour, because "that mobile is
   already against somebody" should not stop you and "that address belongs
   to somebody" must.

   The employee number is pre-filled with the next free one. It is the
   field that matters most and the one most likely to be left blank: every
   performance upload joins people BY employee number, so a person without
   one has their rows dropped in silence. Eleven active staff are in that
   state today, which is how this screen came to exist.                  */
var HRA = { open:false, opts:null, form:{}, chk:null, busy:false, d:null };

/* vHR hands the overview over on every draw, because the card only exists
   for somebody HR, and only vHR knows whether this viewer is. */
function hraHost(d){ HRA.d = d; return '<div id="hracard">' + hraCard(d) + '</div>'; }

function hraSet(k, v){ HRA.form[k] = v; }
function hraVal(k){ var v = HRA.form[k]; return v === undefined || v === null ? "" : v; }

/* Errors and warnings are the same shape; only the colour and the weight
   differ, and the difference is the whole point. */
function hraSays(field){
  var c = HRA.chk;
  if (!c) return "";
  var e = (c.errors || []).filter(function(x){ return x.field === field; });
  var w = (c.warnings || []).filter(function(x){ return x.field === field; });
  return e.map(function(x){ return '<div class="hrabad">' + esc(x.says) + '</div>'; }).join("") +
         w.map(function(x){ return '<div class="hrawarn">' + esc(x.says) + '</div>'; }).join("");
}
function hraBad(field){
  var c = HRA.chk;
  return c && (c.errors || []).some(function(x){ return x.field === field; }) ? " hraerr" : "";
}

function hraField(field, label, kind, extra){
  return '<label class="hrafield' + hraBad(field) + '">' +
    '<span>' + esc(label) + '</span>' +
    '<input data-hra="' + esc(field) + '" type="' + (kind || "text") + '" ' +
      (extra || "") + ' value="' + esc(hraVal(field)) + '">' +
    hraSays(field) + '</label>';
}

function hraPick(field, label, options, extra){
  return '<label class="hrafield' + hraBad(field) + '">' +
    '<span>' + esc(label) + '</span>' +
    '<select data-hra="' + esc(field) + '" ' + (extra || "") + '>' + options + '</select>' +
    hraSays(field) + '</label>';
}

/* --------------------------------------------------------------- the card */
function hraCard(d){
  if (!d || !d.isHr) return "";
  if (!HRA.open) {
    return '<div class="card"><h2>Add a person</h2>' +
      '<p class="mute">Nine fields, all checked as you type. The employee number is ' +
      'required because every performance upload joins people by it — somebody added ' +
      'without one has their rows dropped and nothing says so.</p>' +
      '<p><button class="btn primary" id="hraopen">Add a person</button></p></div>';
  }
  var o = HRA.opts;
  if (!o) return '<div class="card"><h2>Add a person</h2>' +
    '<p class="mute">Loading the chairs, managers and places…</p></div>';

  var chairs = '<option value="">— choose a chair —</option>' +
    (o.chairs || []).map(function(c){
      return '<option value="' + esc(c.id) + '"' +
        (hraVal("chairId") === c.id ? ' selected' : '') + '>' + esc(c.title) +
        (c.inScheme ? ' · in the PLB scheme' : '') +
        (Number(c.seatedNow) ? ' · ' + esc(c.seatedNow) + ' seated' : ' · vacant') +
        '</option>'; }).join("");

  var mgrs = '<option value="">— nobody —</option>' +
    (o.managers || []).map(function(m){
      return '<option value="' + esc(m.id) + '"' +
        (hraVal("managerId") === m.id ? ' selected' : '') + '>' + esc(m.name) +
        (m.chair ? ' · ' + esc(m.chair) : '') + '</option>'; }).join("");

  var places = '<option value="">— no place —</option>' +
    (o.places || []).map(function(p){
      return '<option value="' + esc(p.id) + '"' +
        (hraVal("placeId") === p.id ? ' selected' : '') + '>' + esc(p.name) +
        ' · ' + esc(p.zone) + '</option>'; }).join("");

  var desigs = '<option value="">— none —</option>' +
    (o.designations || []).map(function(x){
      return '<option value="' + esc(x.id) + '"' +
        (hraVal("designationId") === x.id ? ' selected' : '') + '>' + esc(x.title) +
        '</option>'; }).join("");

  var types = (o.employeeTypes || []).map(function(t){
    return '<option value="' + esc(t) + '"' +
      ((hraVal("employeeType") || "EMPLOYEE") === t ? ' selected' : '') + '>' +
      esc(t.toLowerCase().replace(/_/g, " ")) + '</option>'; }).join("");

  var roles = ["VIEWER","MANAGER","LOCATION_HEAD","ADMIN"].map(function(t){
    return '<option value="' + esc(t) + '"' +
      ((hraVal("appRole") || "VIEWER") === t ? ' selected' : '') + '>' +
      esc(t.toLowerCase().replace(/_/g, " ")) + '</option>'; }).join("");

  var depts = (o.departments || []).map(function(x){
    return '<option value="' + esc(x) + '"></option>'; }).join("");

  var ok = HRA.chk && HRA.chk.ok;

  return '<div class="card"><h2>Add a person</h2>' +
    '<p class="mute">Checked against the database as you type, by the same function that ' +
    'checks again before anything is written — so the form and the writer cannot ' +
    'disagree with each other.</p>' +
    '<div class="hragrid">' +
      hraField("fullName", "Full name") +
      hraPick("employeeType", "They are a", types) +
      hraField("employeeNo", "Employee number", "text",
        'placeholder="' + esc((o.nextEmployeeNo || "")) + '"') +
      hraField("workEmail", "Work e-mail", "email") +
      hraField("mobile", "Mobile", "tel", 'placeholder="10 digits, or paste it with +91"') +
      hraField("personalEmail", "Personal e-mail (optional)", "email") +
      hraPick("chairId", "Chair", chairs) +
      hraPick("managerId", "Reports to", mgrs) +
      hraPick("placeId", "Place (optional)", places) +
      hraPick("designationId", "Designation (optional)", desigs) +
      '<label class="hrafield' + hraBad("department") + '"><span>Department</span>' +
        '<input data-hra="department" list="hradepts" value="' + esc(hraVal("department")) + '">' +
        '<datalist id="hradepts">' + depts + '</datalist>' + hraSays("department") + '</label>' +
      hraField("joinedOn", "Joining date", "date") +
      hraPick("appRole", "What they may do in the tool", roles) +
    '</div>' +
    '<p class="mute">A viewer sees their own work. Only an administrator can create ' +
    'another administrator — ask for one to be raised rather than created, so the ' +
    'raising is somebody\'s decision and is in the trail as one.</p>' +
    '<div class="plbar">' +
      '<button class="btn primary" id="hraadd"' + (ok ? '' : ' disabled') + '>' +
        (ok ? "Add them" : "Fix what is marked first") + '</button>' +
      '<button class="btn" id="hranext">Use ' + esc(o.nextEmployeeNo || "") + '</button>' +
      '<button class="btn" id="hracancel">Cancel</button>' +
    '</div>' +
    '<div id="hramsg"></div></div>';
}

/* ------------------------------------------------------------ the wiring */
async function hraCheck(){
  HRA.chk = await hrapi("/hr/check", { method:"POST", body: HRA.form });
  hraRepaint();
}

/* Repainting the whole card on every keystroke would move the caret, so the
   messages are patched in place and only a structural change redraws. */
function hraRepaint(){
  var host = el("hracard");
  if (!host) return;
  var focused = document.activeElement;
  var key = focused && focused.getAttribute ? focused.getAttribute("data-hra") : null;
  var pos = focused && focused.selectionStart;
  host.innerHTML = hraCard(HRA.d);
  hraWire();
  if (key) {
    var back = el("view").querySelector('[data-hra="' + key + '"]');
    if (back) {
      back.focus();
      if (pos !== null && pos !== undefined && back.setSelectionRange) {
        try { back.setSelectionRange(pos, pos); } catch (e) { /* selects have none */ }
      }
    }
  }
}

function hraWire(){
  if (el("hraopen")) el("hraopen").onclick = async function(){
    HRA.open = true;
    hraRepaint();
    HRA.opts = await hrapi("/hr/options");
    if (HRA.opts.error) {
      var why = HRA.opts.reason || HRA.opts.error;
      HRA.opts = null; HRA.open = false;
      hraRepaint();
      var m = el("hramsg") || el("hracard");
      if (m) m.innerHTML = msg("bad", why);
      return;
    }
    if (!hraVal("employeeNo")) hraSet("employeeNo", HRA.opts.nextEmployeeNo);
    hraRepaint();
  };

  if (el("hracancel")) el("hracancel").onclick = function(){
    HRA.open = false; HRA.form = {}; HRA.chk = null; hraRepaint();
  };

  if (el("hranext")) el("hranext").onclick = function(){
    hraSet("employeeNo", HRA.opts && HRA.opts.nextEmployeeNo);
    hraCheck();
  };

  var timer = null;
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-hra]"), function(f){
    var k = f.getAttribute("data-hra");
    f.oninput = function(){
      hraSet(k, f.value);
      clearTimeout(timer);
      timer = setTimeout(hraCheck, 350);
    };
    f.onchange = function(){ hraSet(k, f.value); hraCheck(); };
  });

  if (el("hraadd")) el("hraadd").onclick = async function(){
    if (HRA.busy) return;
    HRA.busy = true; el("hraadd").disabled = true;
    var out = await hrapi("/hr/add", { method:"POST", body: HRA.form });
    HRA.busy = false;
    if (out.error) {
      HRA.chk = { ok:false, errors: out.errors || [], warnings: out.warnings || [] };
      hraRepaint();
      var m = el("hramsg");
      if (m) m.innerHTML = msg("bad", out.reason || out.error);
      return;
    }
    HRA.open = false; HRA.form = {}; HRA.chk = null;
    hraRepaint();
    var box = el("hramsg");
    if (box) box.innerHTML = msg("ok", out.note);
    setTimeout(function(){ route(); }, 1600);
  };
}
