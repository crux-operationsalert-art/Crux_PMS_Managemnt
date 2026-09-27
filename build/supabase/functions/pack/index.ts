// =====================================================================
// Crux pack -- the monthly escalation matrix despatch.
//
// A fifth front door, for one route file, and the reason is worth writing
// down: `api` is at the size an Edge Function deploy will carry, and `ops`
// serves six screens that work. Adding a route to `ops` means re-uploading
// all of it, and a slip anywhere in that upload takes Places, Reports, MIS,
// the rate master, report access and automations down with it. A new door
// costs one more URL and risks nothing that is already running.
//
// Same session token, same shim, same scope rules -- shim.ts and scope.ts
// here are copies of api's, never a second opinion. See ops/README.md.
// =====================================================================
import { CORS, Req, Res, one } from "./shim.ts";
import { buildScope } from "./scope.ts";

import pack from "./routes/pack.ts";

const MOUNTS: [string, any][] = [
  ["/api/pack", pack],
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
  // The function is served at /functions/v1/pack, so the mount prefix has to
  // be rebuilt: strip everything up to and including /pack and put /api back
  // on. The route file expects to be mounted under /api, as api's are.
  const path = "/api" + (url.pathname.replace(/^.*?\/pack(?=\/|$)/, "") || "");

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
    if (status >= 500) console.error("[pack]", e);
    // A bare SQLSTATE tells the reader nothing and sends them hunting through
    // logs. The message goes with it.
    return json({
      error: err.code || err.message || "server_error",
      reason: err.reason ?? (err.code && err.message ? err.message : undefined),
    }, status);
  }
});
