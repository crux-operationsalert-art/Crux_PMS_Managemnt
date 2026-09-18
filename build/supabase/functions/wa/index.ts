// =====================================================================
// Crux - WhatsApp.
//
// Configuration, a test message, and the sender that drains wa_outbox.
// Built to the same rules as mail: the token goes in and never comes back
// out, only an administrator may change any of it, and nothing leaves the
// queue until a sender is actually configured - so an unconfigured tool
// holds its messages rather than losing them.
//
// Two transports, because these are the two a business in India is
// realistically on: Meta's WhatsApp Cloud API, and Twilio.
//
// JWT verification is off at the gateway because this function does its
// own: the browser holds no Supabase key.
// =====================================================================
import { createHash } from "node:crypto";
import { Buffer } from "node:buffer";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "content-type, x-crux-token, x-crux-cron, x-wa-bridge",
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

type Sent = { ok: true; id: string | null } | { ok: false; error: string; permanent: boolean };

// ------------------------------------------------------------- transports
// Meta's Cloud API. A template is required outside the 24-hour window that a
// customer's own message opens, so a queued row that names one is sent as a
// template and everything else as plain text.
async function sendMeta(cfg: Record<string, string>, m: any): Promise<Sent> {
  const to = String(m.recipient || "").replace(/^\+/, "");
  const body: Record<string, unknown> = { messaging_product: "whatsapp", to };

  if (m.template_name) {
    const vars: string[] = Array.isArray(m.template_vars) ? m.template_vars : [];
    body.type = "template";
    body.template = {
      name: m.template_name,
      language: { code: m.template_lang || "en" },
      components: vars.length
        ? [{ type: "body", parameters: vars.map((v) => ({ type: "text", text: String(v) })) }]
        : undefined,
    };
  } else {
    body.type = "text";
    body.text = { preview_url: false, body: String(m.body) };
  }

  const r = await fetch(
    "https://graph.facebook.com/v21.0/" + encodeURIComponent(cfg.from) + "/messages",
    {
      method: "POST",
      headers: {
        authorization: "Bearer " + cfg.token,
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    },
  );
  const t = await r.text();
  if (r.ok) {
    try {
      const j = JSON.parse(t);
      return { ok: true, id: j?.messages?.[0]?.id ?? null };
    } catch {
      return { ok: true, id: null };
    }
  }
  // 4xx is our fault and will not fix itself; 429 and 5xx are worth retrying
  const permanent = r.status >= 400 && r.status < 500 && r.status !== 429;
  return { ok: false, error: r.status + " " + t.slice(0, 400), permanent };
}

async function sendTwilio(cfg: Record<string, string>, m: any): Promise<Sent> {
  const from = cfg.from.startsWith("whatsapp:") ? cfg.from : "whatsapp:" + cfg.from;
  const form = new URLSearchParams({
    From: from,
    To: "whatsapp:" + String(m.recipient),
    Body: String(m.body),
  });
  const r = await fetch(
    "https://api.twilio.com/2010-04-01/Accounts/" +
      encodeURIComponent(cfg.account) + "/Messages.json",
    {
      method: "POST",
      headers: {
        authorization: "Basic " + Buffer.from(cfg.account + ":" + cfg.token).toString("base64"),
        "content-type": "application/x-www-form-urlencoded",
      },
      body: form,
    },
  );
  const t = await r.text();
  if (r.ok) {
    try {
      return { ok: true, id: JSON.parse(t)?.sid ?? null };
    } catch {
      return { ok: true, id: null };
    }
  }
  const permanent = r.status >= 400 && r.status < 500 && r.status !== 429;
  return { ok: false, error: r.status + " " + t.slice(0, 400), permanent };
}

async function drain(limit: number) {
  const settings = await rpc("wa_settings", {});
  const cfg = {
    provider: settings.whatsapp_provider || "",
    from: settings.whatsapp_from || "",
    account: settings.whatsapp_account || "",
    token: settings.whatsapp_token || "",
  };
  if (cfg.provider === "whatsapp_web") {
    // the linked device pulls its own work; pushing from here would race it
    return { drained: 0, sent: 0, failed: 0, reason: "sent_by_linked_device" };
  }
  if (!cfg.provider || !cfg.from || !cfg.token) {
    return { drained: 0, sent: 0, failed: 0, reason: "not_configured" };
  }
  if (cfg.provider === "twilio" && !cfg.account) {
    return { drained: 0, sent: 0, failed: 0, reason: "twilio_needs_account_sid" };
  }

  const rows = (await rpc("wa_claim", { p_limit: limit })) ?? [];
  let sent = 0, failed = 0;
  for (const m of rows) {
    let out: Sent;
    try {
      out = cfg.provider === "twilio" ? await sendTwilio(cfg, m) : await sendMeta(cfg, m);
    } catch (e) {
      out = { ok: false, error: String((e as Error).message), permanent: false };
    }
    if (out.ok) {
      await rpc("wa_sent", { p_id: m.id, p_provider_msg_id: out.id });
      sent++;
    } else {
      await rpc("wa_failed", { p_id: m.id, p_error: out.error, p_permanent: out.permanent });
      failed++;
    }
  }
  return { drained: rows.length, sent, failed };
}

// --------------------------------------------------------------- handler
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const url = new URL(req.url);
  const path = url.pathname.replace(/^.*?\/wa/, "") || "/";

  try {
    // ---------------------------------------------------- a linked device
    // It carries a bridge token, not a session. Everything it may do is
    // here, and it is only ever about its own queue: it can ask for work
    // and say what happened. It cannot read a person, a case or a setting.
    const bridge = req.headers.get("x-wa-bridge");
    if (bridge && path.startsWith("/bridge/")) {
      if (path === "/bridge/claim" && req.method === "POST") {
        return json(await rpc("wa_bridge_claim", { p_token: bridge }));
      }
      if (path === "/bridge/result" && req.method === "POST") {
        const b = await req.json();
        return json(await rpc("wa_bridge_result", {
          p_token: bridge, p_id: b.id, p_ok: !!b.ok,
          p_provider_msg_id: b.messageId ?? null,
          p_error: b.error ?? null, p_permanent: !!b.permanent,
        }));
      }
      if (path === "/bridge/heartbeat" && req.method === "POST") {
        const b = await req.json().catch(() => ({}));
        return json(await rpc("wa_bridge_heartbeat", {
          p_token: bridge, p_state: b.state ?? "READY",
          p_phone: b.phone ?? null, p_detail: b.detail ?? null,
        }));
      }
      if (path === "/bridge/qr" && req.method === "POST") {
        const b = await req.json();
        return json(await rpc("wa_bridge_qr", {
          p_token: bridge, p_qr: b.qr, p_qr_image: b.qrImage ?? null,
        }));
      }
      return json({ error: "no_route", path }, 404);
    }

    // The scheduler has no session, so it carries the same shared secret and
    // the same header name the mail drain uses. It may drain and nothing else.
    const cron = req.headers.get("x-crux-cron");
    if (cron) {
      const expected = await rpc("mail_cron_secret", {});
      if (expected && cron === expected) {
        return json(await drain(Number(url.searchParams.get("limit") || 25)));
      }
      return json({ error: "bad_cron_secret" }, 403);
    }

    const token = req.headers.get("x-crux-token");
    if (!token) return json({ error: "not_signed_in", reason: "Sign in first." }, 401);
    const person = await rpc("auth_whoami", { p_token_hash: sha(token) });
    if (!person) return json({ error: "not_signed_in", reason: "Sign in first." }, 401);

    // Everything here carries or reveals the key that speaks for the company.
    if (person.app_role !== "ADMIN") {
      return json({ error: "admin_only",
        reason: "WhatsApp settings are an administrator's to change." }, 403);
    }

    if (path === "/" || path === "") return json(await rpc("wa_status", {}));

    if (path === "/configure" && req.method === "POST") {
      const b = await req.json();
      const out = await rpc("wa_configure", {
        p_actor: person.id,
        p_provider: b.provider ?? null,
        p_from: b.from ?? null,
        p_account: b.account ?? null,
        p_token: b.token ?? null,
        p_cap: b.cap ?? null,
        p_country_code: b.countryCode ?? null,
        p_mirror: b.mirror ?? null,
      });
      if (out && out.error) return json(out, 403);
      return json(out);
    }

    if (path === "/test" && req.method === "POST") {
      const b = await req.json().catch(() => ({}));
      const out = await rpc("wa_test", { p_actor: person.id, p_to: b.to ?? null });
      if (out && out.error) return json(out, 400);
      // queue it and push it straight out, so the answer is the real answer
      return json({ ...out, drain: await drain(5) });
    }

    if (path === "/drain" && req.method === "POST") {
      return json(await drain(Number(url.searchParams.get("limit") || 25)));
    }

    if (path === "/forget" && req.method === "POST") {
      const out = await rpc("wa_forget_secrets", { p_actor: person.id });
      if (out && out.error) return json(out, 403);
      return json(out);
    }

    // ------------------------------------------------------ device admin
    if (path === "/device/new" && req.method === "POST") {
      const b = await req.json();
      const out = await rpc("wa_bridge_create", {
        p_actor: person.id, p_name: b.name ?? "", p_kind: b.kind ?? "laptop",
      });
      if (out && out.error) return json(out, 403);
      return json(out, 201);
    }

    if (path === "/device/qr") {
      const id = url.searchParams.get("id");
      if (!id) return json({ error: "missing_id" }, 400);
      return json(await rpc("wa_bridge_peek_qr", { p_actor: person.id, p_id: id }));
    }

    if (path === "/device/disable" && req.method === "POST") {
      const b = await req.json();
      const out = await rpc("wa_bridge_disable", { p_actor: person.id, p_id: b.id });
      if (out && out.error) return json(out, 403);
      return json(out);
    }

    if (path === "/alerts") return json(await rpc("ops_alert_open", { p_role: "ADMIN" }));

    if (path === "/alerts/ack" && req.method === "POST") {
      const b = await req.json();
      const out = await rpc("ops_alert_ack", { p_actor: person.id, p_id: b.id });
      if (out && out.error) return json(out, 403);
      return json(out);
    }

    return json({ error: "no_route", path }, 404);
  } catch (e) {
    console.error("[wa]", e);
    return json({ error: "server_error", reason: String((e as Error).message) }, 500);
  }
});
