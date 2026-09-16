// The outbox guard. outbox.body is NOT NULL and two callers used to pass a null
// or an object: the null tripped the constraint after the case had already
// committed, so the work was done and the request still 500'd. These assert
// that a message with nothing to read never reaches the insert.
const assert = require('assert');

const calls = [];
const stub = {
  q: async (sql, params) => { calls.push({ sql, params }); return { rows: [] }; },
  one: async (sql, params) => { calls.push({ sql, params }); return { id: 'OB1' }; },
  many: async () => [],
  tx: async (_a, fn) => fn({ q: stub.q, audit: async () => {} }),
  pool: {},
};
require.cache[require.resolve('../db')] =
  { id: require.resolve('../db'), filename: require.resolve('../db'), loaded: true, exports: stub };

const outbox = require('../outbox');

const msg = (body) => ({
  templateKey: 'ESCALATION_RAISED', recipient: 'Someone@Example.org',
  entityType: 'case', entityId: 'C1', period: 'ESC-1', subject: 's', body,
});

async function main() {
  for (const [label, body] of [['null', null], ['undefined', undefined],
                               ['empty string', ''], ['whitespace', '   '],
                               ['an object', { code: '123456' }]]) {
    calls.length = 0;
    const r = await outbox.enqueue('A1', msg(body));
    assert.strictEqual(r.queued, false, label + ' should not queue');
    assert.strictEqual(r.reason, 'no_body', label + ' should say why');
    assert.strictEqual(calls.length, 0, label + ' must not reach the database');
    console.log('  ok   ' + label + ' is refused before the insert');
  }

  calls.length = 0;
  const ok = await outbox.enqueue('A1', msg('  Something a person can read.  '));
  assert.strictEqual(ok.queued, true);
  assert.strictEqual(calls.length, 1);
  const [, , recipient, , body] = calls[0].params;
  assert.strictEqual(recipient, 'someone@example.org', 'recipient is lower-cased');
  assert.strictEqual(body, 'Something a person can read.', 'body is trimmed, not null');
  console.log('  ok   a real body is queued, trimmed, with the recipient folded');

  // the key is derived, so the same event twice is the same key
  const k1 = (await outbox.enqueue('A1', msg('x'))).key;
  const k2 = (await outbox.enqueue('A1', msg('x'))).key;
  assert.strictEqual(k1, k2, 'same event must derive the same idempotency key');
  console.log('  ok   the same event derives the same idempotency key');

  console.log('all passing');
}
main().catch((e) => { console.error(e); process.exit(1); });
