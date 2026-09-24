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
        ? esc(d.period) + ' · grouped by ' + esc(d.dims[d.group].label.toLowerCase()) +
          ' · ' + esc(rows.length) + ' rows'
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
  var d = await api("/mis/tenday" + (tenPeriod ? "?period=" + encodeURIComponent(tenPeriod) : ""));
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
  var d = await api("/mis/reports");
  if (d.error) { el("view").innerHTML = "<h1>Reports</h1>" + msg("bad", d.reason||d.error); return; }
  el("view").innerHTML =
    '<div class="page-head"><div><h1>Reports</h1>' +
    '<p class="mute">' + esc(d.note) + '</p></div></div>' +
    '<div class="card">' + (d.reports||[]).map(function(r){
      return '<div class="cfgrow"><div><b>' + esc(r.name) + '</b>' +
        (Number(r.rows) ? ' <span class="chip ok">' + esc(r.rows) + ' rows</span>'
                        : ' <span class="pill warn">nothing to print yet</span>') +
        '<div class="mute">' + esc(r.what) + '</div>' +
        '<div class="mute">Scope · ' + esc(r.scope) + '</div></div></div>';
    }).join("") + '</div>';
}

/* ------------------------------------------------------------ rate master
   "A report for a past month uses the rate valid during that month, not the
   one showing at the top of this list. Changing a rate adds a version; it
   never rewrites a closed month."                                         */
async function vRates(){
  var d = await api("/rates");
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
      var h = await api("/rates/" + encodeURIComponent(fam) + "/history");
      if (h.error) { el("rthist").innerHTML = msg("bad", h.reason||h.error); return; }
      el("rthist").innerHTML =
        '<div class="card"><h2>Rate history</h2>' +
        '<p class="mute">' + esc(fam) + ' · every version, oldest first</p>' +
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
    var out = await api("/rates", { method:"POST", body:{
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
