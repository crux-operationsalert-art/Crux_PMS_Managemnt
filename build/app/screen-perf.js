/* ================================================================== perf
   The monthly cycle: what I am measured on, what I owe today, and — if
   anybody reports to me — what my team is doing about theirs.

   One screen, two faces, because they are the same thing seen from either
   end. A branch manager files their own numbers AND sets their team's; a
   field executive only ever does the first. The second face appears when
   the database says somebody reports to you, not when a role says you are
   a manager — those are different questions and only one of them is true
   about a particular Tuesday.

   Nothing here computes a number. Every value on this screen comes from
   perf_value() through perf_tree(), which owns the one rule that makes a
   roll-up correct: counts and rupees accumulate, a percentage or a score
   is a level. A second opinion about somebody's performance is the last
   thing a screen should hold.                                          */
var PF = { period:null, cycle:null, tab:"mine", tree:null, due:null, team:null,
           who:null, open:{}, measures:null, measuresFor:null, form:null,
           sel:{}, busy:false, says:"",
           /* everybody an administrator or HR may set for but who does not
              report to them, and the text typed to find one. Drawn only
              once `find` is two characters or more. */
           /* the reporting line, split: `team` is whose targets are mine to
              set, `watch` is the rest of the line -- people I can see and
              may not set for. */
           watch:[], watchOpen:false,
           wider:[], widerWhy:"", find:"",
           /* the open "change this measure" form, which is a different
              thing from `form` -- that one gives a measure, this one
              changes one already given. */
           editForm:null,
           /* the person named in the hash on the way in, remembered so a
              later re-render does not drag the view back there. */
           cameFor:null,
           /* the blueprint's other sections: the split, the fortnight, the
              tasks, the quarter, and the forms that write to them. */
           weighting:{}, filed:null, tasks:{}, plb:{}, score:null,
           org:null, tgt:null, tgtFor:null, hand:null, month:null, handOpen:{},
           split:null, splitFor:null,
           taskForm:null, weightForm:null, elig:false,
           /* the open "reopen this month for setting KPIs" form, which only
              HR, Business Excellence and an administrator ever see. */
           reopen:null };

function pfMonth(d){ d = d || new Date();
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1)).toISOString().slice(0,10); }

function pfMonthName(s){
  var d = new Date(s + "T00:00:00Z");
  return d.toLocaleString("en-GB", { month:"long", year:"numeric", timeZone:"UTC" });
}

/* The registry codes a measure's FAMILY after a middle dot in its unit --
   "% of working days filed · EX2". The roll-up engine reads that code; a
   person reading their own target must never see it. It is bookkeeping,
   and showing it makes the target look like a machine error.

   Stripped in one place so no caller can forget. */
function pfUnit(u){
  if (!u) return "";
  var i = u.lastIndexOf("·");
  return (i < 0 ? u : u.slice(0, i)).trim();
}

function pfNum(v, unit){
  if (v === null || v === undefined || v === "") return "—";
  var n = Number(v);
  if (!isFinite(n)) return esc(v);
  var s = Math.abs(n) >= 1000 ? n.toLocaleString("en-IN") : String(Math.round(n * 100) / 100);
  return esc(s) + (unit ? ' <span class="mute">' + esc(pfUnit(unit)) + '</span>' : '');
}

/* A bar is a claim about proportion, so it stops at 100 even when the
   number does not -- and the figure beside it still says 143%. */
function pfBar(pct){
  if (pct === null || pct === undefined) return '';
  var w = Math.max(0, Math.min(100, Number(pct)));
  var tone = pct >= 95 ? "ok" : pct >= 75 ? "warn" : "bad";
  return '<div class="pfbar"><i class="' + tone + '" style="width:' + w + '%"></i></div>';
}

/* A screen is published from one place and its service is deployed from
   another, and the two do not always land in the same minute. When the
   routes are not there yet the gateway answers no_route, and this screen
   says that rather than inventing a reason of its own -- "the period has
   not been opened" would send somebody looking for HR about a deploy. */
function pfMissing(r){
  return !!r && (r.error === "no_route" || r._status === 404);
}

/* --------------------------------------------------------------- the shell
   ONE screen, in the blueprint's order. Crux App v2 renders Performance from
   two sections -- isPms and isAppraisal -- and sets isAppraisal:true inside
   the same `route === 'pms'` branch, so the appraisal is a section on this
   page and not a destination. The tool had three pages instead (This month /
   Appraisal / Bonus), two of them titled "Performance", because the same
   screen was built three times in three passes. This is them joined up.

   A to K below are the blueprint's own sections, in its own sequence. Where
   a section has no data path yet it renders with an honest empty state that
   says what is missing: a control that is absent and a control that says
   "nothing yet" are different failures, and only the first is ours.        */
async function vPerf(){
  if (!PF.period) PF.period = pfMonth();
  var c = await plb("/plb/perf/cycle?period=" + PF.period);
  if (pfMissing(c)) {
    el("view").innerHTML = '<h1>Performance &amp; appraisal</h1>' +
      msg("warn", "This screen is published but the service behind it is not " +
        "deployed yet, so there is nothing to show. Nothing is wrong with your " +
        "account and nothing has been lost.");
    return;
  }
  PF.cycle = c.cycle || null;
  PF.mayOpen = !!c.mayOpen;
  if (!PF.team) {
    var t = await plb("/plb/perf/team");
    /* The route returns the WHOLE line -- every depth -- and marks only
       depth 1 as maySet. For Arun Bodupali that is 101 people of whom 2 are
       his to set, and the card used to list all 101 with an identical "Set
       targets" button on every row. He reported that he could not find how
       to set Manish's targets; Manish was row one of a hundred and one, and
       nothing on the row said it was different from the other hundred.

       So the line is split here, once, and the two halves are drawn as two
       different things: the people whose targets are yours, and the people
       whose numbers you can only watch. */
    var line = t.error ? [] : (t.people || []);
    PF.team  = line.filter(function(p){ return p.maySet; });
    PF.watch = line.filter(function(p){ return !p.maySet; });

    /* An administrator and Human Resources may set for everybody. That is a
       hundred rows, and a hundred rows under the heading "my team" is what
       made the tool look as though it were leaking other people's data. So
       the wider list is held here and never drawn until somebody types a
       name into the box that asks for one. */
    PF.wider  = t.error ? [] : (t.wider || []);
    PF.widerWhy = t.error ? "" : (t.why || "");
  }

  /* #perf/<personId> -- arrived from that person's tile under My team,
     meaning to set THEIR targets. Open them rather than leaving the
     visitor to find the name again in a list. Only honoured for somebody
     this caller may actually set for: the tree call behind it refuses
     anyone else, and opening a panel that will refuse is worse than not
     opening one.

     Read once, on the first draw. After that the person is whoever the
     screen's own buttons last chose, so a later re-render does not drag
     the view back to where the visitor came in. */
  var want = (location.hash || "").split("/")[1];
  if (want && !PF.cameFor) {
    PF.cameFor = want;
    var known = (PF.team || []).concat(PF.wider || []).filter(function(p){
      return p.personId === want && p.maySet; })[0];
    if (known) { PF.who = want; PF.whoTree = null; }
  }
  /* The month, the quarter and the split are three different clocks and the
     page shows all three. Asked together because they are drawn together —
     a chip that arrives after the table it belongs to reads as a bug.     */
  var side = await Promise.all([
    perfApi("/perf/weighting"),
    perfApi("/perf/task/mine?period=" + PF.period.slice(0,7)),
    plb("/plb/mine")
  ]);
  PF.weighting = side[0] || {};
  PF.tasks     = side[1] || {};
  PF.plb       = side[2] || {};
  await pfQLoad();
  await pfLoadMine();
  pfRender();
}

/* --------------------------------------- the quarter, on THIS page

   "FOrmat/UI/UX of monthly score card is good and easy to understand, so
    use the same for [the quarterly] too but should be linked with the
    quaterly."  --  and then, later:  "changing the UI/UX of monthly target
    similar to quaterly score card is still pending or I am not able to
    find it".

   Both sentences were true at once, and that is the whole lesson. The
   monthly-shaped quarterly card WAS built, and it was built on the other
   screen -- vPlb, which the navigation calls "Running the scheme". This
   page drew the quarter with pbGoalSheet, the old table, and nobody
   looking at Performance & appraisal ever saw the rebuild.

   So it is loaded and drawn here, from the same endpoints, and "Running
   the scheme" is left to the one job that really is about running it. */
async function pfQLoad(){
  var s = (PF.plb || {}).sheet;
  PF.qmonths = s && s.id ? await plb("/plb/kpi/months?sheet=" + encodeURIComponent(s.id)) : null;
  if (PF.qmonths && PF.qmonths.error) PF.qmonths = null;
  PF.qopts = null;          /* fetched only when the editor is opened */
  PF.qedit = false;
  PF.qparts = null;         /* which measure's breakdown is open      */
}

async function pfLoadMine(){
  if (!PF.cycle) { PF.tree = null; PF.due = null; PF.history = null; return; }
  var r = await Promise.all([
    plb("/plb/perf/tree?cycle=" + PF.cycle.id),
    plb("/plb/perf/due"),
    plb("/plb/perf/score?cycle=" + PF.cycle.id),
    perfApi("/perf/filed?days=14"),
    /* My own measures with everything below me already added in. The
       same call the Org end reads, asked about myself. */
    perfApi("/perf/org?cycle=" + PF.cycle.id),
    /* What the people under me filed against measures that are not mine
       and so cannot climb -- the step a person has to take by reading. */
    perfApi("/perf/handover?cycle=" + PF.cycle.id),
    /* This month out of ten, read out of the same filings. A suggestion
       only: it writes nothing, so it is safe to ask for on every load. */
    perfApi("/perf/month?on=" + PF.period),
  ]);
  PF.tree = r[0]; PF.due = (r[1] || {}).due || []; PF.score = r[2] || null;
  PF.filed = r[3] || null; PF.org = r[4] || null;
  PF.hand = r[5] || null; PF.month = r[6] || null;
}

function pfRender(){
  var head = '<div class="page-head"><div><h1>Performance &amp; appraisal</h1>' +
    '<p class="mute">Two layers, and they are not the same number. The month ' +
    'decides how much of what you earned is released; the quarter decides how ' +
    'much you earned.</p></div>' +
    '<div class="pfperiod">' + pfPeriodPicker() + '</div></div>';

  if (!PF.cycle) {
    el("view").innerHTML = head +
      '<div class="card"><h2>' + esc(pfMonthName(PF.period)) + ' has not been opened</h2>' +
      '<p class="mute">A period has to be opened before anybody can be given a KPI for it. ' +
      'Opening it sets two dates: the last day a manager may set targets, and the last day ' +
      'numbers may still be filed.</p>' +
      (PF.mayOpen
        ? '<p><button class="btn primary" id="pfopen">Open ' + esc(pfMonthName(PF.period)) + '</button></p>'
        : '<div class="empty">HR, Business Excellence or an administrator opens a period.</div>') +
      '<div id="pfmsg">' + PF.says + '</div></div>';
    pfWire();
    return;
  }

  el("view").innerHTML = head + pfWindowBanner() +
    pfSetFor() +           /* A1 whose targets are mine, said at the top   */
    pfToday() +            /* A2 today, as the one headline               */
    pfChips() +            /* A  the three score chips                    */
    pfDaily() +            /* B+D the daily table, and one submission     */
    pfDayNote() +          /* C  anything else about today                */
    pfStreak() +           /* E  your last fourteen days                  */
    pfMyKpis() +           /* F  my KPIs                                  */
    pfAttributes() +       /* G  attributes                               */
    pfRequests() +         /* H  KPI change requests                      */
    pfHandover() +         /* H1 what came up from below, and stopped      */
    pfTargets() +          /* H2 the target, and who it divides across     */
    pfMonthCard() +        /* K1 the month, read out of the filings        */
    pfTeamSection() +      /* I  my team: targets, tasks and eligibility  */
    pfWeighting() +        /* J  the split, for Admin and HR              */
    pfAppraisal() +        /* K  appraisal, and the quarter behind it     */
    '<div id="pfmsg">' + PF.says + '</div>';
  pfWire();
}

function pfPeriodPicker(){
  var opts = "";
  for (var i = 0; i < 12; i++) {
    var d = new Date(); d.setUTCDate(1); d.setUTCMonth(d.getUTCMonth() - i);
    var v = pfMonth(d);
    opts += '<option value="' + v + '"' + (v === PF.period ? ' selected' : '') + '>' +
      esc(pfMonthName(v)) + '</option>';
  }
  return '<select id="pfperiod">' + opts + '</select>';
}

function pfWindowBanner(){
  var c = PF.cycle;
  var bits = [];
  bits.push(c.assign_open
    ? 'KPIs may be set until <b>' + day(c.assign_closes) + '</b>'
    : 'The window for setting KPIs closed on ' + day(c.assign_closes));
  bits.push(c.entry_open
    ? 'numbers may be filed until <b>' + day(c.entry_closes) + '</b>'
    : 'filing closed on ' + day(c.entry_closes));
  return '<div class="pfwin' + (c.entry_open ? '' : ' shut') + '">' +
    bits.join(' · ') +
    (pfMayExtend() && !pfSetWindowOpen()
      ? ' <button class="btn" id="pfreopen">Reopen it</button>' : '') +
    '</div>' +
    (PF.reopen ? pfReopenForm() : '');
}

/* ====================================================== the clock, and who it binds

   "set KPI is still not working and just like that most of the Buttons in
   PMS are not working."

   Measured rather than guessed: the published page was loaded in a browser,
   a manager signed in, and every control on this screen pressed. All of them
   are wired and all of them are clickable. What was failing was the SERVER,
   and the reason is the clock.

   perf_cycle_open sets assign_closes to five working days after the first of
   the month, and perf_assign, perf_assign_edit and perf_assign_remove all
   answer window_closed for anybody but an administrator after that. So for
   roughly three weeks in four, every KPI control on this screen was offered
   and every one of them refused.

   That is the defect migration 242 was written for, said about the clock
   instead of about the reporting line: a control that is always refused is
   worse than no control, because it tells somebody the tool does a thing it
   does not and they stop trusting the ones that work.

   So the question is asked once, here, in the same words the database asks
   it -- `current_date > assign_closes and the actor is not an administrator`
   -- and every KPI control reads the answer. */
function pfSetWindowOpen(){
  var c = PF.cycle;
  if (!c) return false;
  /* An administrator may still set after the window, and it is recorded.
     That is perf_assign's own exception, repeated here so the screen and
     the function agree rather than the screen guessing. */
  if (me && me.app_role === "ADMIN") return true;
  return c.assign_open !== false;
}

/* Said where the control was, not at the top of the page. Somebody looking
   for the button needs the answer where they are looking. */
function pfShutHere(what){
  var c = PF.cycle || {};
  return '<p class="pfshut"><b>' + esc(what) + ' is shut for ' +
    esc(pfMonthName(PF.period)) + '.</b> KPIs for this month had to be set by ' +
    esc(day(c.assign_closes)) + '. ' +
    (pfMayExtend()
      ? 'You can reopen the month at the top of this screen; it is recorded.'
      : 'HR, Business Excellence or an administrator can reopen the month.') +
    '</p>';
}

/* The three the scheme belongs to, in the same words perf_cycle_extend and
   perf_cycle_open both use. */
function pfMayExtend(){
  if (!me) return false;
  return me.app_role === "ADMIN" ||
         me.department === "Human Resources" ||
         me.department === "Business Excellence";
}

function pfReopenForm(){
  var c = PF.cycle || {};
  return '<div class="plform" id="pfreopenform">' +
    '<h4 class="plh">Reopen ' + esc(pfMonthName(PF.period)) + ' for setting KPIs</h4>' +
    '<div class="hragrid">' +
      '<label class="hrafield"><span>Set KPIs until</span>' +
        '<input id="pfreopenday" type="date" min="' + esc(pfToday0()) + '"' +
        ' max="' + esc(c.entry_closes || "") + '" value="' + esc(PF.reopen.until || "") + '"></label>' +
      '<label class="hrafield"><span>Why</span>' +
        '<input id="pfreopenwhy" placeholder="The team were still being given managers."' +
        ' value="' + esc(PF.reopen.why || "") + '"></label>' +
    '</div>' +
    '<p class="mute">Only ever later, and never past ' + esc(day(c.entry_closes)) +
    ' — a KPI first asked for after filing has closed is one nobody could meet. ' +
    'Who reopened it and why is recorded.</p>' +
    '<div class="plbar">' +
      '<button class="btn primary" id="pfreopensave">Reopen it</button>' +
      '<button class="btn" id="pfreopencancel">Cancel</button>' +
    '</div></div>';
}

function pfToday0(){
  var d = new Date();
  return d.getFullYear() + "-" +
    String(d.getMonth() + 1).padStart(2, "0") + "-" +
    String(d.getDate()).padStart(2, "0");
}

/* ---------------------------------------------------------- A · the chips
   KPIs, Attributes, Final. The weights are not typed in here: they come from
   pms_weighting through pms_weighting_for(), which also answers "the scheme
   has not started yet" — and on 29 September 2026 that is the true answer,
   because the Constitution takes effect on 1 October.                     */
function pfChips(){
  var w = PF.weighting.mine || {};
  var kpi = PF.score && PF.score.score !== undefined && PF.score.score !== null
    ? Number(PF.score.score) : null;
  var attr = null, fin = null;
  var m = pfThisMonthScore();
  if (m) { attr = m.attr; fin = m.final; if (m.kpi !== null && m.kpi !== undefined) kpi = m.kpi; }

  function chip(v, label, sub){
    return '<div class="pfchip"><div class="pfchipv">' +
      (v === null || v === undefined ? '—' : pfNum(v)) + '</div>' +
      '<div class="pfchipl">' + label + '</div>' +
      (sub ? '<div class="pfchips">' + sub + '</div>' : '') + '</div>';
  }
  var note = w.applies
    ? esc(w.note)
    : esc(w.note || "No split has been set, so no monthly score can be worked out.");

  return '<div class="card"><div class="pfchiprow">' +
    chip(kpi,  'KPIs',       w.applies ? esc(w.kpiPercent) + '%'  : '') +
    chip(attr, 'Attributes', w.applies ? esc(w.attrPercent) + '%' : '') +
    chip(fin,  'Final',      'out of 10') +
    '</div><p class="mute">' + note +
    (w.applies && w.scope && w.scope !== 'everybody'
      ? ' This split is set for ' + esc(w.scope) + '.' : '') +
    '</p></div>';
}

/* The month's scored row, if there is one. Empty until a manager scores it,
   which is the design: a score nobody has given is not a zero.            */
function pfThisMonthScore(){
  var s = (PF.plb || {}).sheet;
  if (!s || !s.months) return null;
  var want = PF.period.slice(0,7);
  for (var i = 0; i < s.months.length; i++) {
    var m = s.months[i];
    if (String(m.month || "").slice(0,7) === want) {
      return { kpi: m.kpiPoints, attr: m.attrPoints, final: m.monthlyScore };
    }
  }
  return null;
}

/* ------------------------------------------------- B and D · daily update
   The blueprint's table is five columns — KPI, Monthly target, Achieved, %,
   Today's count — and ONE submission for the whole day rather than a button
   per row. The tool had two columns and a button each, which turns filing a
   day into eleven separate acts.                                          */
function pfDaily(){
  var due = PF.due || [];
  var open = PF.cycle.entry_open;
  var byId = {};
  (function walk(list){
    (list || []).forEach(function(m){
      if (m.assignmentId) byId[m.assignmentId] = m;
      walk(m.parts);
    });
  })((PF.tree || {}).measures);

  if (!open) {
    return '<div class="card"><h2>Daily update</h2>' +
      '<div class="empty">Filing closed on ' + day(PF.cycle.entry_closes) +
      '. The month is still readable below.</div></div>';
  }
  if (!due.length) {
    return '<div class="card"><h2>Daily update</h2>' +
      '<p class="mute">Numbers against every KPI, then anything worth recording ' +
      'that is not a number.</p>' +
      '<div class="empty">Nothing is due from you today. What you file and when is ' +
      'set with your KPI, not by this screen.</div></div>';
  }

  var rows = due.map(function(d){
    var m = byId[d.assignmentId] || {};
    var pct = (m.pct === null || m.pct === undefined) ? '' : esc(m.pct) + '%';
    return '<tr>' +
      '<td><b>' + esc(d.name) + '</b>' +
        (d.split ? ' <span class="mute">' + esc(d.split) + '</span>' : '') +
        '<div class="mute">' +
          esc(String(d.cadence || "").toLowerCase().replace(/_/g, " ")) +
          (d.setBy ? ' · set by ' + esc(d.setBy) : '') +
        '</div></td>' +
      '<td>' + (d.target ? pfNum(d.target, d.unit) : '<span class="mute">no target</span>') + '</td>' +
      '<td>' + pfNum(m.value, m.unit) + '</td>' +
      '<td>' + pct + '</td>' +
      '<td><input class="pfin" data-pffile="' + esc(d.assignmentId) + '" type="number" step="any" ' +
        'placeholder="' + (d.alreadyFiled ? 'filed — change it' : 'today’s number') + '"></td>' +
      '</tr>';
  }).join("");

  return '<div class="card"><h2>Daily update</h2>' +
    '<p class="mute">Numbers against every KPI, then anything worth recording ' +
    'that is not a number. The number is for today: filing it tomorrow does not ' +
    'make it tomorrow’s number.</p>' +
    '<div class="scroll"><table><thead><tr>' +
      '<th>KPI</th><th>Monthly target</th><th>Achieved</th><th>%</th><th>Today’s count</th>' +
    '</tr></thead><tbody>' + rows + '</tbody></table></div>' +
    '<p><button class="btn primary" id="pfsubmitday">Submit daily update</button> ' +
    '<span class="mute">Everything you have filled in, in one go. Blank rows are left alone.</span></p>' +
    '</div>';
}

/* ------------------------------------------- C · anything else about today
   A note that counts towards Attributes. The blueprint has an assistant
   proposing which attribute it files under and under what heading, both
   overridable. There is nowhere to file it until a goal sheet exists — the
   attribute rows hang off the sheet — so this says that rather than offering
   a box whose contents would go nowhere.                                  */
function pfDayNote(){
  return '<div class="card"><h2>Anything else about today <span class="mute">· optional</span></h2>' +
    '<p class="mute">Cover you provided, a client remark, a problem you found, ' +
    'somebody who helped. The design files it as an Attribute with a heading, or ' +
    'keeps it as FYI, and it never scores you — your manager does, from these notes.</p>' +
    '<div class="empty">Not built, and not for want of a box. The only attribute ' +
    'writing this database has is the quarterly A-4 / A-5 proposal, which carries ' +
    'three milestones and an evidence reference — it is not a place to put a dated ' +
    'note. Nothing here holds one. Until something does, the record a manager scores ' +
    'A-3 from is the task list below, which is the same idea with a date and an owner ' +
    'on it.</div></div>';
}

/* ----------------------------------------- E · your last fourteen days
   A daily cadence you cannot see the record of is just a form.            */
function pfStreak(){
  var h = PF.filed || {};
  var days = h.days || [];
  if (!days.length) return "";
  var cells = days.map(function(d){
    var cls = d.filed ? ' on' : (d.working ? ' miss' : ' off');
    return '<div class="pfday' + cls + '" title="' + esc(d.day || '') +
      (d.working ? '' : ' · not a working day') + '">' +
      '<div class="pfdow">' + esc((d.dow || '').slice(0,1)) + '</div>' +
      '<div class="pfdd">' + esc(d.dd || '') + '</div></div>';
  }).join("");
  var run = Number(h.run || 0);
  return '<div class="card"><h2>Your last fourteen days</h2>' +
    '<div class="pfstreak">' + cells + '</div>' +
    '<p class="mute">' +
      (run > 0 ? '<b>' + run + ' in a row.</b> ' : '') +
      esc(h.filedDays || 0) + ' of ' + esc(h.workingDays || 0) + ' working days filed. ' +
      'A filled square is a day you filed; a hollow one is a working day you did not; ' +
      'a faded one is not a working day and cannot break a run. ' +
      'It counts days, not numbers — showing up is not the same as doing well.' +
    '</p></div>';
}

/* ------------------------------------------------------------ F · my KPIs */
function pfMyKpis(){
  var t = PF.tree || {};
  if (t.says) {
    return '<div class="card"><h2>My KPIs</h2><div class="empty">' + esc(t.says) + '</div></div>';
  }
  var measures = t.measures || [];
  var n = measures.length;
  return '<div class="card"><h2>My KPIs' +
      (n ? ' <span class="mute">· ' + n + ' set</span>' : '') + '</h2>' +
    '<p class="mute">Set by your manager from your chair’s published measure set — ' +
    'they choose nothing, and neither do you. Sub-categories show under each.</p>' +
    (measures.length
      ? '<div class="pftree">' + measures.map(function(m){ return pfNode(m, 0, false); }).join("") + '</div>'
      : '<div class="empty">Nothing has been set for you this period.</div>') +
    '<p class="mute">Five is the design: three mandatory, two optional. More than five ' +
    'and nobody remembers what they are being measured on.</p></div>';
}

/* --------------------------------------------------------- G · attributes */
function pfAttributes(){
  var s = (PF.plb || {}).sheet;
  if (!s || !(s.attributes || []).length) {
    return '<div class="card"><h2>Attributes <span class="mute">· everything beyond the KPIs</span></h2>' +
      '<p class="mute">Five slots worth two points each. Three are the same for everybody — ' +
      'process and control discipline, data and reporting hygiene, contribution beyond your ' +
      'own chair. The other two are yours to propose.</p>' +
      '<div class="empty">No goal sheet has been issued to you for this quarter, so the ' +
      'attribute slots do not exist yet.</div></div>';
  }
  var m = pfThisMonthScore();
  var rows = (s.attributes || []).map(function(a){
    return '<tr><td><b>' + esc(a.name) + '</b>' +
      (a.proposal ? '<div class="mute">' + esc(a.proposal) + '</div>' : '') +
      (a.evidence ? '<div class="mute">evidence: ' + esc(a.evidence) + '</div>' : '') + '</td>' +
      '<td>' + (a.fixed ? 'the same for everybody' : 'yours to propose') + '</td>' +
      '<td>2 points</td>' +
      '<td>' + esc(String(a.state || "—").toLowerCase()) + '</td></tr>';
  }).join("");
  return '<div class="card"><h2>Attributes <span class="mute">· everything beyond the KPIs</span></h2>' +
    '<div class="scroll"><table><thead><tr><th>Attribute</th><th>Who decides</th>' +
    '<th>Worth</th><th>State</th></tr></thead><tbody>' + rows + '</tbody></table></div>' +
    '<p class="mute">Each is worth two points of the ten. The score itself is monthly, not ' +
    'per attribute: ' +
    (m && m.attr !== null && m.attr !== undefined
      ? 'this month it is ' + pfNum(m.attr) + ' out of 10.'
      : 'this month has not been scored yet.') +
    ' Every point cites a specific record — never an opinion.</p></div>';
}

/* ------------------------------------------- H · KPI change requests
   The blueprint shows a queue with HR: who asked, for which KPI, from what
   to what, why, and the action. Nothing in this database answers to it —
   there is no request kind for a KPI change and no queue behind it. Saying
   so is the honest thing; a button here would go nowhere.                 */
function pfRequests(){
  return '<div class="card"><h2>KPI change requests</h2>' +
    '<div class="empty">Not built. The design has a queue here — who asked, which ' +
    'KPI, from what to what, why, and what HR did — and nothing in the database ' +
    'holds one yet. Until it does, a target change is raised the way the ' +
    'Constitution says: a Target Change Request before the quarter midpoint, ' +
    'through your Functional Head.</div></div>';
}

/* ------------------------------------------- how a number is doing
   One rule, used everywhere a number sits beside a target, so the screen
   never says "good" in one place and shows amber in another.

   A CEILING measure is met by being SMALL -- an error rate, an expense
   variance -- so the ratio is turned the right way up here rather than in
   each caller. Getting that wrong rewards a high error rate, which is the
   kind of mistake a performance system does not recover from.            */
function pfStand(value, target, direction){
  if (value === null || value === undefined || !target) return { k:"none", pct:null, say:"nothing filed yet" };
  var pct = direction === "CEILING"
    ? (Number(value) === 0 ? 150 : Math.round(1000 * target / value) / 10)
    : Math.round(1000 * value / target) / 10;
  if (pct >= 100) return { k:"good",  pct:pct, say:"at or past the target" };
  if (pct >= 50)  return { k:"part",  pct:pct, say:"part of the way" };
  return                 { k:"short", pct:pct, say:"short of half way" };
}

/* A thin bar and a word. Never the colour on its own: somebody reading
   this in greyscale, or not seeing red and green apart, gets the same
   answer from the text as everybody else does from the fill.            */
function pfMeter(value, target, direction){
  var st = pfStand(value, target, direction);
  if (st.k === "none") {
    return '<span class="pfmark none">not filed yet</span>';
  }
  var w = Math.max(2, Math.min(100, st.pct));
  return '<div class="pfbar"><i class="' + st.k + '" style="width:' + w + '%"></i></div>' +
    '<span class="pfmark ' + st.k + '"><s></s>' + esc(st.pct) + '% &middot; ' + esc(st.say) + '</span>';
}

/* The one large thing on the screen. A ring is not comparable down a
   column, which is exactly why there is only one: it answers a single
   question -- is today done -- and nothing else.                        */
function pfRingSvg(done, of, kind){
  var r = 38, c = 2 * Math.PI * r;
  var frac = of > 0 ? Math.min(1, done / of) : 0;
  return '<div class="pfring"><svg viewBox="0 0 92 92" aria-hidden="true">' +
    '<circle class="trk" cx="46" cy="46" r="' + r + '"></circle>' +
    '<circle class="arc" cx="46" cy="46" r="' + r + '" ' +
      'stroke="var(--' + kind + ')" ' +
      'stroke-dasharray="' + c.toFixed(1) + '" ' +
      'stroke-dashoffset="' + (c * (1 - frac)).toFixed(1) + '"></circle>' +
    '</svg><b>' + done + '<span style="font-size:13px;color:var(--mute)">/' + of + '</span></b></div>';
}

/* ------------------------------------------------ A2 · today, as a headline
   Above everything, because it is the only thing most people open this
   screen to do. Filed against due, the run of days behind it, and one
   sentence that is true rather than encouraging.                        */
function pfToday(){
  if (!PF.cycle) return "";
  var due = PF.due || [];
  if (!due.length && !(PF.filed && PF.filed.run)) return "";
  var done = due.filter(function(d){ return d.alreadyFiled; }).length;
  /* Nothing due is not a failure. A day with no measures on it reads
     green, because the person has nothing outstanding -- colouring it
     red would be the screen telling somebody off for a holiday. */
  var kind = done >= due.length ? "green" : done ? "gold" : "terra";
  var run  = (PF.filed && PF.filed.run) || 0;

  var say = !due.length
    ? "Nothing is due from you today."
    : done >= due.length
      ? "Today is done. Every measure has a number against it."
      : done
        ? (due.length - done) + " still to file. The org total moves the moment you do."
        : "Nothing filed yet today. Each number you file reaches your whole line at once.";

  return '<div class="card"><div class="pfhero">' +
    pfRingSvg(done, due.length, kind) +
    '<div class="pfheroT">' +
      '<h3>' + (done >= due.length && due.length ? "Today is filed" : "Today") + '</h3>' +
      '<p>' + esc(say) + '</p>' +
      (run > 0
        ? '<span class="pfrun">' + run + ' working day' + (run === 1 ? '' : 's') + ' in a row</span>'
        : '<span class="pfrun cold">no run going yet</span>') +
    '</div></div></div>';
}

/* --------------------------- H1 · what came up from below, and stopped
   Asked for: "if the managers or a layer or chair where the KPI changes
   there the chair must see the roll up and then update his own."

   A Branch Manager with forty-two executives is handed eighty-six
   numbers. Eighty-six rows is a wall, not a briefing, so this leads with
   one card per measure -- where the team stands, how many of them made
   it, the best and the worst -- and the per-person detail opens
   underneath only when somebody asks for it.                            */
function pfHandover(){
  var h = PF.hand;
  if (!h || h.error) return "";
  var sum = h.summary || [];
  var from = h.from || [];
  if (!sum.length && !from.length) return "";

  var cards = sum.map(function(m){
    var st = pfStand(m.team, m.target, m.direction);
    return '<div class="pfhcard">' +
      '<h4>' + esc(m.name) + '</h4>' +
      '<div class="u">' + esc(pfUnit(m.unit)) + '</div>' +
      '<p class="pfhbig">' + (m.team === null || m.team === undefined
          ? '<span class="mute" style="font-size:15px">nothing filed</span>'
          : pfNum(m.team) +
            '<em>' + (m.kind === "SUM" ? "team total" : "team average") + '</em>') + '</p>' +
      pfMeter(m.team, m.target, m.direction) +
      '<div class="pfspread">' +
        '<span><b>' + m.atOrAbove + '</b> of ' + m.people + ' met it</span>' +
        (m.best === null || m.best === undefined ? '' :
          '<span>best <b>' + pfNum(m.best) + '</b></span>') +
        (m.worst === null || m.worst === undefined ? '' :
          '<span>lowest <b>' + pfNum(m.worst) + '</b></span>') +
      '</div></div>';
  }).join("");

  var people = from.map(function(p){
    var open = PF.handOpen[p.personId];
    var rows = !open ? "" : '<tr><td colspan="2"><div class="scroll"><table>' +
      (p.measures || []).map(function(m){
        return '<tr><td><b>' + esc(m.name) + '</b>' +
          '<div class="mute">' + esc(pfUnit(m.unit)) + '</div></td>' +
          '<td>' + (m.value === null || m.value === undefined
            ? '<span class="mute">nothing filed</span>' : pfNum(m.value)) +
            '<div>' + pfMeter(m.value, m.target, m.direction) + '</div></td></tr>';
      }).join("") + '</table></div></td></tr>';
    return '<tr><td><b>' + esc(p.name) + '</b>' +
        '<div class="mute">' + esc(p.chair || "no chair") + ' &middot; ' +
        (p.measures || []).length + ' measure(s) stop here</div></td>' +
      '<td class="plact"><button class="btn" data-pfhand="' + esc(p.personId) + '">' +
        (open ? 'Hide' : 'Show theirs') + '</button></td></tr>' + rows;
  }).join("");

  return '<div class="card"><h2>What came up from below ' +
      '<span class="mute">&middot; and stops with them</span></h2>' +
    '<p class="mute">These measure something your own do not, so no arithmetic ' +
    'can add them into yours. Read them, then file your own number knowing ' +
    'them &mdash; that is the step the chart cannot take for you.</p>' +
    (cards ? '<div class="pfhand">' + cards + '</div>' : '') +
    (people ? '<div class="scroll"><table>' + people + '</table></div>' : '') +
    '</div>';
}

/* -------------------------------- K1 · the month, read out of the filings
   The Constitution gives each KPI two points -- 2.0 landed, 1.0 partly or
   late, 0.0 not -- and "partly or late" is a person's call about a
   person. So this shows what the numbers say, and its working, and
   writes nothing. A manager who disagrees is doing the job, not
   overriding the tool.

   Named pfMonthCard, not pfMonth: pfMonth() is already the helper that
   gives the first of a month, and a second declaration of that name would
   quietly win and turn PF.period into a lump of HTML.                    */
function pfMonthCard(){
  var m = PF.month;
  /* An unanswered call is not a score of nothing. call() hands back the
     body whatever the status was, so anything that is not recognisably a
     suggestion -- a 404 from a door that is not open yet, a refusal --
     shows nothing at all rather than an empty verdict. */
  if (!m || m.error || !m.measures) return "";
  var now = m.now || {};
  var rows = (m.measures || []).map(function(x){
    return '<li><span>' + esc(x.name) +
      (x.counted ? ' &middot; ' + esc(x.pct) + '%' : '') + '</span>' +
      '<b>' + (x.counted ? esc(x.points) + ' of 2' : esc(x.why || "not counted")) + '</b></li>';
  }).join("");

  return '<div class="card"><h2>This month, out of ten ' +
      '<span class="mute">&middot; what the filings say</span></h2>' +
    '<div class="pfmon">' +
      '<span class="n">' + (m.suggested === null || m.suggested === undefined
        ? '&mdash;' : esc(m.suggested)) + '</span>' +
      '<span class="of">suggested, out of 10</span>' +
      (now.kpiPoints === null || now.kpiPoints === undefined ? '' :
        '<span class="of">&middot; scored ' + esc(now.kpiPoints) + '</span>') +
    '</div>' +
    '<p class="mute" style="margin:7px 0 0">' + esc(m.says || "") + '</p>' +
    (rows ? '<ul class="pfwork">' + rows + '</ul>' : '') +
    '<p class="mute" style="margin:9px 0 0;font-size:12px">' + esc(m.note || "") + '</p>' +
    '</div>';
}

/* ------------------- H2 · the target, and who it divides across
   The other half of the daily flow. The numbers climb on their own; a
   target has to be given, and when it is given to me it divides across my
   team so nobody has to work out their share by hand.

   A count divides -- 600 cases across four people is 150 each. A
   percentage is copied -- 95% across four is 95 each, not 23.75. The
   screen says which of the two it is doing before it does it, because the
   difference between those two sentences is somebody's month.

   Anything typed by hand is pinned and the rest redivide around it. The
   screen marks a pinned share so a manager can see at a glance which of
   their team they have actually decided about.                          */
function pfTargets(){
  var o = PF.org;
  if (!o || o.error || !o.measures || !o.measures.length) return "";

  var rows = o.measures.map(function(m){
    var src = m.targetSource === "MANUAL" ? '<span class="pfpin">agreed</span>'
            : m.targetSource === "SHARED" ? '<span class="mute">a share from above</span>'
            : '<span class="pfseed">a starting number, nobody has agreed it</span>';
    var open = PF.tgtFor === m.assignmentId;
    return '<tr>' +
      '<td><b>' + esc(m.name) + '</b>' +
        '<div class="mute">' + esc(pfUnit(m.unit)) +
          (m.feeders ? ' · ' + m.feeders + ' below feed it' : ' · nothing feeds it') +
        '</div></td>' +
      '<td>' + (m.target === null || m.target === undefined
                 ? '<span class="mute">none</span>' : pfNum(m.target)) +
        '<div class="mute">' + src + '</div></td>' +
      '<td>' + (m.value === null || m.value === undefined
                 ? '<span class="mute">nothing filed</span>' : pfNum(m.value)) +
        (m.pct === null || m.pct === undefined ? '' :
          '<div class="mute">' + esc(m.pct) + '% of target</div>') + '</td>' +
      /* "Set and divide" was wrong on a person's OWN row: they may divide
         it, they may not set it. The verb now says which. */
      '<td class="plact">' + (m.feeders
        ? '<button class="btn" data-pftgt="' + esc(m.assignmentId) + '">' +
            (open ? 'Hide' : 'Divide across my team') + '</button>'
        : '<span class="mute">nobody to divide it across</span>') + '</td>' +
      '</tr>' +
      (open ? '<tr><td colspan="4">' + pfTargetPanel() + '</td></tr>' : '');
  }).join("");

  return '<div class="card"><h2>Targets <span class="mute">· mine, and my team&rsquo;s share of them</span></h2>' +
    '<p class="mute">A target set here divides across everybody whose measure climbs ' +
    'into it. A count is split; a percentage is carried down whole. A share you type ' +
    'yourself is kept, and the others divide what is left around it.</p>' +
    '<div class="scroll"><table><thead><tr>' +
      '<th>Measure</th><th>Target</th><th>Where it stands</th><th></th>' +
    '</tr></thead><tbody>' + rows + '</tbody></table></div></div>';
}

function pfTargetPanel(){
  var t = PF.tgt;
  if (!t) return '<p class="mute">Loading&hellip;</p>';
  if (t.error) return msg("warn", t.reason || t.error);

  /* Nobody sets their own target -- perf_may_set refuses rel 'self' for
     everybody, administrators included. The box used to be drawn anyway,
     so the screen invited an edit the server was always going to refuse
     and made it look as though a person could score themselves.

     What IS yours on your own measure is dividing it across your team,
     which is the rest of this panel. */
  var maySetThis = t.measure && (t.measure.rel === "manage" || t.measure.rel === "admin");

  var head = '<div class="pfsays">' + esc(t.note || "") + '</div>' +
    (maySetThis
      ? '<p><label>Set this measure to ' +
          '<input id="pftgtval" type="number" step="any" value="' +
            esc(t.measure && t.measure.target !== null ? t.measure.target : "") + '"></label> ' +
          '<button class="btn primary" id="pftgtsave">Set and divide</button></p>'
      : '<p class="mute">This target is your manager&rsquo;s to set, not yours. ' +
        'What is yours is how it divides across your team &mdash; below.</p>');

  /* A target divides DOWN to a team and ACROSS to the clients it is owed
     from, and those are two different divisions. This used to return here,
     before pfSplitBlock() -- so a measure with nobody below it offered
     neither, and the commonest case of wanting to split across banks is
     exactly a person with a revenue target and no team under it. A branch
     manager owed ten lakh from SBI, BOM and IDBI had no way to say so.

     Now the absence of a team says only that there is no team. */
  if (!t.team || !t.team.length) {
    return head + '<div class="empty">Nobody reports into this measure, so there ' +
      'is no team to divide it down to.</div>' + pfSplitBlock();
  }

  var rows = t.team.map(function(x){
    return '<tr><td>' + esc(x.name) +
        (x.employeeNo ? ' <span class="mute">' + esc(x.employeeNo) + '</span>' : '') +
        (x.feeders ? '<div class="mute">' + x.feeders + ' below them</div>' : '') +
      '</td>' +
      '<td>' + (x.target === null || x.target === undefined
                 ? '<span class="mute">none</span>' : pfNum(x.target)) + '</td>' +
      '<td>' + (x.pinned
                 ? '<span class="pfpin">pinned &mdash; a later divide leaves it alone</span>'
                 : '<span class="mute">a share</span>') + '</td>' +
      '<td class="plact">' + (x.maySet
        ? '<input class="pfin" data-pfshare="' + esc(x.assignmentId) + '" type="number" ' +
            'step="any" placeholder="pin a number">'
        : '<span class="mute">not yours to set</span>') + '</td></tr>';
  }).join("");

  return head +
    '<div class="scroll"><table><thead><tr>' +
      '<th>Whose</th><th>Their share</th><th></th><th>Pin one</th>' +
    '</tr></thead><tbody>' + rows + '</tbody></table></div>' +
    '<p><button class="btn" id="pfpinsave">Pin what I have typed</button> ' +
    '<span class="mute">The rest redivide around it. Blank boxes are left alone.</span></p>' +
    pfSplitBlock();
}

/* ------------------------------------------ one target, several clients
   A target divides DOWN to a team and ACROSS to the clients it is owed
   from. Ten lakh of collection is Shantanu's, and it is also five lakh of
   SBI, three of BOM and two of IDBI. Both divisions use the same rule --
   a count divides, a percentage is copied -- because they are the same
   act seen along two axes.

   The split lives here rather than on its own screen because this is
   already the place a target is decided, and a second screen for the
   same decision is how two answers to one question get into a tool.   */
function pfSplitBlock(){
  var s = PF.split;
  if (PF.splitFor !== PF.tgtFor) {
    return '<p class="pfsplitq"><button class="btn" id="pfsplitopen">' +
      'Split this across clients</button> ' +
      '<span class="mute">When a target is owed from several banks, it can be ' +
      'filed per bank and still add up to one number.</span></p>';
  }
  if (!s) return '<p class="mute">Loading the split&hellip;</p>';
  if (s.error) return msg("warn", s.reason || s.error);

  var parts = s.parts || [];
  var clients = s.clients || [];
  var chosen = {};
  parts.forEach(function(p){ chosen[p.clientId] = p; });

  var rows = clients.map(function(c){
    var p = chosen[c.id];
    return '<tr>' +
      '<td><label><input type="checkbox" data-pfsplitc="' + esc(c.id) + '"' +
        (p ? ' checked' : '') + (s.maySet ? '' : ' disabled') + '> ' +
        esc(c.name) + '</label></td>' +
      '<td>' + (s.divides
        ? '<input class="pfin" data-pfsplitt="' + esc(c.id) + '" type="number" ' +
          'step="any" value="' + esc(p && p.pinned && p.target !== null ? p.target : "") +
          '" placeholder="' + (p && p.target !== null ? esc(p.target) : 'even share') + '"' +
          (s.maySet ? '' : ' disabled') + '>'
        : '<span class="mute">' + (s.target === null ? '&mdash;' : pfNum(s.target)) +
          ' &mdash; not divided</span>') + '</td>' +
      '<td>' + (p
        ? (p.value === null || p.value === undefined
            ? '<span class="mute">nothing filed</span>' : pfNum(p.value)) +
          (p.filings ? ' <span class="mute">(' + p.filings + ')</span>' : '')
        : '') + '</td></tr>';
  }).join("");

  return '<div class="pfsplit">' +
    '<h3>Across clients</h3>' +
    '<p class="mute">' + esc(s.divides
      ? "A count, so the target divides. A bank left blank takes an even share of what is left."
      : "A percentage, so every bank carries the same number. It is not divided.") + '</p>' +
    '<div class="scroll"><table><thead><tr>' +
      '<th>Bank</th><th>Their share</th><th>Filed so far</th>' +
    '</tr></thead><tbody>' + rows + '</tbody></table></div>' +
    (s.maySet
      ? '<p><button class="btn primary" id="pfsplitsave">Save the split</button> ' +
        '<button class="btn" id="pfsplitclear">Remove the split</button> ' +
        '<span class="mute">Once split, the day&rsquo;s filing asks for each bank ' +
        'separately and they add back to this measure.</span></p>'
      : '<p class="mute">Only the person who sets this target may split it.</p>') +
    '</div>';
}

/* One person's row, used by the reporting line and by the search results
   alike, so the two lists cannot drift into offering different actions. */
function pfTeamRow(p){
  var open = PF.who === p.personId;
  return '<tr><td><b>' + esc(p.name) + '</b>' +
    (p.employeeNo ? ' <span class="mute">' + esc(p.employeeNo) + '</span>' : '') +
    '<div class="mute">' + esc(p.chair || "no chair") +
      (p.department ? ' · ' + esc(p.department) : '') + '</div></td>' +
    '<td class="plact">' +
      '<label class="pfsel"><input type="checkbox" data-pfsel="' + esc(p.personId) + '"' +
        (PF.sel[p.personId] ? ' checked' : '') + '> select</label>' +
      '<button class="btn" data-pfwho="' + esc(p.personId) + '">' +
        (open ? 'Hide' : 'Set targets') + '</button>' +
      '<button class="btn" data-pftask="' + esc(p.personId) + '">Assign a task</button>' +
      '</td></tr>' +
    (open ? '<tr><td colspan="2">' + pfPersonPanel() + '</td></tr>' : '');
}

/* Anyone an administrator or HR may set for who is not in their line.
   Nothing is listed until two characters are typed. The point is not to
   save bytes -- the list is already in the browser -- it is that a screen
   headed "my team" which opens on a hundred strangers is indistinguishable,
   to the person reading it, from a screen that is showing them data they
   should not have. */
function pfFindAnyone(){
  if (!PF.wider || !PF.wider.length) return "";
  var q = (PF.find || "").trim().toLowerCase();
  var hits = q.length < 2 ? [] : PF.wider.filter(function(p){
    return (p.name || "").toLowerCase().indexOf(q) >= 0
        || (p.employeeNo || "").toLowerCase().indexOf(q) >= 0
        || (p.chair || "").toLowerCase().indexOf(q) >= 0
        || (p.department || "").toLowerCase().indexOf(q) >= 0;
  });
  var shown = hits.slice(0, 12);
  return '<div class="pffind">' +
    '<h3>Search for anyone <span class="mute">· ' + PF.wider.length +
      ' outside your reporting line</span></h3>' +
    '<input id="pffind" placeholder="Name, employee number, chair or department"' +
      ' value="' + esc(PF.find || "") + '" autocomplete="off">' +
    (q.length < 2
      ? '<p class="mute">Type two letters. ' + esc(PF.widerWhy || "") + '</p>'
      : (hits.length
          ? '<div class="scroll"><table>' +
              shown.map(pfTeamRow).join("") + '</table></div>' +
            (hits.length > shown.length
              ? '<p class="mute">' + hits.length + ' match. Showing the first ' +
                shown.length + ' — type more to narrow it.</p>'
              : '')
          : '<p class="mute">Nobody matches &ldquo;' + esc(PF.find) + '&rdquo;.</p>')) +
    '</div>';
}

/* Editing and removing a measure arrived with migration 240 and a new
   pair of routes. Until the plb function carrying them is deployed the
   call comes back no_route, and "no_route" on a button somebody just
   pressed is the tool blaming them for its own deployment. */
function pfSaid(o, good){
  if (!o || !o.error) return msg("ok", (o && o.note) || good);
  if (o.error === "no_route") {
    return msg("warn", "This needs the performance service redeployed \u2014 " +
      "the screen has the button and the service does not have the route yet. " +
      "Nothing was changed.");
  }
  /* 42883 is Postgres for "no function of that name and argument types". It
     means the screen and the service are both newer than the database, which
     is a deployment state and not something the person pressing the button
     did. A bare SQLSTATE sends them hunting through logs; this says which of
     the three parts is behind. */
  if (o.error === "42883" ||
      /function .* does not exist/i.test(String(o.reason || o.error))) {
    return msg("warn", "This needs a database migration that has not been " +
      "applied yet \u2014 the screen and the service have the button and the " +
      "database does not have the function behind it. Nothing was changed.");
  }
  /* The clock refused, not the person. It reads as an explanation rather
     than a fault, and it names the way out, because there is one: HR,
     Business Excellence or an administrator can reopen the month. */
  if (o.error === "window_closed") {
    return msg("warn", (o.reason || "The window for setting KPIs has closed.") +
      (pfMayExtend() ? " You can reopen it at the top of this screen." : ""));
  }
  return msg("bad", o.reason || o.error);
}

/* ------------------------- I · my team: targets, tasks and eligibility */
/* Whose targets are mine, said at the TOP of the screen.

   The blueprint puts My team ninth, after eight sections about the reader's
   own numbers, and that order is right for somebody opening this screen to
   file their own figures -- which is most people, most days. It is wrong for
   a manager on the day they have to set their team's targets: Arun Bodupali
   reported he could not find how to set Manish's, and Manish was there, nine
   cards down.

   So the order is left alone and a line is put at the top instead. It names
   the people, so a manager can see at a glance whether the tool agrees with
   them about who their team is, and the button goes straight to the card. */
function pfSetFor(){
  var t = PF.team || [];
  if (!t.length) return "";
  var names = t.slice(0, 4).map(function(p){ return p.name; }).join(", ");
  return '<div class="pfsetfor">' +
    '<div><b>' + t.length + (t.length === 1 ? ' person' : ' people') +
      '</b> whose targets are yours to set this month' +
      '<div class="mute">' + esc(names) +
        (t.length > 4 ? ' and ' + (t.length - 4) + ' more' : '') + '</div></div>' +
    '<button class="btn primary" id="pfgoteam">Set their targets</button></div>';
}

/* The rest of the line: people whose numbers this person may read and whose
   targets are somebody else's to set. Drawn as a count that opens, never as
   a hundred rows carrying a button that would be refused. */
function pfWatchBlock(){
  var w = PF.watch || [];
  if (!w.length) return "";
  if (!PF.watchOpen) {
    return '<p class="pfwatch"><button class="btn" id="pfwatchopen">' +
      'Show the rest of my line (' + w.length + ')</button> ' +
      '<span class="mute">Their targets are set by their own manager. ' +
      'You see how they are doing; you do not set what they are asked for.</span></p>';
  }
  return '<div class="pfwatch open"><h3>The rest of my line ' +
      '<span class="mute">· ' + w.length + ' people, set by their own managers</span></h3>' +
    '<div class="scroll"><table><tbody>' + w.map(function(p){
      return '<tr><td><b>' + esc(p.name) + '</b>' +
        (p.employeeNo ? ' <span class="mute">' + esc(p.employeeNo) + '</span>' : '') +
        '<div class="mute">' + esc(p.chair || "no chair") +
          (p.department ? ' · ' + esc(p.department) : '') + '</div></td>' +
        '<td class="plact"><span class="mute">' +
          (p.depth ? p.depth + ' step' + (p.depth === 1 ? '' : 's') + ' below you' : '') +
        '</span></td></tr>';
    }).join("") + '</tbody></table></div>' +
    '<p><button class="btn" id="pfwatchshut">Hide them again</button></p></div>';
}

function pfTeamSection(){
  /* An administrator with nobody reporting to them still gets this card:
     the search box below is the only way they reach anybody at all. */
  if ((!PF.team || !PF.team.length) && (!PF.wider || !PF.wider.length)
      && (!PF.watch || !PF.watch.length)) return "";
  var n = Object.keys(PF.sel).filter(function(k){ return PF.sel[k]; }).length;
  var rows = (PF.team || []).map(pfTeamRow).join("");
  var mine = (PF.team || []).length;

  return '<div class="card" id="pfteam"><h2>My team ' +
      '<span class="mute">· ' +
      (mine ? mine + (mine === 1 ? ' person whose targets are yours to set'
                                 : ' people whose targets are yours to set')
            : 'targets, tasks and eligibility') + '</span></h2>' +
    (rows ? '' :
      '<p class="mute">Nobody reports to you directly, so there is nobody ' +
      'whose targets are yours to set.' +
      ((PF.wider || []).length ? ' Use the search below to reach somebody.' : '') +
      '</p>') +
    /* Two of these four give somebody a MEASURE and so answer the clock:
       perf_assign_bulk runs perf_assign for each person, and
       perf_carry_forward writes the same rows by another door. Asking
       somebody for a task and reading the eligibility matrix are not
       measures and are not gated, so they stay either way. */
    '<div class="plbar">' +
      (pfSetWindowOpen()
        ? '<button class="btn primary" id="pfbulk"' + (n ? '' : ' disabled') + '>' +
            (n ? 'Give the same KPIs to ' + n + ' selected' : 'Select people to assign in bulk') + '</button>' +
          '<button class="btn" id="pfcarry"' + (n ? '' : ' disabled') + '>Carry last month forward</button>'
        : '') +
      '<button class="btn" id="pftaskall">Assign a task to ' + (n ? n + ' selected' : 'the whole team') + '</button>' +
      '<button class="btn" id="pfelig">Eligibility matrix</button>' +
    '</div>' +
    (pfSetWindowOpen() ? '' : pfShutHere('Giving KPIs in bulk, and carrying last month forward')) +
    (rows ? '<div class="scroll"><table>' + rows + '</table></div>' : '') +
    pfWatchBlock() +
    pfFindAnyone() +
    (PF.form ? pfForm() : '') +
    (PF.taskForm ? pfTaskForm() : '') +
    (PF.elig ? pfEligibility() : '') +
    pfTasksOwed() +
    '</div>';
}

/* What I was asked for, and what I asked of other people. A task closed on
   time is the named artefact A-3 is scored from; a missed one is the other
   kind of record.                                                         */
function pfTasksOwed(){
  var t = PF.tasks || {};
  var owed = t.owed || [], set = t.set || [];
  if (!owed.length && !set.length) return "";
  function list(items, mine){
    return items.map(function(x){
      var cls = x.status === 'MISSED' ? ' bad' : x.status === 'LATE' ? ' warn'
              : x.status === 'DONE' ? ' ok' : x.overdue ? ' warn' : '';
      return '<tr class="pftask' + cls + '"><td><b>' + esc(x.title) + '</b>' +
        '<div class="mute">' +
          (x.dueOn ? 'due ' + day(x.dueOn) : 'no date') +
          (mine ? (x.setBy ? ' · asked by ' + esc(x.setBy) : '')
                : (x.forWhom ? ' · ' + esc(x.forWhom) : '')) +
        '</div></td>' +
        '<td>' + esc(x.status.toLowerCase()) + '</td>' +
        '<td class="plact">' +
          (mine && x.status === 'OPEN'
            ? '<button class="btn" data-pfdone="' + esc(x.id) + '">Done</button>' : '') +
          (!mine && x.status === 'OPEN'
            ? '<button class="btn" data-pfcancel="' + esc(x.id) + '">Call it off</button>' : '') +
        '</td></tr>';
    }).join("");
  }
  return '<h4 class="plh">Tasks this month</h4>' +
    (owed.length ? '<div class="scroll"><table>' + list(owed, true) + '</table></div>'
                 : '<div class="empty">Nobody has asked you for anything this month.</div>') +
    (set.length ? '<h4 class="plh">What you asked for</h4><div class="scroll"><table>' +
                  list(set, false) + '</table></div>' : '');
}

function pfTaskForm(){
  var f = PF.taskForm;
  return '<div class="plform">' +
    '<h4 class="plh">' + (f.who ? 'A task for ' + esc(f.name) : 'A task for the whole team') + '</h4>' +
    '<div class="hragrid">' +
      '<label class="hrafield"><span>What is being asked for</span>' +
        '<input data-pftf="title" value="' + esc(f.title || "") + '" ' +
        'placeholder="Visit the SBI branches in your area"></label>' +
      '<label class="hrafield"><span>By when</span>' +
        '<input data-pftf="dueOn" type="date" value="' + esc(f.dueOn || "") + '"></label>' +
      '<label class="hrafield"><span>Worth, towards A-3</span>' +
        '<select data-pftf="attributeWeight">' +
          '<option value="">not scored</option>' +
          '<option value="1"' + (f.attributeWeight === "1" ? ' selected' : '') + '>1 — partly</option>' +
          '<option value="2"' + (f.attributeWeight === "2" ? ' selected' : '') + '>2 — in full</option>' +
        '</select></label>' +
    '</div>' +
    '<label class="hrafield"><span>Detail</span><textarea data-pftf="detail" rows="2">' +
      esc(f.detail || "") + '</textarea></label>' +
    '<p class="mute">A task closed on time is the record A-3 is scored from — the ' +
    'Constitution says an attribute point must cite a named artefact and never a ' +
    'manager’s assertion. One missed is the other kind of record.</p>' +
    '<p><button class="btn primary" id="pftasksave">Set it</button> ' +
    '<button class="btn" id="pftaskcancel">Cancel</button></p></div>';
}

/* The eligibility matrix, from the Scorecard Guide's own gates. Read-only:
   the gates are the Constitution's and this screen does not set them.     */
function pfEligibility(){
  var rows = [
    ["Goal sheet acknowledged", "By day 10. Not acknowledging changes nothing — it still operates, and the fact is recorded."],
    ["Goal sheet issued at all", "By day 15, or the chair's standard sheet applies and you cannot be scored below it."],
    ["A month scored", "Neither manager nor Functional Head scored it — that month is excluded and the denominator reduces."],
    ["Protected leave", "The month is excluded, and the denominator reduces."],
    ["Attribute total above 1.5 in a month", "Functional Head countersigns."],
    ["Average monthly score 9.5 or above, or 4.0 or below", "Functional Head, with a Business Excellence rubric check."],
    ["Achievement below 50% or above 110%", "Functional Head, with MIS attesting the source data — both tails, not just the good one."],
    ["Unit average above 8.5", "Business Excellence calibration review — never a cap, never a forced curve."]
  ].map(function(r){
    return '<tr><td><b>' + esc(r[0]) + '</b></td><td>' + esc(r[1]) + '</td></tr>';
  }).join("");
  return '<div class="plform"><h4 class="plh">Eligibility matrix</h4>' +
    '<p class="mute">The gates in the Constitution, and what each one does. There is no ' +
    'forced distribution: no quota, no ranking, no bell curve, and no cap on how many ' +
    'people can score well.</p>' +
    '<div class="scroll"><table>' + rows + '</table></div>' +
    '<p><button class="btn" id="pfeligclose">Close</button></p></div>';
}

/* ---------------------------------------------------- J · the weighting */
function pfWeighting(){
  if (!PF.weighting.maySet) return "";
  var all = PF.weighting.all || [];
  var rows = all.map(function(w){
    return '<tr><td>' + (w.scopeAll ? '<b>Everybody</b>'
        : w.chair ? esc(w.chair) : w.person ? esc(w.person) : '—') + '</td>' +
      '<td>' + esc(w.kpiPercent) + ' / ' + esc(w.attrPercent) + '</td>' +
      '<td>' + day(w.effectiveFrom) + '</td>' +
      '<td class="mute">' + esc(w.setBy || '—') + '</td></tr>';
  }).join("");
  return '<div class="card"><h2>PMS weighting <span class="mute">· Admin and HR</span></h2>' +
    '<p class="mute">The split between KPIs and Attributes, for everybody or for selected ' +
    'teams. The Constitution sets it at 75 / 25 from 1 October 2026. A rule about one ' +
    'person beats a rule about their chair, which beats a rule about everybody.</p>' +
    (rows ? '<div class="scroll"><table><thead><tr><th>Applies to</th><th>KPI / Attr</th>' +
            '<th>From</th><th>Set by</th></tr></thead><tbody>' + rows + '</tbody></table></div>'
          : '<div class="empty">No split has been set. Nothing can be scored until one is.</div>') +
    '<p><button class="btn" id="pfweight">Open weighting</button></p>' +
    (PF.weightForm ? pfWeightForm() : '') + '</div>';
}

function pfWeightForm(){
  var f = PF.weightForm;
  return '<div class="plform"><h4 class="plh">A new split</h4>' +
    '<div class="hragrid">' +
      '<label class="hrafield"><span>KPIs %</span><input data-pfwf="kpiPercent" type="number" ' +
        'min="0" max="100" value="' + esc(f.kpiPercent || 75) + '"></label>' +
      '<label class="hrafield"><span>Attributes %</span><input data-pfwf="attrPercent" type="number" ' +
        'min="0" max="100" value="' + esc(f.attrPercent || 25) + '"></label>' +
      '<label class="hrafield"><span>From</span><input data-pfwf="effectiveFrom" type="date" ' +
        'value="' + esc(f.effectiveFrom || "") + '"></label>' +
    '</div>' +
    '<p class="mute">It has to add to 100. Earlier months keep the split they were scored ' +
    'under — changing this does not rewrite a month that has already closed.</p>' +
    '<p><button class="btn primary" id="pfweightsave">Save</button> ' +
    '<button class="btn" id="pfweightcancel">Cancel</button></p></div>';
}

/* ------------------------------------------------------- K · the appraisal
   The quarter. The blueprint puts it on this page and so does the scheme:
   PLB = Target × Payout Factor × Consistency Factor, where the Payout Factor
   comes from the quarter's Achievement and the Consistency Factor from the
   mean of these monthly scores. The two layers meet here, which is why this
   section is on the same screen as the daily update rather than behind a tab.

   The renderers are the ones the Bonus screen already used and they are
   correct — disputes, countersign, the manager's view. Reusing them is the
   difference between joining two screens and rewriting nine hundred lines. */
function pfAppraisal(){
  var p = PF.plb || {};
  var s = p.sheet;
  var head = '<div class="card"><h2>Appraisal <span class="mute">· ' +
    (p.quarter ? 'the quarter from ' + day(p.quarter) : 'this quarter') + '</span></h2>' +
    '<p class="mute">Your monthly scores decide how much of what you earned is released. ' +
    'An average of 8 out of 10 releases 80% of it; 10 releases all of it; below 3 it stops ' +
    'falling. What you earned comes from the goal sheet below.</p>';

  if (!s) {
    return head + '<div class="empty">' +
      (p.inScheme === false
        ? 'Your chair is not in the PLB scheme. The scheme starts at Branch Manager and ' +
          'Manager level; the Board and the Managing Director are outside it entirely.'
        : 'No goal sheet has been issued to you for this quarter. If none reaches you by ' +
          'day 15 your chair’s standard sheet applies, and you cannot be scored below what ' +
          'it produces.') +
      '</div></div>';
  }
  /* Those renderers arrive with the Bonus screen, which is a different patch
     in the same page. If a build ever leaves one out, say so here rather than
     throwing and taking the whole screen down with it — the sections above
     this one are still true and still worth reading. */
  if (typeof pbGoalSheet !== "function" || typeof pbMonthTable !== "function" ||
      typeof pbResult !== "function" || typeof pbDisputes !== "function") {
    return head + '<div class="empty">Your goal sheet is there, but the part of ' +
      'the page that draws it was not published with this one. Nothing is wrong ' +
      'with your account and nothing has been lost.</div></div>';
  }
  PB.data = p; PB.quarter = p.quarter;
  /* The quarter in the monthly card's shape, drawn HERE rather than on the
     other screen. pbGoalSheet -- the old three-percentages table -- is only
     fallen back on when /kpi/months could not be read, and it says so. */
  return head + '</div>' +
    (PF.qmonths ? pfQuarterCard() : pbGoalSheet(s)) +
    pbMonthTable(s) + pbResult(s) + pbDisputes(s, true);
}

/* ===================================================================
   The quarterly scorecard, in the monthly card's shape.

   The old table showed a measure's phasing as three percentages --
   "50 · 30 · 20". That is the RULE for splitting a quarter, not a
   scorecard: nobody reads it and knows what October was asking for. This
   draws what the monthly card draws -- a target, what was filed against
   it, and how that reads -- three times, one per month.

   And it is the LINK as well, because none of the numbers are invented
   for the drawing. `target` is the real monthly target sitting in PMS;
   `filed` is what was actually entered against it; `implied` is what
   this quarterly target and its split say that month should have been.
   Where the first two disagree with the third, it says so.
   =================================================================== */

var PF_DIR = [["", "— as the measure suggests —"],
              ["HIGHER", "A bigger number is better"],
              ["LOWER",  "A smaller number is better"]];

function pfQNum(v, unit){
  if (v === null || v === undefined || v === "") return "—";
  return pfNum(v, unit);
}

function pfQMonth(m, unit){
  var says = m.agrees === false
    ? '<span class="pfqbad" title="The monthly target and the quarter’s ' +
      'split do not agree">doesn’t match the quarter</span>'
    : (m.target === null || m.target === undefined
        ? '<span class="mute">no target yet</span>' : '');
  var pct = (m.target !== null && m.target !== undefined &&
             m.filed !== null && m.filed !== undefined && Number(m.target) !== 0)
    ? Math.round(1000 * Number(m.filed) / Number(m.target)) / 10 : null;
  return '<div class="pfqm">' +
    '<div class="pfqmh">' + esc(pfMonthName(m.month)) + '</div>' +
    '<div class="pfqmn"><span>Target</span><b>' + pfQNum(m.target, unit) + '</b></div>' +
    '<div class="pfqmn"><span>Filed</span><b>' + pfQNum(m.filed, unit) + '</b></div>' +
    '<div class="pfqmn"><span>The quarter implies</span><b>' +
      pfQNum(m.implied, unit) + '</b></div>' +
    (pct === null ? '' : pfBar(pct)) +
    (says ? '<div class="pfqsay">' + says + '</div>' : '') +
    '</div>';
}

/* A breakdown of ONE measure -- "sixty cases" as "Bank A forty, Bank B
   twenty". It carries no weight and enters no arithmetic: the measure set
   a chair publishes stays identical for every seat of that chair, and this
   is one person saying where their own sixty are going to come from. */
function pfQParts(x){
  var open = PF.qparts === x.goalKpiId;
  var list = (x.parts || []);
  var may  = (PF.qmonths || {}).maySet;
  if (!open) {
    return '<div class="pfqpsum">' +
      (list.length
        ? esc(String(list.length)) + ' sub-KPI' + (list.length === 1 ? '' : 's') +
          ' · ' + list.map(function(p){
            return esc(p.label) + ' ' + pfQNum(p.target, x.unit); }).join(' · ') +
          (x.partsAddUp === false
            ? ' <span class="pfqbad">they come to ' + esc(String(x.partsTotal)) +
              ', not ' + pfQNum(x.quarterly, x.unit) + '</span>' : '')
        : '<span class="mute">No sub-KPIs on this measure.</span>') +
      ' <button class="lnk" data-pfqparts="' + esc(x.goalKpiId) + '">' +
      (list.length ? 'Change them' : (may ? 'Break it down' : 'Show')) +
      '</button></div>';
  }
  var rows = list.concat([{ label:"", target:"" }]).map(function(p, i){
    return '<tr>' +
      '<td><input data-pfqpl="' + i + '" value="' + esc(p.label || "") +
        '" placeholder="Bank, product or place"></td>' +
      '<td><input data-pfqpt="' + i + '" type="number" step="any" value="' +
        esc(p.target === null || p.target === undefined ? "" : p.target) +
        '" placeholder="how many"></td>' +
      '<td><input data-pfqpn="' + i + '" value="' + esc(p.note || "") +
        '" placeholder="a note, if one helps"></td></tr>';
  }).join("");
  return '<div class="pfqparts">' +
    '<p class="mute">A breakdown of this one measure, for this person only. ' +
    'It carries no weight and changes no score — it is how the number is ' +
    'going to be made, so the chair is still asked for the same things. ' +
    'Leave a row blank to drop it.</p>' +
    '<table class="pfqpt"><thead><tr><th>Sub-KPI</th><th>Target</th>' +
    '<th>Note</th></tr></thead><tbody>' + rows + '</tbody></table>' +
    (may
      ? '<p><button class="btn primary" data-pfqpsave="' + esc(x.goalKpiId) +
        '">Save the breakdown</button> ' +
        '<button class="btn" data-pfqpcancel="1">Cancel</button></p>'
      : '<p class="mute">You can read this; changing it is their manager’s.</p>') +
    '<div id="pfqpmsg"></div></div>';
}

function pfQMeasure(x, i){
  var months = (x.months || []).map(function(m){ return pfQMonth(m, x.unit); }).join("");
  return '<div class="pfqmeas">' +
    '<div class="pfqhead">' +
      '<div><b>' + esc(x.name) + '</b>' +
        (x.unit ? ' <span class="mute">' + esc(pfUnit(x.unit)) + '</span>' : '') +
        '<div class="mute">Worth ' + esc(String(x.weight)) + '% of the quarter · ' +
          'the quarter asks for ' + pfQNum(x.quarterly, x.unit) +
          (x.actual === null || x.actual === undefined ? ''
            : ' · so far ' + pfQNum(x.actual, x.unit)) + '</div>' +
      '</div>' +
    '</div>' +
    '<div class="pfqmonths">' + months + '</div>' +
    pfQParts(x) +
    '</div>';
}

function pfQuarterCard(){
  var q = PF.qmonths || {};
  var ms = q.measures || [];
  return '<div class="card" id="pfquarter">' +
    '<div class="pfqtop">' +
      '<div><h2>The quarter, month by month</h2>' +
      '<p class="mute">The same shape as the monthly card above, because it is ' +
      'the same question asked of three months at once. The target on each ' +
      'month is the real one sitting in PMS; what the quarter implies is what ' +
      'this quarterly target and its split say that month should have been. ' +
      'Where the two disagree the month says so.</p></div>' +
      (q.maySet
        ? '<div><button class="btn" id="pfqedit">' +
          (PF.qedit ? 'Close the measure list' : 'Change the measures') +
          '</button></div>'
        : '') +
    '</div>' +
    (PF.qedit ? pfQEditor() : '') +
    (ms.length
      ? ms.map(pfQMeasure).join("")
      : '<div class="empty">There are no measures on this quarter’s sheet yet.</div>') +
    '<div id="pfqmsg">' + (PF.qsays || "") + '</div></div>';
}

/* ------------------------------------------------- changing the measures

   Until migration 255 there was no way to. plb_goal_kpi rows were written
   once, when the sheet was issued, and a sheet issued with the wrong
   measure stayed wrong for the quarter.

   The whole list is sent at once, because the rule that makes it valid --
   the weights add to a hundred -- is a rule about the SET. Editing one row
   at a time means every intermediate state is invalid. */
function pfQEditor(){
  var o = PF.qopts;
  if (!o) return '<div class="pfqedit"><p class="mute">Loading the measure list…</p></div>';
  /* A route that is not there yet is not a refusal, and must not be dressed
     as one. "These measures are not yours to change" told to somebody whose
     measures they are is how a deploy that has not happened gets mistaken
     for a permission problem and chased for an afternoon. */
  if (o.error === "no_route" || o.error === "no_such_function") {
    return '<div class="pfqedit"><div class="empty">The measure editor is ' +
      'built but not published to the server yet. Nothing is wrong with your ' +
      'account. Everything else on this card is live and correct.</div></div>';
  }
  if (o.error || !o.maySet) {
    return '<div class="pfqedit"><div class="empty">' +
      esc(o.why || o.reason || 'These measures are not yours to change.') +
      '</div></div>';
  }
  var ms = PF.qdraft || [];
  var sum = ms.reduce(function(a, m){ return a + (Number(m.weight) || 0); }, 0);
  var rows = ms.map(function(m, i){
    var k = (o.measures || []).filter(function(c){ return c.kpiId === m.kpiId; })[0] || {};
    return '<tr>' +
      '<td>' + esc(k.name || m.name || "—") +
        (k.unit ? '<div class="mute">' + esc(pfUnit(k.unit)) + '</div>' : '') + '</td>' +
      '<td><input data-pfqw="' + i + '" type="number" step="any" min="0" max="100" ' +
        'value="' + esc(m.weight === null || m.weight === undefined ? "" : m.weight) + '"></td>' +
      '<td><input data-pfqt="' + i + '" type="number" step="any" ' +
        'value="' + esc(m.target === null || m.target === undefined ? "" : m.target) + '"></td>' +
      '<td><select data-pfqd="' + i + '">' + PF_DIR.map(function(d){
          return '<option value="' + d[0] + '"' +
            ((m.direction || "") === d[0] ? ' selected' : '') + '>' +
            esc(d[1]) + '</option>'; }).join("") + '</select></td>' +
      '<td><button class="lnk" data-pfqdrop="' + i + '">Take off</button></td>' +
      '</tr>';
  }).join("");
  var spare = (o.measures || []).filter(function(c){
    return !ms.some(function(m){ return m.kpiId === c.kpiId; }); });
  return '<div class="pfqedit">' +
    '<p class="mute">Which measures this quarter asks for, what each is worth, ' +
    'what it asks for and which way it points. The weights have to add to a ' +
    'hundred — a score nobody can work out by hand is a score nobody trusts. ' +
    'Every measure needs a target, and zero is a target you can type.</p>' +
    '<table class="pfqet"><thead><tr><th>Measure</th><th>Weight %</th>' +
    '<th>Target</th><th>Which way is better</th><th></th></tr></thead>' +
    '<tbody>' + (rows || '<tr><td colspan="5" class="mute">Nothing on the sheet.</td></tr>') +
    '</tbody><tfoot><tr><td class="mute">Weights</td>' +
    '<td class="' + (Math.round(sum * 100) / 100 === 100 ? 'pfqok' : 'pfqbad') + '">' +
    esc(String(Math.round(sum * 100) / 100)) + '</td>' +
    '<td colspan="3" class="mute">' +
    (Math.round(sum * 100) / 100 === 100 ? 'adds up' : 'has to come to 100') +
    '</td></tr></tfoot></table>' +
    (spare.length
      ? '<p><label>Add a measure <select id="pfqadd">' +
        '<option value="">— choose —</option>' +
        spare.map(function(c){
          return '<option value="' + esc(c.kpiId) + '">' + esc(c.name) +
            (c.ofTheChair ? '' : ' (not this chair’s)') + '</option>'; }).join("") +
        '</select></label> <button class="btn" id="pfqaddgo">Add</button></p>'
      : '') +
    '<p><button class="btn primary" id="pfqsave">Save the measures</button> ' +
    '<button class="btn" id="pfqcancel">Cancel</button></p></div>';
}

/* One node, and its parts and its team under it. Depth is only indentation;
   the shape comes from the database. */
function pfNode(m, depth, isTeam){
  var id = m.assignmentId;
  var kids = (m.parts || []).length + (m.team || []).length;
  var isOpen = !!PF.open[id];
  var who = m.person
    ? '<span class="pfwho">' + esc(m.person.name) +
      (m.person.chair ? ' <span class="mute">' + esc(m.person.chair) + '</span>' : '') + '</span>'
    : '';

  var head = '<div class="pfrow" style="padding-left:' + (depth * 18) + 'px">' +
    (kids
      ? '<button class="pftog" data-pfopen="' + esc(id) + '">' + (isOpen ? '−' : '+') + '</button>'
      : '<span class="pftog pfnone"></span>') +
    '<span class="pfname">' + (isTeam ? who : esc(m.split || m.name)) +
      (isTeam ? '' : (m.splitKind ? ' <span class="chip">' + esc(m.splitKind.toLowerCase()) + '</span>' : '')) +
    '</span>' +
    '<span class="pfval">' + pfNum(m.value, m.unit) + '</span>' +
    '<span class="pftgt">' + (m.target ? 'of ' + pfNum(m.target) : '<span class="mute">no target</span>') + '</span>' +
    '<span class="pfpct">' + (m.pct === null || m.pct === undefined ? '' : esc(m.pct) + '%') + '</span>' +
    '<span class="pfmeter">' + pfBar(m.pct) + '</span>' +
    '</div>';

  var body = "";
  if (isOpen) {
    body = (m.parts || []).map(function(p){ return pfNode(p, depth + 1, false); }).join("") +
           (m.team  || []).map(function(p){ return pfNode(p, depth + 1, true);  }).join("");
  }
  return head + body;
}

/* pfTeam() used to live here: a SECOND drawing of the team card that
   nothing has called since pfTeamSection() replaced it. It was removed
   when the window rule went in and landed in the dead copy by mistake --
   which is the whole argument against keeping one. A card drawn in two
   places is a card that gets fixed in one.                             */
function pfPersonPanel(){
  var t = PF.whoTree;
  if (!t) return '<p class="mute">Loading…</p>';
  /* A reason, and a way out of it. This panel used to sit on "Loading…" for
     ever when the call failed, because call() rejected and the render that
     was going to follow never ran. call() no longer rejects, so the reason
     arrives here -- and a reason somebody cannot act on is only half the
     repair, hence the button. */
  if (t.error) {
    return msg("bad", t.reason || t.error) +
      '<p><button class="btn" id="pfwhoretry">Try again</button></p>';
  }
  var ms = t.measures || [];
  return '<div class="pfpanel">' +
    (ms.length
      ? '<div class="pftree">' + ms.map(function(m){ return pfNode(m, 0, false); }).join("") + '</div>' +
        pfMeasureAdmin(ms)
      : '<div class="empty">' + esc(t.says || "Nothing set for them this period.") + '</div>') +
    (pfSetWindowOpen()
      ? '<p><button class="btn" id="pfadd">Set a KPI for ' + esc(t.person.name) + '</button></p>'
      : pfShutHere('Setting a KPI for ' + t.person.name)) +
    (PF.editForm ? pfEditForm(ms) : '') +
    '</div>';
}

/* Change a measure, or take it back. Separate from the tree above rather
   than two more buttons on every node, because the tree is read far more
   often than it is edited and a row of verbs on each line is how a reading
   surface turns into a control panel. */
function pfMeasureAdmin(ms){
  var top = ms.filter(function(m){ return !m.splitOf; });
  if (!top.length) return "";
  /* Edit and Remove go through perf_assign_edit and perf_assign_remove, and
     both refuse once the month's window has shut. Drawing them anyway is
     drawing two buttons that always refuse. */
  if (!pfSetWindowOpen()) {
    return '<div class="pfadmin"><h4>Change what they are measured on</h4>' +
      pfShutHere('Changing what they are measured on') + '</div>';
  }
  return '<div class="pfadmin"><h4>Change what they are measured on</h4>' +
    '<div class="scroll"><table><tbody>' + top.map(function(m){
      return '<tr><td><b>' + esc(m.name) + '</b>' +
        (m.unit ? ' <span class="mute">(' + esc(m.unit) + ')</span>' : '') +
        (m.weight !== null && m.weight !== undefined
          ? ' <span class="chip">' + pfNum(m.weight) + '%</span>' : '') +
        '</td><td class="plact">' +
          '<button class="btn" data-pfedit="' + esc(m.assignmentId) + '">Edit</button>' +
          '<button class="btn" data-pfrm="' + esc(m.assignmentId) + '">Remove</button>' +
        '</td></tr>';
    }).join("") + '</tbody></table></div></div>';
}

function pfEditForm(ms){
  var f = PF.editForm;
  var mine = (PF.measures || {}).mine || [];
  var others = ms.filter(function(m){
    return !m.splitOf && m.assignmentId !== f.assignmentId; });
  return '<div class="plform">' +
    '<h4 class="plh">Change &ldquo;' + esc(f.was) + '&rdquo;</h4>' +
    '<div class="hragrid">' +
      '<label class="hrafield"><span>Call it</span>' +
        '<input data-pfe="name" value="' + esc(f.name || "") + '"></label>' +
      '<label class="hrafield"><span>Measured in <i class="hrahint">cases, rupees, %, days</i></span>' +
        '<input data-pfe="unit" value="' + esc(f.unit || "") + '"></label>' +
      '<label class="hrafield"><span>Weight %</span>' +
        '<input data-pfe="weight" type="number" step="any" value="' + esc(f.weight || "") + '"></label>' +
      '<label class="hrafield"><span>They file</span><select data-pfe="cadence">' +
        '<option value="">— leave it as it is —</option>' +
        ["DAILY","WEEKLY","MONTHLY","QUARTERLY"].map(function(c){
          return '<option value="' + c + '"' + (f.cadence === c ? ' selected' : '') + '>' +
            c.toLowerCase() + '</option>'; }).join("") +
      '</select></label>' +
      '<label class="hrafield"><span>Which way is better <i class="hrahint">more is better, or fewer is</i></span><select data-pfe="direction">' +
        '<option value="">&mdash; as the measure suggests &mdash;</option>' +
        '<option value="HIGHER"' + (f.direction === "HIGHER" ? ' selected' : '') +
          '>A bigger number is better</option>' +
        '<option value="LOWER"' + (f.direction === "LOWER" ? ' selected' : '') +
          '>A smaller number is better</option>' +
      '</select></label>' +
      '<label class="hrafield"><span>Adds up into <i class="hrahint">which of YOUR measures this one feeds</i></span><select data-pfe="rollsInto">' +
        '<option value="">— nothing —</option>' +
        mine.map(function(m){
          return '<option value="' + esc(m.assignmentId) + '"' +
            (f.rollsInto === m.assignmentId ? ' selected' : '') + '>' +
            esc(m.name) + (m.split ? ' · ' + esc(m.split) : '') + '</option>'; }).join("") +
      '</select></label>' +
    '</div>' +
    '<p class="mute">The target is not here. It is set on the measure itself, ' +
    'where setting it also divides it down the team and across the clients — ' +
    'two places to type one number is how the two stop agreeing.</p>' +
    '<div class="plbar">' +
      '<button class="btn primary" id="pfesave">Save the change</button>' +
      '<button class="btn" id="pfecancel">Cancel</button>' +
    '</div></div>';
}

/* ------------------------------------------------------------ the form */
function pfForm(){
  var f = PF.form, cat = (PF.measures || {}).catalogue || [], mine = (PF.measures || {}).mine || [];
  if (!PF.measures) return '<div class="plform"><p class="mute">Loading the measures…</p></div>';

  var cads = {};
  cat.forEach(function(k){ if (k.cadence) cads[k.cadence] = 1; });
  var cadOpts = Object.keys(cads).sort().map(function(c){
    return '<option value="' + esc(c) + '"' + (f.cadence === c ? ' selected' : '') + '>' +
      esc(c.toLowerCase().replace(/_/g, " ")) + '</option>'; }).join("");

  return '<div class="plform">' +
    '<h4 class="plh">' + (f.bulk ? 'The same KPI for everyone selected' : 'A KPI for ' + esc(f.name)) + '</h4>' +
    '<div class="hragrid">' +
      '<label class="hrafield"><span>Measure</span><select data-pff="kpiId">' +
        '<option value="">— choose —</option>' +
        cat.map(function(k){
          return '<option value="' + esc(k.id) + '"' + (f.kpiId === k.id ? ' selected' : '') + '>' +
            esc(k.name) + (k.unit ? ' (' + esc(k.unit) + ')' : '') + '</option>'; }).join("") +
        /* The registry is what a chair is MEANT to be measured on, and it
           is not the whole of what a manager ever needs to ask for. Until
           this option existed the form refused to submit without a
           catalogue id, so "add a KPI" had no door at all: perf_assign has
           always taken a free-text name, and nothing offered one. */
        '<option value="NEW"' + (f.kpiId === "NEW" ? ' selected' : '') +
          '>— something else, named here —</option>' +
      '</select></label>' +
    (f.kpiId === "NEW"
      /* newName, not name: f.name already holds the PERSON's name, which is
         what the heading above reads from. */
      ? '<label class="hrafield"><span>Call it</span>' +
          '<input data-pff="newName" value="' + esc(f.newName || "") +
          '" placeholder="Name it the way they would say it"></label>' +
        '<label class="hrafield"><span>Measured in <i class="hrahint">cases, rupees, %, days</i></span>' +
          '<input data-pff="unit" value="' + esc(f.unit || "") +
          '" placeholder="cases, visits, rupees, %"></label>'
      : '') +
      '<label class="hrafield"><span>Target</span>' +
        '<input data-pff="target" type="number" step="any" value="' + esc(f.target || "") + '"></label>' +
      '<label class="hrafield"><span>Weight %</span>' +
        '<input data-pff="weight" type="number" step="any" value="' + esc(f.weight || "") + '"></label>' +
      '<label class="hrafield"><span>They file</span><select data-pff="cadence">' +
        '<option value="">— as the measure says —</option>' + cadOpts + '</select></label>' +
      '<label class="hrafield"><span>On which day</span>' +
        '<input data-pff="cadenceDay" type="number" min="1" max="28" ' +
        'placeholder="10 for the 10th, 5 for Friday" value="' + esc(f.cadenceDay || "") + '"></label>' +
      '<label class="hrafield"><span>Which way is better <i class="hrahint">more is better, or fewer is</i></span><select data-pff="direction">' +
        '<option value="">&mdash; as the measure suggests &mdash;</option>' +
        '<option value="HIGHER"' + (f.direction === "HIGHER" ? ' selected' : '') +
          '>A bigger number is better</option>' +
        '<option value="LOWER"' + (f.direction === "LOWER" ? ' selected' : '') +
          '>A smaller number is better</option>' +
      '</select></label>' +
      '<label class="hrafield"><span>Adds up into <i class="hrahint">which of YOUR measures this one feeds</i></span><select data-pff="rollsInto">' +
        '<option value="">— nothing yet —</option>' +
        mine.map(function(m){
          return '<option value="' + esc(m.assignmentId) + '"' +
            (f.rollsInto === m.assignmentId ? ' selected' : '') + '>' +
            esc(m.name) + (m.split ? ' · ' + esc(m.split) : '') + '</option>'; }).join("") +
      '</select></label>' +
    '</div>' +
    (PF.measures.note ? '<div class="plsub">' + msg("warn", PF.measures.note) + '</div>' : '') +
    '<p class="mute">A measure with no target is not scored and does not drag the average ' +
    'down — it is left out and says so. Leave it blank if you genuinely have not set one ' +
    'yet, rather than putting a nought in.</p>' +
    '<div class="plbar">' +
      '<button class="btn primary" id="pfsave">' +
        (f.bulk ? 'Give it to everyone selected' : 'Set it') + '</button>' +
      '<button class="btn" id="pfcancel">Cancel</button>' +
    '</div></div>';
}

/* The catalogue a manager picks from. Asked for one person, it comes back
   as that chair's measure set rather than as every measure in the company,
   which is the difference between choosing and searching. Cached per
   person, because the one thing worse than a long list is a long list that
   is fetched again every time the form is drawn. */
async function pfMeasuresFor(personId){
  var key = personId || "all";
  if (PF.measuresFor === key && PF.measures) return;
  PF.measures = null; PF.measuresFor = key; pfRender();
  var q = "/plb/perf/measures?cycle=" + PF.cycle.id +
          (personId ? "&person=" + encodeURIComponent(personId) : "");
  var m = await plb(q);
  /* A second click while the first was in flight wins; this one is stale. */
  if (PF.measuresFor !== key) return;
  PF.measures = m;
  pfRender();
}

/* ------------------------------------------------- the quarter's handlers

   Kept in one function so that a build which somehow drops the quarter
   block drops its wiring with it, rather than leaving live buttons over a
   panel that is not there. */
function pfQWire(){
  if (el("pfqedit")) el("pfqedit").onclick = async function(){
    PF.qedit = !PF.qedit; PF.qsays = "";
    if (PF.qedit) {
      pfRender();                                  /* say "Loading…" first */
      var s = (PF.plb || {}).sheet;
      PF.qopts = await plb("/plb/sheet/measures?sheet=" + encodeURIComponent(s.id));
      /* The draft starts as what is on the sheet now, read from the card
         we already have, so opening the editor asks nothing extra. */
      PF.qdraft = ((PF.qmonths || {}).measures || []).map(function(m){
        return { kpiId:m.kpiId, name:m.name, weight:m.weight,
                 target:m.quarterly, direction:m.direction || "" };
      });
    }
    pfRender();
  };

  if (el("pfqcancel")) el("pfqcancel").onclick = function(){
    PF.qedit = false; PF.qdraft = null; PF.qsays = ""; pfRender();
  };

  if (el("pfqaddgo")) el("pfqaddgo").onclick = function(){
    var id = el("pfqadd").value;
    if (!id) return;
    var c = ((PF.qopts || {}).measures || []).filter(function(m){
      return m.kpiId === id; })[0] || {};
    PF.qdraft = (PF.qdraft || []).concat([{ kpiId:id, name:c.name,
      weight:"", target:"", direction:c.suggests || "" }]);
    pfRender();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pfqdrop]"), function(b){
    b.onclick = function(){
      var i = Number(b.getAttribute("data-pfqdrop"));
      PF.qdraft = (PF.qdraft || []).filter(function(_, j){ return j !== i; });
      pfRender();
    };
  });

  /* Typing is held in the draft rather than read at save time, so adding a
     row does not throw away what was typed into the others. */
  ["pfqw:weight", "pfqt:target", "pfqd:direction"].forEach(function(pair){
    var attr = pair.split(":")[0], field = pair.split(":")[1];
    Array.prototype.forEach.call(
      el("view").querySelectorAll("[data-" + attr + "]"), function(inp){
        inp.oninput = inp.onchange = function(){
          var i = Number(inp.getAttribute("data-" + attr));
          if (PF.qdraft && PF.qdraft[i]) PF.qdraft[i][field] = inp.value;
          if (field === "weight") pfRender();   /* the running total moves */
        };
      });
  });

  if (el("pfqsave")) el("pfqsave").onclick = async function(){
    var s = (PF.plb || {}).sheet;
    var o = await plb("/plb/sheet/measures", { method:"POST", body:{
      sheetId: s.id,
      measures: (PF.qdraft || []).map(function(m){
        return { kpiId:m.kpiId, weight:m.weight, target:m.target,
                 direction:m.direction || null };
      })
    }});
    if (o.error) {
      PF.qsays = msg("bad", (o.fields || []).map(function(f){ return f.reason; })
        .concat([o.reason || o.error]).filter(Boolean).join(" "));
      pfRender();
      return;
    }
    PF.qsays = msg("ok", o.note);
    PF.qedit = false; PF.qdraft = null;
    await pfQLoad();
    PF.qsays = msg("ok", o.note);
    pfRender();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pfqparts]"), function(b){
    b.onclick = function(){
      PF.qparts = b.getAttribute("data-pfqparts"); PF.qsays = ""; pfRender();
    };
  });
  if (el("view").querySelector("[data-pfqpcancel]")) {
    el("view").querySelector("[data-pfqpcancel]").onclick = function(){
      PF.qparts = null; pfRender();
    };
  }
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pfqpsave]"), function(b){
    b.onclick = async function(){
      var parts = [], i = 0;
      while (el("view").querySelector('[data-pfqpl="' + i + '"]')) {
        var lab = el("view").querySelector('[data-pfqpl="' + i + '"]').value;
        var tgt = el("view").querySelector('[data-pfqpt="' + i + '"]').value;
        var nte = el("view").querySelector('[data-pfqpn="' + i + '"]').value;
        /* A row with no name is a row somebody did not fill in, not a row
           they want saved blank. The empty row at the bottom is there to
           be typed into or ignored. */
        if (String(lab).trim() !== "") {
          parts.push({ label:lab, target:tgt === "" ? null : tgt, note:nte || null });
        }
        i = i + 1;
      }
      var o = await plb("/plb/kpi/parts", { method:"POST", body:{
        goalKpiId: b.getAttribute("data-pfqpsave"), parts: parts }});
      if (o.error) {
        if (el("pfqpmsg")) el("pfqpmsg").innerHTML = msg("bad", o.reason || o.error);
        return;
      }
      PF.qparts = null;
      await pfQLoad();
      PF.qsays = msg("ok", o.note || "Saved.");
      pfRender();
    };
  });
}

/* ---------------------------------------------------------------- wiring */
function pfWire(){
  pfQWire();

  if (el("pfwhoretry")) el("pfwhoretry").onclick = async function(){
    if (!PF.who || !PF.cycle) return;
    PF.whoTree = null; pfRender();
    PF.whoTree = await plb("/plb/perf/tree?cycle=" + PF.cycle.id +
                           "&person=" + encodeURIComponent(PF.who));
    pfRender();
  };
  if (el("pfperiod")) el("pfperiod").onchange = async function(){
    PF.period = el("pfperiod").value; PF.tree = null; PF.who = null;
    PF.whoTree = null; PF.says = ""; PF.measures = null; PF.measuresFor = null;
    el("view").innerHTML = '<p class="mute">Loading…</p>';
    await vPerf();
  };

  if (el("pfopen")) el("pfopen").onclick = async function(){
    var o = await plb("/plb/perf/cycle/open", { method:"POST", body:{ period: PF.period } });
    PF.says = o.error ? msg("bad", o.reason || o.error) : msg("ok", o.note);
    await vPerf();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pftab]"), function(b){
    b.onclick = function(){ PF.tab = b.getAttribute("data-pftab"); pfRender(); };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pfopen]"), function(b){
    b.onclick = function(){
      var k = b.getAttribute("data-pfopen");
      PF.open[k] = !PF.open[k];
      pfRender();
    };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pfsel]"), function(b){
    b.onchange = function(){ PF.sel[b.getAttribute("data-pfsel")] = b.checked; pfRender(); };
  });

  /* The search box re-renders the whole screen on every keystroke, which
     would otherwise take the caret with it. So the value and the caret are
     put back and the field is re-focused -- and the state is read from the
     event rather than from PF, because PF.find is what we are about to
     set. */
  if (el("pffind")) {
    var box = el("pffind");
    box.oninput = function(){
      var at = box.selectionStart;
      PF.find = box.value;
      pfRender();
      var again = el("pffind");
      if (again) { again.focus(); try { again.setSelectionRange(at, at); } catch (e) {} }
    };
  }

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pfwho]"), function(b){
    b.onclick = async function(){
      var id = b.getAttribute("data-pfwho");
      if (PF.who === id) { PF.who = null; PF.whoTree = null; PF.form = null; pfRender(); return; }
      PF.who = id; PF.whoTree = null; PF.form = null; pfRender();
      PF.whoTree = await plb("/plb/perf/tree?cycle=" + PF.cycle.id + "&person=" + id);
      pfRender();
    };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pffileb]"), function(b){
    b.onclick = async function(){
      if (PF.busy) return;
      var id = b.getAttribute("data-pffileb");
      var box = el("view").querySelector('[data-pffile="' + id + '"]');
      if (!box || box.value === "") return;
      PF.busy = true; b.disabled = true;
      var o = await plb("/plb/perf/file", { method:"POST", body:{
        assignmentId: id, asOf: new Date().toISOString().slice(0,10), value: box.value } });
      PF.busy = false;
      PF.says = o.error ? msg("bad", o.reason || o.error) : msg("ok", o.note);
      await pfLoadMine(); pfRender();
    };
  });

  /* The top-of-page pointer scrolls to the card rather than jumping by
     anchor, so the reader keeps their place in the page and can see that
     the card was there all along. */
  if (el("pfgoteam")) el("pfgoteam").onclick = function(){
    var card = el("pfteam");
    if (!card) return;
    try { card.scrollIntoView({ behavior: "smooth", block: "start" }); }
    catch (e) { card.scrollIntoView(); }
  };

  /* ------------------------------------------ reopening a shut month */
  if (el("pfreopen")) el("pfreopen").onclick = function(){
    var c = PF.cycle || {};
    /* A week from today, bounded by the day filing closes -- the same two
       limits perf_cycle_extend applies, so the box opens on a date it will
       accept rather than on one it will refuse. */
    var d = new Date(); d.setDate(d.getDate() + 7);
    var want = d.toISOString().slice(0, 10);
    if (c.entry_closes && want > c.entry_closes) want = c.entry_closes;
    PF.reopen = { until: want, why: "" };
    pfRender();
  };
  if (el("pfreopencancel")) el("pfreopencancel").onclick = function(){
    PF.reopen = null; pfRender();
  };
  if (el("pfreopensave")) el("pfreopensave").onclick = async function(){
    if (PF.busy) return;
    PF.busy = true;
    var o = await perfApi("/perf/cycle/extend", { method:"POST", body:{
      cycleId: PF.cycle.id,
      until: el("pfreopenday").value,
      why: el("pfreopenwhy").value } });
    PF.busy = false;
    PF.says = pfSaid(o, "Reopened.");
    if (o && !o.error) {
      PF.reopen = null;
      /* The cycle the whole screen reads is now wrong, so it is re-read
         rather than patched: assign_open is what every KPI control asks. */
      var c = await plb("/plb/perf/cycle?period=" + PF.period);
      PF.cycle = c.cycle || PF.cycle;
    }
    pfRender();
  };

  if (el("pfwatchopen")) el("pfwatchopen").onclick = function(){
    PF.watchOpen = true; pfRender();
  };
  if (el("pfwatchshut")) el("pfwatchshut").onclick = function(){
    PF.watchOpen = false; pfRender();
  };

  if (el("pfadd")) el("pfadd").onclick = async function(){
    PF.form = { personId: PF.who, name: (PF.whoTree.person || {}).name, bulk:false };
    PF.editForm = null;
    pfRender();
    await pfMeasuresFor(PF.who);
  };

  /* ------------------------------------------- changing a measure given */
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pfedit]"), function(b){
    b.onclick = async function(){
      var id = b.getAttribute("data-pfedit");
      var m = ((PF.whoTree || {}).measures || []).filter(function(x){
        return x.assignmentId === id; })[0];
      if (!m) return;
      PF.form = null;
      PF.editForm = { assignmentId: id, was: m.name, name: m.name,
                      unit: m.unit || "", weight: m.weight,
                      cadence: "", rollsInto: m.rollsInto || "" };
      pfRender();
      /* The roll-up list is the SETTER's own measures, which is what the
         database checks, so it is fetched for nobody in particular. */
      await pfMeasuresFor(null);
    };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pfe]"), function(f){
    f.onchange = function(){ PF.editForm[f.getAttribute("data-pfe")] = f.value; };
  });

  if (el("pfecancel")) el("pfecancel").onclick = function(){
    PF.editForm = null; pfRender();
  };

  if (el("pfesave")) el("pfesave").onclick = async function(){
    if (PF.busy) return;
    var f = PF.editForm;
    if (!(f.name || "").trim()) {
      PF.says = msg("bad", "A measure needs a name."); pfRender(); return;
    }
    PF.busy = true; el("pfesave").disabled = true;
    var body = { assignmentId: f.assignmentId, name: f.name.trim(),
                 unit: (f.unit || "").trim(), weight: f.weight,
                 rollsInto: f.rollsInto };
    /* An empty cadence means "leave it", and sending "" would be refused
       as a cadence that does not exist. */
    if (f.cadence) body.cadence = f.cadence;
    var o = await plb("/plb/perf/edit", { method:"POST", body: body });
    PF.busy = false;
    PF.says = pfSaid(o, "Changed.");
    if (!o.error) { PF.editForm = null; PF.whoTree = null; }
    if (PF.who && !PF.whoTree) {
      PF.whoTree = await plb("/plb/perf/tree?cycle=" + PF.cycle.id + "&person=" + PF.who);
    }
    pfRender();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pfrm]"), function(b){
    b.onclick = async function(){
      if (PF.busy) return;
      var id = b.getAttribute("data-pfrm");
      var m = ((PF.whoTree || {}).measures || []).filter(function(x){
        return x.assignmentId === id; })[0] || {};
      if (!confirm("Take “" + (m.name || "this measure") + "” back?\n\n" +
          "If anything has been filed against it, it is withdrawn rather than " +
          "deleted — it stops being asked for and what was filed still reads back.")) return;
      PF.busy = true; b.disabled = true;
      var o = await plb("/plb/perf/remove", { method:"POST", body:{ assignmentId: id } });
      PF.busy = false;
      PF.says = pfSaid(o, "Removed.");
      PF.editForm = null; PF.whoTree = null;
      if (PF.who) {
        PF.whoTree = await plb("/plb/perf/tree?cycle=" + PF.cycle.id + "&person=" + PF.who);
      }
      pfRender();
    };
  });

  if (el("pfbulk")) el("pfbulk").onclick = async function(){
    PF.form = { bulk:true };
    pfRender();
    /* No one person, so no one chair: the whole catalogue, which is the
       honest answer when the same measure is going to several chairs. */
    await pfMeasuresFor(null);
  };

  if (el("pfcarry")) el("pfcarry").onclick = async function(){
    var who = Object.keys(PF.sel).filter(function(k){ return PF.sel[k]; });
    var done = 0, said = [];
    for (var i = 0; i < who.length; i++) {
      var o = await plb("/plb/perf/carry", { method:"POST",
        body:{ cycleId: PF.cycle.id, personId: who[i] } });
      if (o.error) said.push(o.reason || o.error); else done += (o.copied || 0);
    }
    PF.says = said.length ? msg("bad", said.join(" "))
                          : msg("ok", done + " measure(s) carried forward. The targets are blank " +
                                "on purpose — last month’s number is not this month’s promise.");
    PF.whoTree = null; pfRender();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pff]"), function(f){
    f.onchange = function(){
      var k = f.getAttribute("data-pff");
      PF.form[k] = f.value;
      /* Choosing "something else" has to put two more boxes on the form,
         so that one field re-draws and the rest do not -- a re-render on
         every keystroke would take the caret out of the name box. */
      if (k === "kpiId") pfRender();
    };
  });

  if (el("pfcancel")) el("pfcancel").onclick = function(){ PF.form = null; pfRender(); };

  if (el("pfsave")) el("pfsave").onclick = async function(){
    if (PF.busy) return;
    var f = PF.form;
    if (!f.kpiId) { PF.says = msg("bad", "Choose a measure first."); pfRender(); return; }
    var named = f.kpiId === "NEW";
    if (named && !(f.newName || "").trim()) {
      PF.says = msg("bad", "Give the measure a name, or pick one from the list.");
      pfRender(); return;
    }
    PF.busy = true; el("pfsave").disabled = true;
    /* kpiId is sent only when it names a catalogue row. perf_assign reads
       the name off the kpi_definition when it is given one and off the body
       when it is not, so the two cases are the same call. */
    var body = { cycleId: PF.cycle.id, target: f.target,
                 weight: f.weight, cadence: f.cadence, cadenceDay: f.cadenceDay,
                 rollsInto: f.rollsInto };
    if (named) {
      body.name = (f.newName || "").trim();
      body.unit = (f.unit || "").trim();
    } else {
      body.kpiId = f.kpiId;
    }
    var o;
    if (f.bulk) {
      o = await plb("/plb/perf/assign/bulk", { method:"POST", body:{
        cycleId: PF.cycle.id,
        people: Object.keys(PF.sel).filter(function(k){ return PF.sel[k]; }),
        measures: [body] } });
    } else {
      body.personId = f.personId;
      o = await plb("/plb/perf/assign", { method:"POST", body: body });
    }
    PF.busy = false;
    PF.says = o.error ? msg("bad", o.reason || o.error) : msg("ok", o.note || "Set.");
    PF.form = null; PF.whoTree = null; PF.measures = null; PF.measuresFor = null;
    if (PF.who) PF.whoTree = await plb("/plb/perf/tree?cycle=" + PF.cycle.id + "&person=" + PF.who);
    pfRender();
  };

  /* ------------------------------------------------ the one daily submission
     The blueprint submits a day, not a row. Everything filled in goes at
     once; a blank is left alone rather than filed as a zero, because a zero
     you meant and a box you did not reach are different facts.            */
  /* ------------------------------------ one person's handover, opened
     Everything this needs is already in PF.hand, so it re-renders rather
     than asking the server again -- opening four people in a row should
     not be four round trips. */
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pfhand]"), function(b){
    b.onclick = function(){
      var id = b.getAttribute("data-pfhand");
      if (PF.handOpen[id]) delete PF.handOpen[id]; else PF.handOpen[id] = true;
      pfRender();
    };
  });

  /* ------------------------------------------------ the target and its shares */
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pftgt]"), function(b){
    b.onclick = async function(){
      var id = b.getAttribute("data-pftgt");
      if (PF.tgtFor === id) {
        PF.tgtFor = null; PF.tgt = null;
        PF.split = null; PF.splitFor = null; pfRender(); return; }
      /* A split belongs to one measure. Carrying it to the next panel
         would show one measure's banks under another's target. */
      PF.tgtFor = id; PF.tgt = null; PF.split = null; PF.splitFor = null;
      pfRender();
      PF.tgt = await perfApi("/perf/target/team?assignment=" + encodeURIComponent(id));
      pfRender();
    };
  });

  /* ------------------------------------------ the split across clients */
  if (el("pfsplitopen")) el("pfsplitopen").onclick = async function(){
    el("pfsplitopen").disabled = true;
    PF.splitFor = PF.tgtFor; PF.split = null; pfRender();
    PF.split = await perfApi("/perf/split?assignment=" + encodeURIComponent(PF.tgtFor));
    pfRender();
  };

  /* Reads the boxes rather than keeping a second copy of them in state:
     the ticks and the numbers on screen ARE the intent, and a mirror of
     them is one more thing to fall out of step. */
  function pfSplitParts(){
    var parts = [];
    Array.prototype.forEach.call(
      el("view").querySelectorAll("[data-pfsplitc]"), function(cb){
        if (!cb.checked) return;
        var id = cb.getAttribute("data-pfsplitc");
        var box = el("view").querySelector('[data-pfsplitt="' + id + '"]');
        var v = box && box.value !== "" ? box.value : null;
        parts.push(v === null ? { ref:id } : { ref:id, target:Number(v) });
      });
    return parts;
  }

  async function pfSplitSend(parts){
    if (PF.busy) return;
    PF.busy = true;
    var o = await perfApi("/perf/split", { method:"POST",
      body:{ assignmentId: PF.tgtFor, parts: parts } });
    PF.busy = false;
    if (o && o.error) {
      PF.says = msg(o.error === "has_filings" ? "warn" : "bad", o.reason || o.error);
      pfRender(); return;
    }
    PF.says = msg("good", (o && o.note) || "Saved.");
    PF.split = await perfApi("/perf/split?assignment=" + encodeURIComponent(PF.tgtFor));
    await pfLoadMine();
    pfRender();
  }

  if (el("pfsplitsave")) el("pfsplitsave").onclick = function(){
    var parts = pfSplitParts();
    if (!parts.length) {
      PF.says = msg("warn", "Tick the banks to split across, or use Remove the split.");
      pfRender(); return;
    }
    pfSplitSend(parts);
  };

  if (el("pfsplitclear")) el("pfsplitclear").onclick = function(){ pfSplitSend([]); };

  if (el("pftgtsave")) el("pftgtsave").onclick = async function(){
    var v = el("pftgtval").value;
    if (v === "") { PF.says = "A target needs a number."; pfRender(); return; }
    if (PF.busy) return;
    PF.busy = true; el("pftgtsave").disabled = true;
    var o = await perfApi("/perf/target", { method:"POST",
      body: { assignmentId: PF.tgtFor, target: v } });
    PF.busy = false;
    PF.says = o && o.error ? (o.reason || o.error) : (o && o.note) || "Set.";
    PF.tgt = await perfApi("/perf/target/team?assignment=" + encodeURIComponent(PF.tgtFor));
    await pfLoadMine();
    pfRender();
  };

  if (el("pfpinsave")) el("pfpinsave").onclick = async function(){
    var boxes = Array.prototype.slice.call(el("view").querySelectorAll("[data-pfshare]"))
      .filter(function(x){ return x.value !== ""; });
    if (!boxes.length) { PF.says = "Nothing typed, so nothing pinned."; pfRender(); return; }
    if (PF.busy) return;
    PF.busy = true; el("pfpinsave").disabled = true;
    var done = 0, bad = null;
    for (var i = 0; i < boxes.length; i++) {
      var o = await perfApi("/perf/target", { method:"POST", body: {
        assignmentId: boxes[i].getAttribute("data-pfshare"),
        target: boxes[i].value, manual: true } });
      if (o && o.error) { bad = o.reason || o.error; } else { done++; }
    }
    PF.busy = false;
    PF.says = bad ? (done + " pinned, and one was refused: " + bad)
                  : done + " share(s) pinned. The rest divided around them.";
    PF.tgt = await perfApi("/perf/target/team?assignment=" + encodeURIComponent(PF.tgtFor));
    await pfLoadMine();
    pfRender();
  };

  if (el("pfsubmitday")) el("pfsubmitday").onclick = async function(){
    if (PF.busy) return;
    var boxes = Array.prototype.slice.call(el("view").querySelectorAll("[data-pffile]"))
      .filter(function(b){ return b.value !== ""; });
    if (!boxes.length) {
      PF.says = msg("warn", "Nothing to file — every box is blank.");
      pfRender(); return;
    }
    PF.busy = true; el("pfsubmitday").disabled = true;
    var today = new Date().toISOString().slice(0,10), done = 0, bad = [];
    for (var i = 0; i < boxes.length; i++) {
      var o = await plb("/plb/perf/file", { method:"POST", body:{
        assignmentId: boxes[i].getAttribute("data-pffile"), asOf: today, value: boxes[i].value } });
      if (o.error) bad.push(o.reason || o.error); else done++;
    }
    PF.busy = false;
    PF.says = bad.length
      ? msg("bad", done + " filed, " + bad.length + " refused. " + bad.join(" "))
      : msg("ok", done + (done === 1 ? " number" : " numbers") + " filed for today.");
    await pfLoadMine(); pfRender();
  };

  /* ------------------------------------------------------------ the tasks */
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pftask]"), function(b){
    b.onclick = function(){
      var id = b.getAttribute("data-pftask");
      var who = (PF.team || []).filter(function(p){ return p.personId === id; })[0] || {};
      PF.taskForm = { who: id, name: who.name || "them" };
      pfRender();
    };
  });

  if (el("pftaskall")) el("pftaskall").onclick = function(){
    PF.taskForm = { who: null, name: null };
    pfRender();
  };

  if (el("pftaskcancel")) el("pftaskcancel").onclick = function(){
    PF.taskForm = null; pfRender();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pftf]"), function(f){
    f.onchange = function(){ PF.taskForm[f.getAttribute("data-pftf")] = f.value; };
    f.oninput  = function(){ PF.taskForm[f.getAttribute("data-pftf")] = f.value; };
  });

  if (el("pftasksave")) el("pftasksave").onclick = async function(){
    if (PF.busy) return;
    var f = PF.taskForm;
    if (!f.title) { PF.says = msg("bad", "A task needs a sentence saying what is being asked for."); pfRender(); return; }
    PF.busy = true; el("pftasksave").disabled = true;
    var body = { title: f.title, detail: f.detail || null, dueOn: f.dueOn || null,
                 attributeWeight: f.attributeWeight || null };
    if (f.who) {
      body.people = [f.who];
    } else {
      var picked = Object.keys(PF.sel).filter(function(k){ return PF.sel[k]; });
      if (picked.length) body.people = picked; else body.allReports = true;
    }
    var o = await perfApi("/perf/task/assign", { method:"POST", body: body });
    PF.busy = false;
    if (o.error) {
      PF.says = msg("bad", o.reason || o.error);
    } else {
      var refused = (o.refused || []).length;
      PF.says = msg(refused ? "warn" : "ok",
        o.created + (o.created === 1 ? " task set" : " tasks set") + " for " + o.period +
        (refused ? ". " + refused + " refused: " + (o.refused || []).join(", ") + ". " + (o.note || "") : "."));
    }
    PF.taskForm = null;
    PF.tasks = await perfApi("/perf/task/mine?period=" + PF.period.slice(0,7));
    pfRender();
  };

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pfdone]"), function(b){
    b.onclick = async function(){
      if (PF.busy) return;
      PF.busy = true; b.disabled = true;
      var o = await perfApi("/perf/task/close", { method:"POST",
        body:{ id: b.getAttribute("data-pfdone") } });
      PF.busy = false;
      PF.says = o.error ? msg("bad", o.reason || o.error)
        : msg(o.status === "LATE" ? "warn" : "ok",
            o.status === "LATE"
              ? "Closed, but after " + day(o.dueOn) + ", so it stands as late."
              : "Closed on time.");
      PF.tasks = await perfApi("/perf/task/mine?period=" + PF.period.slice(0,7));
      pfRender();
    };
  });

  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pfcancel]"), function(b){
    b.onclick = async function(){
      if (PF.busy) return;
      var why = prompt("Why is this being called off? It goes on the record.");
      if (why === null) return;
      PF.busy = true; b.disabled = true;
      var o = await perfApi("/perf/task/cancel", { method:"POST",
        body:{ id: b.getAttribute("data-pfcancel"), why: why } });
      PF.busy = false;
      PF.says = o.error ? msg("bad", o.reason || o.error) : msg("ok", "Called off.");
      PF.tasks = await perfApi("/perf/task/mine?period=" + PF.period.slice(0,7));
      pfRender();
    };
  });

  /* ----------------------------------------------------- the eligibility */
  if (el("pfelig")) el("pfelig").onclick = function(){ PF.elig = true; pfRender(); };
  if (el("pfeligclose")) el("pfeligclose").onclick = function(){ PF.elig = false; pfRender(); };

  /* ------------------------------------------------------- the weighting */
  if (el("pfweight")) el("pfweight").onclick = function(){
    var w = (PF.weighting.mine || {});
    PF.weightForm = { kpiPercent: w.kpiPercent || 75, attrPercent: w.attrPercent || 25,
                      effectiveFrom: "" };
    pfRender();
  };
  if (el("pfweightcancel")) el("pfweightcancel").onclick = function(){
    PF.weightForm = null; pfRender();
  };
  Array.prototype.forEach.call(el("view").querySelectorAll("[data-pfwf]"), function(f){
    f.onchange = function(){ PF.weightForm[f.getAttribute("data-pfwf")] = f.value; };
    f.oninput  = function(){ PF.weightForm[f.getAttribute("data-pfwf")] = f.value; };
  });
  if (el("pfweightsave")) el("pfweightsave").onclick = async function(){
    if (PF.busy) return;
    PF.busy = true; el("pfweightsave").disabled = true;
    var o = await perfApi("/perf/weighting", { method:"POST", body: PF.weightForm });
    PF.busy = false;
    PF.says = o.error ? msg("bad", o.reason || o.error) : msg("ok", o.note);
    PF.weightForm = null;
    PF.weighting = await perfApi("/perf/weighting");
    pfRender();
  };

  /* The appraisal section is the Bonus screen's own renderers, so it is the
     Bonus screen's own wiring. Guarded because every one of those handlers
     tests for its element first, and most of them are not on this page. */
  try { if ((PF.plb || {}).sheet) pbWire(); } catch (e) {}
}
