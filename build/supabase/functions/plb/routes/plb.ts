// =====================================================================
// Performance — the PLB scheme.
//
// PLB = Target × Payout Factor × Consistency Factor. The curve and the
// dial live in the database as plb_payout_factor and plb_consistency,
// written from the published breakpoints rather than a table of points,
// and proved against all five worked examples in the employee explainer.
// Nothing here recomputes them: a second opinion about somebody's pay is
// the one thing this service must never hold.
//
// Two views on the same data:
//
//   /mine      what the employee sees — every one of the twelve things
//              section 6.2 says they must always be able to see, plus the
//              arithmetic as a sentence
//   /quarter   what the manager sees — who has a sheet, who has not, what
//              is scored, what is certified
//
// Every write goes through a SECURITY DEFINER function that does its own
// permission check, so "nobody scores themselves" is enforced once, in
// the database, rather than restated here and left to drift.
// =====================================================================
import { Router, one, many } from "../shim.ts";
const r = Router();

// Running the scheme is HR's and Business Excellence's; being measured by
// it is everybody's. The screen is told which so it renders the difference
// rather than offering a button that will be refused.
const maySetUp = (req: any) =>
  req.person.app_role === "ADMIN" ||
  (req.person.department || "") === "Human Resources" ||
  (req.person.department || "") === "Business Excellence";

function out(res: any, o: any) {
  if (o?.error) {
    return res.status(
      o.error === "not_permitted" || o.error === "not_admin" ? 403 : 400,
    ).json(o);
  }
  return res.json(o);
}

// The quarter a date falls in, as its first day. Everything is keyed by it.
const quarterOf = (s?: string) => {
  const d = s ? new Date(s) : new Date();
  const m = d.getUTCMonth();
  return new Date(Date.UTC(d.getUTCFullYear(), m - (m % 3), 1))
    .toISOString().slice(0, 10);
};

// ------------------------------------------------------------------ read

// What the signed-in person is measured on, this quarter or any other.
r.get("/mine", async (req: any, res: any) => {
  const q = quarterOf(req.query.get("quarter") || undefined);
  const sheet = await one(
    `select id from plb_goal_sheet where person_id = $1 and quarter = $2`,
    [req.person.id, q],
  );
  if (!sheet) {
    // Not having a sheet is a fact about the scheme, not an error. The
    // backstop in the Constitution is the registry default at day 15, and
    // the screen should say which of those two situations this is.
    const chair = await one(
      `select ch.title, ch.code,
              (select count(*) from kpi_definition k
                where k.chair_id = ch.id and k.active and k.position < 100) as kpis
         from chair_holder h join chair ch on ch.id = h.chair_id
        where h.person_id = $1 and h.to_date is null
        order by h.is_primary desc nulls last limit 1`,
      [req.person.id],
    );
    return res.json({
      quarter: q,
      sheet: null,
      chair: chair?.title || null,
      inScheme: Number(chair?.kpis || 0) > 0,
      maySetUp: maySetUp(req),
    });
  }
  const full = await one(`select plb_sheet($1) as s`, [sheet.id]);
  return res.json({ quarter: q, sheet: full.s, maySetUp: maySetUp(req) });
});

// The whole quarter: sheets issued, and the people who should have one.
r.get("/quarter", async (req: any, res: any) => {
  const q = quarterOf(req.query.get("quarter") || undefined);
  const o = await one(`select plb_quarter($1) as q`, [q]);
  return res.json({ ...o.q, maySetUp: maySetUp(req), me: req.person.id });
});

// One sheet in full — the manager's view of somebody else's.
r.get("/sheet/:id", async (req: any, res: any) => {
  const o = await one(`select plb_sheet($1) as s`, [req.params.id]);
  if (!o?.s?.sheetId) return res.status(404).json({ error: "no_such_sheet" });
  const mine = o.s.personId === req.person.id;
  if (!mine && !maySetUp(req)) {
    return res.status(403).json({
      error: "not_permitted",
      reason: "A goal sheet is the employee's and their manager's.",
    });
  }
  return res.json({ sheet: o.s, mine, maySetUp: maySetUp(req) });
});

// The registry, so a manager can see what a chair is measured on before
// issuing anything — and so nobody has to take the weights on trust.
r.get("/registry", async (_req: any, res: any) => {
  const kpis = await many(
    `select ch.code, ch.title as chair,
            count(*) as kpis,
            round(100.0 / count(*), 2) as weight_each,
            jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'unit', k.unit)
                      order by k.position) as measures
       from kpi_definition k join chair ch on ch.id = k.chair_id
      where k.active and k.position < 100
      group by ch.code, ch.title order by ch.title`,
    [],
  );
  const attrs = await many(
    `select id, name, unit, mandatory from kpi_definition
      where chair_id is null and active order by position`,
    [],
  );
  return res.json({ chairs: kpis, attributes: attrs });
});

// ----------------------------------------------------------------- write

r.post("/issue", async (req: any, res: any) => {
  if (!maySetUp(req)) {
    return res.status(403).json({
      error: "not_permitted",
      reason: "Issuing a goal sheet is the reporting manager's, through HR.",
    });
  }
  const b = req.body || {};
  // $5::text, and JSON.stringify, on purpose. postgres.js decides how to
  // serialise by the JS type it is given: an object becomes JSON, but an
  // ARRAY becomes a Postgres array literal -- so [] would arrive as {}, and
  // jsonb_to_recordset would refuse it as a non-array. Pinning the parameter
  // to text and casting on the server takes the guess out of it.
  const o = await one(
    `select plb_sheet_issue($1,$2,$3,$4, coalesce($5::text,'[]')::jsonb, $6) as o`,
    [req.person.id, b.personId, quarterOf(b.quarter), b.targetPlb || 0,
     JSON.stringify(Array.isArray(b.targets) ? b.targets : []),
     b.isDefault === true],
  );
  return out(res, o.o);
});

r.post("/acknowledge", async (req: any, res: any) => {
  const o = await one(`select plb_acknowledge($1,$2) as o`,
    [req.person.id, (req.body || {}).sheetId]);
  return out(res, o.o);
});

r.post("/lock", async (req: any, res: any) => {
  if (!maySetUp(req)) return res.status(403).json({ error: "not_permitted" });
  const o = await one(`select plb_sheet_lock($1,$2) as o`,
    [req.person.id, (req.body || {}).sheetId]);
  return out(res, o.o);
});

r.post("/self", async (req: any, res: any) => {
  const b = req.body || {};
  const o = await one(`select plb_self_eval($1,$2,$3,$4,$5) as o`,
    [req.person.id, b.sheetId, b.month, b.kpi, b.attr]);
  return out(res, o.o);
});

r.post("/score", async (req: any, res: any) => {
  const b = req.body || {};
  const o = await one(`select plb_score_month($1,$2,$3,$4,$5,$6) as o`,
    [req.person.id, b.sheetId, b.month, b.kpi, b.attr, b.reason || null]);
  return out(res, o.o);
});

r.post("/score/lock", async (req: any, res: any) => {
  if (!maySetUp(req)) return res.status(403).json({ error: "not_permitted" });
  const b = req.body || {};
  const o = await one(`select plb_score_lock($1,$2,$3) as o`,
    [req.person.id, b.sheetId, b.month]);
  return out(res, o.o);
});

r.post("/actual", async (req: any, res: any) => {
  if (!maySetUp(req)) return res.status(403).json({ error: "not_permitted" });
  const b = req.body || {};
  const o = await one(`select plb_actual_set($1,$2,$3,$4) as o`,
    [req.person.id, b.sheetId, b.kpiId, b.actual]);
  return out(res, o.o);
});

r.post("/certify", async (req: any, res: any) => {
  if (!maySetUp(req)) return res.status(403).json({ error: "not_permitted" });
  const o = await one(`select plb_certify($1,$2) as o`,
    [req.person.id, (req.body || {}).sheetId]);
  return out(res, o.o);
});

r.post("/publish", async (req: any, res: any) => {
  if (!maySetUp(req)) return res.status(403).json({ error: "not_permitted" });
  const o = await one(`select plb_publish($1,$2) as o`,
    [req.person.id, (req.body || {}).sheetId]);
  return out(res, o.o);
});

export default r;
