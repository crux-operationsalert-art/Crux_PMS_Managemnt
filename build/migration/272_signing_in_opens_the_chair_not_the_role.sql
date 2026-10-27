-- Signing in opens the chair, not the bare role
--
-- The owner, 27 Oct, with two screenshots: Manish Shukla's Crux opened by
-- the administrator (Act as) reads "OPERATIONS · Head — Operations", with
-- Clients, My team & structure, Hiring & pending chairs, Joining, Reports and
-- History in the navigation. The same Manish Shukla signing in himself reads
-- "MANAGER · MANAGER", with Dashboard, My profile, Performance, Visits, OGL
-- and Escalations and nothing else. "This is how it should actually open for
-- that chair" -- the first one.
--
-- Why the two differ. The page draws itself from the person object it is
-- handed: start(person) paints the chair title, the department and, through
-- paintNav, the screens the person may open. Act as hands it the answer of
-- auth_whoami, which carries designation, chair_title, department,
-- scope_level and the screen list (access_screens). So does every reload
-- (/api/me). But a fresh sign-in hands it what auth_google or auth_login
-- returned, and both returned four fields: id, full_name, work_email and
-- app_role. No screens, so the navigation fell back to what the bare role
-- allows; no chair or department, so the header printed the role twice.
-- The person was the same, the session was the same, and the access policy
-- was never asked.
--
-- One answer to "who is this", in one place: both sign-ins now return
-- auth_whoami's answer for the session they have just made. Nothing about
-- who may sign in changes -- the domain check, the people-master check, the
-- password comparison and the lock-out are untouched, and run first.
do $do$
declare r record; v_def text; v_n int;
  v_anchor text := $a$  return jsonb_build_object('id', p.id, 'full_name', p.full_name,
    'work_email', p.work_email, 'app_role', p.app_role);$a$;
  v_repl text := $b$  -- 272: the same answer /api/me and Act as give -- the chair, the
  -- department and the screens -- so a fresh sign-in opens the chair's view.
  return auth_whoami(p_token_hash);$b$;
begin
  for r in select unnest(array['auth_google','auth_login']) fn loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = r.fn;
    if v_def is null then
      raise exception 'Migration 272: % is not there to change.', r.fn;
    end if;
    if position(v_repl in v_def) > 0 then
      raise notice 'Migration 272: % already answers with auth_whoami.', r.fn;
      continue;
    end if;
    v_n := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
    if v_n <> 1 then
      raise exception 'Migration 272: the return in % occurs % times, not once.', r.fn, v_n;
    end if;
    execute replace(v_def, v_anchor, v_repl);
  end loop;
end
$do$;

-- --------------------------------------------------------------- the proof
-- Against a real chair holder, inside a subtransaction that is rolled back:
-- sign in by Google and by password, and compare with what Act as and a
-- reload are given for the same session.
do $guard$
declare v_p person; g jsonb; w jsonb; l jsonb; res text;
begin
  select p.* into v_p from person p
   where p.employment_status = 'ACTIVE' and p.superseded_by is null
     and p.employee_type <> 'SERVICE_ACCOUNT'
     and lower(p.work_email) like '%@cruxindia.co.in'
     and exists (select 1 from chair_holder h where h.person_id = p.id and h.to_date is null)
   order by p.employee_no limit 1;
  if v_p.id is null then
    raise notice 'Migration 272: no seated Workspace person to check against here.';
    return;
  end if;

  begin
    g := auth_google(v_p.work_email, '272-probe-g', null);
    w := auth_whoami('272-probe-g');
    if g ? 'error' then
      raise exception 'Migration 272: Google sign-in refused % : %', v_p.full_name, g;
    end if;
    if g - 'acting' is distinct from w - 'acting' then
      raise exception 'Migration 272: Google sign-in and /api/me disagree: % vs %', g, w;
    end if;
    if g->'screens' is null or jsonb_array_length(g->'screens') = 0 then
      raise exception 'Migration 272: Google sign-in carries no screens: %', g;
    end if;

    update person set password_hash = '272-probe-hash' where id = v_p.id;
    l := auth_login(v_p.work_email, '272-probe-hash', '272-probe-l', null);
    if l - 'acting' is distinct from auth_whoami('272-probe-l') - 'acting' then
      raise exception 'Migration 272: password sign-in and /api/me disagree: %', l;
    end if;
    if auth_login(v_p.work_email, 'wrong', '272-probe-x', null)->>'error' is distinct from 'bad_credentials' then
      raise exception 'Migration 272: a wrong password was let in.';
    end if;
    raise exception using errcode = 'P0001', message = '272-rollback';
  exception when others then
    if sqlerrm <> '272-rollback' then raise; end if;
  end;
  raise notice 'Migration 272: both sign-ins now open % as the chair (% screens), as Act as does.',
    v_p.full_name, jsonb_array_length(coalesce(g->'screens','[]'::jsonb));
end
$guard$;
