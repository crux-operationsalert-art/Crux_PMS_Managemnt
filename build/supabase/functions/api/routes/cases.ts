// Escalations. What a person may do on a case comes from escalation_party and
// escalation_action — the part they play, not their app role — so the action
// set the UI renders is generated, not hard-coded.

import { Router, q, one, many, tx, enqueue, issueActivation } from "../shim.ts";
import { requireChair, emptyReason, mayWriteChair } from "../scope.ts";
const r = Router();

r.get('/', requireChair, async (req, res) => {
  const branches = await req.scope.branches();
  if (!branches.length) return res.json({ cases: [], empty: emptyReason(req.scope) });
  const ids = branches.map((b) => b.id);
  const cases = await many(
    `select c.id, c.ref, c.status, c.strike_count, c.last_activity_at, c.next_chase_at, c.auto_close_at,
            cl.name as client, b.name as branch, cat.name as category, d.name as desk,
            rp.full_name as raised_by
       from "case" c
       join client cl on cl.id = c.client_id
       left join branch b on b.id = c.branch_id
       join category cat on cat.id = c.category_id
       left join desk d on d.id = c.desk_id
       join person rp on rp.id = c.raised_by
      where (c.branch_id = any($1) or (c.branch_id is null and c.client_id in (select distinct client_id from branch where id = any($1))))
      order by (c.status <> 'CLOSED') desc, c.last_activity_at desc
      limit 200`,
    [ids]
  );
  res.json({ cases });
});

r.get('/:id', requireChair, async (req, res) => {
  const c = await one(`select * from "case" where id = $1`, [req.params.id]);
  if (!c) return res.status(404).json({ error: 'not_found' });
  const branches = await req.scope.branches();
  if (c.branch_id && !branches.some((b) => b.id === c.branch_id))
    return res.status(403).json({ error: 'out_of_scope', reason: 'This case belongs to a branch outside your coverage.' });

  const [events, parties, actions] = await Promise.all([
    many(`select at, kind, note, actor_id from case_event where case_id = $1 order by at`, [c.id]),
    many(`select ep.part, p.full_name, p.id from escalation_party ep join person p on p.id = ep.person_id where ep.case_id = $1`, [c.id]),
    many(
      `select a.code, a.label, a.needs_note
         from escalation_action a
         join escalation_party ep on ep.part = any(a.allowed_parts)
        where ep.case_id = $1 and ep.person_id = $2
          and (a.valid_statuses is null or $3 = any(a.valid_statuses))`,
      [c.id, req.person.id, c.status]
    ),
  ]);
  res.json({ case: c, events, parties, actions });
});

// Raising: 4 types. The category decides who hears first; the level order is
// fixed. next_chase_at is scheduled here and never swept for (rule R-03).
r.post('/', requireChair, async (req, res, next) => {
  const { clientId, branchId, categoryId, againstPersonId, againstText, description, kind } = req.body;
  try {
    const out = await tx(req.person.id, async (t) => {
      const cat = await t.q(`select name, desk_id, chase_hours, pinned from category where id = $1 and active`, [categoryId]);
      if (!cat.rows.length) throw Object.assign(new Error('bad_category'), { status: 400 });
      const chaseHours = cat.rows[0].chase_hours ?? Number(Deno.env.get("CHASE_HOURS") || 24);

      // next_ref locks a counter row: two people raising at the same moment
      // cannot be handed the same reference, and a differently-shaped ref
      // elsewhere in the table cannot break the sequence.
      const ref = (await t.q(`select next_ref('ESC') as ref`)).rows[0].ref;
      const c = (await t.q(
        `insert into "case" (ref, client_id, branch_id, category_id, raised_by, against_person_id, against_text,
                             description, desk_id, status, next_chase_at, last_activity_at)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,'OPEN', working_hours_after(now(), $10), now())
         returning id, ref, next_chase_at`,
        [ref, clientId, branchId || null, categoryId, req.person.id, againstPersonId || null,
         againstText || null, description, cat.rows[0].desk_id, chaseHours]
      )).rows[0];

      await t.q(`insert into case_event (case_id, at, kind, actor_id, note) values ($1, now(), $2, $3, $4)`,
        [c.id, 'RAISED', req.person.id, kind || 'ESCALATION']);
      await t.q(`insert into escalation_party (case_id, person_id, part) values ($1,$2,'RAISER')`,
        [c.id, req.person.id]);
      await t.audit('CASE_RAISED', 'case', c.ref, null, { category: cat.rows[0].name, branchId: branchId || null });
      return c;
    });

    // level-1 notice, once, keyed to the case — a retry cannot duplicate it.
    // The body is written here rather than pulled from a template table: the
    // recipient is a client's level-1 contact, and the first thing they should
    // read is which branch, what was raised and by when.
    const l1 = await one(
      `select m.email, b.name as branch, b.code, cl.name as client, cat.name as category
         from branch_effective_matrix m
         join branch b on b.id = m.branch_id
         join client cl on cl.id = b.client_id
         cross join lateral (select name from category where id = $2) cat
        where m.branch_id = $1 and m.level = 1 and coalesce(btrim(m.email),'') <> ''`,
      [branchId, categoryId]
    );
    if (l1) await enqueue(req.person.id, {
      templateKey: 'ESCALATION_RAISED', recipient: l1.email,
      entityType: 'case', entityId: out.id, period: out.ref,
      subject: out.ref + ' · ' + l1.category + ' · ' + l1.branch,
      body: [
        out.ref + ' has been raised against ' + l1.branch + ' (' + l1.code + '), ' + l1.client + '.',
        'Category: ' + l1.category,
        description || '(no description was given)',
        'A reply is expected by ' + new Date(out.next_chase_at).toISOString().slice(0, 16).replace('T', ' ') +
        '. If nothing is heard by then this is chased again and the desk is added.',
        'Raised by ' + req.person.full_name + ' (' + req.person.work_email + ').',
      ].join('\n\n'),
    });
    res.status(201).json(out);
  } catch (e) { next(e); }
});

// Acting on a case. The action must be one the caller's part allows; the check
// is the same query the UI used to render the buttons.
r.post('/:id/action', requireChair, async (req, res, next) => {
  const { code, note } = req.body;
  try {
    const out = await tx(req.person.id, async (t) => {
      const allowed = (await t.q(
        `select a.* from escalation_action a
           join escalation_party ep on ep.part = any(a.allowed_parts)
          where ep.case_id = $1 and ep.person_id = $2 and a.code = $3`,
        [req.params.id, req.person.id, code]
      )).rows[0];
      if (!allowed) throw Object.assign(new Error('not_your_action'), { status: 403 });
      if (allowed.needs_note && !note) throw Object.assign(new Error('note_required'), { status: 400 });

      const c = (await t.q(`select ref, status from "case" where id = $1 for update`, [req.params.id])).rows[0];
      const next_status = allowed.sets_status || c.status;
      // R-05: auto-close is scheduled at resolution time, so changing the
      // setting later never moves a window somebody is already inside.
      // It was written here as a literal 7 days while auto_close_days sat in
      // app_setting being read by nothing - an administrator could have
      // changed it and watched nothing happen.
      const closeDays = Number(
        (await t.q(`select value from app_setting where key = 'auto_close_days'`)).rows[0]?.value
      ) || 7;
      await t.q(
        `update "case" set status = $2, last_activity_at = now(),
                resolution_note = coalesce($3, resolution_note),
                resolved_at = case when $2 = 'RESOLVED' then now() else resolved_at end,
                auto_close_at = case when $2 = 'RESOLVED'
                                     then now() + make_interval(days => $4::int)
                                     else auto_close_at end
          where id = $1`,
        [req.params.id, next_status, next_status === 'RESOLVED' ? note : null, closeDays]
      );
      await t.q(`insert into case_event (case_id, at, kind, actor_id, note) values ($1, now(), $2, $3, $4)`,
        [req.params.id, code, req.person.id, note || null]);
      await t.q(`insert into escalation_action_log (case_id, action_code, actor_id, at, note) values ($1,$2,$3,now(),$4)`,
        [req.params.id, code, req.person.id, note || null]);
      await t.audit('CASE_' + code, 'case', c.ref, { status: c.status }, { status: next_status });
      return { ref: c.ref, status: next_status };
    });
    res.json(out);
  } catch (e) { next(e); }
});

export default r;
