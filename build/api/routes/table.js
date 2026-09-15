// The generic table endpoint the application's data seam calls.
//
//   GET    /api/:table?col=v&col=v   -> rows   (a repeated param means "in this set")
//   POST   /api/:table               -> inserted row
//   PATCH  /api/:table/:id           -> updated row
//   DELETE /api/:table/:id           -> ok
//
// Reads come from the seam schema, whose views present this database in the
// shape the application expects. See build/supabase/seam_views.sql.
//
// Scope is enforced in the query, never in the caller. A request with no scope
// returns an empty set and a reason (D8) -- never another chair's rows.
const { Router } = require('express');
const { q, many, tx } = require('../db');
const scopeLib = require('../scope');

// Allow-list. A table absent from here is not reachable at all, so a mistake
// upstream cannot turn this into a way to read any table in the database.
const TABLES = {
  geo_zone:          { scope: 'reference' },
  client:            { scope: 'reference' },
  holiday:           { scope: 'reference', pk: 'date', writesTo: 'holiday' },
  forecast_scenario: { scope: 'reference', pk: 'key' },
  person:            { scope: 'subtree' },
  assignment:        { scope: 'coverage' },
  business_record:   { scope: 'coverage' },
  rate:              { scope: 'coverage' },
  tenday_snapshot:   { scope: 'coverage' },
  rate_anomaly:      { scope: 'coverage' },
};

// Column names are read from the view itself rather than hardcoded, so a view
// change cannot silently leave this rejecting a column that now exists.
const columnCache = new Map();
async function columnsOf(table) {
  if (columnCache.has(table)) return columnCache.get(table);
  const rows = await many(
    `select column_name from information_schema.columns
      where table_schema = 'seam' and table_name = $1`,
    [table]
  );
  const set = new Set(rows.map((r) => r.column_name));
  columnCache.set(table, set);
  return set;
}

// The clients and zones this person covers. A CLIENT-scoped rule carries no
// zone and covers every zone for that client, so the two sets are separate.
async function coverageSets(personId) {
  const rows = await many(
    `select client_id::text as client_id, geo_node_id::text as zone_id
       from coverage_rule
      where person_id = $1
        and (effective_to is null or effective_to >= current_date)`,
    [personId]
  );
  return {
    clients: [...new Set(rows.map((r) => r.client_id).filter(Boolean))],
    zones: [...new Set(rows.map((r) => r.zone_id).filter(Boolean))],
  };
}

async function subtreePeople(scope) {
  if (!scope.subtreeIds.length) return [scope.personId];
  const rows = await many(
    `select distinct person_id::text as id from chair_holder
      where chair_id = any($1::uuid[]) and to_date is null`,
    [scope.subtreeIds]
  );
  return [...new Set([scope.personId, ...rows.map((r) => r.id)])];
}

// Returns { sql, params } for the scope predicate, or { empty, reason }.
async function scopePredicate(table, req, params) {
  const spec = TABLES[table];
  const scope = req.scope;
  if (spec.scope === 'reference') return { sql: null };
  if (req.person && req.person.app_role === 'ADMIN') return { sql: null };
  if (!scope || !scope.chairs.length)
    return { empty: true, reason: scopeLib.emptyReason(scope) };

  if (spec.scope === 'subtree') {
    const ids = await subtreePeople(scope);
    params.push(ids);
    return { sql: `id = any($${params.length}::text[])` };
  }

  const cov = await coverageSets(scope.personId);
  if (!cov.clients.length && !cov.zones.length)
    return { empty: true, reason: scopeLib.emptyReason(scope) };

  const cols = await columnsOf(table);
  const parts = [];
  if (cov.clients.length && cols.has('client_id')) {
    params.push(cov.clients);
    parts.push(`client_id = any($${params.length}::text[])`);
  }
  if (cov.zones.length && cols.has('zone_id')) {
    params.push(cov.zones);
    parts.push(`zone_id = any($${params.length}::text[])`);
  }
  if (!parts.length) return { sql: null };
  return { sql: '(' + parts.join(' or ') + ')' };
}

const router = Router({ mergeParams: true });

router.use((req, res, next) => {
  if (!TABLES[req.params.table])
    return res.status(404).json({ error: 'unknown_table', reason: `No table "${req.params.table}" is exposed.` });
  next();
});

router.get('/', async (req, res, next) => {
  try {
    const table = req.params.table;
    const cols = await columnsOf(table);
    const params = [];
    const where = [];

    for (const [k, raw] of Object.entries(req.query)) {
      if (!cols.has(k))
        return res.status(400).json({ error: 'unknown_column', reason: `"${k}" is not a column of ${table}.` });
      const vals = Array.isArray(raw) ? raw : [raw];
      params.push(vals.map(String));
      where.push(`${k}::text = any($${params.length}::text[])`);
    }

    const sc = await scopePredicate(table, req, params);
    if (sc.empty) {
      res.set('X-Crux-Empty-Reason', sc.reason);
      return res.json([]);
    }
    if (sc.sql) where.push(sc.sql);

    const sql = `select * from seam.${table}` + (where.length ? ' where ' + where.join(' and ') : '');
    res.json((await q(sql, params)).rows);
  } catch (e) { next(e); }
});

// Writes reach the underlying table, never the view. Only tables whose mapping
// is one-to-one are writable; the rest say so rather than failing obscurely.
router.post('/', async (req, res, next) => {
  const table = req.params.table;
  const spec = TABLES[table];
  if (!spec.writesTo) return notWritable(table, res);
  try {
    if (table === 'holiday') {
      const b = req.body || {};
      const row = await tx(req.person.id, async (t) => {
        const r = await t.q(
          `insert into holiday (day, name, applies_to, confirmed, source)
           values ($1,$2,$3,coalesce($4,true),'api')
           returning day as date, name, applies_to as scope, confirmed`,
          [b.date, b.name, b.scope || null, b.confirmed]
        );
        await t.audit('CREATE', 'holiday', String(b.date), null, r.rows[0]);
        return r.rows[0];
      });
      return res.json(row);
    }
    return notWritable(table, res);
  } catch (e) { next(e); }
});

router.patch('/:id', async (req, res, next) => {
  const table = req.params.table;
  if (!TABLES[table].writesTo) return notWritable(table, res);
  try {
    if (table === 'holiday') {
      const b = req.body || {};
      const row = await tx(req.person.id, async (t) => {
        const before = (await t.q(`select day as date, name, applies_to as scope, confirmed from holiday where day = $1`, [req.params.id])).rows[0];
        if (!before) return null;
        const r = await t.q(
          `update holiday set name = coalesce($2, name),
                              applies_to = coalesce($3, applies_to),
                              confirmed = coalesce($4, confirmed)
            where day = $1
            returning day as date, name, applies_to as scope, confirmed`,
          [req.params.id, b.name ?? null, b.scope ?? null, b.confirmed ?? null]
        );
        await t.audit('UPDATE', 'holiday', String(req.params.id), before, r.rows[0]);
        return r.rows[0];
      });
      if (!row) return res.status(404).json({ error: 'not_found' });
      return res.json(row);
    }
    return notWritable(table, res);
  } catch (e) { next(e); }
});

router.delete('/:id', async (req, res, next) => {
  const table = req.params.table;
  if (!TABLES[table].writesTo) return notWritable(table, res);
  try {
    if (table === 'holiday') {
      const ok = await tx(req.person.id, async (t) => {
        const before = (await t.q(`select day as date, name, applies_to as scope, confirmed from holiday where day = $1`, [req.params.id])).rows[0];
        if (!before) return false;
        await t.q(`delete from holiday where day = $1`, [req.params.id]);
        await t.audit('DELETE', 'holiday', String(req.params.id), before, null);
        return true;
      });
      if (!ok) return res.status(404).json({ error: 'not_found' });
      return res.json({ ok: true });
    }
    return notWritable(table, res);
  } catch (e) { next(e); }
});

function notWritable(table, res) {
  return res.status(501).json({
    error: 'write_not_mapped',
    reason:
      `${table} is read-only through this endpoint. It is a view over several ` +
      `tables, so a write has to name which one it means. Masters are loaded ` +
      `through Data setup -> Bulk upload (/api/upload), which validates and ` +
      `applies them all-or-nothing.`,
  });
}

module.exports = router;
module.exports.TABLES = TABLES;
