// Report access, HR, and Joining.
//
// Report access is the design's screen for the thing that is easiest to get
// wrong: what a person sees is mostly INHERITED -- it follows the chair and the
// reporting line -- and only occasionally granted explicitly. The screen shows
// both, separately, because revoking an explicit grant does nothing if the
// chair already carries the same visibility, and somebody has to be able to
// see that.
//
// HR is employee information, satisfaction and performance. No payroll: that
// stays where it is.

import { Router, many, one, tx } from "../shim.ts";
import { requireChair } from "../scope.ts";
const r = Router();

const adminOnly = (req: any) => req.person.app_role === "ADMIN";

r.get("/", requireChair, async (req: any, res: any) => {
  const people = await many(
    `select p.id, p.full_name, p.employee_no, p.department,
            ch.title as chair,
            (select count(*)::int from coverage_rule cr
              where cr.person_id = p.id and cr.effective_to is null) as coverage_rules,
            (select count(*)::int from temp_participant_grant g
              where g.person_id = p.id and g.revoked_at is null
                and (g.expires_at is null or g.expires_at > now())) as grants
       from person p
       left join chair_holder h on h.person_id = p.id and h.to_date is null and h.is_primary
       left join chair ch on ch.id = h.chair_id
      where p.employment_status = 'ACTIVE' and p.superseded_by is null
      order by p.full_name limit 1000`);
  res.json({ people, mayGrant: adminOnly(req) });
});

// /person/:id, not /:id -- a bare parameter at the root would have swallowed
// /joining and matched it as a person id.
r.get("/person/:personId", requireChair, async (req: any, res: any) => {
  const [who, inherited, explicit] = await Promise.all([
    one(`select p.id, p.full_name, p.employee_no, p.department, ch.title as chair,
                m.full_name as manager
           from person p
           left join chair_holder h on h.person_id = p.id and h.to_date is null and h.is_primary
           left join chair ch on ch.id = h.chair_id
           left join person m on m.id = p.manager_id
          where p.id = $1`, [req.params.personId]),
    // what the chair and the reporting line already carry
    many(`select 'Coverage' as via,
                 c.name || ' at ' || coalesce(o.name,'no location') as what,
                 count(*)::int as branches
            from coverage_rule cr
            join branch b on b.id = cr.branch_id
            join client c on c.id = b.client_id
            left join op_node o on o.id = b.op_node_id
           where cr.person_id = $1 and cr.effective_to is null
           group by 1,2
           order by 3 desc limit 100`, [req.params.personId]),
    many(`select g.id, g.reason, g.granted_at, g.expires_at,
                 b.full_name as by
            from temp_participant_grant g
            left join person b on b.id = g.granted_by
           where g.person_id = $1 and g.revoked_at is null
           order by g.granted_at desc`, [req.params.personId]),
  ]);
  if (!who) return res.status(404).json({ error: "not_found" });
  res.json({
    person: who, inherited, explicit, mayGrant: adminOnly(req),
    note: "Inherited access follows the chair and the reporting line and cannot be " +
      "revoked here — change the chair or the coverage instead. Only the explicit " +
      "grants below are revocable on this screen.",
  });
});

r.post("/grant", requireChair, async (req: any, res: any, next: any) => {
  const { personId, reason, expiresAt } = req.body || {};
  try {
    if (!adminOnly(req)) {
      return res.status(403).json({ error: "admin_only",
        reason: "The administrator grants access beyond what a chair carries." });
    }
    if (!personId || !reason || !String(reason).trim()) {
      return res.status(400).json({ error: "reason_required",
        reason: "A grant beyond the chair carries the reason it was given." });
    }
    const out = await tx(req.person.id, async (t: any) => {
      const g = (await t.q(
        `insert into temp_participant_grant (person_id, granted_by, reason, granted_at, expires_at)
         values ($1,$2,$3, now(), $4::timestamptz) returning id, granted_at, expires_at`,
        [personId, req.person.id, String(reason).trim(), expiresAt || null])).rows[0];
      await t.audit("ACCESS_GRANTED", "person", personId, null,
        { reason: String(reason).trim(), expiresAt: expiresAt || null });
      return g;
    });
    res.status(201).json(out);
  } catch (e) { next(e); }
});

r.post("/revoke", requireChair, async (req: any, res: any, next: any) => {
  const { grantId } = req.body || {};
  try {
    if (!adminOnly(req)) {
      return res.status(403).json({ error: "admin_only",
        reason: "The administrator grants and revokes access." });
    }
    const out = await tx(req.person.id, async (t: any) => {
      const g = (await t.q(
        `update temp_participant_grant set revoked_at = now()
          where id = $1 and revoked_at is null returning person_id, reason`,
        [grantId])).rows[0];
      if (!g) throw Object.assign(new Error("not_found"), { status: 404,
        reason: "That grant is already revoked or does not exist." });
      await t.audit("ACCESS_REVOKED", "person", g.person_id, { reason: g.reason }, null);
      return { ok: true };
    });
    res.json(out);
  } catch (e) { next(e); }
});

// ------------------------------------------------------------------- HR
r.get("/hr/overview", requireChair, async (req: any, res: any) => {
  const isHr = req.person.app_role === "ADMIN" ||
               (req.person.department || "") === "Human Resources";
  const [head, depts, types, notes, vacant] = await Promise.all([
    one(`select count(*)::int as people,
                count(*) filter (where employee_type = 'PARTNER')::int as partners,
                count(*) filter (where employee_type <> 'PARTNER')::int as employees,
                count(*) filter (where manager_id is null)::int as no_manager
           from person where employment_status = 'ACTIVE' and superseded_by is null`),
    many(`select coalesce(department,'(not set)') as department, count(*)::int as n
            from person where employment_status = 'ACTIVE' and superseded_by is null
           group by 1 order by 2 desc`),
    many(`select coalesce(employee_type,'(not set)') as kind, count(*)::int as n
            from person where employment_status = 'ACTIVE' and superseded_by is null
           group by 1 order by 2 desc`),
    many(`select coalesce(note_class::text,'UNCLASSIFIED') as note_class, count(*)::int as n
            from person_event where kind = 'NOTE' group by 1 order by 2 desc`),
    one(`select count(*)::int as n from chair ch
          where not exists (select 1 from chair_holder h
                             where h.chair_id = ch.id and h.to_date is null)`),
  ]);
  res.json({
    isHr, head, depts, types, notes, vacantChairs: vacant.n,
    satisfaction: null,
    satisfactionWhy: "Nothing has been surveyed yet, so there is no satisfaction " +
      "figure. A number here without a survey behind it would be a guess.",
    payrollNote: "No payroll. That stays where it is.",
  });
});

// --------------------------------------------------------------- joining
// A joiner is a person_request that HR has approved and the administrator has
// not yet seated, plus anybody seated who has never activated their account.
r.get("/joining", requireChair, async (_req: any, res: any) => {
  const [inflight, unactivated] = await Promise.all([
    many(`select pr.id, pr.full_name, pr.work_email, pr.state, pr.requested_at,
                 pr.due_at, ch.title as chair, rb.full_name as raised_by,
                 hr.full_name as hr_by, pr.hr_at
            from person_request pr
            left join chair ch on ch.id = pr.chair_id
            left join person rb on rb.id = pr.requested_by
            left join person hr on hr.id = pr.hr_by
           where pr.state in ('AWAITING_HR','AWAITING_ADMIN')
           order by pr.due_at nulls last`),
    many(`select p.id, p.full_name, p.work_email, ch.title as chair,
                 (select max(at) from person_event e
                   where e.person_id = p.id and e.kind = 'ACTIVATION_ISSUED') as code_sent
            from person p
            left join chair_holder h on h.person_id = p.id and h.to_date is null and h.is_primary
            left join chair ch on ch.id = h.chair_id
           where p.employment_status = 'ACTIVE' and p.superseded_by is null
             and exists (select 1 from person_event e
                          where e.person_id = p.id and e.kind = 'ACTIVATION_ISSUED')
             and not exists (select 1 from auth_session s
                              where s.person_id = p.id and s.source <> 'ACTIVATION_OTP')
           order by p.full_name limit 200`),
  ]);
  res.json({
    inflight, unactivated,
    steps: ["Raised", "HR approves the chair and terms",
            "Administrator creates the account", "Activation code sent",
            "Signed in for the first time"],
    emptyWhy: inflight.length || unactivated.length ? null :
      "Nobody is joining. A joiner appears here the moment a hire is raised under " +
      "Hiring & pending chairs, and stays until they have signed in once.",
  });
});

export default r;
