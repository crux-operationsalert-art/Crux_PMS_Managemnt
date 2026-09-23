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
      row("Employment", [p.employee_type, p.employment_status].filter(Boolean).join(" · "), null) +
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
            ? 'You are an administrator, so the tool shows you everything anyway — but a '
              + 'chair is what the appraisal and escalation ladders hang off, so it is worth having one.'
            : 'A chair is what the tool resolves your view from. Ask HR to seat you.') +
          '</div>') +
    '</div>' +

    '<div class="card"><h2>What you cover</h2>' +
      (Number(cov.branches || 0)
        ? '<p>' + esc(cov.branches) + ' branches, ' + esc(cov.clients) + ' clients, ' +
          esc(cov.locations) + ' locations. Coverage is what decides which branches, ' +
          'cases and scores you see — not your job title.</p>'
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
          : "Recorded against your file. No HR address is set, so nobody has been e-mailed — tell them yourself.");
        vProfile();
      };
    };
  });
}
