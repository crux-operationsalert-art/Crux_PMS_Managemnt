-- Signing in opens the chair (migration 272)
--
-- "SC one shows how Manish Shukla's profile gets opened by admin and this is
--  how it should actually open for that chair, but SC2 is how it is opening
--  when Manish Shukla is logging in" -- 27 Oct.
--
-- Each assertion is one of those sentences:
--
--   a Google sign-in is handed the same person a reload and Act as are
--   so is a password sign-in
--   that person carries the chair, the department and the screens
--   and the doors stay where they were: wrong domain, not on the master,
--   wrong password, all still refused
--
-- Everything is rolled back.

begin;

do $t$
declare ch uuid; p uuid; g jsonb; w jsonb; l jsonb;
begin
  insert into app_setting (key, value, plain_language, group_name)
  values ('workspace_domain', 'cruxindia.co.in', 'test', 'Sign-in')
  on conflict (key) do nothing;

  insert into chair (code, title, level) values ('SI_BM', 'Branch Manager', 'branch')
    returning id into ch;
  insert into person (employee_no, full_name, work_email, department, app_role, employment_status)
    values ('SI-001', 'Sign In Manager', 'si.manager@cruxindia.co.in', 'Operations',
            'MANAGER', 'ACTIVE')
    returning id into p;
  insert into chair_holder (chair_id, person_id, from_date, is_primary)
    values (ch, p, current_date, true);

  -- -------------------------------------------------------- Google sign-in
  g := auth_google('si.manager@cruxindia.co.in', 'si-token-g', null);
  w := auth_whoami('si-token-g');
  if g ? 'error' then
    raise exception 'FAIL  a seated Workspace person could not sign in: %', g;
  end if;
  if g is distinct from w then
    raise exception 'FAIL  a Google sign-in is handed a different person from a reload. '
                    'Sign-in: %  Reload: %', g, w;
  end if;
  raise notice 'PASS  a Google sign-in is handed the same person a reload and Act as are';

  if g->>'chair_title' is distinct from 'Branch Manager'
     or g->>'department' is distinct from 'Operations' then
    raise exception 'FAIL  the sign-in does not carry the chair and department, so the header '
                    'prints the bare role: %', g;
  end if;
  if jsonb_typeof(g->'screens') is distinct from 'array'
     or not (g->'screens') ? 'reports' then
    raise exception 'FAIL  the sign-in does not carry the chair''s screens, so the navigation '
                    'falls back to the role: %', g->'screens';
  end if;
  if g->>'scope_level' is distinct from 'branch' then
    raise exception 'FAIL  the sign-in does not say what level the chair is at: %', g->'scope_level';
  end if;
  raise notice 'PASS  and that person carries the chair, the department and its screens';

  -- ------------------------------------------------------ password sign-in
  update person set password_hash = 'si-hash' where id = p;
  l := auth_login('si.manager@cruxindia.co.in', 'si-hash', 'si-token-l', null);
  if l is distinct from auth_whoami('si-token-l') then
    raise exception 'FAIL  a password sign-in is handed a different person from a reload: %', l;
  end if;
  raise notice 'PASS  so is a password sign-in';

  -- ---------------------------------------------- the doors did not move
  if auth_login('si.manager@cruxindia.co.in', 'nope', 'si-token-x', null)->>'error'
     is distinct from 'bad_credentials' then
    raise exception 'FAIL  a wrong password was let in';
  end if;
  if auth_google('somebody@gmail.com', 'si-token-y', null)->>'error'
     is distinct from 'wrong_domain' then
    raise exception 'FAIL  a personal address was let in';
  end if;
  if auth_google('nobody@cruxindia.co.in', 'si-token-z', null)->>'error'
     is distinct from 'not_a_person' then
    raise exception 'FAIL  somebody not on the people master was let in';
  end if;
  if exists (select 1 from auth_session where token_hash in ('si-token-x','si-token-y','si-token-z')) then
    raise exception 'FAIL  a refused sign-in still made a session';
  end if;
  raise notice 'PASS  and the doors stay where they were: wrong password, wrong domain and '
               'not on the master are still refused, with no session made';

  raise notice '--- signing in opens the chair: every assertion passed ---';
end $t$;

rollback;
