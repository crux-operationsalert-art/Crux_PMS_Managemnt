#!/usr/bin/env bash
# Rebuilds the database from this directory alone.
#
#   build/schema/load.sh "postgres://user@host/dbname"
#
# The order below is the whole point of splitting the baseline into files.
# Nothing here depends on the order the tables happened to be written in:
#
#   00  extensions and schemas   hand-written; tolerates a Postgres that has
#                                neither Supabase's extension schemas nor
#                                several of its extensions
#   05  types                    no table behind any of them
#   08  sequences                before the tables, because a column default
#                                that calls nextval on a sequence that does
#                                not exist is a table that will not load
#   10  tables                   columns and defaults only
#   20  keys                     before the foreign keys need them
#   40  functions                before the checks, because a CHECK can call
#                                one (person_mobile_shape does)
#   21  checks
#   22  foreign keys             last of the constraints, so table order is free
#   30  indexes                  some expression indexes call functions too
#   50  views                    read the tables
#   60  triggers                 call the functions
#   70  row level security
#   75  grants
#   80  comments
#   90  cron                     skipped unless pg_cron is installed
#
# check_function_bodies is off for the whole load. The definitions came out
# of a database where they worked; re-proving each one against a half-built
# schema would only force an ordering that does not exist.
set -euo pipefail

DB="${1:-}"
if [ -z "$DB" ]; then
  echo "usage: $0 <postgres connection string>" >&2
  exit 2
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run() {
  local f="$here/$1"
  if [ ! -f "$f" ]; then
    echo "missing: $1" >&2
    return 1
  fi
  printf '  %-24s %8s bytes\n' "$1" "$(wc -c < "$f")"
  psql "$DB" -v ON_ERROR_STOP=1 -q \
    -c 'set check_function_bodies = off' \
    -f "$f"
}

echo "Rebuilding from $here"
for f in 00_extensions.sql 05_types.sql 08_sequences.sql 10_tables.sql \
         20_keys.sql \
         40_functions_1.sql 40_functions_2.sql 40_functions_3.sql 40_functions_4.sql \
         21_checks.sql 22_foreign_keys.sql 30_indexes.sql \
         50_views.sql 60_triggers.sql 70_rls.sql 75_grants.sql 80_comments.sql; do
  run "$f"
done

# pg_cron is not present on a plain Postgres, and a baseline that refuses to
# load without it would be a baseline nobody could test against.
if psql "$DB" -tAc "select 1 from pg_extension where extname='pg_cron'" | grep -q 1; then
  run 90_cron.sql
else
  echo "  90_cron.sql              skipped, no pg_cron here"
fi

echo "Done."
