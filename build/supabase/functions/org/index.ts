// =====================================================================
// Crux - the operating structure, served live.
//
// A separate front door from `crux` on purpose: the org chart is read-only
// reference data, so it needs none of the upload, mail or reset surface,
// and keeping it apart means the chart can change without redeploying the
// function that holds the service key for everything else.
//
// JWT verification is off at the gateway because this function does its
// own: the browser holds no Supabase key.
// =====================================================================
import { createHash } from "node:crypto";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "content-type, x-crux-token",
  "access-control-allow-methods": "GET,POST,OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...CORS },
  });

async function rpc(fn: string, args: Record<string, unknown>) {
  const r = await fetch(SUPABASE_URL + "/rest/v1/rpc/" + fn, {
    method: "POST",
    headers: {
      apikey: SERVICE_KEY,
      authorization: "Bearer " + SERVICE_KEY,
      "content-type": "application/json",
    },
    body: JSON.stringify(args),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(fn + ": " + r.status + " " + text);
  return text ? JSON.parse(text) : null;
}

const sha = (s: string) => createHash("sha256").update(s).digest("hex");

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const url = new URL(req.url);
  const path = url.pathname.replace(/^.*?\/org/, "") || "/";

  try {
    // Signed in is enough. The structure is who the company is, not anyone's
    // caseload, so it is not gated on holding a chair - which is exactly why
    // it renders for an administrator who has not been seated yet.
    const token = req.headers.get("x-crux-token");
    if (!token) return json({ error: "not_signed_in", reason: "Sign in first." }, 401);
    const person = await rpc("auth_whoami", { p_token_hash: sha(token) });
    if (!person) return json({ error: "not_signed_in", reason: "Sign in first." }, 401);

    if (path === "/" || path === "") return json(await rpc("org_chart", {}));

    // Where a chair is held. Reading is for anyone signed in; changing it is
    // an administrator's, because it decides whose work a person sees.
    if (path === "/unplaced") return json(await rpc("org_unplaced", {}));

    if (path === "/place" && req.method === "POST") {
      if (person.app_role !== "ADMIN") {
        return json({ error: "admin_only",
          reason: "Recording where a chair is held is an administrator's to do." }, 403);
      }
      const b = await req.json();
      const out = await rpc("org_place_holder", {
        p_actor: person.id, p_holder: b.holder, p_seating: b.place ?? null,
      });
      if (out && out.error) return json(out, 400);
      return json(out);
    }

    if (path === "/place/auto" && req.method === "POST") {
      if (person.app_role !== "ADMIN") {
        return json({ error: "admin_only",
          reason: "Placing chair holders is an administrator's to do." }, 403);
      }
      const out = await rpc("chair_place_from_coverage", { p_actor: person.id });
      if (out && out.error) return json(out, 403);
      return json(out);
    }

    if (path === "/chair") {
      const code = url.searchParams.get("code");
      if (!code) return json({ error: "missing_code" }, 400);
      const out = await rpc("org_chair", { p_code: code });
      if (!out) return json({ error: "no_such_chair", code }, 404);
      return json(out);
    }

    return json({ error: "no_route", path }, 404);
  } catch (e) {
    console.error("[org]", e);
    return json({ error: "server_error", reason: String((e as Error).message) }, 500);
  }
});
