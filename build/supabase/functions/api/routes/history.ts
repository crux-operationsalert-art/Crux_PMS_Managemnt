// History & audit trail — the design's screen, and the one panel in the tool
// that has always had real data behind it.
//
// Every write in this application goes through tx(), and tx() cannot commit an
// audit row without the change it describes. So this is not a log that someone
// remembered to write: it is the same transaction.

import { Router, many } from "../shim.ts";
import { requireChair } from "../scope.ts";
const r = Router();

r.get("/", requireChair, async (req: any, res: any) => {
  const mine = req.query.get("mine") === "1" || !req.scope.isAdmin;
  const action = req.query.get("action");
  const limit = Math.min(Number(req.query.get("limit") || 200), 500);

  const rows = await many(
    `select a.at, a.action, a.entity_type, a.entity_ref,
            a.old_value, a.new_value,
            p.full_name as actor, p.employee_no
       from audit_entry a
       left join person p on p.id = a.actor_id
      where ($1::uuid is null or a.actor_id = $1)
        and ($2::text is null or a.action = $2)
      order by a.at desc
      limit $3`,
    [mine ? req.person.id : null, action || null, limit],
  );
  const kinds = await many(
    `select action, count(*)::int as n from audit_entry group by 1 order by 2 desc limit 40`);
  res.json({ rows, kinds, mine, isAdmin: !!req.scope.isAdmin });
});

export default r;
