// MIS, the 10-day management view, and Reports.
//
// The design says the thing these three screens have to obey, in its own
// words: "Nothing on this screen is hard-coded, so it waits for the data layer
// to answer rather than showing numbers from nowhere." So every figure here is
// read from business_record, seam.tenday_snapshot and seam.forecast_scenario,
// and when those are empty the screen says which table is empty and what fills
// it. No demo month, no illustrative totals.

import { Router, many, one } from "../shim.ts";
import { requireChair } from "../scope.ts";
const r = Router();

const DIMS: Record<string, { label: string; sql: string; join: string }> = {
  client: { label: "Client", sql: "c.name",
            join: "left join client c on c.id = b.client_id" },
  zone:   { label: "Zone",   sql: "g.name",
            join: "left join geo_node g on g.id = b.geo_node_id" },
  owner:  { label: "Owner",  sql: "p.full_name",
            join: "left join person p on p.id = b.owner_id" },
};

r.get("/", requireChair, async (req: any, res: any) => {
  const dim = DIMS[req.query.get("group") || "client"] ? (req.query.get("group") || "client") : "client";
  const d = DIMS[dim];
  const periods = await many(
    `select distinct period from business_record order by period desc limit 24`);
  const period = req.query.get("period") || (periods[0] ? periods[0].period : null);

  const rows = period ? await many(
    `select coalesce(${d.sql}, '(not named)') as label,
            sum(b.day10)::bigint  as day10,
            sum(b.mtd)::bigint    as mtd,
            sum(b.target)::bigint as target,
            sum(b.revenue)::numeric as revenue,
            count(*)::int as records
       from business_record b
       ${d.join}
      where b.period = $1
      group by 1 order by 4 desc nulls last, 1`,
    [period]) : [];

  const tiles = period ? await one(
    `select sum(mtd)::bigint as mtd, sum(target)::bigint as target,
            sum(day10)::bigint as day10, sum(revenue)::numeric as revenue,
            count(*)::int as records
       from business_record where period = $1`, [period]) : null;

  // Provenance, as the design asks for: which table answered, and how many rows.
  const provenance = await many(
    `select 'business_record' as table, count(*)::int as n from business_record
     union all select 'target', count(*)::int from target
     union all select 'rate', count(*)::int from rate
     union all select 'perf_revenue', count(*)::int from perf_revenue
     union all select 'perf_collection', count(*)::int from perf_collection`);

  res.json({
    period, periods, group: dim, dims: DIMS, rows, tiles, provenance,
    emptyWhy: period ? null :
      "business_record has no rows, so there is no month to report on. It is " +
      "filled by the Collections and Past performance uploads under Data setup. " +
      "Until then this screen has nothing to read, and showing a number here " +
      "would mean inventing one.",
    noTarget: rows.length && !rows.some((x: any) => Number(x.target || 0) > 0)
      ? "No targets are set for this period, so achievement cannot be worked out. " +
        "Targets come from the KPI targets upload."
      : null,
  });
});

// The 10-day view: where the month could finish, read from what was on the
// board by the 10th. Same records, same rates and same scope as the MIS.
r.get("/tenday", requireChair, async (req: any, res: any) => {
  const periods = await many(
    `select distinct period from seam.tenday_snapshot order by period desc limit 24`);
  const period = req.query.get("period") || (periods[0] ? periods[0].period : null);
  const [rows, scenarios] = await Promise.all([
    period ? many(
      `select location, day10_revenue, actual_revenue, live_addition,
              sheet_x5, sheet_x4, sheet_x35, sheet_x325, src
         from seam.tenday_snapshot where period = $1 order by location`, [period]) : [],
    many(`select key, label, multiplier, stance, source
            from seam.forecast_scenario order by multiplier`),
  ]);
  res.json({
    period, periods, rows, scenarios,
    emptyWhy: period ? null :
      "No ten-day snapshot has been loaded. It is the month's position as at the " +
      "10th, which is what the forecast is read from — without it there is " +
      "nothing to project forward.",
    noScenarios: scenarios.length ? null :
      "No forecast scenarios are configured, so there is no conservative, base or " +
      "stretch to compare against.",
  });
});

// Reports: what this tool can actually produce today, with the row count behind
// each one so the list cannot promise a report that would come out empty.
r.get("/reports", requireChair, async (_req: any, res: any) => {
  const n = await one(
    `select (select count(*) from branch b join client c on c.id=b.client_id
              where c.status='ACTIVE' and b.status='ACTIVE') as branches,
            (select count(*) from branch_matrix_state where complete_levels < 5) as incomplete,
            (select count(*) from coverage_rule where effective_to is null) as coverage,
            (select count(*) from audit_entry) as audit,
            (select count(*) from penalty_instance) as penalties,
            (select count(*) from person where employment_status='ACTIVE') as people,
            (select count(*) from business_record) as business`);
  res.json({
    reports: [
      { key: "matrix",   name: "Branches still missing escalation levels",
        what: "Every active branch with fewer than five levels, and which level is missing.",
        scope: "Your coverage", rows: Number(n.incomplete) },
      { key: "coverage", name: "Coverage and handlers",
        what: "Who covers which client at which location, and the branches each covers.",
        scope: "Everything you can see", rows: Number(n.coverage) },
      { key: "people",   name: "People and chairs",
        what: "Every active person, the chair they hold and who they report to.",
        scope: "Your subtree", rows: Number(n.people) },
      { key: "audit",    name: "Audit trail",
        what: "Every change, who made it and what it was before. Written in the same transaction as the change.",
        scope: "Everything you can see", rows: Number(n.audit) },
      { key: "penalty",  name: "Penalty ledger",
        what: "Every penalty raised, the cutoff missed and the evidence for it.",
        scope: "Your subtree", rows: Number(n.penalties) },
      { key: "mis",      name: "MIS extract",
        what: "The month by client, zone or owner, with target and achievement.",
        scope: "Your coverage", rows: Number(n.business) },
    ],
    note: "A report with no rows behind it is listed with a zero rather than hidden, " +
      "so it is clear the report exists and the data has not arrived yet.",
  });
});

export default r;
