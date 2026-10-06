/* ====================================================================== team
   My team — the people tree, in the shape of the attached org-chart design.

   The design is a sample of the UI and UX, not of the content: its cards
   carry chairs and level frameworks, these carry the people who actually
   hold them and what they have filed this month. What is taken from it is
   the language — a paper surface, hairline connectors drawn in CSS rather
   than SVG, a serif name over a small-caps chair, tiny outlined tags, and
   depth shown by tinting the top edge of a card rather than by indenting.

   What the tool already had under "My team" was a second drawing of the
   CHAIR tree, which is what "Structure" is for. This is the other tree:
   who reports to whom. It is worth being exact about the difference,
   because person.manager_id is what every visibility rule since migration
   218 is built on. Dragging a card here changes who can read whose
   numbers. That is why nothing on this screen decides anything: every
   card arrives from org_team_tree carrying its own mayMove and maySet,
   and every drop is refused or allowed by org_move_person.             */

var TM = { tree:null, cycle:null, shut:{}, sel:null, drag:null, over:null,
           busy:false, says:"", detail:null, detailFor:null, addTo:null,
           conduct:null, conductFor:null, form:null,
           addOpts:null, addTab:"move", addErr:null, qForm:null,
           /* the flat list beside the chart: which of the two is on
              screen, the payload, the search box, which gap is being
              filtered for, how it is sorted, and the one row whose
              reporting line is being changed. */
           view:"chart", tbl:null, tq:"", tonly:"", tsort:"name", tedit:null };

async function vPeople(){
  el("view").innerHTML = '<p class="mute">Loading&hellip;</p>';
  /* Both at once. The list is refused for everybody but the administrator
     and HR -- it answers {mayUse:false} with a reason rather than an error
     -- so asking for it always is cheaper than working out first whether
     to ask, and the answer decides whether the tab is drawn at all. */
  var got = await Promise.all([
    perfApi("/perf/team/tree"),
    perfApi("/perf/team/people")
  ]);
  TM.tree = got[0];
  TM.tbl  = got[1];
  /* Somebody who manages nobody -- the administrator, and HR -- gets an
     empty chart and used to get nothing else. For them the list IS the
     screen, so it opens on it. */
  if (tmMayList() && !tmRoot(TM.tree || {})) TM.view = "table";
  tmRender();
}

function tmMayList(){
  return !!(TM.tbl && !TM.tbl.error && TM.tbl.mayUse);
}

/* Everything below hangs off one flat list of people with a depth and a
   managerId. Building the parent map here rather than asking the server
   for nested JSON keeps the move cheap: after a drag only one row's
   managerId changes, and the tree redraws from the same array.          */
function tmKids(people){
  var by = {};
  people.forEach(function(p){
    var k = p.managerId || "_root";
    (by[k] = by[k] || []).push(p);
  });
  return by;
}

function tmRoot(t){
  var people = t.people || [];
  for (var i = 0; i < people.length; i++) if (people[i].depth === 0) return people[i];
  return people[0] || null;
}

/* ------------------------------------------------------- one card
   Status never travels as colour alone: the bar carries a number and a
   word beside it, so the card reads the same in greyscale and to somebody
   who does not see red and green apart.                                */
function tmCard(p){
  var d = Math.min(5, (p.depth || 0) + 1);
  var pct = p.progress;
  var band = pct === null || pct === undefined ? "none"
           : pct >= 100 ? "good" : pct >= 50 ? "part" : "short";
  var word = { good:"on target", part:"part way", short:"behind", none:"nothing filed" }[band];

  var tags = [];
  if (p.reports) tags.push('<span class="tmtg n">' + p.reports + ' report' +
                           (p.reports === 1 ? '' : 's') + '</span>');
  if (p.measures) tags.push('<span class="tmtg">' + p.filed + '/' + p.measures + ' filed</span>');
  if (!p.measures) tags.push('<span class="tmtg d">no measures</span>');
  if (p.rel === "self") tags.push('<span class="tmtg v">you</span>');

  return '<div class="tmcard d' + d + (TM.sel === p.personId ? ' sel' : '') +
      (TM.over === p.personId ? ' over' : '') + '"' +
      ' data-tm="' + esc(p.personId) + '"' +
      (p.mayMove ? ' draggable="true"' : '') + '>' +
    /* The + sits on the card rather than in the panel because that is
       where somebody looking at a team reaches for it, and because it
       names WHOSE team is being added to without a sentence saying so. */
    (p.mayAddUnder
      ? '<button class="tmadd" data-tmadd="' + esc(p.personId) + '" title="Add to ' +
        esc(p.name) + '&rsquo;s team">+</button>'
      : '') +
    '<div class="tmnm">' + esc(p.name) + '</div>' +
    '<div class="tmch">' + esc(p.chair || "no chair") + '</div>' +
    (p.employeeNo ? '<div class="tmno">' + esc(p.employeeNo) + '</div>' : '') +
    '<div class="tmbar ' + band + '"><i style="width:' +
      (pct === null || pct === undefined ? 0 : Math.max(2, Math.min(100, pct))) +
      '%"></i></div>' +
    '<div class="tmpc ' + band + '">' +
      (pct === null || pct === undefined ? esc(word)
        : esc(pct) + '% &middot; ' + esc(word)) + '</div>' +
    (tags.length ? '<div class="tmtags">' + tags.join("") + '</div>' : '') +
    '</div>';
}

function tmBranch(by, key){
  var kids = by[key] || [];
  if (!kids.length) return "";
  return '<ul>' + kids.map(function(p){
    var mine = by[p.personId] || [];
    var shut = TM.shut[p.personId];
    return '<li>' +
      (mine.length
        ? '<button class="tmtog" data-tmtog="' + esc(p.personId) + '">' +
            (shut ? '+' : '&minus;') + '</button>'
        : '') +
      tmCard(p) +
      (mine.length && !shut ? tmBranch(by, p.personId) : '') +
      '</li>';
  }).join("") + '</ul>';
}

/* ============================================ the flat list of everybody

   The chart above is the right drawing for "who works for whom". It is the
   wrong one for the job this list does, which is the opposite: finding the
   people the chart does NOT show. Somebody with no manager is drawn under
   nobody, so on a chart they are simply absent — and absence is the one
   thing a chart cannot point at.

   Measured on the live company the day this was written: 103 members of
   staff, of whom 3 have no manager, 2 hold no chair, 49 have no designation
   and 13 have no location. None of that is visible on the tree; all of it
   is one glance in a list.

   Nothing here writes. Changing who somebody reports to goes through
   org_move_person, the same call the drag does, so there is one set of
   rules, one audit row and one refusal. */

/* The gaps, as chips. Each is a count and the filter behind it, which is
   the same question asked twice — press the number and you are looking at
   the people it counted. */
var TM_GAPS = [
  { key:"",              label:"Everybody",       test:null },
  { key:"noManager",     label:"No manager",      test:function(p){ return !p.managerId; } },
  { key:"noChair",       label:"No chair",        test:function(p){ return !p.chair; } },
  { key:"noDesignation", label:"No designation",  test:function(p){ return !p.designation; } },
  { key:"noDepartment",  label:"No department",   test:function(p){ return !p.department; } },
  { key:"noLocation",    label:"No location",     test:function(p){ return !p.location; } }
];

function tmGapTest(key){
  for (var i = 0; i < TM_GAPS.length; i++) {
    if (TM_GAPS[i].key === key) return TM_GAPS[i].test;
  }
  return null;
}

/* Everybody below a person, worked out here rather than asked for. The
   list already carries every row's managerId, so the whole tree is in the
   browser — and moving somebody under their own report is the one refusal
   org_move_person makes that the screen can predict exactly. Offering it
   and having it refused is the defect migration 242 was written for. */
function tmBelow(personId){
  var all = (TM.tbl && TM.tbl.people) || [];
  var kids = {};
  all.forEach(function(p){
    if (!p.managerId) return;
    (kids[p.managerId] = kids[p.managerId] || []).push(p.personId);
  });
  var out = {}, stack = (kids[personId] || []).slice();
  while (stack.length) {
    var id = stack.pop();
    if (out[id]) continue;          /* a ring in the data must not hang the page */
    out[id] = true;
    (kids[id] || []).forEach(function(k){ stack.push(k); });
  }
  return out;
}

function tmListHead(){
  var s = TM.tbl.summary || {};
  var who = TM.tbl.asAdministrator ? "You hold the administrator role"
          : "You work in Human Resources";
  return '<div class="page-head"><div><h1>All people</h1>' +
    '<p class="mute">' + esc(who) + ', so this is every person who works ' +
    'here — including the ones the chart cannot draw because they report to ' +
    'nobody. Changing who somebody reports to changes who can read their ' +
    'numbers, so every change is recorded.</p></div>' +
    '<div class="tmcount"><b>' + esc(s.people || 0) + '</b><span>people</span></div>' +
    '</div>';
}

/* The rows actually on screen: the search box and the chip, applied in that
   order, then sorted. Done here rather than in the database because the
   whole company is a hundred rows and a round trip per keystroke is a
   worse screen than a hundred rows of JavaScript. */
function tmRows(){
  var all = (TM.tbl && TM.tbl.people) || [];
  var test = tmGapTest(TM.tonly);
  var q = (TM.tq || "").trim().toLowerCase();
  var rows = all.filter(function(p){
    if (test && !test(p)) return false;
    if (!q) return true;
    return [p.name, p.employeeNo, p.designation, p.chair, p.location,
            p.department, p.reportsTo, p.workEmail]
      .join(" ").toLowerCase().indexOf(q) >= 0;
  });
  var k = TM.tsort;
  /* A missing value sorts LAST whichever way the column is read: the point
     of the list is to find the gaps, and a column of blanks at the top of
     an alphabetical sort buries the names. The chips are how you ask for
     the gaps. */
  rows.sort(function(a, b){
    if (k === "reports") return (b.reports || 0) - (a.reports || 0);
    var x = (a[k] || ""), y = (b[k] || "");
    if (!x && y) return 1;
    if (x && !y) return -1;
    if (x !== y) return x.toLowerCase() < y.toLowerCase() ? -1 : 1;
    return (a.name || "") < (b.name || "") ? -1 : 1;
  });
  return rows;
}

function tmTable(){
  var s = TM.tbl.summary || {};
  var chips = TM_GAPS.map(function(g){
    var n = g.key ? (s[g.key] || 0) : (s.people || 0);
    /* A gap with nobody in it is not offered. "No chair 0" is a button
       that leads to an empty table, which reads as a broken filter. */
    if (g.key && !n) return "";
    return '<button class="tmchip' + (TM.tonly === g.key ? ' on' : '') + '" ' +
      'data-tmgap="' + esc(g.key) + '">' + esc(g.label) +
      ' <span class="tmtg n">' + esc(n) + '</span></button>';
  }).join("");

  var cols = [["name","Name"], ["designation","Designation"],
              ["location","Location"], ["reportsTo","Reporting to"],
              ["reports","Reports"]];
  var head = '<tr>' + cols.map(function(c){
    return '<th><button class="tmsort' + (TM.tsort === c[0] ? ' on' : '') + '" ' +
      'data-tmsort="' + c[0] + '">' + esc(c[1]) +
      (TM.tsort === c[0] ? ' <span class="tmar">&darr;</span>' : '') +
      '</button></th>';
  }).join("") + '<th></th></tr>';

  var rows = tmRows();
  var body = rows.length
    ? rows.map(tmListRow).join("")
    : '<tr><td colspan="6" class="mute">Nobody matches that.</td></tr>';

  return '<div class="tmbarrow">' +
      '<input id="tmfind" class="pfin tmfind" placeholder="Find a name, a number, a place&hellip;" ' +
        'value="' + esc(TM.tq || "") + '">' +
      '<span class="mute tmshow">' + esc(rows.length) + ' of ' +
        esc(s.people || 0) + ' shown</span>' +
    '</div>' +
    '<div class="tmchips">' + chips + '</div>' +
    '<div class="card tmlist"><div class="scroll"><table class="tbl">' +
      '<thead>' + head + '</thead><tbody>' + body + '</tbody></table></div></div>';
}

function tmListRow(p){
  var editing = TM.tedit === p.personId;

  var who = '<td><b>' + esc(p.name) + '</b>' +
    (p.employeeNo ? ' <span class="tmtg">' + esc(p.employeeNo) + '</span>' : '') +
    '<div class="mute">' + esc(p.workEmail || "no work e-mail") +
      (p.department ? ' &middot; ' + esc(p.department) : '') + '</div></td>';

  /* Designation and chair are two different columns in the database and
     half the company has only the second. Showing the chair underneath is
     not the same as pretending it is the designation — it is what the
     person actually holds, said as what it is. */
  var what = '<td>' + (p.designation
      ? esc(p.designation)
      : '<span class="tmgap">not set</span>') +
    (p.chair ? '<div class="mute">' + esc(p.chair) + '</div>'
             : '<div class="tmgap">no chair</div>') + '</td>';

  var place = '<td>' + (p.location
      ? esc(p.location) +
        (p.locationFrom === "coverage"
          ? '<div class="mute">from what they cover</div>' : '')
      : '<span class="tmgap">not set</span>') + '</td>';

  var rep = '<td>' + (editing ? tmRepForm(p)
    : (p.reportsTo
        ? esc(p.reportsTo)
        : '<span class="tmgap">nobody</span>')) + '</td>';

  var n = '<td class="tmn">' + (p.reports ? esc(p.reports) : '') + '</td>';

  var act = '<td class="plact">' +
    (p.mayMove && !editing
      ? '<button class="btn" data-tmrep="' + esc(p.personId) + '">' +
        (p.reportsTo ? 'Change' : 'Assign') + '</button>'
      : '') + '</td>';

  return '<tr' + (p.managerId ? '' : ' class="tmwarnrow"') + '>' +
    who + what + place + rep + n + act + '</tr>';
}

/* The picker. Everybody the move would not refuse: not themselves, and
   nobody already below them. The order is alphabetical because that is how
   somebody looks for a name they already have in mind. */
function tmRepForm(p){
  var all = (TM.tbl && TM.tbl.people) || [];
  var below = tmBelow(p.personId);
  var opts = all.filter(function(q){
    return q.personId !== p.personId && !below[q.personId];
  }).map(function(q){
    return '<option value="' + esc(q.personId) + '"' +
      (q.personId === p.managerId ? ' selected' : '') + '>' +
      esc(q.name) + (q.chair ? ' &middot; ' + esc(q.chair) : '') + '</option>';
  }).join("");

  return '<div class="tmrep">' +
    '<select id="tmrepsel" class="pfin">' +
      '<option value="">&mdash; nobody: top of the company &mdash;</option>' +
      opts +
    '</select>' +
    '<div class="tmrepb">' +
      '<button class="btn primary" data-tmrepgo="' + esc(p.personId) + '">Save</button> ' +
      '<button class="btn" id="tmrepno">Cancel</button>' +
    '</div></div>';
}

/* Two drawings of the same people, and the switch between them.
   Drawn only where there are two: for everybody but the administrator and
   HR there is one, and a tab strip with one tab on it is furniture.      */
function tmTabs(){
  if (!tmMayList()) return "";
  var n = ((TM.tbl.summary || {}).people) || 0;
  return '<div class="tmviews">' +
    '<button class="tmview' + (TM.view === "chart" ? ' on' : '') + '" ' +
      'data-tmview="chart">Chart</button>' +
    '<button class="tmview' + (TM.view === "table" ? ' on' : '') + '" ' +
      'data-tmview="table">All people <span class="tmtg n">' + esc(n) + '</span></button>' +
    '</div>';
}

function tmRender(){
  var t = TM.tree;
  if ((!t || t.error) && !tmMayList()) {
    el("view").innerHTML = '<h1>My team</h1>' +
      msg("bad", (t && (t.reason || t.error)) || "The team could not be read.");
    return;
  }
  /* The list comes BEFORE the chart's own empty state on purpose. The two
     people who most need it -- the administrator and HR -- are exactly the
     two who manage nobody, so a guard that returns early on "nobody reports
     to you" would hide the list from the only people allowed to see it. */
  if (TM.view === "table" && tmMayList()) {
    el("view").innerHTML = tmListHead() + tmTabs() + tmTable() +
      '<div id="pfmsg">' + TM.says + '</div>';
    tmWire();
    return;
  }

  var people = (t && t.people) || [];
  var root = tmRoot(t || {});
  if (!root) {
    el("view").innerHTML = '<h1>My team</h1>' + tmTabs() +
      '<div class="empty">Nobody reports to you, so there is no team to draw. ' +
      'Your own measures are on Performance &amp; appraisal.' +
      (tmMayList()
        ? ' Every person in the company is under <b>All people</b> above.'
        : '') +
      '</div>' + '<div id="pfmsg">' + TM.says + '</div>';
    tmWire();
    return;
  }
  var by = tmKids(people);

  var n = people.length - 1;
  var head = '<div class="page-head"><div><h1>My team</h1>' +
    '<p class="mute">' +
      (n ? esc(n) + ' ' + (n === 1 ? 'person' : 'people') + ' below you. ' : '') +
      'Drag a card onto another to change who they report to. ' +
      'That changes who can see their numbers, so every move is recorded.' +
    '</p></div></div>';

  var bar = '<div class="tmbarrow">' +
    '<button class="btn" id="tmexp">Expand all</button> ' +
    '<button class="btn" id="tmcol">Collapse all</button> ' +
    '<span class="mute tmkey">' +
      '<span class="tmsw good"></span> on target ' +
      '<span class="tmsw part"></span> part way ' +
      '<span class="tmsw short"></span> behind ' +
      '<span class="tmsw none"></span> nothing filed' +
    '</span></div>';

  el("view").innerHTML = head + tmTabs() + bar +
    '<div class="card tmwrap"><div class="tmoc">' +
      '<ul><li>' +
        ((by[root.personId] || []).length
          ? '<button class="tmtog" data-tmtog="' + esc(root.personId) + '">' +
              (TM.shut[root.personId] ? '+' : '&minus;') + '</button>'
          : '') +
        tmCard(root) +
        (TM.shut[root.personId] ? '' : tmBranch(by, root.personId)) +
      '</li></ul>' +
    '</div></div>' +
    (TM.addTo ? tmAdd() : '') +
    (TM.sel ? tmPanel() : '') +
    '<div id="pfmsg">' + TM.says + '</div>';

  tmWire();
}

/* -------------------------------------------- the + on a card
   Two things live behind one button and they are NOT the same thing, so
   they are not the same tab. Moving somebody who already works here is
   the manager's to do outright: the identity exists, nothing is created,
   and org_move_person settles it. Asking for somebody who does not work
   here yet is a request, because it makes an ACCOUNT -- something that
   can sign in, be paid and read other people's numbers -- and that stays
   HR's. The panel says which is which in those words, so nobody files a
   request for a person sitting two desks away.                          */
function tmAdd(){
  var o = TM.addOpts;
  if (!o) return '<div class="card tmpanel"><p class="mute">Loading&hellip;</p></div>';
  if (o.error) {
    return '<div class="card tmpanel">' + msg("bad", o.reason || o.error) +
      '<p><button class="btn" id="tmaclose">Close</button></p></div>';
  }

  var movable = o.movable || [];
  var tabs = '<div class="tmtabs">' +
    '<button class="tmtab' + (TM.addTab === "move" ? ' on' : '') + '" data-tmatab="move">' +
      'Somebody already here' +
      (movable.length ? ' <span class="tmtg n">' + esc(movable.length) + '</span>' : '') +
    '</button>' +
    '<button class="tmtab' + (TM.addTab === "new" ? ' on' : '') + '" data-tmatab="new">' +
      (o.mayCreate ? 'A new joiner' : 'Ask HR for a new joiner') +
    '</button></div>';

  var body;
  if (TM.addTab === "move") {
    body = movable.length
      ? '<p class="mute">They already have an account. Moving them changes who ' +
        'can see their numbers, so it is recorded.</p>' +
        '<p><select id="tmamove" class="pfin" style="max-width:26rem">' +
          movable.map(function(m){
            return '<option value="' + esc(m.personId) + '">' + esc(m.name) +
              (m.employeeNo ? ' &middot; ' + esc(m.employeeNo) : '') +
              (m.managerName ? ' &mdash; now under ' + esc(m.managerName) : '') +
              '</option>';
          }).join("") +
        '</select></p>' +
        '<p><button class="btn primary" id="tmamovego">Move them under ' +
          esc(o.underName) + '</button></p>'
      : '<p class="mute">There is nobody you can move. Everybody you manage ' +
        'already reports to ' + esc(o.underName) + ', or moving them would ' +
        'turn the reporting line into a circle.</p>';
  } else {
    var chairs = o.chairs || [];
    body =
      (o.mayCreate
        ? '<p class="mute">You are in HR, so you can make the account yourself ' +
          'on <a href="#people">People</a> &mdash; that form asks for everything ' +
          'at once. Filing it here instead puts it in the same queue, which is ' +
          'useful when somebody else will finish it.</p>'
        : '<p class="mute">A new joiner needs an account, and an account is ' +
          'HR&rsquo;s to make: it can sign in, be paid, and read other ' +
          'people&rsquo;s numbers. Ask here and HR finishes it &mdash; they ' +
          'appear on your team the moment that happens.</p>') +
      '<p><label>Their name<br><input id="tmaname" class="pfin" style="width:100%" ' +
        'placeholder="Nikhil Sawant"></label></p>' +
      '<p><label>Work e-mail<br><input id="tmamail" class="pfin" style="width:100%" ' +
        'placeholder="nikhil.sawant@cruxindia.co.in"></label></p>' +
      '<p><label>Chair <select id="tmachair">' +
        chairs.map(function(c){
          return '<option value="' + esc(c.chairId) + '">' + esc(c.title) + '</option>';
        }).join("") +
      '</select></label> ' +
      '<label>Kind <select id="tmatype">' +
        '<option value="EMPLOYEE">Employee</option>' +
        '<option value="PARTNER">Partner</option>' +
        '<option value="INTERN">Intern</option>' +
        '<option value="CONTRACT">Contract</option>' +
      '</select></label></p>' +
      '<p><button class="btn primary" id="tmaask">Send it to HR</button></p>';
  }

  /* Anything already queued for this manager, shown on both tabs, because
     the commonest way to get two accounts for one person is not knowing
     somebody asked on Monday. */
  var pend = o.pending || [];
  var queue = pend.length
    ? '<h3 class="tmh3">Already with HR</h3>' +
      '<table class="tbl tmq"><tbody>' + pend.map(function(q){
        return '<tr><td>' + esc(q.name) + '</td><td class="mute">' + esc(q.email) +
          '</td><td class="mute">asked by ' + esc(q.requestedBy || "somebody") +
          '</td><td>' + (TM.addOpts.mayCreate
            ? '<button class="btn" data-tmqok="' + esc(q.requestId) + '">Make the account</button> ' +
              '<button class="btn" data-tmqno="' + esc(q.requestId) + '">Refuse</button>'
            : '<span class="tmtg">waiting</span>') + '</td></tr>';
      }).join("") + '</tbody></table>' +
      (TM.qForm && TM.qForm.indexOf("ok:") === 0 ? tmQForm(TM.qForm.slice(3)) : '') +
      (TM.qForm && TM.qForm.indexOf("no:") === 0 ? tmQNo(TM.qForm.slice(3)) : '')
    : '';

  return '<div class="card tmpanel">' +
    '<h2>Add to ' + esc(o.underName) + '&rsquo;s team</h2>' +
    tabs + '<div class="tmabody">' + body + '</div>' +
    (TM.addErr ? tmAddErr() : '') +
    queue +
    '<p><button class="btn" id="tmaclose">Close</button></p></div>';
}

/* person_add answers with a field-by-field list rather than one sentence,
   and throwing that away to print "invalid" would be the same as not
   having written it. */
function tmAddErr(){
  var e = TM.addErr;
  if (!e) return "";
  var errs = e.errors || [];
  if (!errs.length) return msg("bad", e.reason || e.error);
  return msg("bad", (e.reason || "That cannot be made yet.") +
    '<ul class="tmerrs">' + errs.map(function(x){
      return '<li><b>' + esc(x.field) + '</b> &mdash; ' + esc(x.says) + '</li>';
    }).join("") + '</ul>');
}

/* What HR adds that the manager could not know: the employee number every
   performance upload joins on, and the mobile that is the second way in. */
function tmQForm(id){
  return '<div class="tmfm"><h4>Make the account</h4>' +
    '<p class="mute">The name, address, chair and manager come from the ask ' +
    'and cannot be changed here &mdash; approving is approving that person, ' +
    'not a different one.</p>' +
    '<p><label>Employee number<br><input id="tmqno" class="pfin" ' +
      'placeholder="EMP-0123"></label> ' +
    '<label>Mobile<br><input id="tmqmob" class="pfin" ' +
      'placeholder="9820011223"></label></p>' +
    '<p><label>Department<br><input id="tmqdept" class="pfin"></label> ' +
    '<label>Joined on<br><input id="tmqjoin" type="date"></label></p>' +
    '<p><label>Sign-in role <select id="tmqrole">' +
      '<option value="VIEWER">Viewer</option>' +
      '<option value="MANAGER">Manager</option>' +
      '<option value="LOCATION_HEAD">Location head</option>' +
    '</select></label></p>' +
    '<p><button class="btn primary" data-tmqgo="' + esc(id) + '">Create it</button> ' +
    '<button class="btn" id="tmqcancel">Cancel</button></p></div>';
}

/* A refusal must carry a reason -- the table's own constraint insists, and
   so does the manager who asked and has to do something next. */
function tmQNo(id){
  return '<div class="tmfm"><h4>Refuse this ask</h4>' +
    '<p><label>Why<br><textarea id="tmqwhy" rows="3" style="width:100%" ' +
      'placeholder="Headcount for the quarter is already filled."></textarea></label></p>' +
    '<p><button class="btn primary" data-tmqnogo="' + esc(id) + '">Refuse it</button> ' +
    '<button class="btn" id="tmqcancel">Cancel</button></p></div>';
}

/* ------------------------------------- what a manager does with a person
   Only the actions that exist are offered. A button that opens nothing is
   worse than no button: it tells somebody the tool does a thing it does
   not, and they stop trusting the ones that work. PIP and a formal
   warning are named here as not built rather than drawn and dead.       */
function tmPanel(){
  var p = (TM.tree.people || []).filter(function(x){ return x.personId === TM.sel; })[0];
  if (!p) return "";
  var can = p.maySet;

  var acts = can
    ? '<div class="tmacts">' +
        '<button class="btn" data-tmgo="targets">Set this month&rsquo;s targets</button>' +
        '<button class="btn" data-tmgo="score">Monthly review and score</button>' +
        '<button class="btn" data-tmgo="quarter">Quarterly scorecard</button>' +
        '<button class="btn" data-tmgo="task">Ask them for something</button>' +
        '<button class="btn" data-tmform="warn">Issue a warning</button>' +
        '<button class="btn" data-tmform="pip">Put on a PIP</button>' +
      '</div>'
    : '<p class="mute">You can see how ' + esc(p.name.split(" ")[0]) +
      ' is doing. Setting their targets and scoring them belongs to the ' +
      'person they report to.</p>';

  var det = TM.detailFor === p.personId ? TM.detail : null;

  return '<div class="card tmpanel">' +
    '<h2>' + esc(p.name) +
      ' <span class="mute">&middot; ' + esc(p.chair || "no chair") + '</span></h2>' +
    '<p class="mute">' +
      (p.measures
        ? esc(p.filed) + ' of ' + esc(p.measures) + ' measures filed this month' +
          (p.progress === null || p.progress === undefined ? ''
            : ', ' + esc(p.onTrack) + ' at or past target')
        : 'No measures are set for them this month.') +
    '</p>' +
    acts +
    tmConduct() +
    '<h3 class="tmh3">Measure by measure</h3>' +
    (det === null
      ? '<p class="mute">' +
        '<button class="btn" id="tmload">Show each measure</button></p>'
      : det.error
        ? msg("warn", det.reason || det.error)
        : tmMeasures(det)) +
    '</div>';
}

function tmMeasures(d){
  var ms = d.measures || [];
  if (!ms.length) return '<div class="empty">Nothing is assigned to them this month.</div>';
  return '<div class="scroll"><table><thead><tr>' +
      '<th>Measure</th><th>Target</th><th>Where they are</th><th></th>' +
    '</tr></thead><tbody>' + ms.map(function(m){
      return '<tr><td><b>' + esc(m.name) + '</b>' +
          '<div class="mute">' + esc(pfUnit(m.unit)) + '</div></td>' +
        '<td>' + (m.target === null || m.target === undefined
          ? '<span class="mute">none</span>' : pfNum(m.target)) + '</td>' +
        '<td>' + (m.value === null || m.value === undefined
          ? '<span class="mute">nothing filed</span>' : pfNum(m.value)) + '</td>' +
        '<td style="min-width:150px">' + pfMeter(m.value, m.target, m.direction) + '</td></tr>';
    }).join("") + '</tbody></table></div>';
}


/* ------------------------------------- warnings, and the plan if there is one
   Two different shapes, drawn differently on purpose. A warning is a
   dated line that never changes. A plan is a live thing with reviews
   that are either held or overdue, and the overdue ones are the whole
   point of booking them as rows.                                       */
function tmConduct(){
  var c = TM.conductFor === TM.sel ? TM.conduct : null;
  if (!c) {
    return '<p class="tmsoon"><button class="btn" id="tmconduct">' +
      'Warnings and improvement plan</button></p>';
  }
  if (c.error) return msg("warn", c.reason || c.error);

  var ws = c.warnings || [];
  var warn = !ws.length
    ? '<p class="mute">No warning has been issued.</p>'
    : '<ul class="tmwarn">' + ws.map(function(w){
        return '<li><span class="tmlvl ' + esc((w.level||"").toLowerCase()) + '">' +
          esc(w.level) + '</span> <b>' + esc(w.subject) + '</b>' +
          '<div class="mute">' + esc((w.issuedAt||"").slice(0,10)) +
          ' &middot; ' + esc(w.issuedBy || "") + '</div>' +
          (w.detail ? '<div>' + esc(w.detail) + '</div>' : '') + '</li>';
      }).join("") + '</ul>';

  var p = c.plan;
  var plan;
  if (!p) {
    plan = '<p class="mute">Not on an improvement plan.</p>';
  } else {
    var rs = p.reviews || [];
    var due = rs.filter(function(r){ return r.overdue; }).length;
    var held = rs.filter(function(r){ return r.heldAt; }).length;
    plan = '<div class="tmplan">' +
      '<div class="tmplanh"><b>' + esc(p.state) + '</b> ' +
        '<span class="mute">' + esc(p.startsOn) + ' to ' + esc(p.endsOn) + '</span>' +
        (due ? ' <span class="tmover">' + due + ' review' +
               (due === 1 ? '' : 's') + ' overdue</span>' : '') +
      '</div>' +
      '<p><b>Concern.</b> ' + esc(p.concern) + '</p>' +
      '<p><b>What improvement looks like.</b> ' + esc(p.expectation) + '</p>' +
      (p.support ? '<p><b>Support.</b> ' + esc(p.support) + '</p>' : '') +
      (p.outcome ? '<p><b>Outcome.</b> ' + esc(p.outcome) + '</p>' : '') +
      '<div class="scroll"><table><thead><tr>' +
        '<th>#</th><th>Due</th><th>Held</th><th>Judgement</th><th></th>' +
      '</tr></thead><tbody>' + rs.map(function(r){
        return '<tr' + (r.overdue ? ' class="tmoverrow"' : '') + '>' +
          '<td>' + esc(r.seq) + '</td>' +
          '<td>' + esc(r.dueOn) + (r.overdue ? ' <span class="tmover">overdue</span>' : '') + '</td>' +
          '<td>' + (r.heldAt ? esc(r.heldAt.slice(0,10)) : '<span class="mute">not yet</span>') + '</td>' +
          '<td>' + (r.judgement ? esc(r.judgement.replace(/_/g," ").toLowerCase()) : '') +
            (r.note ? '<div class="mute">' + esc(r.note) + '</div>' : '') + '</td>' +
          '<td class="plact">' + (!r.heldAt && c.mayAct
            ? '<button class="btn" data-tmhold="' + esc(r.id) + '">Hold it</button>' : '') +
          '</td></tr>';
      }).join("") + '</tbody></table></div>' +
      (c.mayAct && (p.state === "OPEN" || p.state === "EXTENDED")
        ? '<p><button class="btn" data-tmform="close">Close the plan</button> ' +
          '<span class="mute">' + held + ' of ' + rs.length + ' reviews held.</span></p>'
        : '') +
      '</div>';
  }

  return '<h3 class="tmh3">Warnings</h3>' + warn +
         '<h3 class="tmh3">Improvement plan</h3>' + plan +
         (TM.form ? tmForm() : '');
}

/* One form, three shapes. Each field is what the database will refuse
   without, so the refusal happens here where it costs nothing.        */
function tmForm(){
  var f = TM.form;
  if (f === "warn") {
    return '<div class="tmfm"><h4>Issue a warning</h4>' +
      '<p><label>Level <select id="tmwlevel">' +
        '<option value="VERBAL">Verbal</option>' +
        '<option value="WRITTEN" selected>Written</option>' +
        '<option value="FINAL">Final</option></select></label></p>' +
      '<p><label>What it is about<br><input id="tmwsub" class="pfin" ' +
        'style="width:100%" placeholder="Numbers not filed for six working days"></label></p>' +
      '<p><label>Detail<br><textarea id="tmwdet" rows="3" style="width:100%"></textarea></label></p>' +
      '<p><button class="btn primary" id="tmwsave">Issue it</button> ' +
      '<button class="btn" id="tmfcancel">Cancel</button> ' +
      '<span class="mute">A warning is never edited afterwards.</span></p></div>';
  }
  if (f === "pip") {
    return '<div class="tmfm"><h4>Open an improvement plan</h4>' +
      '<p><label>The concern<br><textarea id="tmpcon" rows="2" style="width:100%" ' +
        'placeholder="Cases completed has been under half of target for two months"></textarea></label></p>' +
      '<p><label>What improvement looks like<br><textarea id="tmpexp" rows="2" ' +
        'style="width:100%" placeholder="At or above 90% of the monthly target for two consecutive months"></textarea></label></p>' +
      '<p><label>Support offered<br><textarea id="tmpsup" rows="2" style="width:100%"></textarea></label></p>' +
      '<p><label>Ends on <input id="tmpend" type="date"></label> ' +
      '<label>Review every <input id="tmpev" class="pfin" type="number" value="14" ' +
        'style="width:70px"> days</label></p>' +
      '<p><button class="btn primary" id="tmpsave">Open it</button> ' +
      '<button class="btn" id="tmfcancel">Cancel</button> ' +
      '<span class="mute">The reviews are booked now, not remembered later.</span></p></div>';
  }
  if (f === "close") {
    return '<div class="tmfm"><h4>Close the plan</h4>' +
      '<p><label>Outcome <select id="tmcst">' +
        '<option value="MET">Met</option>' +
        '<option value="NOT_MET">Not met</option>' +
        '<option value="EXTENDED">Extended</option>' +
        '<option value="WITHDRAWN">Withdrawn</option></select></label></p>' +
      '<p><label>Why<br><textarea id="tmcnote" rows="3" style="width:100%"></textarea></label></p>' +
      '<p><button class="btn primary" id="tmcsave">Close it</button> ' +
      '<button class="btn" id="tmfcancel">Cancel</button> ' +
      '<span class="mute">Met or not met needs a reason.</span></p></div>';
  }
  if (f && f.indexOf("hold:") === 0) {
    return '<div class="tmfm"><h4>Hold this review</h4>' +
      '<p><label>How it is going <select id="tmhj">' +
        '<option value="ON_TRACK">On track</option>' +
        '<option value="AT_RISK">At risk</option>' +
        '<option value="OFF_TRACK">Off track</option></select></label></p>' +
      '<p><label>Note<br><textarea id="tmhnote" rows="3" style="width:100%"></textarea></label></p>' +
      '<p><button class="btn primary" id="tmhsave">Record it</button> ' +
      '<button class="btn" id="tmfcancel">Cancel</button></p></div>';
  }
  return "";
}

/* ------------------------------------------------------------- wiring */
function tmWire(){
  /* ------------------------------------------------- the chart / the list */
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmview]"), function(b){
    b.onclick = function(){
      TM.view = b.getAttribute("data-tmview");
      TM.tedit = null;
      tmRender();
    };
  });

  /* Typing re-draws the table, which replaces the box being typed into, so
     the caret has to be put back where it was. Without this the field
     loses focus after the first letter and the search is unusable. */
  var box = el("tmfind");
  if (box) box.oninput = function(){
    var at = box.selectionStart;
    TM.tq = box.value;
    TM.tedit = null;
    tmRender();
    var again = el("tmfind");
    if (!again) return;
    again.focus();
    try { again.setSelectionRange(at, at); } catch (e) { /* older browsers */ }
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmgap]"), function(b){
    b.onclick = function(){
      TM.tonly = b.getAttribute("data-tmgap");
      TM.tedit = null;
      tmRender();
    };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmsort]"), function(b){
    b.onclick = function(){ TM.tsort = b.getAttribute("data-tmsort"); tmRender(); };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmrep]"), function(b){
    b.onclick = function(){ TM.tedit = b.getAttribute("data-tmrep"); tmRender(); };
  });
  if (el("tmrepno")) el("tmrepno").onclick = function(){ TM.tedit = null; tmRender(); };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmrepgo]"), function(b){
    b.onclick = async function(){
      var id = b.getAttribute("data-tmrepgo");
      var to = el("tmrepsel") ? el("tmrepsel").value : "";
      TM.tedit = null;
      /* An empty value is "nobody", which is a real answer and not a
         missing one -- org_move_person takes a null manager and allows it
         for exactly the two people who can see this list. */
      await tmMove(id, to || null);
    };
  });

  if (el("tmexp")) el("tmexp").onclick = function(){ TM.shut = {}; tmRender(); };
  if (el("tmcol")) el("tmcol").onclick = function(){
    TM.shut = {};
    (TM.tree.people || []).forEach(function(p){
      if (p.depth > 0 || p.reports) TM.shut[p.personId] = true; });
    tmRender();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmtog]"), function(b){
    b.onclick = function(e){
      e.stopPropagation();
      var id = b.getAttribute("data-tmtog");
      if (TM.shut[id]) delete TM.shut[id]; else TM.shut[id] = true;
      tmRender();
    };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tm]"), function(c){
    var id = c.getAttribute("data-tm");

    c.onclick = function(){
      TM.sel = TM.sel === id ? null : id;
      TM.detail = null; TM.detailFor = null;
      /* Somebody else's warnings must not stay on screen under this
         person's name, and a half-typed form must not follow them. */
      TM.conduct = null; TM.conductFor = null; TM.form = null;
      /* Two panels arguing over the screen is one too many: picking a
         person puts that person's panel up, and the + panel away. */
      TM.addTo = null; TM.addOpts = null; TM.addErr = null; TM.qForm = null;
      tmRender();
    };

    /* A drag is only armed where the server said mayMove. The drop is
       still checked again by org_move_person -- this only stops the
       gesture being offered where it would certainly be refused. */
    c.ondragstart = function(e){
      TM.drag = id;
      try { e.dataTransfer.setData("text/plain", id); } catch (err) {}
      e.dataTransfer.effectAllowed = "move";
      c.classList.add("dragging");
    };
    c.ondragend = function(){ TM.drag = null; TM.over = null; tmRender(); };

    c.ondragover = function(e){
      if (!TM.drag || TM.drag === id) return;
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";
      if (TM.over !== id) { TM.over = id; c.classList.add("over"); }
    };
    c.ondragleave = function(){ if (TM.over === id) { TM.over = null; c.classList.remove("over"); } };

    c.ondrop = async function(e){
      e.preventDefault();
      var moved = TM.drag; TM.drag = null; TM.over = null;
      if (!moved || moved === id) { tmRender(); return; }
      await tmMove(moved, id);
    };
  });

  /* ------------------------------------ warnings and the improvement plan */
  async function tmConductLoad(){
    TM.conductFor = TM.sel;
    TM.conduct = await perfApi("/perf/conduct?person=" + encodeURIComponent(TM.sel));
    tmRender();
  }

  if (el("tmconduct")) el("tmconduct").onclick = function(){
    el("tmconduct").disabled = true; tmConductLoad();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmform]"), function(b){
    b.onclick = function(){
      TM.form = b.getAttribute("data-tmform");
      /* Opening a form needs the panel underneath it, so the conduct is
         loaded first if it has not been. */
      if (TM.conductFor !== TM.sel) tmConductLoad(); else tmRender();
    };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmhold]"), function(b){
    b.onclick = function(){ TM.form = "hold:" + b.getAttribute("data-tmhold"); tmRender(); };
  });

  if (el("tmfcancel")) el("tmfcancel").onclick = function(){ TM.form = null; tmRender(); };

  /* -------------------------------------------------------- the + */
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmadd]"), function(b){
    b.onclick = async function(e){
      /* The + lives inside a card that is itself clickable and draggable,
         so the click must stop here or opening the + also selects the
         person and the two panels argue over the screen. */
      e.stopPropagation();
      var id = b.getAttribute("data-tmadd");
      TM.addTo = id; TM.addOpts = null; TM.addErr = null;
      TM.qForm = null; TM.addTab = "move";
      tmRender();
      TM.addOpts = await perfApi("/perf/team/add?under=" + encodeURIComponent(id));
      /* Open on the tab that has something in it. Landing on an empty
         picker when the real answer is "ask HR" wastes a click every
         time, which is most times on a small team. */
      if (TM.addOpts && !TM.addOpts.error &&
          !(TM.addOpts.movable || []).length) TM.addTab = "new";
      tmRender();
    };
  });

  if (el("tmaclose")) el("tmaclose").onclick = function(){
    TM.addTo = null; TM.addOpts = null; TM.addErr = null; TM.qForm = null;
    tmRender();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmatab]"), function(b){
    b.onclick = function(){
      TM.addTab = b.getAttribute("data-tmatab"); TM.addErr = null; tmRender();
    };
  });

  async function tmAddReload(){
    TM.addOpts = await perfApi("/perf/team/add?under=" + encodeURIComponent(TM.addTo));
    TM.tree = await perfApi("/perf/team/tree");
    tmRender();
  }

  if (el("tmamovego")) el("tmamovego").onclick = async function(){
    var who = el("tmamove").value;
    var under = TM.addTo;
    if (!who || !under) return;
    /* The panel is closed before the move rather than after it, because
       the list it is showing is about to be wrong -- the person just
       moved out of it. */
    TM.addTo = null; TM.addOpts = null;
    await tmMove(who, under);
  };

  if (el("tmaask")) el("tmaask").onclick = async function(){
    if (TM.busy) return;
    TM.busy = true; TM.addErr = null;
    var o = await perfApi("/perf/team/request", { method:"POST", body:{
      fullName: el("tmaname").value,
      workEmail: el("tmamail").value,
      chairId: el("tmachair") ? el("tmachair").value : null,
      employeeType: el("tmatype").value,
      managerId: TM.addTo } });
    TM.busy = false;
    if (o && o.error) { TM.addErr = o; tmRender(); return; }
    TM.says = msg("good", (o && o.note) || "Sent to HR.");
    await tmAddReload();
  };

  /* -------------------------------------------- HR decides an ask */
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmqok]"), function(b){
    b.onclick = function(){
      TM.qForm = "ok:" + b.getAttribute("data-tmqok"); TM.addErr = null; tmRender();
    };
  });
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmqno]"), function(b){
    b.onclick = function(){
      TM.qForm = "no:" + b.getAttribute("data-tmqno"); TM.addErr = null; tmRender();
    };
  });
  if (el("tmqcancel")) el("tmqcancel").onclick = function(){ TM.qForm = null; tmRender(); };

  async function tmDecide(id, decision, fields){
    if (TM.busy) return;
    TM.busy = true; TM.addErr = null;
    var o = await perfApi("/perf/team/request/decide", { method:"POST", body:{
      requestId: id, decision: decision, fields: fields } });
    TM.busy = false;
    if (o && o.error) { TM.addErr = o; tmRender(); return; }
    TM.says = msg("good", (o && o.note) || "Done.");
    TM.qForm = null;
    await tmAddReload();
  }

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmqgo]"), function(b){
    b.onclick = function(){
      tmDecide(b.getAttribute("data-tmqgo"), "APPROVE", {
        employeeNo: el("tmqno").value, mobile: el("tmqmob").value,
        department: el("tmqdept").value, joinedOn: el("tmqjoin").value || null,
        appRole: el("tmqrole").value });
    };
  });
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmqnogo]"), function(b){
    b.onclick = function(){
      tmDecide(b.getAttribute("data-tmqnogo"), "REJECT", { reason: el("tmqwhy").value });
    };
  });

  async function tmSend(path, body, good){
    if (TM.busy) return;
    TM.busy = true;
    var o = await perfApi(path, { method:"POST", body: body });
    TM.busy = false;
    if (o && o.error) { TM.says = msg("bad", o.reason || o.error); tmRender(); return; }
    TM.says = msg("good", (o && o.note) || good);
    TM.form = null;
    await tmConductLoad();
    /* A warning or a plan does not change a number, but the tile's own
       counts come from the same call, so the tree is refreshed too. */
    TM.tree = await perfApi("/perf/team/tree");
    tmRender();
  }

  if (el("tmwsave")) el("tmwsave").onclick = function(){
    tmSend("/perf/warn", { personId: TM.sel,
      level: el("tmwlevel").value, subject: el("tmwsub").value,
      detail: el("tmwdet").value, aboutKind: "CONDUCT" }, "Issued.");
  };

  if (el("tmpsave")) el("tmpsave").onclick = function(){
    tmSend("/perf/pip", { personId: TM.sel,
      concern: el("tmpcon").value, expectation: el("tmpexp").value,
      support: el("tmpsup").value,
      endsOn: el("tmpend").value || null,
      reviewEveryDays: el("tmpev").value || 14 }, "Opened.");
  };

  if (el("tmcsave")) el("tmcsave").onclick = function(){
    var p = TM.conduct && TM.conduct.plan;
    if (!p) return;
    tmSend("/perf/pip/close", { planId: p.id,
      state: el("tmcst").value, note: el("tmcnote").value }, "Closed.");
  };

  if (el("tmhsave")) el("tmhsave").onclick = function(){
    tmSend("/perf/pip/review", { reviewId: TM.form.slice(5),
      judgement: el("tmhj").value, note: el("tmhnote").value }, "Recorded.");
  };

  if (el("tmload")) el("tmload").onclick = async function(){
    el("tmload").disabled = true;
    TM.detailFor = TM.sel;
    TM.detail = await perfApi("/perf/org?cycle=" + encodeURIComponent(TM.tree.cycleId) +
                              "&person=" + encodeURIComponent(TM.sel));
    tmRender();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-tmgo]"), function(b){
    b.onclick = function(){
      var where = b.getAttribute("data-tmgo");
      /* These live on Performance & appraisal and on the scheme screen.
         Sending somebody there is honest; rebuilding them here would be a
         second implementation of a thing that already works.

         The PERSON goes with them. This used to send a bare "#plb", which
         is the manager's OWN bonus screen -- so pressing "Monthly review
         and score" on somebody's tile opened your own sheet, with your own
         self-evaluation box on it. Read from that tile, the tool appeared
         to be asking a manager to self-evaluate their report. Nothing was
         ever written that way, because plb_self_eval only writes against
         the signed-in person's own sheet; the damage was entirely to what
         the screen appeared to be asking for.

         Both destinations read the id back off the hash and open on that
         person, the same way #cases/<id> and #ogl/<id> already work. */
      location.hash = (where === "quarter" || where === "score")
        ? "#plb/" + TM.sel : "#perf/" + TM.sel;
      if (typeof route === "function") route();
    };
  });
}

async function tmMove(personId, managerId){
  if (TM.busy) return;
  TM.busy = true;
  TM.says = msg("info", "Moving&hellip;");
  tmRender();

  var o = await perfApi("/perf/team/move",
    { method:"POST", body:{ personId: personId, managerId: managerId } });
  TM.busy = false;

  if (o && o.error) {
    /* would_loop is not a fault the person made -- it is the tool
       refusing to turn the reporting line into a ring. It reads as an
       explanation, not as an error. */
    TM.says = msg(o.error === "would_loop" ? "warn" : "bad",
      o.reason || o.error);
    tmRender();
    return;
  }

  TM.says = msg("good", (o && o.note) || "Moved.");
  /* Both drawings are now wrong, and only one of them is on screen. They
     are both re-read anyway: the commonest use of the list is several
     moves in a row, and a chart that silently kept the old line until the
     next visit is how somebody comes to believe a move did not take. */
  TM.tree = await perfApi("/perf/team/tree");
  if (tmMayList()) TM.tbl = await perfApi("/perf/team/people");
  tmRender();
}
