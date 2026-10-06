/* =====================================================================
   The floating question mark.

   "There is a lot of explanatory or helping text making this tool all
   cluttered, move all that to a floating question mark button, which will
   give explanation of the open screen and tab."

   Two halves, and the second is the one that makes this work at all.

   WRITTEN. HELP holds a short piece per screen: what it is for, and what
   you actually do on it, as steps. That is the part worth reading, and it
   is the part no screen currently says -- the prose on the screens
   explains individual decisions, never the journey.

   COLLECTED. Every long explanatory paragraph already on a screen is
   moved here at render time rather than deleted. A MutationObserver
   watches #view; after each draw it finds the paragraphs that are prose
   rather than labels, hides them, and stacks them in the panel under
   "Also on this screen".

   Collecting rather than editing is deliberate. The application is one row
   of app_page, 378 kilobytes of it, and the explanatory text is spread
   through dozens of string concatenations. Editing each by hand would be
   dozens of chances to break a screen, and every new paragraph anybody
   adds later would be back on the page. A rule applied at render time
   covers the screens that exist, the screens in app_page this file has
   never seen, and the screens nobody has written yet.

   WHAT IS NOT COLLECTED, and why each one stays:
     - anything under 100 characters, which is a label or a hint, not prose
     - .msg, which is how the tool says something went wrong or right
     - .empty, which is a screen saying why it has nothing on it
     - anything inside an open form, where the guidance is about the box
       the person is typing into at that moment
   ===================================================================== */

var QH = { open:false, moved:[], tab:null };

/* Per screen: a sentence on what it is for, then the steps. Deliberately
   short. A help panel nobody finishes reading is the clutter moved, not
   removed. */
var HELP = {
  today: { t:"Dashboard",
    w:"Everything waiting on you today, in one place.",
    s:["Read the tiles across the top — those are the numbers your chair is judged on.",
       "Work down the list below them. Anything with a button is something only you can clear.",
       "Nothing here is a report. If a figure looks wrong, open the screen it came from."] },

  perf: { t:"Performance & appraisal",
    w:"Your measures, your team's, and the bonus they add up to.",
    s:["File your own numbers at the top, on the cadence you were given.",
       "Under My team, open a person to set their targets, change what they are measured on, or assign a task.",
       "You cannot set your own. Your manager sets yours, the same way you set your team's.",
       "The quarterly scorecard at the foot is the same numbers, totalled and turned into money."],
    j:true },

  plb: { t:"Running the scheme",
    w:"Issuing goal sheets, certifying a quarter, and closing it.",
    s:["Issue a sheet to everyone in the scheme at the start of a quarter.",
       "Each month, score the people who have self-evaluated.",
       "At the end of the quarter, pull the actuals from what was filed, certify, then publish.",
       "Publishing is what makes the amount real. Nothing is paid before it."],
    j:true },

  people: { t:"My team & structure",
    w:"Who reports to whom, and the things you do about a person rather than a number.",
    s:["Drag a card onto another to move that person under them.",
       "Open a card for their measures, their record, and a review.",
       "Add somebody new, or pull across somebody who already works here.",
       "A move is recorded. It changes who may set that person's targets from that moment.",
       "All people is the same company as a list, for the administrator and HR. " +
       "It is the only place somebody who reports to nobody can be seen — " +
       "a chart cannot draw an absence.",
       "The chips on that list count the gaps. Press one and you are looking " +
       "at the people it counted."] },

  cases: { t:"Escalations",
    w:"Things that went wrong at a branch, and what is being done about them.",
    s:["Raise one when the outcome is decided, not when it is alleged.",
       "Every escalation has an owner and a clock. The clock is the client's, not ours.",
       "Closing one needs a reason, because the reason is what the client is told."] },

  ogl: { t:"OGL Assignment",
    w:"Work allotted out, and whether it came back inside the agreed time.",
    s:["Assign, then watch the SLA column.",
       "At risk means it will breach if nothing changes today.",
       "A breach is not deleted. It is explained."] },

  clients: { t:"Clients",
    w:"The banks, their branches, and who to contact at each.",
    s:["A branch sits under a client and has one escalation contact chain.",
       "The chain is what Escalation matrix sends to each month."] },

  matrix: { t:"Escalation matrix",
    w:"The monthly statement that goes to each client, naming who to call.",
    s:["Check the contacts, then despatch.",
       "What went out is kept. A contact changed afterwards does not rewrite last month."] },

  visits: { t:"Visits & claims",
    w:"Where you went, and what it cost.",
    s:["File the visit, then the claim against it.",
       "A claim with no visit behind it is the thing this screen exists to prevent."] },

  hiring: { t:"Hiring & pending chairs",
    w:"Chairs with nobody in them, and requests to fill one.",
    s:["A manager asks. Human Resources decides and makes the account.",
       "An approved request becomes a person, a chair and a sign-in in one step."] },

  joining: { t:"Joining",
    w:"People who have accepted and not yet started.",
    s:["Everything that must be true on day one, as a list.",
       "The welcome e-mail goes out when the account is made, not when the list is finished."] },

  hr:    { t:"HR",  w:"The people record: joiners, leavers, and what changed.",
    s:["Human Resources runs the scheme and the records.",
       "Setting a named person's KPIs and targets is their own manager's, not HR's."] },

  reports:{ t:"Reports", w:"The numbers, as tables you can take away.",
    s:["Pick the period first. Everything below it follows.",
       "A report is a view of what was filed. It changes nothing."] },

  history:{ t:"History & audit trail", w:"Who did what, and when.",
    s:["Every change that matters writes a row here, naming the person who made it.",
       "This is the answer to “who moved this”, and it cannot be edited."] },

  profile:{ t:"My profile", w:"Your own record, and your sign-in.",
    s:["Change your password here.",
       "Anything you cannot edit is held by Human Resources."] },

  config: { t:"Settings", w:"How the tool behaves for everybody.",
    s:["These are company-wide. A change here is felt by every user.",
       "Every change is written to History & audit trail against your name."] }
};

/* The journey the owner said was confusing, said once, in order. It is
   attached to the two screens it spans rather than repeated on each. */
var HELP_JOURNEY = [
  ["Every day",    "You file your figures against the measures you were given. Nothing is scored yet — these are facts."],
  ["Each month",   "You self-evaluate: you say how the month went, out of 10. Then your manager scores you, out of 10, seeing what you filed and what you said. Three quarters of that score is the KPIs, one quarter is the attributes."],
  ["Each quarter", "The quarterly scorecard adds up what was actually filed against what was agreed. That part is arithmetic, not judgement — nobody types it in."],
  ["Then",         "Achievement × the payout curve × the consistency of your monthly scores = the bonus. It is certified, then published. Published is the point at which it is real."]
];

function qhIcon(){
  return '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" ' +
    'stroke="currentColor" stroke-width="2.4" stroke-linecap="round">' +
    '<path d="M9.1 9a3 3 0 1 1 4.2 2.8c-.8.4-1.3 1.1-1.3 2v.4"/>' +
    '<circle cx="12" cy="17.6" r="1.1" fill="currentColor" stroke="none"/></svg>';
}

function qhBody(){
  var tab = (typeof currentTab === "function") ? currentTab() : "today";
  var h = HELP[tab];
  var title = h ? h.t : ((typeof LABEL === "object" && LABEL[tab]) || "This screen");

  var out = '<div class="qhhead"><h2>' + esc(title) + '</h2>' +
    '<button class="qhx" id="qhclose" aria-label="Close">×</button></div>';

  if (h) {
    out += '<p class="qhwhat">' + esc(h.w) + '</p>';
    out += '<h3>What you do here</h3><ol class="qhsteps">' +
      h.s.map(function(x){ return '<li>' + esc(x) + '</li>'; }).join("") + '</ol>';
    if (h.j) {
      out += '<h3>How a score becomes a bonus</h3><dl class="qhjourney">' +
        HELP_JOURNEY.map(function(p){
          return '<dt>' + esc(p[0]) + '</dt><dd>' + esc(p[1]) + '</dd>';
        }).join("") + '</dl>';
    }
  } else {
    out += '<p class="qhwhat">There is no written guide for this screen yet. ' +
      'Anything the screen itself explains is below.</p>';
  }

  if (QH.moved.length) {
    out += '<h3>Also on this screen</h3>' +
      '<div class="qhmoved">' + QH.moved.map(function(x){
        return '<p>' + x + '</p>'; }).join("") + '</div>';
  }

  out += '<p class="qhfoot">Crux · Crux Risk Management Pvt. Ltd.</p>';
  return out;
}

function qhPaint(){
  var p = el("qhpanel");
  if (!p) return;
  p.innerHTML = qhBody();
  if (el("qhclose")) el("qhclose").onclick = qhToggle;
}

function qhToggle(){
  QH.open = !QH.open;
  var p = el("qhpanel"), s = el("qhscrim"), b = el("qhbtn");
  if (!p) return;
  if (QH.open) qhPaint();
  p.classList.toggle("on", QH.open);
  if (s) s.classList.toggle("on", QH.open);
  if (b) b.setAttribute("aria-expanded", QH.open ? "true" : "false");
}

/* Prose, or a label? Length decides, because every other test needs the
   author to have marked it and none of them did. 100 characters is about
   a line and a half: long enough that no unit, count or hint reaches it,
   short enough that nothing anybody would call an explanation escapes. */
function qhIsProse(n){
  if (n.getAttribute("data-qh")) return false;
  if (n.closest(".plform, .hraform, .qhpanel")) return false;
  return (n.textContent || "").trim().length >= 100;
}

function qhCollect(){
  var v = el("view");
  if (!v) return;
  QH.moved = [];
  var ns = v.querySelectorAll("p.mute, .plsub > p, p.hint");
  Array.prototype.forEach.call(ns, function(n){
    if (!qhIsProse(n)) return;
    n.setAttribute("data-qh", "1");
    n.style.display = "none";
    QH.moved.push(n.innerHTML);
  });
  var b = el("qhbtn");
  if (b) b.classList.toggle("has", QH.moved.length > 0);
  if (QH.open) qhPaint();
}

function qhMount(){
  if (el("qhbtn")) return;
  var scrim = document.createElement("div");
  scrim.id = "qhscrim";
  scrim.onclick = function(){ if (QH.open) qhToggle(); };

  var panel = document.createElement("aside");
  panel.id = "qhpanel";
  panel.className = "qhpanel";

  var btn = document.createElement("button");
  btn.id = "qhbtn";
  btn.type = "button";
  btn.title = "What is this screen for?";
  btn.setAttribute("aria-label", "What is this screen for?");
  btn.setAttribute("aria-expanded", "false");
  btn.innerHTML = qhIcon();
  btn.onclick = qhToggle;

  document.body.appendChild(scrim);
  document.body.appendChild(panel);
  document.body.appendChild(btn);

  document.addEventListener("keydown", function(e){
    if (e.key === "Escape" && QH.open) qhToggle();
  });

  /* No router hook. The observer catches every draw, including the ones
     that finish after an await and the ones on screens this file has
     never heard of. Debounced, because a screen that renders in three
     passes should collect once. */
  var v = el("view");
  if (v && window.MutationObserver) {
    var t = null;
    new MutationObserver(function(){
      clearTimeout(t);
      t = setTimeout(qhCollect, 80);
    }).observe(v, { childList:true, subtree:true });
  }
  qhCollect();
}

/* Mounted when #view exists, which is after sign-in. Before that there is
   one box asking for a password and nothing a help panel could usefully
   say about it. Polled rather than hooked to a boot function, so this
   needs no anchor in a page it cannot see. */
(function qhBoot(){
  var tries = 0;
  function go(){
    if (el("view")) { qhMount(); return; }
    if (++tries > 60) return;
    setTimeout(go, 400);
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", go);
  } else { go(); }
})();
