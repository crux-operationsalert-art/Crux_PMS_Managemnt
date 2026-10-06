-- The account that runs the tool is not a person who works here (243, 245)
--
-- "Operations.alert is the admin or email to manage this tool and not an
--  employee to be reporting to anyone."
--
-- Migration 243 said that by adding a sixth employee_type and widening the
-- thirteen functions that already knew a client contact is not staff. That
-- left two holes, found by measuring rather than by reading, and 245 closed
-- them. What is asserted here is the whole rule rather than either half:
--
--   * a service account is not staff, by EITHER of the two staff tests --
--     is_staff and person_is_staff disagreed about exactly this person, and
--     the one that said yes is the one the People upload template reads;
--   * it is not in the reporting line in either direction, and that is
--     enforced by the database rather than by a predicate repeated in the
--     four walkers that would otherwise carry it;
--   * none of which costs it the administrator's powers, because it still
--     has to administer the tool.
--
-- Everything is rolled back.

begin;

do $seed$
declare
  p_adm uuid; p_svc uuid; p_top uuid; p_low uuid;
begin
  insert into person (full_name, work_email, app_role)
    values ('AC Admin', 'ac.adm@example.invalid', 'ADMIN') returning id into p_adm;
  -- AC Top carries an employee number because is_staff asks for one of
  -- three things -- a number, our own domain, or a chair -- and a fixture
  -- with none of the three is not a member of staff by anybody's reading.
  insert into person (full_name, work_email, app_role, employee_no)
    values ('AC Top', 'ac.top@example.invalid', 'MANAGER', 'AC-0001')
    returning id into p_top;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('AC Low', 'ac.low@example.invalid', 'VIEWER', p_top) returning id into p_low;

  -- The account itself, written the way the live one is: ADMIN, an address
  -- at our own domain, no employee number, no chair, nobody above or below.
  -- The domain is the detail that mattered -- it is why is_staff said yes.
  insert into person (full_name, work_email, app_role, employee_type)
    values ('AC Service', 'ac.service@cruxindia.co.in', 'ADMIN', 'SERVICE_ACCOUNT')
    returning id into p_svc;

  create temporary table _ac (k text primary key, v uuid) on commit drop;
  insert into _ac values ('adm',p_adm),('svc',p_svc),('top',p_top),('low',p_low);
end $seed$;

do $t$
declare
  p_adm uuid; p_svc uuid; p_top uuid; p_low uuid;
  n int; v_caught boolean; v_ok boolean;
begin
  select v into p_adm from _ac where _ac.k = 'adm';
  select v into p_svc from _ac where _ac.k = 'svc';
  select v into p_top from _ac where _ac.k = 'top';
  select v into p_low from _ac where _ac.k = 'low';

  -- ----------------------------------------------------- it is not staff
  if is_staff(p_svc) then
    raise exception 'FAIL  is_staff calls the service account staff. That is '
                    'what put it in the People upload template.';
  end if;
  if person_is_staff(p_svc) then
    raise exception 'FAIL  person_is_staff calls the service account staff';
  end if;
  raise notice 'PASS  neither staff test calls a service account staff';

  -- The domain arm is the one that caught it out, so it is named: an
  -- address at our own domain is not, on its own, a member of staff.
  if not is_staff(p_top) or not person_is_staff(p_top) then
    raise exception 'FAIL  an ordinary person stopped reading as staff. The '
                    'test has become stricter than intended.';
  end if;
  raise notice 'PASS  and an ordinary person still does';

  -- ------------------------------------------- nobody reports to it
  v_caught := false;
  begin
    update person set manager_id = p_svc where id = p_low;
    raise exception using errcode = 'P0001', message = 'it went through';
  exception
    when sqlstate 'P0001' then v_caught := sqlerrm <> 'it went through';
    when others then v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL  somebody was given the service account as their manager';
  end if;
  raise notice 'PASS  nobody can be made to report to a service account';

  -- ...including at the moment they are created, which is the path the
  -- People upload and person_add both take.
  v_caught := false;
  begin
    insert into person (full_name, work_email, app_role, manager_id)
      values ('AC New', 'ac.new@example.invalid', 'VIEWER', p_svc);
    raise exception using errcode = 'P0001', message = 'it went through';
  exception
    when sqlstate 'P0001' then v_caught := sqlerrm <> 'it went through';
    when others then v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL  somebody was CREATED under the service account';
  end if;
  raise notice 'PASS  and nobody can be created under one either';

  -- ------------------------------------------- and it reports to nobody
  v_caught := false;
  begin
    update person set manager_id = p_top where id = p_svc;
    raise exception using errcode = 'P0001', message = 'it went through';
  exception
    when sqlstate 'P0001' then v_caught := sqlerrm <> 'it went through';
    when others then v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL  the service account was given a manager';
  end if;
  raise notice 'PASS  and it cannot be given a manager';

  v_caught := false;
  begin
    insert into person (full_name, work_email, app_role, employee_type, manager_id)
      values ('AC Svc 2', 'ac.svc2@cruxindia.co.in', 'ADMIN', 'SERVICE_ACCOUNT', p_top);
    raise exception using errcode = 'P0001', message = 'it went through';
  exception
    when sqlstate 'P0001' then v_caught := sqlerrm <> 'it went through';
    when others then v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL  a service account was created WITH a manager';
  end if;
  raise notice 'PASS  nor created with one';

  -- ------------------------------- the rule is not wider than it says
  -- A rule that refuses the one case must not refuse the hundred others.
  v_ok := false;
  begin
    update person set manager_id = p_adm where id = p_low;
    v_ok := true;
    raise exception using errcode = 'P0001', message = 'undo';
  exception
    when sqlstate 'P0001' then if sqlerrm <> 'undo' then v_ok := false; end if;
    when others then v_ok := false;
  end;
  if not v_ok then
    raise exception 'FAIL  an ordinary move between two people is now refused';
  end if;
  raise notice 'PASS  an ordinary move between two people is untouched';

  -- ---------------------------------- so the walkers cannot carry it
  -- org_subtree, app_subtree, org_team_tree and perf_reminder_sweep have no
  -- employee_type test of their own. They do not need one: there is no
  -- reporting edge for them to follow.
  select count(*) into n from person p
   where p.employment_status = 'ACTIVE' and p.superseded_by is null
     and p.id <> p_svc
     and exists (select 1 from org_subtree(p.id) s where s.person_id = p_svc);
  if n > 0 then
    raise exception 'FAIL  the service account is inside % org_subtree(s)', n;
  end if;
  select count(*) into n from person p
   where p.employment_status = 'ACTIVE' and p.superseded_by is null
     and p.id <> p_svc
     and exists (select 1 from perf_line(p.id) l where l.person_id = p_svc);
  if n > 0 then
    raise exception 'FAIL  the service account is inside % reporting line(s)', n;
  end if;
  select count(*) into n from person p
   where p.employment_status = 'ACTIVE' and p.superseded_by is null
     and p.id <> p_svc
     and exists (select 1 from kpi_subtree_people(p.id) k where k.person_id = p_svc);
  if n > 0 then
    raise exception 'FAIL  % person/people are offered the service account '
                    'as somebody to set measures for', n;
  end if;
  raise notice 'PASS  it is in nobody''s subtree, line or measure-setting list';

  -- -------------------------------------- and it still runs the tool
  -- This is the half that must NOT have changed. It administers the tool;
  -- it is simply not measured by it.
  if not exists (select 1 from person
                  where id = p_svc and app_role = 'ADMIN'
                    and employment_status = 'ACTIVE' and superseded_by is null) then
    raise exception 'FAIL  the service account lost its ADMIN role';
  end if;
  select count(*) into n from person p
   where p.employment_status = 'ACTIVE' and p.superseded_by is null
     and p.id <> p_svc
     and perf_rel(p_svc, p.id) is distinct from 'admin';
  if n > 0 then
    raise exception 'FAIL  the service account no longer reads as '
                    'administrator over % person/people', n;
  end if;
  raise notice 'PASS  and it still administers the tool over everybody';

  -- It is also out of the flat people list, which is the screen an
  -- administrator would otherwise use to put it back.
  if exists (select 1 from jsonb_array_elements(
               org_people_table(p_adm)->'people') x
              where (x->>'personId')::uuid = p_svc) then
    raise exception 'FAIL  the service account is in the All people list';
  end if;
  raise notice 'PASS  and it is not in the list of everybody who works here';

  raise notice '--- the account that runs the tool: every assertion passed ---';
end $t$;

rollback;
