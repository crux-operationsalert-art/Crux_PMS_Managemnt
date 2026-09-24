-- The nine screens themselves, appended before boot(). They call the `ops`
-- Edge Function, so migration 137 must run first -- it adds that helper.
--
-- Five of them create their own first row and are useful before any upload
-- lands: log a visit, raise a claim and walk it through Operations, HR and
-- Accounts, share an idea, add a rate, grant and revoke report access. The
-- four that only read -- MIS, the 10-day view, Reports and the HR overview --
-- carry the design's own instruction with them: nothing is hard-coded, so each
-- says which table answered and how many rows it had.
do $$
declare v_body text; v_new text; v_js text;
begin
  select html into v_body from app_page where slug = 'app';
  if v_body is null then raise exception 'no app page'; end if;
  if position(E'\nboot();\n</script>' in v_body) = 0 then
    raise exception 'the tail anchor is not there';
  end if;
  if position('async function vVisits(){' in v_body) > 0 then
    raise exception 'the screens are already there';
  end if;
  if position('var ops  = function' in v_body) = 0 then
    raise exception 'migration 137 has not run -- the ops helper is not there';
  end if;

  v_js := $js$
/* --------------------------------------------------------- visits & claims
   The design: log a visit, raise a claim, and a claim table that shows the
   stage each one is at and who it is with. A visit writes back into the
   branch record -- it updates the contact it met.                        */
async function vVisits(){
  var d = await ops("/field");
  if (d.error) { el("view").innerHTML = "<h1>Visits &amp; claims</h1>" + msg("bad", d.reason||d.error); return; }
  var visits = d.visits||[], claims = d.claims||[], flow = d.flow||[];
  function stagePill(s){
    if (s === 'PAID') return '<span class="pill ok">paid</span>';
    if (s === 'REJECTED' || s === 'DISPUTED') return '<span class="pill bad">'+esc(s.toLowerCase())+'</span>';
    return '<span class="pill warn">'+esc(String(s).toLowerCase().replace(/_/g,' '))+'</span>';
  }
  el("view").innerHTML =
    '<div class="page-head"><div><h1>Visits &amp; claims</h1>' +
    '<p class="mute">' + esc(visits.length) + ' visits and ' + esc(claims.length) +
      ' claims' + (d.mine ? ' of your own' : ' across everyone') + '. A claim walks ' +
      esc(flow.join(' &rarr; ').toLowerCase().replace(/_/g,' ')) +
      ', and the database refuses to mark one paid without a payment reference.</p></div>' +
    '<div><button class="btn primary" id="vsLog">Log a visit</button> ' +
    '<button class="btn" id="vsClaim">Raise a claim</button></div></div>' +
    '<div id="vsmsg"></div><div id="vsbox"></div>' +

    '<div class="card"><h2>Expense claims</h2>' +
      (claims.length
        ? '<div class="scroll"><table><tr><th>Ref</th><th>Visit</th><th>Who</th>' +
          '<th>Amount</th><th>Stage</th><th></th></tr>' +
          claims.map(function(c){
            var act = d.canAct[c.stage]
              ? '<button class="btn" data-clmv="'+esc(c.id)+'" data-clmst="'+esc(c.stage)+'">Action</button>'
              : '';
            return '<tr><td>'+esc(c.ref)+'</td>' +
              '<td>'+esc(c.branch||'-')+(c.visited_on?' <span class="mute">'+esc(day(c.visited_on))+'</span>':'')+'</td>' +
              '<td>'+esc(c.who)+'</td><td>'+esc(money(c.amount))+'</td>' +
              '<td>'+stagePill(c.stage)+(c.paid_ref?' <span class="mute">'+esc(c.paid_ref)+'</span>':'')+'</td>' +
              '<td>'+act+'</td></tr>';
          }).join("") + '</table></div>'
        : '<div class="empty">No claim has been raised. Log a visit first, then raise ' +
          'the claim against it -- a claim tied to a visit is one Operations can check.</div>') +
    '</div>' +

    '<div class="card"><h2>Visits</h2>' +
      (visits.length
        ? '<div class="scroll"><table><tr><th>When</th><th>Branch</th><th>Client</th>' +
          '<th>Why</th><th>Who</th></tr>' +
          visits.map(function(v){
            return '<tr><td>'+esc(day(v.visited_on))+'</td><td>'+esc(v.branch||'-')+'</td>' +
              '<td>'+esc(v.client||'-')+'</td><td>'+esc(v.purpose||'')+'</td>' +
              '<td>'+esc(v.who)+'</td></tr>';
          }).join("") + '</table></div>'
        : '<div class="empty">No visit has been recorded. Logging one moves the ' +
          'last-seen date on that branch and, if you met somebody new, replaces the ' +
          'point of contact on its record.</div>') +
    '</div>';

  if (el("vsLog")) el("vsLog").onclick = function(){ vsVisitForm(d); };
  if (el("vsClaim")) el("vsClaim").onclick = function(){ vsClaimForm(d); };
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-clmv]"), function(b){
    b.onclick = function(){ vsAdvance(b.getAttribute("data-clmv"), b.getAttribute("data-clmst")); };
  });
}

function vsVisitForm(d){
  el("vsbox").innerHTML =
    '<div class="card"><h2>Log a visit</h2>' +
    '<label>Branch<br><select id="vsBranch">' +
      (d.branches||[]).map(function(b){
        return '<option value="'+esc(b.id)+'">'+esc(b.client)+' -- '+esc(b.name)+' ('+esc(b.code)+')</option>';
      }).join("") + '</select></label> ' +
    '<label>When<br><input id="vsWhen" type="date"></label> ' +
    '<label>Why you went<br><input id="vsWhy" placeholder="collection follow-up, audit, training"></label><br>' +
    '<label>Who you met<br><input id="vsMet" placeholder="optional"></label> ' +
    '<label>Their mobile<br><input id="vsMetM"></label> ' +
    '<label>Their e-mail<br><input id="vsMetE"></label><br>' +
    '<label>Note<br><input id="vsNote"></label> ' +
    '<button class="btn primary" id="vsGo">Save the visit</button> ' +
    '<button class="btn" id="vsCancel">Cancel</button>' +
    '<p class="mute">Naming somebody you met replaces the Crux point of contact on ' +
    'that branch. The old one is retired, not overwritten.</p><div id="vsboxmsg"></div></div>';
  el("vsCancel").onclick = function(){ el("vsbox").innerHTML = ""; };
  el("vsGo").onclick = async function(){
    el("vsGo").disabled = true;
    var out = await ops("/field/visit", { method:"POST", body:{
      branchId: el("vsBranch").value, visitedOn: el("vsWhen").value || null,
      purpose: el("vsWhy").value, met: el("vsMet").value,
      metMobile: el("vsMetM").value, metEmail: el("vsMetE").value,
      note: el("vsNote").value } });
    el("vsGo").disabled = false;
    if (out.error) { el("vsboxmsg").innerHTML = msg("bad", out.reason||out.error); return; }
    el("vsbox").innerHTML = "";
    el("vsmsg").innerHTML = msg("ok", "Visit logged.");
    vVisits();
  };
}

function vsClaimForm(d){
  var vs = d.visits||[];
  el("vsbox").innerHTML =
    '<div class="card"><h2>Raise a claim</h2>' +
    (vs.length
      ? '<label>Against which visit<br><select id="vcVisit">' +
        vs.map(function(v){
          return '<option value="'+esc(v.id)+'">'+esc(day(v.visited_on))+' -- '+
            esc(v.branch||'no branch')+' -- '+esc(v.purpose||'')+'</option>';
        }).join("") + '</select></label> '
      : '<p class="mute">You have no visits logged, so this claim will not be tied to ' +
        'one. Operations can still see it, but a claim against a visit is easier to ' +
        'check.</p>') +
    '<label>Amount<br><input id="vcAmt" type="number" min="0" step="1"></label> ' +
    '<button class="btn primary" id="vcGo">Send it to Operations</button> ' +
    '<button class="btn" id="vcCancel">Cancel</button><div id="vsboxmsg"></div></div>';
  el("vcCancel").onclick = function(){ el("vsbox").innerHTML = ""; };
  el("vcGo").onclick = async function(){
    el("vcGo").disabled = true;
    var out = await ops("/field/claim", { method:"POST", body:{
      visitId: el("vcVisit") ? el("vcVisit").value : null,
      amount: Number(el("vcAmt").value) } });
    el("vcGo").disabled = false;
    if (out.error) { el("vsboxmsg").innerHTML = msg("bad", out.reason||out.error); return; }
    el("vsbox").innerHTML = "";
    el("vsmsg").innerHTML = msg("ok", out.ref + " raised. It is with Operations.");
    vVisits();
  };
}

function vsAdvance(id, stage){
  var nextLabel = stage === 'ACCOUNTS' ? 'Mark it paid' : 'Approve and pass it on';
  el("vsbox").innerHTML =
    '<div class="card"><h2>' + esc(nextLabel) + '</h2>' +
    (stage === 'ACCOUNTS'
      ? '<label>Payment reference<br><input id="vaRef" placeholder="required"></label> '
      : '') +
    '<button class="btn primary" id="vaGo">' + esc(nextLabel) + '</button> ' +
    '<button class="btn" id="vaDisp">Dispute it</button> ' +
    '<button class="btn" id="vaCancel">Cancel</button>' +
    '<label id="vaWhyWrap" style="display:none"><br>Reason<br><input id="vaWhy"></label>' +
    '<div id="vsboxmsg"></div></div>';
  el("vaCancel").onclick = function(){ el("vsbox").innerHTML = ""; };
  async function send(to){
    el("vaGo").disabled = true;
    var out = await ops("/field/claim/" + encodeURIComponent(id) + "/advance",
      { method:"POST", body:{ to: to,
        paidRef: el("vaRef") ? el("vaRef").value : null,
        disputeReason: el("vaWhy") ? el("vaWhy").value : null } });
    el("vaGo").disabled = false;
    if (out.error) { el("vsboxmsg").innerHTML = msg("bad", out.reason||out.error); return; }
    el("vsbox").innerHTML = "";
    el("vsmsg").innerHTML = msg("ok", out.ref + " is now " +
      String(out.stage).toLowerCase().replace(/_/g,' ') + ".");
    vVisits();
  }
  el("vaGo").onclick = function(){ send(stage === 'ACCOUNTS' ? 'PAID' : null); };
  /* First press reveals the reason box, because a dispute without one is
     refused by the database anyway; the second press sends it.            */
  el("vaDisp").onclick = function(){
    if (el("vaWhyWrap").style.display === "none") {
      el("vaWhyWrap").style.display = "";
      el("vaDisp").textContent = "Send the dispute";
      return;
    }
    if (!el("vaWhy").value.trim()) {
      el("vsboxmsg").innerHTML = msg("warn", "A dispute carries the reason the person argues against.");
      return;
    }
    send('DISPUTED');
  };
}

/* ---------------------------------------------------------------- ideathon
   Driven by Business Excellence. An idea that is held or rejected carries the
   reason, so the person who raised it is told why rather than left guessing. */
async function vIdeas(){
  var d = await ops("/field/ideas");
  if (d.error) { el("view").innerHTML = "<h1>Ideathon</h1>" + msg("bad", d.reason||d.error); return; }
  var ideas = d.ideas||[];
  var mayDecide = !!me && (me.app_role === "ADMIN" ||
    String(me.department||"").indexOf("Business Excellence") >= 0);
  el("view").innerHTML =
    '<div class="page-head"><div><h1>Ideathon</h1>' +
    '<p class="mute">Driven by Business Excellence. ' + esc(ideas.length) +
      ' ideas. Anyone can share one; Business Excellence decides, and an idea put ' +
      'on hold or turned down carries the reason.</p></div>' +
    '<div><button class="btn primary" id="idAdd">Share an idea</button></div></div>' +
    '<div id="idmsg"></div><div id="idbox"></div>' +
    '<div class="card"><h2>Ideas</h2>' +
      (ideas.length
        ? ideas.map(function(i){
            return '<div class="cfgrow"><div>' +
              '<b>' + esc(i.title) + '</b> <span class="chip">' + esc(i.stage.toLowerCase().replace(/_/g,' ')) + '</span>' +
              '<div class="mute">' + esc(i.ref) + ' &middot; ' + esc(i.raised_by) +
                (i.owner_dept ? ' &middot; ' + esc(i.owner_dept) : '') +
                ' &middot; ' + esc(when(i.created_at)) + '</div>' +
              (i.body ? '<div class="mute">' + esc(i.body) + '</div>' : '') +
              (i.decision_reason ? '<div class="mute"><b>Decision:</b> ' + esc(i.decision_reason) + '</div>' : '') +
              (i.charter ? '<div class="mute"><b>Charter:</b> ' + esc(i.charter) + '</div>' : '') +
              '</div>' +
              (mayDecide ? '<div class="cfgset"><button class="btn" data-idd="'+esc(i.id)+'" ' +
                'data-idst="'+esc(i.stage)+'">Decide</button></div>' : '') +
              '</div>';
          }).join("")
        : '<div class="empty">Nobody has shared an idea yet. The first one starts the ' +
          'list -- it goes to Business Excellence, who take it to review.</div>') +
    '</div>';

  el("idAdd").onclick = function(){
    el("idbox").innerHTML =
      '<div class="card"><h2>Share an idea</h2>' +
      '<label>In one line<br><input id="idTitle"></label> ' +
      '<label>Which department it belongs to<br><input id="idDept" placeholder="optional"></label><br>' +
      '<label>The idea<br><input id="idBody"></label> ' +
      '<button class="btn primary" id="idGo">Share it</button> ' +
      '<button class="btn" id="idCancel">Cancel</button><div id="idboxmsg"></div></div>';
    el("idCancel").onclick = function(){ el("idbox").innerHTML = ""; };
    el("idGo").onclick = async function(){
      el("idGo").disabled = true;
      var out = await ops("/field/idea", { method:"POST", body:{
        title: el("idTitle").value, body: el("idBody").value,
        ownerDept: el("idDept").value } });
      el("idGo").disabled = false;
      if (out.error) { el("idboxmsg").innerHTML = msg("bad", out.reason||out.error); return; }
      el("idbox").innerHTML = "";
      el("idmsg").innerHTML = msg("ok", out.ref + " shared.");
      vIdeas();
    };
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-idd]"), function(b){
    b.onclick = function(){
      var id = b.getAttribute("data-idd");
      el("idbox").innerHTML =
        '<div class="card"><h2>Decide on this idea</h2>' +
        '<label>Stage<br><select id="idStage">' +
          (d.stages||[]).map(function(s){
            return '<option value="'+esc(s)+'"'+(s===b.getAttribute("data-idst")?' selected':'')+'>' +
              esc(s.toLowerCase().replace(/_/g,' ')) + '</option>';
          }).join("") + '</select></label> ' +
        '<label>Reason<br><input id="idWhy" placeholder="required to hold or reject"></label> ' +
        '<label>Charter<br><input id="idChart" placeholder="optional"></label> ' +
        '<button class="btn primary" id="idDGo">Save</button> ' +
        '<button class="btn" id="idDCancel">Cancel</button><div id="idboxmsg"></div></div>';
      el("idDCancel").onclick = function(){ el("idbox").innerHTML = ""; };
      el("idDGo").onclick = async function(){
        el("idDGo").disabled = true;
        var out = await ops("/field/idea/" + encodeURIComponent(id) + "/decide",
          { method:"POST", body:{ stage: el("idStage").value,
            reason: el("idWhy").value, charter: el("idChart").value } });
        el("idDGo").disabled = false;
        if (out.error) { el("idboxmsg").innerHTML = msg("bad", out.reason||out.error); return; }
        el("idbox").innerHTML = "";
        el("idmsg").innerHTML = msg("ok", out.ref + " is now " +
          String(out.stage).toLowerCase().replace(/_/g,' ') + ".");
        vIdeas();
      };
    };
  });
}
/* ---------------------------------------------------------------------- HR
   Employee information, satisfaction and performance. No payroll: that stays
   where it is. Every block says how it is worked out, because a number whose
   derivation is not stated is a number nobody will act on.                */
async function vHR(){
  var d = await ops("/access/hr/overview");
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
  var d = await ops("/access/joining");
  if (d.error) { el("view").innerHTML = "<h1>Joining</h1>" + msg("bad", d.reason||d.error); return; }
  var infl = d.inflight||[], un = d.unactivated||[];
  el("view").innerHTML =
    '<div class="page-head"><div><h1>Joining</h1>' +
    '<p class="mute">' + esc(infl.length) + ' in flight, ' + esc(un.length) +
      ' seated but never signed in. The steps are: ' +
      esc((d.steps||[]).join(' &rarr; ')) + '.</p></div></div>' +

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
    'fifteen minutes, so a stale one is the usual reason -- seating them again ' +
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
  var d = await ops("/access");
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
          (p.department?' &middot; '+esc(p.department):'')+'</div></td>' +
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
  var d = await ops("/access/person/" + encodeURIComponent(id));
  if (d.error) { el("acbox").innerHTML = msg("bad", d.reason||d.error); return; }
  var p = d.person||{};
  el("acbox").innerHTML =
    '<div class="card"><h2>' + esc(p.full_name) + '</h2>' +
    '<p class="mute">' + esc(p.chair || 'holds no chair') +
      (p.manager ? ' &middot; reports to ' + esc(p.manager) : '') + '</p>' +
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
      var out = await ops("/access/revoke", { method:"POST", body:{ grantId: b.getAttribute("data-acr") } });
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
      var out = await ops("/access/grant", { method:"POST", body:{
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
/* ---------------------------------------------------------------------- MIS
   The design's own rule for this screen, in its words: "Nothing on this screen
   is hard-coded, so it waits for the data layer to answer rather than showing
   numbers from nowhere." Every figure is read from business_record, and the
   provenance strip at the foot says which table answered and how many rows it
   had, so a zero can never be mistaken for a result.                      */
var misGroup = "client", misPeriod = null;
async function vMis(){
  var q = "/mis?group=" + encodeURIComponent(misGroup) +
          (misPeriod ? "&period=" + encodeURIComponent(misPeriod) : "");
  var d = await api(q);
  if (d.error) { el("view").innerHTML = "<h1>MIS</h1>" + msg("bad", d.reason||d.error); return; }
  misPeriod = d.period;
  var rows = d.rows||[], t = d.tiles||{};
  function pct(a, b){ return Number(b) ? Math.round(Number(a)/Number(b)*100) + "%" : "-"; }
  function tile(k, v, s){
    return '<div class="cfgrow"><div><b>' + esc(k) + '</b>' +
      (s ? '<div class="mute">' + esc(s) + '</div>' : '') + '</div>' +
      '<div class="cfgset">' + esc(v) + '</div></div>';
  }
  el("view").innerHTML =
    '<div class="page-head"><div><h1>MIS</h1>' +
    '<p class="mute">' + (d.period
        ? esc(d.period) + ' &middot; grouped by ' + esc(d.dims[d.group].label.toLowerCase()) +
          ' &middot; ' + esc(rows.length) + ' rows'
        : 'No month to report on yet') + '</p></div>' +
    '<div>' + Object.keys(d.dims||{}).map(function(k){
        return '<button class="btn' + (k===d.group?' primary':'') + '" data-misg="'+esc(k)+'">' +
          esc(d.dims[k].label) + '</button> ';
      }).join("") + '</div></div>' +

    ((d.periods||[]).length
      ? '<div class="card"><h2>Month</h2>' +
        d.periods.map(function(p){
          return '<button class="btn' + (p.period===d.period?' primary':'') +
            '" data-misp="'+esc(p.period)+'">' + esc(p.period) + '</button> ';
        }).join("") + '</div>'
      : '') +

    (d.emptyWhy
      ? '<div class="card"><h2>No data</h2><div class="empty">' + esc(d.emptyWhy) + '</div></div>'
      : '<div class="card"><h2>The month</h2>' +
          tile("Month to date", money(t.mtd), "What is on the board now") +
          tile("Target", money(t.target), "From the KPI targets upload") +
          tile("Achievement", pct(t.mtd, t.target), "Month to date against target") +
          tile("As at the 10th", money(t.day10), "What the forecast is read from") +
          tile("Revenue", money(t.revenue), "Priced at the rate valid in this month") +
          tile("Records behind it", t.records, "Rows in business_record for this month") +
        '</div>' +
        (d.noTarget ? msg("warn", d.noTarget) : "") +
        '<div class="card"><h2>' + esc(d.dims[d.group].label) + '</h2>' +
        '<div class="scroll"><table><tr><th>' + esc(d.dims[d.group].label) + '</th>' +
        '<th>10th</th><th>MTD</th><th>Target</th><th>Achievement</th><th>Revenue</th></tr>' +
        rows.map(function(r){
          return '<tr><td>'+esc(r.label)+'</td><td>'+esc(money(r.day10))+'</td>' +
            '<td>'+esc(money(r.mtd))+'</td><td>'+esc(money(r.target))+'</td>' +
            '<td>'+esc(pct(r.mtd, r.target))+'</td><td>'+esc(money(r.revenue))+'</td></tr>';
        }).join("") + '</table></div></div>') +

    '<div class="card"><h2>Where these figures came from</h2>' +
    '<p class="mute">Nothing on this screen is hard-coded. It waits for the data ' +
    'layer to answer rather than showing numbers from nowhere, so here is what ' +
    'answered.</p><div class="scroll"><table><tr><th>Table</th><th>Rows</th></tr>' +
    (d.provenance||[]).map(function(x){
      return '<tr><td>'+esc(x.table)+'</td><td>' +
        (Number(x.n) ? esc(x.n) : '<span class="pill warn">empty</span>') + '</td></tr>';
    }).join("") + '</table></div></div>';

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-misg]"), function(b){
    b.onclick = function(){ misGroup = b.getAttribute("data-misg"); vMis(); };
  });
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-misp]"), function(b){
    b.onclick = function(){ misPeriod = b.getAttribute("data-misp"); vMis(); };
  });
}

/* ------------------------------------------------- 10-day management view
   Where the month could finish, read from what was on the board by the 10th.
   Same records, same rates and same scope as the MIS.                     */
var tenPeriod = null;
async function vTenday(){
  var d = await ops("/mis/tenday" + (tenPeriod ? "?period=" + encodeURIComponent(tenPeriod) : ""));
  if (d.error) { el("view").innerHTML = "<h1>10-day view</h1>" + msg("bad", d.reason||d.error); return; }
  tenPeriod = d.period;
  var rows = d.rows||[], sc = d.scenarios||[];
  el("view").innerHTML =
    '<div class="page-head"><div><h1>10-day management view</h1>' +
    '<p class="mute">Where the month could finish, read from what was on the board ' +
    'by the 10th. Same records, same rates and same scope as the MIS.</p></div></div>' +

    ((d.periods||[]).length
      ? '<div class="card"><h2>Month</h2>' + d.periods.map(function(p){
          return '<button class="btn'+(p.period===d.period?' primary':'')+
            '" data-tenp="'+esc(p.period)+'">'+esc(p.period)+'</button> ';
        }).join("") + '</div>'
      : '') +

    '<div class="card"><h2>Scenarios</h2>' +
      (sc.length
        ? '<div class="scroll"><table><tr><th>Scenario</th><th>Multiplier</th>' +
          '<th>Stance</th><th>Where it comes from</th></tr>' +
          sc.map(function(s){
            return '<tr><td>'+esc(s.label)+'</td><td>'+esc(s.multiplier)+'</td>' +
              '<td>'+esc(s.stance||'')+'</td><td class="mute">'+esc(s.source||'')+'</td></tr>';
          }).join("") + '</table></div>'
        : '<div class="empty">' + esc(d.noScenarios) + '</div>') +
    '</div>' +

    '<div class="card"><h2>By location</h2>' +
      (d.emptyWhy
        ? '<div class="empty">' + esc(d.emptyWhy) + '</div>'
        : '<div class="scroll"><table><tr><th>Location</th><th>10th day</th>' +
          '<th>Current MTD</th><th>Added since</th><th>x3.25</th><th>x3.5</th>' +
          '<th>x4</th><th>x5</th></tr>' +
          rows.map(function(r){
            return '<tr><td>'+esc(r.location)+'</td>' +
              '<td>'+esc(money(r.day10_revenue))+'</td>' +
              '<td>'+esc(money(r.actual_revenue))+'</td>' +
              '<td>'+esc(money(r.live_addition))+'</td>' +
              '<td>'+esc(money(r.sheet_x325))+'</td><td>'+esc(money(r.sheet_x35))+'</td>' +
              '<td>'+esc(money(r.sheet_x4))+'</td><td>'+esc(money(r.sheet_x5))+'</td></tr>';
          }).join("") + '</table></div>') +
    '</div>';

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tenp]"), function(b){
    b.onclick = function(){ tenPeriod = b.getAttribute("data-tenp"); vTenday(); };
  });
}

/* --------------------------------------------------------------- reports */
async function vReports(){
  var d = await ops("/mis/reports");
  if (d.error) { el("view").innerHTML = "<h1>Reports</h1>" + msg("bad", d.reason||d.error); return; }
  el("view").innerHTML =
    '<div class="page-head"><div><h1>Reports</h1>' +
    '<p class="mute">' + esc(d.note) + '</p></div></div>' +
    '<div class="card">' + (d.reports||[]).map(function(r){
      return '<div class="cfgrow"><div><b>' + esc(r.name) + '</b>' +
        (Number(r.rows) ? ' <span class="chip ok">' + esc(r.rows) + ' rows</span>'
                        : ' <span class="pill warn">nothing to print yet</span>') +
        '<div class="mute">' + esc(r.what) + '</div>' +
        '<div class="mute">Scope &middot; ' + esc(r.scope) + '</div></div></div>';
    }).join("") + '</div>';
}

/* ------------------------------------------------------------ rate master
   "A report for a past month uses the rate valid during that month, not the
   one showing at the top of this list. Changing a rate adds a version; it
   never rewrites a closed month."                                         */
async function vRates(){
  var d = await ops("/rates");
  if (d.error) { el("view").innerHTML = "<h1>Rate master</h1>" + msg("bad", d.reason||d.error); return; }
  var rates = d.rates||[];
  el("view").innerHTML =
    '<div class="page-head"><div><h1>Rate master</h1>' +
    '<p class="mute">' + esc(rates.length) + ' rates. Changing one adds a version ' +
    'and end-dates the old; a report for a past month reads the rate that was ' +
    'valid then, not the one at the top of this list.</p></div>' +
    (d.mayEdit ? '<div><button class="btn primary" id="rtAdd">Add a rate</button></div>' : '') +
    '</div><div id="rtmsg"></div><div id="rtbox"></div>' +
    '<div class="card"><h2>In force</h2>' +
      (rates.length
        ? '<div class="scroll"><table><tr><th>Rate</th><th>Value</th><th>Client</th>' +
          '<th>Applies to</th><th>W.E.F.</th><th>Until</th><th>Versions</th><th></th></tr>' +
          rates.map(function(r){
            return '<tr><td>'+esc(r.family)+'</td><td>'+esc(money(r.value))+'</td>' +
              '<td>'+esc(r.client||'every client')+'</td><td>'+esc(r.scope)+'</td>' +
              '<td>'+esc(day(r.effective_from))+(r.future?' <span class="chip warn">future</span>':'')+'</td>' +
              '<td>'+esc(r.effective_to ? day(r.effective_to) : 'open')+'</td>' +
              '<td>'+esc(r.versions)+'</td>' +
              '<td><button class="btn" data-rth="'+esc(r.family)+'">History</button></td></tr>';
          }).join("") + '</table></div>'
        : '<div class="empty">No rates configured yet. ' + esc(d.emptyWhy) + '</div>') +
    '</div><div id="rthist"></div>';

  if (el("rtAdd")) el("rtAdd").onclick = function(){ rtForm(d, null); };
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-rth]"), function(b){
    b.onclick = async function(){
      var fam = b.getAttribute("data-rth");
      var h = await ops("/rates/" + encodeURIComponent(fam) + "/history");
      if (h.error) { el("rthist").innerHTML = msg("bad", h.reason||h.error); return; }
      el("rthist").innerHTML =
        '<div class="card"><h2>Rate history</h2>' +
        '<p class="mute">' + esc(fam) + ' &middot; every version, oldest first</p>' +
        '<div class="scroll"><table><tr><th>From</th><th>To</th><th>Value</th>' +
        '<th>Applies to</th><th>Set by</th><th>Why</th></tr>' +
        (h.versions||[]).map(function(v){
          return '<tr><td>'+esc(day(v.effective_from))+'</td>' +
            '<td>'+esc(v.effective_to ? day(v.effective_to) : 'open')+'</td>' +
            '<td>'+esc(money(v.value))+'</td><td>'+esc(v.scope)+'</td>' +
            '<td>'+esc(v.by||'')+'</td><td class="mute">'+esc(v.reason||'')+'</td></tr>';
        }).join("") + '</table></div>' +
        '<p class="mute">A report for a past month uses the rate valid during that ' +
        'month. Changing a rate adds a version; it never rewrites a closed month.</p>' +
        (d.mayEdit ? '<button class="btn" data-rtnew="'+esc(fam)+'">New version</button> ' : '') +
        '<button class="btn" id="rthClose">Close</button></div>';
      el("rthClose").onclick = function(){ el("rthist").innerHTML = ""; };
      Array.prototype.forEach.call(el("rthist").querySelectorAll("[data-rtnew]"), function(n){
        n.onclick = function(){ rtForm(d, n.getAttribute("data-rtnew")); };
      });
    };
  });
}

function rtForm(d, family){
  el("rtbox").innerHTML =
    '<div class="card"><h2>' + (family ? 'New version of ' + esc(family) : 'Add a rate') + '</h2>' +
    '<label>Applies to<br><select id="rtScope">' +
      (d.scopes||[]).map(function(s){
        return '<option value="'+esc(s.key)+'">'+esc(s.label)+'</option>'; }).join("") +
      '</select></label> ' +
    '<label>Client<br><select id="rtClient"><option value="">every client</option>' +
      (d.clients||[]).map(function(c){
        return '<option value="'+esc(c.id)+'">'+esc(c.name)+'</option>'; }).join("") +
      '</select></label> ' +
    '<label>Value<br><input id="rtValue" type="number" min="0" step="0.01"></label> ' +
    '<label>With effect from<br><input id="rtFrom" type="date"></label> ' +
    '<label>Why<br><input id="rtWhy" placeholder="what changed and on whose say-so"></label> ' +
    '<button class="btn primary" id="rtGo">Save</button> ' +
    '<button class="btn" id="rtCancel">Cancel</button>' +
    '<p class="mute">The version in force is end-dated the day before this one ' +
    'starts. Nothing is overwritten.</p><div id="rtboxmsg"></div></div>';
  el("rtCancel").onclick = function(){ el("rtbox").innerHTML = ""; };
  el("rtGo").onclick = async function(){
    el("rtGo").disabled = true;
    var out = await ops("/rates", { method:"POST", body:{
      family: family, clientId: el("rtClient").value || null,
      scope: el("rtScope").value, value: Number(el("rtValue").value),
      effectiveFrom: el("rtFrom").value, reason: el("rtWhy").value } });
    el("rtGo").disabled = false;
    if (out.error) { el("rtboxmsg").innerHTML = msg("bad", out.reason||out.error); return; }
    el("rtbox").innerHTML = "";
    el("rtmsg").innerHTML = msg("ok", out.code + " saved" +
      (out.superseded ? ", superseding " + out.superseded : "") + ".");
    vRates();
  };
}
$js$;

  v_new := replace(v_body, E'\nboot();\n</script>', v_js || E'\nboot();\n</script>');

  if position('async function vVisits(){' in v_new) = 0 then raise exception 'visits not added'; end if;
  if position('async function vMis(){' in v_new) = 0 then raise exception 'mis not added'; end if;
  if position('async function vRates(){' in v_new) = 0 then raise exception 'rates not added'; end if;
  if length(v_new) - length(v_body) < 34000 then
    raise exception 'the page grew by only % bytes', length(v_new) - length(v_body);
  end if;

  update app_page set html = v_new, updated_at = now() where slug = 'app';
end $$;
