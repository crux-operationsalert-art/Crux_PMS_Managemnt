// =====================================================================
// Crux ops -- the screens added after the cut-over.
//
// One Edge Function deploys in one call, and `api` outgrew what that call
// carries. This is the same front door serving the rest: the same session
// token, the same scope rules, the same shim. See README.md -- shim.ts and
// scope.ts here are copies of api's, never a second opinion.
// =====================================================================
import { CORS, Req, Res, one } from "./shim.ts";
import { buildScope } from "./scope.ts";

import field from "./routes/field.ts";
import rates from "./routes/rates.ts";
import mis from "./routes/mis.ts";
import access from "./routes/access.ts";
import auto from "./routes/auto.ts";

const MOUNTS: [string, any][] = [
  ["/api/field", field],
  ["/api/rates", rates],
  ["/api/mis", mis],
  ["/api/access", access],
  ["/api/auto", auto],
];

const sha = async (s: string) => {
  const b = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(b)).map((x) => x.toString(16).padStart(2, "0")).join("");
};

// The same session rows the upload service issues. A token minted there works
// here; revoking it there revokes it here.
async function personFor(req: Request) {
  const token = req.headers.get("x-crux-token");
  if (!token) return null;
  const r = await one(
    `update auth_session s set last_seen_at = now()
      where s.token_hash = $1 and s.revoked_at is null and s.expires_at > now()
      returning s.person_id`,
    [await sha(token)],
  );
  if (!r) return null;
  return await one(
    `select p.id, p.full_name, p.work_email, p.department, p.app_role, d.title as designation
       from person p left join designation d on d.id = p.designation_id
      where p.id = $1 and p.employment_status = 'ACTIVE' and p.superseded_by is null`,
    [r.person_id],
  );
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status, headers: { "content-type": "application/json", ...CORS },
  });

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const url = new URL(request.url);
  // The function is served at /functions/v1/ops, so the mount prefix has to be
  // rebuilt: strip everything up to and including /ops and put /api back on.
  // The route files are shared with `api` and expect to be mounted under it.
  const path = "/api" + (url.pathname.replace(/^.*?\/ops(?=\/|$)/, "") || "");

  try {
    if (path === "/" || path === "/api" || path === "/api/health") {
      const db = await one(`select now() as at`).catch(() => null);
      return json({
        ok: !!db, at: db?.at ?? null,
        routes: MOUNTS.map(([m]) => m),
        note: "Send the session token from the upload service as x-crux-token.",
      }, db ? 200 : 503);
    }

    const person = await personFor(request);
    if (!person) {
      return json({ error: "sign_in_required",
        reason: "Sign in at the upload service and send its token as x-crux-token." }, 401);
    }

    let body: Record<string, unknown> = {};
    if (request.method !== "GET" && request.method !== "HEAD") {
      body = await request.json().catch(() => ({}));
    }

    const scope = await buildScope(person.id as string, person.app_role as string);

    for (const [mount, router] of MOUNTS) {
      if (path !== mount && !path.startsWith(mount + "/")) continue;
      const rest = path.slice(mount.length) || "/";
      const req: Req = {
        method: request.method, path: rest, params: {},
        query: url.searchParams, body,
        person, scope,
        get: (h: string) => request.headers.get(h),
      };
      const res = new Res();
      const matched = await router.handle(req, res);
      if (matched && res._done) return res._done;
      if (matched) return json({ error: "no_response", path }, 500);
    }

    return json({ error: "no_route", path, routes: MOUNTS.map(([m]) => m) }, 404);
  } catch (e) {
    const err = e as { status?: number; code?: string; message?: string; reason?: string };
    const status = err.status ?? 500;
    if (status >= 500) console.error("[api]", e);
    // A bare SQLSTATE tells the reader nothing and sends them hunting through
    // logs. The message goes with it.
    return json({
      error: err.code || err.message || "server_error",
      reason: err.reason ?? (err.code && err.message ? err.message : undefined),
    }, status);
  }
});
