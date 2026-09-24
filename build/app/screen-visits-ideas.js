/* --------------------------------------------------------- visits & claims
   The design: log a visit, raise a claim, and a claim table that shows the
   stage each one is at and who it is with. A visit writes back into the
   branch record -- it updates the contact it met.                        */
async function vVisits(){
  var d = await api("/field");
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
      esc(flow.join(' → ').toLowerCase().replace(/_/g,' ')) +
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
          'the claim against it — a claim tied to a visit is one Operations can check.</div>') +
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
        return '<option value="'+esc(b.id)+'">'+esc(b.client)+' — '+esc(b.name)+' ('+esc(b.code)+')</option>';
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
    var out = await api("/field/visit", { method:"POST", body:{
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
          return '<option value="'+esc(v.id)+'">'+esc(day(v.visited_on))+' — '+
            esc(v.branch||'no branch')+' — '+esc(v.purpose||'')+'</option>';
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
    var out = await api("/field/claim", { method:"POST", body:{
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
    var out = await api("/field/claim/" + encodeURIComponent(id) + "/advance",
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
  var d = await api("/field/ideas");
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
              '<div class="mute">' + esc(i.ref) + ' · ' + esc(i.raised_by) +
                (i.owner_dept ? ' · ' + esc(i.owner_dept) : '') +
                ' · ' + esc(when(i.created_at)) + '</div>' +
              (i.body ? '<div class="mute">' + esc(i.body) + '</div>' : '') +
              (i.decision_reason ? '<div class="mute"><b>Decision:</b> ' + esc(i.decision_reason) + '</div>' : '') +
              (i.charter ? '<div class="mute"><b>Charter:</b> ' + esc(i.charter) + '</div>' : '') +
              '</div>' +
              (mayDecide ? '<div class="cfgset"><button class="btn" data-idd="'+esc(i.id)+'" ' +
                'data-idst="'+esc(i.stage)+'">Decide</button></div>' : '') +
              '</div>';
          }).join("")
        : '<div class="empty">Nobody has shared an idea yet. The first one starts the ' +
          'list — it goes to Business Excellence, who take it to review.</div>') +
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
      var out = await api("/field/idea", { method:"POST", body:{
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
        var out = await api("/field/idea/" + encodeURIComponent(id) + "/decide",
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
