// =====================================================================
// The escalation matrix as a monthly despatch.
//
// The matrix itself is edited elsewhere -- api/routes/matrix.ts owns the
// five levels a branch. This is the other half, which the tool never had:
// the pack that goes to the client every month, who it went to, when, and
// what it said at the moment it left.
//
// Not one decision is taken here. matrix_month() says what a person may
// see, matrix_pack() says what would go and what is held back, and
// matrix_send() says whether they may send it and freezes the snapshot.
// All three are SECURITY DEFINER, so a caller that skips this service is
// refused in exactly the same words. What is left for this file is the
// post: turning the letter the database wrote into rows in the outbox,
// one per recipient, through the same idempotent queue as everything else.
//
// It lives on `ops` rather than beside the rest of the matrix because
// `api` is at the size an Edge Function deploy will carry and cannot take
// another route. See ops/README.md.
// =====================================================================
import { Router, one, enqueue } from "../shim.ts";
import { requireChair } from "../scope.ts";
const r = Router();

function out(res: any, o: any) {
  if (o?.error) {
    const forbidden = o.error === "read_only" || o.error === "no_client_view";
    return res.status(forbidden ? 403 : 400).json(o);
  }
  return res.json(o);
}

const monthOf = (s?: string | null) => {
  const d = s ? new Date(s) : new Date();
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1))
    .toISOString().slice(0, 10);
};

// Every client this person covers, and whether this month's matrix has
// gone out. This is what the Branch Manager's page opens on.
r.get("/month", requireChair, async (req: any, res: any) => {
  const d = await one(`select matrix_month($1,$2::date) as d`,
    [req.person.id, monthOf(req.query.get("period"))]);
  return res.json(d?.d ?? {});
});

// One client's pack, before it is sent. Looking is not sending.
r.get("/client/:clientId", requireChair, async (req: any, res: any) => {
  const d = await one(`select matrix_pack($1,$2,$3::date) as d`,
    [req.person.id, req.params.clientId, monthOf(req.query.get("period"))]);
  return out(res, d?.d ?? {});
});

// What went out before, for this client. A dispatch is a record, so it
// should be readable after the month it belongs to.
r.get("/history/:clientId", requireChair, async (req: any, res: any) => {
  const d = await one(
    `select coalesce(jsonb_agg(jsonb_build_object(
              'dispatchId', d.id, 'period', d.period, 'sentAt', d.sent_at,
              'branches', d.branch_count, 'heldBack', d.held_back,
              'recipients', to_jsonb(d.recipients),
              'by', p.full_name) order by d.period desc), '[]'::jsonb) as d
       from matrix_dispatch d
       join person p on p.id = d.prepared_by
      where d.client_id = $1
        and exists (select 1 from branch b
                     join matrix_scope_branches($2) s on s.branch_id = b.id
                    where b.client_id = $1)`,
    [req.params.clientId, req.person.id],
  );
  return res.json({ dispatches: d?.d ?? [] });
});

// Send it. The database freezes the snapshot and writes the letter; this
// puts it in the post.
//
// One outbox row per recipient rather than one row with several addresses,
// because a bounce should name the address that bounced and a re-send
// should not re-send to everybody.
r.post("/send", requireChair, async (req: any, res: any) => {
  const b = req.body || {};
  const to: string[] = Array.isArray(b.to)
    ? b.to.map((x: any) => String(x).trim().toLowerCase()).filter(Boolean)
    : [];
  const period = monthOf(b.period);

  const d = await one(`select matrix_send($1,$2,$3::date,$4::text[],$5) as d`,
    [req.person.id, b.clientId, period, to, b.note || null]);
  const o = d?.d ?? {};
  if (o.error) return out(res, o);

  const queued: any[] = [];
  for (const addr of to) {
    queued.push({
      to: addr,
      ...(await enqueue(req.person.id, {
        templateKey: "MATRIX_MONTHLY",
        recipient: addr,
        subject: o.subject,
        body: o.body,
        entityType: "client",
        entityId: b.clientId,
        period,
      })),
    });
  }

  // A dispatch that reached nobody is not a dispatch, and the screen has to
  // be able to say so rather than showing a tick.
  const sent = queued.filter((q) => q.queued).length;
  const already = queued.filter((q) => q.reason === "duplicate").length;
  return res.json({
    ...o, queued,
    note: o.note + " " +
      (sent
        ? sent + " message(s) queued."
        : already
        ? "Nothing new was queued: the same letter has already gone to " +
          "these addresses for this month. The record is updated; the post is not sent twice."
        : "Nothing could be queued, so nobody has been written to yet."),
  });
});

export default r;
