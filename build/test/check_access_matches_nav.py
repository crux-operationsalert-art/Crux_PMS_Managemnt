#!/usr/bin/env python3
"""The navigation and the database must answer the same question the same way.

The published tool decides what to draw with SCREENS, CHAIR_LEVEL and UNDER.
The ops service decides what to serve with access_level_screen,
access_chair_level and access_screen_parent. Those are two readers of one
policy and they are meant to agree; nothing but this check makes them.

    build/test/check_access_matches_nav.py [connection string]

It reads index.html — the published tool, not a copy of it — and compares
every (level, screen) pair against what access_may_open() would answer.
Exit 0 when they agree, 1 when they do not, and it names each disagreement.
"""
import json
import re
import subprocess
import sys

REPO = __file__.rsplit("/build/", 1)[0]
DSN = sys.argv[1] if len(sys.argv) > 1 else "host=/home/crux/pg port=55432 user=crux dbname=crux"


def js_object(src, name):
    """Pull `var NAME = { ... };` out of the page and read it as JSON.

    The page is hand-written JavaScript, so the keys are bare and the strings
    are double quoted. Nothing in these three objects needs more than that."""
    i = src.index(name)
    i = src.index("{", i)
    depth, j = 0, i
    while True:
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                break
        j += 1
    body = src[i:j + 1]
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    body = re.sub(r"(?m)^\s*//.*$", "", body)
    body = re.sub(r"([{,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:", r'\1"\2":', body)
    body = re.sub(r",(\s*[}\]])", r"\1", body)
    return json.loads(body)


def psql(sql):
    out = subprocess.run(["psql", DSN, "-tA", "-F", "|", "-c", sql],
                         capture_output=True, text=True)
    if out.returncode:
        print(out.stderr.strip(), file=sys.stderr)
        sys.exit(2)
    return [l.split("|") for l in out.stdout.strip().split("\n") if l]


page = open(REPO + "/index.html", encoding="utf-8").read()
screens = js_object(page, "var SCREENS =")
under = js_object(page, "var UNDER =")
chair_level = js_object(page, "var CHAIR_LEVEL =")

db_screens = {}
for level, screen in psql("select level, screen from access_level_screen"):
    db_screens.setdefault(level, set()).add(screen)
db_under = dict(psql("select screen, parent from access_screen_parent"))
db_chair = dict(psql("select chair_title, level from access_chair_level"))

bad = []

# Every screen the page knows about, against every level the page knows about.
every_screen = sorted({s for v in screens.values() for s in v} | set(under))
for level in sorted(screens):
    for screen in every_screen:
        key = under.get(screen, screen)
        page_says = key in screens[level]
        db_says = db_under.get(screen, screen) in db_screens.get(level, set())
        if page_says != db_says:
            bad.append(f"  {level:10s} {screen:10s} page={page_says!s:5s} database={db_says!s:5s}")

# The admin level is the page's short circuit and the database's; it is not in
# SCREENS at all, so it is checked on its own terms.
if "admin" in db_screens:
    bad.append("  admin carries rows in access_level_screen; it is meant to short-circuit before reading it")

for title, level in chair_level.items():
    if db_chair.get(title) != level:
        bad.append(f"  chair {title!r}: page={level} database={db_chair.get(title)}")
for title, level in db_chair.items():
    if title not in chair_level:
        bad.append(f"  chair {title!r} is in the database and not in the page")

checked = len(screens) * len(every_screen) + len(chair_level)
if bad:
    print(f"FAIL  {len(bad)} disagreement(s) out of {checked} checked")
    print("\n".join(bad))
    sys.exit(1)
print(f"PASS  the navigation and the database agree on all {checked} of them "
      f"({len(screens)} levels x {len(every_screen)} screens, "
      f"{len(chair_level)} chair titles)")
