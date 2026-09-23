/* ------------------------------------------------- history & audit trail
   Every write in this tool goes through one transaction helper, and that
   helper cannot commit an audit row without the change it describes. So
   this is not a log somebody remembered to write: it is the same
   transaction. That is why it can be shown as evidence.                  */
var hstAction = "";
async function vHistory(){
  var q = "/history?limit=300" + (hstAction ? "&action=" + encodeURIComponent(hstAction) : "");
  var d = await api(q);
  if (d.error) {
    el("view").innerHTML = "<h1>History</h1>" + msg("bad", d.reason || d.error); return;
  }
  var rows = d.rows || [], kinds = d.kinds || [];

  function detail(x){
    function pick(v){
      if (!v) return "";
      try { var o = (typeof v === "string") ? JSON.parse(v) : v;
            return Object.keys(o).slice(0,4).map(function(k){
              var val = o[k];
              if (val && typeof val === "object") val = JSON.stringify(val).slice(0,40);
              return k + " " + String(val === null ? "-" : val).slice(0,40);
            }).join(", ");
      } catch(e){ return String(v).slice(0,80); }
    }
    var a = pick(x.old_value), b = pick(x.new_value);
    return a && b ? esc(a) + ' &rarr; ' + esc(b) : esc(b || a || "");
  }

  el("view").innerHTML =
    '<div class="page-head"><div><h1>History &amp; audit trail</h1>' +
    '<p class="mute">' + esc(rows.length) + ' entries' +
      (d.mine && !d.isAdmin ? ' that you made' : '') +
      '. Every one of them was written inside the transaction that made the ' +
      'change, so nothing here can describe something that did not happen, and ' +
      'nothing that happened is missing.</p></div></div>' +
    '<div class="card"><h2>What kind</h2>' +
      '<button class="btn' + (hstAction ? '' : ' primary') + '" data-hst="">Everything</button> ' +
      kinds.map(function(k){
        return '<button class="btn' + (hstAction === k.action ? ' primary' : '') +
          '" data-hst="' + esc(k.action) + '">' + esc(k.action) +
          ' <span class="chip">' + esc(k.n) + '</span></button> ';
      }).join("") +
    '</div>' +
    '<div class="card"><h2>What happened</h2>' +
      (rows.length
        ? '<div class="scroll"><table>' +
          '<tr><th>When</th><th>Who</th><th>What</th><th>To what</th><th>Detail</th></tr>' +
          rows.map(function(x){
            return '<tr><td>' + esc(when(x.at)) + '</td>' +
              '<td>' + esc(x.actor || "the tool itself") +
                (x.employee_no ? ' <span class="mute">' + esc(x.employee_no) + '</span>' : '') + '</td>' +
              '<td>' + esc(x.action) + '</td>' +
              '<td>' + esc(x.entity_type || "") +
                (x.entity_ref ? ' <span class="mute">' + esc(x.entity_ref) + '</span>' : '') + '</td>' +
              '<td class="mute">' + detail(x) + '</td></tr>';
          }).join("") + '</table></div>'
        : '<div class="empty">Nothing matches that.</div>') +
    '</div>';

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-hst]"), function(b){
    b.onclick = function(){ hstAction = b.getAttribute("data-hst"); vHistory(); };
  });
}
