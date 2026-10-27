-- Existing staff get a login ID and a password
--
-- The owner, 27 Oct: "I am still not able to add existing staff as an
-- admin", and then, offered a way: "Yes, using login ID and password along
-- with all current ones and give me an excel sheet with this login IDs and
-- passwords. If you are not able to identify the managers and other
-- details, keep it open I will do it on the tool."
--
-- Why existing staff could not be added. The add path worked -- an
-- administrator may call person_add -- but it demanded what the company
-- does not have for most of the people who do its work: 394 people
-- verified cases in October (the BI dashboard's workforce list, from
-- Force1), 346 of them are not in the tool, and what is known of them is a
-- name, a location and whether they work in the field or the back office.
-- person_check refused every one: no work e-mail ("how they sign in"), no
-- mobile ("the second way in"). The People upload asks the same. And sign-in
-- itself knew only two doors -- a Google Workspace address, or a work e-mail
-- with a password -- while no account in the tool had a password and
-- nothing could set one.
--
-- So, a third door that needs neither:
--
--   LOGIN ID.  person.user_id, which the table has always had (unique, never
--              used). It is the employee number -- EMP-0003 -- set from it
--              wherever it is empty. auth_salt and auth_login accept a login
--              ID wherever they accepted a work e-mail; Google sign-in is
--              untouched.
--   PASSWORD.  Stored as the tool already stores one: a random salt and the
--              scrypt hash, computed in the edge function. The database never
--              sees a password, and nothing in the repository holds one.
--   ISSUING.   auth_password_issue: an administrator, or HR, gives somebody
--              a temporary password (the edge function makes it, shows it
--              once, and keeps nothing). HR may not issue one for an
--              administrator -- that would be HR taking the administrator's
--              keys -- nobody issues their own, and a service account has
--              none. Issuing ends that person's other password sessions.
--   CHANGING.  auth_password_change: anybody, for themselves, given their
--              current password. A password handed out on a spreadsheet is
--              one the person should replace, and My profile now lets them.
--   ADDING.    person_check: no work e-mail and no mobile become warnings,
--              in words that say what follows ("they sign in with their login
--              ID"), not refusals. person_add sets the login ID and returns
--              it. The employee number, the chair and the name are still
--              required: those are what the tool cannot work without.
--   ONBOARDING person_onboard_existing: an administrator adds existing staff
--              in one go -- name, Field or Back office chair, a manager where
--              one is known, a password hash -- numbered on from the last
--              employee number. A name already in the tool is refused, not
--              duplicated. The rows themselves are loaded through it, never
--              committed: names and hashes do not belong in a public
--              repository.

-- --------------------------------------------- the doors, by substitution
do $do$
declare r record; v_def text; v_n int;
begin
  for r in
    select * from (values
      -- a login ID is a way in wherever a work e-mail was
      ('auth_salt',
       $a$where lower(work_email) = lower(p_email)$a$,
       $b$where (lower(work_email) = lower(btrim(p_email))
         or lower(user_id) = lower(btrim(p_email)))  -- 274: or the login ID$b$),
      ('auth_login',
       $a$where lower(work_email) = lower(p_email)$a$,
       $b$where (lower(work_email) = lower(btrim(p_email))
         or lower(user_id) = lower(btrim(p_email)))  -- 274: or the login ID$b$),
      -- an existing member of staff with no work e-mail can still be added
      ('person_check',
       $a$e := e || jsonb_build_object('field','workEmail',
        'says','A work address is how they sign in and how the tool reaches them.');$a$,
       $b$w := w || jsonb_build_object('field','workEmail',  -- 274: a warning
        'says','No work e-mail. They sign in with their login ID and a password, and the tool cannot e-mail them until one is added.');$b$),
      ('person_check',
       $a$e := e || jsonb_build_object('field','mobile',
        'says','A mobile number is required -- it is the second way in when e-mail fails.');$a$,
       $b$w := w || jsonb_build_object('field','mobile',  -- 274: a warning
        'says','No mobile number. Add it when you have it -- it is the other way to reach them.');$b$),
      -- the login ID is the employee number, and the screen is told it
      ('person_add',
       $a$  returning id into v_id;$a$,
       $b$  returning id into v_id;
  -- 274: the login ID is the employee number
  update person set user_id = nullif(btrim(v->>'employeeNo'),'') where id = v_id;$b$),
      ('person_add',
       $a$  return jsonb_build_object('ok', true, 'personId', v_id,$a$,
       $b$  return jsonb_build_object('ok', true, 'personId', v_id,
    'loginId', nullif(btrim(v->>'employeeNo'),''),  -- 274$b$)
    ) t(fn, anchor, repl)
  loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = r.fn;
    if v_def is null then
      raise exception 'Migration 274: % is not there to change.', r.fn;
    end if;
    if position(r.repl in v_def) > 0 then
      raise notice 'Migration 274: % already carries this change.', r.fn;
      continue;
    end if;
    v_n := (length(v_def) - length(replace(v_def, r.anchor, ''))) / length(r.anchor);
    if v_n <> 1 then
      raise exception 'Migration 274: the anchor in % occurs % times, not once: %',
        r.fn, v_n, left(r.anchor, 60);
    end if;
    execute replace(v_def, r.anchor, r.repl);
  end loop;
end
$do$;

-- Everybody who has an employee number has a login ID from today.
update person set user_id = btrim(employee_no)
 where user_id is null and nullif(btrim(employee_no), '') is not null
   and superseded_by is null and left_on is null;

-- ------------------------------------------------------- the salt, by id
-- Changing a password is done signed in, and a person with no work e-mail
-- has nothing else to look the salt up by.
create or replace function public.auth_salt_of(p_person uuid)
returns text language sql stable security definer set search_path to 'public' as $$
  select password_salt from person
   where id = p_person and employment_status = 'ACTIVE' and superseded_by is null
$$;

-- ---------------------------------------------------------------- change
create or replace function public.auth_password_change(
  p_person uuid, p_current_hash text, p_new_salt text, p_new_hash text)
returns jsonb language plpgsql volatile security definer set search_path to 'public' as $$
declare p person;
begin
  select * into p from person
   where id = p_person and employment_status = 'ACTIVE' and superseded_by is null;
  if p.id is null then
    return jsonb_build_object('error','not_a_person');
  end if;
  if coalesce(p_new_salt,'') !~ '^[0-9a-f]{32}$' or coalesce(p_new_hash,'') !~ '^[0-9a-f]{128}$' then
    return jsonb_build_object('error','invalid','reason','That is not a password the tool can store.');
  end if;
  -- somebody who has a password proves they know it; somebody signed in by
  -- Google who never had one is setting their first
  if p.password_hash is not null
     and (p_current_hash is null or p_current_hash <> p.password_hash) then
    return jsonb_build_object('error','wrong_password',
      'reason','That is not your current password.');
  end if;
  update person
     set password_salt = p_new_salt, password_hash = p_new_hash,
         user_id = coalesce(user_id, nullif(btrim(employee_no),''))
   where id = p.id;
  insert into person_event (person_id, kind, note, at)
  values (p.id, 'PASSWORD_CHANGED', 'Changed their own password', now());
  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p.id, 'PASSWORD_CHANGED', 'person', p.id::text, null, null);
  return jsonb_build_object('ok', true,
    'loginId', coalesce(p.user_id, nullif(btrim(p.employee_no),'')),
    'note', 'Your password is changed. Use it from your next sign-in.');
end $$;

-- ----------------------------------------------------------------- issue
create or replace function public.auth_password_issue(
  p_actor uuid, p_person uuid, p_salt text, p_hash text)
returns jsonb language plpgsql volatile security definer set search_path to 'public' as $$
declare a person; p person; v_login text;
begin
  select * into a from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null or not (a.app_role = 'ADMIN' or coalesce(a.department,'') = 'Human Resources') then
    return jsonb_build_object('error','not_permitted',
      'reason','Giving somebody a password is the administrator''s, or Human Resources''.');
  end if;
  select * into p from person
   where id = p_person and employment_status = 'ACTIVE' and superseded_by is null;
  if p.id is null then
    return jsonb_build_object('error','not_a_person','reason','Nobody active by that id.');
  end if;
  if p.id = a.id then
    return jsonb_build_object('error','your_own',
      'reason','Change your own password on My profile, with your current one.');
  end if;
  if p.employee_type = 'SERVICE_ACCOUNT' then
    return jsonb_build_object('error','not_permitted',
      'reason','A service account signs in by Google only.');
  end if;
  if p.app_role = 'ADMIN' and a.app_role <> 'ADMIN' then
    return jsonb_build_object('error','not_permitted',
      'reason','Only an administrator can give an administrator a password.');
  end if;
  v_login := coalesce(p.user_id, nullif(btrim(p.employee_no),''));
  if v_login is null then
    return jsonb_build_object('error','no_login_id',
      'reason','Give them an employee number first: it is their login ID.');
  end if;
  if coalesce(p_salt,'') !~ '^[0-9a-f]{32}$' or coalesce(p_hash,'') !~ '^[0-9a-f]{128}$' then
    return jsonb_build_object('error','invalid','reason','That is not a password the tool can store.');
  end if;

  update person set password_salt = p_salt, password_hash = p_hash, user_id = v_login
   where id = p.id;
  -- whoever was signed in with the old password is not any more
  update auth_session set revoked_at = now()
   where person_id = p.id and source = 'PASSWORD' and revoked_at is null;
  insert into person_event (person_id, kind, note, at)
  values (p.id, 'PASSWORD_ISSUED', 'Temporary password issued by ' || a.full_name, now());
  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (a.id, 'PASSWORD_ISSUED', 'person', p.id::text, null,
          jsonb_build_object('loginId', v_login));
  return jsonb_build_object('ok', true, 'personId', p.id, 'name', p.full_name,
    'loginId', v_login,
    'note', p.full_name || ' signs in with login ID ' || v_login ||
            ' and the temporary password shown, and should change it on My profile.');
end $$;

-- ------------------------------------------------------------ onboarding
create or replace function public.person_onboard_existing(p_actor uuid, p_rows jsonb)
returns jsonb language plpgsql volatile security definer set search_path to 'public' as $$
declare
  a person; r jsonb; v_next int; v_no text; v_id uuid; v_name text; v_chair uuid;
  v_mgr uuid; v_desig uuid; v_fe uuid; v_bo uuid; v_held text;
  made jsonb := '[]'::jsonb; skipped jsonb := '[]'::jsonb;
begin
  select * into a from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null or a.app_role <> 'ADMIN' then
    return jsonb_build_object('error','not_permitted',
      'reason','Onboarding staff in bulk is the administrator''s.');
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then
    return jsonb_build_object('error','invalid','reason','Send the people as a list.');
  end if;

  select id into v_desig from designation where lower(btrim(title)) = 'executive' limit 1;
  select id into v_fe from chair where code = 'FE';
  select id into v_bo from chair where code = 'BO';
  if v_fe is null or v_bo is null then
    return jsonb_build_object('error','no_chair',
      'reason','The Field Executives and Back Office chairs are not there to seat anybody in.');
  end if;
  select coalesce(max((substring(btrim(employee_no) from '^EMP-([0-9]+)$'))::int), 0) + 1
    into v_next from person where btrim(employee_no) ~ '^EMP-[0-9]+$';

  for r in select * from jsonb_array_elements(p_rows) loop
    v_name := regexp_replace(btrim(coalesce(r->>'fullName','')), '\s+', ' ', 'g');
    if length(v_name) < 3 then
      skipped := skipped || jsonb_build_object('name', v_name, 'why', 'no name');
      continue;
    end if;
    select string_agg(coalesce(employee_no, 'no number'), ', ') into v_held
      from person
     where superseded_by is null and left_on is null
       and lower(regexp_replace(btrim(full_name), '\s+', ' ', 'g')) = lower(v_name);
    if v_held is not null then
      skipped := skipped || jsonb_build_object('name', v_name,
        'why', 'already in the tool as ' || v_held);
      continue;
    end if;
    if coalesce(r->>'salt','') !~ '^[0-9a-f]{32}$' or coalesce(r->>'hash','') !~ '^[0-9a-f]{128}$' then
      skipped := skipped || jsonb_build_object('name', v_name, 'why', 'no password');
      continue;
    end if;
    v_chair := case upper(coalesce(r->>'chair','')) when 'FE' then v_fe else v_bo end;
    v_mgr := null;
    if nullif(r->>'managerId','') is not null then
      select id into v_mgr from person
       where id = (r->>'managerId')::uuid and employment_status = 'ACTIVE'
         and superseded_by is null and employee_type <> 'SERVICE_ACCOUNT';
    end if;

    v_no := 'EMP-' || lpad(v_next::text, 4, '0');
    v_next := v_next + 1;
    insert into person (full_name, employee_no, user_id, employee_type, department,
                        designation_id, manager_id, employment_status, app_role,
                        source_ref, password_salt, password_hash)
    values (v_name, v_no, v_no, 'EMPLOYEE', 'Operations', v_desig, v_mgr, 'ACTIVE',
            'VIEWER', left('onboard-2026-10 ' || coalesce(r->>'location',''), 200),
            r->>'salt', r->>'hash')
    returning id into v_id;
    insert into chair_holder (chair_id, person_id, is_primary, from_date)
    values (v_chair, v_id, true, current_date);
    insert into person_event (person_id, kind, note, at)
    values (v_id, 'CREATED',
      'Onboarded by ' || a.full_name || ' from the October work record (' ||
      coalesce(nullif(r->>'location',''), 'no location') || ')', now());
    made := made || jsonb_build_object('name', v_name, 'employeeNo', v_no,
      'personId', v_id, 'chair', case when v_chair = v_fe then 'FE' else 'BO' end,
      'managerId', v_mgr);
  end loop;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (a.id, 'PEOPLE_ONBOARDED', 'person', null, null,
          jsonb_build_object('created', jsonb_array_length(made),
                             'skipped', jsonb_array_length(skipped)));
  return jsonb_build_object('ok', true, 'created', made, 'skipped', skipped);
end $$;

revoke execute on function public.auth_salt_of(uuid) from public, anon, authenticated;
revoke execute on function public.auth_password_change(uuid, text, text, text) from public, anon, authenticated;
revoke execute on function public.auth_password_issue(uuid, uuid, text, text) from public, anon, authenticated;
revoke execute on function public.person_onboard_existing(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.auth_salt_of(uuid) to service_role;
grant execute on function public.auth_password_change(uuid, text, text, text) to service_role;
grant execute on function public.auth_password_issue(uuid, uuid, text, text) to service_role;
grant execute on function public.person_onboard_existing(uuid, jsonb) to service_role;

-- --------------------------------------------------------------- the proof
-- Inside a subtransaction that is rolled back. Hashes are stand-ins: the
-- database only ever compares the hash it is handed with the one it holds.
do $guard$
declare v_admin uuid; v_hr uuid; v_some uuid; o jsonb; v_new uuid; v_login text;
  s1 text := repeat('a', 32); h1 text := repeat('1', 128);
  s2 text := repeat('b', 32); h2 text := repeat('2', 128);
begin
  select id into v_admin from person where app_role = 'ADMIN' and employment_status = 'ACTIVE'
     and superseded_by is null and employee_type = 'SERVICE_ACCOUNT' limit 1;
  select id into v_hr from person where department = 'Human Resources' and app_role <> 'ADMIN'
     and employment_status = 'ACTIVE' and superseded_by is null limit 1;
  if v_admin is null then
    raise notice 'Migration 274: no administrator to check against here.';
    return;
  end if;
  begin
    o := person_onboard_existing(v_admin, jsonb_build_array(
      jsonb_build_object('fullName','Probe  Onboarded Person','chair','FE','location','Probe',
                         'salt', s1, 'hash', h1),
      jsonb_build_object('fullName', (select full_name from person where id = v_admin),
                         'chair','BO','salt', s1, 'hash', h1)));
    if jsonb_array_length(o->'created') <> 1 or jsonb_array_length(o->'skipped') <> 1 then
      raise exception 'Migration 274: onboarding did not create one and refuse the duplicate: %', o;
    end if;
    v_new := (o#>>'{created,0,personId}')::uuid;
    v_login := o#>>'{created,0,employeeNo}';
    if (select full_name from person where id = v_new) <> 'Probe Onboarded Person' then
      raise exception 'Migration 274: the name was not tidied.';
    end if;
    if auth_salt(lower(v_login)) is distinct from s1 then
      raise exception 'Migration 274: the salt is not found by login ID.';
    end if;
    o := auth_login(v_login, h1, '274-probe', null);
    if o ? 'error' or o->>'id' is distinct from v_new::text then
      raise exception 'Migration 274: the login ID does not sign in: %', o;
    end if;
    if auth_login(v_login, h2, '274-probe-x', null)->>'error' is distinct from 'bad_credentials' then
      raise exception 'Migration 274: a wrong password was let in by login ID.';
    end if;
    if auth_password_change(v_new, h2, s2, h2)->>'error' is distinct from 'wrong_password' then
      raise exception 'Migration 274: a password was changed without the current one.';
    end if;
    if auth_password_change(v_new, h1, s2, h2)->>'ok' is null
       or auth_login(v_login, h2, '274-probe-2', null) ? 'error' then
      raise exception 'Migration 274: the changed password does not sign in.';
    end if;
    if v_hr is not null and auth_password_issue(v_hr, v_admin, s1, h1)->>'error'
       is distinct from 'not_permitted' then
      raise exception 'Migration 274: HR gave an administrator a password.';
    end if;
    if auth_password_issue(v_admin, v_new, s1, h1)->>'loginId' is distinct from v_login then
      raise exception 'Migration 274: the administrator could not issue a password.';
    end if;
    if auth_password_issue(v_admin, v_admin, s1, h1)->>'error' is distinct from 'your_own' then
      raise exception 'Migration 274: somebody issued their own password.';
    end if;
    if not exists (select 1 from jsonb_array_elements(person_check(jsonb_build_object(
          'fullName','Probe Person','employeeNo','EMP-9999',
          'chairId',(select id from chair where code = 'FE')))->'warnings') x
         where x->>'field' = 'workEmail') then
      raise exception 'Migration 274: no work e-mail is not a warning.';
    end if;
    raise exception using errcode = 'P0001', message = '274-rollback';
  exception when others then
    if sqlerrm <> '274-rollback' then raise; end if;
  end;
  raise notice 'Migration 274: a login ID signs in, a password can be issued and changed, and staff can be onboarded.';
end
$guard$;
