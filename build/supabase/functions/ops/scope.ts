// D7: the chair, not the person, drives everything.
// D8: no chair may borrow another chair's data. A read with no scope returns an
// empty set and a reason — never a fallback to somebody else's dashboard.
// Carried across from build/api/scope.js; the SQL is unchanged.
import { many, one } from "./shim.ts";

export async function chairsFor(personId: string) {
  return many(
    `select ch.id, ch.code, ch.title, ch.parent_id, chh.is_primary
       from chair_holder chh
       join chair ch on ch.id = chh.chair_id
      where chh.person_id = $1 and chh.to_date is null
      order by chh.is_primary desc, ch.title`,
    [personId],
  );
}

export async function subtree(chairId: string) {
  return many(
    `with recursive t as (
        select id from chair where id = $1
        union all
        select c.id from chair c join t on c.parent_id = t.id)
      select id from t`,
    [chairId],
  );
}

// The branches a person may see, from coverage_rule only. Two people with the
// same designation and different coverage see different branches; that is the
// point.
export async function branchScope(personId: string) {
  return many(
    `select distinct b.id, b.code, b.name, b.client_id, b.status
       from coverage_rule r
       cross join lateral coverage_resolve(r) cr(branch_id)
       join branch b on b.id = cr.branch_id
      where r.person_id = $1
        and (r.effective_to is null or r.effective_to >= current_date)`,
    [personId],
  );
}

// HR sees people and never client data; Operations owns the matrix; Finance and
// Compliance get branch details and contacts only. Driven by the table, so a
// policy change is a row, not a deploy.
export async function clientViewKind(personId: string) {
  const r = await one(
    `select coalesce(p2.view_kind, 'none') as view_kind
       from person p
       left join client_view_policy p2 on p2.department = p.department
      where p.id = $1`,
    [personId],
  );
  return r ? (r.view_kind as string) : "none";
}

// The rows of business_record a person may see.
//
// business_record is keyed by (client, geography) and not by branch, so a
// coverage rule cannot be applied to it directly: it has to be reduced to the
// (client, geography) pairs it reaches. Two separate lists would not do -- a
// person covering Client A in Zone 1 and Client B in Zone 2 must not be shown
// Client A in Zone 2 -- so the pairs are kept as pairs and matched as pairs.
export async function recordScope(personId: string) {
  return many(
    `select distinct b.client_id, b.geo_node_id
       from coverage_rule r
       cross join lateral coverage_resolve(r) cr(branch_id)
       join branch b on b.id = cr.branch_id
      where r.person_id = $1
        and (r.effective_to is null or r.effective_to >= current_date)`,
    [personId],
  );
}

// The eight scope levels the design gives every chair. The table lives in the
// database -- access_level_screen, seeded from the published tool's own
// SCREENS -- so the navigation and this service read one policy rather than
// two copies of it. See migration 204.
export async function levelAndScreens(personId: string) {
  const r = await one(
    `select access_level_of($1) as level, access_screens($1) as screens`,
    [personId],
  );
  return {
    level: (r?.level as string) ?? "exec",
    screens: (r?.screens as string[]) ?? [],
  };
}

// The owner's instruction, in their words: operations.alert is the admin, the
// creator, the controller -- nothing is hidden from it and it can change
// everything. So an ADMIN's scope is not derived from a seat; it is every
// chair and every branch. D8 still governs everyone else: a scope is built
// from the person's own chairs and coverage, and that is what every query
// below filters on.
export async function buildScope(personId: string, appRole?: string): Promise<any> {
  const isAdmin = appRole === "ADMIN";
  const [chairs, clientView, access] = await Promise.all([
    chairsFor(personId),
    clientViewKind(personId),
    levelAndScreens(personId),
  ]);
  const primary = chairs.find((c: any) => c.is_primary) ?? chairs[0] ?? null;
  const everyChair = isAdmin
    ? (await many(`select id from chair`)).map((r: any) => r.id)
    : null;
  return {
    personId,
    chairs,
    primaryChair: primary,
    isAdmin,
    level: access.level,
    screens: access.screens,
    clientView: isAdmin ? "full" : clientView,
    chairIds: isAdmin ? everyChair : chairs.map((c: any) => c.id),
    subtreeIds: isAdmin
      ? everyChair
      : (primary ? (await subtree(primary.id)).map((r: any) => r.id) : []),
    branchIds: null,
    async branches() {
      if (!this.branchIds) {
        this.branchIds = isAdmin
          ? await many(`select b.id, b.code, b.name, b.client_id, b.status from branch b`)
          : await branchScope(personId);
      }
      return this.branchIds;
    },
  };
}

// The empty state says why it is empty. A new chair with no coverage yet is a
// real, expected condition — it is not an error and it is not somebody else's
// data.
export function emptyReason(scope: any) {
  if (!scope) return "Not signed in.";
  if (!scope.chairs.length) {
    return "You do not hold a chair yet. Ask HR to seat you before this page can show anything.";
  }
  return "This chair has no coverage assigned. Operations assigns coverage; nothing is shown until it does.";
}

// A seat is not what entitles an administrator to look at the tool. Without
// this, an admin who had just loaded 636 people and 152 chairs opened People
// and Org chart and saw nothing, with no way to tell a permission problem from
// an empty database -- which is exactly what happened.
//
// D8 still holds for everyone who is not an administrator: their scope is
// built from their own chairs and coverage, and every query filters on it. An
// administrator's scope is deliberately the whole company, set in buildScope.
export function requireChair(req: any, res: any, next: (e?: unknown) => void) {
  if (req.scope && req.scope.isAdmin) { next(); return; }
  if (!req.scope || !req.scope.chairs.length) {
    res.status(403).json({ error: "no_chair", reason: emptyReason(req.scope) });
    return;
  }
  next();
}

// The screen gate.
//
// The published tool says of its own access table: "It is NOT the permission
// check. Every service decides for itself and refuses in its own words; hiding
// a screen stops somebody wandering into it and does nothing about somebody
// typing the URL." This is the service deciding. Every route below names the
// screen it serves, and a caller whose level does not carry that screen is
// refused here -- with the same answer the navigation got, because both read
// access_level_screen.
//
// A refusal says what was asked for and what the caller is, because "403" sent
// somebody hunting through logs once already.
export function requireScreen(screen: string) {
  return function (req: any, res: any, next: (e?: unknown) => void) {
    if (!req.scope) {
      res.status(401).json({ error: "sign_in_required", reason: "Not signed in." });
      return;
    }
    if (req.scope.isAdmin || (req.scope.screens || []).includes(screen)) { next(); return; }
    res.status(403).json({
      error: "out_of_scope",
      screen,
      level: req.scope.level,
      reason: "This is not a screen your chair carries, so there is nothing here " +
        "for you to see. If it should be, the chair's scope level is what changes, " +
        "not this page.",
    });
  };
}

// postgres.js infers a parameter's type from the value it is given, and an
// empty JavaScript array tells it nothing. Every array below is a list of ids
// that is allowed to be empty in principle, so an empty one is sent as a list
// holding the nil uuid instead: it matches nothing, which is the right answer,
// and it carries a type.
export const NOBODY = "00000000-0000-0000-0000-000000000000";
export const idList = (ids: string[] | null | undefined) =>
  ids && ids.length ? ids : [NOBODY];

// Write guard: may this request touch this chair?
export async function mayWriteChair(scope: any, chairId: string) {
  if (!scope) return false;
  if (scope.isAdmin) return true;
  if (scope.chairIds.includes(chairId)) return true;
  return scope.subtreeIds.includes(chairId);
}
