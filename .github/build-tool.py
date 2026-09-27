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

for name, sentinel, rules in PATCHES:
    if sentinel in app:
        print("%-32s already in app_page; skipped." % name)
        continue
    for old, new, want in rules:
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
