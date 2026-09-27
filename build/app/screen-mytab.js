/* ================================================================== mine
   My profile, as the design draws it.

   The design's own subtitle says what the screen is: "Your details, your
   tasks, and anything you need from another department." The build had the
   first two. The third had nothing at all -- no control, no route, no row
   -- even though the schema was already shaped for it and had been since
   the beginning: `raisable` for the thing asked, `request_task` for the
   duty it puts on somebody, with a due time, a strike count and a place to
   hang an escalation. Two tables, both empty.

   So the left column is the design's: tasks waiting on ME, in a card that
   is the only terracotta thing on the page, because it is the only part
   that is somebody else's clock. The right column is the design's three
   cards -- Employment, Contact, Documents -- and then what I have asked
   other departments for and where each of those got to.

   Nothing here writes to the record. An edit is a request that HR approves,
   which is the design's rule and was already built; this screen keeps it
   and says so under every card.                                         */
var MY = { desk:null, me:null, busy:false, says:"", form:null, open:null };

function myWhen(s){
  if (!s) return "";
  var d = new Date(s), now = new Date();
  var mins = Math.round((d - now) / 60000);
  if (mins <= 0) return "overdue";
  if (mins < 60) return "due in " + mins + " min";
  if (mins < 60 * 20) return "due in " + Math.round(mins / 60) + " working hours";
  return "due " + day(s);
}

/* A state nobody has set is not a state. The design lists four documents
   whether or not they exist; a person who has never been asked for one
   should read as "not asked for", not as a blank that looks like a failing. */
var MY_DOC = { VERIFIED:["ok","verified"], WITH_HR:["warn","with HR"],
               WITH_ACCOUNTS:["warn","with Accounts"],
               REVISION_REQUESTED:["bad","revision requested"] };

async function vProfile(){
  var r = await Promise.all([ hrapi("/hr/desk"), api("/profile") ]);
  MY.desk = r[0] || {}; MY.me = r[1] || {};

  if (MY.desk.error && MY.me.error) {
    el("view").innerHTML = "<h1>My profile</h1>" +
      msg("bad", MY.me.reason || MY.me.error); return;
  }
  myRender();
}

function myRender(){
  var d = MY.desk || {}, p = MY.me || {};

  el("view").innerHTML =
    '<div class="page-head"><div><h1>My profile</h1>' +
      '<p class="mute">Your details, your tasks, and anything you need from ' +
      'another department.</p></div>' +
      '<div><button class="btn primary" id="myask">Raise a request</button></div>' +
    '</div><div id="mymsg">' + MY.says + '</div><div id="mybox"></div>' +

    '<div class="mygrid">' +
      '<div class="mycol">' + myTasks() + '</div>' +
      '<div class="mycol">' +
        myFacts("Employment", d.employment) +
        myFacts("Contact", d.contact) +
        myDocs() +
        myRaised() +
        myWhere() +
      '</div>' +
    '</div>';
  myWire();
}

/* ------------------------------------------------- tasks waiting on me */
function myTasks(){
  var d = MY.desk || {}, p = MY.me || {};
  var onMe = d.onMe || [], due = d.dueToday || [];
  var reqs = p.requests || [], cases = p.cases || [], notices = p.notices || [];
  var n = onMe.length + due.length + reqs.length + cases.length;

  var body = "";

  onMe.forEach(function(t){
    body += '<div class="mytask' + (t.overdue ? ' late' : '') + '">' +
      '<div class="myt">' + esc(t.body) + '</div>' +
      '<div class="mute">' + esc(t.from) + ' · ' + esc(t.department) +
        ' · ' + esc(t.ref) + '</div>' +
      '<div class="' + (t.overdue ? 'mylate' : 'mute') + '">' + esc(myWhen(t.dueAt)) +
        (t.strikes ? ' · strike ' + esc(t.strikes) + ' of 3' : '') + '</div>' +
      '<button class="btn" data-myact="' + esc(t.taskId) + '">Action it</button>' +
      '</div>';
  });

  due.forEach(function(x){
    if (x.alreadyFiled) return;
    body += '<div class="mytask">' +
      '<div class="myt">File ' + esc(x.name) +
        (x.split ? ' <span class="mute">' + esc(x.split) + '</span>' : '') + '</div>' +
      '<div class="mute">due from you today' +
        (x.target ? ' · target ' + esc(x.target) + ' ' + esc(x.unit || "") : '') + '</div>' +
      '<button class="btn" onclick="location.hash=\'#perf\'">Action it</button>' +
      '</div>';
  });

  reqs.forEach(function(x){
    body += '<div class="mytask">' +
      '<div class="myt">A person to approve · ' + esc(x.full_name) + '</div>' +
      '<div class="mute">' + esc(x.chair || "no chair named") + ' · ' +
        esc(x.state === 'AWAITING_HR' ? 'waiting on HR' : 'waiting on the administrator') +
        (x.due_at ? ' · ' + esc(when(x.due_at)) : '') + '</div>' +
      '<button class="btn" onclick="location.hash=\'#joining\'">Action it</button>' +
      '</div>';
  });

  cases.forEach(function(c){
    body += '<div class="mytask">' +
      '<div class="myt">' + esc(c.ref) + ' · ' + esc(c.category) + '</div>' +
      '<div class="mute">' + esc(c.status) +
        (c.next_chase_at ? ' · next chase ' + esc(when(c.next_chase_at)) : '') + '</div>' +
      '<button class="btn" onclick="location.hash=\'#cases\'">Action it</button>' +
      '</div>';
  });

  return '<div class="card mytasks"><h2>Tasks waiting on me</h2>' +
    (n ? body
       : '<div class="empty">Nothing is waiting on you. A request from another ' +
         'department, a number due from you today, an approval, or an escalation ' +
         'you are a party to would appear here.</div>') +
    (notices.length
      ? '<h4 class="plh">Told to you</h4>' +
        notices.slice(0, 8).map(function(x){
          return '<div class="mytask quiet"><div>' + esc(x.text) + '</div>' +
            '<div class="mute">' + esc(when(x.at)) + '</div></div>'; }).join("")
      : '') +
    '</div>';
}

/* --------------------------------------------- employment and contact */
function myFacts(title, rows){
  rows = rows || [];
  return '<div class="card"><h2>' + esc(title) + '</h2>' +
    rows.map(function(x){
      return '<div class="cfgrow"><div><b>' + esc(x.label) + '</b>' +
        '<div>' + (x.value ? esc(x.value) : '<span class="mute">not recorded</span>') +
        '</div></div>' +
        (x.field
          ? '<div class="cfgset"><button class="btn" data-myf="' + esc(x.field) +
            '" data-myw="' + esc(x.value || "") + '" data-myl="' + esc(x.label) +
            '">Edit</button></div>'
          : '') + '</div>';
    }).join("") +
    '<p class="mute">' + esc((MY.desk || {}).says || "") + '</p></div>';
}

function myDocs(){
  var docs = (MY.desk || {}).documents || [];
  return '<div class="card"><h2>Documents</h2>' +
    docs.map(function(x){
      var s = MY_DOC[x.state];
      return '<div class="cfgrow"><div><b>' + esc(x.label) + '</b>' +
        (x.note ? '<div class="mute">' + esc(x.note) + '</div>' : '') +
        '</div><div class="cfgset">' +
        (s ? '<span class="pill ' + s[0] + '">' + esc(s[1]) + '</span>'
           : '<span class="mute">not asked for</span>') +
        '</div></div>';
    }).join("") +
    '<p class="mute">A document you have never been asked for is not the same as ' +
    'one you have not produced, so it says which. HR records what it has seen; ' +
    'nothing here uploads a file yet.</p></div>';
}

/* ------------------------------------------ what I asked other people for */
function myRaised(){
  var rows = (MY.desk || {}).raised || [];
  if (!rows.length) {
    return '<div class="card"><h2>What you have asked for</h2>' +
      '<div class="empty">You have not asked another department for anything. ' +
      'Raise a request and it becomes a task on somebody there, with a time on ' +
      'it -- and if it is not answered, that counts against them, not you.</div></div>';
  }
  return '<div class="card"><h2>What you have asked for</h2>' +
    '<div class="scroll"><table>' +
    '<tr><th>Ref</th><th>What</th><th>With</th><th>State</th></tr>' +
    rows.map(function(x){
      return '<tr><td>' + esc(x.ref) + '</td>' +
        '<td>' + esc(x.body) + '<div class="mute">' + esc(x.department) + '</div></td>' +
        '<td>' + esc(x.responder) + '</td>' +
        '<td>' + (x.actionedAt
          ? '<span class="pill ok">answered ' + esc(day(x.actionedAt)) + '</span>'
          : '<span class="pill ' + (x.strikes ? 'bad' : 'warn') + '">' +
            esc(myWhen(x.dueAt)) + '</span>' +
            (x.strikes ? '<div class="mute">strike ' + esc(x.strikes) + ' of 3</div>' : '')) +
        '</td></tr>';
    }).join("") + '</table></div></div>';
}

/* ------------------------------------------------ the chair and the reach */
function myWhere(){
  var p = MY.me || {}, chairs = p.chairs || [], cov = p.coverage || {},
      events = p.events || [];
  return '<div class="card"><h2>Where you sit</h2>' +
    (chairs.length
      ? '<div class="scroll"><table><tr><th>Chair</th><th>Code</th>' +
        '<th>Reports to</th><th>Since</th></tr>' +
        chairs.map(function(c){
          return '<tr><td>' + esc(c.title) +
            (c.is_primary ? ' <span class="chip ok">primary</span>' : '') + '</td>' +
            '<td>' + esc(c.code) + '</td><td>' + esc(c.reports_to || "-") + '</td>' +
            '<td>' + esc(c.from_date ? day(c.from_date) : "") + '</td></tr>';
        }).join("") + '</table></div>'
      : '<div class="empty">You hold no chair. ' +
        (p.isAdmin
          ? 'You are an administrator, so the tool shows you everything anyway -- but a '
            + 'chair is what the appraisal and escalation ladders hang off.'
          : 'A chair is what the tool resolves your view from. Ask HR to seat you.') +
        '</div>') +
    (Number(cov.branches || 0)
      ? '<p class="mute">' + esc(cov.branches) + ' branches, ' + esc(cov.clients) +
        ' clients, ' + esc(cov.locations) + ' locations. Coverage is what decides ' +
        'which branches, cases and scores you see -- not your job title.</p>'
      : '<p class="mute">No coverage is assigned to you, so the operational screens ' +
        'have nothing to draw.</p>') +
    (events.length
      ? '<h4 class="plh">Your record</h4><div class="scroll"><table>' +
        '<tr><th>When</th><th>Kind</th><th>Note</th></tr>' +
        events.slice(0, 20).map(function(e){
          return '<tr><td>' + esc(when(e.at)) + '</td><td>' + esc(e.kind) +
            (e.note_class && e.note_class !== 'UNCLASSIFIED'
              ? ' <span class="chip">' + esc(e.note_class) + '</span>' : '') + '</td>' +
            '<td class="mute">' + esc(e.note || "") + '</td></tr>';
        }).join("") + '</table></div>'
      : '') +
    '</div>';
}

/* ------------------------------------------------------------- the forms */
function myAskForm(){
  var depts = (MY.desk || {}).departments || [];
  return '<div class="card"><h2>Raise a request</h2>' +
    '<p class="mute">To any department. It becomes a task on somebody there with a ' +
    'time on it. An unactioned request counts against the responder, not against ' +
    'you -- so ask, rather than chasing.</p>' +
    '<div class="hragrid">' +
      '<label class="hrafield"><span>Department</span><select id="myd">' +
        '<option value="">— choose —</option>' +
        depts.map(function(x){
          return '<option value="' + esc(x.name) + '">' + esc(x.name) +
            ' <span>(' + esc(x.people) + ')</span></option>'; }).join("") +
      '</select></label>' +
      '<label class="hrafield"><span>Type</span><select id="myt2">' +
        ['Document','Correction to my details','Access','Equipment','Other']
          .map(function(x){ return '<option>' + x + '</option>'; }).join("") +
      '</select></label>' +
    '</div>' +
    '<div style="padding:8px 15px"><label>What you need<br>' +
      '<textarea id="myb" placeholder="The thing you need, as the person answering ' +
      'will read it."></textarea></label></div>' +
    '<div class="plbar"><button class="btn primary" id="mysend">Send request</button>' +
      '<button class="btn" id="mycancel">Cancel</button></div>' +
    '<div id="myboxmsg"></div></div>';
}

function myEditForm(field, was, label){
  return '<div class="card"><h2>Ask for ' + esc(label).toLowerCase() +
      ' to be changed</h2>' +
    '<p class="mute">Nothing changes when you send this. It goes to HR with your ' +
    'current value beside the one you want, and HR makes the change.</p>' +
    '<div class="hragrid">' +
      '<label class="hrafield"><span>It says now</span>' +
        '<input value="' + esc(was) + '" disabled></label>' +
      '<label class="hrafield"><span>It should say</span>' +
        '<input id="myNew" value="' + esc(was) + '"></label>' +
      '<label class="hrafield"><span>Why</span>' +
        '<input id="myWhy" placeholder="optional"></label>' +
    '</div>' +
    '<div class="plbar"><button class="btn primary" id="myGo">Send it to HR</button>' +
      '<button class="btn" id="mycancel">Cancel</button></div>' +
    '<div id="myboxmsg"></div></div>';
}

/* ---------------------------------------------------------------- wiring */
function myWire(){
  if (el("myask")) el("myask").onclick = function(){
    el("mybox").innerHTML = myAskForm();
    el("mybox").scrollIntoView({ behavior:"smooth", block:"nearest" });
    myWireBox();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-myf]"), function(b){
    b.onclick = function(){
      el("mybox").innerHTML = myEditForm(b.getAttribute("data-myf"),
        b.getAttribute("data-myw"), b.getAttribute("data-myl"));
      el("mybox").scrollIntoView({ behavior:"smooth", block:"nearest" });
      myWireBox(b.getAttribute("data-myf"), b.getAttribute("data-myw"));
    };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-myact]"), function(b){
    b.onclick = async function(){
      if (MY.busy) return;
      MY.busy = true; b.disabled = true;
      var o = await hrapi("/hr/desk/request/action", { method:"POST",
        body:{ taskId: b.getAttribute("data-myact") } });
      MY.busy = false;
      MY.says = o.error ? msg("bad", o.reason || o.error) : msg("ok", o.note);
      await vProfile();
    };
  });
}

function myWireBox(field, was){
  if (el("mycancel")) el("mycancel").onclick = function(){ el("mybox").innerHTML = ""; };

  if (el("mysend")) el("mysend").onclick = async function(){
    if (MY.busy) return;
    if (!el("myd").value) {
      el("myboxmsg").innerHTML = msg("bad", "Choose the department it is for.");
      return;
    }
    MY.busy = true; el("mysend").disabled = true;
    var o = await hrapi("/hr/desk/request", { method:"POST", body:{
      department: el("myd").value, type: el("myt2").value, body: el("myb").value } });
    MY.busy = false;
    if (o.error) {
      el("myboxmsg").innerHTML = msg("bad", o.reason || o.error);
      el("mysend").disabled = false; return;
    }
    el("mybox").innerHTML = "";
    MY.says = msg("ok", o.note);
    await vProfile();
  };

  if (el("myGo")) el("myGo").onclick = async function(){
    if (MY.busy) return;
    MY.busy = true; el("myGo").disabled = true;
    var o = await api("/profile/change", { method:"POST", body:{
      field: field, was: was, now: el("myNew").value, why: el("myWhy").value } });
    MY.busy = false;
    if (o.error) {
      el("myboxmsg").innerHTML = msg("bad", o.reason || o.error);
      el("myGo").disabled = false; return;
    }
    el("mybox").innerHTML = "";
    MY.says = msg("ok", o.toldHr
      ? "Sent. HR has been told, by notice and by e-mail. Nothing has changed yet."
      : "Recorded against your file. No HR address is set, so nobody has been " +
        "e-mailed -- tell them yourself.");
    await vProfile();
  };
}
