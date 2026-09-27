"""Insert the project-key shim into the fetched application and write index.html.

Kept out of the workflow file because a heredoc inside a YAML block scalar is
how the first version of this broke: the inner document dedented to column
zero and took the YAML with it.

It also applies correctness patches on the way past. Every one of them
belongs in app_page and has a migration written for it; they are applied
here as well because app_page could not be reached while people were locked
out of the tool, and because a republish must never quietly undo them. Each
is idempotent and each asserts the exact number of call sites it expects, so
the build fails loudly rather than publishing a page it did not understand.
"""
import io
import sys

app = io.open("app.raw", encoding="utf-8").read()
shim = io.open("shim.html", encoding="utf-8").read()

PATCHES = []

# ------------------------------------------------------------ 1. STORAGE
# localStorage THROWS rather than returning null when a browser refuses site
# data: a private window, blocked cookies, some managed-device policies. The
# application reads it in the FIRST statement of its script, so the throw
# took the whole file with it -- nothing after that line ran, including the
# line that wires the Sign in button and the call to boot(). What was left
# on screen was the sign-in card, which is static HTML, with a button
# attached to nothing.
#
# Reproduced in Chromium with storage blocked: one "The operation is
# insecure." and el("go").onclick undefined.
PATCHES.append((
    "storage guards",
    'function aaGet(',
    [('var token = localStorage.getItem("cruxToken") || "";',
      'function aaGet(k){ try { return localStorage.getItem(k); } catch (e) { return null; } }\n'
      'function aaSet(k, v){ try { localStorage.setItem(k, v); } catch (e) { /* memory only */ } }\n'
      'function aaDrop(k){ try { localStorage.removeItem(k); } catch (e) { /* nothing to do */ } }\n'
      'var token = aaGet("cruxToken") || "";', 1),
     ('localStorage.setItem("cruxToken", token);', 'aaSet("cruxToken", token);', 2),
     ('token=""; localStorage.removeItem("cruxToken"); me=null;',
      'token=""; aaDrop("cruxToken"); aaDrop("cruxAdminToken"); me=null;', 1)],
))

# --------------------------------------------------------- 2. THE GSI RACE
# The Google library is loaded with <script async defer>, and boot() tested
# for it exactly ONCE:
#
#     if (cfg.googleClientId && window.google && google.accounts) { ... }
#     else { ghint = "Google sign-in is still loading, or is not configured yet." }
#
# There is no retry behind that message. Whether the Google button appeared
# at all came down to which of two network requests won a race -- /api/config,
# which boot() awaits, against accounts.google.com/gsi/client. On a cold
# cache or a slow link the library loses, the else branch runs, and the
# button never renders: "still loading" is a permanent state, not a
# transient one. That is why sign-in worked on some page loads and not
# others, with nothing different about the account.
#
# Confirmed from a screen recording: that exact sentence on screen, no
# Google button, and a reload minutes later showing the button fine.
PATCHES.append((
    "google sign-in race",
    "function gsiReady(",
    [('async function boot(){',
      '/* Wait for the Google library rather than testing for it once. It is\n'
      '   loaded async, so on a cold cache boot() reached the check first and\n'
      '   wrote "still loading" as a final answer with no retry behind it. */\n'
      'function gsiReady(ms){\n'
      '  var deadline = Date.now() + (ms || 8000);\n'
      '  return new Promise(function(done){\n'
      '    (function poll(){\n'
      '      if (window.google && google.accounts && google.accounts.id) return done(true);\n'
      '      if (Date.now() > deadline) return done(false);\n'
      '      setTimeout(poll, 60);\n'
      '    })();\n'
      '  });\n'
      '}\n\n'
      'async function boot(){', 1),
     ('  if (cfg.googleClientId && window.google && google.accounts) {',
      '  if (cfg.googleClientId) { await gsiReady(8000); }\n'
      '  if (cfg.googleClientId && window.google && google.accounts) {', 1),
     ('    el("ghint").textContent = "Google sign-in is still loading, or is not configured yet.";',
      '    el("ghint").textContent = cfg.googleClientId\n'
      '      ? "Google sign-in did not load. Reload the page; if it keeps happening, "\n'
      '        + "tell your administrator \\u2014 nothing is wrong with your account."\n'
      '      : "Google sign-in is not configured yet.";', 1)],
))

# ------------------------------------------------- 3. THE PASSWORD BOX LIES
# No account in Crux has a password -- 635 active people, zero hashes -- so
# /api/login cannot succeed for anybody. The box is furniture, and when
# Google fails it is the only thing left to try, so people try it.
#
# Worse, Chrome's password manager fills the WORK E-MAIL box with whatever
# it stored as the username for this site, which on the recording was the
# company name: "Crux Risk Management Pvt Ltd". That is sent to the server
# and comes back as a flat refusal, which reads as "my password is wrong".
#
# So: refuse a value that is not an address before spending a round trip on
# it, and when the server does refuse, say why nobody can get in this way.
PATCHES.append((
    "password box tells the truth",
    "not an e-mail address",
    [('    var out = await crux("/api/login", { method:"POST",\n'
      '      body:{ email: el("em").value.trim(), password: el("pw").value } });\n'
      '    if (out.error) { el("loginMsg").innerHTML = msg("bad", out.reason || out.error); return; }',
      '    var em = el("em").value.trim();\n'
      '    if (!/^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$/.test(em)) {\n'
      '      el("loginMsg").innerHTML = msg("bad", "That is not an e-mail address. Your "\n'
      '        + "browser has probably filled this box with a saved name rather than an "\n'
      '        + "address. Clear it and type your work address.");\n'
      '      return;\n'
      '    }\n'
      '    var out = await crux("/api/login", { method:"POST",\n'
      '      body:{ email: em, password: el("pw").value } });\n'
      '    if (out.error) { el("loginMsg").innerHTML = msg("bad", (out.reason || out.error)\n'
      '      + " No Crux account has a password set, so this box cannot let anyone in. "\n'
      '      + "Use the Google button above."); return; }', 1)],
))

# ------------------------------------- 4. ONE 401 SIGNED EVERYBODY OUT
# call() ended with:
#
#     if (r.status === 401) { signOut(); }
#
# Any 401, from any service, destroyed the session and threw the person
# back to the sign-in screen. That is right for our own session check and
# wrong for everything else.
#
# `plb` and `hr` were deployed with Supabase's gateway JWT verification
# left ON -- they are the only two app-facing functions where it is; crux,
# api, org, ops, cfg, kpi and wa are all off. The gateway therefore rejects
# those two with 401 BEFORE the function runs, and the page cannot satisfy
# it: the project key is appended as a query parameter precisely because
# adding an Authorization header would trip the CORS preflight every other
# function depends on.
#
# So signing in with the URL left on #plb went: sign-in succeeds, session
# created, route() draws the PLB screen, plb() returns a gateway 401,
# signOut() fires, and you are back on the login page before anything
# rendered. Server-side it looks like a clean successful login, which is
# exactly what login_attempt showed.
#
# The real fix is to redeploy those two functions with verify_jwt off. This
# makes the page survive until then, and stops any one misconfigured
# service from ever locking somebody out of all the others.
PATCHES.append((
    "a foreign 401 no longer signs out",
    "service_unreachable",
    [('  if (r.status === 401) { signOut(); }',
      '  /* Our own session check saying "not signed in" is a reason to sign out.\n'
      '     A gateway refusing a single service is not: it says nothing about the\n'
      '     session, and treating it as if it did is how one misconfigured\n'
      '     function locked everybody out of the whole tool. */\n'
      '  if (r.status === 401) {\n'
      '    if (b && (b.error === "not_signed_in" || b.error === "sign_in_required")) {\n'
      '      signOut();\n'
      '    } else if (b && !b.error) {\n'
      '      b.error = "service_unreachable";\n'
      '      b.reason = "That part of the tool refused the request before it arrived. "\n'
      '        + "It is nothing to do with your sign-in, and nothing else is affected.";\n'
      '    }\n'
      '  }', 1)],
))

# ----------------------------------- 5. EVERY CHAIR SAW EVERY SCREEN
# The v2 design gives each chair its own navigation and one of eight scope
# levels. The tool shipped one flat list of 21 screens to everybody, so an
# administrator looking at Crux as a Field Executive found Penalty ledger,
# Data setup and Settings on a screen the design gives seven entries.
#
# allowed() only ever asked two questions -- is this one of three admin
# tabs, and is Settings allowed -- so every other screen was open to
# everyone who could sign in.
#
# READ THIS BEFORE TRUSTING IT. Hiding a screen is not a permission check.
# It stops somebody wandering into a screen that is not theirs; it does not
# stop somebody typing the URL, and it is not what keeps anybody's data
# safe. The real check belongs in the services, per endpoint, and that work
# is listed in build/SECURITY_scope.md. This closes what the owner actually
# saw and makes the navigation match the design; it does not close the
# underlying hole, and saying otherwise would be worse than the hole.
PATCHES.append((
    "each chair sees its own screens",
    "CHAIR_LEVEL",
    [('function allowed(key){\n'
      '  if (key === "config") {\n'
      '    return !!me && (me.app_role === "ADMIN" ||\n'
      '      me.department === "Human Resources" || me.department === "Finance & Accounts");\n'
      '  }\n'
      '  return !ADMIN_TABS[key] || (me && me.app_role === "ADMIN");\n'
      '}',
      '/* --------------------------------------------------------------- access\n'
      '   The v2 design gives every chair its own navigation and one of eight\n'
      '   scope levels. This is that table, keyed on the chair title the\n'
      '   session already returns.\n'
      '\n'
      '   It decides what appears in the navigation and what currentTab() will\n'
      '   open. It is NOT the permission check. Every service decides for\n'
      '   itself and refuses in its own words; hiding a screen stops somebody\n'
      '   wandering into it and does nothing about somebody typing the URL. */\n'
      'var SCREENS = {\n'
      '  exec:    ["today","ogl","cases","pms","plb","visits","ideas","profile"],\n'
      '  team:    ["today","ogl","cases","pms","plb","people","visits","ideas","profile"],\n'
      '  branch:  ["today","ogl","cases","pms","plb","clients","people","hiring","joining",\n'
      '            "visits","ideas","reports","history","profile"],\n'
      '  partner: ["today","ogl","cases","pms","plb","clients","people","hiring","joining",\n'
      '            "visits","ideas","penalties","reports","history","profile"],\n'
      '  hr:      ["today","cases","pms","plb","people","hr","hiring","joining","visits",\n'
      '            "ideas","penalties","reports","history","mail","auto","config","profile"],\n'
      '  finance: ["today","cases","pms","plb","clients","people","hiring","visits","ideas",\n'
      '            "penalties","reports","history","auto","config","profile"],\n'
      '  analytics:["today","cases","pms","plb","people","ideas","data","coverage","reports",\n'
      '            "history","profile"],\n'
      '  staff:   ["today","cases","pms","plb","people","clients","visits","ideas","reports",\n'
      '            "history","profile"]\n'
      '};\n'
      '\n'
      '/* Branch, region and national carry the same list in the design; what\n'
      '   differs between them is how far they SEE, which is the service\'s\n'
      '   question, not this one. */\n'
      'var CHAIR_LEVEL = {\n'
      '  "Executive":"exec", "Field Executives / Verifiers":"exec",\n'
      '  "Back Office / Processing Executives":"exec",\n'
      '  "Branch Collection Executive":"exec", "Central Collections Executives":"exec",\n'
      '  "Team Leader / Supervisor":"team", "Partner Team Leader / Supervisor":"team",\n'
      '  "Branch Manager":"branch", "Zonal Manager":"branch", "Regional Manager":"branch",\n'
      '  "Assistant Vice President":"branch", "Head \\u2014 Operations":"branch",\n'
      '  "Operations Head":"branch", "Sales Manager":"branch",\n'
      '  "Location Partner / Franchisee Partner":"partner",\n'
      '  "Head \\u2014 HR Operations":"hr", "HR Executive":"hr",\n'
      '  "Head \\u2014 Human Resources":"hr", "HR Operations":"hr",\n'
      '  "Head \\u2014 Finance Operations":"finance", "Finance Head":"finance",\n'
      '  "Vice President":"finance", "Accounts":"finance",\n'
      '  "MIS & Business Analytics":"analytics",\n'
      '  "Business Excellence & PMO":"staff", "Assurance, Risk & Compliance":"staff",\n'
      '  "Legal & Compliance":"staff", "Company Secretary":"staff",\n'
      '  "Chief Executive Officer / Managing Director":"admin", "Managing Director":"admin"\n'
      '};\n'
      '\n'
      '/* A screen reached from inside a parent follows its parent. */\n'
      'var UNDER = { matrix:"clients", org:"people", whatsapp:"mail",\n'
      '              mis:"reports", tenday:"reports", rates:"reports", access:"reports" };\n'
      '\n'
      'function myLevel(){\n'
      '  if (!me) return "exec";\n'
      '  if (me.app_role === "ADMIN") return "admin";\n'
      '  var byChair = CHAIR_LEVEL[me.chair_title || ""];\n'
      '  if (byChair) return byChair;\n'
      '  /* No chair, or a chair nobody has classified yet: fall back on the\n'
      '     department, and failing that on the smallest list there is. A\n'
      '     person the tool cannot place should see less, not more. */\n'
      '  var d = me.department || "";\n'
      '  if (d === "Human Resources") return "hr";\n'
      '  if (d === "Finance & Accounts" || d === "Finance") return "finance";\n'
      '  if (d === "MIS") return "analytics";\n'
      '  return "exec";\n'
      '}\n'
      '\n'
      'function allowed(key){\n'
      '  if (!me) return false;\n'
      '  var lvl = myLevel();\n'
      '  if (lvl === "admin") return true;\n'
      '  var list = SCREENS[lvl] || SCREENS.exec;\n'
      '  var k = UNDER[key] || key;\n'
      '  return list.indexOf(k) > -1;\n'
      '}', 1)],
))

# ------------------------------- 6. ONE PERFORMANCE SCREEN, AND THE MONTH
# The navigation offered "Performance & appraisal" and "Performance & bonus"
# as two separate top-level entries. The design has one. Somebody looking for
# their bonus had to already know that bonus lives under the second
# Performance and not the first, which is not a thing anybody knows.
#
# So: one entry, "Performance", with the monthly screen as its face and the
# two existing screens kept as sub-tabs underneath it. Nothing is deleted --
# #pms and #plb still route, still work, and are now reachable without
# guessing which of two identically-named tabs to press.
#
# The new face is the monthly cycle the owner asked for: a manager sets the
# measures and the targets inside the window, the person files on the cadence
# they were given, and the numbers climb. It is one file, build/app/screen-
# perf.js, read from the repository rather than pasted here, so the screen can
# be read and reviewed as JavaScript instead of as Python string literals.
SCREEN_PERF = io.open("build/app/screen-perf.js", encoding="utf-8").read()

PATCHES.append((
    "one Performance screen",
    "function pfRender(",
    [# the screen's own styles, beside the ones it borrows
     ('.hrawarn{color:var(--gold-ink);font-size:12px;line-height:1.45}',
      '.hrawarn{color:var(--gold-ink);font-size:12px;line-height:1.45}\n'
      '/* ------------------------------------------------------------------ perf\n'
      '   A tree that opens, a bar that stops at 100 even when the number does\n'
      '   not, and a banner that says which of the two windows is still open.\n'
      '   The numbers are tabular so a column of them reads as a column.     */\n'
      '.pfperiod select{min-height:36px}\n'
      '.pftabs{display:flex;gap:8px;margin:0 0 14px}\n'
      '/* .chip paints itself with var(--ink2), which this sheet never\n'
      '   defines, so the count inherits the button\'s colour -- white on\n'
      '   near-white once the tab is selected, which is a count nobody can\n'
      '   read. Both states are stated here. */\n'
      '.pftabs .chip{color:var(--ink);margin-left:6px}\n'
      '.pftabs .primary .chip{background:rgba(255,255,255,.18);\n'
      '  border-color:rgba(255,255,255,.5);color:#fff}\n'
      '.pfwin{margin:0 0 14px;padding:8px 12px;background:var(--green-bg);\n'
      '  border-left:3px solid var(--green);font-size:13px;color:var(--body)}\n'
      '.pfwin.shut{background:var(--terra-bg);border-left-color:var(--terra);color:var(--terra-ink)}\n'
      '.pftree{padding:2px 0 8px}\n'
      '.pfrow{display:flex;align-items:center;gap:8px;padding:7px 15px;\n'
      '  border-top:1px solid var(--line3);font-size:13px}\n'
      '/* The page gives every button a 46px minimum and a blue hover. A\n'
      '   disclosure triangle is not that kind of button, so both are said\n'
      '   again here -- the hover included, because button:hover outranks a\n'
      '   plain class and would otherwise paint this one navy mid-click. */\n'
      '.pftog{width:20px;height:20px;min-height:20px;flex:0 0 20px;\n'
      '  border:1px solid var(--line);background:var(--white);color:var(--mute);\n'
      '  font-size:12px;line-height:1;cursor:pointer;border-radius:3px;padding:0}\n'
      '.pftog:hover{background:var(--panel);color:var(--ink);border-color:var(--field)}\n'
      '.pftog.pfnone{border:none;background:none}\n'
      '.pfname{flex:1 1 auto;min-width:0;color:var(--ink);overflow:hidden;\n'
      '  text-overflow:ellipsis;white-space:nowrap}\n'
      '.pfwho{font-weight:600}\n'
      '.pfval{flex:0 0 96px;text-align:right;color:var(--ink);font-variant-numeric:tabular-nums}\n'
      '.pftgt{flex:0 0 96px;text-align:right;color:var(--mute);font-variant-numeric:tabular-nums}\n'
      '.pfpct{flex:0 0 52px;text-align:right;color:var(--body);font-variant-numeric:tabular-nums}\n'
      '.pfmeter{flex:0 0 90px}\n'
      '.pfbar{height:6px;background:var(--line2);border-radius:3px;overflow:hidden}\n'
      '.pfbar i{display:block;height:100%}\n'
      '.pfbar i.ok{background:var(--green)}\n'
      '.pfbar i.warn{background:var(--gold)}\n'
      '.pfbar i.bad{background:var(--terra)}\n'
      'input.pfin{width:120px}\n'
      '/* input{width:100%;min-height:44px} in the base sheet catches\n'
      '   checkboxes as well as text boxes, which is why a tick elsewhere in\n'
      '   the tool is a 44px-tall square. Here it is a tick.              */\n'
      '.pfsel{display:inline-flex;align-items:center;gap:5px;margin-right:10px;\n'
      '  font-size:12px;color:var(--mute);white-space:nowrap;vertical-align:middle}\n'
      '.pfsel input[type=checkbox]{width:15px;height:15px;min-height:0;padding:0;\n'
      '  margin:0;flex:0 0 15px;accent-color:var(--blue)}\n'
      '.pfpanel{padding:2px 0 6px}\n'
      '@media (max-width:720px){\n'
      '  .pfrow{flex-wrap:wrap}\n'
      '  .pftgt,.pfmeter{display:none}\n'
      '}', 1),
     # the two entries become one
     ('["pms","Performance & appraisal"], ["plb","Performance & bonus"], ',
      '["perf","Performance"], ', 1),
     # and the old two keep their routes, as sub-tabs under it
     ('var FAMILY = [\n'
      '  ["clients", [["clients","Clients"], ["matrix","Escalation matrix"]]],',
      'var FAMILY = [\n'
      '  ["perf",    [["perf","This month"], ["pms","Appraisal"], ["plb","Bonus"]]],\n'
      '  ["clients", [["clients","Clients"], ["matrix","Escalation matrix"]]],', 1),
     # every chair that could see the two can see the one
     ('"pms","plb",', '"perf",', 8),
     # reaching #pms or #plb directly is reaching Performance
     ('var UNDER = { matrix:"clients", org:"people", whatsapp:"mail",',
      'var UNDER = { matrix:"clients", org:"people", whatsapp:"mail",\n'
      '              pms:"perf", plb:"perf",', 1),
     # the router learns the new face
     ('pms:vPms, plb:vPlb,', 'pms:vPms, plb:vPlb, perf:vPerf,', 1),
     # and the face itself goes in ahead of the first screen
     ('/* --------------------------------------------------------------- today */',
      SCREEN_PERF.rstrip() + '\n\n'
      '/* --------------------------------------------------------------- today */', 1)],
))

# ----------------------------- 7. THE MATRIX NOBODY COULD SEE GOING OUT
# The tool held the escalation matrix and chased the branches missing a
# level. It had nowhere at all for the monthly act: the pack that goes to
# the client, who it went to, when, and what it said at the moment it left.
# A branch manager could keep five levels filled for a year and never once
# be told whether the client had been sent them.
#
# Two entrances, because it is one question asked in two places: a line on
# the dashboard that says whether this month has gone out, and the section
# on the Escalation matrix screen that it goes out from.
SCREEN_MATRIX = io.open("build/app/screen-matrix-month.js", encoding="utf-8").read()

PATCHES.append((
    "the matrix that goes out",
    "function mxMonthLoad(",
    [# a fifth front door. `api` is at the size a deploy will carry and
     # `ops` serves six screens that work, so the despatch got its own
     # rather than every one of those being re-uploaded to add one route.
     ('var PLB  = "https://oxpwqfbtbxlvuqpztbwg.supabase.co/functions/v1/plb";\n'
      'var plb  = function(p,o){ return call(PLB,  p, o); };',
      'var PLB  = "https://oxpwqfbtbxlvuqpztbwg.supabase.co/functions/v1/plb";\n'
      'var plb  = function(p,o){ return call(PLB,  p, o); };\n'
      'var PACK = "https://oxpwqfbtbxlvuqpztbwg.supabase.co/functions/v1/pack";\n'
      'var packApi = function(p,o){ return call(PACK, p, o); };', 1),
     # the styles it needs that the page does not already have
     ('.hrabad{color:var(--terra-ink);font-size:12px;line-height:1.45}',
      '.hrabad{color:var(--terra-ink);font-size:12px;line-height:1.45}\n'
      '/* ---------------------------------------------------------- matrix\n'
      '   The monthly pack. A letter somebody is about to send should look\n'
      '   like a letter before they send it.                              */\n'
      '.mxline{margin:10px 15px;padding:8px 12px;font-size:13px;border-left:3px solid var(--line)}\n'
      '.mxline.due{background:var(--gold-bg);border-left-color:var(--gold);color:var(--gold-ink)}\n'
      '.mxline.done{background:var(--green-bg);border-left-color:var(--green);color:var(--body)}\n'
      '.mxlist{margin:6px 15px 10px 32px;padding:0;font-size:13px;color:var(--body)}\n'
      '.mxlist li{margin:2px 0}\n'
      '.mxpack{padding:4px 0 10px}\n'
      '.mxsays{margin:0 15px 6px;font-size:13px;color:var(--body)}\n'
      '.mxrecs{display:flex;flex-wrap:wrap;gap:8px 18px;padding:2px 15px 8px}\n'
      '.mxrec{display:inline-flex;align-items:center;gap:6px;font-size:13px;\n'
      '  white-space:nowrap;color:var(--body)}\n'
      '.mxrec input[type=checkbox]{width:15px;height:15px;min-height:0;padding:0;\n'
      '  margin:0;flex:0 0 15px;accent-color:var(--blue)}\n'
      '.mxbranches{padding:0 15px 6px}\n'
      '.mxb{border-top:1px solid var(--line3);padding:6px 0}\n'
      '.mxb summary{cursor:pointer;font-size:13px;color:var(--ink)}\n'
      '.mxlv{width:100%;margin:6px 0 2px;font-size:12.5px}\n'
      '.mxlv td{padding:3px 8px 3px 0;border:none;vertical-align:top}\n'
      '.mxl{width:28px;color:var(--mute);font-variant-numeric:tabular-nums}\n'
      '#mxperiod{width:auto;min-width:170px}', 1),
     # the dashboard line
     ('\'<div class="card"><h2>Your appraisal cycle</h2>\' + pmsSummary(pms) + \'</div>\' +',
      '\'<div id="mxcard"></div>\' +\n'
      '    \'<div class="card"><h2>Your appraisal cycle</h2>\' + pmsSummary(pms) + \'</div>\' +', 1),
     ('(cases.empty ? \'<div class="card"><h2>Escalations</h2>\' + msg("warn", cases.empty) + \'</div>\' : "");\n'
      '}',
      '(cases.empty ? \'<div class="card"><h2>Escalations</h2>\' + msg("warn", cases.empty) + \'</div>\' : "");\n'
      '  mxCardLoad();\n'
      '}', 1),
     # and the section on the matrix screen itself
     ('\'<p class="mute">Five levels per branch. Completeness is computed, never stored.</p>\' +',
      '\'<p class="mute">Five levels per branch. Completeness is computed, never stored.</p>\' +\n'
      '    \'<div id="mxmonth"><p class="mute">Loading this month\\u2019s pack\\u2026</p></div>\' +', 1),
     (': \'<div class="empty">Every branch in your coverage has all five levels.</div>\') + \'</div>\';\n'
      '}',
      ': \'<div class="empty">Every branch in your coverage has all five levels.</div>\') + \'</div>\';\n'
      '  mxMonthLoad();\n'
      '}', 1),
     # the screen itself, ahead of the performance screens
     ('/* ---------------------------------------------------------- performance */',
      SCREEN_MATRIX.rstrip() + '\n\n'
      '/* ---------------------------------------------------------- performance */', 1)],
))

# --------------------------- 8. THE DESPATCH MOVED TO ITS OWN FRONT DOOR
# Patch 7 is all-or-nothing on one sentinel, and by the time the despatch
# needed a different base the page already carried patch 7's first version.
# So this is the difference between the two, and nothing else.
#
# The routes were written for `ops`. `api` is at the size an Edge Function
# deploy will carry, and `ops` serves six screens that work -- Places,
# Reports, MIS, the rate master, report access and automations -- every one
# of which would have had to be re-uploaded to add one route to it. A slip
# anywhere in that upload takes all six down to add one. A fifth front door
# costs one more URL and risks nothing that is already running.
#
# On a page that has never had patch 7, patch 7 splices the screen with
# packApi already in it and defines the wrapper, so this one finds its
# sentinel and skips. On the page as published, patch 7 skips and this one
# does the move.
PATCHES.append((
    "the despatch has its own door",
    "var packApi =",
    [('var PLB  = "https://oxpwqfbtbxlvuqpztbwg.supabase.co/functions/v1/plb";\n'
      'var plb  = function(p,o){ return call(PLB,  p, o); };',
      'var PLB  = "https://oxpwqfbtbxlvuqpztbwg.supabase.co/functions/v1/plb";\n'
      'var plb  = function(p,o){ return call(PLB,  p, o); };\n'
      'var PACK = "https://oxpwqfbtbxlvuqpztbwg.supabase.co/functions/v1/pack";\n'
      'var packApi = function(p,o){ return call(PACK, p, o); };', 1),
     ('ops("/pack/', 'packApi("/pack/', 5)],
))

# ------------------------------------------- 9. MY PROFILE, AS DRAWN
# The design's My profile is three things and its own subtitle says which:
# "Your details, your tasks, and anything you need from another department."
# The build had the first two. The third had no control, no route and no
# row -- even though `raisable` and `request_task` have been in the schema
# since the beginning, shaped for exactly this, and both empty.
#
# This replaces the screen rather than adding beside it, because a second
# profile screen is how the page ended up with two vPeople.
SCREEN_MINE = io.open("build/app/screen-mytab.js", encoding="utf-8").read()

PATCHES.append((
    "my profile, as the design draws it",
    "function myRender(",
    [# the whole of the old vProfile, replaced. A span rather than a literal:
     # the function is 7,400 characters and quoting it here to delete it would
     # be 7,400 more chances to get one of them wrong.
     (("async function vProfile(){",
       "\n/* ------------------------------------------------ hiring & pending chairs"),
      SCREEN_MINE.rstrip() + "\n", 1),
     # the styles the design's layout needs
     ('.hrawarn{color:var(--gold-ink);font-size:12px;line-height:1.45}',
      '.hrawarn{color:var(--gold-ink);font-size:12px;line-height:1.45}\n'
      '/* ------------------------------------------------------------------ mine\n'
      '   Two columns, and the left one is the only terracotta thing on the\n'
      '   page -- because it is the only part of it that is somebody else\'s\n'
      '   clock.                                                            */\n'
      '.mygrid{display:grid;grid-template-columns:minmax(280px,1fr) minmax(0,1.6fr);\n'
      '  gap:16px;align-items:start}\n'
      '.mycol{min-width:0}\n'
      '.card.mytasks{border-color:var(--terra)}\n'
      '.card.mytasks>h2{background:var(--terra-bg);color:var(--terra-ink);\n'
      '  border-bottom-color:var(--terra-line)}\n'
      '.mytask{padding:13px 15px;border-bottom:1px solid var(--line3)}\n'
      '.mytask .myt{font-size:14px;font-weight:600;line-height:1.35;color:var(--ink)}\n'
      '.mytask .mute{font-size:12px;margin-top:4px}\n'
      '.mytask .btn{margin-top:9px}\n'
      '.mytask.late{background:var(--terra-bg)}\n'
      '.mytask.quiet .myt{font-weight:400}\n'
      '.mylate{font-size:12px;margin-top:4px;color:var(--terra-ink)}\n'
      '@media (max-width:860px){ .mygrid{grid-template-columns:1fr} }', 1)],
))

# ------------------------------------- 10. THE NAVIGATION ASKS THE SERVER
# The page carries its own copy of the access table -- SCREENS, CHAIR_LEVEL,
# UNDER -- and says so, immediately above it:
#
#     "It decides what appears in the navigation and what currentTab() will
#      open. It is NOT the permission check. Every service decides for itself
#      and refuses in its own words."
#
# Migration 204 made the second sentence true: the table now lives in the
# database, the ops service gates every route on it, and auth_whoami returns
# the caller's level and the screens it carries. Two copies of one policy
# drift, and the copy nobody edits becomes the one that is wrong, so the page
# prefers the server's answer and keeps its own only as a fallback for a
# session minted before 204.
#
# Deliberately NOT deleting the local table: a page that could not draw a
# navigation at all if one field were missing from one response would be a
# worse failure than a stale one.
#
# This one has NO matching migration, and that is not an oversight. The table
# it edits is not in app_page at all -- patch 5 above puts it there at publish
# time, and a migration written against app_page fails its own assertion,
# which is how this was found. So the anchors below only exist after patch 5
# has run, and the order of this list is what makes that true.
#
# build/test/check_access_matches_nav.py reads the BUILT page and compares
# every (level, screen) pair against access_level_screen, so the two copies
# cannot drift without a test saying so.
#
# Order matters and is load-bearing: patch 5 above is what puts SCREENS,
# CHAIR_LEVEL and UNDER into the page at all -- app_page has none of them --
# so the anchors below only exist once it has run.
PATCHES.append((
    "navigation asks the server",
    "me.screens",
    [('function myLevel(){\n  if (!me) return "exec";\n  if (me.app_role === "ADMIN") return "admin";',
      'function myLevel(){\n'
      '  if (!me) return "exec";\n'
      '  /* What the database said when this session was minted. The page\n'
      '     works it out below only if the session predates migration 204. */\n'
      '  if (me.scope_level) return me.scope_level;\n'
      '  if (me.app_role === "ADMIN") return "admin";', 1),
     ('function allowed(key){\n  if (!me) return false;\n  var lvl = myLevel();\n  if (lvl === "admin") return true;',
      'function allowed(key){\n'
      '  if (!me) return false;\n'
      '  /* The server\'s list, which is the same rows the ops service refuses\n'
      '     on. If it is here, it is the answer -- working it out again from a\n'
      '     second copy could only disagree. */\n'
      '  if (me.screens && me.screens.length) {\n'
      '    return me.screens.indexOf(key) > -1;\n'
      '  }\n'
      '  var lvl = myLevel();\n'
      '  if (lvl === "admin") return true;', 1)],
))

print("%d patches to consider." % len(PATCHES))
for name, sentinel, rules in PATCHES:
    if sentinel in app:
        print("%-32s already in app_page; skipped." % name)
        continue
    for old, new, want in rules:
        # A rule may name a SPAN -- ("from", "up to but not including") --
        # when what it replaces is a whole function. Quoting a 7,400-character
        # function literally, only to delete it, is 7,400 more chances to get
        # one character wrong; both ends are still asserted to occur exactly
        # once, so a page that has moved still fails the build.
        if isinstance(old, tuple):
            a_, b_ = old
            if app.count(a_) != want or app.count(b_) != want:
                sys.exit("::error::%s: span markers %r / %r occur %d / %d times, "
                         "expected %d each. The application has moved; re-check "
                         "the matching migration before publishing."
                         % (name, a_[:40], b_[:40], app.count(a_), app.count(b_), want))
            i_ = app.index(a_)
            j_ = app.index(b_, i_)
            app = app[:i_] + new + app[j_:]
            continue
        found = app.count(old)
        if found != want:
            sys.exit("::error::%s: expected %d of %r, found %d. The application has "
                     "moved; re-check the matching migration before publishing."
                     % (name, want, old[:60], found))
        app = app.replace(old, new)
    print("%-32s applied (%d site(s))." % (name, sum(w for _, _, w in rules)))

# Whichever path got us here, the published page must not reach localStorage
# anywhere except inside the three guards.
bare = app.count("localStorage.")
if bare != 3:
    sys.exit("::error::Expected exactly 3 localStorage calls (the guards), found %d." % bare)

# Immediately before the application's own first script, so the wrapper is in
# force for every call it makes — including the very first one, /api/config.
MARKER = '<script src="https://accounts.google.com/gsi/client"'
if MARKER not in app:
    sys.exit("::error::Could not find the application's first script tag to insert before.")

out = app.replace(MARKER, shim + MARKER, 1)
io.open("index.html", "w", encoding="utf-8").write(out)
print("index.html written, %d bytes (application %d + shim %d)"
      % (len(out), len(app), len(shim)))
