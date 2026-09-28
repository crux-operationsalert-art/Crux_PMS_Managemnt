-- =====================================================================
-- Crux baseline | 40_functions_1.sql | functions, part 1 of 4
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- Ordered by name, not by dependency. Load with check_function_bodies off.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.access_level_of(p_person uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select 'admin' from person p
      where p.id = p_person and p.app_role = 'ADMIN'
        and p.employment_status = 'ACTIVE' and p.superseded_by is null),
    (select cl.level
       from chair_holder h
       join chair ch on ch.id = h.chair_id
       join access_chair_level cl on cl.chair_title = ch.title
      where h.person_id = p_person and h.to_date is null
      order by h.is_primary desc, ch.title
      limit 1),
    (select dl.level from person p
       join access_department_level dl on dl.department = p.department
      where p.id = p_person),
    'exec')
$function$
;

CREATE OR REPLACE FUNCTION public.access_may_open(p_person uuid, p_screen text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when p_screen is null or btrim(p_screen) = '' then false
    when access_level_of(p_person) = 'admin' then true
    else exists (
      select 1 from access_level_screen ls
       where ls.level = access_level_of(p_person)
         and ls.screen = coalesce(
               (select sp.parent from access_screen_parent sp where sp.screen = p_screen),
               p_screen))
  end
$function$
;

CREATE OR REPLACE FUNCTION public.access_policy_questions()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_open  int := 0;
  v_shut  int := 0;
  n int;
  v_detail text;
begin
  -- ------------------------------------------------ 1. the rate master
  -- rates is a child of reports, so every level that carries Reports can read
  -- every client's commercial rate. Finance and the administrator own WRITING
  -- one; reading one is open to six of the eight levels.
  select count(*) into n
    from access_screen_parent
   where screen = 'rates' and parent = 'reports';
  if n > 0 then
    select count(*) into n from person p
     where p.employment_status = 'ACTIVE' and p.superseded_by is null
       and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
       and access_may_open(p.id, 'rates');
    perform ops_alert_raise(
      'ACCESS_POLICY',
      'The rate master is open to everyone who can open Reports',
      'access-policy-rates', 'INFO',
      n || ' people can read every client''s commercial rate, because the rate '
        || 'master is reached from inside Reports and six of the eight scope '
        || 'levels carry Reports. Finance and the administrator own changing a '
        || 'rate; this is about reading one.',
      'If that is right, resolve this. If it is not, move it under Settings, '
        || 'which only HR, Finance and the administrator carry: '
        || 'update access_screen_parent set parent = ''config'' where screen = ''rates'';');
    v_open := v_open + 1;
  else
    update ops_alert set resolved_at = now(),
           resolved_note = 'The rate master no longer follows Reports.'
     where dedupe_key = 'access-policy-rates' and resolved_at is null;
    v_shut := v_shut + (case when found then 1 else 0 end);
  end if;

  -- --------------------------------------- 2. the rule nobody ever read
  -- The published tool declares ADMIN_TABS = { data, mail, whatsapp } and
  -- never reads it. SCREENS gives mail to hr and data to analytics, and
  -- SCREENS is what runs.
  select count(*) into n from access_level_screen
   where (level = 'hr' and screen = 'mail')
      or (level = 'analytics' and screen = 'data');
  if n > 0 then
    perform ops_alert_raise(
      'ACCESS_POLICY',
      'Two screens the design marked administrator-only are not',
      'access-policy-admin-tabs', 'INFO',
      'The tool declares ADMIN_TABS = { data, mail, whatsapp } and never reads '
        || 'it, so the intention is legible and has never run. What runs gives '
        || 'Messaging to HR and Data setup to MIS. What was seeded is what runs.',
      'If the intention was the policy: '
        || 'delete from access_level_screen where (level, screen) in '
        || '((''hr'',''mail''), (''analytics'',''data'')); '
        || 'and take the dead variable out of the page.');
    v_open := v_open + 1;
  else
    update ops_alert set resolved_at = now(),
           resolved_note = 'Messaging and Data setup are the administrator''s now.'
     where dedupe_key = 'access-policy-admin-tabs' and resolved_at is null;
    v_shut := v_shut + (case when found then 1 else 0 end);
  end if;

  -- ------------------------- 3. a permission for a screen nobody can open
  -- places.ts carries mayAssign, which lets a department with a matrix or full
  -- client view assign coverage. No such person's level carries the coverage
  -- screen, so the permission is for a page they cannot open. Before the
  -- services enforced the policy they could reach it by typing the URL; they
  -- can not now, which is the policy working, and the policy may be wrong.
  select count(*), string_agg(distinct p.department, ', ')
    into n, v_detail
    from person p
    join client_view_policy v on v.department = p.department
   where p.employment_status = 'ACTIVE' and p.superseded_by is null
     and v.view_kind in ('matrix','full')
     and not access_may_open(p.id, 'coverage');
  if n > 0 then
    perform ops_alert_raise(
      'ACCESS_POLICY',
      'Operations may assign coverage and cannot open the screen that does it',
      'access-policy-coverage', 'INFO',
      n || ' people in ' || v_detail || ' hold the permission to assign '
        || 'coverage, and not one of them is at a scope level that carries the '
        || 'Places, coverage & owners screen -- which only MIS and the '
        || 'administrator do. The navigation has never offered it to them; '
        || 'until the services enforced the policy they could still reach it by '
        || 'typing the address.',
      'If Operations runs coverage, give the level the screen -- for example: '
        || 'insert into access_level_screen (level, screen) values '
        || '(''branch'',''coverage'') on conflict do nothing; -- and it appears '
        || 'in their navigation. If it does not, the mayAssign check in '
        || 'ops/routes/places.ts is vestigial and should go.');
    v_open := v_open + 1;
  else
    update ops_alert set resolved_at = now(),
           resolved_note = 'Everyone who may assign coverage can open the screen.'
     where dedupe_key = 'access-policy-coverage' and resolved_at is null;
    v_shut := v_shut + (case when found then 1 else 0 end);
  end if;

  return jsonb_build_object('open', v_open, 'resolved', v_shut);
end $function$
;

CREATE OR REPLACE FUNCTION public.access_screens(p_person uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when access_level_of(p_person) = 'admin'
    then (select array_agg(distinct s order by s)
            from (select screen as s from access_level_screen
                  union select screen from access_screen_parent) q)
    else (select coalesce(array_agg(distinct s order by s), '{}'::text[])
            from (
              select ls.screen as s
                from access_level_screen ls
               where ls.level = access_level_of(p_person)
              union
              -- a child screen comes with its parent, which is how the
              -- rate master rides under Reports
              select sp.screen
                from access_screen_parent sp
                join access_level_screen ls2
                  on ls2.screen = sp.parent
                 and ls2.level = access_level_of(p_person)) q)
  end
$function$
;

CREATE OR REPLACE FUNCTION public.add_business_minutes(p_from timestamp with time zone, p_minutes integer, p_cal uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  c business_calendar%rowtype;
  v_day date; v_left int := p_minutes;
  v_start timestamptz; v_end timestamptz; v_cursor timestamptz; v_avail int;
  v_guard int := 0;
begin
  select * into c from business_calendar where id = p_cal;
  if not found then raise exception 'no such calendar'; end if;
  if p_minutes <= 0 then return p_from; end if;

  v_day := (p_from at time zone c.timezone)::date;
  v_cursor := p_from;

  while v_left > 0 loop
    v_guard := v_guard + 1;
    if v_guard > 3650 then
      raise exception 'add_business_minutes ran past ten years; check the calendar';
    end if;

    if ogl_is_working_day(v_day, p_cal) then
      v_start := (v_day + c.window_start) at time zone c.timezone;
      v_end   := (v_day + c.window_end)   at time zone c.timezone;
      if v_cursor < v_start then v_cursor := v_start; end if;
      if v_cursor < v_end then
        v_avail := (extract(epoch from (v_end - v_cursor)) / 60)::int;
        if v_avail >= v_left then
          return v_cursor + (v_left || ' minutes')::interval;
        end if;
        v_left := v_left - v_avail;
      end if;
    end if;
    v_day := v_day + 1;
    v_cursor := (v_day + c.window_start) at time zone c.timezone;
  end loop;
  return v_cursor;
end $function$
;

CREATE OR REPLACE FUNCTION public.app_config()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'googleClientId', (select value from app_setting where key='google_client_id'),
    'workspaceDomain', (select value from app_setting where key='workspace_domain'))
$function$
;

CREATE OR REPLACE FUNCTION public.app_html(p_slug text DEFAULT 'app'::text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select html from app_page where slug = p_slug
$function$
;

CREATE OR REPLACE FUNCTION public.app_is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from chair_holder ch
      join chair c on c.id = ch.chair_id
     where ch.person_id = app_person_id()
       and ch.to_date is null
       and c.level = 'admin')
$function$
;

CREATE OR REPLACE FUNCTION public.app_person_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.id from person p
   where p.work_email = lower(nullif(current_setting('request.jwt.claims', true)::json->>'email',''))
     and p.employment_status = 'ACTIVE'
   limit 1
$function$
;

CREATE OR REPLACE FUNCTION public.app_refs(p_person uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'clients', coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name)
                                          order by name)
                          from client where status = 'ACTIVE' or status is null), '[]'::jsonb),
    'branches', coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,
                                             'client_id',client_id) order by name)
                           from branch), '[]'::jsonb),
    'categories', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name)
                             from category), '[]'::jsonb),
    'zones', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,
                                 'region',region,'group',group_name) order by name)
                        from geo_node where level = 'ZONE'), '[]'::jsonb),
    'verification_types', coalesce((select jsonb_agg(jsonb_build_object('code',code,'label',label)
                                      order by label)
                                     from verification_type where active), '[]'::jsonb),
    'people', ogl_people())
$function$
;

CREATE OR REPLACE FUNCTION public.app_scope_clients()
 RETURNS TABLE(client_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select distinct cr.client_id from coverage_rule cr
   where cr.person_id in (select person_id from app_subtree())
     and cr.effective_to is null
$function$
;

CREATE OR REPLACE FUNCTION public.app_subtree()
 RETURNS TABLE(person_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with recursive below as (
    select id from person where id = app_person_id()
    union all
    select p.id from person p join below b on p.manager_id = b.id
  )
  select id from below
$function$
;

CREATE OR REPLACE FUNCTION public.assignment_state_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_left int;
begin
  if new.current_state is distinct from old.current_state
     and coalesce(current_setting('crux.ogl_transition', true), '') <> 'on' then
    raise exception 'current_state is written only by ogl_transition(); % -> % was attempted directly',
      old.current_state, new.current_state
      using hint = 'Call ogl_transition(assignment, to_state, actor, reason).';
  end if;

  -- a move to COMPLETED while a point has no finding on it is refused for
  -- every caller, including a future one nobody has written yet
  if new.current_state = 'COMPLETED' and old.current_state is distinct from 'COMPLETED' then
    select count(*) into v_left from case_verification_requirement
     where case_id = new.case_id and status in ('PENDING','IN_PROGRESS');
    if v_left > 0 then
      raise exception 'cannot complete: % verification point(s) have no finding recorded', v_left
        using hint = 'Report each point first, then complete through ogl_complete().';
    end if;
  end if;

  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.auth_act_as(p_actor uuid, p_person uuid, p_chair uuid, p_token_hash text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a person%rowtype; t person%rowtype; n int; v_chair text;
begin
  select * into a from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null or a.app_role <> 'ADMIN' then
    return jsonb_build_object('error','not_permitted',
      'reason','Only an administrator can look at the tool as somebody else.');
  end if;

  if p_person is null and p_chair is not null then
    select count(*) into n from chair_holder h join person p2 on p2.id = h.person_id
     where h.chair_id = p_chair and h.to_date is null
       and p2.superseded_by is null and p2.employment_status = 'ACTIVE';
    select ch.title into v_chair from chair ch where ch.id = p_chair;
    if n = 0 then
      return jsonb_build_object('error','chair_is_empty',
        'reason', coalesce(v_chair,'That chair') || ' has nobody in it, so there is nobody to look at the tool as. Seat somebody first.');
    end if;
    if n > 1 then
      return jsonb_build_object('error','chair_is_shared',
        'reason', v_chair || ' is held by ' || n || ' people. Pick which of them.',
        'holders', (select jsonb_agg(jsonb_build_object('personId', p2.id, 'name', p2.full_name)
                      order by p2.full_name)
                      from chair_holder h join person p2 on p2.id = h.person_id
                     where h.chair_id = p_chair and h.to_date is null
                       and p2.superseded_by is null and p2.employment_status = 'ACTIVE'));
    end if;
    select p2.id into p_person from chair_holder h join person p2 on p2.id = h.person_id
     where h.chair_id = p_chair and h.to_date is null
       and p2.superseded_by is null and p2.employment_status = 'ACTIVE' limit 1;
  end if;

  if p_person is null then
    return jsonb_build_object('error','nobody_named',
      'reason','Name a person, or a chair somebody is sitting in.');
  end if;
  select * into t from person
   where id = p_person and employment_status = 'ACTIVE' and superseded_by is null;
  if t.id is null then
    return jsonb_build_object('error','no_such_person',
      'reason','That person is not active on the people master.');
  end if;
  if t.id = a.id then
    return jsonb_build_object('error','that_is_you',
      'reason','You are already signed in as yourself.');
  end if;

  insert into auth_session (person_id, expires_at, source, token_hash, acting_actor_id)
  values (t.id, now() + interval '2 hours', 'ACT_AS', p_token_hash, a.id);

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (a.id, 'ACTED_AS', 'person', t.id::text,
          jsonb_build_object('actor', a.full_name, 'actorEmail', a.work_email, 'ip', p_ip),
          jsonb_build_object('as', t.full_name, 'asEmail', t.work_email,
                             'asRole', t.app_role, 'viaChair', v_chair));

  return jsonb_build_object('id', t.id, 'full_name', t.full_name,
    'work_email', t.work_email, 'app_role', t.app_role, 'department', t.department,
    'chair_title', (select ch.title from chair_holder h join chair ch on ch.id = h.chair_id
                     where h.person_id = t.id and h.to_date is null
                     order by h.is_primary desc, ch.title limit 1),
    'employee_no', t.employee_no,
    'scope_level', access_level_of(t.id),
    'screens', to_jsonb(access_screens(t.id)),
    'acting', jsonb_build_object('by', a.full_name, 'byId', a.id, 'byEmail', a.work_email),
    'note', 'You are looking at Crux as ' || t.full_name || '. Everything you do here is recorded as ' || t.full_name || ', with your name against it in the audit trail.');
end $function$
;

CREATE OR REPLACE FUNCTION public.auth_act_targets(p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a person%rowtype;
begin
  select * into a from person where id = p_actor;
  if a.id is null or a.app_role <> 'ADMIN' then
    return jsonb_build_object('error','not_permitted',
      'reason','Only an administrator can look at the tool as somebody else.');
  end if;
  return jsonb_build_object(
    'people', coalesce((
      select jsonb_agg(jsonb_build_object(
               'personId', p.id, 'name', p.full_name, 'employeeNo', p.employee_no,
               'email', p.work_email, 'role', p.app_role, 'department', p.department,
               'chair', (select ch.title from chair_holder h join chair ch on ch.id = h.chair_id
                          where h.person_id = p.id and h.to_date is null
                          order by h.is_primary desc, ch.title limit 1))
             order by p.full_name)
        from person p
       where p.superseded_by is null and p.employment_status = 'ACTIVE'
         and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'), '[]'::jsonb),
    'chairs', coalesce((
      select jsonb_agg(jsonb_build_object(
               'chairId', ch.id, 'chair', ch.title, 'code', ch.code,
               'seated', (select count(*) from chair_holder h
                           where h.chair_id = ch.id and h.to_date is null),
               'inScheme', exists (select 1 from kpi_definition k
                                    where k.chair_id = ch.id and k.active and k.position < 100),
               'holders', (select coalesce(jsonb_agg(jsonb_build_object(
                     'personId', p2.id, 'name', p2.full_name) order by p2.full_name), '[]'::jsonb)
                   from chair_holder h2 join person p2 on p2.id = h2.person_id
                  where h2.chair_id = ch.id and h2.to_date is null
                    and p2.superseded_by is null and p2.employment_status = 'ACTIVE'))
             order by ch.title)
        from chair ch
       where exists (select 1 from chair_holder h
                      where h.chair_id = ch.id and h.to_date is null)), '[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.auth_gate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare
  email text := lower(new.email);
  p     person%rowtype;
begin
  if email !~ '@cruxindia\.co\.in$' then
    raise exception 'Sign-in refused: % is not a Crux Workspace address.', email
      using hint = 'Personal addresses cannot hold a chair. Ask HR to create your work account.';
  end if;

  select * into p from person where work_email = email;

  if not found then
    raise exception 'Sign-in refused: % is not on the people master.', email
      using hint = 'HR loads the person first. Signing in does not create an employee.';
  end if;

  if p.employment_status <> 'ACTIVE' then
    raise exception 'Sign-in refused: % is marked %.', email, p.employment_status
      using hint = 'A leaver keeps their history and loses their access. HR reactivates if this is wrong.';
  end if;

  update person set auth_user_id = new.id where id = p.id and auth_user_id is null;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.auth_google(p_email text, p_token_hash text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p person%rowtype; v_domain text;
begin
  select value into v_domain from app_setting where key = 'workspace_domain';

  if lower(p_email) not like '%@' || lower(coalesce(v_domain,'cruxindia.co.in')) then
    insert into login_attempt (email, ip, ok) values (lower(p_email), p_ip, false);
    return jsonb_build_object('error','wrong_domain',
      'reason', p_email || ' is not a Crux Workspace address.',
      'hint','Personal addresses cannot hold a chair.');
  end if;

  select * into p from person
   where lower(work_email) = lower(p_email)
     and employment_status = 'ACTIVE'
     and superseded_by is null;

  if not found then
    insert into login_attempt (email, ip, ok) values (lower(p_email), p_ip, false);
    return jsonb_build_object('error','not_a_person',
      'reason', p_email || ' is not on the people master.',
      'hint','HR loads the person first. Signing in does not create an employee.');
  end if;

  insert into login_attempt (email, ip, ok) values (lower(p_email), p_ip, true);
  insert into auth_session (person_id, expires_at, source, token_hash)
  values (p.id, now() + interval '7 days', 'WORKSPACE_SSO', p_token_hash);

  return jsonb_build_object('id', p.id, 'full_name', p.full_name,
    'work_email', p.work_email, 'app_role', p.app_role);
end $function$
;

CREATE OR REPLACE FUNCTION public.auth_login(p_email text, p_hash text, p_token_hash text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p person%rowtype; v_fails int;
begin
  select count(*) into v_fails from login_attempt
   where at > now() - interval '15 minutes' and ok = false
     and (email = lower(p_email) or (p_ip is not null and ip = p_ip));

  if v_fails >= 5 then
    return jsonb_build_object('error','locked_out',
      'reason','Too many failed attempts. Try again in fifteen minutes.');
  end if;

  select * into p from person
   where lower(work_email) = lower(p_email)
     and employment_status = 'ACTIVE'
     and superseded_by is null;

  if not found or p.password_hash is null
     or length(p.password_hash) <> length(p_hash)
     or p.password_hash <> p_hash then
    insert into login_attempt (email, ip, ok) values (lower(p_email), p_ip, false);
    -- one message for both cases: a different answer for "no such person"
    -- would turn this endpoint into a staff directory
    return jsonb_build_object('error','bad_credentials',
      'reason','Wrong address or password.');
  end if;

  insert into login_attempt (email, ip, ok) values (lower(p_email), p_ip, true);
  insert into auth_session (person_id, expires_at, source, token_hash)
  values (p.id, now() + interval '7 days', 'PASSWORD', p_token_hash);

  return jsonb_build_object('id', p.id, 'full_name', p.full_name,
    'work_email', p.work_email, 'app_role', p.app_role);
end $function$
;

CREATE OR REPLACE FUNCTION public.auth_salt(p_email text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select password_salt from person
   where lower(work_email) = lower(p_email)
     and employment_status = 'ACTIVE'
     and superseded_by is null
$function$
;

CREATE OR REPLACE FUNCTION public.auth_signout(p_token_hash text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update auth_session set revoked_at = now()
   where token_hash = p_token_hash and revoked_at is null
$function$
;

CREATE OR REPLACE FUNCTION public.auth_whoami(p_token_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_person uuid; v_actor uuid; p person%rowtype; a person%rowtype;
begin
  update auth_session s set last_seen_at = now()
   where s.token_hash = p_token_hash and s.revoked_at is null and s.expires_at > now()
   returning s.person_id, s.acting_actor_id into v_person, v_actor;
  if v_person is null then return null; end if;
  select * into p from person
   where id = v_person and employment_status = 'ACTIVE' and superseded_by is null;
  if not found then return null; end if;
  if v_actor is not null then select * into a from person where id = v_actor; end if;
  return jsonb_build_object(
    'id', p.id, 'full_name', p.full_name, 'work_email', p.work_email,
    'app_role', p.app_role, 'department', p.department,
    'designation', (select d.title from designation d where d.id = p.designation_id),
    'chair_title', (select ch.title from chair_holder h join chair ch on ch.id = h.chair_id
                     where h.person_id = p.id and h.to_date is null
                     order by h.is_primary desc, ch.title limit 1),
    'employee_no', p.employee_no,
    -- the two new ones: what this person may open, decided in one place
    'scope_level', access_level_of(p.id),
    'screens', to_jsonb(access_screens(p.id)),
    'acting', case when v_actor is null then null else jsonb_build_object(
        'by', a.full_name, 'byId', a.id, 'byEmail', a.work_email) end);
end $function$
;

CREATE OR REPLACE FUNCTION public.automation_load(p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'automation_load expects an array, got %', coalesce(jsonb_typeof(p_rows),'null');
  end if;

  insert into automation (key, title, grp, owner, state, fires_on,
                          trigger_on, conditions, actions, notifies, guard,
                          enabled, disabled_reason)
  select r.key, r.title, r.grp, r.owner, r.state,
         nullif(array_to_string(coalesce(r.trigger_on, '{}'), ' - '), ''),
         r.trigger_on, r.conditions, r.actions, r.notifies, r.guard,
         (r.state = 'live'),
         -- the table refuses a disabled row with no reason, and it is right to
         case when r.state = 'live' then null
              else coalesce(r.blocked_why, 'Blocked, and no reason was recorded against it.') end
    from jsonb_to_recordset(p_rows) as r(
      key text, title text, grp text, owner text, state text,
      trigger_on text[], conditions text[], actions text[], notifies text[],
      guard text, blocked_why text)
  on conflict (key) do update set
      title = excluded.title, grp = excluded.grp, owner = excluded.owner,
      state = excluded.state, fires_on = excluded.fires_on,
      trigger_on = excluded.trigger_on, conditions = excluded.conditions,
      actions = excluded.actions, notifies = excluded.notifies,
      guard = excluded.guard, enabled = excluded.enabled,
      disabled_reason = excluded.disabled_reason;

  get diagnostics n = row_count;
  return n;
end $function$
;

CREATE OR REPLACE FUNCTION public.branch_centre(p_branch uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select a.centre
  from branch b
  join geo_node g on g.id = b.geo_node_id
  join holiday_centre_alias a on lower(a.city) = lower(g.name)
  where b.id = p_branch;
$function$
;

CREATE OR REPLACE FUNCTION public.business_minutes_between(p_from timestamp with time zone, p_to timestamp with time zone, p_cal uuid)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  c business_calendar%rowtype;
  v_day date; v_total int := 0;
  v_start timestamptz; v_end timestamptz; v_a timestamptz; v_b timestamptz;
begin
  if p_to <= p_from then return 0; end if;
  select * into c from business_calendar where id = p_cal;
  if not found then raise exception 'no such calendar'; end if;

  v_day := (p_from at time zone c.timezone)::date;
  while v_day <= (p_to at time zone c.timezone)::date loop
    if ogl_is_working_day(v_day, p_cal) then
      v_start := (v_day + c.window_start) at time zone c.timezone;
      v_end   := (v_day + c.window_end)   at time zone c.timezone;
      v_a := greatest(p_from, v_start);
      v_b := least(p_to, v_end);
      if v_b > v_a then
        v_total := v_total + (extract(epoch from (v_b - v_a)) / 60)::int;
      end if;
    end if;
    v_day := v_day + 1;
  end loop;
  return v_total;
end $function$
;

CREATE OR REPLACE FUNCTION public.case_auto_close_window()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_days int;
begin
  if new.status = 'RESOLVED' and old.status is distinct from 'RESOLVED' then
    v_days := coalesce(nullif((select value from app_setting
                                where key = 'auto_close_days'), ''), '7')::int;
    -- scheduled at resolution, so changing the setting later never moves a
    -- window somebody is already inside
    new.auto_close_at := now() + make_interval(days => v_days);
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.case_parties_sync(p_case uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c "case"; n int := 0;
begin
  select * into c from "case" where id = p_case;
  if c.id is null then return 0; end if;

  with want as (
    select c.raised_by as person_id, 'RAISER'::esc_party as part
     where c.raised_by is not null
    union
    select c.against_person_id, 'RESPONDENT'
     where c.against_person_id is not null
    union
    select p.manager_id, 'MANAGER' from person p
     where p.id = c.against_person_id and p.manager_id is not null
    union
    select d.primary_person_id, 'DESK' from desk d
     where d.id = c.desk_id and d.primary_person_id is not null
    union
    select d.primary_person_id, 'HR' from desk d
     where d.name = 'HR' and d.primary_person_id is not null
  ),
  -- one person, one part: the first part in this order wins, so an HR head
  -- who raised the case acts as the raiser rather than as both
  ranked as (
    select distinct on (person_id) person_id, part
    from want
    order by person_id,
      case part when 'RAISER' then 1 when 'RESPONDENT' then 2
                when 'MANAGER' then 3 when 'DESK' then 4 else 5 end
  ),
  gone as (
    delete from escalation_party ep
     where ep.case_id = p_case
       and not exists (select 1 from ranked r
                        where r.person_id = ep.person_id and r.part = ep.part)
    returning 1
  ),
  put as (
    insert into escalation_party (case_id, person_id, part)
    select p_case, person_id, part from ranked
    on conflict do nothing
    returning 1
  )
  select (select count(*) from put) into n;

  return n;
end $function$
;

CREATE OR REPLACE FUNCTION public.case_parties_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  perform case_parties_sync(new.id);
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.case_status_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if old.status = 'CLOSED' and new.status is distinct from 'CLOSED' then
    raise exception 'ESC % is closed. A closed escalation is reopened by '
      'raising a new one, so that the record of the first stays true.', old.ref
      using errcode = 'check_violation';
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.chair_place_from_coverage(p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role role_kind;
  r record;
  v_scopes text[];
  v_seating uuid;
  v_placed jsonb := '[]'::jsonb;
  v_left   jsonb := '[]'::jsonb;
  v_why    text;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Placing chair holders is an administrator''s to do.');
  end if;

  for r in
    select h.id as holder_id, h.person_id, h.chair_id,
           p.full_name, c.code, c.title,
           (select count(*) from chair_seating s where s.chair_id = h.chair_id) as places
    from chair_holder h
    join chair c on c.id = h.chair_id
    join person p on p.id = h.person_id
    where h.seating_id is null
    order by c.code, p.full_name
  loop
    v_seating := null;
    v_why     := null;

    if r.places = 1 then
      -- a chair held in exactly one place needs no evidence at all
      select s.id into v_seating from chair_seating s where s.chair_id = r.chair_id;
      if v_seating is null then v_why := 'the chair has no seating at all'; end if;
    else
      select array_agg(distinct sc) into v_scopes
        from (select geo_seat_scope(b.geo_node_id) as sc
                from coverage_rule cr
                join branch b on b.id = cr.branch_id
               where cr.person_id = r.person_id) q
       where sc is not null;

      if v_scopes is null or array_length(v_scopes, 1) = 0 then
        v_why := case when exists (select 1 from coverage_rule cr where cr.person_id = r.person_id)
                        then 'their coverage is in a place the chart has no seat for'
                        else 'no coverage to place them by' end;
      elsif array_length(v_scopes, 1) > 1 then
        v_why := 'their coverage spans ' || array_to_string(v_scopes, ', ');
      else
        select s.id into v_seating from chair_seating s
         where s.chair_id = r.chair_id and s.scope_label = v_scopes[1];
        if v_seating is null then
          v_why := 'the chair has no seating in ' || v_scopes[1];
        end if;
      end if;
    end if;

    if v_seating is null then
      v_left := v_left || jsonb_build_object(
        'person', r.full_name, 'chair', r.code, 'title', r.title, 'why', v_why);
    else
      update chair_holder set seating_id = v_seating where id = r.holder_id;
      v_placed := v_placed || jsonb_build_object(
        'person', r.full_name, 'chair', r.code,
        'place', (select coalesce(scope_label,'(the only place)')
                    from chair_seating where id = v_seating));
    end if;
  end loop;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'CHAIR_HOLDERS_PLACED', 'chair_holder', 'bulk',
          jsonb_build_object('placed', jsonb_array_length(v_placed),
                             'left', jsonb_array_length(v_left)));

  return jsonb_build_object(
    'placed', jsonb_array_length(v_placed), 'detail', v_placed,
    'unplaced', jsonb_array_length(v_left), 'left', v_left);
end $function$
;

CREATE OR REPLACE FUNCTION public.chair_reports_to_someone(p_chair uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with recursive up as (
    select c.parent_id, 1 as d from chair c where c.id = p_chair
    union all
    select c.parent_id, up.d + 1
      from up join chair c on c.id = up.parent_id
     where up.parent_id is not null and up.d < 30
  )
  select exists (
    select 1 from up
      join chair_holder h on h.chair_id = up.parent_id and h.to_date is null
     where up.parent_id is not null);
$function$
;

CREATE OR REPLACE FUNCTION public.config_job_set(p_actor uuid, p_key text, p_enabled boolean, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; j job_config;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Starting and stopping a job is an administrator''s to do.');
  end if;

  select * into j from job_config where job_key = p_key;
  if j.job_key is null then return jsonb_build_object('error','no_such_job'); end if;

  if not p_enabled and coalesce(btrim(p_reason),'') = '' then
    return jsonb_build_object('error','reason_required',
      'reason','Say why it is being stopped. Somebody will need to know, '
               'possibly months from now.');
  end if;

  update job_config
     set enabled = p_enabled,
         reason = case when p_enabled then null else btrim(p_reason) end,
         disabled_by = case when p_enabled then null else p_actor end,
         disabled_at = case when p_enabled then null else now() end
   where job_key = p_key;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, case when p_enabled then 'JOB_STARTED' else 'JOB_STOPPED' end,
          'job_config', p_key,
          jsonb_build_object('enabled', j.enabled),
          jsonb_build_object('enabled', p_enabled, 'reason', btrim(p_reason)));

  return jsonb_build_object('ok', true, 'key', p_key, 'enabled', p_enabled);
end $function$
;

CREATE OR REPLACE FUNCTION public.config_penalty_save(p_actor uuid, p_id uuid, p_amount numeric DEFAULT NULL::numeric, p_active boolean DEFAULT NULL::boolean, p_recovered_by text DEFAULT NULL::text, p_applies_to text[] DEFAULT NULL::text[], p_plain_language text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r penalty_rule;
begin
  if not may_edit_penalty_rule(p_actor) then
    return jsonb_build_object('error','not_allowed',
      'reason','Penalty rules are for an administrator, HR or Finance.');
  end if;

  select * into r from penalty_rule where id = p_id;
  if r.id is null then return jsonb_build_object('error','no_such_rule'); end if;

  if p_amount is not null and p_amount < 0 then
    return jsonb_build_object('error','bad_amount','reason','An amount cannot be negative.');
  end if;
  if p_recovered_by is not null and p_recovered_by not in ('HR','FINANCE') then
    return jsonb_build_object('error','bad_recovery',
      'reason','Recovery is by HR through payroll or by Finance through billing.');
  end if;

  -- switching on a rule that will charge nothing is worth saying out loud
  if coalesce(p_active, r.active)
     and coalesce(p_amount, r.amount) = 0 then
    return jsonb_build_object('error','no_amount',
      'reason','Set an amount before switching this rule on. A rule at zero '
               'records a charge of nothing against somebody''s name.');
  end if;

  update penalty_rule set
    amount         = coalesce(p_amount, amount),
    active         = coalesce(p_active, active),
    recovered_by   = coalesce(p_recovered_by, recovered_by),
    applies_to_list= coalesce(p_applies_to, applies_to_list),
    plain_language = coalesce(nullif(btrim(p_plain_language),''), plain_language)
   where id = p_id;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, 'PENALTY_RULE_CHANGED', 'penalty_rule', r.code,
          jsonb_build_object('amount', r.amount, 'active', r.active,
                             'recovered_by', r.recovered_by),
          jsonb_build_object('amount', coalesce(p_amount, r.amount),
                             'active', coalesce(p_active, r.active),
                             'recovered_by', coalesce(p_recovered_by, r.recovered_by)));

  return jsonb_build_object('ok', true, 'code', r.code);
end $function$
;

CREATE OR REPLACE FUNCTION public.config_read(p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_penalty boolean;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  v_penalty := may_edit_penalty_rule(p_actor);

  if v_role is distinct from 'ADMIN' and not v_penalty then
    return jsonb_build_object('error','not_allowed',
      'reason','Configuration is for an administrator, and penalty rules for '
               'HR and Finance as well.');
  end if;

  return jsonb_build_object(
    'mayEditSettings', v_role = 'ADMIN',
    'mayEditPenalties', v_penalty,

    'locations', case when v_role <> 'ADMIN' then '[]'::jsonb else op_tree() end,

    'groups', case when v_role <> 'ADMIN' then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('name', g.group_name, 'settings', g.settings)
             order by g.group_name)
      from (
        select group_name,
               jsonb_agg(jsonb_build_object(
                 'key', key,
                 'value', case when secret then null else value end,
                 'isSecret', secret,
                 'isSet', coalesce(nullif(value,''),'') <> '',
                 'says', plain_language,
                 'inForce', in_force,
                 'editable', editable_by <> 'SYSTEM')
                 order by key) as settings
        from app_setting
        group by group_name) g), '[]'::jsonb) end,

    'jobs', case when v_role <> 'ADMIN' then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', j.job_key, 'enabled', j.enabled, 'cron', j.cron,
        'reason', j.reason,
        'disabledAt', j.disabled_at,
        'disabledBy', (select full_name from person where id = j.disabled_by),
        'lastRun', (select jsonb_build_object(
                      'at', r.started_at, 'state', r.state,
                      'counts', r.counts, 'error', r.error)
                    from job_run r where r.job_key = j.job_key
                    order by r.started_at desc limit 1))
        order by j.job_key)
      from job_config j), '[]'::jsonb) end,

    'penalties', case when not v_penalty then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'code', r.code, 'what', r.what, 'says', r.plain_language,
        'appliesTo', r.applies_to_list, 'frequency', r.frequency,
        'cutoff', r.cutoff_spec, 'amount', r.amount,
        'recoveredBy', r.recovered_by, 'active', r.active,
        'charged', (select count(*) from penalty_instance i where i.rule_id = r.id),
        'fires', r.code in ('P-01','P-06'))
        order by r.code)
      from penalty_rule r), '[]'::jsonb) end
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.config_set(p_actor uuid, p_key text, p_value text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; s app_setting;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Changing a setting is an administrator''s to do.');
  end if;

  select * into s from app_setting where key = p_key;
  if s.key is null then
    return jsonb_build_object('error','no_such_setting',
      'reason','There is no setting by that name.');
  end if;
  if s.editable_by = 'SYSTEM' then
    return jsonb_build_object('error','not_yours_to_set',
      'reason','That value is how the system talks to itself. It is not typed in.');
  end if;

  update app_setting set value = coalesce(p_value, ''),
         updated_by = p_actor, updated_at = now()
   where key = p_key;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, 'SETTING_CHANGED', 'app_setting', p_key,
          jsonb_build_object('value', case when s.secret then '(a secret)' else s.value end),
          jsonb_build_object('value', case when s.secret then '(a secret)' else p_value end));

  return jsonb_build_object('ok', true, 'key', p_key,
    'value', case when s.secret then null else p_value end,
    'wasInForce', s.in_force);
end $function$
;

CREATE OR REPLACE FUNCTION public.coverage_no_overlap()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare clash record;
begin
  if new.scope_type = 'BRANCH' then
    select r.id, r.scope_type, 1 as n into clash
      from coverage_rule r
     where r.person_id = new.person_id and r.role = new.role and r.id <> new.id
       and (r.effective_to is null or r.effective_to >= current_date)
       and ( (r.scope_type = 'BRANCH' and r.branch_id = new.branch_id)
          or (r.scope_type <> 'BRANCH'
              and exists (select 1 from coverage_resolve(r) x where x = new.branch_id)) )
     limit 1;
  else
    select r.id, r.scope_type, count(*) as n into clash
      from coverage_rule r
      cross join lateral (select 1 from coverage_resolve(r) x
                           where x in (select coverage_resolve(new))) hit
     where r.person_id = new.person_id and r.role = new.role and r.id <> new.id
       and (r.effective_to is null or r.effective_to >= current_date)
     group by r.id, r.scope_type
     limit 1;
  end if;

  if clash.id is not null then
    raise exception 'coverage overlap: % branches already covered by rule % (%)',
      clash.n, clash.id, clash.scope_type using errcode = 'check_violation';
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.coverage_resolve(p_rule coverage_rule)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select b.id from branch b
  left join client_zone cz on cz.id = b.client_zone_id
  where case p_rule.scope_type
    when 'CLIENT'      then b.client_id = p_rule.client_id
    when 'CLIENT_ZONE' then b.client_zone_id = p_rule.client_zone_id
    when 'STATE'       then b.client_id = p_rule.client_id and b.geo_node_id in (
                              with recursive t as (
                                select id from geo_node where id = p_rule.geo_node_id
                                union all select g.id from geo_node g join t on g.parent_id = t.id
                              ) select id from t)
    when 'BRANCH'      then b.id = p_rule.branch_id
    when 'LOCATION'    then b.op_node_id in (
                              with recursive t as (
                                select id from op_node where id = p_rule.op_node_id
                                union all select o.id from op_node o join t on o.parent_id = t.id
                              ) select id from t)
                           and (p_rule.client_id is null or b.client_id = p_rule.client_id)
                           and b.status = 'ACTIVE'
  end;
$function$
;

CREATE OR REPLACE FUNCTION public.crux_mail_tick()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_req bigint; v_url text; v_secret text; v_anon text;
begin
  if not coalesce((select enabled from job_config where job_key='MAIL_DRAIN'), true) then
    return null;
  end if;
  if not exists (select 1 from outbox where state in ('QUEUED','DEFERRED')) then
    return null;
  end if;

  select value into v_url    from app_setting where key = 'function_base_url';
  select value into v_secret from app_setting where key = 'mail_cron_secret';
  select value into v_anon   from app_setting where key = 'anon_key';

  select net.http_post(
    url := v_url || '/mail',
    headers := jsonb_build_object(
      'content-type','application/json',
      'authorization','Bearer ' || v_anon,
      'x-crux-cron', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  ) into v_req;
  return v_req;
end $function$
;

CREATE OR REPLACE FUNCTION public.crux_matrix_nudge_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d date := date_trunc('month', current_date)::date; n int := 0;
begin
  if not coalesce((select enabled from job_config where job_key='MATRIX_NUDGE'), false) then
    return jsonb_build_object('skipped', 'MATRIX_NUDGE is switched off.');
  end if;
  while d < current_date loop
    if is_working_day(d, null) then n := n + 1; end if;
    d := d + 1;
  end loop;
  if not is_working_day(current_date, null) then
    return jsonb_build_object('skipped', 'Not a working day.');
  end if;
  if n <> 4 then
    return jsonb_build_object('skipped',
      'Today is working day ' || (n + 1) || ' of the month; the nudge goes on the fifth.');
  end if;
  return matrix_nudge_sweep();
end $function$
;

CREATE OR REPLACE FUNCTION public.crux_penalty_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not coalesce((select enabled from job_config where job_key='PENALTY_SWEEP'), false) then
    return jsonb_build_object('skipped', 'PENALTY_SWEEP is switched off.');
  end if;
  return penalty_sweep();
end $function$
;

CREATE OR REPLACE FUNCTION public.crux_perf_reminder_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not coalesce((select enabled from job_config where job_key='PERF_REMINDERS'), false) then
    return jsonb_build_object('skipped', 'PERF_REMINDERS is switched off.');
  end if;
  return perf_reminder_sweep();
end $function$
;

CREATE OR REPLACE FUNCTION public.crux_request_strike_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not coalesce((select enabled from job_config where job_key='REQUEST_STRIKES'), false) then
    return jsonb_build_object('skipped', 'REQUEST_STRIKES is switched off.');
  end if;
  return request_strike_sweep();
end $function$
;

CREATE OR REPLACE FUNCTION public.crux_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_run uuid; v_closed int := 0; v_risk int := 0; v_breached int := 0;
  v_sub jsonb := '{}'::jsonb; v_esc jsonb := '{}'::jsonb; v_strk jsonb := '{}'::jsonb;
  v_counts jsonb;
begin
  insert into job_run (job_key, started_at, state)
  values ('CRUX_TICK', now(), 'RUNNING') returning id into v_run;

  -- R-05: a resolved case closes itself seven days later, on the schedule set
  -- when it was resolved rather than by a sweep guessing at it.
  if coalesce((select enabled from job_config where job_key='AUTO_CLOSE'), true) then
    with done as (
      update "case" set status = 'CLOSED', closed_at = now(), last_activity_at = now()
       where status = 'RESOLVED' and auto_close_at is not null and auto_close_at <= now()
      returning id
    )
    insert into case_event (case_id, at, kind, note)
    select id, now(), 'AUTO_CLOSED', 'Closed automatically seven days after resolution.' from done;
    get diagnostics v_closed = row_count;
  end if;

  -- SLA status is derived from the clock, never typed in. A paused clock is
  -- not breaching: while a granted pause is open the deadline does not move
  -- towards the assignment.
  if coalesce((select enabled from job_config where job_key='SLA_SWEEP'), true) then
    with hit as (
      update sla_instance si set sla_status = 'BREACHED'
        where si.stopped_at is null and si.sla_status <> 'BREACHED'
          and now() > coalesce(si.extended_to, si.due_at)
          and not exists (select 1 from sla_clock_segment s
                           where s.sla_instance_id = si.id and s.closed_at is null
                             and s.counts_to_sla = false)
      returning si.assignment_id, si.id, coalesce(si.extended_to, si.due_at) as deadline)
    insert into assignment_event (assignment_id, event_type, is_system, payload)
    select assignment_id, 'SLA_BREACHED', true,
           jsonb_build_object('instance', id, 'deadline', deadline) from hit;
    get diagnostics v_breached = row_count;

    with hit as (
      update sla_instance si set sla_status = 'AT_RISK'
        from sla_rule r
       where r.id = si.sla_rule_id
         and si.stopped_at is null and si.sla_status = 'ON_TRACK'
         and not exists (select 1 from sla_clock_segment s
                          where s.sla_instance_id = si.id and s.closed_at is null
                            and s.counts_to_sla = false)
         and ogl_elapsed_sla(si.id) >= si.tat_business_minutes * r.at_risk_pct / 100.0
      returning si.assignment_id, si.id, r.at_risk_pct)
    insert into assignment_event (assignment_id, event_type, is_system, payload)
    select assignment_id, 'SLA_AT_RISK', true,
           jsonb_build_object('instance', id, 'at_risk_pct', at_risk_pct) from hit;
    get diagnostics v_risk = row_count;
  end if;

  -- the OGL engine: sub-TATs first, because an auto-accepted delay moves a
  -- deadline and the escalation sweep should see the moved one
  if coalesce((select enabled from job_config where job_key='OGL_SWEEP'), true) then
    v_sub  := ogl_sub_tat_sweep();
    v_esc  := ogl_escalation_sweep();
    v_strk := ogl_strike_sweep();
  end if;

  v_counts := jsonb_build_object('auto_closed', v_closed,
                'sla_at_risk', v_risk, 'sla_breached', v_breached)
              || v_sub || v_esc || v_strk;

  update job_run set finished_at = now(), state = 'DONE', counts = v_counts where id = v_run;
  return v_counts;
exception when others then
  update job_run set finished_at = now(), state = 'FAILED', error = sqlerrm where id = v_run;
  raise;
end $function$
;

CREATE OR REPLACE FUNCTION public.crux_wa_bridge_tick()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not coalesce((select enabled from job_config where job_key='WA_BRIDGE_SWEEP'), true) then
    return 0;
  end if;
  return wa_bridge_sweep();
end $function$
;

CREATE OR REPLACE FUNCTION public.crux_wa_tick()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
;

CREATE OR REPLACE FUNCTION public.csv_cell(v text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case when v is null then ''
              when v ~ '[",\n]' then '"' || replace(v, '"', '""') || '"'
              else v end
$function$
;

CREATE OR REPLACE FUNCTION public.daily_count_unwrap_values()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare inner_txt text;
begin
  if new.values is null then return new; end if;

  -- a jsonb that IS a string may be JSON that was encoded twice
  if jsonb_typeof(new.values) = 'string' then
    inner_txt := new.values #>> '{}';
    begin
      if jsonb_typeof(inner_txt::jsonb) in ('object','array') then
        new.values := inner_txt::jsonb;
      end if;
    exception when others then
      -- genuinely just a string. Leave it exactly as it came.
      null;
    end;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.data_reset(p_actor uuid, p_confirm text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t text; n bigint; v_counts jsonb := '{}'::jsonb; v_chair uuid; v_total bigint := 0;
begin
  if p_confirm is distinct from 'DELETE ALL DATA' then
    return jsonb_build_object('error','not_confirmed',
      'reason','This empties every person, client, branch, case and filing in the tool.',
      'hint','Type DELETE ALL DATA to confirm.');
  end if;
  if p_actor is null or not exists (select 1 from person where id = p_actor and app_role = 'ADMIN') then
    return jsonb_build_object('error','admin_only',
      'reason','Only an administrator can empty the tool.');
  end if;

  -- the chair the administrator sits in survives, or they cannot sign back in
  select chair_id into v_chair from chair_holder
   where person_id = p_actor and to_date is null
   order by is_primary desc limit 1;

  foreach t in array array[
    'sla_clock_segment','assignment_request','assignment_event','assignment_completion',
    'sla_instance','assignment','repeat_point_decision','case_verification_requirement',
    'case_party','verification_case','ogl_escalation_matrix',
    'escalation_action_log','escalation_party','case_event','case',
    'claim','penalty_instance','pms_adjustment','pms_component','pms_dispute',
    'pms_exception','pms_score','pms_cycle','raisable',
    'daily_count','daily_note','task','target','perf_month','perf_revenue','perf_collection',
    'role_change','person_event','letter','notification','push_subscription',
    'value_correction','day_reopen','person_request','upload_row','upload_batch','holiday',
    'matrix_contact','client_contact','branch_contact','coverage_rule','client_zone',
    'branch','client','sample_row','login_attempt','outbox','delivery'
  ] loop
    if to_regclass('public.' || quote_ident(t)) is not null then
      execute format('delete from %I', t);
      get diagnostics n = row_count;
      if n > 0 then
        v_counts := v_counts || jsonb_build_object(t, n);
        v_total := v_total + n;
      end if;
    end if;
  end loop;

  -- people and chairs last, and never the administrator doing this
  delete from chair_holder where person_id <> p_actor;
  get diagnostics n = row_count;
  v_counts := v_counts || jsonb_build_object('chair_holder', n); v_total := v_total + n;

  delete from person where id <> p_actor;
  get diagnostics n = row_count;
  v_counts := v_counts || jsonb_build_object('person', n); v_total := v_total + n;

  -- keep the administrator's own chair and the line above it, so the structure
  -- they sit in is still coherent when they sign back in
  delete from chair where id not in (
    with recursive up as (
      select id, parent_id from chair where id = v_chair
      union all
      select c.id, c.parent_id from chair c join up on c.id = up.parent_id)
    select id from up);
  get diagnostics n = row_count;
  v_counts := v_counts || jsonb_build_object('chair', n); v_total := v_total + n;

  delete from geo_node;
  get diagnostics n = row_count;
  v_counts := v_counts || jsonb_build_object('geo_node', n); v_total := v_total + n;

  -- references start again from one, since nothing is left to collide with
  update ref_counter set last_no = 0;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'DATA_RESET', 'database', 'all', v_counts);

  return jsonb_build_object('deleted', v_total, 'byTable', v_counts,
    'kept', 'Configuration, the audit trail, your own account and the chair you sit in.');
end $function$
;

CREATE OR REPLACE FUNCTION public.data_reset_preview()
 RETURNS TABLE(table_name text, rows bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t text; n bigint;
begin
  foreach t in array array[
    'sla_clock_segment','assignment_request','assignment_event','assignment_completion',
    'sla_instance','assignment','repeat_point_decision','case_verification_requirement',
    'case_party','verification_case','ogl_escalation_matrix',
    'escalation_action_log','escalation_party','case_event','case',
    'claim','penalty_instance','pms_adjustment','pms_component','pms_dispute',
    'pms_exception','pms_score','pms_cycle','raisable',
    'daily_count','daily_note','task','target','perf_month','perf_revenue','perf_collection',
    'role_change','person_event','letter','notification','push_subscription',
    'value_correction','day_reopen','upload_row','upload_batch','holiday',
    'matrix_contact','client_contact','branch_contact','coverage_rule','client_zone',
    'branch','client','chair_holder','person','chair','geo_node',
    'sample_row','login_attempt','outbox','delivery','person_request'
  ] loop
    if to_regclass('public.' || quote_ident(t)) is not null then
      execute format('select count(*) from %I', t) into n;
      if n > 0 then
        table_name := t; rows := n; return next;
      end if;
    end if;
  end loop;
end $function$
;

CREATE OR REPLACE FUNCTION public.dept_canon(p_text text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with k as (
    select regexp_replace(
             regexp_replace(lower(btrim(coalesce(p_text,''))), '\s+and\s+', ' & ', 'g'),
             '[^a-z]', '', 'g') as key
  ), want as (
    select case (select key from k)
             when 'hr'            then 'humanresources'
             when 'humanresource' then 'humanresources'
             when 'people'        then 'humanresources'
             when 'ops'           then 'operations'
             when 'bd'            then 'businessdevelopment'
             when 'sales'         then 'businessdevelopment'
             when 'it'            then 'technology'
             when 'tech'          then 'technology'
             when 'finance'       then 'financeaccounts'
             when 'accounts'      then 'financeaccounts'
             when 'compliance'    then 'complianceassurance'
             when 'assurance'     then 'complianceassurance'
             else (select key from k)
           end as key
  )
  select d.department
    from client_view_policy d, want w
   where w.key <> ''
     and regexp_replace(
           regexp_replace(lower(d.department), '\s+and\s+', ' & ', 'g'),
           '[^a-z]', '', 'g') = w.key
   limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.dept_from_chair(p_person uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select dept_canon(case c.function_name
                      when 'Operations' then 'Operations'
                      when 'Finance'    then 'Finance & Accounts'
                      when 'Commercial' then 'Business Development'
                      when 'MIS'        then 'MIS'
                      when 'Technology' then 'Technology'
                      else null end)
    from chair_holder h
    join chair c on c.id = h.chair_id
   where h.person_id = p_person and h.to_date is null
   order by h.is_primary desc, h.from_date
   limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.geo_region(p_in text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case lower(btrim(regexp_replace(coalesce(p_in,''), '[\s_-]+', ' ', 'g')))
    when 'east' then 'East' when 'west' then 'West'
    when 'north' then 'North' when 'south' then 'South'
    when 'central' then 'Central'
    when 'north east' then 'North East' when 'northeast' then 'North East'
    when 'ne' then 'North East'
    else null end;
$function$
;

CREATE OR REPLACE FUNCTION public.geo_seat_scope(p_geo uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with recursive up as (
    select id, parent_id, level, name from geo_node where id = p_geo
    union all
    select g.id, g.parent_id, g.level, g.name
    from geo_node g join up u on u.parent_id = g.id),
  t as (
    select max(case when level='ZONE' then name end) as zone,
           max(case when level='CITY' then name end) as city
    from up)
  select case
           when city ilike 'pune'  then 'Pune'
           when city ilike 'thane' then 'Thane'
           when zone = 'North' then 'North'
           when zone in ('North East','East') then 'North East & East'
           when zone = 'South' then 'South'
           when zone = 'West'  then 'other West locations'
         end
  from t
$function$
;

CREATE OR REPLACE FUNCTION public.holiday_applies(p_day date, p_centre text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from holiday h
    where h.day = p_day
      and h.confirmed
      and ( holiday_is_national(h.applies_to)
            or ( p_centre is not null and exists (
                   select 1
                     from unnest(string_to_array(h.applies_to, ',')) hc
                     join unnest(
                            string_to_array(
                              coalesce((select string_agg(a.centre, ',')
                                          from holiday_centre_alias a
                                         where lower(btrim(a.city)) = lower(btrim(p_centre))),
                                       p_centre), ',')) mine
                       on lower(btrim(hc)) = lower(btrim(mine))
                 ) ) )
  );
$function$
;

CREATE OR REPLACE FUNCTION public.holiday_is_national(p_applies text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select p_applies is null
      or btrim(lower(p_applies)) in ('all india', 'national', 'india', 'pan india');
$function$
;

CREATE OR REPLACE FUNCTION public.hr_loose_ends()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with live as (
    select p.id, p.employee_type
      from person p
     where p.superseded_by is null
       and p.employment_status = 'ACTIVE'
       and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'),
  measured as (
    select distinct h.person_id
      from chair_holder h
      join live l on l.id = h.person_id
     where h.to_date is null
       and exists (select 1 from kpi_definition k
                    where k.chair_id = h.chair_id and k.active and k.position < 100)),
  seated_chairs as (
    select ch.id, ch.code, ch.title,
           (select count(*) from chair_holder h
             join live l2 on l2.id = h.person_id
            where h.chair_id = ch.id and h.to_date is null) as seated,
           (select count(*) from kpi_definition k
             where k.chair_id = ch.id and k.active and k.position < 100) as measures
      from chair ch)
  select jsonb_build_object(
    'reach', (
      select jsonb_build_object(
        'people', (select count(*) from live),
        'measured', (select count(*) from measured),
        'says',
          case when (select count(*) from measured) = (select count(*) from live)
               then 'Every active person sits in a chair the scheme can measure.'
               else (select count(*) from measured)::text || ' of ' ||
                    (select count(*) from live)::text ||
                    ' active people sit in a chair that carries a measure set. '
                 || 'The rest cannot be scored at all -- not scored badly, not '
                 || 'scored at zero: the engine has nothing to read for them. '
                 || 'A chair gets a measure set on the KPIs screen, and doing '
                 || 'that is what decides who the bonus scheme covers.'
          end)),
    'chairs', coalesce((
      select jsonb_agg(jsonb_build_object(
               'chair', title, 'code', code, 'seated', seated, 'measures', measures)
             order by measures, seated desc, title)
        from seated_chairs where seated > 0), '[]'::jsonb),
    'spare', coalesce((
      select jsonb_agg(jsonb_build_object(
               'chair', title, 'code', code, 'measures', measures) order by title)
        from seated_chairs where seated = 0 and measures > 0), '[]'::jsonb),
    'unseated', plb_unseated(),
    'withoutNumber', person_without_number());
$function$
;

CREATE OR REPLACE FUNCTION public.is_op_zone(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select op_zone_id(p_name) is not null;
$function$
;

CREATE OR REPLACE FUNCTION public.is_staff(p_person uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from person p
     where p.id = p_person
       and p.superseded_by is null
       and (p.employee_no is not null
            or lower(p.work_email) like '%@cruxindia.co.in'
            or exists (select 1 from chair_holder h
                        where h.person_id = p.id and h.to_date is null)));
$function$
;

CREATE OR REPLACE FUNCTION public.is_working_day(p_day date, p_centre text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when extract(isodow from p_day) = 7 then false
    when extract(isodow from p_day) = 6
      and lower(coalesce((select value from app_setting where key='sat'),'')) like 'no%'
      then false
    else not holiday_applies(p_day, p_centre)
  end
$function$
;

CREATE OR REPLACE FUNCTION public.is_ym(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select p is not null and p ~ '^\d{4}-(0[1-9]|1[0-2])$'
$function$
;

CREATE OR REPLACE FUNCTION public.is_ymd(p text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
begin
  if p is null or p !~ '^\d{4}-\d{2}-\d{2}$' then return false; end if;
  perform p::date;
  return true;
exception when others then
  return false;
end $function$
;

CREATE OR REPLACE FUNCTION public.kpi_mine(p_actor uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'mine', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', k.id, 'name', k.name, 'unit', k.unit, 'cadence', k.cadence,
        'accrual', k.accrual, 'mandatory', k.mandatory, 'active', k.active,
        'position', k.position, 'parent', k.parent_id,
        'setBy', (select full_name from person s where s.id = (
                    select t.set_by from kpi_target t
                     where t.kpi_id = k.id order by t.period desc limit 1)))
        order by k.position, k.name)
      from kpi_definition k where k.person_id = p_actor), '[]'::jsonb),

    'team', coalesce((
      select jsonb_agg(jsonb_build_object(
        'person', p.id, 'name', p.full_name,
        'chair', (select c.title from chair_holder h join chair c on c.id = h.chair_id
                   where h.person_id = p.id and h.to_date is null
                   order by h.is_primary desc nulls last limit 1),
        'kpis', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', k.id, 'name', k.name, 'unit', k.unit, 'cadence', k.cadence,
            'accrual', k.accrual, 'mandatory', k.mandatory, 'active', k.active,
            'position', k.position, 'parent', k.parent_id)
            order by k.position, k.name)
          from kpi_definition k where k.person_id = p.id), '[]'::jsonb))
        order by p.full_name)
      from kpi_subtree_people(p_actor) s
      join person p on p.id = s.person_id), '[]'::jsonb),

    'cadences', '["DAILY","WEEKLY","MONTHLY","QUARTERLY"]'::jsonb,
    'accruals', '["ADDS","REPLACES"]'::jsonb,
    -- the shape the decision asks for, shown rather than enforced: a manager
    -- adds them one at a time and must not be blocked halfway
    'intended', jsonb_build_object('total', 5, 'mandatory', 3, 'optional', 2)
  )
$function$
;

CREATE OR REPLACE FUNCTION public.kpi_registry_completeness()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'seatedChairs', (select count(*) from chair ch
                      where exists (select 1 from chair_holder h
                                     where h.chair_id = ch.id and h.to_date is null)),
    'withMeasures', (select count(*) from chair ch
                      where exists (select 1 from chair_holder h
                                     where h.chair_id = ch.id and h.to_date is null)
                        and exists (select 1 from kpi_definition k
                                     where k.chair_id = ch.id and k.active)),
    'peopleWithout', (select count(*) from chair_holder h
                       join kpi_registry_gap g on g.chair_id = h.chair_id
                      where h.to_date is null),
    'gaps', coalesce((select jsonb_agg(jsonb_build_object(
                        'code', g.code, 'chair', g.title,
                        'seated', g.seated, 'statements', g.statements)
                      order by g.seated desc, g.title)
                       from kpi_registry_gap g), '[]'::jsonb))
$function$
;

CREATE OR REPLACE FUNCTION public.kpi_retire(p_actor uuid, p_id uuid, p_active boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_person uuid; v_name text;
begin
  select person_id, name into v_person, v_name from kpi_definition where id = p_id;
  if v_person is null then return jsonb_build_object('error','no_such_kpi'); end if;
  if v_person = p_actor then
    return jsonb_build_object('error','not_your_own',
      'reason','Nobody retires their own KPI.');
  end if;
  if not exists (select 1 from kpi_subtree_people(p_actor) s where s.person_id = v_person) then
    return jsonb_build_object('error','out_of_subtree',
      'reason','You may only change KPIs for people on chairs at or below your own.');
  end if;

  update kpi_definition set active = p_active where id = p_id;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, case when p_active then 'KPI_RESTORED' else 'KPI_RETIRED' end,
          'kpi_definition', p_id::text, jsonb_build_object('name', v_name));

  return jsonb_build_object('ok', true, 'name', v_name, 'active', p_active);
end $function$
;

CREATE OR REPLACE FUNCTION public.kpi_save(p_actor uuid, p_person uuid, p_name text, p_id uuid DEFAULT NULL::uuid, p_unit text DEFAULT NULL::text, p_cadence text DEFAULT 'DAILY'::text, p_accrual text DEFAULT 'ADDS'::text, p_mandatory boolean DEFAULT true, p_position integer DEFAULT NULL::integer, p_parent uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid; v_count int; v_name text;
begin
  if p_person = p_actor then
    return jsonb_build_object('error','not_your_own',
      'reason','Nobody sets their own KPI. Your manager sets yours, the same '
               'way you set your team''s.');
  end if;
  if not exists (select 1 from kpi_subtree_people(p_actor) s where s.person_id = p_person) then
    return jsonb_build_object('error','out_of_subtree',
      'reason','You may only set KPIs for people on chairs at or below your own.');
  end if;
  if coalesce(btrim(p_name),'') = '' then
    return jsonb_build_object('error','no_name','reason','Give the KPI a name.');
  end if;
  if p_cadence not in ('DAILY','WEEKLY','MONTHLY','QUARTERLY') then
    return jsonb_build_object('error','bad_cadence');
  end if;
  if p_accrual not in ('ADDS','REPLACES') then
    return jsonb_build_object('error','bad_accrual');
  end if;

  if p_id is null then
    -- five is the number the owner settled. A sub-category hangs off a KPI
    -- and is not one of the five.
    select count(*) into v_count from kpi_definition
     where person_id = p_person and parent_id is null and active;
    if p_parent is null and v_count >= 5 then
      return jsonb_build_object('error','too_many',
        'reason','Five KPIs is the agreed shape. Retire one before adding another, '
                 'or add this as a sub-category of an existing KPI.');
    end if;

    insert into kpi_definition
      (person_id, name, unit, cadence, accrual, mandatory, position, parent_id)
    values (p_person, btrim(p_name), nullif(btrim(coalesce(p_unit,'')),''),
            p_cadence::kpi_cadence, p_accrual::kpi_accrual, p_mandatory,
            coalesce(p_position, v_count + 1), p_parent)
    returning id into v_id;
  else
    select name into v_name from kpi_definition where id = p_id and person_id = p_person;
    if v_name is null then
      return jsonb_build_object('error','no_such_kpi',
        'reason','That KPI does not belong to that person.');
    end if;
    update kpi_definition set
      name = btrim(p_name),
      unit = nullif(btrim(coalesce(p_unit,'')),''),
      cadence = p_cadence::kpi_cadence,
      accrual = p_accrual::kpi_accrual,
      mandatory = p_mandatory,
      position = coalesce(p_position, position),
      parent_id = p_parent
     where id = p_id
    returning id into v_id;
  end if;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, case when p_id is null then 'KPI_DEFINED' else 'KPI_CHANGED' end,
          'kpi_definition', v_id::text,
          jsonb_build_object('person', (select full_name from person where id = p_person),
                             'name', btrim(p_name), 'cadence', p_cadence,
                             'accrual', p_accrual, 'mandatory', p_mandatory));

  return jsonb_build_object('ok', true, 'id', v_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.kpi_subtree_people(p_actor uuid)
 RETURNS TABLE(person_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with mine as (
    select ch.chair_id, ch.seating_id from chair_holder ch
     where ch.person_id = p_actor and ch.to_date is null
  ),
  my_places as (
    select distinct s.scope_label from mine m
     join chair_seating s on s.id = m.seating_id
     where s.scope_label is not null
  ),
  below as (
    select distinct c.id
      from chair c
     where exists (
       with recursive t as (
         select chair_id as id from mine
         union all
         select k.id from chair k join t on k.parent_id = t.id)
       select 1 from t where t.id = c.id)
  )
  select distinct h.person_id
    from chair_holder h
    join person p on p.id = h.person_id
    left join chair_seating s on s.id = h.seating_id
   where h.chair_id in (select id from below)
     and h.to_date is null
     and p.employment_status = 'ACTIVE'
     and p.superseded_by is null
     and h.person_id <> p_actor
     and (
       -- nobody has a place on record, so place cannot decide anything
       not exists (select 1 from my_places)
       or s.scope_label is null
       or s.scope_label in (select scope_label from my_places)
     )
$function$
;

CREATE OR REPLACE FUNCTION public.mail_configure(p_actor uuid, p_provider text DEFAULT NULL::text, p_from text DEFAULT NULL::text, p_from_name text DEFAULT NULL::text, p_reply_to text DEFAULT NULL::text, p_api_key text DEFAULT NULL::text, p_cap text DEFAULT NULL::text, p_oauth_client_id text DEFAULT NULL::text, p_oauth_client_secret text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_changed text[] := '{}';
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Mail settings are an administrator''s to change.');
  end if;

  if p_provider is not null then
    if p_provider <> '' and p_provider not in
       ('resend','sendgrid','brevo','postmark','gmail_oauth','apps_script') then
      return jsonb_build_object('error','unknown_provider',
        'reason','Known providers are resend, sendgrid, brevo, postmark, '
                 'gmail_oauth and apps_script.');
    end if;
    update app_setting set value = p_provider, updated_by = p_actor, updated_at = now()
     where key = 'mail_provider';
    v_changed := array_append(v_changed, 'provider');
  end if;

  if p_from is not null then
    if p_from <> '' and p_from !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
      return jsonb_build_object('error','bad_from',
        'reason','The from address does not look like an address.');
    end if;
    update app_setting set value = p_from, updated_by = p_actor, updated_at = now()
     where key = 'mail_from';
    v_changed := array_append(v_changed, 'from');
  end if;

  if p_from_name is not null then
    update app_setting set value = p_from_name, updated_by = p_actor, updated_at = now()
     where key = 'mail_from_name';
    v_changed := array_append(v_changed, 'from_name');
  end if;

  if p_reply_to is not null then
    update app_setting set value = p_reply_to, updated_by = p_actor, updated_at = now()
     where key = 'mail_reply_to';
    v_changed := array_append(v_changed, 'reply_to');
  end if;

  if p_oauth_client_id is not null then
    update app_setting set value = p_oauth_client_id, updated_by = p_actor, updated_at = now()
     where key = 'mail_oauth_client_id';
    v_changed := array_append(v_changed, 'oauth_client_id');
  end if;

  if coalesce(p_api_key,'') <> '' then
    update app_setting set value = p_api_key, updated_by = p_actor, updated_at = now()
     where key = 'mail_api_key';
    v_changed := array_append(v_changed, 'api_key');
  end if;

  if coalesce(p_oauth_client_secret,'') <> '' then
    update app_setting set value = p_oauth_client_secret, updated_by = p_actor, updated_at = now()
     where key = 'mail_oauth_client_secret';
    v_changed := array_append(v_changed, 'oauth_client_secret');
  end if;

  if p_cap is not null and p_cap ~ '^\d+$' then
    update app_setting set value = p_cap, updated_by = p_actor, updated_at = now()
     where key = 'mail_daily_cap';
    update mail_budget set cap = p_cap::int where day = current_date;
    v_changed := array_append(v_changed, 'cap');
  end if;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'MAIL_CONFIGURED', 'app_setting', 'mail',
          jsonb_build_object('changed', v_changed));

  return mail_status() || jsonb_build_object('changed', to_jsonb(v_changed));
end $function$
;

CREATE OR REPLACE FUNCTION public.mail_cron_secret()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select value from app_setting where key = 'mail_cron_secret'
$function$
;

CREATE OR REPLACE FUNCTION public.mail_enqueue(p_template text, p_recipient text, p_subject text, p_body text, p_entity_type text DEFAULT NULL::text, p_entity_id uuid DEFAULT NULL::uuid, p_cc text DEFAULT NULL::text, p_not_before timestamp with time zone DEFAULT now(), p_scope text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_key text; v_id uuid;
begin
  if coalesce(btrim(coalesce(p_recipient,'')),'') = '' then
    return jsonb_build_object('error','no_recipient');
  end if;
  -- an address nobody can reach is not an error, but it is not a send either
  if lower(p_recipient) ~ '\.(invalid|test|example|localhost)$'
     or lower(p_recipient) ~ '@(example\.(com|net|org))$' then
    return jsonb_build_object('skipped','placeholder_address','recipient',p_recipient);
  end if;

  v_key := encode(extensions.digest(concat_ws('|',
             p_template, lower(btrim(p_recipient)),
             coalesce(p_entity_type,''), coalesce(p_entity_id::text,''),
             coalesce(p_scope, current_date::text)), 'sha256'), 'hex');

  insert into outbox (idempotency_key, template_key, entity_type, entity_id,
                      recipient, cc_addr, subject, body, not_before)
  values (v_key, p_template, p_entity_type, p_entity_id,
          btrim(p_recipient), nullif(btrim(coalesce(p_cc,'')),''),
          p_subject, p_body, coalesce(p_not_before, now()))
  on conflict (idempotency_key) do nothing
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('duplicate', true, 'key', v_key);
  end if;
  return jsonb_build_object('id', v_id, 'key', v_key);
end $function$
;

CREATE OR REPLACE FUNCTION public.mail_forget_secrets(p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind;
begin
  select app_role into v_role from person where id = p_actor;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin');
  end if;
  update app_setting set value = '', updated_by = p_actor, updated_at = now()
   where key in ('mail_api_key','mail_oauth_client_secret','mail_oauth_refresh_token');
  insert into audit_entry (actor_id, action, entity_type, entity_ref)
  values (p_actor, 'MAIL_SECRETS_CLEARED', 'app_setting', 'mail');
  return mail_status();
end $function$
;

CREATE OR REPLACE FUNCTION public.mail_oauth_begin(p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_nonce text;
begin
  select app_role into v_role from person where id = p_actor;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin');
  end if;
  v_nonce := encode(extensions.gen_random_bytes(24), 'hex');
  update app_setting
     set value = jsonb_build_object('nonce', v_nonce, 'actor', p_actor,
                                    'expires', (now() + interval '10 minutes'))::text,
         updated_by = p_actor, updated_at = now()
   where key = 'mail_oauth_state';
  return jsonb_build_object('nonce', v_nonce);
end $function$
;

CREATE OR REPLACE FUNCTION public.mail_oauth_claim(p_nonce text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb;
begin
  select nullif(value,'')::jsonb into v from app_setting where key = 'mail_oauth_state';
  if v is null then return null; end if;
  -- one time: whatever the outcome, the nonce is spent
  update app_setting set value = '' where key = 'mail_oauth_state';
  if v->>'nonce' is distinct from p_nonce then return null; end if;
  if (v->>'expires')::timestamptz < now() then return null; end if;
  return (v->>'actor')::uuid;
end $function$
;

CREATE OR REPLACE FUNCTION public.mail_oauth_save(p_actor uuid, p_refresh_token text, p_from text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind;
begin
  select app_role into v_role from person where id = p_actor;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin');
  end if;
  if coalesce(btrim(p_refresh_token),'') = '' then
    return jsonb_build_object('error','no_token',
      'reason','Google returned no refresh token. That happens when the mailbox '
             ||'has already consented once - revoke the grant at '
             ||'myaccount.google.com/permissions and try again.');
  end if;
  update app_setting set value = p_refresh_token, updated_by = p_actor, updated_at = now()
   where key = 'mail_oauth_refresh_token';
  if coalesce(btrim(p_from),'') <> '' then
    update app_setting set value = btrim(p_from), updated_by = p_actor, updated_at = now()
     where key = 'mail_from';
  end if;
  update app_setting set value = 'gmail_oauth', updated_by = p_actor, updated_at = now()
   where key = 'mail_provider';
  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'MAIL_OAUTH_GRANTED', 'app_setting', 'mail',
          jsonb_build_object('sends_as', p_from));
  return mail_status();
end $function$
;

CREATE OR REPLACE FUNCTION public.mail_settings()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  from app_setting
  where key in ('mail_provider','mail_from','mail_from_name','mail_reply_to',
                'mail_api_key','mail_oauth_client_id','mail_oauth_client_secret',
                'mail_oauth_refresh_token','google_client_id',
                'mail_relay_url','mail_relay_secret')
$function$
;

CREATE OR REPLACE FUNCTION public.mail_status()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with s as (select key, value from app_setting where key like 'mail%' or key = 'google_client_id'),
  p as (select coalesce(nullif((select value from s where key='mail_provider'),''),'') as provider)
  select jsonb_build_object(
    'provider',      nullif((select provider from p), ''),
    'from',          nullif((select value from s where key='mail_from'), ''),
    'fromName',      nullif((select value from s where key='mail_from_name'), ''),
    'replyTo',       nullif((select value from s where key='mail_reply_to'), ''),
    'oauthClientId', nullif((select value from s where key='mail_oauth_client_id'), ''),
    'oauthSet',      coalesce(nullif((select value from s where key='mail_oauth_client_secret'),''),'') <> '',
    'keySet',        coalesce(nullif((select value from s where key='mail_api_key'),''),'') <> '',
    'grantSet',      coalesce(nullif((select value from s where key='mail_oauth_refresh_token'),''),'') <> '',
    'relayUrl',      nullif((select value from s where key='mail_relay_url'), ''),
    'relaySecretSet', coalesce(nullif((select value from s where key='mail_relay_secret'),''),'') <> '',
    'cap',        coalesce(nullif((select value from app_setting where key='mail_daily_cap'),''),'1500')::int,
    'ready', case (select provider from p)
               when '' then false
               when 'gmail_oauth' then
                 coalesce(nullif((select value from s where key='mail_from'),''),'') <> ''
                 and coalesce(nullif((select value from s where key='mail_oauth_refresh_token'),''),'') <> ''
               when 'apps_script' then
                 coalesce(nullif((select value from s where key='mail_relay_url'),''),'') <> ''
                 and coalesce(nullif((select value from s where key='mail_relay_secret'),''),'') <> ''
               else
                 coalesce(nullif((select value from s where key='mail_from'),''),'') <> ''
                 and coalesce(nullif((select value from s where key='mail_api_key'),''),'') <> ''
             end,
    'queued',    (select count(*) from outbox where state='QUEUED'),
    'deferred',  (select count(*) from outbox where state='DEFERRED'),
    'abandoned', (select count(*) from outbox where state='ABANDONED'),
    'sent',      (select count(*) from outbox where state='SENT'),
    'sentToday', coalesce((select recipients_sent from mail_budget where day = current_date), 0),
    'lastError', (select last_error from outbox
                   where last_error is not null order by created_at desc limit 1),
    'recent',    coalesce((select jsonb_agg(r order by r->>'created_at' desc) from (
                   select jsonb_build_object(
                     'template_key', o.template_key, 'recipient', o.recipient,
                     'state', o.state, 'attempts', o.attempts, 'sent_at', o.sent_at,
                     'last_error', o.last_error, 'created_at', o.created_at) as r
                   from outbox o order by o.created_at desc limit 10) q), '[]'::jsonb)
  )
$function$
;

CREATE OR REPLACE FUNCTION public.mail_test(p_actor uuid, p_to text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role role_kind; v_email text; v_name text; v_to text; r jsonb;
begin
  select app_role, work_email, full_name into v_role, v_email, v_name
    from person where id = p_actor;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin');
  end if;
  v_to := coalesce(nullif(btrim(coalesce(p_to,'')),''), v_email);

  r := mail_enqueue(
        'TEST', v_to,
        'Crux - test message',
        'This is a test from Crux, sent by ' || coalesce(v_name,'an administrator') ||
        ' at ' || to_char(ogl_ts(now()), 'DD Mon YYYY HH24:MI') || ' IST.' || E'\n\n' ||
        'If this reached you, the outbox has a way out of the building and ' ||
        'escalation mail will go the same way.',
        'app_setting', null, null, now(),
        to_char(now(), 'YYYY-MM-DD HH24:MI'));

  if r ? 'skipped' then
    return jsonb_build_object('error','placeholder_address',
      'reason','That address is @example.invalid and cannot receive mail. '
             ||'Give a real one, or set your own work address on the people master.');
  end if;
  return r || jsonb_build_object('to', v_to);
end $function$
;

CREATE OR REPLACE FUNCTION public.matrix_client_view(p_person uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when p.app_role = 'ADMIN' then 'full'
              else coalesce(v.view_kind, 'none') end
    from person p
    left join client_view_policy v on v.department = p.department
   where p.id = p_person;
$function$
;

CREATE OR REPLACE FUNCTION public.matrix_complete(p_branch uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select count(distinct level) = 5 from matrix_contact
   where branch_id = p_branch
     and level between 1 and 5
     and coalesce(btrim(name), '') <> ''
     and (coalesce(btrim(mobile), '') <> '' or coalesce(btrim(email), '') <> '')
$function$
;

CREATE OR REPLACE FUNCTION public.matrix_month(p_person uuid, p_period date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_view text; v_period date; rows jsonb; n_clients int; n_sent int; n_gap int;
begin
  v_view := matrix_client_view(p_person);
  if v_view is null or v_view = 'none' then
    return jsonb_build_object('clients','[]'::jsonb, 'period', date_trunc('month', p_period)::date,
      'says','Your function does not see client data, so the matrix is not yours to send.');
  end if;
  v_period := date_trunc('month', p_period)::date;

  with mine as (
    select b.id, b.client_id
      from branch b
      join matrix_scope_branches(p_person) s on s.branch_id = b.id
     where b.status = 'ACTIVE'
  ),
  per as (
    select m.client_id,
           count(*) as branches,
           count(*) filter (where st.complete_levels = 5) as ready,
           count(*) filter (where st.complete_levels < 5) as incomplete
      from mine m
      join branch_matrix_state st on st.branch_id = m.id
     group by m.client_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'clientId', c.id, 'code', c.code, 'name', c.name,
           'branches', p.branches, 'ready', p.ready, 'incomplete', p.incomplete,
           'recipients', (select count(*) from client_contact k where k.client_id = c.id),
           'sentAt', d.sent_at, 'dispatchId', d.id,
           'sentCount', d.branch_count, 'heldBack', d.held_back)
           order by c.name), '[]'::jsonb),
         count(*), count(*) filter (where d.sent_at is not null),
         count(*) filter (where p.incomplete > 0)
    into rows, n_clients, n_sent, n_gap
    from per p
    join client c on c.id = p.client_id
    left join matrix_dispatch d on d.client_id = c.id and d.period = v_period
   where c.status = 'ACTIVE';

  return jsonb_build_object(
    'period', v_period, 'clients', rows,
    'total', n_clients, 'sent', n_sent, 'withGaps', n_gap,
    'maySend', v_view = 'matrix' or v_view = 'full',
    'says', case
      when n_clients = 0 then 'You cover no active branch, so there is no matrix to send.'
      when n_sent = n_clients then 'This month''s matrix has gone to all ' || n_clients || ' client(s).'
      else (n_clients - n_sent) || ' of ' || n_clients || ' client(s) are still waiting for '
           || 'this month''s matrix'
           || case when n_gap > 0 then ', and ' || n_gap || ' have a branch with a missing level.'
                   else '.' end end);
end $function$
;

CREATE OR REPLACE FUNCTION public.matrix_nudge_sweep(p_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_run uuid; r record; m jsonb; c jsonb; late text; n_late int;
  body text; n int := 0; v_period date;
begin
  insert into job_run (job_key, started_at, state)
  values ('MATRIX_NUDGE', now(), 'RUNNING') returning id into v_run;

  v_period := date_trunc('month', p_on)::date;

  for r in
    select p.id, p.full_name, lower(btrim(p.work_email)) as email
      from person p
     where p.employment_status = 'ACTIVE' and p.superseded_by is null
       and coalesce(btrim(p.work_email), '') <> ''
       and exists (select 1 from coverage_rule cr
                    where cr.person_id = p.id
                      and (cr.effective_to is null or cr.effective_to >= p_on))
  loop
    m := matrix_month(r.id, p_on);
    if not coalesce((m->>'maySend')::boolean, false) then continue; end if;

    late := ''; n_late := 0;
    for c in select jsonb_array_elements(m->'clients') loop
      if c->>'sentAt' is null then
        n_late := n_late + 1;
        late := late || '  - ' || (c->>'name')
             || ' -- ' || (c->>'ready') || ' of ' || (c->>'branches') || ' branches ready'
             || case when coalesce((c->>'incomplete')::int, 0) > 0
                     then ', ' || (c->>'incomplete') || ' still missing a level'
                     else '' end
             || case when coalesce((c->>'recipients')::int, 0) = 0
                     then ', and no contacts on file to send it to'
                     else '' end
             || E'\n';
      end if;
    end loop;

    if n_late = 0 then continue; end if;

    body := 'Good morning ' || split_part(r.full_name, ' ', 1) || E',\n\n'
         || n_late || ' client(s) have not had the escalation matrix for '
         || to_char(v_period, 'FMMonth YYYY') || E':\n\n'
         || late || E'\n'
         || 'A branch with a blank level is held back and named in the letter rather '
         || 'than sent with a gap, so a client with an incomplete branch can still be '
         || 'sent what is ready.' || E'\n\n'
         || 'Open Escalation matrix in Crux.' || E'\n';

    insert into outbox (idempotency_key, template_key, recipient, subject, body,
                        entity_type, entity_id, not_before, state)
    values (md5('MATRIX_NUDGE|' || r.email || '|' || v_period), 'MATRIX_NUDGE', r.email,
            'Escalation matrix for ' || to_char(v_period, 'FMMonth YYYY')
              || ' has not gone out',
            body, 'person', r.id, now(), 'QUEUED')
    on conflict (idempotency_key) do nothing;
    n := n + 1;
  end loop;

  update job_run set finished_at = now(), state = 'DONE',
         counts = jsonb_build_object('day', p_on, 'period', v_period, 'nudges', n)
   where id = v_run;

  return jsonb_build_object('period', v_period, 'nudges', n,
    'note', case when n = 0
      then 'Every client covered by somebody has had this month''s matrix, so nobody was written to.'
      else n || ' person(s) reminded.' end);
exception when others then
  update job_run set finished_at = now(), state = 'FAILED', error = sqlerrm where id = v_run;
  raise;
end $function$
;

CREATE OR REPLACE FUNCTION public.matrix_pack(p_person uuid, p_client uuid, p_period date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_view text; v_period date; c client%rowtype;
  branches jsonb; held jsonb; n_ok int; n_held int; d matrix_dispatch;
begin
  v_view := matrix_client_view(p_person);
  if v_view is null or v_view = 'none' then
    return jsonb_build_object('error','no_client_view',
      'reason','Your function does not see client data, so it does not see the matrix either.');
  end if;

  v_period := date_trunc('month', p_period)::date;
  select * into c from client where id = p_client;
  if c.id is null then return jsonb_build_object('error','no_such_client'); end if;

  with mine as (
    select b.id, b.code, b.name
      from branch b
      join matrix_scope_branches(p_person) s on s.branch_id = b.id
     where b.client_id = p_client and b.status = 'ACTIVE'
  ),
  lv as (
    select m.id as branch_id, m.code, m.name,
           coalesce(jsonb_agg(jsonb_build_object(
             'level', e.level, 'levelName', e.level_name, 'name', e.name,
             'mobile', case when v_view = 'contacts' then null else e.mobile end,
             'email',  case when v_view = 'contacts' then null else e.email end,
             'inherited', e.inherited) order by e.level)
             filter (where e.level is not null), '[]'::jsonb) as levels,
           count(*) filter (
             where e.name is not null and btrim(e.name) <> ''
               and (coalesce(btrim(e.mobile),'') <> '' or coalesce(btrim(e.email),'') <> '')
           ) as complete,
           bool_or(e.inherited) as using_default
      from mine m
      left join branch_effective_matrix e on e.branch_id = m.id
     group by m.id, m.code, m.name
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'branchId', branch_id, 'code', code, 'name', name,
      'levels', levels, 'complete', complete,
      'usingClientDefault', coalesce(using_default, false))
      order by name) filter (where complete = 5), '[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object(
      'branchId', branch_id, 'code', code, 'name', name,
      'complete', complete, 'missing', 5 - complete)
      order by name) filter (where complete < 5), '[]'::jsonb),
    count(*) filter (where complete = 5),
    count(*) filter (where complete < 5)
    into branches, held, n_ok, n_held
  from lv;

  select * into d from matrix_dispatch
   where client_id = p_client and period = v_period;

  return jsonb_build_object(
    'client', jsonb_build_object('clientId', c.id, 'code', c.code, 'name', c.name),
    'period', v_period,
    'view', v_view,
    'branches', branches, 'heldBack', held,
    'ready', n_ok, 'incomplete', n_held,
    'recipients', coalesce((
      select jsonb_agg(jsonb_build_object('kind', k.kind, 'name', k.name, 'email', k.email)
             order by k.kind, k.email)
        from client_contact k where k.client_id = p_client), '[]'::jsonb),
    'dispatch', case when d.id is null then null else jsonb_build_object(
      'dispatchId', d.id, 'sentAt', d.sent_at, 'recipients', to_jsonb(d.recipients),
      'branchCount', d.branch_count, 'heldBack', d.held_back) end,
    'says', case
      when n_ok = 0 and n_held = 0 then
        'You cover no active branch of this client, so there is nothing to send.'
      when n_ok = 0 then
        'Every branch you cover is missing a level, so there is nothing that can be sent. '
        || 'A matrix with a gap in it reads as complete, which is worse than no matrix.'
      when n_held > 0 then
        n_ok || ' branch(es) are ready. ' || n_held || ' are held back until their '
        || 'missing levels are filled, and are named below rather than sent with a gap.'
      else 'All ' || n_ok || ' branch(es) are complete.' end);
end $function$
;

