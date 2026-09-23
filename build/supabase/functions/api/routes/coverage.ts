// Coverage and handlers — who covers which client, where.
//
// The design's screen: a location, the clients that have branches there, and
// the handler on each one, with Edit. This is the replacement for assigning
// people through a spreadsheet, which is what the owner asked for: "this
// current challenge that we are facing of assigning people can be managed in
// configuration".
//
// A rule is stored per BRANCH, because that is the only shape coverage_rule's
// own CHECK allows (CLIENT, CLIENT_ZONE, STATE, BRANCH) and it is the shape
// the 1,123 rules already in the tool use. Assigning somebody to a location
// therefore writes one rule per branch of that client at that location, and
// un-assigning end-dates the same set. The screen never shows that: it shows
// the location, the client and the person, which is how the work is actually
// talked about.

import { Router, many, one, tx } from "../shim.ts";
import { requireChair } from "../scope.ts";
const r = Router();

// Operations owns coverage, and an administrator owns everything. Anyone else
// may look and not touch, which is the same rule the matrix screen uses.
function mayAssign(req: any) {
  return req.person && (req.person.app_role === "ADMIN" ||
                        req.scope.clientView === "matrix" ||
                        req.scope.clientView === "full");
}

const ACTIVE_BRANCHES = `
  select b.id, b.op_node_id, b.client_id
    from branch b
    join client c on c.id = b.client_id
   where b.status = 'ACTIVE' and c.status = 'ACTIVE' and b.op_node_id is not null`;

r.get("/", requireChair, async (req: any, res: any) => {
  const rows = await many(
    `with b as (${ACTIVE_BRANCHES}),
     cov as (
       select b.op_node_id, b.client_id, r.person_id, r.product, count(*) as n,
              min(r.effective_from) as from_date
         from coverage_rule r join b on b.id = r.branch_id
        where r.effective_to is null
        group by 1,2,3,4)
     select o.id as location_id, o.name as location, coalesce(z.name,'') as zone,
            c.id as client_id, c.code as client_code, c.name as client,
            (select count(*) from b where b.op_node_id = o.id and b.client_id = c.id) as branches,
            coalesce((
              select jsonb_agg(jsonb_build_object(
                       'person_id', cov.person_id, 'name', p.full_name,
                       'employee_no', p.employee_no, 'chair', ch.title,
                       'product', cov.product, 'branches', cov.n,
                       'from', cov.from_date) order by cov.n desc)
                from cov
                join person p on p.id = cov.person_id
                left join chair_holder h on h.person_id = p.id and h.to_date is null and h.is_primary
                left join chair ch on ch.id = h.chair_id
               where cov.op_node_id = o.id and cov.client_id = c.id), '[]'::jsonb) as handlers
       from op_node o
       left join op_node z on z.id = o.parent_id
       cross join client c
      where o.level = 'LOCATION' and o.active and c.status = 'ACTIVE'
        and exists (select 1 from b where b.op_node_id = o.id and b.client_id = c.id)
      order by o.name, c.name`,
  );
  res.json({ rows, mayAssign: mayAssign(req) });
});

// Everything the Assign dialog needs, so the page never asks the person to
// know an employee number by heart — which is the thing they could not do
// with the spreadsheet.
r.get("/options", requireChair, async (_req: any, res: any) => {
  const [locations, clients, people, products] = await Promise.all([
    many(`select o.id, o.name, coalesce(z.name,'') as zone
            from op_node o left join op_node z on z.id = o.parent_id
           where o.level = 'LOCATION' and o.active order by o.name`),
    many(`select id, code, name from client where status = 'ACTIVE' order by name`),
    many(`select p.id, p.employee_no, p.full_name, ch.title as chair
            from person p
            join chair_holder h on h.person_id = p.id and h.to_date is null
            join chair ch on ch.id = h.chair_id
           where p.employment_status = 'ACTIVE' and p.superseded_by is null
           order by p.full_name`),
    many(`select distinct product from coverage_rule
           where product is not null and btrim(product) <> '' order by 1`),
  ]);
  res.json({ locations, clients, people, products });
});

// Assign. One rule per branch, skipping any this person already covers, so
// pressing it twice is harmless.
r.post("/", requireChair, async (req: any, res: any, next: any) => {
  const { locationId, clientId, personId, product, effectiveFrom, role } = req.body || {};
  try {
    if (!mayAssign(req)) {
      return res.status(403).json({ error: "not_permitted",
        reason: "Operations and the administrator assign coverage." });
    }
    if (!locationId || !clientId || !personId) {
      return res.status(400).json({ error: "incomplete",
        reason: "An assignment names the location, the client and the person." });
    }
    const out = await tx(req.person.id, async (t: any) => {
      const n = (await t.q(
        `insert into coverage_rule
           (person_id, role, scope_type, branch_id, product, effective_from,
            is_assigned_handler, source_ref)
         select $3, coalesce($6,'HANDLER'), 'BRANCH', b.id, nullif(btrim(coalesce($4,'')),''),
                coalesce($5::date, current_date), true, 'Coverage screen'
           from (${ACTIVE_BRANCHES}) b
          where b.op_node_id = $1 and b.client_id = $2
            and not exists (select 1 from coverage_rule r
                             where r.branch_id = b.id and r.person_id = $3
                               and r.effective_to is null)
         returning 1`,
        [locationId, clientId, personId, product || null, effectiveFrom || null, role || null],
      )).rows.length;
      await t.audit("COVERAGE_ASSIGNED", "op_node", locationId, null,
        { clientId, personId, product: product || null, branches: n });
      return n;
    });
    res.status(201).json({ branches: out });
  } catch (e) { next(e); }
});

// Un-assign. The rules are end-dated, never deleted — who covered what last
// month is how a penalty or an escalation is argued about later.
r.post("/end", requireChair, async (req: any, res: any, next: any) => {
  const { locationId, clientId, personId, effectiveTo } = req.body || {};
  try {
    if (!mayAssign(req)) {
      return res.status(403).json({ error: "not_permitted",
        reason: "Operations and the administrator assign coverage." });
    }
    if (!locationId || !clientId || !personId) {
      return res.status(400).json({ error: "incomplete",
        reason: "Name the location, the client and the person to end." });
    }
    const out = await tx(req.person.id, async (t: any) => {
      const n = (await t.q(
        `update coverage_rule r
            set effective_to = coalesce($4::date, current_date)
           from (${ACTIVE_BRANCHES}) b
          where r.branch_id = b.id and b.op_node_id = $1 and b.client_id = $2
            and r.person_id = $3 and r.effective_to is null
         returning 1`,
        [locationId, clientId, personId, effectiveTo || null],
      )).rows.length;
      await t.audit("COVERAGE_ENDED", "op_node", locationId,
        { clientId, personId }, { branches: n });
      return n;
    });
    res.json({ branches: out });
  } catch (e) { next(e); }
});

export default r;
