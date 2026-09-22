// =====================================================================
// Crux - KPIs.
//
// Its own front door, small on purpose. Everything it does is one of three
// things: show a person their own KPIs and their team's, define or change
// one for somebody on a chair at or below their own, or retire one.
//
// It grants nothing itself. Every rule the owner settled - nobody sets
// their own, a manager acts only at or below their own chair, five is the
// shape, a KPI is retired and never deleted - lives in the database
// functions, so a second caller could not get round them by asking
// differently.
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
  const path = url.pathname.replace(/^.*?\/kpi/, "") || "/";

  try {
    const token = req.headers.get("x-crux-token");
    if (!token) return json({ error: "not_signed_in", reason: "Sign in first." }, 401);
    const person = await rpc("auth_whoami", { p_token_hash: sha(token) });
    if (!person) return json({ error: "not_signed_in", reason: "Sign in first." }, 401);

    if (path === "/" || path === "") {
      return json(await rpc("kpi_mine", { p_actor: person.id }));
    }

    if (path === "/save" && req.method === "POST") {
      const b = await req.json();
      const out = await rpc("kpi_save", {
        p_actor: person.id,
        p_person: b.person,
        p_name: b.name,
        p_id: b.id ?? null,
        p_unit: b.unit ?? null,
        p_cadence: b.cadence ?? "DAILY",
        p_accrual: b.accrual ?? "ADDS",
        p_mandatory: b.mandatory !== false,
        p_position: b.position ?? null,
        p_parent: b.parent ?? null,
      });
      if (out && out.error) {
        return json(out, out.error === "out_of_subtree" || out.error === "not_your_own" ? 403 : 400);
      }
      return json(out);
    }

    if (path === "/retire" && req.method === "POST") {
      const b = await req.json();
      const out = await rpc("kpi_retire", {
        p_actor: person.id, p_id: b.id, p_active: b.active === true,
      });
      if (out && out.error) {
        return json(out, out.error === "out_of_subtree" || out.error === "not_your_own" ? 403 : 400);
      }
      return json(out);
    }

    return json({ error: "no_route", path }, 404);
  } catch (e) {
    console.error("[kpi]", e);
    return json({ error: "server_error", reason: String((e as Error).message) }, 500);
  }
});
