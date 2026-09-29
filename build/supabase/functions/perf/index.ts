// =====================================================================
// Crux perf -- the parts of the Performance screen that arrived after plb
// was already deployed.
//
// A sixth front door, for the reason the fifth one exists and the comment
// in build-tool.py gives: one Edge Function deploys in one call, and
// re-uploading a large working function to add three routes risks the
// large working function. `plb` serves the scheme and is correct; these
// are the screen's newer sections -- the tasks somebody was asked to do,
// the split between KPIs and Attributes, and the fortnight strip.
//
// shim.ts here is a byte copy of plb's, never a second opinion.
// =====================================================================
import { CORS, Req, Res, one } from "./shim.ts";

import perf from "./routes/perf.ts";

const MOUNTS: [string, any][] = [
  ["/api/perf", perf],
];

const sha = async (s: string) => {
  const b = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(b)).map((x) => x.toString(16).padStart(2, "0")).join("");
};

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
  const path = "/api" + (url.pathname.replace(/^.*?\/perf(?=\/|$)/, "") || "");

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
    if (status >= 500) console.error("[perf]", e);
    return json({
      error: err.code || err.message || "server_error",
      reason: err.reason ?? (err.code && err.message ? err.message : undefined),
    }, status);
  }
});
