// =====================================================================
// Places, coverage & owners -- one screen for where the work is, who runs
// it, who handles which client there, what it is priced at, which cities
// answer to it, and what a file may call it.
//
// Before this the same question was asked on three screens and none of
// them showed the answer: the grouping was edited on Settings and could
// not be MOVED, coverage was its own page, and the link between a city
// and an operating zone was shown nowhere at all -- which is how a rate
// for "Kolkata" came to price a different place from the branch for
// "Kolkata".
//
// The read is split: op_places() is the tree and its counts, op_place()
// is one place opened, and op_branches() is a search -- because Mumbai
// has 1,665 branches and a list of those is not a page.
//
// Every write goes through a SECURITY DEFINER function that does its own
// permission check, so the rule about who may change what lives in one
// place rather than being restated here and drifting.
// =====================================================================
import { Router, one } from "../shim.ts";
import { requireChair } from "../scope.ts";
const r = Router();

// Looking is a chair's right; changing the grouping is the administrator's.
// The screen is told which, so it renders the difference rather than offering
// a button that will be refused.
const mayEdit = (req: any) => req.person.app_role === "ADMIN";
const mayAssign = (req: any) =>
  req.person.app_role === "ADMIN" ||
  req.scope.clientView === "matrix" || req.scope.clientView === "full";
const mayPrice = (req: any) =>
  req.person.app_role === "ADMIN" ||
  (req.person.department || "") === "Finance & Accounts";

// A refusal from one of the functions carries its own reason; 403 when it is
// about who you are, 400 when it is about what you asked for.
function out(res: any, o: any) {
  if (o?.error) {
    return res.status(o.error === "not_admin" || o.error === "not_permitted" ? 403 : 400).json(o);
  }
  return res.json(o);
}

// ------------------------------------------------------------------ read
r.get("/", requireChair, async (req: any, res: any) => {
  const d = await one(`select op_places() as d`);
  res.json({
    ...(d?.d ?? {}),
    mayEdit: mayEdit(req), mayAssign: mayAssign(req), mayPrice: mayPrice(req),
    emptyWhy: "The operating grouping is empty, so nothing can be placed. Load " +
      "Geography under Data setup, or add a group and its zones here.",
  });
});

r.get("/options", requireChair, async (_req: any, res: any) => {
  const d = await one(`select op_options() as d`);
  res.json(d?.d ?? {});
});

r.get("/place/:id", requireChair, async (req: any, res: any) => {
  const d = await one(`select op_place($1) as d`, [req.params.id]);
  if (!d?.d?.id) return res.status(404).json({ error: "no_such_place" });
  res.json(d.d);
});

r.get("/branches", requireChair, async (req: any, res: any) => {
  const d = await one(`select op_branches($1,$2,$3,$4) as d`, [
    req.query.get("node"), req.query.get("client") || null,
    req.query.get("q") || null, Number(req.query.get("limit") || 200),
  ]);
  res.json(d?.d ?? { total: 0, shown: 0, rows: [] });
});

// ------------------------------------------------------------- the tree
// Add, rename, or MOVE. The move is the reason this screen exists: op_save
// used to accept a parent on an edit and drop it.
r.post("/node", requireChair, async (req: any, res: any, next: any) => {
  const { id, name, parentId, active } = req.body || {};
  try {
    out(res, (await one(`select op_save($1,$2,$3,$4,$5) as r`,
      [req.person.id, name ?? null, id ?? null, parentId ?? null,
       typeof active === "boolean" ? active : null]))?.r);
  } catch (e) { next(e); }
});

r.post("/node/retire", requireChair, async (req: any, res: any, next: any) => {
  try {
    out(res, (await one(`select op_retire($1,$2,$3) as r`,
      [req.person.id, req.body?.id ?? null, req.body?.active === true]))?.r);
  } catch (e) { next(e); }
});

// ---------------------------------------------------------------- cities
// A city answers to an operating zone. Sent as the node's id, never as typed
// text, so geo_node.op_zone can only ever name something that exists.
r.post("/city", requireChair, async (req: any, res: any, next: any) => {
  try {
    out(res, (await one(`select op_city_align($1,$2,$3) as r`,
      [req.person.id, req.body?.cityId ?? null, req.body?.placeId ?? null]))?.r);
  } catch (e) { next(e); }
});

// --------------------------------------------------------------- aliases
r.post("/alias", requireChair, async (req: any, res: any, next: any) => {
  const { writtenAs, means, note } = req.body || {};
  try {
    out(res, (await one(`select op_alias_save($1,$2,$3,$4) as r`,
      [req.person.id, writtenAs ?? null, means ?? null, note ?? null]))?.r);
  } catch (e) { next(e); }
});

r.post("/alias/remove", requireChair, async (req: any, res: any, next: any) => {
  try {
    out(res, (await one(`select op_alias_remove($1,$2) as r`,
      [req.person.id, req.body?.writtenAs ?? null]))?.r);
  } catch (e) { next(e); }
});

// --------------------------------------------------------- who runs it
// The place-role: who runs this location, or this client at it. One row, not
// one per branch -- assigning Mumbai used to mean 1,665 rows.
r.post("/role", requireChair, async (req: any, res: any, next: any) => {
  const { nodeId, personId, role, clientId, from } = req.body || {};
  try {
    out(res, (await one(`select op_role_set($1,$2,$3,$4,$5,$6::date) as r`,
      [req.person.id, nodeId ?? null, personId ?? null, role ?? null,
       clientId ?? null, from || null]))?.r);
  } catch (e) { next(e); }
});

r.post("/role/end", requireChair, async (req: any, res: any, next: any) => {
  try {
    out(res, (await one(`select op_role_end($1,$2,$3::date) as r`,
      [req.person.id, req.body?.ruleId ?? null, req.body?.to || null]))?.r);
  } catch (e) { next(e); }
});

// The chair, which is the job -- a different thing from who runs the place
// today, and the owner was explicit that both are needed.
r.post("/chair", requireChair, async (req: any, res: any, next: any) => {
  const { personId, chairId, place, primary } = req.body || {};
  try {
    out(res, (await one(`select op_chair_seat($1,$2,$3,$4,$5) as r`,
      [req.person.id, personId ?? null, chairId ?? null, place ?? null,
       primary === true]))?.r);
  } catch (e) { next(e); }
});

r.post("/chair/end", requireChair, async (req: any, res: any, next: any) => {
  try {
    out(res, (await one(`select op_chair_unseat($1,$2) as r`,
      [req.person.id, req.body?.holderId ?? null]))?.r);
  } catch (e) { next(e); }
});

// ------------------------------------------------------------ coverage
// The whole place at once, or a chosen few. clientIds null means every client
// with a branch there.
r.post("/assign", requireChair, async (req: any, res: any, next: any) => {
  const { nodeId, personId, clientIds, product, from } = req.body || {};
  try {
    if (!mayAssign(req)) {
      return res.status(403).json({ error: "not_permitted",
        reason: "Operations and the administrator assign coverage." });
    }
    out(res, (await one(`select op_bulk_assign($1,$2,$3,$4::uuid[],$5,$6::date) as r`,
      [req.person.id, nodeId ?? null, personId ?? null,
       Array.isArray(clientIds) && clientIds.length ? clientIds : null,
       product || null, from || null]))?.r);
  } catch (e) { next(e); }
});

r.post("/coverage/end", requireChair, async (req: any, res: any, next: any) => {
  try {
    if (!mayAssign(req)) {
      return res.status(403).json({ error: "not_permitted",
        reason: "Operations and the administrator assign coverage." });
    }
    out(res, (await one(`select op_role_end($1,$2,$3::date) as r`,
      [req.person.id, req.body?.ruleId ?? null, req.body?.to || null]))?.r);
  } catch (e) { next(e); }
});

// -------------------------------------------------- clients and branches
// A client is AT a place because its branches are. Adding one moves its
// unplaced branches there; removing one takes them off. Nothing is deleted.
r.post("/client", requireChair, async (req: any, res: any, next: any) => {
  const { clientId, nodeId, attach } = req.body || {};
  try {
    out(res, (await one(`select op_client_place($1,$2,$3,$4) as r`,
      [req.person.id, clientId ?? null, nodeId ?? null, attach !== false]))?.r);
  } catch (e) { next(e); }
});

r.post("/branch", requireChair, async (req: any, res: any, next: any) => {
  const { id, clientId, code, name, nodeId, address, active } = req.body || {};
  try {
    out(res, (await one(`select op_branch_save($1,$2,$3,$4,$5,$6,$7,$8) as r`,
      [req.person.id, clientId ?? null, code ?? null, name ?? null, nodeId ?? null,
       id ?? null, address ?? null,
       typeof active === "boolean" ? active : null]))?.r);
  } catch (e) { next(e); }
});

// ------------------------------------------------------------- the rate
// Never an update: the version in force is end-dated the day before the new
// one starts and both stay readable, so a closed month still reads the rate
// that was valid then.
r.post("/rate", requireChair, async (req: any, res: any, next: any) => {
  const { clientId, nodeId, value, from, to, reason } = req.body || {};
  try {
    if (!mayPrice(req)) {
      return res.status(403).json({ error: "not_permitted",
        reason: "Finance and the administrator own the rate master." });
    }
    out(res, (await one(`select op_rate_set($1,$2,$3::numeric,$4,$5,$6,$7) as r`,
      [req.person.id, clientId ?? null, value ?? null, from ?? null,
       nodeId ?? null, to ?? null, reason ?? null]))?.r);
  } catch (e) { next(e); }
});

export default r;
