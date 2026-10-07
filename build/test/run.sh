#!/usr/bin/env bash
# Rebuild the database from build/schema alone, then run the behaviour tests
# against it.
#
#   ./build/test/run.sh
#
# This is the proof behind the claim in build/migration/README.md. The claim
# is that the repository can rebuild the database. A claim like that is worth
# nothing asserted, so this asserts nothing: it takes a blank Postgres, loads
# the baseline and nothing else -- no build/schema.sql, no fixture standing in
# for what the baseline was missing, no migration applied on top -- and then
# runs the same assertions the live project passes.
#
# It also counts what it built and says so, because "the load did not error"
# and "the database is there" are different sentences.
#
# Needs postgresql-16 on the path. Nothing here touches Supabase.
set -euo pipefail

PGBIN=${PGBIN:-/usr/lib/postgresql/16/bin}
RUNAS=${RUNAS:-crux}
BASE=${BASE:-/home/$RUNAS/pg}
PORT=${PORT:-55432}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
NODE=${NODE:-/opt/node22/bin/node}
PGJS=${PGJS:-/tmp/claude-0/node_modules}

as() { if [ "$(id -un)" = "$RUNAS" ]; then bash -c "$1"; else su "$RUNAS" -c "$1"; fi; }
DSN="host=$BASE port=$PORT user=$RUNAS dbname=crux"
psq() { psql "$DSN" "$@"; }

id -u "$RUNAS" >/dev/null 2>&1 || useradd -m "$RUNAS"

if ! as "$PGBIN/pg_ctl -D $BASE/data status" >/dev/null 2>&1; then
  rm -rf "$BASE"; mkdir -p "$BASE"; chown -R "$RUNAS" "$BASE"
  as "$PGBIN/initdb -D $BASE/data -U $RUNAS --auth=trust -E UTF8" >/dev/null
  as "$PGBIN/pg_ctl -D $BASE/data -l $BASE/log -o '-k $BASE -p $PORT -c listen_addresses=' -w start"
fi

as "$PGBIN/dropdb   -h $BASE -p $PORT -U $RUNAS --if-exists crux"
as "$PGBIN/createdb -h $BASE -p $PORT -U $RUNAS crux"

# The three roles Supabase creates for every project. The grants file and
# several policies name them, and a plain cluster has none of them.
echo "== the roles Supabase provides and a local cluster does not"
psq -q <<'SQL'
do $$ begin create role anon         nologin; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role service_role  nologin; exception when duplicate_object then null; end $$;
SQL

echo "== rebuilding from build/schema, and from nothing else"
PATH="$PGBIN:$PATH" "$REPO/build/schema/load.sh" "$DSN"

echo
echo "== what got built"
psq -tA <<'SQL'
select '   tables    ' || count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r';
select '   functions ' || count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prokind in ('f','p');
select '   views     ' || count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','seam') and c.relkind='v';
select '   indexes   ' || count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='i';
select '   triggers  ' || count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal;
select '   policies  ' || count(*) from pg_policies where schemaname='public';
SQL

# A function whose body calls a function that does not exist is created
# without complaint -- that is how person_merge_plan came to call
# person_merge_side, which was never there. Nothing in a load can catch it,
# so it is checked here, once, against everything that loaded.
#
# The bodies are read as text, which means the comments, the string literals
# and the temp tables in them have to come out first or the answer is mostly
# prose. Only names carrying an underscore are looked at: every function this
# project has written has one, and the ordinary English words that sit in
# front of a bracket do not.
echo
echo "== every function the bodies call is present"
missing=$(psq -tA <<'SQL'
with src as (
  select regexp_replace(
           regexp_replace(
             regexp_replace(
               regexp_replace(p.prosrc, '--[^\n]*', ' ', 'g'),
               '/\*.*?\*/', ' ', 'g'),
             '''[^'']*''', ' ', 'g'),
           'create\s+(temp\s+|temporary\s+)?table(\s+if\s+not\s+exists)?\s+[a-z0-9_]+', ' ', 'gi') as body
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public','stg') and p.prokind in ('f','p')),
called as (
  select distinct m[1] as name
    from src cross join lateral
         regexp_matches(body, '(?:^|[^a-zA-Z0-9_.$])([a-z][a-z0-9_]*_[a-z0-9_]+)\s*\(', 'g') m)
select string_agg(c.name, ', ' order by c.name)
  from called c
 where not exists (select 1 from pg_proc p2 where p2.proname = c.name)
   and not exists (select 1 from pg_type t where t.typname = c.name)
   -- pg_net is not installed on a plain cluster and never will be here
   and c.name not in ('http_post','get_diagnostics','make_interval','array_agg');
SQL
)
if [ -n "$missing" ]; then
  echo "   MISSING: $missing"
else
  echo "   none missing"
fi

echo
echo "== behaviour"
# || true on purpose: psql exits non-zero when an assertion RAISEs, and under
# set -e that killed the script before it could print WHICH one. A test runner
# that dies silently on a failing test is worse than no runner.
out=""
for t in test_190_198 test_scope test_task test_line test_seat test_seed test_flow test_link test_move test_split test_phase test_pip test_join test_mail test_welcome test_edit test_offer test_people test_account test_window test_quarter test_assign test_escalate test_partner test_ratio test_qedit; do
  out="$out
$(psq -q -f "$REPO/build/test/$t.sql" 2>&1 | sed 's/^psql:[^ ]* //' || true)"
done
echo "$out" | grep -E 'PASS|FAIL|ERROR|---' || true
pass=$(echo "$out" | grep -c 'PASS' || true)
fail=$(echo "$out" | grep -cE 'FAIL|ERROR' || true)

# Everything above this line is true of the DATABASE. None of it is true of the
# service until the values survive the trip through postgres.js -- and a text[]
# that arrived as a string would make requireScreen() decide access by
# substring, while an empty one would refuse everybody. Both are checked
# against the same driver at the same version.
echo
echo "== the boundary between Postgres and the service"
if [ -d "$PGJS/postgres" ] && [ -x "$NODE" ]; then
  if PGJS="$PGJS" "$NODE" "$REPO/build/test/driver_check.mjs"; then
    pass=$((pass + 10))
  else
    fail=$((fail + 1))
  fi
else
  echo "   skipped: postgres@3.4.5 is not installed here."
  echo "   npm install postgres@3.4.5, or set PGJS to a node_modules holding it."
  echo "   A check nobody can run must not read as a check that passed, so this"
  echo "   says so rather than staying quiet."
fi

# The quarterly scorecard shows the numbers behind somebody's bonus, and its
# denominators are not visible in a screenshot: a mean over months that were
# excluded, a ratio not capped where the scheme caps it, a band boundary off
# by one. Those are arithmetic, so they are checked as arithmetic. It needs no
# database -- it reads the block straight out of the screen file.
echo
echo "== the quarterly scorecard, in OKR shape"
if [ -x "$NODE" ]; then
  if "$NODE" "$REPO/build/test/okr_check.mjs"; then
    pass=$((pass + 22))
  else
    fail=$((fail + 1))
  fi
else
  echo "   skipped: node is not on this machine."
  missing="$missing okr"
fi

# The reminder carries a link and the HTML twin has to make it clickable.
# That half lives in the mail function, not the database, and the thing it
# must never do -- turn javascript: into an anchor -- is not visible in any
# e-mail anybody would look at.
echo
echo "== the links in the triggered mail"
if [ -x "$NODE" ]; then
  if "$NODE" "$REPO/build/test/linkify_check.mjs"; then
    pass=$((pass + 14))
  else
    fail=$((fail + 1))
  fi
else
  echo "   skipped: node is not on this machine."
  missing="$missing linkify"
fi

# The floating question mark decides, by a rule, which paragraphs come off
# every screen in the tool -- including screens whose text lives in app_page
# and not in this repository. Too generous and an error message disappears
# into a panel nobody opens; too mean and the clutter stays. The rule is
# asserted against the shapes it will actually meet.
echo
echo "== the floating question mark"
if [ -x "$NODE" ]; then
  if "$NODE" "$REPO/build/test/help_check.mjs"; then
    pass=$((pass + 20))
  else
    fail=$((fail + 1))
  fi
else
  echo "   skipped: node is not on this machine."
  missing="$missing help"
fi

# The dashboard is the screen most people open first, and almost everything
# that could be wrong on it looks fine: an arc that does not account for the
# circle, a bar drawn past its own track, a null printed as a nought, a
# threshold written in two places that drift apart.
echo
echo "== the dashboard"
if [ -x "$NODE" ]; then
  if "$NODE" "$REPO/build/test/today_check.mjs"; then
    pass=$((pass + 28))
  else
    fail=$((fail + 1))
  fi
else
  echo "   skipped: node is not on this machine."
  missing="$missing today"
fi

# The flat list of everybody. The picker on it is the one place the screen
# predicts a refusal rather than asking for one, so it has to predict it
# exactly; and the list has to be drawn for the administrator and HR, who
# are the two people who manage nobody.
echo
echo "== all people, the flat list"
if [ -x "$NODE" ]; then
  if "$NODE" "$REPO/build/test/list_check.mjs"; then
    pass=$((pass + 59))
  else
    fail=$((fail + 1))
  fi
else
  echo "   skipped: node is not on this machine."
  missing="$missing list"
fi

# The clock. For three weeks in four the KPI controls were offered and the
# database refused them, which is migration 242's defect said about the
# calendar instead of the reporting line.
echo
echo "== the window for setting KPIs"
if [ -x "$NODE" ]; then
  if "$NODE" "$REPO/build/test/window_check.mjs"; then
    pass=$((pass + 35))
  else
    fail=$((fail + 1))
  fi
else
  echo "   skipped: node is not on this machine."
  missing="$missing window"
fi

# Signing in as somebody else has to forget the last person's screens, and
# the list of screens it forgets has to keep covering all of them.
echo
echo "== signing in forgets the last person"
if [ -x "$NODE" ]; then
  if "$NODE" "$REPO/build/test/forget_check.mjs"; then
    pass=$((pass + 15))
  else
    fail=$((fail + 1))
  fi
else
  echo "   skipped: node is not on this machine."
  missing="$missing forget"
fi

# Can somebody actually GET to it?
#
# Three changes in one week passed the build, passed every test, were
# published, and reached no screen: the quarterly rebuild written into the
# dead part of a mirror file, patch 18 skipped on every build by a sentinel
# that reported somebody else's work, and the monthly-shaped quarterly card
# built on a tab the owner was never told to open. No test could catch any of
# them, because a test proves a FUNCTION is correct and says nothing about
# whether a person can get to it.
#
# reach_check asks the only question those three had in common: starting from
# the screen the owner is told to open, is there a path of calls that reaches
# this? It runs over the published index.html, which is the artefact a person
# actually loads.
echo
echo "== every feature is reachable from the screen it belongs on"
if [ -x "$NODE" ]; then
  if "$NODE" "$REPO/build/test/reach_check.mjs"; then
    pass=$((pass + 9))
  else
    fail=$((fail + 1))
  fi
else
  echo "   skipped: node is not on this machine."
  missing="$missing reach"
fi

# The navigation and the database are two readers of one access policy. They
# are meant to agree, and nothing but this makes them.
echo
echo "== the navigation and the database, on every screen"
if "$REPO/build/test/check_access_matches_nav.py" "$DSN"; then :; else fail=$((fail + 1)); fi

echo
echo "== $pass passed, $fail failed"
[ "$fail" = "0" ] && [ -z "$missing" ]
