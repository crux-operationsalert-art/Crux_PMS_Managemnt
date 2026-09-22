// =====================================================================
// Crux - Configuration.
//
// Its own front door, for the same reason org and wa have theirs: this one
// reads and writes every number the tool runs on, so it should not share a
// deployment with the routes that serve day-to-day work. A change to a
// setting screen must never require redeploying the escalation engine.
//
// Everything here is one of three things and nothing else: read the
// configuration, change one setting, or start and stop a job. Penalty rules
// come through the same door because the same screen owns them, and because
// the people who may edit them are not only administrators.
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
  const path = url.pathname.replace(/^.*?\/cfg/, "") || "/";

  try {
    const token = req.headers.get("x-crux-token");
    if (!token) return json({ error: "not_signed_in", reason: "Sign in first." }, 401);
    const person = await rpc("auth_whoami", { p_token_hash: sha(token) });
    if (!person) return json({ error: "not_signed_in", reason: "Sign in first." }, 401);

    // Who may do what is decided in the database, not here: config_read
    // returns the two permissions with the data, and every write re-checks
    // for itself. This function never grants anything on its own.
    if (path === "/" || path === "") {
      const out = await rpc("config_read", { p_actor: person.id });
      if (out && out.error) return json(out, 403);
      return json(out);
    }

    if (path === "/setting" && req.method === "POST") {
      const b = await req.json();
      const out = await rpc("config_set", {
        p_actor: person.id, p_key: b.key, p_value: b.value ?? "",
      });
      if (out && out.error) return json(out, out.error === "not_admin" ? 403 : 400);
      return json(out);
    }

    if (path === "/job" && req.method === "POST") {
      const b = await req.json();
      const out = await rpc("config_job_set", {
        p_actor: person.id, p_key: b.key,
        p_enabled: !!b.enabled, p_reason: b.reason ?? null,
      });
      if (out && out.error) return json(out, out.error === "not_admin" ? 403 : 400);
      return json(out);
    }

    if (path === "/penalty" && req.method === "POST") {
      const b = await req.json();
      const out = await rpc("config_penalty_save", {
        p_actor: person.id, p_id: b.id,
        p_amount: b.amount ?? null,
        p_active: typeof b.active === "boolean" ? b.active : null,
        p_recovered_by: b.recoveredBy ?? null,
        p_applies_to: b.appliesTo ?? null,
        p_plain_language: b.says ?? null,
      });
      if (out && out.error) return json(out, out.error === "not_allowed" ? 403 : 400);
      return json(out);
    }

    return json({ error: "no_route", path }, 404);
  } catch (e) {
    console.error("[cfg]", e);
    return json({ error: "server_error", reason: String((e as Error).message) }, 500);
  }
});
