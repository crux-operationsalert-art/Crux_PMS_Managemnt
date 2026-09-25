// =====================================================================
// Places -- the operating grouping, the cities that answer to it, and who
// handles which client where. One screen, because they are one question.
//
// Before this, the grouping was edited on Configuration, coverage was a
// separate screen, and the alignment between a city and an operating zone
// was not shown anywhere at all -- which is how a rate for "Kolkata" came
// to price a different place from the branch for "Kolkata".
//
// Everything here is read by op_places() in one go and written through
// SECURITY DEFINER functions that do their own permission check, so the
// rule about who may change the grouping lives in one place rather than
// being restated in the route and drifting.
// =====================================================================
import { Router, one } from "../shim.ts";
import { requireChair } from "../scope.ts";
const r = Router();

// Looking is a chair's right; changing the grouping is the administrator's.
// The screen is told which it is so it can render the difference rather than
// offering a button that will be refused.
function mayEdit(req: any) {
  return req.person.app_role === "ADMIN";
}
// Coverage has its own owner: Operations assigns handlers, the administrator
// may do anything. Same test the coverage screen used.
function mayAssign(req: any) {
  return req.person.app_role === "ADMIN" ||
         req.scope.clientView === "matrix" || req.scope.clientView === "full";
}

r.get("/", requireChair, async (req: any, res: any) => {
  const d = await one(`select op_places() as d`);
  const out = d?.d ?? {};
  res.json({
    ...out,
    mayEdit: mayEdit(req),
    mayAssign: mayAssign(req),
    emptyWhy:
      "The operating grouping is empty, so nothing can be placed. Load Geography " +
      "under Data setup, or add a group and its zones here.",
  });
});

// ------------------------------------------------------------- grouping
// Add, rename, or MOVE. The move is the reason this screen exists: op_save
// used to accept a parent on an edit and ignore it.
r.post("/node", requireChair, async (req: any, res: any, next: any) => {
  const { id, name, parentId, active } = req.body || {};
  try {
    const out = (await one(`select op_save($1,$2,$3,$4,$5) as r`,
      [req.person.id, name ?? null, id ?? null, parentId ?? null,
       typeof active === "boolean" ? active : null]))?.r;
    if (out?.error) return res.status(out.error === "not_admin" ? 403 : 400).json(out);
    res.json(out);
  } catch (e) { next(e); }
});

r.post("/node/retire", requireChair, async (req: any, res: any, next: any) => {
  const { id, active } = req.body || {};
  try {
    const out = (await one(`select op_retire($1,$2,$3) as r`,
      [req.person.id, id ?? null, active === true]))?.r;
    if (out?.error) return res.status(out.error === "not_admin" ? 403 : 400).json(out);
    res.json(out);
  } catch (e) { next(e); }
});

// ---------------------------------------------------------------- cities
// A city answers to an operating zone. Sent as the node's id, never as typed
// text, so geo_node.op_zone can only ever name something that exists.
r.post("/city", requireChair, async (req: any, res: any, next: any) => {
  const { cityId, placeId } = req.body || {};
  try {
    const out = (await one(`select op_city_align($1,$2,$3) as r`,
      [req.person.id, cityId ?? null, placeId ?? null]))?.r;
    if (out?.error) return res.status(out.error === "not_admin" ? 403 : 400).json(out);
    res.json(out);
  } catch (e) { next(e); }
});

// --------------------------------------------------------------- aliases
// What a spelling in a file means. A row, not a deploy.
r.post("/alias", requireChair, async (req: any, res: any, next: any) => {
  const { writtenAs, means, note } = req.body || {};
  try {
    const out = (await one(`select op_alias_save($1,$2,$3,$4) as r`,
      [req.person.id, writtenAs ?? null, means ?? null, note ?? null]))?.r;
    if (out?.error) return res.status(out.error === "not_admin" ? 403 : 400).json(out);
    res.json(out);
  } catch (e) { next(e); }
});

r.post("/alias/remove", requireChair, async (req: any, res: any, next: any) => {
  const { writtenAs } = req.body || {};
  try {
    const out = (await one(`select op_alias_remove($1,$2) as r`,
      [req.person.id, writtenAs ?? null]))?.r;
    if (out?.error) return res.status(out.error === "not_admin" ? 403 : 400).json(out);
    res.json(out);
  } catch (e) { next(e); }
});

// -------------------------------------------------------------- handlers
// The options the Assign box needs, so nobody has to hold an employee number
// in their head -- which is the thing the spreadsheet could not do.
r.get("/handlers", requireChair, async (_req: any, res: any) => {
  const d = await one(
    `select jsonb_build_object(
       'people', coalesce((
         select jsonb_agg(jsonb_build_object('id', p.id, 'employeeNo', p.employee_no,
                  'name', p.full_name, 'chair', ch.title) order by p.full_name)
           from person p
           join chair_holder h on h.person_id = p.id and h.to_date is null
           join chair ch on ch.id = h.chair_id
          where p.employment_status = 'ACTIVE' and p.superseded_by is null), '[]'::jsonb),
       'products', coalesce((
         select jsonb_agg(distinct product) from coverage_rule
          where product is not null and btrim(product) <> ''), '[]'::jsonb)
     ) as d`);
  res.json(d?.d ?? { people: [], products: [] });
});

// Assign. One rule per branch, skipping any this person already covers, so
// pressing it twice is harmless.
const ACTIVE_BRANCHES = `
  select b.id, b.op_node_id, b.client_id
    from branch b join client c on c.id = b.client_id
   where b.status = 'ACTIVE' and c.status = 'ACTIVE' and b.op_node_id is not null`;

r.post("/coverage", requireChair, async (req: any, res: any, next: any) => {
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
    const n = (await one(
      `with ins as (
         insert into coverage_rule
           (person_id, role, scope_type, branch_id, product, effective_from,
            is_assigned_handler, source_ref)
         select $3, coalesce($6,'HANDLER'), 'BRANCH', b.id,
                nullif(btrim(coalesce($4,'')),''),
                coalesce($5::date, current_date), true, 'Places screen'
           from (${ACTIVE_BRANCHES}) b
          where b.op_node_id = $1 and b.client_id = $2
            and not exists (select 1 from coverage_rule r
                             where r.branch_id = b.id and r.person_id = $3
                               and r.effective_to is null)
         returning 1)
       select count(*)::int as n from ins`,
      [locationId, clientId, personId, product || null, effectiveFrom || null, role || null],
    ))?.n ?? 0;
    await one(
      `insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
       values ($1,'COVERAGE_ASSIGNED','op_node',$2,$3) returning 1`,
      [req.person.id, String(locationId),
       JSON.stringify({ clientId, personId, product: product || null, branches: n })]);
    res.status(201).json({ branches: n,
      note: n ? null : "Everyone named already covers every branch of that client there." });
  } catch (e) { next(e); }
});

// Un-assign. The rules are end-dated, never deleted -- who covered what last
// month is how a penalty or an escalation is argued about later.
r.post("/coverage/end", requireChair, async (req: any, res: any, next: any) => {
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
    const n = (await one(
      `with upd as (
         update coverage_rule r
            set effective_to = coalesce($4::date, current_date)
           from (${ACTIVE_BRANCHES}) b
          where r.branch_id = b.id and b.op_node_id = $1 and b.client_id = $2
            and r.person_id = $3 and r.effective_to is null
         returning 1)
       select count(*)::int as n from upd`,
      [locationId, clientId, personId, effectiveTo || null],
    ))?.n ?? 0;
    await one(
      `insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
       values ($1,'COVERAGE_ENDED','op_node',$2,$3,$4) returning 1`,
      [req.person.id, String(locationId),
       JSON.stringify({ clientId, personId }), JSON.stringify({ branches: n })]);
    res.json({ branches: n });
  } catch (e) { next(e); }
});

export default r;
