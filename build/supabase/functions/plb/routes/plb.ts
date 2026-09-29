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
//
// This says who may RUN the scheme -- issue, lock, certify, publish, decide
// a dispute. Migration 218 stopped it also meaning "may read and set any
// one person's numbers": that is perf_rel, asked of the database, and the
// answer is the reporting line and nothing else.
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
  // Ask first, read second. Until migration 218 this read the sheet and
  // then let through the employee themselves or anyone at all in HR,
  // Business Excellence or administration -- so a manager could not open
  // their own report's sheet and an HR executive could open the chief
  // executive's. The relationship is the database's to state.
  const rel = await one(`select plb_sheet_rel($1,$2) as rel`,
    [req.person.id, req.params.id]);
  if (rel?.rel == null) {
    const exists = await one(`select 1 as yes from plb_goal_sheet where id = $1`,
      [req.params.id]);
    if (!exists) return res.status(404).json({ error: "no_such_sheet" });
    return res.status(403).json({
      error: "not_permitted",
      reason: "A goal sheet is the employee's and the line above them.",
    });
  }
  const o = await one(`select plb_sheet($1) as s`, [req.params.id]);
  if (!o?.s?.sheetId) return res.status(404).json({ error: "no_such_sheet" });
  return res.json({
    sheet: o.s,
    mine: rel.rel === "self",
    rel: rel.rel,
    maySet: rel.rel === "manage" || rel.rel === "admin",
    maySetUp: maySetUp(req),
  });
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

// ------------------------------------------------- attributes A-4, A-5

// The employee proposes. The three admissibility questions are asked in the
// database, not here, so an upload or a script gets the same answers.
r.post("/attr/propose", async (req: any, res: any) => {
  const b = req.body || {};
  const o = await one(`select plb_attr_propose($1,$2,$3,$4,$5,$6,$7,$8) as o`,
    [req.person.id, b.sheetId, b.kpiId, b.proposal, b.evidence, b.m1, b.m2, b.m3]);
  return out(res, o.o);
});

// The manager approves or returns it. "Nobody approves their own" is checked
// in the function, so an ADMIN reviewing their own sheet is refused too.
r.post("/attr/decide", async (req: any, res: any) => {
  if (!maySetUp(req)) return res.status(403).json({ error: "not_permitted" });
  const b = req.body || {};
  const o = await one(`select plb_attr_decide($1,$2,$3,$4,$5) as o`,
    [req.person.id, b.sheetId, b.kpiId, b.approve === true, b.note || null]);
  return out(res, o.o);
});

// 4.5: an attribute score above 7.5 out of 10 is checked, not waved through.
r.post("/countersign", async (req: any, res: any) => {
  if (!maySetUp(req)) return res.status(403).json({ error: "not_permitted" });
  const b = req.body || {};
  const o = await one(`select plb_countersign($1,$2,$3) as o`,
    [req.person.id, b.sheetId, b.month]);
  return out(res, o.o);
});

// ---------------------------------------------------------- the dispute

// Raising is the employee's, and only theirs. No guard here beyond the one in
// the function, which also holds the window open or shut.
r.post("/dispute", async (req: any, res: any) => {
  const b = req.body || {};
  const o = await one(`select plb_dispute_raise($1,$2,$3,$4,$5,$6,$7,$8) as o`,
    [req.person.id, b.sheetId, b.element, b.kpiId || null, b.month || null,
     b.claimed, b.claimedValue ?? null, b.evidence]);
  return out(res, o.o);
});

r.post("/dispute/respond", async (req: any, res: any) => {
  if (!maySetUp(req)) return res.status(403).json({ error: "not_permitted" });
  const b = req.body || {};
  const o = await one(`select plb_dispute_respond($1,$2,$3) as o`,
    [req.person.id, b.disputeId, b.response]);
  return out(res, o.o);
});

r.post("/dispute/escalate", async (req: any, res: any) => {
  const b = req.body || {};
  const o = await one(`select plb_dispute_escalate($1,$2,$3) as o`,
    [req.person.id, b.disputeId, b.why]);
  return out(res, o.o);
});

r.post("/dispute/decide", async (req: any, res: any) => {
  if (!maySetUp(req)) return res.status(403).json({ error: "not_permitted" });
  const b = req.body || {};
  const o = await one(`select plb_dispute_decide($1,$2,$3,$4) as o`,
    [req.person.id, b.disputeId, b.outcome, b.decision]);
  return out(res, o.o);
});

r.post("/dispute/withdraw", async (req: any, res: any) => {
  const o = await one(`select plb_dispute_withdraw($1,$2) as o`,
    [req.person.id, (req.body || {}).disputeId]);
  return out(res, o.o);
});

// =====================================================================
// The monthly cycle: a manager sets KPIs and targets, people file numbers
// on the cadence they were given, and the numbers climb.
//
// Not one guard in here decides anything. perf_may_set() decides who may
// set a KPI -- the reporting manager, HR, Business Excellence or an
// administrator, and never the person themselves -- and perf_file()
// decides who may file. Both are SECURITY DEFINER, so a caller who skips
// this service is refused in exactly the same words.
// =====================================================================

const monthOf = (s?: string) => {
  const d = s ? new Date(s) : new Date();
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1))
    .toISOString().slice(0, 10);
};

// The cycle for a period, and whether its two windows are open. A period
// with no cycle is not an error: it is a month nobody has opened yet, and
// the screen should say so rather than show an empty grid.
r.get("/perf/cycle", async (req: any, res: any) => {
  const period = monthOf(req.query.get("period") || undefined);
  const kind = req.query.get("kind") === "QUARTER" ? "QUARTER" : "MONTH";
  const c = await one(
    `select id, period_start, period_kind, assign_opens, assign_closes,
            entry_closes, state,
            current_date <= assign_closes as assign_open,
            current_date <= entry_closes  as entry_open
       from perf_cycle where period_start = $1 and period_kind = $2`,
    [period, kind],
  );
  return res.json({
    period, kind, cycle: c,
    mayOpen: req.person.app_role === "ADMIN" ||
             ["Human Resources", "Business Excellence"].includes(req.person.department || ""),
    note: c ? null : "No cycle has been opened for " + period + " yet.",
  });
});

r.post("/perf/cycle/open", async (req: any, res: any) => {
  const b = req.body || {};
  const o = await one(`select perf_cycle_open($1,$2,$3) as o`,
    [req.person.id, monthOf(b.period), b.kind === "QUARTER" ? "QUARTER" : "MONTH"]);
  return out(res, o.o);
});

// The whole tree for one person: their measures, their own splits under
// each, and the people who roll into it under that. Defaults to the caller,
// so "my performance" needs no argument.
r.get("/perf/tree", async (req: any, res: any) => {
  const who = req.query.get("person") || req.person.id;
  const cycle = req.query.get("cycle");
  if (!cycle) return res.status(400).json({ error: "missing_cycle" });
  // perf_tree_for, not perf_tree. This route took ?person= off the query
  // string and passed it straight through, so anyone who could sign in
  // could read anyone's performance by knowing their id. The wrapper
  // refuses a person outside the caller's line and says which relationship
  // it is, so the screen knows whether to draw an input or a number.
  const o = await one(`select perf_tree_for($1,$2,$3) as o`,
    [req.person.id, who, cycle]);
  return out(res, o.o);
});

// What is due from me today. The cadence decides, and the working-day
// calendar behind it is the same one the dispute window runs on.
r.get("/perf/due", async (req: any, res: any) => {
  const on = req.query.get("on") || null;
  const o = await one(`select perf_due($1, coalesce($2::date, current_date)) as o`,
    [req.person.id, on]);
  return res.json({ due: o.o, on: on });
});

r.post("/perf/file", async (req: any, res: any) => {
  const b = req.body || {};
  const o = await one(`select perf_file($1,$2,$3::date,$4::numeric,$5) as o`,
    [req.person.id, b.assignmentId, b.asOf, b.value, b.note || null]);
  return out(res, o.o);
});

// ------------------------------------------------------------ setting

// My team, and the line below it. Depth 1 is mine to set; deeper is mine
// to watch and nothing more. Both come back in one list with the depth on
// each row, because the screen has to draw the difference and asking twice
// is how the list and the gate start disagreeing.
r.get("/perf/team", async (req: any, res: any) => {
  const people = await many(
    `select p.id as "personId", p.full_name as name, p.employee_no as "employeeNo",
            p.department, l.depth,
            l.depth = 1 as "maySet",
            (select ch.title from chair_holder h join chair ch on ch.id = h.chair_id
              where h.person_id = p.id and h.to_date is null
              order by h.is_primary desc, ch.title limit 1) as chair
       from perf_line($1) l
       join person p on p.id = l.person_id
      where p.superseded_by is null and p.employment_status = 'ACTIVE'
        and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
      order by l.depth, p.full_name`,
    [req.person.id],
  );
  // An administrator is not in anybody's reporting line and still has to be
  // able to work. Named here rather than folded into perf_line, so the line
  // stays a statement about the organisation and not about the tool.
  if (people.length === 0 && req.person.app_role === "ADMIN") {
    const all = await many(
      `select p.id as "personId", p.full_name as name, p.employee_no as "employeeNo",
              p.department, 1 as depth, true as "maySet",
              (select ch.title from chair_holder h join chair ch on ch.id = h.chair_id
                where h.person_id = p.id and h.to_date is null
                order by h.is_primary desc, ch.title limit 1) as chair
         from person p
        where p.superseded_by is null and p.employment_status = 'ACTIVE'
          and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
          and p.id <> $1
        order by p.full_name`,
      [req.person.id],
    );
    return res.json({ people: all, asAdministrator: true });
  }
  return res.json({ people });
});

// What a chair is measured on, so a manager starts from the registry
// rather than from a blank box. My own measures come back too, because a
// KPI given to somebody has to climb into one of mine.
r.get("/perf/measures", async (req: any, res: any) => {
  const cycle = req.query.get("cycle");
  const person = req.query.get("person");
  // Asked about a person rather than a chair, resolve their chair here.
  // The screen knows who it is setting a KPI for; it has no business
  // knowing chair ids, and a manager choosing from every measure in the
  // company is searching rather than choosing.
  let chair = req.query.get("chair");
  if (!chair && person) {
    const seat = await one(
      `select h.chair_id from chair_holder h
        where h.person_id = $1 and h.to_date is null
        order by h.is_primary desc limit 1`,
      [person],
    );
    chair = seat?.chair_id ?? null;
  }
  const measuresOf = (c: string | null) =>
    many(
      `select k.id, k.name, k.unit, k.cadence::text as cadence,
              k.accrual::text as accrual, k.mandatory,
              perf_accrual_kind(k.id, k.unit) as kind
         from kpi_definition k
        where k.active and k.position < 100
          and ($1::uuid is null or k.chair_id = $1::uuid)
        order by k.position, k.name`,
      [c],
    );

  let catalogue = await measuresOf(chair);
  let note: string | null = null;
  // A chair nobody has given a measure set yet must not leave the manager
  // with an empty dropdown and no way forward. Fall back to the whole
  // catalogue and say why, rather than presenting nothing as an answer.
  if (chair && catalogue.length === 0) {
    catalogue = await measuresOf(null);
    note = "That chair has no measure set of its own yet, so every measure " +
           "is offered. Setting one here does not add it to the chair.";
  }

  const mine = cycle
    ? await many(
      `select a.id as "assignmentId", a.name, a.unit, a.split_label as split
         from perf_assignment a
        where a.person_id = $1 and a.cycle_id = $2::uuid
        order by a.name, a.split_label`,
      [req.person.id, cycle],
    )
    : [];
  return res.json({ catalogue, mine, chairId: chair, note });
});

r.post("/perf/assign", async (req: any, res: any) => {
  const o = await one(`select perf_assign($1, $2::jsonb) as o`,
    [req.person.id, JSON.stringify(req.body || {})]);
  return out(res, o.o);
});

// The same measures onto many people at once. Every one still goes through
// perf_assign inside the database, so nobody is given a KPI by a route that
// skips the checks, and the answer says which were refused and why.
r.post("/perf/assign/bulk", async (req: any, res: any) => {
  const o = await one(`select perf_assign_bulk($1, $2::jsonb) as o`,
    [req.person.id, JSON.stringify(req.body || {})]);
  return out(res, o.o);
});

r.post("/perf/carry", async (req: any, res: any) => {
  const b = req.body || {};
  const o = await one(`select perf_carry_forward($1,$2,$3,$4) as o`,
    [req.person.id, b.cycleId, b.personId, b.keepTargets === true]);
  return out(res, o.o);
});

// The six months behind a measure, so a target is set against what happened.
r.get("/perf/history", async (req: any, res: any) => {
  const o = await one(`select perf_history_for($1,$2,$3,$4,$5) as o`,
    [req.person.id,
     req.query.get("person") || req.person.id,
     req.query.get("name"), req.query.get("kpi"),
     Number(req.query.get("months") || 6)]);
  if (o.o?.error) return out(res, o.o);
  return res.json({ history: o.o });
});

r.get("/perf/score", async (req: any, res: any) => {
  const cycle = req.query.get("cycle");
  if (!cycle) return res.status(400).json({ error: "missing_cycle" });
  const o = await one(`select perf_kpi_score_for($1,$2,$3) as o`,
    [req.person.id, req.query.get("person") || req.person.id, cycle]);
  return out(res, o.o);
});

export default r;
