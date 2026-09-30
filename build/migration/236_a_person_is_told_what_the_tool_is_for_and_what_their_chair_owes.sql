-- A person is told what the tool is for, and what their chair owes (236)
--
-- "Send everyone an email with the link to the app and the user name and the
-- password, also what is that they are supposed to do based on their chair
-- and role. Also this same email must get triggered as soon as a new employee
-- is added by the managers."
--
-- Two different things are being asked for and they need different rules,
-- which is the whole design of this file:
--
--   A ONE-OFF to everybody who already works here, ahead of a demo. Those
--   people have a password that somebody set for them, and telling them what
--   it is, is the point.
--
--   A STANDING welcome that fires whenever HR makes an account. That one runs
--   unattended, for years, to people who have not started yet. A standing job
--   that puts a working password in an inbox is a standing liability: it sits
--   in a mailbox that gets forwarded, backed up and eventually breached, and
--   it is the same password for as long as nobody changes it.
--
-- So the password is a PARAMETER, defaulted OFF. The trigger on a new joiner
-- never passes one and tells them to use Google sign-in instead; the one-off
-- passes one per person. The recurring behaviour is the safe one by default
-- and the unsafe one has to be asked for by name, every time.
--
-- The second rule, which is the same one as migration 235: nothing sends
-- while app_url is unset. An e-mail whose whole purpose is a link, carrying a
-- link that goes nowhere, is worse than no e-mail -- it teaches a hundred
-- people on their first day that the tool is broken.

-- ------------------------------------------------- what this person is for
-- Composed separately from the sending so it can be read, checked and shown
-- to somebody before a hundred copies go out.
create or replace function person_welcome_body(p_person uuid,
                                               p_sign_in text default null)
returns text
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  p person; v_chair chair; v_mgr text; v_level text; v_note text;
  v_link text; v_screens text; v_measures text; v_cycle perf_cycle;
  b text;
begin
  select * into p from person where id = p_person;
  if p.id is null then return null; end if;

  v_link := app_link();
  if v_link is null then return null; end if;

  select c.* into v_chair from chair_holder h join chair c on c.id = h.chair_id
   where h.person_id = p_person and h.to_date is null
   order by h.is_primary desc limit 1;

  select m.full_name into v_mgr from person m where m.id = p.manager_id;

  v_level := access_level_of(p_person);
  select label || ' -- ' || note into v_note
    from access_level where level = v_level;

  select string_agg(initcap(replace(s, '-', ' ')), ', ' order by s)
    into v_screens
    from unnest(access_screens(p_person)) s;

  -- The newest cycle this person actually holds measures in, rather than the
  -- newest cycle there is. Those are not the same thing: a person seated
  -- mid-month, or two cycles opened for one month, would otherwise be told
  -- they have nothing to file when they do.
  select c.* into v_cycle from perf_cycle c
   where c.period_kind = 'MONTH'
     and exists (select 1 from perf_assignment a
                  where a.person_id = p_person and a.cycle_id = c.id
                    and a.part_of_id is null)
   order by c.period_start desc limit 1;

  -- What they are actually measured on, with the target and how often it is
  -- owed. This is the part that answers "what am I supposed to do": a list of
  -- screens tells somebody where to click, and this tells them what for.
  select string_agg(
           '  - ' || a.name
           -- FM drops the trailing zeros and leaves the point behind, so a
           -- whole number reads "target 300." with a full stop in the middle
           -- of the sentence. rtrim takes it off.
           || case when a.target_value is not null
                   then ', target '
                        || rtrim(trim(to_char(a.target_value, 'FM999999999.99')), '.')
                        || coalesce(' ' || perf_unit_plain(a.unit), '')
                   else '' end
           || case when upper(coalesce(a.cadence::text,'')) like 'DAIL%'
                        then ' -- every working day'
                   when upper(coalesce(a.cadence::text,'')) like 'WEEK%'
                        then ' -- weekly'
                   else ' -- monthly' end,
           E'\n' order by a.name)
    into v_measures
    from perf_assignment a
   where a.person_id = p_person and a.cycle_id = v_cycle.id
     and a.part_of_id is null;

  b := 'Hello ' || split_part(p.full_name, ' ', 1) || E',\n\n'
    || 'Crux is where your work is recorded and where your performance and '
    || 'bonus are worked out. Everything about how you are measured is on it, '
    || 'including the arithmetic, so nothing about your score should ever be '
    || 'a surprise.' || E'\n\n'

    || 'Open it here: ' || v_link || E'\n\n'

    || 'Signing in' || E'\n'
    || 'Your user name is your work address, ' || p.work_email || '.' || E'\n'
    || coalesce(p_sign_in,
         'Use the Google button and sign in with that address -- there is no '
         || 'separate password to remember.') || E'\n\n'

    || 'Your chair' || E'\n'
    || coalesce(v_chair.title, 'You are not yet seated in a chair, so no '
                || 'measures have reached you. HR will place you.')
    || coalesce(E'\nYou report to ' || v_mgr || '.', '')
    || E'\n\n'

    || case when coalesce(v_measures, '') <> '' then
         'What you file, and how often' || E'\n'
         || v_measures || E'\n\n'
         || 'File these on the Performance and appraisal screen. The number is '
         || 'for the day it belongs to -- filing it late does not make it a '
         || 'later day''s number, and the days you file are themselves one of '
         || 'the things measured.' || E'\n\n'
       else
         'No measures have been set for you yet. Your manager sets them at the '
         || 'start of the month, and until then there is nothing for you to '
         || 'file.' || E'\n\n'
       end

    || 'What you can open' || E'\n'
    || coalesce(v_note, 'Your own work.') || E'\n'
    || coalesce('Screens: ' || v_screens || '.', '') || E'\n\n'

    || case when v_level in ('branch','team','hr','admin','partner') then
         'Because you have people under you, you also set their targets, hold '
         || 'their monthly reviews and score them. Their numbers climb into '
         || 'yours, so their filing is your filing.' || E'\n\n'
       else '' end

    || 'If anything here is wrong -- the chair, the manager, the measures -- '
    || 'tell HR rather than working around it. All of it is what your bonus is '
    || 'calculated from.' || E'\n';

  return b;
end $function$;

comment on function person_welcome_body(uuid,text) is
  'The welcome message for one person: the link, how they sign in, their '
  'chair, what they file and how often, and what their level may open. '
  'Null when app_url is unset, because a welcome whose point is a link '
  'cannot be sent without one.';

-- --------------------------------------------------------------- send one
create or replace function person_welcome_send(p_actor uuid, p_person uuid,
                                               p_sign_in text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_actor person; p person; b text; v_key text;
begin
  select * into v_actor from person where id = p_actor;
  if v_actor.id is null then
    return jsonb_build_object('error','not_permitted','reason','Who is asking?');
  end if;
  -- HR, an administrator, or the person's own manager. A welcome names a
  -- chair and a manager, so whoever sends it is asserting both.
  if v_actor.app_role <> 'ADMIN'
     and coalesce(v_actor.department,'') <> 'Human Resources'
     and not org_may_add_under(p_actor, p_person) then
    return jsonb_build_object('error','not_permitted',
      'reason','Welcoming somebody is HR''s, an administrator''s, or their '
              'own manager''s.');
  end if;

  select * into p from person where id = p_person;
  if p.id is null then return jsonb_build_object('error','no_such_person'); end if;
  if coalesce(btrim(p.work_email),'') = '' then
    return jsonb_build_object('error','no_address',
      'reason', p.full_name || ' has no work address to write to.');
  end if;
  if p.employment_status <> 'ACTIVE' or p.superseded_by is not null then
    return jsonb_build_object('error','not_active',
      'reason','That person is not active.');
  end if;

  b := person_welcome_body(p_person, p_sign_in);
  if b is null then
    return jsonb_build_object('error','no_app_url',
      'reason','Nobody has said where the tool is served from, so this '
              'message would carry a link to nowhere. Set app_url in '
              'Configuration and send again.');
  end if;

  -- Keyed on the person and the day, so re-running a blast is harmless and a
  -- manager clicking twice does not send twice.
  v_key := md5('WELCOME|' || lower(btrim(p.work_email)) || '|' || current_date);

  insert into outbox (idempotency_key, template_key, recipient, subject, body,
                      entity_type, entity_id, not_before, state)
  values (v_key, 'ACTIVATION', lower(btrim(p.work_email)),
          'Your Crux account, and what your chair is measured on',
          b, 'person', p_person, now(), 'QUEUED')
  on conflict (idempotency_key) do nothing;

  if not found then
    return jsonb_build_object('ok', true, 'queued', false,
      'reason','Already sent to ' || p.work_email || ' today.');
  end if;

  insert into person_event (person_id, kind, note, at)
  values (p_person, 'WELCOMED',
          'Welcome and instructions sent by ' || v_actor.full_name, now());

  return jsonb_build_object('ok', true, 'queued', true,
    'to', p.work_email,
    'withPassword', p_sign_in is not null,
    'note', 'Queued for ' || p.full_name || '.');
end $function$;

comment on function person_welcome_send(uuid,uuid,text) is
  'Queue the welcome for one person. p_sign_in replaces the default "use '
  'the Google button" line and is the ONLY way a password reaches the '
  'message -- it is never read from the database and never defaulted on.';

-- --------------------------------------------------------------- send all
-- The one-off. Deliberately not a sweep on a schedule: telling everybody
-- about the tool is something a person decides to do on a day, once.
create or replace function person_welcome_all(p_actor uuid,
                                              p_domain text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_actor person; r record; o jsonb;
  n_sent int := 0; n_skip int := 0; v_why jsonb := '[]'::jsonb;
begin
  select * into v_actor from person where id = p_actor;
  if v_actor.id is null
     or (v_actor.app_role <> 'ADMIN'
         and coalesce(v_actor.department,'') <> 'Human Resources') then
    return jsonb_build_object('error','not_permitted',
      'reason','Writing to everybody is HR''s or an administrator''s.');
  end if;

  if app_link() is null then
    return jsonb_build_object('error','no_app_url',
      'reason','Nobody has said where the tool is served from. Set app_url '
              'first, or a hundred people get a link to nowhere.');
  end if;

  for r in
    select p.id, p.full_name, p.work_email
      from person p
     where p.employment_status = 'ACTIVE' and p.superseded_by is null
       and coalesce(btrim(p.work_email),'') <> ''
       -- A chair is the filter that separates the people who work here from
       -- the client contacts sitting in the same table. Without it this
       -- writes to five hundred bank managers.
       and exists (select 1 from chair_holder h
                    where h.person_id = p.id and h.to_date is null)
       and (p_domain is null or lower(p.work_email) like '%' || lower(p_domain))
     order by p.full_name
  loop
    o := person_welcome_send(p_actor, r.id, null);
    if coalesce((o->>'queued')::boolean, false) then
      n_sent := n_sent + 1;
    else
      n_skip := n_skip + 1;
      v_why := v_why || jsonb_build_object('person', r.full_name,
                          'why', coalesce(o->>'reason', o->>'error'));
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'queued', n_sent, 'skipped', n_skip,
    'skippedWhy', v_why,
    'note', n_sent || ' welcome(s) queued. They leave on the next mail drain.');
end $function$;

comment on function person_welcome_all(uuid,text) is
  'The one-off blast to everybody holding a chair. Only people with a chair, '
  'so it cannot write to the client-bank contacts in the same table.';

-- ------------------------------------------- and whenever HR makes an account
-- The standing half of the request. It fires on the INSERT of a person, which
-- is the one place every route into the company passes through -- person_add,
-- the joiner request HR approves, and a bulk upload alike.
--
-- It never carries a password. It is also silent when app_url is unset rather
-- than failing the insert: a welcome that cannot be written is not a reason to
-- refuse somebody a job.
create or replace function person_welcome_on_create()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare b text; v_key text;
begin
  if new.employment_status <> 'ACTIVE' or new.superseded_by is not null then
    return new;
  end if;
  if coalesce(btrim(new.work_email),'') = '' then return new; end if;

  b := person_welcome_body(new.id, null);
  if b is null then return new; end if;   -- no app_url, so nothing to send

  v_key := md5('WELCOME|' || lower(btrim(new.work_email)) || '|' || current_date);
  insert into outbox (idempotency_key, template_key, recipient, subject, body,
                      entity_type, entity_id, not_before, state)
  values (v_key, 'ACTIVATION', lower(btrim(new.work_email)),
          'Your Crux account, and what your chair is measured on',
          b, 'person', new.id, now(), 'QUEUED')
  on conflict (idempotency_key) do nothing;

  return new;
end $function$;

comment on function person_welcome_on_create() is
  'Sends the welcome when a person is created, by whatever route. Silent '
  'when app_url is unset: a message that cannot be written is not a reason '
  'to refuse somebody a job.';

drop trigger if exists person_welcome_after_insert on person;
create trigger person_welcome_after_insert
  after insert on person
  for each row execute function person_welcome_on_create();

-- ------------------------------------------------------------- the gate
revoke execute on function person_welcome_body(uuid,text) from public, anon, authenticated;
revoke execute on function person_welcome_send(uuid,uuid,text) from public, anon, authenticated;
revoke execute on function person_welcome_all(uuid,text) from public, anon, authenticated;

do $guard$
declare n int; v text;
begin
  select count(*) into n from pg_proc
   where proname in ('person_welcome_body','person_welcome_send',
                     'person_welcome_all','person_welcome_on_create');
  if n <> 4 then
    raise exception 'Migration 236 left % of 4 functions behind', n;
  end if;

  if not exists (select 1 from pg_trigger
                  where tgname = 'person_welcome_after_insert'
                    and not tgisinternal) then
    raise exception 'Migration 236 did not arm the trigger on person';
  end if;

  -- The rule that matters most: silent while nobody has said where the tool
  -- is. If this ever returns a body, every new joiner gets a dead link.
  if coalesce(btrim((select value from app_setting where key='app_url')),'') = ''
     and (select person_welcome_body(id) from person
           where employment_status='ACTIVE' limit 1) is not null then
    raise exception 'Migration 236: a welcome was composed with no app_url set';
  end if;
end $guard$;
