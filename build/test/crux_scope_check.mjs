// Who may read an OGL assignment, asked at the front door.
//
// /api/ogl/points, /api/ogl/arbiter and /api/ogl/pause-preview call
// functions that take only the assignment id, not the caller. Until they
// were routed through ogl_detail first, anybody signed in who held an id
// could read another chair's case parties and their addresses. This runs
// the real handler (build/supabase/functions/crux/index.ts, transpiled
// here) with Deno.serve and the RPC layer stubbed, and checks that another
// chair's assignment is refused BEFORE the reading function is called.
//
//   TSLIB=/path/to/typescript /opt/node22/bin/node build/test/crux_scope_check.mjs

import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";

const here = dirname(fileURLToPath(import.meta.url));
const ts = createRequire(import.meta.url)(
  process.env.TSLIB || "/opt/node-tools/node_modules/typescript");
const src = readFileSync(join(here, "..", "supabase", "functions", "crux", "index.ts"), "utf8");
const out = join(mkdtempSync(join(tmpdir(), "crux-")), "crux.mjs");
writeFileSync(out, ts.transpileModule(src, { compilerOptions: { target: 99, module: 99 } }).outputText);

let handler; const calls = [];
globalThis.Deno = { env: { get: (k) => k === "SUPABASE_URL" ? "https://x.supabase.co" : "svc" },
                    serve: (h) => { handler = h; } };
const MINE = "a-mine", THEIRS = "a-theirs";
globalThis.fetch = async (u, o) => {
  const fn = String(u).split("/rpc/")[1]; const a = JSON.parse(o.body || "{}"); calls.push(fn);
  let out = null;
  if (fn === "auth_whoami") out = { id: "p1", app_role: "VIEWER" };
  else if (fn === "ogl_detail") out = a.p_assignment === MINE ? { assignment: {} }
                                   : { error: "not_yours", reason: "another chair" };
  else if (fn === "ogl_open_points") out = [{ party: "X", address: "Y" }];
  else if (fn === "ogl_arbiter") out = { name: "Boss", how: "manager" };
  else if (fn === "ogl_pause_preview") out = { ok: true };
  return new Response(JSON.stringify(out), { status: 200 });
};
await import(pathToFileURL(out).href);
const H = { "x-crux-token": "t" };
async function go(path, init = {}) {
  calls.length = 0;
  const r = await handler(new Request("https://x.supabase.co/functions/v1/crux" + path,
                                      { headers: H, ...init }));
  return { status: r.status, body: await r.json(), calls: calls.slice() };
}
let fails = 0; const ok = (n, c, s) => { console.log((c ? "PASS  " : "FAIL  ") + n + (c ? "" : "  -- " + JSON.stringify(s))); if (!c) fails++; };
for (const [name, path, init, fn] of [
  ["points", "/api/ogl/points?id=", {}, "ogl_open_points"],
  ["arbiter", "/api/ogl/arbiter?id=", {}, "ogl_arbiter"],
  ["pause-preview", "/api/ogl/pause-preview", "POST", "ogl_pause_preview"]]) {
  const mk = (id) => init === "POST"
    ? [path, { method: "POST", body: JSON.stringify({ id, reason: "r" }), headers: { ...H, "content-type": "application/json" } }]
    : [path + id, {}];
  let r = await go(...mk(THEIRS));
  ok(`${name}: another chair's assignment is refused 403`, r.status === 403 && r.body.error === "not_yours", r);
  ok(`${name}: and the reading function is never called`, !r.calls.includes(fn), r.calls);
  r = await go(...mk(MINE));
  ok(`${name}: their own is answered`, r.status === 200 && r.calls.includes(fn), r);
}
let r = await go("/api/ogl/detail?id=" + THEIRS);
ok("detail still refuses the same way it did", r.status === 403, r);
r = await handler(new Request("https://x.supabase.co/functions/v1/crux/api/ogl/points?id=" + MINE));
ok("no token is still 401", r.status === 401, r.status);
console.log(fails ? `-- crux: ${fails} failed` : "-- crux: all passed"); process.exit(fails ? 1 : 0);
