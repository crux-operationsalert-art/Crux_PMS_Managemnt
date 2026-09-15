// Query construction for the generic table endpoint. No database: the db
// module is stubbed so we can assert the exact SQL and parameters, which is
// where an injection or a missing scope predicate would show up.
const assert = require('assert');
const path = require('path');

const calls = [];
const stub = {
  q: async (sql, params) => { calls.push({ sql, params }); return { rows: [{ ok: true }] }; },
  many: async (sql, params) => {
    calls.push({ sql, params });
    if (/information_schema/.test(sql)) {
      return [{ column_name: 'id' }, { column_name: 'client_id' }, { column_name: 'zone_id' },
              { column_name: 'period' }, { column_name: 'is_aggregate' }];
    }
    if (/from coverage_rule/.test(sql)) return [{ client_id: 'C1', zone_id: 'Z1' }];
    if (/chair_holder/.test(sql)) return [{ id: 'P2' }];
    return [];
  },
  tx: async (_actor, fn) => fn({ q: stub.q, audit: async () => {} }),
  one: async () => null,
  pool: {},
};
require.cache[require.resolve('../db')] = { id: require.resolve('../db'), filename: require.resolve('../db'), loaded: true, exports: stub };

const router = require('../routes/table');

function run(method, urlPath, { table, query = {}, body = {}, person, scope, id }) {
  return new Promise((resolve) => {
    const req = { method, url: urlPath, params: { table, id }, query, body, person, scope };
    const res = {
      statusCode: 200,
      headers: {},
      status(c) { this.statusCode = c; return this; },
      set(k, v) { this.headers[k] = v; return this; },
      json(payload) { resolve({ status: this.statusCode, payload, headers: this.headers }); },
    };
    router.handle(req, res, (e) => resolve({ status: e ? 500 : 404, payload: e ? { error: e.message } : null, headers: res.headers }));
  });
}

const admin = { id: 'A1', app_role: 'ADMIN' };
const member = { id: 'P1', app_role: 'MEMBER' };
const scopeWithChair = { personId: 'P1', chairs: [{ id: 'CH1' }], subtreeIds: ['CH1'] };
const scopeNoChair = { personId: 'P1', chairs: [], subtreeIds: [] };

(async () => {
  let failures = 0;
  const check = (name, fn) => { try { fn(); console.log('  ok   ' + name); } catch (e) { failures++; console.log('  FAIL ' + name + ' -- ' + e.message); } };

  // 1. unknown table is refused before any SQL runs
  calls.length = 0;
  let r = await run('GET', '/', { table: 'pg_shadow', person: admin, scope: scopeWithChair });
  check('unknown table -> 404, no SQL', () => {
    assert.strictEqual(r.status, 404);
    assert.strictEqual(calls.length, 0);
  });

  // 2. unknown column is refused
  calls.length = 0;
  r = await run('GET', '/', { table: 'business_record', query: { '; drop table person; --': 'x' }, person: admin, scope: scopeWithChair });
  check('unknown column -> 400', () => assert.strictEqual(r.status, 400));

  // 3. filters are parameterised, never interpolated
  calls.length = 0;
  r = await run('GET', '/', { table: 'business_record', query: { period: "2026-09'; drop table person; --" }, person: admin, scope: scopeWithChair });
  check('filter value is a bound parameter', () => {
    const sel = calls.find((c) => /from seam\./.test(c.sql));
    assert.ok(sel, 'a select ran');
    assert.ok(!/drop table/i.test(sel.sql), 'value never reaches the SQL text');
    assert.ok(/period::text = any\(\$1::text\[\]\)/.test(sel.sql), 'uses = any($1)');
    assert.deepStrictEqual(sel.params[0], ["2026-09'; drop table person; --"]);
  });

  // 4. a non-admin gets a scope predicate
  calls.length = 0;
  r = await run('GET', '/', { table: 'business_record', person: member, scope: scopeWithChair });
  check('non-admin read is scoped in the query', () => {
    const sel = calls.find((c) => /from seam\.business_record/.test(c.sql));
    assert.ok(/where /.test(sel.sql), 'has a where clause');
    assert.ok(/client_id = any/.test(sel.sql) || /zone_id = any/.test(sel.sql), 'restricted by coverage');
  });

  // 5. an admin is not scoped
  calls.length = 0;
  r = await run('GET', '/', { table: 'business_record', person: admin, scope: scopeWithChair });
  check('admin read is unscoped', () => {
    const sel = calls.find((c) => /from seam\.business_record/.test(c.sql));
    assert.ok(!/where /.test(sel.sql), 'no where clause');
  });

  // 6. no chair -> empty set and a reason, never another chair's rows (D8)
  calls.length = 0;
  r = await run('GET', '/', { table: 'business_record', person: member, scope: scopeNoChair });
  check('no chair -> [] with a reason, no select', () => {
    assert.deepStrictEqual(r.payload, []);
    assert.ok(r.headers['X-Crux-Empty-Reason'], 'reason header set');
    assert.ok(!calls.some((c) => /from seam\.business_record/.test(c.sql)), 'no row read happened');
  });

  // 7. reference tables are readable without coverage
  calls.length = 0;
  r = await run('GET', '/', { table: 'geo_zone', person: member, scope: scopeNoChair });
  check('reference table readable without coverage', () => {
    assert.ok(Array.isArray(r.payload) === false || r.payload, 'returned rows');
    const sel = calls.find((c) => /from seam\.geo_zone/.test(c.sql));
    assert.ok(sel && !/where /.test(sel.sql), 'unrestricted');
  });

  // 8. a view over several tables refuses writes clearly rather than failing oddly
  r = await run('POST', '/', { table: 'business_record', body: { mtd: 1 }, person: admin, scope: scopeWithChair });
  check('unmapped write -> 501 write_not_mapped', () => {
    assert.strictEqual(r.status, 501);
    assert.strictEqual(r.payload.error, 'write_not_mapped');
  });

  console.log(failures ? `\n${failures} failing` : '\nall passing');
  process.exit(failures ? 1 : 0);
})();
