// Visits & claims, and the Ideathon — the three things a person raises from
// the field rather than reads.
//
// All three tables exist and are empty, so every one of these screens starts
// at zero. That is not the same as not working: the write path is the whole
// point, and the first row comes from the screen. A claim walks
// DRAFT -> OPS_APPROVAL -> HR_APPROVAL -> ACCOUNTS -> PAID, and the database
// refuses PAID without a payment reference and DISPUTED without a reason, so
// the stage a claim is at is always answerable.

import { Router, many, one, tx } from "../shim.ts";
import { requireChair } from "../scope.ts";
const r = Router();

const CLAIM_FLOW = ["DRAFT", "OPS_APPROVAL", "HR_APPROVAL", "ACCOUNTS", "PAID"];

// Who may move a claim on at each stage. Finance pays, HR checks the person,
// Operations checks the visit actually happened.
function mayAdvance(req: any, stage: string) {
  const d = req.person.department || "";
  if (req.person.app_role === "ADMIN") return true;
  if (stage === "OPS_APPROVAL") return d === "Operations";
  if (stage === "HR_APPROVAL") return d === "Human Resources";
  if (stage === "ACCOUNTS") return d === "Finance & Accounts";
  return false;
}

r.get("/", requireChair, async (req: any, res: any) => {
  const mine = !req.scope.isAdmin;
  const [visits, claims, branches] = await Promise.all([
    many(`select v.id, v.visited_on, v.purpose, v.answers,
                 b.name as branch, b.code as branch_code, c.name as client,
                 p.full_name as who
            from visit v
            left join branch b on b.id = v.branch_id
            left join client c on c.id = v.client_id
            join person p on p.id = v.person_id
           where ($1::uuid is null or v.person_id = $1)
           order by v.visited_on desc, v.created_at desc limit 200`,
         [mine ? req.person.id : null]),
    many(`select cl.id, cl.ref, cl.amount, cl.stage::text as stage, cl.paid_ref,
                 cl.dispute_reason, cl.created_at,
                 p.full_name as who, v.visited_on, b.name as branch
            from claim cl
            join person p on p.id = cl.person_id
            left join visit v on v.id = cl.visit_id
            left join branch b on b.id = v.branch_id
           where ($1::uuid is null or cl.person_id = $1)
           order by cl.created_at desc limit 200`,
         [mine ? req.person.id : null]),
    // only what this person may actually visit
    many(`select distinct b.id, b.code, b.name, c.name as client
            from branch b join client c on c.id = b.client_id
           where b.status = 'ACTIVE' and c.status = 'ACTIVE'
             and ($1::uuid is null or exists (
                   select 1 from coverage_rule cr
                    where cr.branch_id = b.id and cr.person_id = $1
                      and cr.effective_to is null))
           order by c.name, b.name limit 500`,
         [mine ? req.person.id : null]),
  ]);
  res.json({
    visits, claims, branches, flow: CLAIM_FLOW, mine,
    canAct: {
      OPS_APPROVAL: mayAdvance(req, "OPS_APPROVAL"),
      HR_APPROVAL: mayAdvance(req, "HR_APPROVAL"),
      ACCOUNTS: mayAdvance(req, "ACCOUNTS"),
    },
  });
});

// A visit writes back into the branch record: it is the thing that moves the
// last-seen date and updates the contact it met.
r.post("/visit", requireChair, async (req: any, res: any, next: any) => {
  const { branchId, visitedOn, purpose, met, metMobile, metEmail, note } = req.body || {};
  try {
    if (!branchId || !purpose) {
      return res.status(400).json({ error: "incomplete",
        reason: "A visit names the branch and why you went." });
    }
    const out = await tx(req.person.id, async (t: any) => {
      const b = (await t.q(`select id, code, client_id from branch where id = $1`,
                           [branchId])).rows[0];
      if (!b) throw Object.assign(new Error("no_such_branch"), { status: 404 });

      const v = (await t.q(
        `insert into visit (person_id, visited_on, branch_id, client_id, purpose, answers)
         values ($1, coalesce($2::date, current_date), $3, $4, $5, $6::jsonb)
         returning id, visited_on`,
        [req.person.id, visitedOn || null, b.id, b.client_id, purpose,
         JSON.stringify({ met: met || null, note: note || null })])).rows[0];

      // met somebody new -> the branch's point of contact is updated, which is
      // what the design means by "a visit writes back into this record"
      if (met && String(met).trim()) {
        await t.q(`update branch_contact set active = false
                    where branch_id = $1 and role = 'CRUX_POC' and active`, [b.id]);
        await t.q(
          `insert into branch_contact (branch_id, role, name, mobile, email, active)
           values ($1,'CRUX_POC',$2,$3,$4,true)`,
          [b.id, String(met).trim(), metMobile || null, metEmail || null]);
      }
      await t.audit("VISIT_LOGGED", "branch", b.code, null,
        { visitedOn: v.visited_on, purpose, met: met || null });
      return v;
    });
    res.status(201).json(out);
  } catch (e) { next(e); }
});

r.post("/claim", requireChair, async (req: any, res: any, next: any) => {
  const { visitId, amount } = req.body || {};
  try {
    if (!amount || Number(amount) <= 0) {
      return res.status(400).json({ error: "amount_required",
        reason: "A claim carries the amount being claimed." });
    }
    const out = await tx(req.person.id, async (t: any) => {
      const ref = (await t.q(`select next_ref('CLM') as ref`)).rows[0].ref;
      const c = (await t.q(
        `insert into claim (ref, visit_id, person_id, amount, stage)
         values ($1, $2, $3, $4, 'OPS_APPROVAL')
         returning id, ref, amount, stage::text as stage`,
        [ref, visitId || null, req.person.id, amount])).rows[0];
      await t.audit("CLAIM_RAISED", "claim", c.ref, null,
        { amount: c.amount, visitId: visitId || null });
      return c;
    });
    res.status(201).json(out);
  } catch (e) { next(e); }
});

// One step at a time, in the order the flow declares. Paying needs a reference
// and disputing needs a reason -- the database enforces both, so this only has
// to ask for them.
r.post("/claim/:id/advance", requireChair, async (req: any, res: any, next: any) => {
  const { to, paidRef, disputeReason } = req.body || {};
  try {
    const out = await tx(req.person.id, async (t: any) => {
      const c = (await t.q(
        `select id, ref, stage::text as stage from claim where id = $1 for update`,
        [req.params.id])).rows[0];
      if (!c) throw Object.assign(new Error("not_found"), { status: 404 });
      if (!mayAdvance(req, c.stage)) {
        throw Object.assign(new Error("not_your_step"), { status: 403,
          reason: "This claim is with " + c.stage.toLowerCase().replace("_", " ") +
            ". Only that desk moves it on." });
      }
      const want = to || CLAIM_FLOW[CLAIM_FLOW.indexOf(c.stage) + 1];
      if (!want) throw Object.assign(new Error("already_finished"), { status: 409 });
      if (want === "PAID" && !paidRef) {
        throw Object.assign(new Error("paid_ref_required"), { status: 400,
          reason: "Paying a claim records the payment reference." });
      }
      if (want === "DISPUTED" && !disputeReason) {
        throw Object.assign(new Error("reason_required"), { status: 400,
          reason: "A dispute carries the reason the person argues against." });
      }
      const stamp = c.stage === "OPS_APPROVAL" ? "ops" :
                    c.stage === "HR_APPROVAL" ? "hr" :
                    c.stage === "ACCOUNTS" ? "accounts" : null;
      const after = (await t.q(
        `update claim set stage = $2::claim_stage,
                paid_ref = coalesce($3, paid_ref),
                dispute_reason = coalesce($4, dispute_reason)` +
         (stamp ? `, ${stamp}_by = $5, ${stamp}_at = now()` : ``) +
        ` where id = $1 returning ref, stage::text as stage`,
        stamp ? [c.id, want, paidRef || null, disputeReason || null, req.person.id]
              : [c.id, want, paidRef || null, disputeReason || null])).rows[0];
      await t.audit("CLAIM_" + want, "claim", c.ref, { stage: c.stage }, { stage: want });
      return after;
    });
    res.json(out);
  } catch (e) { next(e); }
});

// --------------------------------------------------------------- ideathon
r.get("/ideas", requireChair, async (_req: any, res: any) => {
  const ideas = await many(
    `select i.id, i.ref, i.title, i.body, i.stage::text as stage, i.owner_dept,
            i.charter, i.decision_reason, i.decided_at, i.created_at,
            p.full_name as raised_by, s.full_name as sponsor
       from idea i
       join person p on p.id = i.raised_by
       left join person s on s.id = i.sponsor_id
      order by i.created_at desc limit 200`);
  res.json({ ideas,
    stages: ["SUBMITTED","IN_REVIEW","ACCEPTED","INITIATED","ON_HOLD","REJECTED","DELIVERED"] });
});

r.post("/idea", requireChair, async (req: any, res: any, next: any) => {
  const { title, body, ownerDept } = req.body || {};
  try {
    if (!title || !String(title).trim()) {
      return res.status(400).json({ error: "title_required",
        reason: "An idea needs a line somebody else can recognise it by." });
    }
    const out = await tx(req.person.id, async (t: any) => {
      const ref = (await t.q(`select next_ref('IDA') as ref`)).rows[0].ref;
      const i = (await t.q(
        `insert into idea (ref, title, body, raised_by, owner_dept, stage)
         values ($1,$2,$3,$4,$5,'SUBMITTED') returning id, ref, title, stage::text as stage`,
        [ref, String(title).trim(), body || null, req.person.id, ownerDept || null])).rows[0];
      await t.audit("IDEA_RAISED", "idea", i.ref, null, { title: i.title });
      return i;
    });
    res.status(201).json(out);
  } catch (e) { next(e); }
});

// Business Excellence drives the Ideathon, so it and the administrator decide.
r.post("/idea/:id/decide", requireChair, async (req: any, res: any, next: any) => {
  const { stage, reason, charter } = req.body || {};
  try {
    const mayDecide = req.person.app_role === "ADMIN" ||
      (req.person.department || "").indexOf("Business Excellence") >= 0;
    if (!mayDecide) {
      return res.status(403).json({ error: "not_permitted",
        reason: "Business Excellence drives the Ideathon and decides on ideas." });
    }
    if (["REJECTED", "ON_HOLD"].includes(stage) && !reason) {
      return res.status(400).json({ error: "reason_required",
        reason: "Holding or rejecting an idea carries the reason, so the person who raised it knows why." });
    }
    const out = await tx(req.person.id, async (t: any) => {
      const before = (await t.q(`select ref, stage::text as stage from idea where id = $1`,
                                [req.params.id])).rows[0];
      if (!before) throw Object.assign(new Error("not_found"), { status: 404 });
      const after = (await t.q(
        `update idea set stage = $2::idea_stage,
                decision_reason = coalesce($3, decision_reason),
                charter = coalesce($4, charter),
                sponsor_id = coalesce(sponsor_id, $5),
                decided_by = $5, decided_at = now()
          where id = $1 returning ref, stage::text as stage`,
        [req.params.id, stage, reason || null, charter || null, req.person.id])).rows[0];
      await t.audit("IDEA_" + stage, "idea", before.ref,
        { stage: before.stage }, { stage, reason: reason || null });
      return after;
    });
    res.json(out);
  } catch (e) { next(e); }
});

export default r;
