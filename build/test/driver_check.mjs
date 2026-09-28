// What the SQL tests cannot reach: the boundary between Postgres and the
// service.
//
//   build/test/driver_check.mjs
//
// Everything in test_scope.sql is true of the database. None of it is true of
// ops until the values survive the trip through postgres.js, and two of the
// things migration 204 and the MIS scoping rely on are exactly the kind that
// arrive looking almost right:
//
//   access_screens() returns text[]. requireScreen() does
//   `(req.scope.screens || []).includes(screen)`. If the driver handed back
//   the Postgres literal "{today,ogl,...}" as a STRING, String.includes would
//   run happily and do substring matching -- and every non-admin's access
//   would be decided by whether one screen name happens to appear inside
//   another. If it handed back null, requireScreen would refuse everybody and
//   a hundred people would be locked out of a tool that tests green.
//
//   The MIS filter sends two JavaScript arrays as $1::uuid[] and $2::uuid[].
//   If the driver sent them as anything but a Postgres array, the predicate
//   would match nothing, and an empty MIS is a silent wrong answer rather than
//   a loud one.
//
// So both are run here against the same driver, at the same version, with the
// same options ops/shim.ts uses.
//
// Needs `postgres@3.4.5` reachable. run.sh skips this and says so when it is
// not, because a check nobody can run must not read as a check that passed.
import { createRequire } from "node:module";

// ESM resolution ignores NODE_PATH, and this file lives in the repository
// rather than beside a node_modules. So the package is required by path, from
// wherever PGJS says it is, and the ordinary resolution is tried first for
// anyone who has it installed next to the repository.
const require = createRequire(import.meta.url);
const PGJS = process.env.PGJS || "/tmp/claude-0/node_modules";
let postgres;
try {
  postgres = (await import("postgres")).default;
} catch {
  postgres = require(PGJS + "/postgres/cjs/src/index.js");
}

const HOST = process.env.CRUX_PG_HOST || "/home/crux/pg";
const PORT = Number(process.env.CRUX_PG_PORT || 55432);
const USER = process.env.CRUX_PG_USER || "crux";
const DB = process.env.CRUX_PG_DB || "crux";

// ops/shim.ts, verbatim in the part that matters
const sql = postgres({ host: HOST, port: PORT, user: USER, database: DB,
                       prepare: false, max: 2, idle_timeout: 20 });
const q = async (t, p = []) => ({ rows: await sql.unsafe(t, p) });
const one = async (t, p = []) => (await q(t, p)).rows[0] ?? null;
const many = async (t, p = []) => (await q(t, p)).rows;

let pass = 0, fail = 0;
const ok = (name, cond, saw) => {
  if (cond) { console.log("PASS  " + name); pass++; }
  else { console.log("FAIL  " + name + (saw === undefined ? "" : "  -- saw: " + saw)); fail++; }
};

// ------------------------------------------------- what requireScreen reads
// An id nobody holds falls through to 'exec', which is the case that decides
// whether somebody the tool cannot place sees less or sees nothing.
const NOBODY = "11111111-1111-1111-1111-111111111111";
const r = await one(`select access_level_of($1) as level, access_screens($1) as screens`,
                    [NOBODY]);

ok("an unplaced person is at exec level", r && r.level === "exec", r && r.level);
ok("screens arrives as a JavaScript array, not a string",
   Array.isArray(r.screens), Object.prototype.toString.call(r && r.screens));
ok("and it is not empty, which would refuse everybody",
   Array.isArray(r.screens) && r.screens.length > 0,
   r && r.screens && r.screens.length);
ok("includes() finds a screen the level carries",
   (r.screens || []).includes("perf"));
ok("and does not find one it does not",
   !(r.screens || []).includes("auto"));
// The substring trap: on a string, "rate" would be found inside "{...rates...}".
ok("no substring match: 'rate' is not 'rates'",
   !(r.screens || []).includes("rate"));

// --------------------------------------------- what the MIS filter sends
const A = "11111111-1111-1111-1111-111111111111";
const B = "22222222-2222-2222-2222-222222222222";
const Z1 = "33333333-3333-3333-3333-333333333333";
const Z2 = "44444444-4444-4444-4444-444444444444";
const IN_SCOPE = (a, b) =>
  `($${a}::uuid[] is null or exists (
      select 1 from unnest($${a}::uuid[], $${b}::uuid[]) as s(cid, gid)
       where s.cid = b.client_id and s.gid = b.geo_node_id))`;
const four = `(values ('${A}'::uuid,'${Z1}'::uuid),('${A}','${Z2}'),
                      ('${B}','${Z1}'),('${B}','${Z2}')) as b(client_id, geo_node_id)`;

const all = await many(`select count(*)::int as n from ${four} where ${IN_SCOPE(1, 2)}`,
                       [null, null]);
ok("an administrator passes nulls and sees all four", Number(all[0].n) === 4, all[0].n);

const diag = await many(`select b.client_id, b.geo_node_id from ${four} where ${IN_SCOPE(1, 2)}`,
                        [[A, B], [Z1, Z2]]);
ok("two JavaScript arrays arrive as a Postgres array of pairs",
   diag.length === 2, diag.length);
ok("and they are the diagonal, not the whole square",
   diag.length === 2 &&
   diag.some((x) => x.client_id === A && x.geo_node_id === Z1) &&
   diag.some((x) => x.client_id === B && x.geo_node_id === Z2),
   JSON.stringify(diag));

const nil = await many(`select count(*)::int as n from ${four} where ${IN_SCOPE(1, 2)}`,
                       [["00000000-0000-0000-0000-000000000000"],
                        ["00000000-0000-0000-0000-000000000000"]]);
ok("idList()'s nil uuid matches nothing, which is the right answer",
   Number(nil[0].n) === 0, nil[0].n);

await sql.end();
console.log(`\n-- driver: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
