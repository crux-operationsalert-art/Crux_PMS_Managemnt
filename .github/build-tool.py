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
      '/* The three score chips at the head of the screen: KPIs, Attributes,\n'
      '   Final. Only the blueprint\'s own eighteen tokens are used.       */\n'
      '.pfchiprow{display:flex;gap:10px;flex-wrap:wrap}\n'
      '.pfchip{flex:1 1 150px;min-width:130px;padding:12px 14px;background:var(--panel);\n'
      '  border:1px solid var(--line2);border-radius:4px}\n'
      '.pfchipv{font-size:26px;line-height:1.1;color:var(--ink)}\n'
      '.pfchipl{font-size:13px;color:var(--body);margin-top:3px}\n'
      '.pfchips{font-size:12px;color:var(--mute);margin-top:1px}\n'
      '/* Fourteen days. Filled is a day filed, hollow a working day missed,\n'
      '   faded a day that was never a working day and cannot break a run. */\n'
      '.pfstreak{display:flex;gap:5px;flex-wrap:wrap;margin:2px 0 10px}\n'
      '.pfday{width:34px;padding:5px 0;text-align:center;border-radius:3px;\n'
      '  border:1px solid var(--line);background:var(--white);color:var(--mute)}\n'
      '.pfday.on{background:var(--green-bg);border-color:var(--green);color:var(--green)}\n'
      '.pfday.miss{background:var(--white);border-color:var(--field)}\n'
      '.pfday.off{background:var(--panel2);border-color:var(--line3);color:var(--line)}\n'
      '.pfdow{font-size:11px;line-height:1.2}\n'
      '.pfdd{font-size:13px;line-height:1.2;color:var(--ink)}\n'
      '.pfday.off .pfdd{color:var(--mute)}\n'
      '/* A task, and what became of it. */\n'
      '.pftask.ok td{background:var(--green-bg)}\n'
      '.pftask.warn td{background:var(--gold-bg)}\n'
      '.pftask.bad td{background:var(--terra-bg)}\n'
      # A target somebody agreed, and one nobody has yet. The difference
      # matters enough to be visible without reading the words.
      '.pfpin{color:var(--green);font-weight:600}\n'
      '.pfseed{color:var(--gold-ink)}\n'
      '.pfsays{margin:0 0 8px;font-size:13px;color:var(--body)}\n'
      # ------------------------------------------------ the day, as a headline
      # One number, big, and the ring beside it. A person opening this
      # screen should know in one glance whether today is done, and the
      # ring is the only place on the screen that is allowed to be large.
      '.pfhero{display:flex;align-items:center;gap:18px;flex-wrap:wrap;\n'
      '  padding:4px 0 2px}\n'
      '.pfring{flex:0 0 auto;width:92px;height:92px;position:relative}\n'
      '.pfring svg{width:92px;height:92px;transform:rotate(-90deg)}\n'
      '.pfring .trk{fill:none;stroke:var(--line2);stroke-width:8}\n'
      '.pfring .arc{fill:none;stroke-width:8;stroke-linecap:round;\n'
      '  transition:stroke-dashoffset .5s ease}\n'
      '.pfring b{position:absolute;inset:0;display:flex;align-items:center;\n'
      '  justify-content:center;font-size:21px;color:var(--ink);\n'
      '  font-variant-numeric:tabular-nums}\n'
      '.pfheroT{flex:1 1 220px;min-width:0}\n'
      '.pfheroT h3{margin:0 0 2px;font-size:17px;color:var(--ink)}\n'
      '.pfheroT p{margin:0;font-size:13px;color:var(--mute)}\n'
      # A streak is days, not numbers. Showing up is the habit being built.
      '.pfrun{display:inline-flex;align-items:baseline;gap:5px;margin-top:7px;\n'
      '  padding:3px 9px;border-radius:999px;background:var(--green-bg);\n'
      '  color:var(--green);font-size:12.5px;font-weight:600}\n'
      '.pfrun.cold{background:var(--line3);color:var(--mute);font-weight:400}\n'
      # --------------------------------------------------- a measure, as a bar
      # Thin, with the target at the full width and the fill stopping where
      # the number actually is. A bar is comparable down a column; a ring
      # is not, which is why there is exactly one ring on the screen.
      '.pfbar{height:6px;border-radius:4px;background:var(--line2);\n'
      '  overflow:hidden;margin:5px 0 3px;max-width:230px}\n'
      '.pfbar i{display:block;height:100%;border-radius:4px}\n'
      '.pfbar i.good{background:var(--green)}\n'
      '.pfbar i.part{background:var(--gold)}\n'
      '.pfbar i.short{background:var(--terra)}\n'
      # Status never travels alone: the word is beside the colour, always.
      '.pfmark{display:inline-flex;align-items:center;gap:5px;font-size:12px;\n'
      '  font-weight:600}\n'
      '.pfmark.good{color:var(--green)}\n'
      '.pfmark.part{color:var(--gold-ink)}\n'
      '.pfmark.short{color:var(--terra-ink)}\n'
      '.pfmark.none{color:var(--mute);font-weight:400}\n'
      '.pfmark s{width:7px;height:7px;border-radius:2px;background:currentColor;\n'
      '  flex:0 0 7px}\n'
      # ------------------------------------------- what came up from below
      '.pfhand{display:grid;gap:10px;\n'
      '  grid-template-columns:repeat(auto-fill,minmax(232px,1fr));padding:2px 0}\n'
      '.pfhcard{border:1px solid var(--line);border-radius:10px;padding:11px 13px;\n'
      '  background:var(--panel2)}\n'
      '.pfhcard h4{margin:0 0 1px;font-size:13.5px;color:var(--ink)}\n'
      '.pfhcard .u{font-size:11.5px;color:var(--mute)}\n'
      '.pfhbig{font-size:25px;color:var(--ink);margin:7px 0 0;\n'
      '  font-variant-numeric:tabular-nums;line-height:1.1}\n'
      '.pfhbig em{font-size:13px;color:var(--mute);font-style:normal;margin-left:5px}\n'
      '.pfspread{display:flex;gap:14px;margin-top:7px;font-size:12px;color:var(--mute)}\n'
      '.pfspread b{color:var(--body);font-weight:600;\n'
      '  font-variant-numeric:tabular-nums}\n'
      # ---------------------------------------------- the month, as a verdict
      '.pfmon{display:flex;align-items:baseline;gap:10px;flex-wrap:wrap}\n'
      '.pfmon .n{font-size:32px;color:var(--ink);font-variant-numeric:tabular-nums;\n'
      '  line-height:1}\n'
      '.pfmon .of{font-size:14px;color:var(--mute)}\n'
      '.pfwork{margin:9px 0 0;padding:0;list-style:none;font-size:12.5px}\n'
      '.pfwork li{display:flex;justify-content:space-between;gap:10px;\n'
      '  padding:4px 0;border-top:1px solid var(--line3);color:var(--body)}\n'
      '.pfwork li:first-child{border-top:0}\n'
      '.pfwork li span{color:var(--mute)}\n'
      '@media (max-width:560px){\n'
      '  .pfring,.pfring svg{width:74px;height:74px}\n'
      '  .pfring b{font-size:18px}\n'
      '  .pfhand{grid-template-columns:1fr}\n'
      '  .pfbar{max-width:none}\n'
      '}\n'
      # ------------------------------ one target, several clients
      # The split lives inside the target panel, so it is bounded by a
      # rule rather than a card: it is part of deciding the target, not
      # a separate decision.
      '.pfsplitq{margin:10px 0 0;padding-top:9px;border-top:1px solid var(--line3)}\n'
      '.pfsplit{margin:10px 0 0;padding-top:9px;border-top:1px solid var(--line3)}\n'
      '.pfsplit h3{margin:0 0 3px;font-size:13px;color:var(--ink)}\n'
      '.pfsplit table{font-size:12.5px}\n'
      '.pfsplit label{cursor:pointer}\n'
      '.pfsplit input.pfin{width:110px}\n'
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
      '/* A field label that has to teach rather than only name. "Counted in"\n'
      '   and "Climbs into" named the field and told nobody what to put in\n'
      '   it; the hint under the label is the answer. */\n'
      '.hrahint{display:block;font-style:normal;font-weight:400;font-size:11px;\n'
      '  color:var(--mute);letter-spacing:0;text-transform:none;margin-top:1px}\n'
      '/* The clock said no. Said where the control was, in the control\'s\n'
      '   place, because somebody looking for a button needs the answer\n'
      '   where they are looking -- not at the top of the page. */\n'
      '.pfshut{margin:8px 0;padding:10px 13px;border-radius:9px;\n'
      '  background:var(--gold-bg);border-left:3px solid var(--gold);\n'
      '  font-size:13px;color:var(--body)}\n'
      '.pfshut b{color:var(--gold-ink)}\n'
      '.pfwin button{margin-left:10px}\n'
      '/* Whose targets are mine, at the top of the screen. A band rather\n'
      '   than a card: it is a pointer to a card further down, not a place\n'
      '   where anything is decided. */\n'
      '.pfsetfor{display:flex;align-items:center;gap:14px;flex-wrap:wrap;\n'
      '  margin:0 0 14px;padding:11px 14px;border-radius:10px;\n'
      '  background:var(--green-bg);border-left:3px solid var(--green);\n'
      '  font-size:13.5px;color:var(--body)}\n'
      '.pfsetfor > div{flex:1;min-width:220px}\n'
      '.pfsetfor b{color:var(--ink)}\n'
      '.pfsetfor .mute{font-size:12px;margin-top:2px}\n'
      '/* The rest of the line: people you watch and do not set for. Quiet,\n'
      '   and shut until asked for -- it is context, not work. */\n'
      '.pfwatch{margin:12px 0 0;font-size:12.5px}\n'
      '.pfwatch.open{padding-top:10px;border-top:1px solid var(--line3)}\n'
      '.pfwatch h3{margin:0 0 6px;font-size:12.5px;color:var(--mute);\n'
      '  text-transform:uppercase;letter-spacing:.4px}\n'
      '.pfwatch td{padding:5px 6px}\n'
      '/* Search for anyone. Set apart from the reporting line above it by a\n'
      '   border and a tint, because the whole point is that the two lists\n'
      '   are not the same thing: one is your team, the other is everybody. */\n'
      '.pffind{margin-top:14px;padding:12px 14px;border:1px solid var(--line2);\n'
      '  border-radius:10px;background:var(--panel2)}\n'
      '.pffind h3{margin:0 0 8px;font-size:14px}\n'
      '.pffind input{max-width:380px}\n'
      '.pffind table{margin-top:8px}\n'
      '/* Changing a measure already given. Under the tree rather than two\n'
      '   more buttons on every node: the tree is read far more often than\n'
      '   it is edited, and a row of verbs on each line turns a reading\n'
      '   surface into a control panel. */\n'
      '.pfadmin{margin:10px 0 0;padding-top:10px;border-top:1px solid var(--line3)}\n'
      '.pfadmin h4{margin:0 0 6px;font-size:12.5px;color:var(--mute);\n'
      '  text-transform:uppercase;letter-spacing:.4px}\n'
      '.pfadmin td{padding:5px 6px}\n'
      '@media (max-width:720px){\n'
      '  .pfrow{flex-wrap:wrap}\n'
      '  .pftgt,.pfmeter{display:none}\n'
      '  .pffind{padding:10px}\n'
      '  .pffind input{max-width:100%}\n'
      '}', 1),
     # the two entries become one
     ('["pms","Performance & appraisal"], ["plb","Performance & bonus"], ',
      '["perf","Performance & appraisal"], ', 1),
     # and the old two keep their routes, as sub-tabs under it
     ('var FAMILY = [\n'
      '  ["clients", [["clients","Clients"], ["matrix","Escalation matrix"]]],',
      'var FAMILY = [\n'
      '  /* The blueprint has NO sub-tabs on Performance: isAppraisal is set\n'
      '     inside the same route, so the appraisal is a section on the page.\n'
      '     What is left is the one job the design does not place anywhere --\n'
      '     issuing sheets, certifying and closing a quarter -- which is HR\'s\n'
      '     and Business Excellence\'s, not the employee\'s.              */\n'
      '  ["perf",    [["perf","Performance & appraisal"], ["plb","Running the scheme"]]],\n'
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

# ------------------------- 11. PERFORMANCE GETS ITS OWN FRONT DOOR TOO
# The Performance screen grew three things the scheme service had no room
# for: the day you filed, the tasks somebody asked you to do, and the
# monthly weighting. `plb` is the payroll-adjacent service -- it computes
# what people are paid -- and it is at the size where a deploy carries
# every file or none. Adding three routes to it means re-uploading the
# whole of the quarterly scheme to add a task list, and a slip anywhere in
# that upload takes the scheme down.
#
# So the same decision patch 8 made for the despatch: a sixth front door,
# `perf`, carrying only the new routes. `plb` stays exactly as deployed.
# One more URL, and nothing that already runs is touched.
#
# The anchor is patch 7/8's packApi line, which is why this is last: on a
# page that has never had either, patch 7 defines it; on the page as
# published, patch 8 does. Either way it is there by the time this runs.
PATCHES.append((
    "performance has its own door",
    "var perfApi =",
    [('var PACK = "https://oxpwqfbtbxlvuqpztbwg.supabase.co/functions/v1/pack";\n'
      'var packApi = function(p,o){ return call(PACK, p, o); };',
      'var PACK = "https://oxpwqfbtbxlvuqpztbwg.supabase.co/functions/v1/pack";\n'
      'var packApi = function(p,o){ return call(PACK, p, o); };\n'
      'var PERF = "https://oxpwqfbtbxlvuqpztbwg.supabase.co/functions/v1/perf";\n'
      'var perfApi = function(p,o){ return call(PERF, p, o); };', 1)],
))

print("%d patches to consider." % len(PATCHES))
# ------------------------------------------------------ 12. MY TEAM
# The people tree, in the shape of the attached org-chart design. The old
# "My team" drew the CHAIR tree, which is what Structure is for; this one
# draws who reports to whom, which is the column every visibility rule is
# built on.
#
# The screen is inserted and the router is pointed at it. The old vPeople
# is left where it is rather than cut out: excising a function by string
# match is how a build breaks quietly, and an unreferenced function costs
# nothing but bytes.
SCREEN_TEAM = io.open("build/app/screen-team.js", encoding="utf-8").read()

PATCHES.append((
    "my team is the people tree",
    "function tmRender(",
    [("    people:vPeople, penalties:vPenalties,",
      "    people:vTeamScreen, penalties:vPenalties,", 1),

     # The screen, and the design's language as CSS. Colour carries depth,
     # never status on its own: every bar ships a number and a word.
     ('var PF = { period:null, cycle:null, tab:"mine",',
      SCREEN_TEAM.replace("async function vPeople(){", "async function vTeamScreen(){")
      + '\nvar PF = { period:null, cycle:null, tab:"mine",', 1),

     ("</style>",
      # ------------------------------------------- the paper and the rules
      ".tmwrap{overflow:auto;padding:16px 14px 20px}\n"
      ".tmoc{width:max-content;margin:0 auto;font-size:13px}\n"
      ".tmoc ul{padding-top:22px;position:relative;display:flex;\n"
      "  justify-content:center;margin:0;list-style:none}\n"
      ".tmoc>ul{padding-top:0}\n"
      ".tmoc li{position:relative;padding:22px 7px 0;list-style:none;\n"
      "  display:flex;flex-direction:column;align-items:center}\n"
      # The connectors are drawn in CSS, as the design draws them: a pair
      # of borders per item, with the outer halves removed at each end.
      ".tmoc li::before,.tmoc li::after{content:'';position:absolute;top:0;\n"
      "  right:50%;border-top:1px solid var(--line2);width:50%;height:22px}\n"
      ".tmoc li::after{right:auto;left:50%;border-left:1px solid var(--line2)}\n"
      ".tmoc li:only-child{padding-top:0}\n"
      ".tmoc li:only-child::before,.tmoc li:only-child::after{display:none}\n"
      ".tmoc li:first-child::before,.tmoc li:last-child::after{border-top:0 none}\n"
      ".tmoc li:last-child::before{border-right:1px solid var(--line2);\n"
      "  border-radius:0 5px 0 0}\n"
      ".tmoc li:first-child::after{border-radius:5px 0 0 0}\n"
      ".tmoc>ul>li::before,.tmoc>ul>li::after{display:none}\n"
      # ---------------------------------------------------------- the card
      ".tmcard{position:relative;width:186px;padding:9px 11px 10px;\n"
      "  background:var(--panel);border:1px solid var(--line);\n"
      "  border-top:3px solid var(--line2);border-radius:3px;cursor:pointer;\n"
      "  text-align:left;transition:box-shadow .12s,border-color .12s}\n"
      ".tmcard:hover{border-color:var(--mute)}\n"
      ".tmcard.sel{border-color:var(--ink);box-shadow:0 0 0 2px var(--line3)}\n"
      ".tmcard.dragging{opacity:.45}\n"
      ".tmcard.over{border-color:var(--blue);box-shadow:0 0 0 2px var(--blue)}\n"
      "[draggable=true].tmcard{cursor:grab}\n"
      # Depth is shown by tinting the top edge, so the eye reads the level
      # without the tree having to indent.
      ".tmcard.d1{border-top-color:#B9C2D4}\n"
      ".tmcard.d2{border-top-color:#8C99B4}\n"
      ".tmcard.d3{border-top-color:#5F7095}\n"
      ".tmcard.d4{border-top-color:#34497A}\n"
      ".tmcard.d5{border-top-color:#14203A}\n"
      ".tmnm{font-size:14px;color:var(--ink);line-height:1.25;font-weight:600}\n"
      ".tmch{font-size:11.5px;color:var(--mute);margin-top:1px}\n"
      ".tmno{font-size:10px;color:var(--mute);letter-spacing:.04em;\n"
      "  font-variant-numeric:tabular-nums;margin-top:2px}\n"
      # ------------------------------------------------ progress, with words
      ".tmbar{height:5px;border-radius:3px;background:var(--line2);\n"
      "  overflow:hidden;margin:8px 0 3px}\n"
      ".tmbar i{display:block;height:100%;border-radius:3px}\n"
      ".tmbar.good i{background:var(--green)}\n"
      ".tmbar.part i{background:var(--gold)}\n"
      ".tmbar.short i{background:var(--terra)}\n"
      ".tmbar.none i{background:transparent}\n"
      ".tmpc{font-size:11px;font-weight:600}\n"
      ".tmpc.good{color:var(--green)}\n"
      ".tmpc.part{color:var(--gold-ink)}\n"
      ".tmpc.short{color:var(--terra-ink)}\n"
      ".tmpc.none{color:var(--mute);font-weight:400}\n"
      ".tmtags{display:flex;flex-wrap:wrap;gap:3px;margin-top:6px}\n"
      ".tmtg{font-size:8.5px;letter-spacing:.05em;text-transform:uppercase;\n"
      "  padding:0 3px;border:1px solid var(--line2);color:var(--mute)}\n"
      ".tmtg.n{color:var(--green);border-color:var(--green)}\n"
      ".tmtg.v{color:var(--blue);border-color:var(--blue)}\n"
      ".tmtg.d{color:var(--gold-ink);border-color:var(--gold)}\n"
      # --------------------------------------------------------- the rest
      ".tmtog{position:absolute;top:-9px;left:50%;transform:translateX(-50%);\n"
      "  z-index:2;width:17px;height:17px;line-height:15px;padding:0;\n"
      "  border:1px solid var(--line);background:var(--panel);\n"
      "  border-radius:50%;font-size:12px;color:var(--body);cursor:pointer}\n"
      ".tmtog:hover{border-color:var(--ink);color:var(--ink)}\n"
      ".tmbarrow{display:flex;gap:7px;align-items:center;flex-wrap:wrap;\n"
      "  padding:2px 0 10px}\n"
      ".tmkey{font-size:11.5px;display:inline-flex;align-items:center;gap:4px;\n"
      "  flex-wrap:wrap}\n"
      ".tmsw{display:inline-block;width:9px;height:5px;border-radius:2px;\n"
      "  margin-left:7px}\n"
      ".tmsw.good{background:var(--green)}\n"
      ".tmsw.part{background:var(--gold)}\n"
      ".tmsw.short{background:var(--terra)}\n"
      ".tmsw.none{background:var(--line2)}\n"
      ".tmpanel h3.tmh3{margin:14px 0 6px;font-size:13px;color:var(--ink)}\n"
      ".tmacts{display:flex;flex-wrap:wrap;gap:6px;margin:8px 0 4px}\n"
      ".tmsoon{font-size:12px;margin:6px 0 0}\n"
      # ------------------------- warnings, and the plan if there is one
      # A warning is a dated line that never changes; a plan is a live
      # thing whose overdue reviews are the point of booking them.
      ".tmwarn{list-style:none;margin:6px 0 0;padding:0;font-size:13px}\n"
      ".tmwarn li{padding:7px 0;border-top:1px solid var(--line3)}\n"
      ".tmwarn li:first-child{border-top:0}\n"
      ".tmlvl{font-size:9px;letter-spacing:.06em;text-transform:uppercase;\n"
      "  padding:1px 4px;border:1px solid var(--line2);color:var(--mute)}\n"
      ".tmlvl.written{color:var(--gold-ink);border-color:var(--gold)}\n"
      ".tmlvl.final{color:var(--terra-ink);border-color:var(--terra)}\n"
      ".tmplan{border:1px solid var(--line);border-radius:6px;padding:10px 12px;\n"
      "  margin-top:6px;background:var(--panel2);font-size:13px}\n"
      ".tmplan p{margin:4px 0}\n"
      ".tmplanh{display:flex;gap:8px;align-items:center;flex-wrap:wrap;\n"
      "  margin-bottom:5px}\n"
      ".tmover{color:var(--terra-ink);font-weight:600;font-size:11.5px}\n"
      ".tmoverrow td{background:var(--terra-bg)}\n"
      ".tmfm{border:1px solid var(--line);border-radius:6px;padding:11px 13px;\n"
      "  margin-top:9px;background:var(--panel)}\n"
      ".tmfm h4{margin:0 0 7px;font-size:13.5px;color:var(--ink)}\n"
      ".tmfm p{margin:6px 0}\n"
      ".tmfm textarea,.tmfm select{font:inherit;padding:4px 6px;\n"
      "  border:1px solid var(--line);border-radius:3px;background:var(--panel)}\n"
      # ------------------------------------------ the + and what it opens
      # The + sits on the card's own top-right, opposite the collapse
      # toggle that sits centred above it, so the two never overlap even
      # on the narrowest card.
      ".tmadd{position:absolute;top:-8px;right:-8px;z-index:3;\n"
      "  width:19px;height:19px;line-height:17px;padding:0;\n"
      "  border:1px solid var(--line);background:var(--panel);\n"
      "  border-radius:50%;font-size:14px;color:var(--mute);cursor:pointer}\n"
      ".tmadd:hover{border-color:var(--green);color:var(--green);\n"
      "  background:var(--green-bg)}\n"
      ".tmtabs{display:flex;gap:0;margin:10px 0 0;border-bottom:1px solid var(--line)}\n"
      ".tmtab{font:inherit;font-size:13px;padding:6px 12px;cursor:pointer;\n"
      "  border:0;border-bottom:2px solid transparent;background:none;\n"
      "  color:var(--mute)}\n"
      ".tmtab:hover{color:var(--ink)}\n"
      ".tmtab.on{color:var(--ink);border-bottom-color:var(--ink);font-weight:600}\n"
      ".tmabody{padding:10px 0 2px;font-size:13px}\n"
      ".tmabody label{font-size:12.5px;color:var(--mute)}\n"
      ".tmabody input,.tmabody select{font:inherit;padding:4px 6px;\n"
      "  border:1px solid var(--line);border-radius:3px;background:var(--panel);\n"
      "  color:var(--body)}\n"
      ".tmq{margin-top:4px;font-size:12.5px}\n"
      ".tmq td{padding:5px 8px 5px 0;vertical-align:middle}\n"
      ".tmerrs{margin:5px 0 0;padding-left:18px}\n"
      ".tmerrs li{margin:2px 0}\n"
      # ------------------------------- the chart and the list, side by side
      # Two drawings of the same people. The switch is a segmented control
      # rather than the tab strip above, because these are two views of one
      # screen and not two screens -- and because the tab strip is already
      # spoken for by the + panel's own two tabs.
      ".tmviews{display:inline-flex;margin:0 0 12px;border:1px solid var(--line);\n"
      "  border-radius:7px;overflow:hidden;background:var(--panel)}\n"
      ".tmview{font:inherit;font-size:13px;padding:7px 14px;cursor:pointer;\n"
      "  border:0;background:none;color:var(--mute);min-height:0;\n"
      "  display:inline-flex;align-items:center;gap:6px}\n"
      ".tmview + .tmview{border-left:1px solid var(--line)}\n"
      ".tmview:hover{color:var(--ink);background:var(--panel2)}\n"
      ".tmview.on{color:var(--white);background:var(--ink);font-weight:600}\n"
      ".tmview.on .tmtg{color:var(--white);border-color:var(--white)}\n"
      # The headline count, opposite the title: how many people there are
      # is the first thing somebody cleaning a list wants to know.
      ".tmcount{text-align:right;line-height:1.1;margin-left:auto}\n"
      ".tmcount b{display:block;font-size:26px;color:var(--ink);\n"
      "  font-variant-numeric:tabular-nums}\n"
      ".tmcount span{font-size:11px;letter-spacing:.06em;color:var(--mute);\n"
      "  text-transform:uppercase}\n"
      ".tmfind{min-width:300px;max-width:440px;flex:1 1 300px}\n"
      ".tmshow{font-size:12px;white-space:nowrap}\n"
      # The gaps, as chips. Each is a count and the filter behind it, so
      # the number and the people it counted are one press apart.
      ".tmchips{display:flex;flex-wrap:wrap;gap:6px;margin:0 0 12px}\n"
      ".tmchip{font:inherit;font-size:12px;padding:5px 10px;cursor:pointer;\n"
      "  min-height:0;border:1px solid var(--line2);border-radius:999px;\n"
      "  background:var(--panel);color:var(--body);\n"
      "  display:inline-flex;align-items:center;gap:5px}\n"
      ".tmchip:hover{border-color:var(--ink);background:var(--panel2);\n"
      "  color:var(--ink)}\n"
      ".tmchip.on{background:var(--ink);color:var(--white);border-color:var(--ink)}\n"
      ".tmchip.on .tmtg{color:var(--white);border-color:var(--white)}\n"
      ".tmlist{padding:0;overflow:hidden}\n"
      ".tmlist table{font-size:13px}\n"
      ".tmlist th{padding:0}\n"
      # A column heading that sorts is still a heading: it reads as one and
      # only the arrow says it was pressed.
      ".tmsort{font:inherit;font-size:11px;letter-spacing:.06em;\n"
      "  text-transform:uppercase;color:var(--mute);background:none;border:0;\n"
      "  padding:9px 8px;min-height:0;cursor:pointer;width:100%;text-align:left}\n"
      ".tmsort:hover{color:var(--ink);background:var(--panel2)}\n"
      ".tmsort.on{color:var(--ink);font-weight:700}\n"
      ".tmar{font-size:10px}\n"
      ".tmn{text-align:right;font-variant-numeric:tabular-nums;color:var(--mute)}\n"
      # A gap is said in words and never left blank: an empty cell reads as
      # a rendering fault, and the whole point of this screen is the gaps.
      ".tmgap{color:var(--terra-ink);font-size:12px}\n"
      ".tmwarnrow td{background:var(--terra-bg)}\n"
      ".tmrep{display:flex;flex-direction:column;gap:6px;min-width:230px}\n"
      ".tmrep select{max-width:300px}\n"
      ".tmrepb{display:flex;gap:6px}\n"
      # ------------------------------------------ the row, opened as a form
      # A row turns into ONE form rather than six editable cells, because
      # six cells is six saves and six chances to half-finish. It is laid
      # out as a grid that folds to one column, so the same markup is the
      # phone layout without a second set of rules.
      ".tmedrow td{background:var(--panel2);padding:14px 12px}\n"
      ".tmedit{max-width:980px}\n"
      ".tmedh{display:flex;gap:10px;align-items:baseline;flex-wrap:wrap;\n"
      "  margin:0 0 12px;padding-bottom:9px;border-bottom:1px solid var(--line2)}\n"
      ".tmedh b{font-family:var(--serif,Georgia,serif);font-size:16px}\n"
      ".tmedh span{font-size:12px}\n"
      ".tmedg{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));\n"
      "  gap:10px 14px}\n"
      ".tmf{display:flex;flex-direction:column;gap:4px;min-width:0}\n"
      ".tmf>span{font-size:11px;letter-spacing:.06em;text-transform:uppercase;\n"
      "  color:var(--mute)}\n"
      ".tmf .pfin{width:100%}\n"
      ".tmedb{display:flex;gap:8px;margin-top:14px}\n"
      # The refusal sits with the boxes it is about, not above them in a
      # banner: the database names the field, so the screen can too.
      ".tmedbad{margin-top:12px;padding:9px 11px;border:1px solid var(--terra);\n"
      "  background:var(--terra-bg);border-radius:3px;font-size:12px;\n"
      "  color:var(--terra-ink)}\n"
      ".tmedbad b{text-transform:capitalize}\n"
      # ---------------------------------------------- the same change to many
      ".tmck{width:28px;text-align:center}\n"
      ".tmbulk{display:flex;gap:8px;align-items:center;flex-wrap:wrap;\n"
      "  margin:0 0 12px;padding:9px 11px;border:1px solid var(--gold);\n"
      "  background:var(--gold-bg);border-radius:3px}\n"
      ".tmbulk .pfin{min-width:180px}\n"
      ".tmbn{font-size:12px;color:var(--gold-ink);font-variant-numeric:tabular-nums}\n"
      ".tmbf{font-size:11px;letter-spacing:.06em;text-transform:uppercase;\n"
      "  color:var(--mute);margin-left:6px}\n"
      "@media (max-width:720px){\n"
      "  .tmfind{min-width:0}\n"
      "  .tmcount{text-align:left}\n"
      "  .tmedg{grid-template-columns:1fr}\n"
      "  .tmbulk{align-items:stretch;flex-direction:column}\n"
      "}\n"
      # ============================ the quarterly scorecard, in OKR shape
      # One band vocabulary for the whole card -- met / on track / at risk
      # / off track -- and every use of it carries the word beside the
      # colour, so the card reads the same in greyscale and to somebody who
      # does not see red and green apart.
      # ------------------------- the quarter drawn in the monthly card's shape
      # One block per measure instead of one row, because the thing being
      # read is three months of a promise rather than a single line of a
      # table. The head carries the three numbers somebody wants without
      # reading anything else: the weight, what the quarter asks for, and
      # where they have got to.
      ".pbqm{border:1px solid var(--line2);border-radius:3px;margin:0 0 12px;\n"
      "  padding:12px 13px;background:var(--panel2)}\n"
      ".pbqmh{display:flex;gap:18px;align-items:flex-start;flex-wrap:wrap;\n"
      "  margin:0 0 10px;padding-bottom:9px;border-bottom:1px solid var(--line2)}\n"
      ".pbqmh>div:first-child{flex:1 1 220px;min-width:0}\n"
      ".pbqmh b{font-family:var(--serif,Georgia,serif);font-size:15px}\n"
      ".pbqmn{text-align:right;min-width:92px}\n"
      ".pbqmn span{display:block;font-size:10px;letter-spacing:.07em;\n"
      "  text-transform:uppercase;color:var(--mute)}\n"
      ".pbqmn b{font-variant-numeric:tabular-nums;font-size:15px}\n"
      ".pbqm table{width:100%}\n"
      # The parts of a measure. Indented under it, and the total is a row of
      # the same table rather than a sentence beside it, so "do they add up"
      # is answered where the eye already is.
      ".pbparts{width:100%}\n"
      ".pbpsum td{border-top:2px solid var(--line);background:var(--panel)}\n"
      ".pbpart{border:1px solid var(--line2);border-radius:3px;margin:0 0 8px;\n"
      "  padding:9px 11px}\n"
      ".pbparth{display:flex;gap:10px;align-items:center;flex-wrap:wrap}\n"
      ".pbparth b{flex:0 1 auto}\n"
      ".pbparth .btn{margin-left:auto}\n"
      ".pbpart input{width:100%}\n"
      ".pbpartlist{margin:0 0 12px}\n"
      "@media (max-width:720px){\n"
      "  .pbqmh{gap:10px}\n"
      "  .pbqmn{text-align:left;min-width:0}\n"
      "  .pbparth .btn{margin-left:0}\n"
      "}\n"
      ".pbokr{padding-bottom:14px}\n"
      ".pbokrh{display:flex;gap:18px;align-items:flex-start;\n"
      "  justify-content:space-between;flex-wrap:wrap}\n"
      ".pbokrh h2{margin:0}\n"
      ".pbokrring{display:flex;flex-direction:column;align-items:center;gap:1px;\n"
      "  font-size:11px;text-align:center}\n"
      ".pbokrw{font-size:11.5px;font-weight:600;letter-spacing:.02em}\n"
      ".pbokrw.good{color:var(--green)} .pbokrw.part{color:var(--blue)}\n"
      ".pbokrw.risk{color:var(--gold-ink)} .pbokrw.short{color:var(--terra-ink)}\n"
      ".pbokrw.none{color:var(--mute)}\n"
      ".pbring .pbrtrack{stroke:var(--line2)}\n"
      ".pbring .pbrval{stroke:var(--mute)}\n"
      ".pbring.good .pbrval{stroke:var(--green)}\n"
      ".pbring.part .pbrval{stroke:var(--blue)}\n"
      ".pbring.risk .pbrval{stroke:var(--gold)}\n"
      ".pbring.short .pbrval{stroke:var(--terra)}\n"
      ".pbring .pbrtx{font:600 17px/1 inherit;fill:var(--ink)}\n"
      # ------------------------------------------------- the four figures
      ".pbstats{display:flex;flex-wrap:wrap;gap:9px;margin:13px 0 4px}\n"
      ".pbstat{flex:1 1 138px;border:1px solid var(--line);border-radius:6px;\n"
      "  padding:8px 11px 9px;background:var(--panel2)}\n"
      ".pbstat span{display:block;font-size:10.5px;letter-spacing:.05em;\n"
      "  text-transform:uppercase;color:var(--mute)}\n"
      ".pbstat b{display:block;font-size:20px;line-height:1.25;color:var(--ink);\n"
      "  font-variant-numeric:tabular-nums}\n"
      ".pbstat b u{font-size:12px;font-weight:400;color:var(--mute);\n"
      "  text-decoration:none}\n"
      ".pbstat i{font-style:normal;font-size:11px;color:var(--mute)}\n"
      ".pbstat.pbpay{border-color:var(--green);background:var(--green-bg)}\n"
      ".pbstat.pbpay b{color:var(--green)}\n"
      # ----------------------------------------------------- an objective
      ".pbobj{margin-top:16px;border-top:1px solid var(--line);padding-top:11px}\n"
      ".pbobjh{display:flex;gap:9px;align-items:baseline;flex-wrap:wrap}\n"
      ".pbobjh h3{margin:0;font-size:15.5px;color:var(--ink);flex:1 1 auto}\n"
      ".pbobjt{font-size:9.5px;letter-spacing:.09em;text-transform:uppercase;\n"
      "  color:var(--mute);border:1px solid var(--line2);padding:1px 5px}\n"
      ".pbobjs{font-size:17px;font-weight:600;font-variant-numeric:tabular-nums}\n"
      ".pbobjs i{font-style:normal;font-size:11px;font-weight:400;\n"
      "  letter-spacing:.03em;margin-left:3px}\n"
      ".pbobjs.good{color:var(--green)} .pbobjs.part{color:var(--blue)}\n"
      ".pbobjs.risk{color:var(--gold-ink)} .pbobjs.short{color:var(--terra-ink)}\n"
      ".pbobjs.none{color:var(--mute)}\n"
      # ---------------------------------------------------- a key result
      ".pbkr{border:1px solid var(--line);border-radius:6px;padding:9px 12px 10px;\n"
      "  margin-top:8px;background:var(--panel)}\n"
      ".pbkrh{display:flex;gap:8px;align-items:baseline;flex-wrap:wrap}\n"
      ".pbkrn{font-size:9.5px;letter-spacing:.07em;text-transform:uppercase;\n"
      "  color:var(--mute);border:1px solid var(--line2);padding:1px 4px}\n"
      ".pbkrname{font-weight:600;color:var(--ink);flex:1 1 auto;font-size:13.5px}\n"
      ".pbkrw{font-size:11px;color:var(--mute)}\n"
      ".pbkrs{font-size:14.5px;font-weight:600;font-variant-numeric:tabular-nums}\n"
      ".pbkrs i{font-style:normal;font-size:10.5px;font-weight:400;margin-left:2px}\n"
      ".pbkrs.good{color:var(--green)} .pbkrs.part{color:var(--blue)}\n"
      ".pbkrs.risk{color:var(--gold-ink)} .pbkrs.short{color:var(--terra-ink)}\n"
      ".pbkrs.none{color:var(--mute)}\n"
      # The bar runs to 1.50 because that is where the scheme stops giving
      # credit, and the mark at two thirds is the target -- without it a
      # full-looking bar could mean 1.00 or 1.50.
      ".pbkrbar{position:relative;height:7px;border-radius:4px;margin:7px 0 5px;\n"
      "  background:var(--line3);overflow:hidden}\n"
      ".pbkrbar i{display:block;height:100%;border-radius:4px;background:var(--mute)}\n"
      ".pbkrbar u{position:absolute;top:-2px;bottom:-2px;left:66.6%;width:1px;\n"
      "  background:var(--ink);opacity:.45}\n"
      ".pbkrbar.good i{background:var(--green)}\n"
      ".pbkrbar.part i{background:var(--blue)}\n"
      ".pbkrbar.risk i{background:var(--gold)}\n"
      ".pbkrbar.short i{background:var(--terra)}\n"
      ".pbkrf{font-size:12.5px;color:var(--body)}\n"
      # The three months, as check-ins rather than a row of numbers: the
      # quarter is three promises, not one.
      ".pbchk{display:flex;flex-wrap:wrap;gap:5px;margin-top:7px}\n"
      ".pbchki{font-size:11px;padding:2px 6px;border:1px solid var(--line2);\n"
      "  border-radius:3px;color:var(--mute);background:var(--panel2)}\n"
      ".pbchki.on{color:var(--body);border-color:var(--line)}\n"
      ".pbchki b{font-weight:600;color:var(--ink);margin-right:3px}\n"
      ".pbokrf{margin-top:14px;font-size:11.5px}\n"
      "@media (max-width:560px){\n"
      "  .pbokrh{gap:10px}\n"
      "  .pbstat{flex:1 1 100%}\n"
      "}\n"
      "@media (max-width:560px){\n"
      "  .tmcard{width:150px}\n"
      "  .tmoc{font-size:12px}\n"
      "}\n"
      "</style>", 1)],
))

# =====================================================================
# 13. The quarterly scorecard, in OKR shape.
#
# "I don't see the Quarterly score cards -- this should look like a score
# card in OKR format." The data has been there all along: plb_sheet_for
# returns every measure with its target, actual and ratio, the attributes
# with their milestones, the months with their points, and the calc with
# Achievement and the payout factor. What was missing was the SHAPE. A
# seven-column table is a correct statement of a quarter and it is not a
# scorecard; an objective with key results under it, each carrying one
# number between 0 and 1, is.
#
# Nothing here computes anything twice. Objective 1's score is Achievement,
# which the scheme worked out; each key result's score is that measure's
# own ratio over a hundred. Objective 2 is the mean of the attribute points
# across the months that were actually scored, said in those words, because
# attributes are scored monthly and never quarterly and there is no other
# honest reading of them as a quarter.
#
# The code is lifted from build/app/screen-plb.js between two markers
# rather than written out again here. That screen is already inside
# app_page, so an addition to it must be injected -- and a copy of the
# addition living in this file would be a second place to fix a bug in.
# =====================================================================
_PLB_SRC = io.open("build/app/screen-plb.js", encoding="utf-8").read()
_A = _PLB_SRC.index("/* OKR-SCORECARD-START")
_B = _PLB_SRC.index("/* OKR-SCORECARD-END */")
PLB_OKR = _PLB_SRC[_A:_B]
if "function pbOkr(" not in PLB_OKR:
    sys.exit("::error::the OKR markers in screen-plb.js no longer bracket pbOkr")

PATCHES.append((
    "the quarterly scorecard in OKR shape",
    "function pbOkr(",
    [
        # The four functions go in immediately above the table they sit on
        # top of, so somebody reading the file finds them next to each other.
        ("function pbGoalSheet(s){",
         PLB_OKR + "\nfunction pbGoalSheet(s){", 1),

        # And the card is composed FIRST, because it is the answer and the
        # tables under it are the working. A scorecard below its own
        # evidence is not a scorecard.
        ("(s ? pbGoalSheet(s) + pbMonthTable(s)",
         "(s ? pbOkr(s) + pbGoalSheet(s) + pbMonthTable(s)", 1),
    ],
))

# =====================================================================
# 14. THE FLOATING QUESTION MARK
#
# "There is a lot of explanatory or helping text making this tool all
# cluttered, move all that to a floating question mark button, which will
# give explanation of the open screen and tab."
#
# The module is in build/app/screen-help.js and explains itself. What is
# worth saying here is why it collects the prose at RENDER TIME rather
# than this file editing it out of the page.
#
# The application is one row of app_page and the explanatory text is
# spread through dozens of string concatenations inside it. Each one
# removed by hand would be a patch rule, a quoted fragment, and a chance
# to break a screen -- and the next paragraph anybody writes would be
# back on the page with nothing to catch it. A rule applied after each
# draw covers the screens that exist, the screens inside app_page this
# repository has never had the text of, and the screens nobody has
# written yet.
#
# Nothing is deleted. Everything moved is in the panel, under the screen
# it came off.
SCREEN_HELP = io.open("build/app/screen-help.js", encoding="utf-8").read()

PATCHES.append((
    "the floating question mark",
    "function qhMount(",
    [
        # The stylesheet ends in exactly one place.
        ("</style></head><body>",
         '/* ------------------------------------------------ the help panel\n'
         '   The button clears the mobile bar, which is 56px and carries a\n'
         '   safe-area inset under it on a phone with a home indicator. */\n'
         '#qhbtn{position:fixed;right:16px;bottom:16px;z-index:70;\n'
         '  width:48px;height:48px;border-radius:999px;border:0;cursor:pointer;\n'
         '  display:grid;place-items:center;background:var(--ink);color:#fff;\n'
         '  box-shadow:0 6px 18px rgba(16,24,40,.28);padding:0;min-height:0}\n'
         '#qhbtn:hover{filter:brightness(1.12)}\n'
         '#qhbtn:focus-visible{outline:3px solid var(--blue);outline-offset:3px}\n'
         '/* A dot, not a number: how much was moved off the screen is not a\n'
         '   thing anybody needs counted. */\n'
         '#qhbtn.has::after{content:"";position:absolute;top:9px;right:9px;\n'
         '  width:9px;height:9px;border-radius:999px;background:var(--gold);\n'
         '  border:2px solid var(--ink)}\n'
         '#qhscrim{position:fixed;inset:0;z-index:71;background:rgba(16,24,40,.34);\n'
         '  opacity:0;pointer-events:none;transition:opacity .18s ease}\n'
         '#qhscrim.on{opacity:1;pointer-events:auto}\n'
         '.qhpanel{position:fixed;top:0;right:0;bottom:0;z-index:72;width:min(420px,92vw);\n'
         '  background:var(--panel);border-left:1px solid var(--line);overflow-y:auto;\n'
         '  transform:translateX(102%);transition:transform .2s ease;\n'
         '  padding:18px 20px calc(24px + env(safe-area-inset-bottom));\n'
         '  box-shadow:-10px 0 30px rgba(16,24,40,.14)}\n'
         '.qhpanel.on{transform:translateX(0)}\n'
         '.qhhead{display:flex;align-items:flex-start;gap:12px;margin-bottom:4px}\n'
         '.qhhead h2{margin:0;font-size:19px;flex:1}\n'
         '.qhx{border:0;background:transparent;font-size:26px;line-height:1;\n'
         '  color:var(--mute);cursor:pointer;padding:0 2px;min-height:0}\n'
         '.qhpanel h3{font-size:12px;text-transform:uppercase;letter-spacing:.5px;\n'
         '  color:var(--mute);margin:20px 0 7px}\n'
         '.qhwhat{margin:2px 0 0;color:var(--body);font-size:14.5px}\n'
         '.qhsteps{margin:0;padding-left:20px;color:var(--body);font-size:13.5px}\n'
         '.qhsteps li{margin:0 0 7px;line-height:1.5}\n'
         '.qhjourney{margin:0;font-size:13.5px}\n'
         '.qhjourney dt{font-weight:600;color:var(--ink);margin-top:10px}\n'
         '.qhjourney dt:first-child{margin-top:0}\n'
         '.qhjourney dd{margin:2px 0 0;color:var(--body);line-height:1.5}\n'
         '.qhmoved{font-size:13px;color:var(--mute)}\n'
         '.qhmoved p{margin:0 0 9px;line-height:1.5;padding-left:11px;\n'
         '  border-left:2px solid var(--line2)}\n'
         '.qhfoot{margin:22px 0 0;font-size:11px;color:var(--mute)}\n'
         '@media (max-width:760px){\n'
         '  #qhbtn{bottom:calc(68px + env(safe-area-inset-bottom))}\n'
         '  .qhpanel{width:100vw;border-left:0}\n'
         '}\n'
         '@media (prefers-reduced-motion:reduce){\n'
         '  .qhpanel,#qhscrim{transition:none}\n'
         '}\n'
         '</style></head><body>', 1),

        # The module goes in above currentTab(), which it calls.
        ("function currentTab(){",
         SCREEN_HELP + "\nfunction currentTab(){", 1),
    ],
))

# =====================================================================
# 15. THE DASHBOARD, IN THE CONSOLE'S INFORMATION DESIGN
#
# "Giving you an example on how efficiently the Dashboard should represent
# the data that people would be updating daily:
# https://cruxindia.github.io/crux-console/"
#
# That page is one HTML file in cruxindia/crux-console, and what makes it
# work is the ORDER, not the palette: a row of stat tiles each carrying
# one number and a coloured edge, then a wide panel of detail beside a
# narrow one that summarises it, then the things waiting to be done.
#
# Taken here into this tool's own tokens rather than the console's navy,
# and without its 200KB of inlined Chart.js -- a doughnut of three states
# and a row of progress bars are two arcs and a div each, and a charting
# library is not worth a third of the page weight to draw them.
#
# The old vToday is replaced whole, by span, rather than edited: it led
# with escalations and OGL, which is other people's work arriving, and the
# scheme the company is about to run on is measured monthly and paid
# quarterly. The first thing on opening the tool should be whether you
# have filed today and whether you are on track. The operational counts
# keep their place, lower down.
SCREEN_TODAY = io.open("build/app/screen-today.js", encoding="utf-8").read()

PATCHES.append((
    "the dashboard, in the console's shape",
    "function tdRender(",
    [
        # From the old screen up to the helper that follows it. tile() goes
        # with it: nothing else in the page calls it.
        (("async function vToday(){", "function tile(v,l){"),
         SCREEN_TODAY + "\n", 1),

        ('.hrawarn{color:var(--gold-ink);font-size:12px;line-height:1.45}',
         '.hrawarn{color:var(--gold-ink);font-size:12px;line-height:1.45}\n'
         '/* --------------------------------- the three states, as colour\n'
         '   on target / part of the way / behind, used by the tiles, the\n'
         '   bars, the doughnut and its legend so one measure cannot be two\n'
         '   colours in two places.\n'
         '\n'
         '   These are NOT --green/--gold/--terra. Those were tried first\n'
         '   and fail the one test a doughnut has to pass: --gold #8a6d1f\n'
         '   and --terra #b4562f are 9.6 apart to a reader with full colour\n'
         '   vision and 1.8 apart under deuteranopia, which is to say the\n'
         '   middle arc and the behind arc are one arc. The tool\'s palette\n'
         '   is deliberately muted and no three steps of it separate, so\n'
         '   these are stepped out until they do: 30.3 and 24.7 on the\n'
         '   worst adjacent pair, both ways.\n'
         '\n'
         '   The middle step sits below 3:1 against the panel, so it is\n'
         '   never the only thing saying what a figure means -- the legend\n'
         '   carries the words and the counts, every bar carries its own\n'
         '   percentage in ink beside it, and the table names every\n'
         '   measure. */\n'
         ':root{--c-ok:#2f7355;--c-part:#d6b24a;--c-behind:#a03f18;\n'
         '  --c-none:#5c6470}\n'
         '/* ------------------------------------------------- the dashboard\n'
         '   Five tiles across at full width, two on a phone. The edge is\n'
         '   4px and carries the state; the figure is tabular so a column\n'
         '   of them reads as a column. */\n'
         '.tdkpis{display:grid;grid-template-columns:repeat(5,1fr);gap:12px;\n'
         '  margin:0 0 16px}\n'
         '.tdk{position:relative;overflow:hidden;background:var(--panel);\n'
         '  border:1px solid var(--line);border-radius:12px;padding:12px 14px}\n'
         '.tdk .edge{position:absolute;left:0;top:0;bottom:0;width:4px;\n'
         '  background:var(--c-none)}\n'
         '.tdk-ok .edge{background:var(--c-ok)}\n'
         '.tdk-part .edge{background:var(--c-part)}\n'
         '.tdk-behind .edge{background:var(--c-behind)}\n'
         '.tdk .k{font-size:10.5px;font-weight:700;text-transform:uppercase;\n'
         '  letter-spacing:.5px;color:var(--mute)}\n'
         '.tdk .v{font-size:25px;line-height:1.15;margin:3px 0 1px;color:var(--ink);\n'
         '  font-variant-numeric:tabular-nums}\n'
         '.tdk .v .of{font-size:14px;color:var(--mute)}\n'
         '.tdk .s{font-size:11.5px;color:var(--mute)}\n'
         '.tdgrid{display:grid;gap:14px;align-items:start;margin:0 0 14px}\n'
         '.tdg2{grid-template-columns:1.6fr 1fr}\n'
         '.tdg11{grid-template-columns:1fr 1fr}\n'
         '.tdgrid .card{margin:0}\n'
         '.tdgrid h3{margin:0 0 10px;font-size:14px;display:flex;\n'
         '  align-items:baseline;gap:8px}\n'
         '.tdgrid h3 .sub{font-size:11.5px;color:var(--mute);font-weight:400}\n'
         '/* The table. Numbers right, text left, and the bar in its own\n'
         '   column so the figures above and below it still line up. */\n'
         '.tdt{width:100%;border-collapse:collapse;font-size:13px}\n'
         '.tdt th{text-align:left;font-size:10px;text-transform:uppercase;\n'
         '  letter-spacing:.5px;color:var(--mute);font-weight:700;padding:5px 7px;\n'
         '  border-bottom:1px solid var(--line)}\n'
         '.tdt td{padding:7px;border-bottom:1px solid var(--line3)}\n'
         '.tdt th.r,.tdt td.r{text-align:right}\n'
         '.tdt .num{font-variant-numeric:tabular-nums}\n'
         '.tdprog{display:flex;align-items:center;gap:9px;min-width:150px}\n'
         '.tdprog .num{font-size:12px;width:46px;text-align:right}\n'
         '.tdbar{flex:1;height:6px;border-radius:4px;background:var(--line2);\n'
         '  overflow:hidden;min-width:60px}\n'
         '.tdbar i{display:block;height:100%;border-radius:4px}\n'
         '.tdbar i.ok{background:var(--c-ok)}\n'
         '.tdbar i.part{background:var(--c-part)}\n'
         '.tdbar i.behind{background:var(--c-behind)}\n'
         '.tdbar i.none{background:var(--line)}\n'
         '/* The doughnut. Three arcs, started at twelve o\'clock, with the\n'
         '   words in the legend -- nobody reads this by colour alone. */\n'
         '.tddonut{position:relative;height:156px;margin:2px 0 10px}\n'
         '.tddonut svg{width:100%;height:100%;transform:rotate(-90deg)}\n'
         '.tddonut .trk{fill:none;stroke:var(--line2);stroke-width:11}\n'
         '.tddonut .seg{fill:none;stroke-width:11}\n'
         '.tddonut .mid{position:absolute;inset:0;display:flex;\n'
         '  flex-direction:column;align-items:center;justify-content:center;\n'
         '  pointer-events:none}\n'
         '.tddonut .mid b{font-size:24px;color:var(--ink);\n'
         '  font-variant-numeric:tabular-nums;line-height:1}\n'
         '.tddonut .mid span{font-size:11px;color:var(--mute);margin-top:2px}\n'
         '.tdleg{list-style:none;margin:0;padding:0;font-size:12.5px}\n'
         '.tdleg li{display:flex;align-items:center;gap:8px;padding:4px 0;\n'
         '  color:var(--body);border-top:1px solid var(--line3)}\n'
         '.tdleg li:first-child{border-top:0}\n'
         '.tdleg li b{margin-left:auto;font-variant-numeric:tabular-nums;\n'
         '  color:var(--ink)}\n'
         '.tdleg .dot{width:9px;height:9px;border-radius:3px;flex:0 0 9px}\n'
         '.tdleg .dot.ok{background:var(--c-ok)}\n'
         '.tdleg .dot.part{background:var(--c-part)}\n'
         '.tdleg .dot.behind{background:var(--c-behind)}\n'
         '.tdwait{list-style:none;margin:0;padding:0;font-size:13.5px}\n'
         '.tdwait li{display:flex;align-items:center;gap:10px;padding:8px 0;\n'
         '  border-top:1px solid var(--line3);color:var(--body)}\n'
         '.tdwait li:first-child{border-top:0}\n'
         '.tdwait li b{font-size:19px;color:var(--ink);min-width:28px;\n'
         '  font-variant-numeric:tabular-nums}\n'
         '.tdwait li a{margin-left:auto;font-size:12.5px}\n'
         '.tdq{display:grid;grid-template-columns:1fr auto;gap:7px 12px;margin:0;\n'
         '  font-size:13.5px}\n'
         '.tdq dt{color:var(--mute)}\n'
         '.tdq dd{margin:0;text-align:right;color:var(--ink);\n'
         '  font-variant-numeric:tabular-nums}\n'
         '.tdq dd .of{color:var(--mute);font-size:12px}\n'
         '@media (max-width:1040px){\n'
         '  .tdkpis{grid-template-columns:repeat(3,1fr)}\n'
         '  .tdg2,.tdg11{grid-template-columns:1fr}\n'
         '}\n'
         '@media (max-width:620px){\n'
         '  .tdkpis{grid-template-columns:repeat(2,1fr)}\n'
         '  .tdk .v{font-size:22px}\n'
         '  .tdt{min-width:420px}\n'
         '  .tdprog{min-width:110px}\n'
         '}', 1),
    ],
))

# ================================================ 16. SIGNING IN FORGETS
# "when Admin uses 'Look at Crux as someone else', this should actually log
#  in the admin to that person's account and use it as that person."
#
# The SESSION already is that person's. auth_act_as mints a real auth_session
# row for them with acting_actor_id set, hands back their app_role,
# department, chair, scope_level and screens, and writes an ACTED_AS audit
# row naming both people. The page keeps the administrator's own token under
# cruxAdminToken and swaps `token`.
#
# THE SCREENS ARE NOT. start() sets `me`, repaints the navigation and routes
# -- and clears no screen state at all. Twelve screens keep their data in a
# module-level object that survives the swap, and vPerf only re-reads the
# team `if (!PF.team)`. So after acting as somebody else the tool showed the
# ADMINISTRATOR'S team under "whose targets are yours to set", the
# administrator's chart on My team & structure, the administrator's goal
# sheet, and whoever the administrator last had open, still open.
#
# So signing in as anybody -- the first sign-in, acting as somebody, and
# stopping acting, all three of which go through start() -- forgets every
# screen first.
#
# HOW THE INITIAL VALUES ARE KNOWN. Not by listing them again here, which
# would be a second copy to keep in step. The first call to forgetScreens()
# happens inside the first start(), which is before route() and therefore
# before any screen has fetched anything -- so what the objects hold at that
# moment IS their initial value. It is snapshotted then and restored on every
# later call.
#
# The objects are restored IN PLACE rather than reassigned, because the
# screen files close over them.
#
# build/test/forget_check.mjs asserts this list against every `var XX = {` in
# build/app/, so adding a screen cannot quietly leave one behind.
PATCHES.append((
    "signing in forgets the last person's screens",
    'function forgetScreens(',
    [('async function start(person){\n'
      '  me = person;',
      '/* Every screen that keeps what it fetched. */\n'
      'var SCREEN_STATE = ["AA","HE","HRA","MG","MX","MY","PB","PF","PL","QH","TD","TM"];\n'
      'var SCREEN_FRESH = null;\n'
      'function forgetScreens(){\n'
      '  if (!SCREEN_FRESH) {\n'
      '    /* First sign-in: nothing has been fetched, so this IS the start. */\n'
      '    SCREEN_FRESH = {};\n'
      '    SCREEN_STATE.forEach(function(n){\n'
      '      try { SCREEN_FRESH[n] = JSON.stringify(window[n]); } catch (e) {}\n'
      '    });\n'
      '    return;\n'
      '  }\n'
      '  SCREEN_STATE.forEach(function(n){\n'
      '    var was = SCREEN_FRESH[n], now = window[n];\n'
      '    if (was === undefined || !now || typeof now !== "object") return;\n'
      '    try {\n'
      '      var fresh = JSON.parse(was);\n'
      '      Object.keys(now).forEach(function(k){ delete now[k]; });\n'
      '      Object.keys(fresh).forEach(function(k){ now[k] = fresh[k]; });\n'
      '    } catch (e) { /* a screen that cannot be reset is left alone */ }\n'
      '  });\n'
      '}\n'
      '\n'
      'async function start(person){\n'
      '  /* Before anything reads `me`: the person has changed, so nothing\n'
      '     any screen is still holding belongs to them. */\n'
      '  forgetScreens();\n'
      '  me = person;', 1)],
))

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
