-- The two mail switches (migration 270)
--
-- "Client escalation matrix emails are on pause. Add that pause and unpause
--  button for admin ... And same but different button for normal internal
--  mails too, as tool is not 100% live can't make start sending emails yet"
--
-- Each assertion is one of those sentences:
--
--   both start paused, and a switch nobody can find reads as paused
--   paused means held: still queued, no attempt spent, and the queue says why
--   the administrator's own test still goes
--   the two switches are different switches
--   a paused matrix is refused before anything is recorded
--   the WhatsApp copy waits with the e-mail it copies
--   only an administrator flips either, and the flip is in the trail
--   the screens are told, so they do not offer what will be refused
--   and nothing outside the services can reach the switch
--
-- Everything is rolled back.

begin;

do $t$
declare
  p_admin uuid; p_viewer uuid; v_bridge uuid;
  v_int uuid; v_cli uuid; v_test uuid; w_int uuid; w_cli uuid;
  o jsonb; ids text; n int;
begin
  -- The switches are rows 270 inserts, and the suite rebuilds from a schema
  -- snapshot that carries no rows -- so the test brings its own, in 270's
  -- words, as test_partner does for its designation.
  insert into app_setting (key, value, plain_language, group_name)
  values ('mail_client_paused', 'true', 'test', 'Mail'),
         ('mail_internal_paused', 'true', 'test', 'Mail')
  on conflict (key) do nothing;
  update app_setting set value = 'true'
   where key in ('mail_client_paused', 'mail_internal_paused');

  insert into person (full_name, work_email, app_role)
    values ('MP Admin', 'mp.admin@cruxindia.co.in', 'ADMIN') returning id into p_admin;
  insert into person (full_name, work_email, app_role)
    values ('MP Viewer', 'mp.viewer@cruxindia.co.in', 'VIEWER') returning id into p_viewer;

  -- nothing else in the queue may answer for these
  update outbox set not_before = now() + interval '1 year' where state = 'QUEUED';
  update wa_outbox set not_before = now() + interval '1 year' where state = 'QUEUED';

  insert into outbox (idempotency_key, template_key, recipient, subject, body, entity_type)
    values ('mp-int', 'WINDOW_MISS', 'mp.int@cruxindia.co.in', 'Overdue', 'b', 'person')
    returning id into v_int;
  insert into outbox (idempotency_key, template_key, recipient, subject, body, entity_type, entity_id)
    values ('mp-cli', 'MATRIX_MONTHLY', 'mp.cli@bank.co.in', 'Escalation matrix', 'b',
            'client', gen_random_uuid())
    returning id into v_cli;
  insert into outbox (idempotency_key, template_key, recipient, subject, body)
    values ('mp-test', 'TEST', 'mp.admin@cruxindia.co.in', 'Test', 'b')
    returning id into v_test;

  -- ------------------------------------------------- both start paused
  if not mail_paused('internal') or not mail_paused('client') then
    raise exception 'FAIL  the tool is not live and a switch reads as sending';
  end if;
  update app_setting set key = 'mail_internal_paused-gone' where key = 'mail_internal_paused';
  if not mail_paused('internal') then
    raise exception 'FAIL  a switch nobody can find reads as sending. It must fail closed.';
  end if;
  update app_setting set key = 'mail_internal_paused' where key = 'mail_internal_paused-gone';
  update app_setting set value = 'maybe' where key = 'mail_internal_paused';
  if not mail_paused('internal') then
    raise exception 'FAIL  a switch that says neither true nor false reads as sending';
  end if;
  update app_setting set value = 'true' where key = 'mail_internal_paused';
  raise notice 'PASS  both switches start paused, and anything but "false" is paused';

  -- ------------------------------------- paused is held, and the test goes
  o := outbox_claim(50);
  select string_agg(m->>'id', ',') into ids from jsonb_array_elements(o->'messages') m;
  if ids is distinct from v_test::text then
    raise exception 'FAIL  with both paused the queue gave out % -- expected the test alone', ids;
  end if;
  perform outbox_sent(v_test, 'test');   -- as the sender does
  raise notice 'PASS  the administrator''s own test message goes while everything is paused';

  o := outbox_claim(50);
  if o->>'held' is distinct from 'paused' or coalesce(o->>'reason','') not like '%paused%' then
    raise exception 'FAIL  a queue held by a pause did not say so: %', o;
  end if;
  select count(*) into n from outbox
   where id in (v_int, v_cli) and state = 'QUEUED' and attempts = 0;
  if n <> 2 then
    raise exception 'FAIL  a held message was touched -- % of 2 are still queued with no attempt', n;
  end if;
  raise notice 'PASS  paused mail waits in the queue, intact, and the sender is told why';

  -- --------------------------------------- the switch is the administrator's
  if mail_pause_set(p_viewer, 'internal', false)->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  somebody who is not an administrator unpaused internal mail';
  end if;
  if mail_pause_set(p_admin, 'everything', false)->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  a switch that does not exist was flipped';
  end if;
  if mail_pause_set(p_admin, 'internal', null)->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  a flip that did not say which way was read as one';
  end if;
  if not mail_paused('internal') then
    raise exception 'FAIL  a refused flip changed the switch';
  end if;
  raise notice 'PASS  only an administrator flips a switch, and only by saying which way';

  -- --------------------------------------------- two different switches
  o := mail_pause_set(p_admin, 'internal', false);
  if o->>'ok' is null or (o#>>'{pause,internal,paused}')::boolean
     or not (o#>>'{pause,client,paused}')::boolean then
    raise exception 'FAIL  unpausing internal mail did not answer with the two switches: %', o;
  end if;
  o := outbox_claim(50);
  select string_agg(m->>'id', ',') into ids from jsonb_array_elements(o->'messages') m;
  if ids is distinct from v_int::text then
    raise exception 'FAIL  internal on and client paused gave out % -- expected the internal one', ids;
  end if;
  perform outbox_sent(v_int, 'test');   -- as the sender does
  raise notice 'PASS  internal mail on leaves the client matrix paused';

  -- ---------------------------------------------- the matrix is refused
  o := matrix_send(p_admin, gen_random_uuid(), current_date, array['mp.cli@bank.co.in']);
  if o->>'error' is distinct from 'paused' then
    raise exception 'FAIL  the matrix was not refused while client mail is paused: %', o;
  end if;
  if exists (select 1 from matrix_dispatch where prepared_by = p_admin) then
    raise exception 'FAIL  a refused matrix left a despatch behind it saying it went';
  end if;
  if not coalesce((matrix_month(p_admin, current_date)->>'clientMailPaused')::boolean, false) then
    raise exception 'FAIL  the matrix screen is not told the client mail is paused';
  end if;
  raise notice 'PASS  a paused matrix is refused before anything is recorded, and the screen knows';

  o := mail_pause_set(p_admin, 'client', false);
  o := outbox_claim(50);
  select string_agg(m->>'id', ',') into ids from jsonb_array_elements(o->'messages') m;
  if ids is distinct from v_cli::text then
    raise exception 'FAIL  client on gave out % -- expected the matrix row', ids;
  end if;
  perform outbox_sent(v_cli, 'test');   -- as the sender does
  raise notice 'PASS  and unpaused, the matrix row leaves';

  -- ------------------------------------------- the trail, and the screen
  select count(*) into n from audit_entry
   where actor_id = p_admin and action = 'MAIL_RESUMED' and entity_type = 'app_setting';
  if n <> 2 then
    raise exception 'FAIL  % of the two flips are in the trail', n;
  end if;
  perform mail_pause_set(p_admin, 'internal', true);
  perform mail_pause_set(p_admin, 'internal', true);
  select count(*) into n from audit_entry where actor_id = p_admin and action = 'MAIL_PAUSED';
  if n <> 1 then
    raise exception 'FAIL  pausing what was already paused wrote % trail rows -- expected 1', n;
  end if;
  o := mail_status();
  if not (o#>>'{pause,internal,paused}')::boolean or (o#>>'{pause,client,paused}')::boolean
     or (o#>>'{pause,internal,by}') is distinct from 'MP Admin' then
    raise exception 'FAIL  the Mail screen is not told which switch is where, and who set it: %',
      o->'pause';
  end if;
  raise notice 'PASS  every flip is in the trail once, and the Mail screen reads both switches';

  -- ------------------------------------------ the WhatsApp copies wait too
  perform mail_pause_set(p_admin, 'client', true);
  insert into wa_outbox (idempotency_key, template_key, entity_type, recipient, body)
    values ('mp-w-int', 'PERF_DUE', 'person', '+919800000001', 'b') returning id into w_int;
  insert into wa_outbox (idempotency_key, template_key, entity_type, recipient, body)
    values ('mp-w-cli', 'MATRIX_MONTHLY', 'client', '+919800000002', 'b') returning id into w_cli;
  insert into wa_bridge (name, token_hash, state)
    values ('mp phone', encode(extensions.digest('mp-token', 'sha256'), 'hex'), 'READY')
    returning id into v_bridge;
  o := wa_bridge_claim('mp-token');
  if jsonb_array_length(coalesce(o->'messages', '[]'::jsonb)) <> 0 then
    raise exception 'FAIL  a linked phone was handed % message(s) while both switches are paused',
      jsonb_array_length(o->'messages');
  end if;
  if (select heldWhatsapp from (select (mail_pause_state()#>>'{internal,heldWhatsapp}')::int heldWhatsapp) x) < 1 then
    raise exception 'FAIL  the held WhatsApp copies are not counted for the screen';
  end if;
  perform mail_pause_set(p_admin, 'internal', false);
  o := wa_bridge_claim('mp-token');
  select string_agg(m->>'id', ',') into ids from jsonb_array_elements(o->'messages') m;
  if ids is distinct from w_int::text then
    raise exception 'FAIL  internal on, the phone was handed % -- expected the internal copy', ids;
  end if;
  raise notice 'PASS  a WhatsApp copy waits with the e-mail it copies, by the same switch';

  -- ------------------------------------------------ who can reach the switch
  if has_function_privilege('anon', 'mail_pause_set(uuid,text,boolean)', 'execute')
     or has_function_privilege('authenticated', 'mail_pause_set(uuid,text,boolean)', 'execute') then
    raise exception 'FAIL  the switch can be flipped with the public key, as anybody';
  end if;
  if not has_function_privilege('service_role', 'mail_pause_set(uuid,text,boolean)', 'execute') then
    raise exception 'FAIL  the Mail screen''s own service cannot reach the switch';
  end if;
  raise notice 'PASS  only the services reach the switch';

  raise notice '--- the two mail switches: every assertion passed ---';
end $t$;

rollback;
