/* ------------------------------------------------------------- my profile
   The design: your details, your tasks, and anything you need from another
   department. Two things it is firm about and this keeps. Your tasks are
   whatever is genuinely waiting on YOU -- so when nothing is, it says so
   rather than inventing a queue. And an edit is NOT live: it is raised, HR
   approves, and the old and new values sit side by side until they do.   */
async function vProfile(){
  var d = await api("/profile");
  if (d.error) {
    el("view").innerHTML = "<h1>My profile</h1>" + msg("bad", d.reason || d.error); return;
  }
  var p = d.person || {}, chairs = d.chairs || [], cov = d.coverage || {};
  var reqs = d.requests || [], notices = d.notices || [], cases = d.cases || [];
  var events = d.events || [];
  var tasks = reqs.length + notices.length + cases.length;

  function row(label, value, field){
    return '<div class="cfgrow"><div><b>' + esc(label) + '</b>' +
      '<div>' + (value ? esc(value) : '<span class="mute">not recorded</span>') + '</div></div>' +
      (field ? '<div class="cfgset"><button class="btn" data-pf="' + esc(field) +
        '" data-pfwas="' + esc(value || "") + '" data-pflabel="' + esc(label) +
        '">Edit</button></div>' : '') + '</div>';
  }

  el("view").innerHTML =
    '<div class="page-head"><div><h1>My profile</h1>' +
    '<p class="mute">Your details, your tasks, and anything you need from another ' +
    'department.</p></div></div><div id="pfmsg"></div><div id="pfbox"></div>' +

    '<div class="card"><h2>Tasks waiting on me</h2>' +
      (tasks
        ? (reqs.length ? '<div class="scroll"><table>' +
            '<tr><th>What</th><th>Who</th><th>Stage</th><th>Due</th></tr>' +
            reqs.map(function(x){
              return '<tr><td>A person to approve</td><td>' + esc(x.full_name) +
                (x.chair ? ' <span class="mute">' + esc(x.chair) + '</span>' : '') + '</td>' +
                '<td>' + esc(x.state === 'AWAITING_HR' ? 'waiting on HR' : 'waiting on the administrator') +
                '</td><td>' + esc(x.due_at ? when(x.due_at) : "") + '</td></tr>';
            }).join("") + '</table></div>' : '') +
          (cases.length ? '<div class="scroll"><table>' +
            '<tr><th>Escalation</th><th>Category</th><th>Status</th><th>Next chase</th></tr>' +
            cases.map(function(c){
              return '<tr><td>' + esc(c.ref) + '</td><td>' + esc(c.category) + '</td>' +
                '<td>' + esc(c.status) + '</td><td>' + esc(c.next_chase_at ? when(c.next_chase_at) : "") +
                '</td></tr>';
            }).join("") + '</table></div>' : '') +
          (notices.length ? notices.map(function(n){
              return '<div class="cfgrow"><div><b>' + esc(n.kind) + '</b>' +
                '<div class="mute">' + esc(n.text) + '</div>' +
                '<div class="mute">' + esc(when(n.at)) + '</div></div></div>';
            }).join("") : "")
        : '<div class="empty">Nothing is waiting on you. Approvals, escalations you ' +
          'are a party to, and anything another department has asked you for would ' +
          'appear here.</div>') +
    '</div>' +

    '<div class="card"><h2>You</h2>' +
      row("Name", p.full_name, "full_name") +
      row("Work e-mail", p.work_email, "work_email") +
      row("Mobile", p.mobile, "mobile") +
      row("Employee number", p.employee_no, null) +
      row("Department", p.department, "department") +
      row("Designation", p.designation, null) +
      row("Reports to", p.manager ? (p.manager + (p.manager_no ? " (" + p.manager_no + ")" : "")) : "", null) +
      row("Employment", [p.employee_type, p.employment_status].filter(Boolean).join(" &middot; "), null) +
      '<p class="mute">Edits are not live. HR approves, then the record changes, and ' +
      'your old and new values sit side by side on their task until it does.</p>' +
    '</div>' +

    '<div class="card"><h2>Where you sit</h2>' +
      (chairs.length
        ? '<div class="scroll"><table><tr><th>Chair</th><th>Code</th><th>Reports to</th>' +
          '<th>Since</th></tr>' +
          chairs.map(function(c){
            return '<tr><td>' + esc(c.title) +
              (c.is_primary ? ' <span class="chip ok">primary</span>' : '') + '</td>' +
              '<td>' + esc(c.code) + '</td><td>' + esc(c.reports_to || "-") + '</td>' +
              '<td>' + esc(c.from_date ? day(c.from_date) : "") + '</td></tr>';
          }).join("") + '</table></div>'
        : '<div class="empty">You hold no chair. ' +
          (d.isAdmin
            ? 'You are an administrator, so the tool shows you everything anyway -- but a '
              + 'chair is what the appraisal and escalation ladders hang off, so it is worth having one.'
            : 'A chair is what the tool resolves your view from. Ask HR to seat you.') +
          '</div>') +
    '</div>' +

    '<div class="card"><h2>What you cover</h2>' +
      (Number(cov.branches || 0)
        ? '<p>' + esc(cov.branches) + ' branches, ' + esc(cov.clients) + ' clients, ' +
          esc(cov.locations) + ' locations. Coverage is what decides which branches, ' +
          'cases and scores you see -- not your job title.</p>'
        : '<div class="empty">No coverage is assigned to you, so the operational ' +
          'screens have nothing to draw. Operations assigns it under Coverage &amp; ' +
          'handlers.</div>') +
    '</div>' +

    '<div class="card"><h2>Your record</h2>' +
      (events.length
        ? '<div class="scroll"><table><tr><th>When</th><th>Kind</th><th>Note</th></tr>' +
          events.map(function(e){
            return '<tr><td>' + esc(when(e.at)) + '</td><td>' + esc(e.kind) +
              (e.note_class && e.note_class !== 'UNCLASSIFIED'
                ? ' <span class="chip">' + esc(e.note_class) + '</span>' : '') + '</td>' +
              '<td class="mute">' + esc(e.note || "") + '</td></tr>';
          }).join("") + '</table></div>'
        : '<div class="empty">Nothing is recorded against you yet.</div>') +
    '</div>';

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pf]"), function(b){
    b.onclick = function(){
      var field = b.getAttribute("data-pf"), was = b.getAttribute("data-pfwas");
      el("pfbox").innerHTML =
        '<div class="card"><h2>Ask for ' + esc(b.getAttribute("data-pflabel")).toLowerCase() +
          ' to be changed</h2>' +
        '<p class="mute">Nothing changes when you send this. It goes to HR with your ' +
        'current value beside the one you want, and HR makes the change.</p>' +
        '<label>It says now<br><input value="' + esc(was) + '" disabled></label> ' +
        '<label>It should say<br><input id="pfNew" value="' + esc(was) + '"></label> ' +
        '<label>Why<br><input id="pfWhy" placeholder="optional"></label> ' +
        '<button class="btn primary" id="pfGo">Send it to HR</button> ' +
        '<button class="btn" id="pfCancel">Cancel</button><div id="pfboxmsg"></div></div>';
      el("pfbox").scrollIntoView({ behavior:"smooth", block:"nearest" });
      el("pfCancel").onclick = function(){ el("pfbox").innerHTML = ""; };
      el("pfGo").onclick = async function(){
        el("pfGo").disabled = true;
        var out = await api("/profile/change", { method:"POST", body:{
          field: field, was: was, now: el("pfNew").value, why: el("pfWhy").value } });
        el("pfGo").disabled = false;
        if (out.error) { el("pfboxmsg").innerHTML = msg("bad", out.reason || out.error); return; }
        el("pfbox").innerHTML = "";
        el("pfmsg").innerHTML = msg("ok", out.toldHr
          ? "Sent. HR has been told, by notice and by e-mail. Nothing has changed yet."
          : "Recorded against your file. No HR address is set, so nobody has been e-mailed -- tell them yourself.");
        vProfile();
      };
    };
  });
}
/* ------------------------------------------------ hiring & pending chairs
   The design: the hire requests in flight with the stage each is at, a risk
   register of chairs nobody owns, and the empty chairs nobody has even asked
   about. The chain behind it already worked end to end -- raise, HR approves,
   the administrator seats and the activation e-mail goes out. What was
   missing was anywhere to see the chairs sitting empty.                   */
async function vHiring(){
  var d = await api("/people/hiring");
  if (d.error) {
    el("view").innerHTML = "<h1>Hiring &amp; pending chairs</h1>" +
      msg("bad", d.reason || d.error); return;
  }
  var reqs = d.requests || [], vac = d.vacant || [];
  var withKids = vac.filter(function(v){ return Number(v.below) > 0; });
  var asked = vac.filter(function(v){ return v.has_request; }).length;

  function stage(x){
    if (x.state === 'AWAITING_HR') return '<span class="pill warn">waiting on HR</span>';
    if (x.state === 'AWAITING_ADMIN') return '<span class="pill warn">waiting on the administrator</span>';
    if (x.state === 'ACTIVE') return '<span class="pill ok">seated</span>';
    return '<span class="pill">' + esc(x.state) + '</span>';
  }

  el("view").innerHTML =
    '<div class="page-head"><div><h1>Hiring &amp; pending chairs</h1>' +
    '<p class="mute">' + esc(vac.length) + ' chairs have nobody in them, and ' +
      esc(withKids.length) + ' of those have other chairs reporting into them -- ' +
      'which is what makes a vacancy a risk rather than a gap. ' +
      esc(reqs.length) + ' hire requests are in flight.</p></div>' +
    (d.mayRaise ? '<div><button class="btn primary" id="hrAdd">Raise a hire</button></div>' : '') +
    '</div><div id="hrmsg"></div><div id="hrbox"></div>' +

    '<div class="card"><h2>Hire requests</h2>' +
      (reqs.length
        ? '<div class="scroll"><table><tr><th>Who</th><th>Chair</th><th>Stage</th>' +
          '<th>Raised by</th><th>Due</th><th></th></tr>' +
          reqs.map(function(x){
            var act = "";
            if (x.state === 'AWAITING_HR' && d.mayApprove)
              act = '<button class="btn" data-hrapp="'+esc(x.id)+'">Approve the chair</button>';
            if (x.state === 'AWAITING_ADMIN' && d.maySeat)
              act = '<button class="btn primary" data-hrseat="'+esc(x.id)+'">Create the account</button>';
            return '<tr><td>' + esc(x.full_name) + '<div class="mute">' +
              esc(x.work_email || "") + '</div></td>' +
              '<td>' + esc(x.chair || "-") + '</td><td>' + stage(x) + '</td>' +
              '<td>' + esc(x.raised_by || "") + '</td>' +
              '<td>' + esc(x.due_at ? when(x.due_at) : "") + '</td><td>' + act + '</td></tr>';
          }).join("") + '</table></div>'
        : '<div class="empty">No hire has been raised. Raise one against a chair ' +
          'below and it goes to HR, then to the administrator, who creates the ' +
          'account and sends the activation code.</div>') +
    '</div>' +

    '<div class="card"><h2>Risk register &middot; chairs nobody owns</h2>' +
    '<p class="mute">Ordered by how many chairs report into the empty one. A chair ' +
      'with people underneath it and nobody in it is where an escalation stops ' +
      'moving.' + (asked ? ' ' + esc(asked) + ' already have a request against them.' : '') +
      '</p>' +
      (vac.length
        ? '<div class="scroll"><table><tr><th>Chair</th><th>Code</th><th>Reports to</th>' +
          '<th>Chairs below</th><th></th></tr>' +
          vac.map(function(v){
            return '<tr><td>' + esc(v.title) + '</td><td>' + esc(v.code) + '</td>' +
              '<td>' + esc(v.reports_to || "-- top of the tree") + '</td>' +
              '<td>' + (Number(v.below)
                 ? '<span class="pill bad">' + esc(v.below) + '</span>'
                 : '<span class="mute">none</span>') + '</td>' +
              '<td>' + (v.has_request
                 ? '<span class="chip ok">asked for</span>'
                 : (d.mayRaise ? '<button class="btn" data-hrfor="'+esc(v.id)+'" ' +
                     'data-hrtitle="'+esc(v.title)+'">Raise a hire</button>' : '')) +
              '</td></tr>';
          }).join("") + '</table></div>'
        : '<div class="empty">Every chair has somebody in it.</div>') +
    '</div>';

  if (el("hrAdd")) el("hrAdd").onclick = function(){ hrForm(vac, null, null); };
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-hrfor]"), function(b){
    b.onclick = function(){
      hrForm(vac, b.getAttribute("data-hrfor"), b.getAttribute("data-hrtitle"));
    };
  });
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-hrapp]"), function(b){
    b.onclick = async function(){
      b.disabled = true;
      var out = await api("/people/request/" + encodeURIComponent(b.getAttribute("data-hrapp")) +
        "/approve", { method:"POST", body:{} });
      b.disabled = false;
      if (out.error) { el("hrmsg").innerHTML = msg("bad", out.reason || out.error); return; }
      el("hrmsg").innerHTML = msg("ok", "Approved. It is now with the administrator.");
      vHiring();
    };
  });
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-hrseat]"), function(b){
    b.onclick = async function(){
      if (!confirm("Create the account? The person is created, seated in the chair, " +
        "and an activation code is e-mailed to the address HR approved.")) return;
      b.disabled = true;
      var out = await api("/people/request/" + encodeURIComponent(b.getAttribute("data-hrseat")) +
        "/seat", { method:"POST", body:{} });
      b.disabled = false;
      if (out.error) { el("hrmsg").innerHTML = msg("bad", out.reason || out.error); return; }
      el("hrmsg").innerHTML = msg("ok", "Account created. The activation code is on its way.");
      vHiring();
    };
  });
}

function hrForm(vac, chairId, chairTitle){
  el("hrbox").innerHTML =
    '<div class="card"><h2>Raise a hire' + (chairTitle ? ' for ' + esc(chairTitle) : '') + '</h2>' +
    '<p class="mute">This names the person and the chair. HR approves the chair and ' +
    'the terms, then the administrator creates the account and the activation code ' +
    'goes out. Nobody is created by signing in.</p>' +
    (chairId ? '' :
      '<label>Chair<br><select id="hrChair">' +
        vac.map(function(v){
          return '<option value="'+esc(v.id)+'">' + esc(v.title) + ' -- ' + esc(v.code) +
            (Number(v.below) ? ' (' + esc(v.below) + ' below)' : '') + '</option>';
        }).join("") + '</select></label> ') +
    '<label>Full name<br><input id="hrName"></label> ' +
    '<label>Work e-mail<br><input id="hrMail" type="email"></label> ' +
    '<label>Kind<br><select id="hrType">' +
      '<option value="EMPLOYEE">Employee</option>' +
      '<option value="PARTNER">Partner</option></select></label> ' +
    '<button class="btn primary" id="hrGo">Send it to HR</button> ' +
    '<button class="btn" id="hrCancel">Cancel</button><div id="hrboxmsg"></div></div>';
  el("hrbox").scrollIntoView({ behavior:"smooth", block:"nearest" });
  el("hrCancel").onclick = function(){ el("hrbox").innerHTML = ""; };
  el("hrGo").onclick = async function(){
    el("hrGo").disabled = true;
    var out = await api("/people/request", { method:"POST", body:{
      chairId: chairId || el("hrChair").value,
      fullName: el("hrName").value,
      workEmail: el("hrMail").value,
      employeeType: el("hrType").value } });
    el("hrGo").disabled = false;
    if (out.error) { el("hrboxmsg").innerHTML = msg("bad", out.reason || out.error); return; }
    el("hrbox").innerHTML = "";
    el("hrmsg").innerHTML = msg("ok", "Raised. It is with HR" +
      (out.due_at ? ", due " + when(out.due_at) : "") + ".");
    vHiring();
  };
}
