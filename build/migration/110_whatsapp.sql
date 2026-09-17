-- =====================================================================
-- 110 · WhatsApp, on the same terms as mail
--
-- A separate outbox rather than a channel column on the mail one: an
-- e-mail has a subject and a cc, a WhatsApp message has neither, and it
-- has a template name and a 24-hour window that e-mail does not. Two
-- tables that each say what their channel actually carries beats one
-- table half of whose columns are always null.
--
-- What is shared is the discipline: one row per (template, recipient,
-- entity, scope) so a storm of triggers still sends one message; a daily
-- cap; and nothing leaves the queue until an administrator has
-- configured a sender, so an unconfigured tool holds its messages rather
-- than losing them.
--
-- This file carries the schema and the behaviour that is particular to
-- this tool. wa_status, wa_configure, wa_test and wa_forget_secrets are
-- the direct counterparts of the mail_* functions and live in the
-- Supabase migration history under whatsapp_functions,
-- whatsapp_queue_functions and whatsapp_configure_takes_mirror.
-- =====================================================================

create table if not exists wa_budget (
  day             date primary key,
  recipients_sent int not null default 0,
  cap             int not null default 1000,
  reserve         int not null default 0
);

create table if not exists wa_outbox (
  id              uuid primary key default gen_random_uuid(),
  idempotency_key text not null,
  template_key    text not null,
  entity_type     text,
  entity_id       uuid,
  recipient       text not null,
  body            text not null,
  -- outside the 24-hour window WhatsApp only accepts an approved template,
  -- so a queued message carries one where the business has one registered
  template_name   text,
  template_lang   text default 'en',
  template_vars   jsonb,
  state           outbox_state not null default 'QUEUED',
  attempts        int not null default 0,
  not_before      timestamptz not null default now(),
  sent_at         timestamptz,
  last_error      text,
  provider_msg_id text,
  created_at      timestamptz not null default now()
);

create unique index if not exists wa_outbox_idempotency_uniq on wa_outbox (idempotency_key);
create index if not exists wa_outbox_due_idx on wa_outbox (state, not_before) where state = 'QUEUED';

alter table wa_outbox enable row level security;
alter table wa_budget enable row level security;

-- A number is stored however whoever typed it felt like. This is what makes
-- "9049705664", "90497 05664", "+91 90497 05664" and Excel's "8104660689.0"
-- one recipient, so the idempotency key holds and nobody is messaged twice.
create or replace function wa_e164(p text, p_cc text default null)
returns text
language sql
immutable
set search_path to 'public'
as $$
  with d as (
    select regexp_replace(regexp_replace(coalesce(p,''), '\.0+$', ''), '[^0-9]', '', 'g') as n
  )
  select case
    when d.n = '' then null
    when length(d.n) between 11 and 15 and left(d.n,2) = coalesce(nullif(p_cc,''),'91') then '+' || d.n
    when length(d.n) between 11 and 15 and left(d.n,1) = '0'
      then '+' || coalesce(nullif(p_cc,''),'91') || ltrim(d.n, '0')
    when length(d.n) = 10 then '+' || coalesce(nullif(p_cc,''),'91') || d.n
    when length(d.n) between 11 and 15 then '+' || d.n
    else null
  end
  from d
$$;

-- ------------------------------------------------------------ the mirror
-- What actually makes WhatsApp carry traffic. Rather than edit every
-- function that notifies somebody — ogl_notify passes its template key as a
-- variable, so there is no fixed list to enumerate — the mirror happens
-- where every notification already passes: the moment a row lands in the
-- mail outbox.
--
-- The scope carries the e-mail's own idempotency key, so the storm
-- protection that stops a hundred triggers becoming a hundred e-mails also
-- stops them becoming a hundred messages.
create or replace function outbox_mirror_to_whatsapp()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_policy text; v_mobile text; v_text text;
begin
  v_policy := coalesce(nullif((select value from app_setting where key='whatsapp_mirror'),''), 'all');
  if v_policy = 'off' then return new; end if;
  if v_policy <> 'all'
     and position(new.template_key in v_policy) = 0 then
    return new;
  end if;

  select p.mobile into v_mobile
    from person p
   where p.superseded_by is null
     and lower(p.work_email) = lower(new.recipient)
     and p.mobile is not null
   limit 1;
  if v_mobile is null then return new; end if;

  -- WhatsApp has no subject line, and a body written for e-mail carries
  -- markup. Give the reader the subject, then the text, laid out as it read:
  -- the tags that mean "new line" become one before the rest are stripped.
  v_text := regexp_replace(new.body, '</(p|div|tr|li|h[1-6])>', E'\n', 'gi');
  v_text := regexp_replace(v_text, '<br\s*/?>', E'\n', 'gi');
  v_text := regexp_replace(v_text, '<[^>]+>', '', 'g');
  v_text := replace(replace(replace(replace(replace(v_text,
              '&amp;','&'), '&lt;','<'), '&gt;','>'), '&nbsp;',' '), '&quot;','"');
  v_text := btrim(regexp_replace(v_text, '[ \t]*\n[ \t]*', E'\n', 'g'));
  v_text := regexp_replace(v_text, '\n{3,}', E'\n\n', 'g');
  v_text := new.subject || E'\n\n' || v_text;

  if length(v_text) > 900 then
    v_text := left(v_text, 880) || E'\n\n[...] See the e-mail for the rest.';
  end if;

  perform wa_enqueue(
    new.template_key, v_mobile, v_text,
    new.entity_type, new.entity_id, new.not_before,
    'mirror:' || new.idempotency_key);

  return new;
exception when others then
  -- a mirror must never be the reason an e-mail fails to queue
  return new;
end $function$;

drop trigger if exists outbox_whatsapp_mirror on outbox;
create trigger outbox_whatsapp_mirror
  after insert on outbox
  for each row execute function outbox_mirror_to_whatsapp();

-- ---------------------------------------------------------- the schedule
-- The same minute schedule and the same switch as mail. It asks for nothing
-- when the queue is empty, so an unconfigured tool costs nothing to leave
-- running.
insert into job_config (job_key, enabled, cron) values ('WA_DRAIN', true, '* * * * *')
on conflict (job_key) do nothing;

create or replace function crux_wa_tick()
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_req bigint; v_url text; v_secret text; v_anon text;
begin
  if not coalesce((select enabled from job_config where job_key='WA_DRAIN'), true) then
    return null;
  end if;
  if not exists (select 1 from wa_outbox where state in ('QUEUED','DEFERRED')) then
    return null;
  end if;

  select value into v_url    from app_setting where key = 'function_base_url';
  select value into v_secret from app_setting where key = 'mail_cron_secret';
  select value into v_anon   from app_setting where key = 'anon_key';

  select net.http_post(
    url := v_url || '/wa/drain',
    headers := jsonb_build_object(
      'content-type','application/json',
      'authorization','Bearer ' || v_anon,
      'x-crux-cron', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  ) into v_req;
  return v_req;
end $function$;

-- select cron.schedule('crux-whatsapp', '* * * * *', 'select crux_wa_tick()');
