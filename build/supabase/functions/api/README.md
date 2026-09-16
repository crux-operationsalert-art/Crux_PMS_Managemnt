# The deployed API

This is the source of the Supabase Edge Function `api`, which is what actually
serves the application. Until now it existed **only** as a deployment — this
directory is the copy that can be reviewed, diffed and redeployed.

`build/api/` is the Express original and remains the reference implementation.
`shim.ts` is what lets the route files run here almost unchanged: it supplies
`Router`, a `req`/`res` pair and a db module with the same `q`/`one`/`many`/`tx`
contract, including `tx` carrying the actor so an audit row still cannot commit
without the change it describes.

## Deploying

    supabase functions deploy api --project-ref oxpwqfbtbxlvuqpztbwg

A deploy replaces the whole function: every file in this directory has to go up
together, and omitting one fails the bundle rather than half-deploying.

`verify_jwt` is **false** on purpose. The function does its own authentication
against `auth_session` using the `x-crux-token` header — the same session rows
the upload service issues, so one token opens both doors and revoking it there
revokes it here.

## Environment

`SUPABASE_DB_URL` is the only variable it needs. The pooler does not support
prepared statements, hence `prepare: false`.

## Routes

| mount | file |
|---|---|
| `/api/cases` | `routes/cases.ts` |
| `/api/matrix` | `routes/matrix.ts` |
| `/api/pms` | `routes/pms.ts` |
| `/api/people` | `routes/people.ts` |
| `/api/penalties` | `routes/penalties.ts` |
| `/api/sample` | `routes/sample.ts` |
| `/api/<table>` | `routes/table.ts` — last, and only for the ten `seam` views |
