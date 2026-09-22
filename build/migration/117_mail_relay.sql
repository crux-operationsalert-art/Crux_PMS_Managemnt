-- =====================================================================
-- 117 · Mail through an Apps Script relay
--
-- Applied as migrations mail_through_an_apps_script_relay,
-- mail_status_keeps_the_names_the_screen_reads,
-- apps_script_joins_the_provider_list and
-- crux_app_page_mail_through_the_relay, 2026-09-22.
--
-- The Gmail API route needs an OAuth client, a client secret and a refresh
-- token, and after several attempts it has never sent a message. The
-- internship programme in the same organisation has been sending for months
-- through a different mechanism, and the owner pointed at it: a small Apps
-- Script web app running inside the sending account, using GmailApp.
--
-- It works because Apps Script is already authorised to send as the account
-- it runs as. One browser consent, once. Nothing to register, nothing to
-- paste, and no token that expires after six months of disuse.
--
-- The script is in mailer/crux-mail.gs and its four setup steps are in
-- mailer/README.md. It is deployed by the owner from
-- operations.alert@cruxindia.co.in, because whichever account deploys it is
-- the address the mail comes from - which is also why the screen checks with
-- Google who the relay really is rather than trusting the From box.
-- =====================================================================

insert into app_setting (key, value, plain_language, group_name, secret, editable_by, in_force)
values
  ('mail_relay_url', '',
   'The web app URL of the Crux mail relay, ending in /exec. Apps Script gives '
   'it to you when you deploy the script. Setting it up takes about five '
   'minutes and is written out in mailer/README.md.',
   'Mail', false, 'ADMIN', true),
  ('mail_relay_secret', '',
   'The shared secret the relay was given. Run makeSecret in the script once '
   'and paste what it prints. Anyone holding this and the URL can send as the '
   'company, so it is stored the way a password is and never shown again.',
   'Mail', true, 'ADMIN', true)
on conflict (key) do nothing;

-- mail_settings hands the sender its configuration at the moment of sending.
-- Both new keys go with it.
create or replace function mail_settings()
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  from app_setting
  where key in ('mail_provider','mail_from','mail_from_name','mail_reply_to',
                'mail_api_key','mail_oauth_client_id','mail_oauth_client_secret',
                'mail_oauth_refresh_token','google_client_id',
                'mail_relay_url','mail_relay_secret')
$$;

-- mail_status gained relayUrl, relaySecretSet and a "ready" arm for the new
-- provider: both halves present, because a URL without a secret cannot send
-- and saying otherwise sends an administrator looking in the wrong place.
--
-- A caution recorded because it nearly shipped: rewriting this function, I
-- renamed oauthClientId to clientId and oauthSet to secretSet on the way
-- past. The Mail screen reads both by their old names, so the Gmail half of
-- that screen would have gone blank with no error anywhere. The old names
-- stay. Full definition in the ledger under
-- mail_status_keeps_the_names_the_screen_reads.

-- apps_script joins the provider list in mail_configure. The relay URL and
-- its secret are ordinary settings, set through the Configuration door, so
-- mail_configure needed no new parameters - only permission to choose it.
-- Full definition in the ledger under apps_script_joins_the_provider_list.

-- ------------------------------------------------------------ the sender
-- build/supabase/functions/mail/index.ts gained sendAppsScript and a
-- /relay/check route, and was deployed as version 3. Two details in it worth
-- keeping in mind:
--
--   · The script answers 200 with a JSON body whether it sent or not, so the
--     body decides, not the status. A Google web app returns its own HTML
--     error page for anything else, and that page in a delivery row tells
--     nobody anything - so an unparseable answer is reported as "check the
--     URL ends in /exec and the deployment is shared with Anyone", which is
--     what it always actually means.
--
--   · GmailApp returns no message id, so this transport records no provider
--     reference. Inventing one would be worse than having none: it would look
--     like something that could be looked up. The copy in Sent is the record
--     on Google's side; the outbox row is the record on ours.
--
-- The relay check is served by cfg rather than mail, because the mail
-- function admits only the scheduler and the service key, and the browser
-- holds neither.
