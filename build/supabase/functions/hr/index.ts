// =====================================================================
// Crux hr -- adding a person.
//
// A fourth front door, for the reason the second and third exist: one Edge
// Function deploys in one call, and `api` -- which owns the older person
// request flow -- is at that limit and cannot be redeployed. So the new
// path lives here rather than being squeezed in beside something that
// would then refuse to ship.
//
// It does not replace the request flow in api/routes/people.ts. That one
// is a queue: somebody asks, HR approves, an administrator seats. This one
// is the direct path for when the person asking IS HR, and it carries the
// six fields that flow never had -- employee number first among them,
// because the performance upload joins people by it and a person without
// one has their rows dropped in silence.
//
// Same session token, same shim -- shim.ts here is a copy of api's, never a
// second opinion; see ops/README.md. scope.ts is deliberately absent:
// "HR, or an administrator" is not a coverage question, and carrying a
// scope nothing reads would only invite somebody to start reading it.
// =====================================================================
import { CORS, Req, Res, one } from "./shim.ts";

import hr from "./routes/hr.ts";

const MOUNTS: [string, any][] = [
  ["/api/hr", hr],
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
  // The function is served at /functions/v1/hr, so the mount prefix has to be
  // rebuilt: strip everything up to and including /hr and put /api back on.
  // The route files are shared with `api` and expect to be mounted under it.
  const path = "/api" + (url.pathname.replace(/^.*?\/hr(?=\/|$)/, "") || "");

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

    for (const [mount, router] of MOUNTS) {
      if (path !== mount && !path.startsWith(mount + "/")) continue;
      const rest = path.slice(mount.length) || "/";
      const req: Req = {
        method: request.method, path: rest, params: {},
        query: url.searchParams, body,
        person, scope: null,
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
    if (status >= 500) console.error("[hr]", e);
    // A bare SQLSTATE tells the reader nothing and sends them hunting through
    // logs. The message goes with it.
    return json({
      error: err.code || err.message || "server_error",
      reason: err.reason ?? (err.code && err.message ? err.message : undefined),
    }, status);
  }
});
