// Clients — the design's screen, against the real master.
//
// The wireframe is a rail of clients, each opening into the locations it has
// branches at; a client default matrix; the branches at the chosen location;
// and, under any branch, its full record: the five escalation levels with what
// is inherited marked as inherited, the branch manager and the Crux point of
// contact, the address, and who covers it.
//
// The sections the design shows that have no data behind them yet -- the
// performance strip, visits, the RAG reason -- are not faked. Each one says
// what would fill it. An empty panel with a reason is the app's existing
// contract (D8) and it is the difference between "nothing has happened yet"
// and "this is broken".

import { Router, many, one, tx } from "../shim.ts";
import { requireChair } from "../scope.ts";
const r = Router();

function mayEdit(req: any) {
  return !!req.person && (req.person.app_role === "ADMIN" ||
    req.scope.clientView === "matrix" || req.scope.clientView === "full");
}

// Non-admins see the branches their coverage resolves to, and nothing else.
// null means "no restriction" — an administrator.
async function visibleBranchIds(req: any): Promise<string[] | null> {
  if (req.scope.isAdmin) return null;
  const bs = await req.scope.branches();
  return bs.map((b: any) => b.id);
}

r.get("/", requireChair, async (req: any, res: any) => {
  const ids = await visibleBranchIds(req);
  const rows = await many(
    `select c.id, c.code, c.name,
            count(*) filter (where b.status = 'ACTIVE') as active_branches,
            count(*) as branches,
            (select count(*) from matrix_contact m
              where m.client_id = c.id and m.branch_id is null) as default_levels,
            coalesce(jsonb_agg(distinct jsonb_build_object(
              'id', o.id, 'name', o.name, 'zone', coalesce(z.name,''))
              ) filter (where o.id is not null), '[]'::jsonb) as locations
       from client c
       join branch b on b.client_id = c.id
       left join op_node o on o.id = b.op_node_id
       left join op_node z on z.id = o.parent_id
      where c.status = 'ACTIVE'
        and ($1::uuid[] is null or b.id = any($1))
      group by c.id, c.code, c.name
      order by c.name`,
    [ids],
  );
  // the branch count per location, kept out of the aggregate above so the
  // jsonb_agg stays distinct
  const counts = await many(
    `select b.client_id, b.op_node_id,
            count(*) filter (where b.status = 'ACTIVE') as active,
            count(*) as total
       from branch b
      where b.op_node_id is not null and ($1::uuid[] is null or b.id = any($1))
      group by 1,2`,
    [ids],
  );
  const key = (a: string, b: string) => a + "|" + b;
  const byKey: Record<string, any> = {};
  counts.forEach((x: any) => { byKey[key(x.client_id, x.op_node_id)] = x; });
  rows.forEach((c: any) => {
    c.locations = (c.locations || []).map((l: any) => {
      const k = byKey[key(c.id, l.id)] || {};
      return { ...l, active: Number(k.active || 0), total: Number(k.total || 0) };
    }).sort((a: any, b: any) => (a.name < b.name ? -1 : 1));
  });
  res.json({ clients: rows, mayEdit: mayEdit(req) });
});

// The client default matrix: the five levels a branch falls back on when it has
// not entered its own.
r.get("/:clientId/matrix", requireChair, async (req: any, res: any) => {
  const levels = await many(
    `select level, level_name, name, mobile, email, updated_at
       from matrix_contact
      where client_id = $1 and branch_id is null
      order by level`,
    [req.params.clientId],
  );
  const inherit = await one(
    `select count(*)::int as n from branch b
      where b.client_id = $1 and b.status = 'ACTIVE'
        and not exists (select 1 from matrix_contact m where m.branch_id = b.id)`,
    [req.params.clientId],
  );
  res.json({ levels, inheritCount: inherit ? inherit.n : 0, mayEdit: mayEdit(req) });
});

r.get("/:clientId/location/:locationId", requireChair, async (req: any, res: any) => {
  const ids = await visibleBranchIds(req);
  const branches = await many(
    `select b.id, b.code, b.name, b.address, b.status,
            coalesce(s.complete_levels, 0) as complete_levels,
            bm.name as manager, bm.mobile as manager_mobile, bm.email as manager_email,
            poc.name as poc,
            own.full_name as owner
       from branch b
       left join branch_matrix_state s on s.branch_id = b.id
       left join lateral (select name, mobile, email from branch_contact
                           where branch_id = b.id and role = 'BRANCH_MANAGER' and active
                           limit 1) bm on true
       left join lateral (select name from branch_contact
                           where branch_id = b.id and role = 'CRUX_POC' and active
                           limit 1) poc on true
       left join lateral (select p.full_name from coverage_rule cr
                           join person p on p.id = cr.person_id
                          where cr.branch_id = b.id and cr.effective_to is null
                          limit 1) own on true
      where b.client_id = $1 and b.op_node_id = $2
        and ($3::uuid[] is null or b.id = any($3))
      order by b.status, b.name`,
    [req.params.clientId, req.params.locationId, ids],
  );
  res.json({ branches, mayEdit: mayEdit(req) });
});

// A branch's full record, as the design lays it out.
r.get("/branch/:branchId", requireChair, async (req: any, res: any) => {
  const ids = await visibleBranchIds(req);
  const b = await one(
    `select b.id, b.code, b.name, b.address, b.status, b.effective_from as opened_on,
            c.name as client, c.code as client_code,
            o.name as location, z.name as zone,
            coalesce(s.complete_levels, 0) as complete_levels
       from branch b
       join client c on c.id = b.client_id
       left join op_node o on o.id = b.op_node_id
       left join op_node z on z.id = o.parent_id
       left join branch_matrix_state s on s.branch_id = b.id
      where b.id = $1 and ($2::uuid[] is null or b.id = any($2))`,
    [req.params.branchId, ids],
  ).catch(() => null);
  if (!b) {
    return res.status(404).json({ error: "not_found",
      reason: "That branch is not in your coverage." });
  }
  const [levels, contacts, owners] = await Promise.all([
    many(`select level, level_name, name, mobile, email, inherited
            from branch_effective_matrix where branch_id = $1 order by level`,
         [req.params.branchId]),
    many(`select role, name, mobile, email from branch_contact
           where branch_id = $1 and active order by role`, [req.params.branchId]),
    many(`select p.full_name, p.employee_no, cr.product, cr.effective_from,
                 ch.title as chair
            from coverage_rule cr
            join person p on p.id = cr.person_id
            left join chair_holder h on h.person_id = p.id and h.to_date is null and h.is_primary
            left join chair ch on ch.id = h.chair_id
           where cr.branch_id = $1 and cr.effective_to is null`, [req.params.branchId]),
  ]);
  res.json({
    branch: b, levels, contacts, owners, mayEdit: mayEdit(req),
    // Named rather than silently missing. The design has these panels and the
    // tables behind them are empty, which is a fact about the data, not a bug.
    notYet: {
      performance: "Nothing is filed against this branch yet. It fills when Collections and Rates are loaded and daily counts start arriving.",
      visits: "No visit has been recorded here. A visit writes back into this record — it updates the contact it met and moves the last-seen date.",
      rag: "A RAG needs a target and a month of filings to compare against. Neither exists yet.",
    },
  });
});

// Add a branch, as the design's form does it: client, zone and region come from
// the location and are never asked for again.
r.post("/branch", requireChair, async (req: any, res: any, next: any) => {
  const { clientId, locationId, name, code, managerName, managerMobile,
          managerEmail, address } = req.body || {};
  try {
    if (!mayEdit(req)) {
      return res.status(403).json({ error: "not_permitted",
        reason: "Operations and the administrator own the client master." });
    }
    if (!clientId || !locationId || !name || !code) {
      return res.status(400).json({ error: "incomplete",
        reason: "A branch needs its client, its location, a name and a code." });
    }
    const out = await tx(req.person.id, async (t: any) => {
      const dup = (await t.q(
        `select id from branch where client_id = $1 and lower(btrim(code)) = lower(btrim($2))`,
        [clientId, code])).rows[0];
      if (dup) throw Object.assign(new Error("code_taken"), { status: 409,
        reason: "That client already has a branch with this code." });

      const nb = (await t.q(
        `insert into branch (client_id, code, name, address, op_node_id, status, source_ref)
         values ($1, btrim($2), btrim($3), nullif(btrim(coalesce($4,'')),''), $5, 'ACTIVE', 'Clients screen')
         returning id, code, name`,
        [clientId, code, name, address || null, locationId])).rows[0];

      if (managerName && String(managerName).trim()) {
        await t.q(
          `insert into branch_contact (branch_id, role, name, mobile, email, active)
           values ($1,'BRANCH_MANAGER',$2,$3,$4,true)`,
          [nb.id, String(managerName).trim(), managerMobile || null, managerEmail || null]);
      }
      await t.audit("BRANCH_ADDED", "branch", nb.code, null,
        { name: nb.name, clientId, locationId });
      return nb;
    });
    res.status(201).json(out);
  } catch (e) { next(e); }
});

// Edit the details the design's "Edit these details" opens: the address and the
// two people. The matrix is edited through the matrix endpoints, which already
// audit every level.
r.put("/branch/:branchId", requireChair, async (req: any, res: any, next: any) => {
  const { name, address, manager, poc } = req.body || {};
  try {
    if (!mayEdit(req)) {
      return res.status(403).json({ error: "not_permitted",
        reason: "Operations and the administrator own the client master." });
    }
    const out = await tx(req.person.id, async (t: any) => {
      const before = (await t.q(
        `select code, name, address from branch where id = $1`, [req.params.branchId])).rows[0];
      if (!before) throw Object.assign(new Error("not_found"), { status: 404 });

      await t.q(
        `update branch set name = coalesce(nullif(btrim($2),''), name),
                           address = coalesce(nullif(btrim($3),''), address),
                           updated_at = now()
          where id = $1`,
        [req.params.branchId, name || null, address || null]);

      for (const [role, c] of [["BRANCH_MANAGER", manager], ["CRUX_POC", poc]] as any[]) {
        if (!c || !String(c.name || "").trim()) continue;
        await t.q(`update branch_contact set active = false
                    where branch_id = $1 and role = $2 and active`,
                  [req.params.branchId, role]);
        await t.q(
          `insert into branch_contact (branch_id, role, name, mobile, email, active)
           values ($1,$2,$3,$4,$5,true)`,
          [req.params.branchId, role, String(c.name).trim(), c.mobile || null, c.email || null]);
      }

      const after = (await t.q(
        `select code, name, address from branch where id = $1`, [req.params.branchId])).rows[0];
      await t.audit("BRANCH_EDITED", "branch", before.code, before, after);
      return after;
    });
    res.json(out);
  } catch (e) { next(e); }
});

export default r;
