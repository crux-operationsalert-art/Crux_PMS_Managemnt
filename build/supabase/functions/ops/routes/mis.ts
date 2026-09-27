// MIS, the 10-day management view, and Reports.
//
// The design says the thing these three screens have to obey, in its own
// words: "Nothing on this screen is hard-coded, so it waits for the data layer
// to answer rather than showing numbers from nowhere." So every figure here is
// read from business_record, seam.tenday_snapshot and seam.forecast_scenario,
// and when those are empty the screen says which table is empty and what fills
// it. No demo month, no illustrative totals.

import { Router, many, one, tx } from "../shim.ts";
import { emptyReason, idList, recordScope, requireChair, requireScreen } from "../scope.ts";
const r = Router();

const DIMS: Record<string, { label: string; sql: string; join: string }> = {
  client: { label: "Client", sql: "c.name",
            join: "left join client c on c.id = b.client_id" },
  zone:   { label: "Zone",   sql: "g.name",
            join: "left join geo_node g on g.id = b.geo_node_id" },
  owner:  { label: "Owner",  sql: "p.full_name",
            join: "left join person p on p.id = b.owner_id" },
};

// D8 again: no chair may borrow another chair's data. These screens read
// business_record, which is keyed by (client, geography), so the caller's
// coverage has to be reduced to the same pairs before it can be applied --
// and matched AS pairs, or somebody covering Client A in Zone 1 and Client B
// in Zone 2 would be shown Client A in Zone 2.
//
// The predicate below is written once and used by all three reads. A null
// first array means "everything", which is what an administrator gets and
// what nobody else does.
const IN_SCOPE = (a: string, b: string, alias = "b") =>
  `($${a}::uuid[] is null or exists (
      select 1 from unnest($${a}::uuid[], $${b}::uuid[]) as s(cid, gid)
       where s.cid = ${alias}.client_id and s.gid = ${alias}.geo_node_id))`;

// The pairs, or nulls for an administrator. Returned together so a route
// cannot accidentally use one without the other.
async function coveragePairs(req: any) {
  if (req.scope.isAdmin) return { all: true, cids: null, gids: null, pairs: 0 };
  const rows = await recordScope(req.person.id);
  return {
    all: false,
    cids: rows.map((x: any) => x.client_id),
    gids: rows.map((x: any) => x.geo_node_id),
    pairs: rows.length,
  };
}

r.get("/", requireChair, requireScreen("mis"), async (req: any, res: any) => {
  const dim = DIMS[req.query.get("group") || "client"] ? (req.query.get("group") || "client") : "client";
  const d = DIMS[dim];
  const sc = await coveragePairs(req);

  // No coverage is a real, expected condition for a new chair. It is not an
  // error and it is not somebody else's figures, so it says which it is.
  if (!sc.all && !sc.pairs) {
    return res.json({
      period: null, periods: [], group: dim, dims: DIMS, rows: [], tiles: null,
      provenance: [], compare: false, prevPeriod: null, compareWhy: null,
      noTarget: null, scopedTo: 0,
      emptyWhy: emptyReason(req.scope),
    });
  }

  const periods = await many(
    `select distinct b.period from business_record b
      where ${IN_SCOPE("1", "2")}
      order by b.period desc limit 24`, [sc.cids, sc.gids]);
  const period = req.query.get("period") || (periods[0] ? periods[0].period : null);

  // Period comparison. The design's MIS carries cmpPrev, cmpChange and
  // cmpGrowth columns; the month to compare against is the one immediately
  // before the one being shown, which is whatever the period list says it is
  // rather than a date calculation that would invent a month with no records.
  const compare = req.query.get("compare") === "prev";
  const at = periods.findIndex((p: any) => p.period === period);
  const prevPeriod = compare && at >= 0 && periods[at + 1] ? periods[at + 1].period : null;

  const rows = period ? await many(
    `select coalesce(${d.sql}, '(not named)') as label,
            sum(b.day10)::bigint  as day10,
            sum(b.mtd)::bigint    as mtd,
            sum(b.target)::bigint as target,
            sum(b.revenue)::numeric as revenue,
            count(*)::int as records
       from business_record b
       ${d.join}
      where b.period = $1 and ${IN_SCOPE("2", "3")}
      group by 1 order by 4 desc nulls last, 1`,
    [period, sc.cids, sc.gids]) : [];

  const tiles = period ? await one(
    `select sum(b.mtd)::bigint as mtd, sum(b.target)::bigint as target,
            sum(b.day10)::bigint as day10, sum(b.revenue)::numeric as revenue,
            count(*)::int as records
       from business_record b
      where b.period = $1 and ${IN_SCOPE("2", "3")}`,
    [period, sc.cids, sc.gids]) : null;

  // Provenance, as the design asks for: which table answered, and how many
  // rows. For anyone but the administrator that is the rows THEY can read, or
  // the line would quietly report the size of the company.
  const provenance = sc.all
    ? await many(
      `select 'business_record' as table, count(*)::int as n from business_record
       union all select 'target', count(*)::int from target
       union all select 'rate', count(*)::int from rate
       union all select 'perf_revenue', count(*)::int from perf_revenue
       union all select 'perf_collection', count(*)::int from perf_collection`)
    : await many(
      `select 'business_record' as table, count(*)::int as n
         from business_record b where ${IN_SCOPE("1", "2")}`,
      [sc.cids, sc.gids]);

  // the same shape for the month before, merged on the label
  const prevRows = prevPeriod ? await many(
    `select coalesce(${d.sql}, '(not named)') as label,
            sum(b.mtd)::bigint    as mtd,
            sum(b.target)::bigint as target,
            sum(b.revenue)::numeric as revenue
       from business_record b
       ${d.join}
      where b.period = $1 and ${IN_SCOPE("2", "3")}
      group by 1`,
    [prevPeriod, sc.cids, sc.gids]) : [];
  const was: Record<string, any> = {};
  for (const p of prevRows) was[p.label] = p;
  for (const row of rows as any[]) {
    const p = was[row.label];
    row.prev_mtd = p ? p.mtd : null;
    row.prev_revenue = p ? p.revenue : null;
    // A change from nothing is not a percentage. Saying "new" is the honest
    // answer; "+100%" and "+Infinity%" are both wrong.
    const a = Number(row.mtd || 0), b0 = p ? Number(p.mtd || 0) : null;
    row.change = b0 === null ? null : a - b0;
    row.growth = b0 === null ? null : (b0 === 0 ? (a === 0 ? 0 : null) : ((a - b0) / b0) * 100);
  }

  res.json({
    period, periods, group: dim, dims: DIMS, rows, tiles, provenance,
    compare, prevPeriod,
    // What the figures are OF. A total with no scope printed beside it is the
    // thing somebody carries into a meeting and defends as the company's.
    scopedTo: sc.all ? null : sc.pairs,
    scopeNote: sc.all
      ? "Every record, because you are the administrator."
      : "Your coverage: " + sc.pairs + " client and location " +
        (sc.pairs === 1 ? "pair" : "pairs") + ". Somebody with different " +
        "coverage sees different figures, and that is the point.",
    compareWhy: compare && !prevPeriod
      ? "There is no earlier month loaded to compare " + period + " against."
      : null,
    emptyWhy: period ? null :
      "business_record has no rows you cover, so there is no month to report " +
      "on. It is " +
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
r.get("/tenday", requireChair, requireScreen("tenday"), async (req: any, res: any) => {
  const sc = await coveragePairs(req);
  const scenarios = await many(
    `select key, label, multiplier, stance, source
       from seam.forecast_scenario order by multiplier`);

  if (!sc.all && !sc.pairs) {
    return res.json({
      period: null, periods: [], rows: [], scenarios, scopedTo: 0,
      emptyWhy: emptyReason(req.scope),
      noScenarios: scenarios.length ? null :
        "No forecast scenarios are configured, so there is no conservative, base or " +
        "stretch to compare against.",
    });
  }

  // The view carries client_id and geo_node_id since migration 205, so the
  // row can be matched against coverage as a pair. Filtering on the location
  // name would show one client's position to somebody who covers a different
  // client in the same city.
  const periods = await many(
    `select distinct t.period from seam.tenday_snapshot t
      where ${IN_SCOPE("1", "2", "t")} order by t.period desc limit 24`,
    [sc.cids, sc.gids]);
  const period = req.query.get("period") || (periods[0] ? periods[0].period : null);
  const rows = period ? await many(
      `select t.location, t.day10_revenue, t.actual_revenue, t.live_addition,
              t.sheet_x5, t.sheet_x4, t.sheet_x35, t.sheet_x325, t.src
         from seam.tenday_snapshot t
        where t.period = $1 and ${IN_SCOPE("2", "3", "t")}
        order by t.location`, [period, sc.cids, sc.gids]) : [];
  res.json({
    period, periods, rows, scenarios,
    scopedTo: sc.all ? null : sc.pairs,
    emptyWhy: period ? null :
      "No ten-day snapshot has been loaded for anything you cover. It is the " +
      "month's position as at the " +
      "10th, which is what the forecast is read from — without it there is " +
      "nothing to project forward.",
    noScenarios: scenarios.length ? null :
      "No forecast scenarios are configured, so there is no conservative, base or " +
      "stretch to compare against.",
  });
});

// Reports: what this tool can actually produce today, with the row count behind
// each one so the list cannot promise a report that would come out empty.
//
// Each line already declares its scope -- "Your coverage", "Your subtree" --
// and until now every count beside those words was the company's. A number
// that contradicts the sentence next to it is worse than no number, so the
// counts are taken inside the scope each line claims.
r.get("/reports", requireChair, requireScreen("reports"), async (req: any, res: any) => {
  const all = !!req.scope.isAdmin;
  const me = all ? null : req.person.id;
  const subtree = all ? null : idList(req.scope.subtreeIds);
  const n = await one(
    `with mine as (
       -- Only resolved for a real person. An administrator passes null and
       -- never reads this, and resolving all 479 coverage rules to satisfy a
       -- count nobody is going to use would be a slow way to answer nothing.
       select distinct cr.branch_id
         from coverage_rule r
         cross join lateral coverage_resolve(r) cr(branch_id)
        where $1::uuid is not null and r.person_id = $1
          and (r.effective_to is null or r.effective_to >= current_date))
     select (select count(*) from branch b join client c on c.id=b.client_id
              where c.status='ACTIVE' and b.status='ACTIVE'
                and ($1::uuid is null or b.id in (select branch_id from mine))) as branches,
            (select count(*) from branch_matrix_state s
              where s.complete_levels < 5
                and ($1::uuid is null or s.branch_id in (select branch_id from mine))) as incomplete,
            (select count(*) from coverage_rule
              where effective_to is null
                and ($1::uuid is null or person_id = $1)) as coverage,
            (select count(*) from audit_entry a
              where $1::uuid is null or a.actor_id = $1) as audit,
            -- subtreeIds are CHAIR ids, and a penalty is charged to a
            -- PERSON. Matching one against the other would have counted zero
            -- for everybody and looked like an empty ledger.
            (select count(*) from penalty_instance pi
              where $2::uuid[] is null
                 or pi.person_id = $1
                 or exists (select 1 from chair_holder h
                             where h.person_id = pi.person_id and h.to_date is null
                               and h.chair_id = any($2::uuid[]))) as penalties,
            (select count(*) from person p
              where p.employment_status='ACTIVE' and p.superseded_by is null
                and ($2::uuid[] is null or exists (
                      select 1 from chair_holder h
                       where h.person_id = p.id and h.to_date is null
                         and h.chair_id = any($2::uuid[]))
                     or p.id = $1)) as people,
            (select count(*) from business_record b
              where $1::uuid is null or exists (
                    select 1 from mine m join branch bb on bb.id = m.branch_id
                     where bb.client_id = b.client_id
                       and bb.geo_node_id = b.geo_node_id)) as business`,
    [me, subtree]);
  res.json({
    scopedTo: all ? "Everything, because you are the administrator."
                  : "Your coverage and the chairs under yours.",
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

// ------------------------------------------------------------ saved views
// "Only the configuration is stored -- grouping, filters, sort, comparison,
// month and expanded rows -- never a copy of the data, so a saved view always
// reflects current records." So this writes what was selected and nothing that
// could go stale. A view belongs to the person who saved it.
r.get("/views", requireChair, requireScreen("mis"), async (req: any, res: any) => {
  const views = await many(
    `select id, name, config, created_at, used_at
       from mis_view where person_id = $1 order by lower(name)`,
    [req.person.id]);
  res.json({ views,
    note: "A saved view stores what you selected, never the figures, so it " +
      "always reads current records." });
});

r.post("/views", requireChair, requireScreen("mis"), async (req: any, res: any, next: any) => {
  const { name, config } = req.body || {};
  try {
    if (!name || !String(name).trim()) {
      return res.status(400).json({ error: "name_required",
        reason: "A saved view needs a name you will recognise it by." });
    }
    if (!config || typeof config !== "object" || Array.isArray(config)) {
      return res.status(400).json({ error: "config_required",
        reason: "A view is the selection it was saved with." });
    }
    const v = await tx(req.person.id, async (t: any) => {
      const row = (await t.q(
        `insert into mis_view (person_id, name, config)
         values ($1, $2, $3::jsonb)
         on conflict (person_id, lower(btrim(name))) do update
           set config = excluded.config, created_at = now()
         returning id, name, config, created_at`,
        // The object, NOT JSON.stringify(object): postgres.js serialises a
        // value bound to a jsonb parameter itself, so a string that is already
        // JSON gets encoded a second time and lands as a jsonb STRING. That is
        // exactly what mis_view_config_is_object caught on the first call.
        [req.person.id, String(name).trim(), config])).rows[0];
      await t.audit("MIS_VIEW_SAVED", "mis_view", row.id, null, { name: row.name });
      return row;
    });
    res.status(201).json(v);
  } catch (e) { next(e); }
});

r.delete("/views/:id", requireChair, requireScreen("mis"), async (req: any, res: any, next: any) => {
  try {
    const gone = await tx(req.person.id, async (t: any) => {
      const row = (await t.q(
        `delete from mis_view where id = $1 and person_id = $2 returning name`,
        [req.params.id, req.person.id])).rows[0];
      if (!row) return null;
      await t.audit("MIS_VIEW_DELETED", "mis_view", req.params.id, { name: row.name }, null);
      return row;
    });
    if (!gone) return res.status(404).json({ error: "not_found",
      reason: "That view is not yours, or it is already gone." });
    res.json({ ok: true, name: gone.name });
  } catch (e) { next(e); }
});

export default r;
