// The generic table endpoint the application's data seam calls. Carried across
// from build/api/routes/table.js; the SQL and the allow-list are unchanged.
//
//   GET    /api/:table?col=v&col=v   -> rows   (a repeated param means "in this set")
//   POST   /api/:table               -> inserted row
//   PATCH  /api/:table/:id           -> updated row
//   DELETE /api/:table/:id           -> ok
//
// Reads come from the seam schema, whose views present this database in the
// shape the application expects. See build/supabase/03_seam_views.sql.
//
// Scope is enforced in the query, never in the caller. A request with no scope
// returns an empty set and a reason (D8) — never another chair's rows.
import { Router, q, many, tx } from "../shim.ts";
import { emptyReason } from "../scope.ts";

// Allow-list. A table absent from here is not reachable at all, so a mistake
// upstream cannot turn this into a way to read any table in the database.
const TABLES: Record<string, { scope: string; pk?: string; writesTo?: string }> = {
  geo_zone:          { scope: "reference" },
  client:            { scope: "reference" },
  holiday:           { scope: "reference", pk: "date", writesTo: "holiday" },
  forecast_scenario: { scope: "reference", pk: "key" },
  person:            { scope: "subtree" },
  assignment:        { scope: "coverage" },
  business_record:   { scope: "coverage" },
  rate:              { scope: "coverage" },
  tenday_snapshot:   { scope: "coverage" },
  rate_anomaly:      { scope: "coverage" },
};

// Column names are read from the view itself rather than hardcoded, so a view
// change cannot silently leave this rejecting a column that now exists.
const columnCache = new Map<string, Set<string>>();
async function columnsOf(table: string) {
  const hit = columnCache.get(table);
  if (hit) return hit;
  const rows = await many(
    `select column_name from information_schema.columns
      where table_schema = 'seam' and table_name = $1`,
    [table],
  );
  const set = new Set<string>(rows.map((r: any) => r.column_name));
  columnCache.set(table, set);
  return set;
}

// The clients and zones this person covers. A CLIENT-scoped rule carries no
// zone and covers every zone for that client, so the two sets are separate.
async function coverageSets(personId: string) {
  const rows = await many(
    `select client_id::text as client_id, geo_node_id::text as zone_id
       from coverage_rule
      where person_id = $1
        and (effective_to is null or effective_to >= current_date)`,
    [personId],
  );
  return {
    clients: [...new Set(rows.map((r: any) => r.client_id).filter(Boolean))],
    zones: [...new Set(rows.map((r: any) => r.zone_id).filter(Boolean))],
  };
}

async function subtreePeople(scope: any) {
  if (!scope.subtreeIds.length) return [scope.personId];
  const rows = await many(
    `select distinct person_id::text as id from chair_holder
      where chair_id = any($1::uuid[]) and to_date is null`,
    [scope.subtreeIds],
  );
  return [...new Set([scope.personId, ...rows.map((r: any) => r.id)])];
}

async function scopePredicate(table: string, req: any, params: unknown[]) {
  const spec = TABLES[table];
  const scope = req.scope;
  if (spec.scope === "reference") return { sql: null as string | null };
  if (req.person && req.person.app_role === "ADMIN") return { sql: null as string | null };
  if (!scope || !scope.chairs.length) return { empty: true, reason: emptyReason(scope) };

  if (spec.scope === "subtree") {
    const ids = await subtreePeople(scope);
    params.push(ids);
    return { sql: `id = any($${params.length}::text[])` };
  }

  const cov = await coverageSets(scope.personId);
  if (!cov.clients.length && !cov.zones.length) return { empty: true, reason: emptyReason(scope) };

  const cols = await columnsOf(table);
  const parts: string[] = [];
  if (cov.clients.length && cols.has("client_id")) {
    params.push(cov.clients);
    parts.push(`client_id = any($${params.length}::text[])`);
  }
  if (cov.zones.length && cols.has("zone_id")) {
    params.push(cov.zones);
    parts.push(`zone_id = any($${params.length}::text[])`);
  }
  if (!parts.length) return { sql: null as string | null };
  return { sql: "(" + parts.join(" or ") + ")" };
}

function notWritable(table: string, res: any) {
  return res.status(501).json({
    error: "write_not_mapped",
    reason:
      `${table} is read-only through this endpoint. It is a view over several ` +
      `tables, so a write has to name which one it means. Masters are loaded ` +
      `through Data setup -> Bulk upload, which validates and applies them ` +
      `all-or-nothing.`,
  });
}

function known(table: string, res: any) {
  if (TABLES[table]) return true;
  res.status(404).json({
    error: "unknown_table",
    reason: `No table "${table}" is exposed.`,
    tables: Object.keys(TABLES),
  });
  return false;
}

const router = Router();

router.get("/:table", async (req: any, res: any) => {
  const table = req.params.table;
  if (!known(table, res)) return;
  const cols = await columnsOf(table);
  const params: unknown[] = [];
  const where: string[] = [];

  for (const k of new Set(req.query.keys())) {
    if (!cols.has(k)) {
      return res.status(400).json({
        error: "unknown_column",
        reason: `"${k}" is not a column of ${table}.`,
      });
    }
    params.push(req.query.getAll(k).map(String));
    where.push(`${k}::text = any($${params.length}::text[])`);
  }

  const sc: any = await scopePredicate(table, req, params);
  if (sc.empty) {
    // The header is why the page is empty. The body carries it too, because a
    // browser can only read an exposed header and this must never be silent.
    res.set("x-crux-empty-reason", sc.reason);
    return res.json([]);
  }
  if (sc.sql) where.push(sc.sql);

  const sql = `select * from seam.${table}` + (where.length ? " where " + where.join(" and ") : "");
  res.json((await q(sql, params)).rows);
});

// Writes reach the underlying table, never the view. Only tables whose mapping
// is one-to-one are writable; the rest say so rather than failing obscurely.
router.post("/:table", async (req: any, res: any) => {
  const table = req.params.table;
  if (!known(table, res)) return;
  if (table !== "holiday") return notWritable(table, res);
  const b = req.body || {};
  const row = await tx(req.person.id, async (t: any) => {
    const r = await t.q(
      `insert into holiday (day, name, applies_to, confirmed, source)
       values ($1,$2,$3,coalesce($4,true),'api')
       returning day as date, name, applies_to as scope, confirmed`,
      [b.date, b.name, b.scope || null, b.confirmed],
    );
    await t.audit("CREATE", "holiday", String(b.date), null, r.rows[0]);
    return r.rows[0];
  });
  res.json(row);
});

router.patch("/:table/:id", async (req: any, res: any) => {
  const table = req.params.table;
  if (!known(table, res)) return;
  if (table !== "holiday") return notWritable(table, res);
  const b = req.body || {};
  const row = await tx(req.person.id, async (t: any) => {
    const before = (await t.q(
      `select day as date, name, applies_to as scope, confirmed from holiday where day = $1`,
      [req.params.id],
    )).rows[0];
    if (!before) return null;
    const r = await t.q(
      `update holiday set name = coalesce($2, name),
                          applies_to = coalesce($3, applies_to),
                          confirmed = coalesce($4, confirmed)
        where day = $1
        returning day as date, name, applies_to as scope, confirmed`,
      [req.params.id, b.name ?? null, b.scope ?? null, b.confirmed ?? null],
    );
    await t.audit("UPDATE", "holiday", String(req.params.id), before, r.rows[0]);
    return r.rows[0];
  });
  if (!row) return res.status(404).json({ error: "not_found" });
  res.json(row);
});

router.delete("/:table/:id", async (req: any, res: any) => {
  const table = req.params.table;
  if (!known(table, res)) return;
  if (table !== "holiday") return notWritable(table, res);
  const ok = await tx(req.person.id, async (t: any) => {
    const before = (await t.q(
      `select day as date, name, applies_to as scope, confirmed from holiday where day = $1`,
      [req.params.id],
    )).rows[0];
    if (!before) return false;
    await t.q(`delete from holiday where day = $1`, [req.params.id]);
    await t.audit("DELETE", "holiday", String(req.params.id), before, null);
    return true;
  });
  if (!ok) return res.status(404).json({ error: "not_found" });
  res.json({ ok: true });
});

export default router;
export { TABLES };
