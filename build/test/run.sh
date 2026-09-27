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
out=""
for t in test_190_198 test_scope; do
  out="$out
$(psq -q -f "$REPO/build/test/$t.sql" 2>&1 | sed 's/^psql:[^ ]* //')"
done
echo "$out" | grep -E 'PASS|FAIL|ERROR|---' || true
pass=$(echo "$out" | grep -c 'PASS' || true)
fail=$(echo "$out" | grep -cE 'FAIL|ERROR' || true)

# The navigation and the database are two readers of one access policy. They
# are meant to agree, and nothing but this makes them.
echo
echo "== the navigation and the database, on every screen"
if "$REPO/build/test/check_access_matches_nav.py" "$DSN"; then :; else fail=$((fail + 1)); fi

echo
echo "== $pass passed, $fail failed"
[ "$fail" = "0" ] && [ -z "$missing" ]
