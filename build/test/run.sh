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
echo
echo "== every function the bodies call is present"
missing=$(psq -tA <<'SQL'
with called as (
  select distinct m[1] as name
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral regexp_matches(p.prosrc, '([a-z][a-z0-9_]{3,})\s*\(', 'g') m
   where n.nspname = 'public' and p.prokind in ('f','p'))
select string_agg(c.name, ', ' order by c.name)
  from called c
 where not exists (select 1 from pg_proc p2 join pg_namespace n2 on n2.oid = p2.pronamespace
                    where p2.proname = c.name and n2.nspname in ('public','pg_catalog','cron','extensions'))
   and not exists (select 1 from pg_type t where t.typname = c.name)
   and c.name not in (
     -- plpgsql keywords and SQL constructs the pattern also matches
     'select','insert','update','delete','values','where','when','case','coalesce',
     'exists','array','exception','raise','return','returns','declare','begin','loop',
     'using','order','group','having','union','distinct','filter','over','partition',
     'interval','extract','position','overlay','substring','trim','cast','row','rows',
     'grouping','lateral','with','recursive','then','else','from','into','perform',
     'execute','format','concat','nullif','greatest','least','jsonb','json','text',
     'numeric','decimal','character','timestamp','time','date','boolean','integer',
     'bigint','smallint','uuid','interval','xmlelement','collate','offset','limit',
     'fetch','only','natural','inner','outer','left','right','full','cross','join',
     'on','and','or','not','null','true','false','end','elsif','elseif','if','while',
     'for','foreach','continue','exit','assert','get','diagnostics','found','new','old')
SQL
)
if [ -n "$missing" ]; then
  echo "   MISSING: $missing"
else
  echo "   none missing"
fi

echo
echo "== behaviour"
out=$(psq -q -f "$REPO/build/test/test_190_198.sql" 2>&1 | sed 's/^psql:[^ ]* //')
echo "$out" | grep -E 'PASS|FAIL|ERROR|---' || true
pass=$(echo "$out" | grep -c 'PASS' || true)
fail=$(echo "$out" | grep -cE 'FAIL|ERROR' || true)
echo
echo "== $pass passed, $fail failed"
[ "$fail" = "0" ] && [ -z "$missing" ]
