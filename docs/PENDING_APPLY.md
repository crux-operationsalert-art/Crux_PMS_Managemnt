# One thing is in the repository and not yet live

Written 2026-09-30, updated the same day. Delete this file once it is done.

Migration 235 **has now been applied** and verified: all four of its functions
hash byte-for-byte against
`build/migration/235_a_reminder_that_carries_the_way_to_act_on_it.sql`.

Two things remain, and neither is a code change.

## 1 · Redeploy the `mail` edge function

    build/supabase/functions/mail/index.ts

It gained `linkify`, which turns a URL in the body into a real anchor in the
HTML twin. Without it the plain-text half of every message has working links
and the HTML half shows the URL as dead text.

**Deploy with `verify_jwt: false`**, and send every file the function has — a
deploy replaces all of them.

This has no visible effect until step 2, because until `app_url` is set the
messages carry no URLs for it to link.

## 2 · Set `app_url`, which is the only decision left

Until somebody sets it, the reminders carry **no links at all**. That is
deliberate: a link that goes nowhere, in a hundred inboxes, every morning, is
worse than no link.

```sql
update app_setting
   set value = 'https://…the address that serves index.html…'
 where key = 'app_url';
```

The tool is published by `.github/workflows/publish-tool.yml` into this
repository for GitHub Pages to serve, so the address is the Pages URL for the
repo. It is not written in here because this container's egress proxy refuses
`github.io`, so it could not be confirmed to answer — and an unverified
address is not something to put in 101 people's e-mail.

No redeploy is needed after setting it. The next morning's sweep reads the
setting and every message grows working links. The `job_run` row for each
sweep records `linked: true|false`, so whether a given morning's mail carried
links is answerable afterwards without guessing.

## The test suite

`build/schema` is regenerated from the **live** database by the
`Snapshot the schema` workflow, which runs on a push under `build/migration/`.
Migration 235 was pushed before it was applied, so the snapshot taken at that
moment did not contain `app_link` and the suite read `447 passed, 1 failed`.

Now that 235 is live, the next snapshot picks it up and the suite returns to
zero failures. If it still reads one failure and the message is

    ERROR:  function app_link(unknown) does not exist

the snapshot has not run again yet — re-run that workflow rather than
changing the test, which is correct.
