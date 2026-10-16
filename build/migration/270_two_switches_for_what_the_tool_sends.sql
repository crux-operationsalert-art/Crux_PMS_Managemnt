-- Two switches for what the tool sends: one for the client escalation
-- matrix, one for everything internal
--
-- The owner, 16 Oct: "Client escalation matrix emails are on pause. Add that
-- pause and unpause button for admin incase it's not there. And same but
-- different button for normal internal mails too, as tool is not 100% live
-- can't make start sending emails yet."
--
-- Measured before this file. There was no pause of either kind:
--   * The client matrix had no off switch at all. "On pause" was only that
--     nobody had pressed Send: matrix_send recorded the despatch and the
--     pack service queued one MATRIX_MONTHLY mail per recipient. 0 sent.
--   * Internal mail was live. The crux-mail job drains the outbox every
--     minute; 835 messages had gone (welcome letters, daily-count
--     reminders, matrix nudges). Two cron jobs had been paused by hand
--     (256), but anything else that queued a message -- a person added, the
--     window sweep 269 schedules for 05:15 UTC, a case escalated -- went
--     within a minute.
--   * And every outbox row is copied to WhatsApp (whatsapp_mirror = all).
--     723 copies were waiting in wa_outbox for a phone to be linked. A
--     pause on e-mail that let its WhatsApp copy through would not be one.
--
-- So two switches, both ON (= paused) from this file, both in app_setting
-- and both read by the database at the moment a message would leave:
--
--   mail_client_paused    the monthly escalation matrix to client branches.
--                         matrix_send refuses, in words, before it records
--                         a despatch -- so nothing is half-sent and the
--                         dashboard does not say "sent" -- and the queue
--                         holds any MATRIX_MONTHLY row already in it.
--   mail_internal_paused  everything else the tool writes to staff. The
--                         rows still queue, intact, with no attempt spent,
--                         and leave the moment it is switched off. Their
--                         WhatsApp copies are held the same way.
--
-- Held, not discarded: a pause that threw messages away would turn "not yet"
-- into "never", and nobody would know which. What is waiting is counted on
-- the Mail screen beside each switch, so unpausing is never a surprise.
--
-- One thing is never held: TEST, the message an administrator sends to
-- themselves from the Mail screen to prove the relay works. Testing the
-- route before opening it is the whole point of having a pause.
--
-- Sign-in does not depend on mail: every session to date is Google
-- Workspace sign-in (55), Act-as (37) or a password (2); an e-mailed
-- activation code has never been used. Holding ACTIVATION locks nobody out.
--
-- A missing or unreadable setting reads as PAUSED. Failing closed is the
-- only safe way round for a switch whose job is to stop mail.

-- ------------------------------------------------------------- the switches
insert into app_setting (key, value, plain_language, group_name, secret, editable_by, in_force)
values
  ('mail_client_paused', 'true',
   'Client escalation-matrix mail is paused while this is true: nobody can '
   'send the monthly matrix to a client branch. Switched from the Mail screen.',
   'Mail', false, 'ADMIN', true),
  ('mail_internal_paused', 'true',
   'Internal mail is paused while this is true: messages to staff wait in the '
   'queue, intact, with their WhatsApp copies, and go when it is switched off. '
   'An administrator''s own test message still goes. Switched from the Mail screen.',
   'Mail', false, 'ADMIN', true)
on conflict (key) do nothing;

-- ------------------------------------------------------------ the questions
-- Which switch a message answers to. A test is the administrator's own;
-- the matrix pack is the client's; everything else is internal.
create or replace function public.mail_audience(p_template text, p_entity_type text)
returns text language sql immutable set search_path to 'public' as $$
  select case
           when p_template = 'TEST' then 'test'
           when p_template like 'MATRIX_MONTHLY%' or p_entity_type = 'client' then 'client'
           else 'internal'
         end
$$;

create or replace function public.mail_paused(p_kind text)
returns boolean language sql stable security definer set search_path to 'public' as $$
  -- anything but an explicit 'false' is paused: fail closed
  select coalesce(lower(btrim((select value from app_setting
                                where key = case p_kind when 'client' then 'mail_client_paused'
                                                        else 'mail_internal_paused' end))), 'true')
         <> 'false'
$$;

create or replace function public.mail_held(p_template text, p_entity_type text)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select case mail_audience(p_template, p_entity_type)
           when 'test' then false
           when 'client' then mail_paused('client')
           else mail_paused('internal')
         end
$$;

-- What each switch is holding, for the screen beside it.
create or replace function public.mail_pause_state()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_object_agg(k.kind, jsonb_build_object(
           'paused', mail_paused(k.kind),
           'since', s.updated_at,
           'by', p.full_name,
           'heldMail', (select count(*) from outbox o
                         where o.state in ('QUEUED','DEFERRED')
                           and mail_audience(o.template_key, o.entity_type) = k.kind),
           'heldWhatsapp', (select count(*) from wa_outbox w
                             where w.state = 'QUEUED'
                               and mail_audience(w.template_key, w.entity_type) = k.kind),
           'byTemplate', coalesce((select jsonb_object_agg(t.template_key, t.n) from (
                             select o.template_key, count(*) n from outbox o
                              where o.state in ('QUEUED','DEFERRED')
                                and mail_audience(o.template_key, o.entity_type) = k.kind
                              group by 1) t), '{}'::jsonb)))
    from (values ('client', 'mail_client_paused'), ('internal', 'mail_internal_paused')) k(kind, key)
    left join app_setting s on s.key = k.key
    left join person p on p.id = s.updated_by
$$;

create or replace function public.mail_pause_says()
returns text language sql stable security definer set search_path to 'public' as $$
  select concat_ws(' ',
    case when mail_paused('internal')
         then 'Internal mail is paused by the administrator; what is queued waits, intact.' end,
    case when mail_paused('client')
         then 'Client escalation-matrix mail is paused by the administrator.' end,
    case when mail_paused('internal') or mail_paused('client')
         then 'An administrator switches it back on under Messaging, E-mail.' end)
$$;

-- ------------------------------------------------------------- the switch
create or replace function public.mail_pause_set(p_actor uuid, p_kind text, p_paused boolean)
returns jsonb language plpgsql volatile security definer set search_path to 'public' as $$
declare v_key text; v_old text; v_new text;
begin
  if not exists (select 1 from person
                  where id = p_actor and app_role = 'ADMIN'
                    and employment_status = 'ACTIVE' and superseded_by is null) then
    return jsonb_build_object('error','not_permitted',
      'reason','Pausing and unpausing mail is administrator work.');
  end if;
  if p_kind not in ('client','internal') or p_paused is null then
    return jsonb_build_object('error','invalid',
      'reason','Say which mail (client or internal) and whether it is paused.');
  end if;

  v_key := case p_kind when 'client' then 'mail_client_paused' else 'mail_internal_paused' end;
  v_new := case when p_paused then 'true' else 'false' end;
  select value into v_old from app_setting where key = v_key;

  update app_setting set value = v_new, updated_by = p_actor, updated_at = now()
   where key = v_key;
  if not found then
    insert into app_setting (key, value, plain_language, group_name, updated_by)
    values (v_key, v_new, 'Switched from the Mail screen.', 'Mail', p_actor);
  end if;

  if v_old is distinct from v_new then
    insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
    values (p_actor, case when p_paused then 'MAIL_PAUSED' else 'MAIL_RESUMED' end,
            'app_setting', v_key,
            jsonb_build_object('value', v_old), jsonb_build_object('value', v_new));
  end if;

  return jsonb_build_object('ok', true, 'pause', mail_pause_state(),
    'note', case
      when p_paused and p_kind = 'client'
        then 'Client escalation-matrix mail is paused. Nobody can send the matrix to a client.'
      when p_paused
        then 'Internal mail is paused. New messages wait in the queue, intact.'
      when p_kind = 'client'
        then 'Client escalation-matrix mail is on. Operations can send the monthly matrix.'
      else 'Internal mail is on. What was waiting starts going out within a minute.'
    end);
end $$;

-- Only the services call these, with the service key; nothing reaches them
-- from a browser. The same as every other mail function.
revoke execute on function public.mail_audience(text, text) from public, anon, authenticated;
revoke execute on function public.mail_paused(text) from public, anon, authenticated;
revoke execute on function public.mail_held(text, text) from public, anon, authenticated;
revoke execute on function public.mail_pause_state() from public, anon, authenticated;
revoke execute on function public.mail_pause_says() from public, anon, authenticated;
revoke execute on function public.mail_pause_set(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.mail_audience(text, text) to service_role;
grant execute on function public.mail_paused(text) to service_role;
grant execute on function public.mail_held(text, text) to service_role;
grant execute on function public.mail_pause_state() to service_role;
grant execute on function public.mail_pause_says() to service_role;
grant execute on function public.mail_pause_set(uuid, text, boolean) to service_role;

-- --------------------------------------------- where a message would leave
-- By substitution over the live definitions, as 258 and 269 were, so the
-- parts nobody is changing cannot drift while being retyped. Each anchor
-- must occur exactly once, or this stops rather than half-applying.
do $do$
declare
  r record; v_def text; v_n int;
begin
  for r in
    select * from (values
      -- the e-mail queue: a held row is not claimed, so no attempt is spent
      ('outbox_claim',
       $a$where state = 'QUEUED' and not_before <= now()$a$,
       $b$where state = 'QUEUED' and not_before <= now()
       and not mail_held(template_key, entity_type)  -- 270: a paused audience waits$b$),
      ('outbox_claim',
       $a$  return jsonb_build_object('messages', v_msgs, 'room', v_room);$a$,
       $b$  -- 270: nothing claimed because of a pause is said, never silent
  if v_msgs = '[]'::jsonb and exists (
       select 1 from outbox where state = 'QUEUED' and mail_held(template_key, entity_type)) then
    return jsonb_build_object('held', 'paused', 'reason', mail_pause_says(),
                              'messages', '[]'::jsonb);
  end if;
  return jsonb_build_object('messages', v_msgs, 'room', v_room);$b$),
      -- the WhatsApp copies, pushed and pulled
      ('wa_claim',
       $a$where state = 'QUEUED' and not_before <= now()$a$,
       $b$where state = 'QUEUED' and not_before <= now()
        and not mail_held(template_key, entity_type)  -- 270: a paused audience waits$b$),
      ('wa_bridge_claim',
       $a$where state = 'QUEUED' and not_before <= now()$a$,
       $b$where state = 'QUEUED' and not_before <= now()
          and not mail_held(template_key, entity_type)  -- 270: a paused audience waits$b$),
      -- the client matrix: refused before a despatch is recorded
      ('matrix_send',
       $a$  v_period := date_trunc('month', p_period)::date;$a$,
       $b$  -- 270: the client switch. Refused before anything is recorded, so a
  -- paused send leaves no despatch behind it saying it went.
  if mail_paused('client') then
    return jsonb_build_object('error','paused',
      'reason','Client escalation-matrix mail is paused by the administrator, so '
               'nothing has been sent or recorded. It is switched back on under '
               'Messaging, E-mail.');
  end if;

  v_period := date_trunc('month', p_period)::date;$b$),
      -- and the screens are told, so they do not offer what will be refused
      ('matrix_month',
       $a$'maySend', v_view = 'matrix' or v_view = 'full',$a$,
       $b$'maySend', v_view = 'matrix' or v_view = 'full',
    'clientMailPaused', mail_paused('client'),  -- 270$b$),
      ('mail_status',
       $a$'queued',    (select count(*) from outbox where state='QUEUED'),$a$,
       $b$'pause',     mail_pause_state(),  -- 270
    'queued',    (select count(*) from outbox where state='QUEUED'),$b$)
    ) t(fn, anchor, repl)
  loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = r.fn;
    if v_def is null then
      raise exception 'Migration 270: % is not there to change.', r.fn;
    end if;
    if position(r.repl in v_def) > 0 then
      raise notice 'Migration 270: % already carries this change.', r.fn;
      continue;
    end if;
    v_n := (length(v_def) - length(replace(v_def, r.anchor, ''))) / length(r.anchor);
    if v_n <> 1 then
      raise exception 'Migration 270: the anchor in % occurs % times, not once: %',
        r.fn, v_n, left(r.anchor, 60);
    end if;
    execute replace(v_def, r.anchor, r.repl);
  end loop;
end
$do$;

-- --------------------------------------------------------------- the proof
-- Inside a subtransaction that is rolled back: one message of each kind,
-- every combination of the two switches, and the matrix refused.
do $guard$
declare v_admin uuid; v_client uuid; o jsonb; ids text;
  v_int uuid; v_cli uuid; v_test uuid; v_old_int text; v_old_cli text;
begin
  select value into v_old_int from app_setting where key = 'mail_internal_paused';
  select value into v_old_cli from app_setting where key = 'mail_client_paused';
  select id into v_admin from person
   where app_role = 'ADMIN' and employment_status = 'ACTIVE' and superseded_by is null limit 1;

  begin
    -- nothing else in the queue may answer for these three
    update outbox set not_before = now() + interval '1 year' where state = 'QUEUED';
    insert into outbox (idempotency_key, template_key, recipient, subject, body, entity_type)
      values ('270-int', 'WINDOW_MISS', 'probe.int@cruxindia.co.in', 's', 'b', 'person')
      returning id into v_int;
    insert into outbox (idempotency_key, template_key, recipient, subject, body, entity_type)
      values ('270-cli', 'MATRIX_MONTHLY', 'probe.cli@bank.example.in', 's', 'b', 'client')
      returning id into v_cli;
    insert into outbox (idempotency_key, template_key, recipient, subject, body)
      values ('270-test', 'TEST', 'probe.test@cruxindia.co.in', 's', 'b')
      returning id into v_test;
    update app_setting set value = 'true' where key in ('mail_internal_paused','mail_client_paused');

    o := outbox_claim(50);
    select string_agg(m->>'id', ',') into ids from jsonb_array_elements(o->'messages') m;
    if ids is distinct from v_test::text then
      raise exception 'Migration 270: both paused, the claim took % (expected only the test).', ids;
    end if;
    perform outbox_sent(v_test, 'probe');   -- as the sender does
    o := outbox_claim(50);
    if o->>'held' is distinct from 'paused' then
      raise exception 'Migration 270: a queue held by a pause did not say so: %', o;
    end if;
    if (select attempts from outbox where id = v_int) <> 0 then
      raise exception 'Migration 270: a held message spent an attempt.';
    end if;

    if mail_pause_set(v_admin, 'internal', false)->>'ok' is null then
      raise exception 'Migration 270: the administrator could not unpause internal mail.';
    end if;
    o := outbox_claim(50);
    select string_agg(m->>'id', ',') into ids from jsonb_array_elements(o->'messages') m;
    if ids is distinct from v_int::text then
      raise exception 'Migration 270: internal on, client paused, the claim took %.', ids;
    end if;
    perform outbox_sent(v_int, 'probe');

    if matrix_send(v_admin, gen_random_uuid(), current_date, array['x@bank.example.in'])->>'error'
       is distinct from 'paused' then
      raise exception 'Migration 270: the matrix was not refused while client mail is paused.';
    end if;

    perform mail_pause_set(v_admin, 'client', false);
    o := outbox_claim(50);
    select string_agg(m->>'id', ',') into ids from jsonb_array_elements(o->'messages') m;
    if ids is distinct from v_cli::text then
      raise exception 'Migration 270: client on, the claim took %.', ids;
    end if;

    -- a switch nobody can find (renamed away, inside the rollback)
    update app_setting set key = 'mail_internal_paused-probe' where key = 'mail_internal_paused';
    if not mail_paused('internal') then
      raise exception 'Migration 270: a missing switch reads as sending. It must read as paused.';
    end if;

    raise exception using errcode = 'P0001', message = '270-rollback';
  exception when others then
    if sqlerrm <> '270-rollback' then raise; end if;
  end;

  if (select value from app_setting where key = 'mail_internal_paused') is distinct from v_old_int
     or (select value from app_setting where key = 'mail_client_paused') is distinct from v_old_cli then
    raise exception 'Migration 270: the probe did not put the switches back.';
  end if;
  if not mail_paused('internal') or not mail_paused('client') then
    raise exception 'Migration 270: the tool is not 100%% live, and a switch is not paused.';
  end if;
  raise notice 'Migration 270: both switches paused; held mail waits, the test goes, the matrix is refused.';
end
$guard$;
