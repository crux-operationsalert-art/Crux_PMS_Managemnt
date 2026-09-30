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

// =====================================================================
// The pyramid, both ways (migrations 223 and 224).
//
// Up: a person files today's number, and perf_value adds it into
// everything above them the same moment. Nothing here does that
// arithmetic -- it asks.
//
// Down: a manager sets a target and it divides across their team. A count
// divides, a percentage is copied, and a share somebody typed by hand is
// pinned and never overwritten.
// =====================================================================

// One person's measures with everything below them already added in.
// Defaults to the caller, so "my line" needs no argument, and refuses a
// person outside it.
r.get("/org", async (req: any, res: any) => {
  const cycle = req.query.get("cycle");
  if (!cycle) return res.status(400).json({ error: "missing_cycle" });
  const o = await one(`select perf_org_rollup($1,$2::uuid,$3::uuid) as o`,
    [req.person.id, cycle, req.query.get("person") || null]);
  return out(res, o.o);
});

// Set one target. The gate is perf_may_set inside the function -- your own
// team, one step, never yourself -- and the cascade runs from there.
//
// manual defaults to TRUE because a person typing into a box means it.
// The only caller that passes false is a cascade, and a cascade does not
// come through here.
r.post("/target", async (req: any, res: any) => {
  const b = req.body || {};
  if (!b.assignmentId) return res.status(400).json({ error: "missing_assignment" });
  if (b.target === null || b.target === undefined || b.target === "") {
    return res.status(400).json({
      error: "missing_target",
      reason: "A target needs a number. To clear one, set it to zero and say why.",
    });
  }
  const o = await one(`select perf_target_set($1,$2::uuid,$3::numeric,$4) as o`,
    [req.person.id, b.assignmentId, b.target, b.manual !== false]);
  return out(res, o.o);
});

// What the cascade would do, without doing it: the measures that climb
// into this one, what each holds now, and which of them are pinned. So a
// manager can see who is about to move before they move them.
r.get("/target/team", async (req: any, res: any) => {
  const id = req.query.get("assignment");
  if (!id) return res.status(400).json({ error: "missing_assignment" });
  const mine = await one(
    `select a.id, a.person_id, a.name, a.unit, a.target_value as target,
            a.target_source as "targetSource",
            perf_accrual_kind(a.kpi_id, a.unit) as kind,
            perf_rel($1, a.person_id) as rel
       from perf_assignment a where a.id = $2::uuid`,
    [req.person.id, id]);
  if (!mine) return res.status(404).json({ error: "no_such_assignment" });
  if (mine.rel == null) {
    return res.status(403).json({ error: "not_permitted",
      reason: "That measure is not in your line." });
  }
  const team = await many(
    `select c.id as "assignmentId", p.full_name as name, p.employee_no as "employeeNo",
            c.target_value as target, c.target_source as "targetSource",
            c.target_source = 'MANUAL' as pinned,
            perf_rel($1, c.person_id) as rel,
            perf_rel($1, c.person_id) = 'manage' as "maySet",
            (select count(*) from perf_assignment g where g.rolls_into_id = c.id) as feeders
       from perf_assignment c
       join person p on p.id = c.person_id
      where c.rolls_into_id = $2::uuid
      order by p.full_name`,
    [req.person.id, id]);
  return res.json({
    measure: mine, team,
    divides: mine.kind === "SUM",
    note: mine.kind === "SUM"
      ? "A count. What is pinned comes off the top and the rest share what is left."
      : "A percentage. Every person carries the same number; it is not divided.",
  });
});

// What came up from below and stopped there (migration 226).
//
// Most of what a team files climbs on its own. Some of it cannot: the
// measure below is a different quantity from anything the person above
// holds, so no arithmetic can add it in. Those are the numbers a chair has
// to read and then account for in their own filing -- the step the pyramid
// leaves to a human, made visible instead of left implicit.
r.get("/handover", async (req: any, res: any) => {
  const cycle = req.query.get("cycle");
  if (!cycle) return res.status(400).json({ error: "missing_cycle" });
  const o = await one(`select perf_handover($1,$2::uuid,$3::uuid) as o`,
    [req.person.id, cycle, req.query.get("person") || null]);
  return out(res, o.o);
});

// =====================================================================
// The month, read out of the same filings (migration 227).
//
// A suggestion and nothing else. plb_month_suggest writes no row: the
// Constitution's "partly or late" is a person's call about a person, and a
// system that scored it silently would be inventing judgements. So this is
// safe to call on every load of the screen.
//
// The caller passes a date, not a sheet, because a person on the screen
// knows what month they are looking at and does not know their goal
// sheet's id. The quarter it falls in picks the sheet.
// =====================================================================
r.get("/month", async (req: any, res: any) => {
  const who = req.query.get("person") || req.person.id;
  const on = req.query.get("on") || null;
  let sheet = req.query.get("sheet");
  if (!sheet) {
    const row = await one(
      `select s.id
         from plb_goal_sheet s
        where s.person_id = $1::uuid
          and s.quarter = date_trunc('quarter', coalesce($2::date, current_date))::date
        order by s.created_at desc limit 1`,
      [who, on]);
    // No sheet for that quarter is an ordinary state, not a fault -- the
    // screen has nothing to show and says nothing.
    if (!row) {
      return res.json({
        error: "no_sheet",
        reason: "No goal sheet has been issued for that quarter yet.",
      });
    }
    sheet = row.id;
  }
  const o = await one(`select plb_month_suggest($1,$2::uuid,coalesce($3::date, current_date)) as o`,
    [req.person.id, sheet, on]);
  return out(res, o.o);
});

// =====================================================================
// The team, as a structure (migration 229).
//
// The chart the tool already had is the chair tree. This is the people
// tree -- person.manager_id -- which is what every visibility rule is
// built on. Both routes are thin: org_team_tree and org_move_person do
// their own checking, and org_move_person is the most consequential write
// in the tool because moving somebody changes who can read their numbers.
// =====================================================================

r.get("/team/tree", async (req: any, res: any) => {
  const o = await one(`select org_team_tree($1,$2::uuid,$3::uuid) as o`,
    [req.person.id, req.query.get("root") || null, req.query.get("cycle") || null]);
  return out(res, o.o);
});

// A drag that landed. personId moves under managerId.
//
// managerId may legitimately be null -- that is "out of the line
// altogether" -- and org_move_person refuses it for anybody but HR and an
// administrator. So the absence of the field is passed through rather
// than treated as a missing argument.
r.post("/team/move", async (req: any, res: any) => {
  const b = req.body || {};
  if (!b.personId) return res.status(400).json({ error: "missing_person" });
  const o = await one(`select org_move_person($1,$2::uuid,$3::uuid) as o`,
    [req.person.id, b.personId, b.managerId || null]);
  if (o.o?.error === "would_loop") {
    return res.status(409).json(o.o);
  }
  return out(res, o.o);
});

export default r;
