/* ---------------------------------------------------------------------- HR
   Employee information, satisfaction and performance. No payroll: that stays
   where it is. Every block says how it is worked out, because a number whose
   derivation is not stated is a number nobody will act on.                */
async function vHR(){
  var d = await api("/access/hr/overview");
  if (d.error) { el("view").innerHTML = "<h1>HR</h1>" + msg("bad", d.reason||d.error); return; }
  var h = d.head||{};
  function block(title, note, items, how){
    return '<div class="card"><h2>' + esc(title) + '</h2>' +
      (note ? '<p class="mute">' + esc(note) + '</p>' : '') +
      (items.length
        ? '<div class="scroll"><table><tr><th>What</th><th>How many</th></tr>' +
          items.map(function(i){
            return '<tr><td>'+esc(i.k)+'</td><td>'+esc(i.v)+'</td></tr>'; }).join("") +
          '</table></div>'
        : '<div class="empty">Nothing recorded.</div>') +
      (how ? '<p class="mute"><b>How this is worked out:</b> ' + esc(how) + '</p>' : '') +
      '</div>';
  }
  el("view").innerHTML =
    '<div class="page-head"><div><h1>HR</h1>' +
    '<p class="mute">Employee information, satisfaction and performance. ' +
    esc(d.payrollNote) + '</p></div></div>' +
    (d.isHr ? '' : msg("warn", "You can read this. HR and the administrator change it.")) +

    block("Headcount", null, [
      { k: "Active people", v: h.people },
      { k: "Employees", v: h.employees },
      { k: "Partners", v: h.partners },
      { k: "With no manager recorded", v: h.no_manager },
      { k: "Chairs with nobody in them", v: d.vacantChairs },
    ], "Counted from the person master, active rows only. A person with no manager " +
       "recorded resolves no reporting line, so their manager sees nothing of theirs.") +

    block("By department", null, (d.depts||[]).map(function(x){
      return { k: x.department, v: x.n }; }),
      "The department on the person record. It is what decides whether somebody " +
      "sees client data at all.") +

    block("By kind", null, (d.types||[]).map(function(x){
      return { k: x.kind, v: x.n }; }),
      "Employees are recovered through payroll; partners are billed by Finance. " +
      "The penalty engine routes on exactly this.") +

    block("Notes on people", "449 of these were carried across at cut-over.",
      (d.notes||[]).map(function(x){ return { k: x.note_class, v: x.n }; }),
      "A note has to be classified before it can move an Attribute score. " +
      "Unclassified notes are readable but count for nothing.") +

    '<div class="card"><h2>Satisfaction</h2>' +
    '<div class="empty">' + esc(d.satisfactionWhy) + '</div></div>';
}

/* ------------------------------------------------------------------ joining
   A joiner is a request HR has approved and the administrator has not seated,
   plus anybody seated who has never signed in.                            */
async function vJoining(){
  var d = await api("/access/joining");
  if (d.error) { el("view").innerHTML = "<h1>Joining</h1>" + msg("bad", d.reason||d.error); return; }
  var infl = d.inflight||[], un = d.unactivated||[];
  el("view").innerHTML =
    '<div class="page-head"><div><h1>Joining</h1>' +
    '<p class="mute">' + esc(infl.length) + ' in flight, ' + esc(un.length) +
      ' seated but never signed in. The steps are: ' +
      esc((d.steps||[]).join(' → ')) + '.</p></div></div>' +

    '<div class="card"><h2>In progress</h2>' +
      (infl.length
        ? '<div class="scroll"><table><tr><th>Who</th><th>Chair</th><th>Waiting on</th>' +
          '<th>Since</th><th>Due</th></tr>' +
          infl.map(function(j){
            return '<tr><td>'+esc(j.full_name)+'<div class="mute">'+esc(j.work_email||'')+'</div></td>' +
              '<td>'+esc(j.chair||'-')+'</td>' +
              '<td>'+esc(j.state === 'AWAITING_HR' ? 'HR' : 'the administrator')+'</td>' +
              '<td>'+esc(j.requested_at ? when(j.requested_at) : '')+'</td>' +
              '<td>'+esc(j.due_at ? when(j.due_at) : '')+'</td></tr>';
          }).join("") + '</table></div>'
        : '<div class="empty">' + esc(d.emptyWhy || "Nobody is part-way through joining.") +
          '</div>') +
    '</div>' +

    '<div class="card"><h2>Seated, never signed in</h2>' +
    '<p class="mute">An activation code was sent and never used. The code lasts ' +
    'fifteen minutes, so a stale one is the usual reason — seating them again ' +
    'issues a fresh one.</p>' +
      (un.length
        ? '<div class="scroll"><table><tr><th>Who</th><th>Chair</th><th>Code sent</th></tr>' +
          un.map(function(u){
            return '<tr><td>'+esc(u.full_name)+'<div class="mute">'+esc(u.work_email||'')+'</div></td>' +
              '<td>'+esc(u.chair||'-')+'</td>' +
              '<td>'+esc(u.code_sent ? when(u.code_sent) : '')+'</td></tr>';
          }).join("") + '</table></div>'
        : '<div class="empty">Everybody who was sent a code has used it.</div>') +
    '</div>';
}

/* ----------------------------------------------------------- report access
   What a person sees is mostly INHERITED -- it follows the chair and the
   coverage. Only the explicit grants are revocable here, and the screen says
   so, because revoking a grant does nothing if the chair already carries the
   same visibility.                                                        */
var accPerson = null;
async function vAccess(){
  var d = await api("/access");
  if (d.error) { el("view").innerHTML = "<h1>Report access</h1>" + msg("bad", d.reason||d.error); return; }
  var people = d.people||[];
  el("view").innerHTML =
    '<div class="page-head"><div><h1>Report access</h1>' +
    '<p class="mute">' + esc(people.length) + ' people. What somebody sees follows ' +
    'their chair and their coverage; a grant here is the exception, not the rule.' +
    (d.mayGrant ? '' : ' You can read this. The administrator changes it.') +
    '</p></div></div><div id="acmsg"></div>' +
    '<div class="card"><h2>Person</h2><div class="scroll"><table>' +
    '<tr><th>Name</th><th>Chair</th><th>Coverage</th><th>Explicit grants</th><th></th></tr>' +
    people.map(function(p){
      return '<tr><td>'+esc(p.full_name)+'<div class="mute">'+esc(p.employee_no||'')+
          (p.department?' · '+esc(p.department):'')+'</div></td>' +
        '<td>'+esc(p.chair||'-')+'</td>' +
        '<td>'+(Number(p.coverage_rules)?esc(p.coverage_rules)+' rules':'<span class="mute">none</span>')+'</td>' +
        '<td>'+(Number(p.grants)?'<span class="chip ok">'+esc(p.grants)+'</span>':'<span class="mute">none</span>')+'</td>' +
        '<td><button class="btn" data-acp="'+esc(p.id)+'">Open</button></td></tr>';
    }).join("") + '</table></div></div><div id="acbox"></div>';

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-acp]"), function(b){
    b.onclick = function(){ accOpen(b.getAttribute("data-acp")); };
  });
  if (accPerson) accOpen(accPerson);
}

async function accOpen(id){
  accPerson = id;
  var d = await api("/access/person/" + encodeURIComponent(id));
  if (d.error) { el("acbox").innerHTML = msg("bad", d.reason||d.error); return; }
  var p = d.person||{};
  el("acbox").innerHTML =
    '<div class="card"><h2>' + esc(p.full_name) + '</h2>' +
    '<p class="mute">' + esc(p.chair || 'holds no chair') +
      (p.manager ? ' · reports to ' + esc(p.manager) : '') + '</p>' +
    '<h3>Inherited</h3>' +
    '<p class="mute">Follows the chair and the reporting line. Not revocable here.</p>' +
    ((d.inherited||[]).length
      ? '<div class="scroll"><table><tr><th>Via</th><th>What</th><th>Branches</th></tr>' +
        d.inherited.map(function(i){
          return '<tr><td>'+esc(i.via)+'</td><td>'+esc(i.what)+'</td><td>'+esc(i.branches)+'</td></tr>';
        }).join("") + '</table></div>'
      : '<div class="empty">Their chair and coverage carry nothing, so they see no ' +
        'client data at all.</div>') +
    '<h3>Explicit</h3>' +
    ((d.explicit||[]).length
      ? '<div class="scroll"><table><tr><th>Reason</th><th>Granted by</th><th>On</th>' +
        '<th>Expires</th><th></th></tr>' +
        d.explicit.map(function(g){
          return '<tr><td>'+esc(g.reason)+'</td><td>'+esc(g.by||'')+'</td>' +
            '<td>'+esc(when(g.granted_at))+'</td>' +
            '<td>'+esc(g.expires_at ? when(g.expires_at) : 'no end date')+'</td>' +
            '<td>'+(d.mayGrant?'<button class="btn" data-acr="'+esc(g.id)+'">Revoke</button>':'')+'</td></tr>';
        }).join("") + '</table></div>'
      : '<div class="empty">No explicit grants. This person sees only what the chair ' +
        'and reporting line carry.</div>') +
    '<p class="mute">' + esc(d.note) + '</p>' +
    (d.mayGrant ? '<button class="btn primary" id="acAdd">Add access</button>' : '') +
    '<div id="acgrant"></div></div>';

  Array.prototype.forEach.call(el("acbox").querySelectorAll("[data-acr]"), function(b){
    b.onclick = async function(){
      if (!confirm("Revoke this grant? Anything their chair carries is unaffected.")) return;
      b.disabled = true;
      var out = await api("/access/revoke", { method:"POST", body:{ grantId: b.getAttribute("data-acr") } });
      b.disabled = false;
      if (out.error) { el("acmsg").innerHTML = msg("bad", out.reason||out.error); return; }
      el("acmsg").innerHTML = msg("ok", "Revoked.");
      vAccess();
    };
  });
  if (el("acAdd")) el("acAdd").onclick = function(){
    el("acgrant").innerHTML =
      '<div class="card"><h3>Grant additional access to ' + esc(p.full_name) + '</h3>' +
      '<label>Why<br><input id="agWhy" placeholder="required"></label> ' +
      '<label>Until<br><input id="agUntil" type="date"></label> ' +
      '<button class="btn primary" id="agGo">Save grant</button> ' +
      '<button class="btn" id="agCancel">Cancel</button>' +
      '<p class="mute">A grant with no end date stays until somebody revokes it. ' +
      'Put a date on it if it is for one piece of work.</p><div id="agmsg"></div></div>';
    el("agCancel").onclick = function(){ el("acgrant").innerHTML = ""; };
    el("agGo").onclick = async function(){
      el("agGo").disabled = true;
      var out = await api("/access/grant", { method:"POST", body:{
        personId: id, reason: el("agWhy").value,
        expiresAt: el("agUntil").value || null } });
      el("agGo").disabled = false;
      if (out.error) { el("agmsg").innerHTML = msg("bad", out.reason||out.error); return; }
      el("acgrant").innerHTML = "";
      el("acmsg").innerHTML = msg("ok", "Granted.");
      accOpen(id);
    };
  };
}
