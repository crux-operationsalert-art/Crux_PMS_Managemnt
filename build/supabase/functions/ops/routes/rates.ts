// Rate master. The design is firm about the one thing that matters here:
//
//   "A report for a past month uses the rate valid during that month, not the
//    one showing at the top of this list. Changing a rate adds a version; it
//    never rewrites a closed month."
//
// So a change never updates a row. It end-dates the version in force and
// inserts the next one, and every version stays readable. rate.code is unique,
// so a version carries its own code derived from the family.

import { Router, many, one, tx } from "../shim.ts";
import { requireChair } from "../scope.ts";
const r = Router();

function mayEdit(req: any) {
  return req.person.app_role === "ADMIN" ||
         (req.person.department || "") === "Finance & Accounts";
}

// The family a version belongs to: RATE-00007#3 belongs to RATE-00007.

r.get("/", requireChair, async (req: any, res: any) => {
  const [rows, clients] = await Promise.all([
    many(
      `with v as (
         select r.*, split_part(r.code, '#', 1) as family from rate r
       ), latest as (
         select distinct on (family) * from v order by family, effective_from desc
       )
       select l.family, l.id, l.code, l.value, l.currency,
              l.scope::text as scope, l.status, l.effective_from, l.effective_to,
              l.reason, c.name as client, c.code as client_code,
              (select count(*)::int from v where v.family = l.family) as versions,
              (l.effective_from > current_date) as future
         from latest l
         left join client c on c.id = l.client_id
        order by l.family`),
    many(`select id, code, name from client where status = 'ACTIVE' order by name`),
  ]);
  res.json({
    rates: rows, clients, mayEdit: mayEdit(req),
    scopes: [
      { key: "client", label: "Every branch of one client" },
      { key: "group",  label: "A group of branches" },
      { key: "exact",  label: "One named branch" },
    ],
    emptyWhy: "No rate is configured, so nothing can be priced yet. The MIS, the " +
      "10-day view and every revenue figure read the rate that was valid in the " +
      "month being reported, and with none set they have nothing to read.",
  });
});

r.get("/:family/history", requireChair, async (req: any, res: any) => {
  const rows = await many(
    `select r.code, r.value, r.currency, r.scope::text as scope, r.status,
            r.effective_from, r.effective_to, r.reason,
            c.name as client, p.full_name as by
       from rate r
       left join client c on c.id = r.client_id
       left join person p on p.id = r.created_by
      where split_part(r.code, '#', 1) = $1
      order by r.effective_from`,
    [req.params.family]);
  res.json({ family: req.params.family, versions: rows });
});

// Adding a rate, or a new version of one. Never an update: the version in
// force is end-dated the day before the new one starts, and both stay.
r.post("/", requireChair, async (req: any, res: any, next: any) => {
  const { family, clientId, scope, value, effectiveFrom, reason } = req.body || {};
  try {
    if (!mayEdit(req)) {
      return res.status(403).json({ error: "not_permitted",
        reason: "Finance and the administrator own the rate master." });
    }
    if (value === undefined || value === null || Number(value) < 0 || !scope || !effectiveFrom) {
      return res.status(400).json({ error: "incomplete",
        reason: "A rate needs an amount that is not negative, what it applies to, and the date it takes effect." });
    }
    const out = await tx(req.person.id, async (t: any) => {
      const fam = family && String(family).trim()
        ? String(family).trim()
        : (await t.q(`select next_ref('RATE') as ref`)).rows[0].ref;

      // end-date whatever is in force the day before this one starts
      const prev = (await t.q(
        `select id, code, value from rate
          where split_part(code, '#', 1) = $1 and effective_to is null
          order by effective_from desc limit 1`, [fam])).rows[0];
      if (prev) {
        await t.q(
          `update rate set effective_to = $2::date - 1, updated_by = $3, updated_at = now()
            where id = $1`, [prev.id, effectiveFrom, req.person.id]);
      }

      const n = (await t.q(
        `select count(*)::int as n from rate where split_part(code, '#', 1) = $1`,
        [fam])).rows[0].n;

      const nr = (await t.q(
        `insert into rate (code, client_id, scope, value, currency, effective_from,
                           status, reason, created_by, created_at)
         values ($1, $2, $3::rate_scope, $4, 'INR', $5::date, 'active', $6, $7, now())
         returning id, code, value, effective_from`,
        [fam + "#" + (n + 1), clientId || null, scope, value, effectiveFrom,
         reason || null, req.person.id])).rows[0];

      await t.audit("RATE_SET", "rate", nr.code,
        prev ? { value: prev.value, code: prev.code } : null,
        { value: nr.value, from: nr.effective_from, reason: reason || null });
      return { ...nr, family: fam, superseded: prev ? prev.code : null };
    });
    res.status(201).json(out);
  } catch (e) { next(e); }
});

export default r;
