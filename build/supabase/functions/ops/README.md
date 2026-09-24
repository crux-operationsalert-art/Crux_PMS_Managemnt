# ops — the second half of the API

One Supabase Edge Function can only be deployed in a single call, and `api`
had grown past what that call will carry. So the screens added after the
cut-over — Visits & claims, the Ideathon, Rate master, MIS, the 10-day view,
Reports, Report access, HR and Joining — are served from here instead.

It is the same front door: the same `auth_session` token, the same scope rules,
the same `req`/`res` shim. Nothing about how a request is authorised differs.

**`shim.ts` and `scope.ts` here are copies, not a second opinion.** The
authored versions are `../api/shim.ts` and `../api/scope.ts`; these are
refreshed from them before every deploy:

    cp ../api/shim.ts ../api/scope.ts .

If the two ever disagree, `api` is right and this is stale. D8 has one
definition and it lives next to `api`.
