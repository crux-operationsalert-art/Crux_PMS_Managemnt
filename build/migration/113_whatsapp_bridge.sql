-- =====================================================================
-- 113 · WhatsApp through a linked device, and the alerts it raises
--
-- Applied to the database as migrations ops_alert_and_whatsapp_bridge,
-- ops_alert_functions, whatsapp_bridge_functions,
-- whatsapp_bridge_claim_and_pacing, whatsapp_web_provider,
-- whatsapp_bridge_sweep_schedule, whatsapp_bridge_admin_functions and
-- whatsapp_bridge_qr_image, all of 2026-09-18. The screen changes that
-- go with them are in app_page; see crux_app_page_whatsapp_devices,
-- crux_app_page_whatsapp_device_handlers and
-- crux_app_page_qr_no_third_party.
-- =====================================================================

-- =====================================================================
-- An operational alert, and the WhatsApp Web bridge that raises them.
--
-- The owner has chosen to run WhatsApp through a linked-device bridge
-- rather than the Cloud API, as a stop-gap until the paid route is
-- approved. The risks were put to them and they decided; this records
-- the decision rather than re-arguing it.
--
-- What that decision means technically: WhatsApp will not be sent from
-- this database or from an edge function. It is sent by a small program
-- the company runs on a machine it owns, which holds the linked session
-- and asks this system for work. Everything here is the half that lives
-- in the tool: who may ask for work, how fast they may send, and what
-- happens when the link breaks.
-- =====================================================================

-- ------------------------------------------------------------- alerts
-- Deliberately not the `task` table: that one carries attribute_weight,
-- period and outcome, and feeds performance scoring. "Scan this QR code"
-- is not a performance event and must not be scored like one.
create table if not exists ops_alert (
  id              uuid primary key default gen_random_uuid(),
  kind            text not null,
  severity        text not null default 'WARN'
                    check (severity in ('INFO','WARN','URGENT')),
  title           text not null,
  detail          text,
  action_hint     text,
  for_role        text not null default 'ADMIN',
  entity_type     text,
  entity_id       uuid,
  -- one open alert per thing, so a break every minute is one alert
  dedupe_key      text not null,
  retry_at        timestamptz,
  opened_at       timestamptz not null default now(),
  last_seen_at    timestamptz not null default now(),
  occurrences     int not null default 1,
  acknowledged_by uuid references person(id),
  acknowledged_at timestamptz,
  resolved_at     timestamptz,
  resolved_note   text
);

-- an alert is only unique while it is open; once resolved the same thing
-- may legitimately happen again
create unique index if not exists ops_alert_open_uniq
  on ops_alert (dedupe_key) where resolved_at is null;
create index if not exists ops_alert_open_idx
  on ops_alert (severity, opened_at) where resolved_at is null;

alter table ops_alert enable row level security;

-- ------------------------------------------------------------ bridges
create table if not exists wa_bridge (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  device_kind   text not null default 'laptop'
                  check (device_kind in ('laptop','phone','server')),
  token_hash    text not null unique,
  state         text not null default 'NEW'
                  check (state in ('NEW','NEEDS_QR','READY','STALE','DISABLED')),
  phone_number  text,
  last_seen_at  timestamptz,
  last_sent_at  timestamptz,
  last_qr_at    timestamptz,
  qr_payload    text,
  sent_day      date,
  sent_today    int not null default 0,
  created_by    uuid references person(id),
  created_at    timestamptz not null default now(),
  disabled_at   timestamptz,
  note          text
);
create index if not exists wa_bridge_live_idx on wa_bridge (state, last_seen_at);

-- a short log, so "it broke" has a when and a why rather than a feeling
create table if not exists wa_bridge_event (
  id        uuid primary key default gen_random_uuid(),
  bridge_id uuid not null references wa_bridge(id) on delete cascade,
  at        timestamptz not null default now(),
  kind      text not null,
  detail    text
);
create index if not exists wa_bridge_event_idx on wa_bridge_event (bridge_id, at desc);

alter table wa_bridge enable row level security;
alter table wa_bridge_event enable row level security;

-- which bridge sent a message, so a bad device is identifiable
alter table wa_outbox add column if not exists bridge_id uuid references wa_bridge(id);

-- --------------------------------------------------------- the pacing
-- The owner asked for it to be kept quiet. These are the numbers that do
-- that: a gap between messages, a random extra so the gap is not a
-- metronome, a burst ceiling per poll, and a per-device daily limit well
-- under what a person would plausibly send by hand.
insert into app_setting (key, value, plain_language, group_name, secret, editable_by) values
  ('whatsapp_web_gap_seconds', '14',
   'Seconds to wait between two WhatsApp messages from the same device.',
   'WhatsApp', false, 'ADMIN'),
  ('whatsapp_web_jitter_seconds', '9',
   'A random extra wait, up to this many seconds, so the sending is not perfectly regular.',
   'WhatsApp', false, 'ADMIN'),
  ('whatsapp_web_burst', '4',
   'The most messages one device may take in a single poll.',
   'WhatsApp', false, 'ADMIN'),
  ('whatsapp_web_daily_per_device', '180',
   'The most messages one device may send in a day, whatever else happens.',
   'WhatsApp', false, 'ADMIN'),
  ('whatsapp_web_retry_minutes', '5',
   'How long to wait before reattempting after the link breaks.',
   'WhatsApp', false, 'ADMIN'),
  ('whatsapp_web_stale_seconds', '150',
   'A device that has not checked in for this long is treated as offline.',
   'WhatsApp', false, 'ADMIN')
on conflict (key) do nothing;

-- ------------------------------------------------------- alert plumbing
-- Raising the same alert every minute must produce one alert with a count,
-- not a wall. Resolving is by the same key, so whatever raised it can also
-- clear it without knowing the id.
create or replace function ops_alert_raise(
  p_kind text, p_title text, p_dedupe_key text,
  p_severity text default 'WARN', p_detail text default null,
  p_action_hint text default null, p_retry_at timestamptz default null,
  p_entity_type text default null, p_entity_id uuid default null,
  p_for_role text default 'ADMIN')
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_id uuid;
begin
  insert into ops_alert (kind, severity, title, detail, action_hint, for_role,
                         entity_type, entity_id, dedupe_key, retry_at)
  values (p_kind, p_severity, p_title, p_detail, p_action_hint, p_for_role,
          p_entity_type, p_entity_id, p_dedupe_key, p_retry_at)
  on conflict (dedupe_key) where resolved_at is null
  do update set last_seen_at = now(),
                occurrences  = ops_alert.occurrences + 1,
                detail       = coalesce(excluded.detail, ops_alert.detail),
                retry_at     = coalesce(excluded.retry_at, ops_alert.retry_at),
                severity     = excluded.severity
  returning id into v_id;
  return v_id;
end $function$;

create or replace function ops_alert_resolve(p_dedupe_key text, p_note text default null)
returns int
language sql
security definer
set search_path to 'public'
as $$
  with done as (
    update ops_alert set resolved_at = now(), resolved_note = p_note
     where dedupe_key = p_dedupe_key and resolved_at is null
    returning 1)
  select count(*)::int from done
$$;

create or replace function ops_alert_open(p_role text default null)
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'kind', a.kind, 'severity', a.severity,
           'title', a.title, 'detail', a.detail, 'action', a.action_hint,
           'since', a.opened_at, 'seen', a.last_seen_at,
           'times', a.occurrences, 'retry_at', a.retry_at,
           'acknowledged', a.acknowledged_at is not null)
         order by case a.severity when 'URGENT' then 0 when 'WARN' then 1 else 2 end,
                  a.opened_at), '[]'::jsonb)
  from ops_alert a
  where a.resolved_at is null
    and (p_role is null or a.for_role = p_role)
$$;

create or replace function ops_alert_ack(p_actor uuid, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_role role_kind;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Only an administrator can take an operational alert.');
  end if;
  update ops_alert set acknowledged_by = p_actor, acknowledged_at = now()
   where id = p_id and resolved_at is null;
  return jsonb_build_object('ok', true);
end $function$;

revoke all on function ops_alert_raise(text,text,text,text,text,text,timestamptz,text,uuid,text) from public, anon, authenticated;
revoke all on function ops_alert_resolve(text,text) from public, anon, authenticated;
revoke all on function ops_alert_open(text) from public, anon, authenticated;
revoke all on function ops_alert_ack(uuid,uuid) from public, anon, authenticated;

-- ------------------------------------------------------ the bridge half
-- A device proves itself with a token it was given once; the token is
-- stored hashed, exactly like a person's session.

create or replace function wa_bridge_create(p_actor uuid, p_name text,
                                            p_kind text default 'laptop')
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_role role_kind; v_token text; v_id uuid;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Adding a sending device is an administrator''s to do.');
  end if;
  if coalesce(trim(p_name),'') = '' then
    return jsonb_build_object('error','no_name',
      'reason','Give the device a name you will recognise later.');
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into wa_bridge (name, device_kind, token_hash, created_by)
  values (trim(p_name), coalesce(nullif(p_kind,''),'laptop'),
          encode(extensions.digest(v_token, 'sha256'), 'hex'), p_actor)
  returning id into v_id;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'WA_BRIDGE_CREATED', 'wa_bridge', v_id::text,
          jsonb_build_object('name', trim(p_name), 'kind', p_kind));

  -- the only time the token is ever readable
  return jsonb_build_object('id', v_id, 'token', v_token, 'name', trim(p_name));
end $function$;

create or replace function wa_bridge_by_token(p_token text)
returns wa_bridge
language sql
stable security definer
set search_path to 'public'
as $$
  select * from wa_bridge
   where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
     and disabled_at is null
   limit 1
$$;

-- The device says what it is doing. This is also what clears or raises the
-- alerts, because the device is the only thing that knows.
create or replace function wa_bridge_heartbeat(
  p_token text, p_state text, p_phone text default null, p_detail text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare b wa_bridge; v_retry int; v_was text;
begin
  select * into b from wa_bridge_by_token(p_token);
  if b.id is null then
    return jsonb_build_object('error','unknown_device');
  end if;
  v_was := b.state;
  v_retry := coalesce(nullif((select value from app_setting
                               where key='whatsapp_web_retry_minutes'),''),'5')::int;

  update wa_bridge set
    state        = case when p_state in ('NEEDS_QR','READY','STALE') then p_state else state end,
    phone_number = coalesce(nullif(p_phone,''), phone_number),
    last_seen_at = now(),
    qr_payload   = case when p_state = 'READY' then null else qr_payload end,
    note         = coalesce(p_detail, note)
   where id = b.id;

  if p_state <> v_was then
    insert into wa_bridge_event (bridge_id, kind, detail)
    values (b.id, p_state, p_detail);
  end if;

  if p_state = 'READY' then
    perform ops_alert_resolve('wa_bridge_down:' || b.id::text, 'The device reconnected.');
    perform ops_alert_resolve('wa_bridge_qr:'   || b.id::text, 'The code was scanned.');
  elsif p_state = 'STALE' then
    -- a break: say when it will try again rather than leaving it hanging
    perform ops_alert_raise(
      'WHATSAPP_BRIDGE_DOWN',
      'WhatsApp sending device "' || b.name || '" has dropped its link',
      'wa_bridge_down:' || b.id::text,
      'URGENT',
      coalesce(p_detail, 'The device lost its WhatsApp session.'),
      'It will reattempt by itself. If it keeps failing, open the device and '
      'check it is running and online. Messages are held meanwhile, not lost.',
      now() + make_interval(mins => v_retry),
      'wa_bridge', b.id);
  end if;

  return jsonb_build_object('ok', true, 'state', p_state,
    'retryMinutes', v_retry,
    'gapSeconds', coalesce(nullif((select value from app_setting where key='whatsapp_web_gap_seconds'),''),'14')::int,
    'jitterSeconds', coalesce(nullif((select value from app_setting where key='whatsapp_web_jitter_seconds'),''),'9')::int);
end $function$;

-- wa_bridge_qr was first written taking only the code string. It now also
-- takes the picture the device draws of it; the current form is further
-- down, under "the code as a picture".

revoke all on function wa_bridge_create(uuid,text,text) from public, anon, authenticated;
revoke all on function wa_bridge_by_token(text) from public, anon, authenticated;
revoke all on function wa_bridge_heartbeat(text,text,text,text) from public, anon, authenticated;

-- ------------------------------------------------------------ the work
-- Handing work to a device, at a pace that does not look like a machine.
create or replace function wa_bridge_claim(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  b wa_bridge;
  v_gap int; v_jit int; v_burst int; v_per_device int; v_stale int;
  v_global_cap int; v_global_sent int; v_room int; v_wait int;
  v_rows jsonb;
begin
  select * into b from wa_bridge_by_token(p_token);
  if b.id is null then return jsonb_build_object('error','unknown_device'); end if;

  v_gap        := coalesce(nullif((select value from app_setting where key='whatsapp_web_gap_seconds'),''),'14')::int;
  v_jit        := coalesce(nullif((select value from app_setting where key='whatsapp_web_jitter_seconds'),''),'9')::int;
  v_burst      := coalesce(nullif((select value from app_setting where key='whatsapp_web_burst'),''),'4')::int;
  v_per_device := coalesce(nullif((select value from app_setting where key='whatsapp_web_daily_per_device'),''),'180')::int;
  v_stale      := coalesce(nullif((select value from app_setting where key='whatsapp_web_stale_seconds'),''),'150')::int;

  update wa_bridge set last_seen_at = now() where id = b.id;

  if b.state <> 'READY' then
    return jsonb_build_object('messages','[]'::jsonb,'state',b.state,
      'gapSeconds',v_gap,'jitterSeconds',v_jit,
      'reason','not_linked');
  end if;

  -- the day rolls over on its own
  if b.sent_day is distinct from current_date then
    update wa_bridge set sent_day = current_date, sent_today = 0 where id = b.id;
    b.sent_today := 0;
  end if;

  -- do not send faster than a person plausibly would
  v_wait := greatest(0, v_gap - extract(epoch from (now() - coalesce(b.last_sent_at, 'epoch'::timestamptz)))::int);
  if v_wait > 0 then
    return jsonb_build_object('messages','[]'::jsonb,'state','READY',
      'gapSeconds',v_gap,'jitterSeconds',v_jit,'waitSeconds',v_wait,'reason','pacing');
  end if;

  v_global_cap  := coalesce(nullif((select value from app_setting where key='whatsapp_daily_cap'),''),'1000')::int;
  insert into wa_budget (day, cap) values (current_date, v_global_cap)
    on conflict (day) do nothing;
  select recipients_sent into v_global_sent from wa_budget where day = current_date;

  v_room := least(v_burst, v_per_device - b.sent_today, v_global_cap - coalesce(v_global_sent,0));
  if v_room <= 0 then
    return jsonb_build_object('messages','[]'::jsonb,'state','READY',
      'gapSeconds',v_gap,'jitterSeconds',v_jit,'reason','daily_cap_reached');
  end if;

  with picked as (
    update wa_outbox o set attempts = o.attempts + 1, bridge_id = b.id
     where o.id in (
       select id from wa_outbox
        where state = 'QUEUED' and not_before <= now()
        order by not_before
        limit v_room
        for update skip locked)
    returning o.id, o.recipient, o.body, o.template_key)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'to', recipient, 'body', body, 'template', template_key)), '[]'::jsonb)
    into v_rows from picked;

  return jsonb_build_object('messages', v_rows, 'state','READY',
    'gapSeconds', v_gap, 'jitterSeconds', v_jit);
end $function$;

-- What the device saw. A failure it can retry is held for the configured
-- few minutes rather than backed off for ever.
create or replace function wa_bridge_result(
  p_token text, p_id uuid, p_ok boolean,
  p_provider_msg_id text default null, p_error text default null,
  p_permanent boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare b wa_bridge; v_retry int; v_attempts int;
begin
  select * into b from wa_bridge_by_token(p_token);
  if b.id is null then return jsonb_build_object('error','unknown_device'); end if;

  v_retry := coalesce(nullif((select value from app_setting
                               where key='whatsapp_web_retry_minutes'),''),'5')::int;

  if p_ok then
    perform wa_sent(p_id, p_provider_msg_id);
    update wa_bridge set sent_today = sent_today + 1, sent_day = current_date,
                         last_sent_at = now(), last_seen_at = now()
     where id = b.id;
    return jsonb_build_object('ok', true);
  end if;

  select attempts into v_attempts from wa_outbox where id = p_id;
  if p_permanent or v_attempts >= 5 then
    update wa_outbox set state='ABANDONED', last_error=p_error where id = p_id;
  else
    update wa_outbox set state='QUEUED', last_error=p_error,
           not_before = now() + make_interval(mins => v_retry)
     where id = p_id;
  end if;
  update wa_bridge set last_seen_at = now() where id = b.id;
  insert into wa_bridge_event (bridge_id, kind, detail) values (b.id, 'SEND_FAILED', p_error);
  return jsonb_build_object('ok', false, 'retryMinutes', v_retry);
end $function$;

-- ------------------------------------------------ the provider knows itself
create or replace function wa_bridges_live()
returns int
language sql
stable security definer
set search_path to 'public'
as $$
  select count(*)::int from wa_bridge
   where state = 'READY' and disabled_at is null
     and last_seen_at > now() - make_interval(secs =>
       coalesce(nullif((select value from app_setting where key='whatsapp_web_stale_seconds'),''),'150')::int)
$$;

-- A device that has stopped checking in is offline, and that is worth an
-- alert because nothing will send until somebody notices.
create or replace function wa_bridge_sweep()
returns int
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_stale int; n int := 0; r record; v_retry int;
begin
  v_stale := coalesce(nullif((select value from app_setting where key='whatsapp_web_stale_seconds'),''),'150')::int;
  v_retry := coalesce(nullif((select value from app_setting where key='whatsapp_web_retry_minutes'),''),'5')::int;

  for r in
    select * from wa_bridge
     where disabled_at is null and state in ('READY','NEEDS_QR')
       and (last_seen_at is null or last_seen_at < now() - make_interval(secs => v_stale))
  loop
    update wa_bridge set state = 'STALE' where id = r.id;
    insert into wa_bridge_event (bridge_id, kind, detail)
    values (r.id, 'STALE', 'Stopped checking in.');
    perform ops_alert_raise(
      'WHATSAPP_BRIDGE_DOWN',
      'WhatsApp sending device "' || r.name || '" has stopped responding',
      'wa_bridge_down:' || r.id::text,
      'URGENT',
      'It last checked in ' || coalesce(to_char(r.last_seen_at, 'DD Mon HH24:MI'), 'never') || '.',
      'Open that device and check the bridge is running and online. Messages are '
      'held in the queue meanwhile, not lost.',
      now() + make_interval(mins => v_retry),
      'wa_bridge', r.id);
    n := n + 1;
  end loop;
  return n;
end $function$;

revoke all on function wa_bridge_claim(text) from public, anon, authenticated;
revoke all on function wa_bridge_result(text,uuid,boolean,text,text,boolean) from public, anon, authenticated;
revoke all on function wa_bridges_live() from public, anon, authenticated;
revoke all on function wa_bridge_sweep() from public, anon, authenticated;

-- -------------------------------------------------- a third provider
-- whatsapp_web joins meta and twilio as a provider. It is configured by
-- linking a device rather than by pasting a key, so "ready" means a device
-- is linked and checking in, not that a token exists.
create or replace function wa_status()
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $$
  with s as (select key, value from app_setting where key like 'whatsapp%'),
  p as (select coalesce(nullif((select value from s where key='whatsapp_provider'), ''), '') as provider)
  select jsonb_build_object(
    'provider',  nullif((select provider from p), ''),
    'from',      nullif((select value from s where key='whatsapp_from'), ''),
    'account',   nullif((select value from s where key='whatsapp_account'), ''),
    'countryCode', coalesce(nullif((select value from s where key='whatsapp_country_code'),''), '91'),
    'mirror',    coalesce(nullif((select value from s where key='whatsapp_mirror'),''), 'all'),
    'tokenSet',  coalesce(nullif((select value from s where key='whatsapp_token'), ''), '') <> '',
    'cap',       coalesce(nullif((select value from s where key='whatsapp_daily_cap'),''),'1000')::int,
    'reachable', (select count(*) from person where superseded_by is null and mobile is not null),
    'devices',   (select provider from p) = 'whatsapp_web',
    'bridgesLive', wa_bridges_live(),
    'bridges',   coalesce((select jsonb_agg(jsonb_build_object(
                    'id', b.id, 'name', b.name, 'kind', b.device_kind,
                    'state', b.state, 'phone', b.phone_number,
                    'lastSeen', b.last_seen_at, 'sentToday', b.sent_today,
                    'hasQr', b.qr_payload is not null)
                  order by b.created_at)
                  from wa_bridge b where b.disabled_at is null), '[]'::jsonb),
    'pacing',    jsonb_build_object(
                   'gapSeconds',    coalesce(nullif((select value from s where key='whatsapp_web_gap_seconds'),''),'14')::int,
                   'jitterSeconds', coalesce(nullif((select value from s where key='whatsapp_web_jitter_seconds'),''),'9')::int,
                   'perDevice',     coalesce(nullif((select value from s where key='whatsapp_web_daily_per_device'),''),'180')::int,
                   'retryMinutes',  coalesce(nullif((select value from s where key='whatsapp_web_retry_minutes'),''),'5')::int),
    'ready',     case (select provider from p)
                   when '' then false
                   when 'whatsapp_web' then wa_bridges_live() > 0
                   else coalesce(nullif((select value from s where key='whatsapp_from'), ''), '') <> ''
                    and coalesce(nullif((select value from s where key='whatsapp_token'), ''), '') <> ''
                 end,
    'queued',    (select count(*) from wa_outbox where state='QUEUED'),
    'deferred',  (select count(*) from wa_outbox where state='DEFERRED'),
    'abandoned', (select count(*) from wa_outbox where state='ABANDONED'),
    'sent',      (select count(*) from wa_outbox where state='SENT'),
    'sentToday', coalesce((select recipients_sent from wa_budget where day = current_date), 0),
    'lastError', (select last_error from wa_outbox
                   where last_error is not null order by created_at desc limit 1),
    'recent',    coalesce((select jsonb_agg(r order by r->>'created_at' desc) from (
                   select jsonb_build_object(
                     'template_key', o.template_key, 'recipient', o.recipient,
                     'state', o.state, 'attempts', o.attempts, 'sent_at', o.sent_at,
                     'last_error', o.last_error, 'created_at', o.created_at) as r
                   from wa_outbox o order by o.created_at desc limit 10) q), '[]'::jsonb)
  )
$$;

-- The server-side drain must not race the devices for the same rows.
create or replace function wa_claim(p_limit int default 25)
returns setof wa_outbox
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_cap int; v_sent int; v_room int;
begin
  -- whatsapp_web is pulled by the linked device, not pushed from here
  if coalesce((select value from app_setting where key='whatsapp_provider'),'') = 'whatsapp_web' then
    return;
  end if;
  if not (wa_status()->>'ready')::boolean then
    return;
  end if;

  insert into wa_budget (day, cap)
  values (current_date,
          coalesce(nullif((select value from app_setting where key='whatsapp_daily_cap'),''),'1000')::int)
  on conflict (day) do nothing;

  select cap, recipients_sent into v_cap, v_sent from wa_budget where day = current_date;
  v_room := greatest(v_cap - v_sent, 0);
  if v_room = 0 then return; end if;

  return query
  update wa_outbox o set attempts = o.attempts + 1
   where o.id in (
     select id from wa_outbox
      where state = 'QUEUED' and not_before <= now()
      order by not_before
      limit least(p_limit, v_room)
      for update skip locked)
  returning o.*;
end $function$;

-- and the provider list grows by one
create or replace function wa_configure(
  p_actor uuid,
  p_provider text default null, p_from text default null,
  p_account text default null,  p_token text default null,
  p_cap text default null,      p_country_code text default null,
  p_mirror text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_role role_kind; v_changed text[] := '{}';
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','WhatsApp settings are an administrator''s to change.');
  end if;

  if p_provider is not null then
    if p_provider <> '' and p_provider not in ('meta','twilio','whatsapp_web') then
      return jsonb_build_object('error','unknown_provider',
        'reason','Known providers are meta, twilio and whatsapp_web.');
    end if;
    update app_setting set value = p_provider, updated_by = p_actor, updated_at = now()
     where key = 'whatsapp_provider';
    v_changed := array_append(v_changed, 'provider');
  end if;

  if p_from is not null then
    update app_setting set value = p_from, updated_by = p_actor, updated_at = now()
     where key = 'whatsapp_from';
    v_changed := array_append(v_changed, 'from');
  end if;

  if p_account is not null then
    update app_setting set value = p_account, updated_by = p_actor, updated_at = now()
     where key = 'whatsapp_account';
    v_changed := array_append(v_changed, 'account');
  end if;

  if coalesce(p_token,'') <> '' then
    update app_setting set value = p_token, updated_by = p_actor, updated_at = now()
     where key = 'whatsapp_token';
    v_changed := array_append(v_changed, 'token');
  end if;

  if p_country_code is not null and p_country_code ~ '^\d{1,4}$' then
    update app_setting set value = p_country_code, updated_by = p_actor, updated_at = now()
     where key = 'whatsapp_country_code';
    v_changed := array_append(v_changed, 'country_code');
  end if;

  if p_mirror is not null then
    update app_setting set value = coalesce(nullif(trim(p_mirror),''),'all'),
           updated_by = p_actor, updated_at = now()
     where key = 'whatsapp_mirror';
    v_changed := array_append(v_changed, 'mirror');
  end if;

  if p_cap is not null and p_cap ~ '^\d+$' then
    update app_setting set value = p_cap, updated_by = p_actor, updated_at = now()
     where key = 'whatsapp_daily_cap';
    insert into wa_budget (day, cap) values (current_date, p_cap::int)
      on conflict (day) do update set cap = excluded.cap;
    v_changed := array_append(v_changed, 'cap');
  end if;

  update app_setting set value =
    case when (wa_status()->>'ready')::boolean then 'Connected' else 'Not connected' end
   where key = 'whatsapp';

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'WHATSAPP_CONFIGURED', 'app_setting', 'whatsapp',
          jsonb_build_object('changed', v_changed));

  return wa_status() || jsonb_build_object('changed', to_jsonb(v_changed));
end $function$;

revoke all on function wa_status() from public, anon, authenticated;
revoke all on function wa_claim(int) from public, anon, authenticated;
revoke all on function wa_configure(uuid,text,text,text,text,text,text,text) from public, anon, authenticated;

-- ------------------------------------------------------- the every-minute look
-- A device that stops checking in has to be noticed by something other than
-- the device. Every minute, because a break should surface in about the time
-- it takes to walk to the machine.
insert into job_config (job_key, enabled, cron) values ('WA_BRIDGE_SWEEP', true, '* * * * *')
on conflict (job_key) do nothing;

create or replace function crux_wa_bridge_tick()
returns int
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not coalesce((select enabled from job_config where job_key='WA_BRIDGE_SWEEP'), true) then
    return 0;
  end if;
  return wa_bridge_sweep();
end $function$;

select cron.schedule('crux-wa-bridge', '* * * * *', 'select crux_wa_bridge_tick()');

-- --------------------------------------------------------- device admin
-- An administrator can look at the code a device is showing, and can retire
-- a device. Looking is separate from the status call because a QR is worth
-- fetching fresh - it expires in about a minute. (wa_bridge_peek_qr is
-- defined below, in its final form.)

create or replace function wa_bridge_disable(p_actor uuid, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_role role_kind; b wa_bridge;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Retiring a sending device is an administrator''s to do.');
  end if;

  select * into b from wa_bridge where id = p_id;
  if b.id is null then return jsonb_build_object('error','no_such_device'); end if;

  update wa_bridge set disabled_at = now(), state = 'DISABLED',
                       qr_payload = null, token_hash = 'retired:' || id::text
   where id = p_id;

  -- anything it was holding goes back to the queue for another device
  update wa_outbox set state = 'QUEUED', not_before = now()
   where bridge_id = p_id and state = 'QUEUED';

  perform ops_alert_resolve('wa_bridge_down:' || p_id::text, 'The device was retired.');
  perform ops_alert_resolve('wa_bridge_qr:'   || p_id::text, 'The device was retired.');

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'WA_BRIDGE_DISABLED', 'wa_bridge', p_id::text,
          jsonb_build_object('name', b.name));

  return jsonb_build_object('ok', true, 'name', b.name);
end $function$;

revoke all on function wa_bridge_disable(uuid,uuid) from public, anon, authenticated;

-- --------------------------------------------------- the code as a picture
-- The device renders its own code to an image and sends that. The
-- alternative was shipping a QR encoder into the page, or worse, handing the
-- linking credential to a public QR-image service to draw for us.
alter table wa_bridge add column if not exists qr_image text;

create or replace function wa_bridge_qr(p_token text, p_qr text, p_qr_image text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare b wa_bridge;
begin
  select * into b from wa_bridge_by_token(p_token);
  if b.id is null then return jsonb_build_object('error','unknown_device'); end if;

  update wa_bridge set qr_payload = p_qr, qr_image = p_qr_image, last_qr_at = now(),
                       state = 'NEEDS_QR', last_seen_at = now()
   where id = b.id;

  insert into wa_bridge_event (bridge_id, kind, detail) values (b.id, 'NEEDS_QR', null);

  perform ops_alert_raise(
    'WHATSAPP_QR',
    'Scan the WhatsApp code for "' || b.name || '"',
    'wa_bridge_qr:' || b.id::text,
    'URGENT',
    'The device is waiting to be linked and cannot send until it is.',
    'Open the WhatsApp screen and press "Show the code", then on the phone that '
    'owns the company number: WhatsApp, Settings, Linked devices, Link a device. '
    'The code changes every minute or so.',
    null, 'wa_bridge', b.id);

  return jsonb_build_object('ok', true);
end $function$;

-- clear the image too when the link succeeds
create or replace function wa_bridge_heartbeat(
  p_token text, p_state text, p_phone text default null, p_detail text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare b wa_bridge; v_retry int; v_was text;
begin
  select * into b from wa_bridge_by_token(p_token);
  if b.id is null then
    return jsonb_build_object('error','unknown_device');
  end if;
  v_was := b.state;
  v_retry := coalesce(nullif((select value from app_setting
                               where key='whatsapp_web_retry_minutes'),''),'5')::int;

  update wa_bridge set
    state        = case when p_state in ('NEEDS_QR','READY','STALE') then p_state else state end,
    phone_number = coalesce(nullif(p_phone,''), phone_number),
    last_seen_at = now(),
    qr_payload   = case when p_state = 'READY' then null else qr_payload end,
    qr_image     = case when p_state = 'READY' then null else qr_image end,
    note         = coalesce(p_detail, note)
   where id = b.id;

  if p_state <> v_was then
    insert into wa_bridge_event (bridge_id, kind, detail)
    values (b.id, p_state, p_detail);
  end if;

  if p_state = 'READY' then
    perform ops_alert_resolve('wa_bridge_down:' || b.id::text, 'The device reconnected.');
    perform ops_alert_resolve('wa_bridge_qr:'   || b.id::text, 'The code was scanned.');
  elsif p_state = 'STALE' then
    perform ops_alert_raise(
      'WHATSAPP_BRIDGE_DOWN',
      'WhatsApp sending device "' || b.name || '" has dropped its link',
      'wa_bridge_down:' || b.id::text,
      'URGENT',
      coalesce(p_detail, 'The device lost its WhatsApp session.'),
      'It will reattempt by itself. If it keeps failing, open the device and '
      'check it is running and online. Messages are held meanwhile, not lost.',
      now() + make_interval(mins => v_retry),
      'wa_bridge', b.id);
  end if;

  return jsonb_build_object('ok', true, 'state', p_state,
    'retryMinutes', v_retry,
    'gapSeconds', coalesce(nullif((select value from app_setting where key='whatsapp_web_gap_seconds'),''),'14')::int,
    'jitterSeconds', coalesce(nullif((select value from app_setting where key='whatsapp_web_jitter_seconds'),''),'9')::int);
end $function$;

create or replace function wa_bridge_peek_qr(p_actor uuid, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_role role_kind; b wa_bridge;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Linking a sending device is an administrator''s to do.');
  end if;

  select * into b from wa_bridge where id = p_id and disabled_at is null;
  if b.id is null then return jsonb_build_object('error','no_such_device'); end if;

  return jsonb_build_object(
    'id', b.id, 'name', b.name, 'state', b.state,
    'qr', b.qr_payload, 'image', b.qr_image,
    'age', case when b.last_qr_at is null then null
                else extract(epoch from (now() - b.last_qr_at))::int end,
    'lastSeen', b.last_seen_at);
end $function$;

revoke all on function wa_bridge_qr(text,text,text) from public, anon, authenticated;
revoke all on function wa_bridge_heartbeat(text,text,text,text) from public, anon, authenticated;
revoke all on function wa_bridge_peek_qr(uuid,uuid) from public, anon, authenticated;
drop function if exists wa_bridge_qr(text,text);
