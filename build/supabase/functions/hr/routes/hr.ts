// =====================================================================
// HR — adding a person.
//
// The whole validation lives in the database as person_check(), and this
// service calls it twice: once for the screen, as somebody types, and
// once inside person_add() before a row is written. That is deliberate.
// A validator the applier does not share is a validator that drifts, and
// this codebase has paid for that twice — once on rates, where the
// validator folded case and the applier did not, and once on client
// codes, for the same reason. So there is one gate and both sides of the
// door use it.
//
// The one thing that is NOT in the database is the activation code. A
// code belongs in an e-mail and never in a log, so person_add() creates
// the person and this file mints the code and hands it to the outbox.
// =====================================================================
import { Router, one, enqueue, issueActivation } from "../shim.ts";
const r = Router();

// Creating a person makes an account. HR's, or an administrator's — and
// the database function says so too, so a caller that skips this service
// is refused just the same.
const mayAdd = (req: any) =>
  req.person.app_role === "ADMIN" ||
  (req.person.department || "") === "Human Resources";

function out(res: any, o: any) {
  if (o?.error) {
    return res.status(o.error === "not_permitted" ? 403 : 400).json(o);
  }
  return res.json(o);
}

// Everything the form has to offer, in one read, so the screen never has to
// guess at a chair id or invent a department.
r.get("/options", async (req: any, res: any) => {
  if (!mayAdd(req)) {
    return res.status(403).json({
      error: "not_permitted",
      reason: "Adding a person is HR's, or an administrator's.",
    });
  }
  const o = await one(`select person_options() as o`);
  return res.json(o.o);
});

// As they type. Returns every problem at once, in sentences, so nobody
// discovers the second one only after fixing the first.
r.post("/check", async (req: any, res: any) => {
  if (!mayAdd(req)) return res.status(403).json({ error: "not_permitted" });
  const o = await one(`select person_check($1::jsonb, $2) as o`,
    [JSON.stringify(req.body || {}), (req.body || {}).personId || null]);
  return res.json(o.o);
});

// The write. person_add does the person, the seat, the coverage rule and the
// trail in one transaction; if any of it fails none of it happened.
r.post("/add", async (req: any, res: any) => {
  const o = await one(`select person_add($1, $2::jsonb) as o`,
    [req.person.id, JSON.stringify(req.body || {})]);
  if (o.o?.error) return out(res, o.o);

  // The account exists; now let them into it. A failure here leaves a real
  // person who cannot yet sign in, which is recoverable and says so, rather
  // than rolling back a person somebody has already been told about.
  let activation = "sent";
  try {
    const code = await issueActivation(o.o.personId, req.person.id);
    const q = await enqueue(req.person.id, {
      templateKey: "ACTIVATION",
      recipient: o.o.email,
      entityType: "person",
      entityId: o.o.personId,
      subject: "Activate your Crux account",
      body: [
        "An account has been created for you on Crux.",
        "Your activation code is " + code + ". It is valid for 15 minutes.",
        'Open Crux, choose "Activate", and enter the code. If you did not expect ' +
          "this, tell your administrator — the code is single-use and expires on its own.",
      ].join("\n\n"),
    });
    if (!q.queued) activation = "not sent: " + (q.reason || "unknown");
  } catch (e) {
    activation = "not sent: " + ((e as Error).message || "failed");
  }

  return res.json({
    ...o.o,
    activation,
    note: o.o.note +
      (activation === "sent"
        ? " An activation code has gone to " + o.o.email + ", valid fifteen minutes."
        : " The person exists, but the activation e-mail " + activation +
          ". Re-send it from HR rather than creating them again."),
  });
});

export default r;
