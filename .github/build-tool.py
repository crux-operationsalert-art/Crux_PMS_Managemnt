"""Insert the project-key shim into the fetched application and write index.html.

Kept out of the workflow file because a heredoc inside a YAML block scalar is
how the first version of this broke: the inner document dedented to column
zero and took the YAML with it.

It also applies one correctness patch on the way past. See GUARD below.
"""
import io
import sys

app = io.open("app.raw", encoding="utf-8").read()
shim = io.open("shim.html", encoding="utf-8").read()

# ---------------------------------------------------------------- GUARD
# localStorage THROWS rather than returning null when a browser refuses
# site data: a private window, blocked cookies, some managed-device
# policies. The application reads it in the FIRST statement of its script:
#
#     var token = localStorage.getItem("cruxToken") || "";
#
# so the throw takes the whole file with it. Nothing after that line runs --
# including the line that wires the Sign in button and the call to boot()
# that renders the Google button. What is left on screen is the sign-in
# card, which is static HTML, with a button attached to nothing. It looks
# like the tool is up and sign-in is broken, and no request ever reaches
# the server, so nothing is logged and there is nothing to find.
#
# Reproduced in Chromium with storage blocked: one "The operation is
# insecure." and el("go").onclick undefined.
#
# This belongs in app_page and there is a migration written for it --
# build/migration/188_the_line_that_locked_somebody_out.sql. It is applied
# here as well because app_page could not be reached when people were
# locked out, and because a republish must never quietly undo it. Once 188
# has been applied this becomes a no-op: the guards are already present and
# every replacement below finds nothing to do, which is checked rather than
# assumed.
GUARD = [
    ('var token = localStorage.getItem("cruxToken") || "";',
     'function aaGet(k){ try { return localStorage.getItem(k); } catch (e) { return null; } }\n'
     'function aaSet(k, v){ try { localStorage.setItem(k, v); } catch (e) { /* memory only */ } }\n'
     'function aaDrop(k){ try { localStorage.removeItem(k); } catch (e) { /* nothing to do */ } }\n'
     'var token = aaGet("cruxToken") || "";',
     1),
    ('localStorage.setItem("cruxToken", token);',
     'aaSet("cruxToken", token);',
     2),
    ('token=""; localStorage.removeItem("cruxToken"); me=null;',
     'token=""; aaDrop("cruxToken"); aaDrop("cruxAdminToken"); me=null;',
     1),
]

already = "function aaGet(" in app
if already:
    print("app_page already carries the storage guards; nothing to patch.")
else:
    for old, new, want in GUARD:
        found = app.count(old)
        if found != want:
            sys.exit("::error::Storage guard: expected %d of %r, found %d. "
                     "The application has moved; re-check "
                     "build/migration/188 before publishing." % (want, old[:48], found))
        app = app.replace(old, new)
    print("Storage guards applied to %d call sites." % sum(w for _, _, w in GUARD))

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
