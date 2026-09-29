// =====================================================================
// The Performance screen's later sections.
//
// Every one of these is a thin call onto a SECURITY DEFINER function that
// does its own permission check -- "you may only ask somebody who reports
// to you" is enforced once, in the database, rather than restated here and
// left to drift.
// =====================================================================
import { Router, one, many } from "../shim.ts";
const r = Router();

// Running the scheme is HR's and Business Excellence's; being measured by
// it is everybody's. Same rule, same words, as plb/routes/plb.ts.
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


// The fortnight strip above the KPI list. Days, not numbers: a run is a
// record of showing up, and a Sunday cannot break one.
r.get("/filed", async (req: any, res: any) => {
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
