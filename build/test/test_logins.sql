-- A login ID and a password for existing staff (migration 274)
--
-- "I am still not able to add existing staff as an admin" ... "Yes, using
--  login ID and password along with all current ones" -- 27 Oct.
--
-- Each assertion is one of those sentences:
--
--   a login ID signs in, and so does the work e-mail it stands beside
--   the wrong password is still refused, by either
--   a person changes their own password, given the current one
--   an administrator or HR issues one -- HR not for an administrator,
--   nobody for themselves, nobody for a service account
--   issuing one ends the sessions the old one opened
--   existing staff are onboarded in one go, numbered on, seated, and
--   never twice under one name
--   and the add form takes somebody with no work e-mail or mobile
--
-- Hashes are stand-ins: the database only compares the hash it is handed
-- with the one it holds. Everything is rolled back.

begin;

do $t$
declare
  p_admin uuid; p_hr uuid; p_svc uuid; p_staff uuid; o jsonb; v_new uuid; v_no text;
  s1 text := repeat('a', 32); h1 text := repeat('1', 128);
  s2 text := repeat('b', 32); h2 text := repeat('2', 128);
  s3 text := repeat('c', 32); h3 text := repeat('3', 128);
  v_fe uuid;
begin
  -- the rows 274 expects and a rebuilt database does not carry
  insert into designation (title, seniority) select 'Executive', 0
   where not exists (select 1 from designation where lower(title) = 'executive');
  insert into chair (code, title, level) values ('FE','Field Executives / Verifiers','executive')
    on conflict do nothing;
  insert into chair (code, title, level) values ('BO','Back Office / Processing Executives','executive')
    on conflict do nothing;
  select id into v_fe from chair where code = 'FE';

  insert into person (employee_no, full_name, work_email, app_role, employment_status, employee_type)
    values ('EMP-0900', 'LG Admin', 'lg.admin@cruxindia.co.in', 'ADMIN', 'ACTIVE', 'EMPLOYEE')
    returning id into p_admin;
  insert into person (employee_no, full_name, work_email, department, app_role, employment_status)
    values ('EMP-0901', 'LG Hr', 'lg.hr@cruxindia.co.in', 'Human Resources', 'MANAGER', 'ACTIVE')
    returning id into p_hr;
  insert into person (full_name, work_email, app_role, employment_status, employee_type)
    values ('LG Service', 'lg.svc@cruxindia.co.in', 'ADMIN', 'ACTIVE', 'SERVICE_ACCOUNT')
    returning id into p_svc;
  insert into person (employee_no, user_id, full_name, work_email, app_role, employment_status,
                      password_salt, password_hash)
    values ('EMP-0902', 'EMP-0902', 'LG Staff', 'lg.staff@cruxindia.co.in', 'VIEWER', 'ACTIVE', s1, h1)
    returning id into p_staff;

  -- ------------------------------------------- the login ID is a way in
  if auth_salt('emp-0902') is distinct from s1 or auth_salt('LG.Staff@cruxindia.co.in') is distinct from s1 then
    raise exception 'FAIL  the salt is not found by login ID and by e-mail alike';
  end if;
  o := auth_login(' EMP-0902 ', h1, 'lg-t1', null);
  if o ? 'error' or o->>'id' is distinct from p_staff::text then
    raise exception 'FAIL  the login ID does not sign in: %', o;
  end if;
  if auth_login('lg.staff@cruxindia.co.in', h1, 'lg-t2', null) ? 'error' then
    raise exception 'FAIL  the work e-mail stopped signing in';
  end if;
  raise notice 'PASS  a login ID signs in, and so does the work e-mail it stands beside';
  if auth_login('EMP-0902', h2, 'lg-tx', null)->>'error' is distinct from 'bad_credentials' then
    raise exception 'FAIL  a wrong password was let in by login ID';
  end if;
  raise notice 'PASS  the wrong password is still refused';

  -- ------------------------------------------------------- changing it
  if auth_password_change(p_staff, h2, s2, h2)->>'error' is distinct from 'wrong_password' then
    raise exception 'FAIL  a password was changed without the current one';
  end if;
  if auth_password_change(p_staff, h1, 'not-hex', h2)->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  something that is not a stored password was stored';
  end if;
  if auth_password_change(p_staff, h1, s2, h2)->>'ok' is null
     or auth_login('EMP-0902', h2, 'lg-t3', null) ? 'error'
     or not (auth_login('EMP-0902', h1, 'lg-t4', null) ? 'error') then
    raise exception 'FAIL  after a change the new password must sign in and the old one must not';
  end if;
  raise notice 'PASS  a person changes their own password, given the current one';

  -- ----------------------------------------------------------- issuing
  if auth_password_issue(p_staff, p_hr, s3, h3)->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  somebody who is neither HR nor an administrator issued a password';
  end if;
  if auth_password_issue(p_hr, p_admin, s3, h3)->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  HR gave an administrator a password, which is taking their keys';
  end if;
  if auth_password_issue(p_admin, p_admin, s3, h3)->>'error' is distinct from 'your_own' then
    raise exception 'FAIL  an administrator issued their own password';
  end if;
  if auth_password_issue(p_admin, p_svc, s3, h3)->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  a service account was given a password';
  end if;
  o := auth_password_issue(p_hr, p_staff, s3, h3);
  if o->>'loginId' is distinct from 'EMP-0902' then
    raise exception 'FAIL  HR could not issue an ordinary member of staff a password: %', o;
  end if;
  raise notice 'PASS  an administrator or HR issues a password -- HR not for an administrator, '
               'nobody for themselves, nobody for a service account';
  if exists (select 1 from auth_session where token_hash in ('lg-t1','lg-t3') and revoked_at is null) then
    raise exception 'FAIL  the sessions the old password opened are still live';
  end if;
  if exists (select 1 from auth_session where token_hash = 'lg-t2' and revoked_at is null) then
    raise exception 'FAIL  the e-mail sign-in session was left open too';
  end if;
  if auth_login('EMP-0902', h3, 'lg-t5', null) ? 'error' then
    raise exception 'FAIL  the issued password does not sign in';
  end if;
  raise notice 'PASS  issuing one ends every session the old password opened';

  -- -------------------------------------------------------- onboarding
  if person_onboard_existing(p_hr, '[]'::jsonb)->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  onboarding in bulk is the administrator''s, and HR did it';
  end if;
  o := person_onboard_existing(p_admin, jsonb_build_array(
    jsonb_build_object('fullName','  Asha   Field ', 'chair','FE', 'location','Pune',
                       'managerId', p_hr, 'salt', s1, 'hash', h1),
    jsonb_build_object('fullName','Bala Back', 'chair','BO', 'location','Mumbai', 'salt', s1, 'hash', h1),
    jsonb_build_object('fullName','LG Staff', 'chair','BO', 'salt', s1, 'hash', h1),
    jsonb_build_object('fullName','No Password', 'chair','BO')));
  if jsonb_array_length(o->'created') <> 2 then
    raise exception 'FAIL  expected two onboarded: %', o;
  end if;
  if not exists (select 1 from jsonb_array_elements(o->'skipped') x
                  where x->>'name' = 'LG Staff' and x->>'why' like 'already in the tool as EMP-0902%') then
    raise exception 'FAIL  a name already in the tool was not refused by name: %', o->'skipped';
  end if;
  if (o#>>'{created,0,employeeNo}', o#>>'{created,1,employeeNo}') is distinct from ('EMP-0903','EMP-0904') then
    raise exception 'FAIL  onboarded people are not numbered on from the last number: %', o->'created';
  end if;
  v_new := (o#>>'{created,0,personId}')::uuid;
  select employee_no into v_no from person where id = v_new;
  if (select full_name from person where id = v_new) <> 'Asha Field'
     or (select user_id from person where id = v_new) is distinct from v_no
     or (select manager_id from person where id = v_new) is distinct from p_hr
     or not exists (select 1 from chair_holder where person_id = v_new and chair_id = v_fe and to_date is null) then
    raise exception 'FAIL  an onboarded person is not tidied, given a login ID, managed and seated';
  end if;
  if (select manager_id from person where full_name = 'Bala Back') is not null then
    raise exception 'FAIL  a manager was guessed where none was given';
  end if;
  if auth_login(v_no, h1, 'lg-t6', null) ? 'error' then
    raise exception 'FAIL  an onboarded person cannot sign in with their login ID';
  end if;
  raise notice 'PASS  existing staff are onboarded in one go, numbered on, seated, given a login ID, '
               'and never twice under one name';

  -- ------------------------------------------------- the single add form
  o := person_check(jsonb_build_object('fullName','Chetan Nomail','employeeNo','EMP-0950',
                                       'chairId', v_fe));
  if not (o->>'ok')::boolean then
    raise exception 'FAIL  somebody with no work e-mail or mobile is still refused: %', o->'errors';
  end if;
  if not exists (select 1 from jsonb_array_elements(o->'warnings') x where x->>'field' = 'workEmail')
     or not exists (select 1 from jsonb_array_elements(o->'warnings') x where x->>'field' = 'mobile') then
    raise exception 'FAIL  no work e-mail and no mobile must still be said, as warnings: %', o->'warnings';
  end if;
  o := person_add(p_admin, jsonb_build_object('fullName','Chetan Nomail','employeeNo','EMP-0950',
                                              'chairId', v_fe));
  if o->>'loginId' is distinct from 'EMP-0950'
     or (select user_id from person where id = (o->>'personId')::uuid) is distinct from 'EMP-0950' then
    raise exception 'FAIL  a person added by the form has no login ID: %', o;
  end if;
  raise notice 'PASS  and the add form takes somebody with no work e-mail or mobile, with a login ID';

  raise notice '--- login IDs and passwords: every assertion passed ---';
end $t$;

rollback;
