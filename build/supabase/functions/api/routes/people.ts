// People, chairs, the hiring chain, and the org chart the prototype reads.

import { Router, q, one, many, tx, enqueue, issueActivation } from "../shim.ts";
import { requireChair, emptyReason, mayWriteChair } from "../scope.ts";
const r = Router();

r.get('/me', (req, res) => {
  if (!req.person) return res.status(401).json({ error: 'sign_in_required' });
  res.json({ person: req.person, chairs: req.scope.chairs, primaryChair: req.scope.primaryChair, clientView: req.scope.clientView });
});

// The org chart. chair_status is a view, so the risk badge is never a stored
// number that drifted.
r.get('/org', requireChair, async (req, res) => {
  // ONE ROW PER CHAIR. Both joins below used to multiply: a chair like
  // Executive has 63 primary holders and chair_status yields a row per holder,
  // so the org chart came back with Executive 63 times, Team Leader 9 and
  // Branch Manager 11 -- and the page builds its tree by recursing on every
  // row it is given, so 11 x 9 x 63 nodes were drawn and the browser stopped
  // responding. A shared chair is normal here; the query has to say so.
  const rows = await many(
    `select ch.id, ch.code, ch.title, ch.parent_id,
            hold.person_id, hold.full_name, hold.designation,
            coalesce(st.state, case when hold.headcount > 0 then 'FILLED' else 'DORMANT' end) as state,
            coalesce(st.overdue_days, 0) as overdue_days,
            hold.headcount = 0 as vacant,
            hold.headcount
       from chair ch
       left join lateral (
         select count(*)::int as headcount,
                min(p.id::text)::uuid as person_id,
                case when count(*) = 1 then min(p.full_name)
                     when count(*) > 1 then min(p.full_name) || ' +' || (count(*) - 1)
                end as full_name,
                min(d.title) as designation
           from chair_holder chh
           join person p on p.id = chh.person_id
           left join designation d on d.id = p.designation_id
          where chh.chair_id = ch.id and chh.to_date is null
       ) hold on true
       left join lateral (
         select s.state, s.overdue_days from chair_status s
          where s.chair_id = ch.id
          order by s.overdue_days desc nulls last limit 1
       ) st on true
      order by ch.title`
  );
  res.json({ chairs: rows });
});

r.get('/team', requireChair, async (req, res) => {
  if (!req.scope.subtreeIds.length) return res.json({ team: [] });
  // One row per person, not per chair: a shared chair has many holders and all
  // of them are on the team. An administrator holds no seat, so there is no
  // chair to exclude -- passing null excludes nothing rather than throwing.
  const rows = await many(
    `select ch.id as chair_id, ch.title, p.id as person_id, p.full_name, p.work_email,
            s.state, s.overdue_days
       from chair ch
       join chair_holder chh on chh.chair_id = ch.id and chh.to_date is null
       join person p on p.id = chh.person_id
       left join lateral (
         select s2.state, s2.overdue_days from chair_status s2
          where s2.chair_id = ch.id order by s2.overdue_days desc nulls last limit 1
       ) s on true
      where ch.id = any($1) and ($2::uuid is null or ch.id <> $2::uuid)
      order by ch.title, p.full_name`,
    [req.scope.subtreeIds, req.scope.primaryChair ? req.scope.primaryChair.id : null]
  );
  res.json({ team: rows });
});

// Adding a person: the manager raises it, HR approves the chair and terms, the
// administrator creates the account. Nobody is created by a sign-in.
//
// This is NOT the hire requisition (headcount against a chair, which carries a
// justification and a Finance approval) — that is a separate flow. A person
// request already names the person, so the work e-mail is captured here at
// raise time, not later at seating. The designation is carried by the chair.
r.post('/request', requireChair, async (req, res, next) => {
  const { fullName, workEmail, chairId, managerId, employeeType } = req.body;
  try {
    if (!(await mayWriteChair(req.scope, chairId))) return res.status(403).json({ error: 'out_of_subtree' });
    if (!fullName || !workEmail)
      return res.status(400).json({ error: 'name_and_email_required',
        reason: 'A person request names the person and their work address; HR approves against both.' });

    const out = await tx(req.person.id, async (t) => {
      const pr = (await t.q(
        `insert into person_request
           (full_name, work_email, chair_id, manager_id, requested_by, employee_type, state, due_at)
         values ($1, lower($2), $3, coalesce($4::uuid, $5::uuid), $5::uuid,
                 coalesce($6,'EMPLOYEE'), 'AWAITING_HR', now() + interval '48 hours')
         returning id, due_at, state`,
        [fullName, workEmail, chairId, managerId || null, req.person.id, employeeType || null]
      )).rows[0];
      await t.audit('PERSON_REQUESTED', 'chair', chairId, null,
        { fullName, workEmail: String(workEmail).toLowerCase(), dueAt: pr.due_at });
      return pr;
    });
    res.status(201).json(out);
  } catch (e) { next(e); }
});

// HR approves the chair and the terms. Without this step nothing ever reaches
// the administrator, so the queue's 'Approve chair' action lands here.
r.post('/request/:id/approve', requireChair, async (req, res, next) => {
  try {
    if (req.person.department !== 'Human Resources' && req.person.app_role !== 'ADMIN')
      return res.status(403).json({ error: 'hr_only', reason: 'HR approves the chair and the terms.' });
    const out = await tx(req.person.id, async (t) => {
      const pr = (await t.q(
        `update person_request set state = 'AWAITING_ADMIN', hr_by = $2, hr_at = now()
          where id = $1 and state = 'AWAITING_HR'
          returning id, full_name, chair_id, state`,
        [req.params.id, req.person.id]
      )).rows[0];
      if (!pr) throw Object.assign(new Error('not_awaiting_hr'), { status: 409,
        reason: 'This request is not waiting on HR.' });
      await t.audit('PERSON_REQUEST_HR_APPROVED', 'chair', pr.chair_id, { state: 'AWAITING_HR' },
        { state: 'AWAITING_ADMIN' });
      return pr;
    });
    res.json(out);
  } catch (e) { next(e); }
});

// The administrator creates the account once HR has approved: person row,
// chair_holder row, activation code. The address is the one HR approved on the
// request — it is not re-supplied here, so nobody can seat a different mailbox
// than the one that was reviewed.
r.post('/request/:id/seat', requireChair, async (req, res, next) => {
  try {
    if (req.person.app_role !== 'ADMIN')
      return res.status(403).json({ error: 'admin_only',
        reason: 'HR approves the chair; the administrator creates the account.' });
    const seated = await tx(req.person.id, async (t) => {
      const pr = (await t.q(
        `select * from person_request where id = $1 and state = 'AWAITING_ADMIN' for update`,
        [req.params.id])).rows[0];
      if (!pr) throw Object.assign(new Error('not_approved'), { status: 409,
        reason: 'This request has not been approved by HR yet.' });
      // manager_id carries the reporting line: RLS resolves a manager's subtree
      // through person.manager_id, so a person seated without it sees nobody.
      const p = (await t.q(
        `insert into person (full_name, work_email, manager_id, employee_type, employment_status)
         values ($1, lower($2), $3, $4, 'ACTIVE') returning id`,
        [pr.full_name, pr.work_email, pr.manager_id, pr.employee_type || 'EMPLOYEE']
      )).rows[0];
      await t.q(
        `insert into chair_holder (chair_id, person_id, is_primary, from_date) values ($1,$2,true,current_date)`,
        [pr.chair_id, p.id]
      );
      await t.q(
        `update person_request set state = 'ACTIVE', admin_by = $3, admin_at = now(), person_id = $2
          where id = $1`,
        [pr.id, p.id, req.person.id]);
      await t.audit('PERSON_SEATED', 'chair', pr.chair_id, { state: 'AWAITING_ADMIN' },
        { state: 'ACTIVE', personId: p.id, email: pr.work_email });
      return { personId: p.id, email: String(pr.work_email).toLowerCase() };
    });
    const code = await issueActivation(seated.personId, req.person.id);
    await enqueue(req.person.id, {
      templateKey: 'ACTIVATION', recipient: seated.email,
      entityType: 'person', entityId: seated.personId,
      subject: 'Activate your Crux account',
      // Was `body: { code }`, which reached the person as a JSON blob and put
      // the activation code through JSON.stringify on the way. It is a sentence.
      body: [
        'An account has been created for you on Crux.',
        'Your activation code is ' + code + '. It is valid for 15 minutes.',
        'Open Crux, choose "Activate", and enter the code. If you did not expect this, tell your administrator — the code is single-use and expires on its own.',
      ].join('\n\n'),
    });
    res.status(201).json({ personId: seated.personId });
  } catch (e) { next(e); }
});

// Notes on a person. The 449 rescued notes live here too, and a note is
// classified before it can feed an Attribute score.
r.post('/:personId/note', requireChair, async (req, res, next) => {
  const { kind, note, noteClass } = req.body;
  try {
    const out = await tx(req.person.id, async (t) => {
      const e = (await t.q(
        `insert into person_event (person_id, at, kind, note, note_class, actor_id)
         values ($1, now(), $2, $3, coalesce($4::note_class,'UNCLASSIFIED'), $5) returning id`,
        [req.params.personId, kind || 'NOTE', note, noteClass || null, req.person.id]
      )).rows[0];
      await t.audit('PERSON_NOTE_ADDED', 'person', req.params.personId, null, { kind, noteClass });
      return e;
    });
    res.status(201).json(out);
  } catch (e) { next(e); }
});

// Moving a chair. The design's structure screen lets you drag a chair onto a
// new parent; this is the write behind it. A chair cannot be moved under
// itself or under anything beneath it, because that would cut the branch off
// from the tree entirely -- the recursive walk below is what proves it.
r.post('/chair/:id/move', requireChair, async (req, res, next) => {
  const { parentId } = req.body || {};
  try {
    if (req.person.app_role !== 'ADMIN' && !(await mayWriteChair(req.scope, req.params.id)))
      return res.status(403).json({ error: 'out_of_subtree',
        reason: 'You may only move chairs at or below your own.' });

    const out = await tx(req.person.id, async (t) => {
      const me = (await t.q(
        `select id, code, title, parent_id from chair where id = $1`, [req.params.id])).rows[0];
      if (!me) throw Object.assign(new Error('no_such_chair'), { status: 404 });

      if (parentId) {
        const up = (await t.q(
          `with recursive t as (
              select id from chair where id = $1
              union all
              select c.id from chair c join t on c.parent_id = t.id)
            select 1 from t where id = $2`, [req.params.id, parentId])).rows.length;
        if (up) throw Object.assign(new Error('would_make_a_loop'), { status: 409,
          reason: 'That chair sits underneath this one. Moving it there would cut the branch off the tree.' });
        const p = (await t.q(`select id, title from chair where id = $1`, [parentId])).rows[0];
        if (!p) throw Object.assign(new Error('no_such_parent'), { status: 404 });
      }

      const was = (await t.q(
        `select title from chair where id = $1`, [me.parent_id])).rows[0];
      await t.q(`update chair set parent_id = $2 where id = $1`,
        [req.params.id, parentId || null]);
      const now = (await t.q(
        `select title from chair where id = $1`, [parentId || null])).rows[0];

      await t.audit('CHAIR_MOVED', 'chair', me.code,
        { parent: was ? was.title : null }, { parent: now ? now.title : null });
      return { id: me.id, title: me.title,
               from: was ? was.title : null, to: now ? now.title : null };
    });
    res.json(out);
  } catch (e) { next(e); }
});

export default r;
