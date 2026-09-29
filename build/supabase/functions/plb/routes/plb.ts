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
  const o = await one(`select perf_tree($1,$2) as o`, [who, cycle]);
  return res.json(o.o);
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

// Who I may set KPIs for. A manager's own reports, and for HR or an
// administrator everybody -- asked of the database rather than decided
// here, so the list and the gate cannot disagree.
r.get("/perf/team", async (req: any, res: any) => {
  const people = await many(
    `select p.id as "personId", p.full_name as name, p.employee_no as "employeeNo",
            p.department,
            (select ch.title from chair_holder h join chair ch on ch.id = h.chair_id
              where h.person_id = p.id and h.to_date is null
              order by h.is_primary desc, ch.title limit 1) as chair
       from person p
      where p.superseded_by is null and p.employment_status = 'ACTIVE'
        and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
        and perf_may_set($1, p.id)
      order by p.full_name`,
    [req.person.id],
  );
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
  const o = await one(`select perf_history($1,$2,$3,$4) as o`,
    [req.query.get("person") || req.person.id,
     req.query.get("name"), req.query.get("kpi"),
     Number(req.query.get("months") || 6)]);
  return res.json({ history: o.o });
});

r.get("/perf/score", async (req: any, res: any) => {
  const cycle = req.query.get("cycle");
  if (!cycle) return res.status(400).json({ error: "missing_cycle" });
  const o = await one(`select perf_kpi_score($1,$2) as o`,
    [req.query.get("person") || req.person.id, cycle]);
  return res.json(o.o);
});

// The fortnight strip above the KPI list. Days, not numbers: a run is a
// record of showing up, and a Sunday cannot break one.
r.get("/perf/filed", async (req: any, res: any) => {
  const o = await one(`select perf_filed_days($1, $2::int) as o`,
    [req.query.get("person") || req.person.id, Number(req.query.get("days") || 14)]);
  return res.json(o.o);
});

// =====================================================================
// Tasks — "Assign a task", the second of the three buttons the blueprint
// puts over the team list.
//
// One person asking another for a specific thing by a date: one manager,
// or every manager at once. Not an escalation and not a KPI. It lands on
// A-3, contribution beyond your own chair, which the Scorecard Guide says
// must cite a named artefact rather than a manager's assertion — and a
// task closed on time IS that artefact.
//
// Every one of these is a thin call onto a SECURITY DEFINER function that
// does its own permission check, for the reason the rest of this file
// gives: "you may only ask somebody who reports to you" is enforced once,
// in the database, rather than restated here and left to drift.
// =====================================================================

const periodOf = (s?: string) => {
  if (s && /^\d{4}-\d{2}$/.test(s)) return s;
  const d = s ? new Date(s) : new Date();
  return d.toISOString().slice(0, 7);
};

// What I owe and what I asked of other people, for one month.
r.get("/task/mine", async (req: any, res: any) => {
  const period = periodOf(req.query.get("period") || undefined);
  const o = await one(`select task_mine($1,$2) as o`, [req.person.id, period]);
  return res.json(o.o);
});

// A month's tasks for one person, and the A-3 they suggest. Asked of
// somebody else it is still the database that decides whether the caller
// may look — perf_may_set is the same gate the KPI side uses, because
// "may I score you" and "may I see what you were asked to do" are the
// same question.
r.get("/task/evidence", async (req: any, res: any) => {
  const who = req.query.get("person") || req.person.id;
  const period = periodOf(req.query.get("period") || undefined);
  if (who !== req.person.id) {
    const ok = await one(`select perf_may_set($1,$2) as ok`, [req.person.id, who]);
    if (!ok?.ok) {
      return res.status(403).json({
        error: "not_permitted",
        reason: "You can see what somebody was asked to do if you could score them.",
      });
    }
  }
  const o = await one(`select task_evidence($1,$2) as o`, [who, period]);
  return res.json(o.o);
});

// Set one. people / chair / department / allReports — the four ways
// "all the managers" actually gets written down.
r.post("/task/assign", async (req: any, res: any) => {
  const o = await one(`select task_assign($1,$2::jsonb) as o`,
    [req.person.id, JSON.stringify(req.body || {})]);
  return out(res, o.o);
});

// Done. Whether that reads DONE or LATE is the clock's answer, not the
// caller's, so there is nothing to pass but the outcome.
r.post("/task/close", async (req: any, res: any) => {
  const b = req.body || {};
  if (!b.id) return res.status(400).json({ error: "missing_task" });
  const o = await one(`select task_close($1,$2::uuid,$3) as o`,
    [req.person.id, b.id, b.outcome || null]);
  return out(res, o.o);
});

// Called off, by whoever asked for it.
r.post("/task/cancel", async (req: any, res: any) => {
  const b = req.body || {};
  if (!b.id) return res.status(400).json({ error: "missing_task" });
  const o = await one(`select task_cancel($1,$2::uuid,$3) as o`,
    [req.person.id, b.id, b.why || null]);
  return out(res, o.o);
});

// =====================================================================
// The weighting — the blueprint's "PMS weighting · Admin and HR" panel.
//
// The split between KPIs and Attributes, for everybody or for a chair or
// for one person, from a date. The Constitution sets it at 75/25 from
// 1 October 2026; before that date the reader is told the scheme has not
// started rather than shown a blank chip.
// =====================================================================

r.get("/weighting", async (req: any, res: any) => {
  const who = req.query.get("person") || req.person.id;
  const on = req.query.get("on") || null;
  const mine = await one(
    `select pms_weighting_for($1, coalesce($2::date, current_date)) as o`, [who, on]);
  // The whole table as well, but only for the people who may change it —
  // one person's split is nobody else's business.
  const rows = maySetUp(req)
    ? await many(
        `select w.id, w.scope_all as "scopeAll", w.kpi_percent as "kpiPercent",
                w.attr_percent as "attrPercent", w.effective_from as "effectiveFrom",
                c.title as chair, p.full_name as person,
                s.full_name as "setBy"
           from pms_weighting w
           left join chair  c on c.id = w.chair_id
           left join person p on p.id = w.person_id
           left join person s on s.id = w.set_by
          order by w.effective_from desc, w.scope_all desc`)
    : null;
  return res.json({ mine: mine.o, all: rows, maySet: maySetUp(req) });
});

r.post("/weighting", async (req: any, res: any) => {
  if (!maySetUp(req)) {
    return res.status(403).json({
      error: "not_permitted",
      reason: "The split between KPIs and Attributes is Admin's and HR's to set.",
    });
  }
  const b = req.body || {};
  const kpi = Number(b.kpiPercent), attr = Number(b.attrPercent);
  if (!Number.isFinite(kpi) || !Number.isFinite(attr) || kpi + attr !== 100) {
    return res.status(400).json({
      error: "does_not_add_up",
      reason: "A split has to add to 100. " + kpi + " and " + attr + " make " + (kpi + attr) + ".",
    });
  }
  const scopeAll = !b.chairId && !b.personId;
  const row = await one(
    `insert into pms_weighting (scope_all, chair_id, person_id, kpi_percent,
                                attr_percent, effective_from, set_by)
     values ($1, $2::uuid, $3::uuid, $4::numeric, $5::numeric,
             coalesce($6::date, current_date), $7)
     returning id, effective_from as "effectiveFrom"`,
    [scopeAll, b.chairId || null, b.personId || null, kpi, attr,
     b.effectiveFrom || null, req.person.id],
  );
  return res.json({
    saved: row,
    note: "Set from " + row.effectiveFrom + ". Earlier months keep the split they were scored under.",
  });
});

export default r;
