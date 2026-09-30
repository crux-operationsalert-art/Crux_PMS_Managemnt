# Two things are in the repository and not yet on the live database

Written 2026-09-30. Delete this file once both are done.

The Supabase tool this session uses stopped receiving approvals partway
through the last change, so two steps could not be carried out from here.
Both are finished work: they are committed, they pass their tests, and they
apply cleanly. They are simply not yet applied to the live project.

Nothing in the tool is broken while they wait. The reminders keep going out
exactly as they did before — the change makes them better, it does not fix
something that is currently failing.

## 1 · Apply migration 235

    build/migration/235_a_reminder_that_carries_the_way_to_act_on_it.sql

Adds `app_url` to `app_setting`, `app_link()`, `perf_unit_plain()`, and
rewrites `perf_reminder_sweep` and `matrix_nudge_sweep` to use them. The
migration ends in a guard that raises if any of it did not take, so a
successful apply is evidence and not an assumption.

Verify afterwards the way everything else on this project is verified — by
hashing the live function against the file, not by the apply returning
success:

```sql
select proname, md5(prosrc), length(prosrc)
  from pg_proc
 where proname in ('app_link','perf_unit_plain',
                   'perf_reminder_sweep','matrix_nudge_sweep')
 order by proname;
```

## 2 · Redeploy the `mail` edge function

    build/supabase/functions/mail/index.ts

It gained `linkify`, which turns a URL in the body into a real anchor in the
HTML twin. Without it the plain-text half of every message has working links
and the HTML half has the URL as dead text.

**Deploy with `verify_jwt: false`**, and send every file the function has —
a deploy replaces all of them.

## 3 · Then set `app_url`, which is the only decision left

Until somebody sets it, the reminders carry **no links at all**. That is
deliberate: a link that goes nowhere, in a hundred inboxes, every morning,
is worse than no link.

```sql
update app_setting
   set value = 'https://…the address that serves index.html…'
 where key = 'app_url';
```

The tool is published by `.github/workflows/publish-tool.yml` into this
repository for GitHub Pages to serve, so the address is the Pages URL for
the repo. It is not written in here because this container's egress proxy
refuses `github.io`, so it could not be confirmed to answer — and an
unverified address is not something to put in 101 people's e-mail.

No redeploy is needed after setting it. The next morning's sweep reads the
setting and every message grows working links. The `job_run` row for each
sweep records `linked: true|false`, so whether a given morning's mail
carried links is answerable afterwards without guessing.
