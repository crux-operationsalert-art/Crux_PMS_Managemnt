// My profile — the design's screen: your details, your tasks, and anything you
// need from another department.
//
// Two things the design is firm about and this keeps. Edits are NOT live: a
// change is raised, HR approves, and only then does the record move; your old
// and new values sit side by side on their task. And the tasks panel is
// whatever is genuinely waiting on YOU, which for most people today is nothing
// -- so it says so rather than inventing a queue.

import { Router, many, one, tx, enqueue } from "../shim.ts";
const r = Router();

r.get("/", async (req: any, res: any) => {
  if (!req.person) return res.status(401).json({ error: "sign_in_required" });
  const me = req.person.id as string;

  const [person, chairs, cover, events, requests, notices, cases] = await Promise.all([
    one(`select p.id, p.full_name, p.work_email, p.mobile, p.employee_no, p.department,
                p.employee_type, p.employment_status, p.app_role,
                d.title as designation, m.full_name as manager, m.employee_no as manager_no
           from person p
           left join designation d on d.id = p.designation_id
           left join person m on m.id = p.manager_id
          where p.id = $1`, [me]),
    many(`select ch.code, ch.title, h.is_primary, h.from_date,
                 par.title as reports_to
            from chair_holder h
            join chair ch on ch.id = h.chair_id
            left join chair par on par.id = ch.parent_id
           where h.person_id = $1 and h.to_date is null
           order by h.is_primary desc, ch.title`, [me]),
    one(`select count(distinct b.id)::int as branches,
                count(distinct b.client_id)::int as clients,
                count(distinct b.op_node_id)::int as locations
           from coverage_rule cr
           join branch b on b.id = cr.branch_id
          where cr.person_id = $1 and cr.effective_to is null`, [me]),
    many(`select at, kind, note, note_class, status
            from person_event where person_id = $1
            order by at desc limit 50`, [me]),
    // what is actually waiting on this person to act
    // $1 and $2 only -- an unreferenced parameter is one Postgres cannot infer a
    // type for, and it answers 42P18 rather than guessing. This had a spare $1.
    many(`select pr.id, pr.full_name, pr.state, pr.due_at, ch.title as chair
            from person_request pr
            left join chair ch on ch.id = pr.chair_id
           where (pr.state = 'AWAITING_HR'
                    and ($1::text = 'Human Resources' or $2::text = 'ADMIN'))
              or (pr.state = 'AWAITING_ADMIN' and $2::text = 'ADMIN')
           order by pr.due_at`, [req.person.department || "", req.person.app_role || ""]),
    many(`select at, kind, text from notification
           where person_id = $1 order by at desc limit 20`, [me]),
    many(`select c.ref, c.status, c.next_chase_at, cat.name as category
            from escalation_party ep
            join "case" c on c.id = ep.case_id
            join category cat on cat.id = c.category_id
           where ep.person_id = $1 and c.status <> 'CLOSED'
           order by c.next_chase_at nulls last limit 20`, [me]),
  ]);

  res.json({
    person, chairs, coverage: cover, events, requests, notices, cases,
    clientView: req.scope ? req.scope.clientView : "none",
    isAdmin: req.scope ? !!req.scope.isAdmin : false,
  });
});

// A change is a request, never a write. It lands as an event on the person, is
// audited, and HR is told -- by notification and by e-mail, because a request
// nobody is told about is the same as no request.
r.post("/change", async (req: any, res: any, next: any) => {
  const { field, was, now: wants, why } = req.body || {};
  try {
    if (!req.person) return res.status(401).json({ error: "sign_in_required" });
    if (!field || !String(wants || "").trim()) {
      return res.status(400).json({ error: "incomplete",
        reason: "Say which detail you want changed and what it should say." });
    }
    const out = await tx(req.person.id, async (t: any) => {
      const note = "Asked for " + field + " to change from " +
        (was && String(was).trim() ? '"' + was + '"' : "(blank)") +
        ' to "' + String(wants).trim() + '"' +
        (why && String(why).trim() ? ". Reason: " + String(why).trim() : ".");
      const e = (await t.q(
        `insert into person_event (person_id, at, kind, note, note_class, actor_id, status)
         values ($1, now(), 'PROFILE_CHANGE_REQUESTED', $2, 'UNCLASSIFIED', $1, 'OPEN')
         returning id, at`, [req.person.id, note])).rows[0];
      await t.q(
        `insert into notification (person_id, at, kind, text)
         select p.id, now(), 'PROFILE_CHANGE_REQUESTED', $1
           from person p
          where p.department = 'Human Resources' and p.employment_status = 'ACTIVE'`,
        [req.person.full_name + " asked for a change to their record. " + note]);
      await t.audit("PROFILE_CHANGE_REQUESTED", "person", req.person.id, { [field]: was ?? null },
        { [field]: String(wants).trim() });
      return { id: e.id, at: e.at, note };
    });

    // HR by e-mail as well, so it is not only a row somebody has to go looking for
    const hr = await one(
      `select work_email from person
        where department = 'Human Resources' and employment_status = 'ACTIVE'
          and coalesce(btrim(work_email),'') <> '' order by full_name limit 1`);
    if (hr) {
      await enqueue(req.person.id, {
        templateKey: "PROFILE_CHANGE", recipient: hr.work_email,
        entityType: "person", entityId: req.person.id,
        subject: "Record change requested by " + req.person.full_name,
        body: [
          req.person.full_name + " (" + (req.person.work_email || "no address") +
            ") has asked for a change to their own record.",
          out.note,
          "Nothing has changed yet. Approve it against their record, and the old and " +
            "new values stay side by side so the change is answerable later.",
        ].join("\n\n"),
      });
    }
    res.status(201).json({ ...out, toldHr: !!hr });
  } catch (e) { next(e); }
});

export default r;
