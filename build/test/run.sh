#!/usr/bin/env bash
# Run migrations 190-199 and their behaviour tests against a throwaway local
# Postgres, so they are proved before they are applied to the project.
#
# Why this exists: "CREATE OR REPLACE FUNCTION succeeded" is not a test.
# plpgsql checks syntax when a function is created and nothing at all about
# the functions its body calls. Everything here RUNS the code.
#
#   ./build/test/run.sh
#
# Needs postgresql-16 on the path. Nothing touches Supabase.
set -euo pipefail

PGBIN=${PGBIN:-/usr/lib/postgresql/16/bin}
RUNAS=${RUNAS:-crux}
BASE=${BASE:-/home/$RUNAS/pg}
PORT=${PORT:-55432}
REPO=$(cd "$(dirname "$0")/../.." && pwd)

as() { if [ "$(id -un)" = "$RUNAS" ]; then bash -c "$1"; else su "$RUNAS" -c "$1"; fi; }
psq() { psql "host=$BASE port=$PORT user=$RUNAS dbname=crux" "$@"; }

id -u "$RUNAS" >/dev/null 2>&1 || useradd -m "$RUNAS"

if ! as "$PGBIN/pg_ctl -D $BASE/data status" >/dev/null 2>&1; then
  rm -rf "$BASE"; mkdir -p "$BASE"; chown -R "$RUNAS" "$BASE"
  as "$PGBIN/initdb -D $BASE/data -U $RUNAS --auth=trust -E UTF8" >/dev/null
  as "$PGBIN/pg_ctl -D $BASE/data -l $BASE/log -o '-k $BASE -p $PORT -c listen_addresses=' -w start"
fi

as "$PGBIN/dropdb   -h $BASE -p $PORT -U $RUNAS --if-exists crux"
as "$PGBIN/createdb -h $BASE -p $PORT -U $RUNAS crux"

# The base schema, with the two expression-based UNIQUE constraints rewritten
# as indexes -- they are not valid table constraints and never were, which is
# one more sign that build/schema.sql is a design document rather than the
# DDL that built the project.
python3 - "$REPO" <<'PY'
import io, sys
r = sys.argv[1]
a = io.open(r + "/build/schema.sql", encoding="utf-8").read()
a = a.replace(",\n  constraint client_contact_uniq unique (client_id, kind, lower(email))\n", "\n")
a = a.replace(",\n  constraint client_zone_uniq unique (client_id, lower(name))\n", "\n")
a += "\ncreate unique index client_contact_uniq on client_contact (client_id, kind, lower(email));\n"
a += "create unique index client_zone_uniq on client_zone (client_id, lower(name));\n"
io.open("/tmp/crux_schema_test.sql", "w", encoding="utf-8").write(a)
PY

echo "== base schema"
psq -q -c "create extension if not exists pgcrypto;" >/dev/null
psq -q -f /tmp/crux_schema_test.sql 2>&1 | grep -c ERROR || true

echo "== what Supabase provides and a local cluster does not"
psq -q <<'SQL' >/dev/null
do $$ begin create role anon;          exception when duplicate_object then null; end $$;
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
create schema if not exists cron;
create or replace function cron.schedule(jobname text, sched text, cmd text)
returns bigint language sql as $$ select 1::bigint $$;
SQL

echo "== the live shape, reconstructed (see the header of the fixture)"
psq -v ON_ERROR_STOP=1 -q -f "$REPO/build/test/fixture_live_shape.sql"

echo "== migrations"
for f in 190_the_monthly_kpi_cycle 191_assigning_a_kpi_for_a_month \
         192_filing_a_number 193_how_a_number_climbs 194_setting_and_filing \
         195_what_a_manager_sees 196_the_matrix_that_goes_out \
         197_the_reminder_on_the_cadence 198_the_matrix_nudge \
         199_a_split_without_an_id_is_still_a_split \
         200_adds_is_a_default_nobody_set \
         201_the_tenth_of_the_month 202_my_tab; do
  psq -v ON_ERROR_STOP=1 -q -f "$REPO/build/migration/$f.sql" >/dev/null
  echo "   applied $f"
done

echo "== behaviour"
out=$(psq -q -f "$REPO/build/test/test_190_198.sql" 2>&1 | sed 's/^psql:[^ ]* //')
echo "$out" | grep -E 'PASS|FAIL|ERROR|---' || true
pass=$(echo "$out" | grep -c 'PASS' || true)
fail=$(echo "$out" | grep -cE 'FAIL|ERROR' || true)
echo
echo "== $pass passed, $fail failed"
[ "$fail" = "0" ]
