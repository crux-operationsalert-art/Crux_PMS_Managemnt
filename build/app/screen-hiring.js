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
      esc(withKids.length) + ' of those have other chairs reporting into them — ' +
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
              '<td>' + esc(v.reports_to || "— top of the tree") + '</td>' +
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
          return '<option value="'+esc(v.id)+'">' + esc(v.title) + ' — ' + esc(v.code) +
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
