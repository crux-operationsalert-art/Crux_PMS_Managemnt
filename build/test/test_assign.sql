-- Assigning people: the gaps the list finds, closed (migration 248)
--
-- "I am able to update and change the managers, but nothing else designation,
--  chair, location, department and other important aspects."
-- "...one that you missed about assigning People  No manager 1 · No chair 2 ·
--  No designation 49 · No department 49 · No location"
--
-- Every assertion below is one sentence of that, said in SQL:
--
--   the gate            -> administrator and HR, and nobody else
--   the role            -> the administrator's alone, and never your own
--   atomic              -> a bad field does not let a good one through
--   the picked lists    -> a designation or a place that does not exist is
--                          refused by name, not written
--   the place           -> a seating belongs to a chair, and the wrong one
--                          is refused
--   the chair           -> held, not owned: the old holding is closed
--   the line            -> still org_move_person's, including the ring
--   in bulk             -> one refusal does not stop the rest, and is reported
--   the count moves     -> the chip that said 1 says 0 afterwards
--
-- Everything is rolled back.

begin;

do $seed$
declare
  p_adm uuid; p_hr uuid; p_other uuid; p_a uuid; p_b uuid; p_c uuid;
  v_d1 uuid; v_d2 uuid; v_ch1 uuid; v_ch2 uuid; v_s1 uuid; v_s2 uuid;
begin
  insert into person (full_name, work_email, app_role)
    values ('AS Admin','as.adm@example.invalid','ADMIN') returning id into p_adm;
  insert into person (full_name, work_email, app_role, department)
    values ('AS HR','as.hr@example.invalid','MANAGER','Human Resources')
    returning id into p_hr;
  insert into person (full_name, work_email, app_role)
    values ('AS Other','as.other@example.invalid','MANAGER') returning id into p_other;

  -- Three people with gaps: no designation, no department, no chair.
  insert into person (full_name, work_email, app_role)
    values ('AS Gap One','as.g1@example.invalid','VIEWER') returning id into p_a;
  insert into person (full_name, work_email, app_role)
    values ('AS Gap Two','as.g2@example.invalid','VIEWER') returning id into p_b;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('AS Gap Three','as.g3@example.invalid','VIEWER', p_a) returning id into p_c;

  insert into designation (title, seniority) values ('AS Officer', 50)
    returning id into v_d1;
  insert into designation (title, seniority) values ('AS Manager', 30)
    returning id into v_d2;

  insert into chair (code, title, level) values ('AS-C1','AS Chair One','BRANCH')
    returning id into v_ch1;
  insert into chair (code, title, level) values ('AS-C2','AS Chair Two','BRANCH')
    returning id into v_ch2;
  insert into chair_seating (chair_id, scope_label) values (v_ch1, 'AS Mumbai')
    returning id into v_s1;
  insert into chair_seating (chair_id, scope_label) values (v_ch2, 'AS Ranchi')
    returning id into v_s2;

  create temporary table _as (k text primary key, v uuid) on commit drop;
  insert into _as values ('adm',p_adm),('hr',p_hr),('other',p_other),
                         ('a',p_a),('b',p_b),('c',p_c),
                         ('d1',v_d1),('d2',v_d2),
                         ('ch1',v_ch1),('ch2',v_ch2),('s1',v_s1),('s2',v_s2);
end $seed$;

do $t$
declare
  p_adm uuid; p_hr uuid; p_other uuid; p_a uuid; p_b uuid; p_c uuid;
  v_d1 uuid; v_d2 uuid; v_ch1 uuid; v_ch2 uuid; v_s1 uuid; v_s2 uuid;
  o jsonb; n int; before_no_dept int; after_no_dept int;
begin
  select v into p_adm   from _as where _as.k='adm';
  select v into p_hr    from _as where _as.k='hr';
  select v into p_other from _as where _as.k='other';
  select v into p_a     from _as where _as.k='a';
  select v into p_b     from _as where _as.k='b';
  select v into p_c     from _as where _as.k='c';
  select v into v_d1    from _as where _as.k='d1';
  select v into v_d2    from _as where _as.k='d2';
  select v into v_ch1   from _as where _as.k='ch1';
  select v into v_ch2   from _as where _as.k='ch2';
  select v into v_s1    from _as where _as.k='s1';
  select v into v_s2    from _as where _as.k='s2';

  -- ------------------------------------------------------------- the gate
  if org_person_set(p_other, p_a, jsonb_build_object('department','Sales'))
     ->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  an ordinary manager changed somebody''s department';
  end if;
  if coalesce((org_assign_options(p_other)->>'mayUse')::boolean,false) then
    raise exception 'FAIL  an ordinary manager was handed the dropdowns';
  end if;
  raise notice 'PASS  assigning people is not an ordinary manager''s';

  o := org_person_set(p_adm, p_a, jsonb_build_object('department','Operations'));
  if o->>'error' is not null then
    raise exception 'FAIL  the administrator could not set a department: %', o;
  end if;
  o := org_person_set(p_hr, p_b, jsonb_build_object('department','Operations'));
  if o->>'error' is not null then
    raise exception 'FAIL  Human Resources could not set a department: %', o;
  end if;
  raise notice 'PASS  the administrator and Human Resources both can';

  -- ------------------------------------------------------------- the role
  -- HR runs the people and the administrator runs the tool. What somebody is
  -- allowed to DO is the one field on the row that is not HR's.
  o := org_person_set(p_hr, p_a, jsonb_build_object('appRole','ADMIN'));
  if o->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  Human Resources made somebody an administrator: %', o;
  end if;
  if (select app_role::text from person where id = p_a) = 'ADMIN' then
    raise exception 'FAIL  the role was written anyway';
  end if;
  if coalesce((org_assign_options(p_hr)->>'maySetRole')::boolean,false) then
    raise exception 'FAIL  Human Resources was offered the role box they may not use';
  end if;
  o := org_person_set(p_adm, p_adm, jsonb_build_object('appRole','VIEWER'));
  if o->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  an administrator demoted themselves: %', o;
  end if;
  o := org_person_set(p_adm, p_a, jsonb_build_object('appRole','MANAGER'));
  if o->>'error' is not null then
    raise exception 'FAIL  the administrator could not set a role: %', o;
  end if;
  raise notice 'PASS  the role is the administrator''s, and never their own';

  -- ------------------------------------------------------------ the lists
  if org_person_set(p_adm, p_a, jsonb_build_object(
       'designationId','00000000-0000-0000-0000-000000000000'))->>'error'
     is distinct from 'invalid' then
    raise exception 'FAIL  a designation that does not exist was accepted';
  end if;
  o := org_person_set(p_adm, p_a, jsonb_build_object('designationId', v_d1));
  if o->>'error' is not null then
    raise exception 'FAIL  a real designation was refused: %', o;
  end if;
  if (select designation_id from person where id = p_a) is distinct from v_d1 then
    raise exception 'FAIL  the designation did not land';
  end if;
  raise notice 'PASS  a designation is picked from the list, never spelled into being';

  -- ----------------------------------------------------------- atomic
  o := org_person_set(p_adm, p_a, jsonb_build_object(
         'designationId','00000000-0000-0000-0000-000000000000',
         'department','Should Not Land'));
  if o->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  the bad field was accepted';
  end if;
  if (select department from person where id = p_a) = 'Should Not Land' then
    raise exception 'FAIL  a good field saved beside a bad one. A form that '
                    'half-saves is worse than one that refuses.';
  end if;
  if jsonb_array_length(o->'fields') = 0 then
    raise exception 'FAIL  the refusal does not say which box was wrong';
  end if;
  raise notice 'PASS  nothing saves unless everything validates, and the '
               'refusal names the box';

  -- ------------------------------------------------------- chair and place
  if org_person_set(p_adm, p_a, jsonb_build_object('seatingId', v_s1))
     ->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  a place was set on somebody holding no chair';
  end if;
  if org_person_set(p_adm, p_a, jsonb_build_object('chairId', v_ch1,
       'seatingId', v_s2))->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  a place belonging to another chair was accepted';
  end if;
  o := org_person_set(p_adm, p_a, jsonb_build_object('chairId', v_ch1,
         'seatingId', v_s1));
  if o->>'error' is not null then
    raise exception 'FAIL  a chair and its own place were refused: %', o;
  end if;
  select count(*) into n from chair_holder h
   where h.person_id = p_a and h.to_date is null and h.is_primary;
  if n <> 1 then
    raise exception 'FAIL  % open primary chair holdings, not one', n;
  end if;
  if (select seating_id from chair_holder
       where person_id = p_a and to_date is null and is_primary) is distinct from v_s1 then
    raise exception 'FAIL  the place did not land on the holding';
  end if;
  raise notice 'PASS  a chair carries its place, and the wrong place is refused';

  -- Moving to another chair closes the old holding rather than rewriting it:
  -- last year's answer to "who sat there" has to survive this year's change.
  o := org_person_set(p_adm, p_a, jsonb_build_object('chairId', v_ch2));
  if o->>'error' is not null then
    raise exception 'FAIL  the chair could not be changed: %', o;
  end if;
  if not exists (select 1 from chair_holder
                  where person_id = p_a and chair_id = v_ch1 and to_date is not null) then
    raise exception 'FAIL  the old holding was deleted instead of closed. The '
                    'history of who sat where is gone.';
  end if;
  select count(*) into n from chair_holder h
   where h.person_id = p_a and h.to_date is null and h.is_primary;
  if n <> 1 then
    raise exception 'FAIL  % open primary holdings after the move, not one', n;
  end if;
  raise notice 'PASS  a chair is held, not owned: the old holding is closed';

  -- -------------------------------------------------------------- the line
  -- Still org_move_person's, which means its refusals are still its own.
  if org_person_set(p_adm, p_a, jsonb_build_object('managerId', p_c))
     ->>'error' is distinct from 'would_loop' then
    raise exception 'FAIL  the reporting line was made a ring. org_move_person '
                    'is no longer the one authority on it.';
  end if;
  o := org_person_set(p_adm, p_c, jsonb_build_object('managerId', p_b,
         'department','Operations'));
  if o->>'error' is not null then
    raise exception 'FAIL  a manager and a department together were refused: %', o;
  end if;
  if (select manager_id from person where id = p_c) is distinct from p_b then
    raise exception 'FAIL  the manager did not change';
  end if;
  if not exists (select 1 from audit_entry
                  where entity_ref = p_c::text and action = 'REPORTING_CHANGED') then
    raise exception 'FAIL  the reporting change was not audited';
  end if;
  raise notice 'PASS  the reporting line is still org_move_person''s, ring and all';

  -- ------------------------------------------------------------- audited
  if not exists (select 1 from audit_entry
                  where entity_ref = p_a::text and action = 'PERSON_ASSIGNED') then
    raise exception 'FAIL  changing somebody''s details was not audited';
  end if;
  raise notice 'PASS  and every change is on the record';

  -- -------------------------------------------------------------- in bulk
  o := org_person_set_many(p_adm, '[]'::jsonb, jsonb_build_object('department','X'));
  if o->>'error' is distinct from 'nobody_chosen' then
    raise exception 'FAIL  the bulk form accepted nobody';
  end if;

  o := org_person_set_many(p_adm,
         jsonb_build_array(p_b::text, p_c::text, '00000000-0000-0000-0000-000000000000'),
         jsonb_build_object('designationId', v_d2));
  if jsonb_array_length(o->'failed') <> 1 then
    raise exception 'FAIL  the unknown person was not reported as refused: %', o;
  end if;
  if (select designation_id from person where id = p_b) is distinct from v_d2
     or (select designation_id from person where id = p_c) is distinct from v_d2 then
    raise exception 'FAIL  one bad row stopped the good ones';
  end if;
  raise notice 'PASS  one refusal in a batch stops neither the batch nor the report of it';

  -- -------------------------------------------------- and the chip moves
  -- The count and the list behind it are the same question asked twice. If
  -- setting a department did not move the number, one of the two is lying.
  select (org_people_table(p_adm)->'summary'->>'noDepartment')::int into before_no_dept;
  o := org_person_set(p_adm, p_c, jsonb_build_object('department', null));
  if o->>'error' is not null then
    raise exception 'FAIL  a department could not be cleared: %', o;
  end if;
  select (org_people_table(p_adm)->'summary'->>'noDepartment')::int into after_no_dept;
  if after_no_dept <> before_no_dept + 1 then
    raise exception 'FAIL  clearing a department moved the chip from % to %',
      before_no_dept, after_no_dept;
  end if;
  o := org_person_set(p_adm, p_c, jsonb_build_object('department','Operations'));
  select (org_people_table(p_adm)->'summary'->>'noDepartment')::int into after_no_dept;
  if after_no_dept <> before_no_dept then
    raise exception 'FAIL  setting it back did not move the chip back';
  end if;
  raise notice 'PASS  the chip and the list are the same question asked twice';

  -- -------------------------------------------- the dropdowns the screen draws
  o := org_people_table(p_adm);
  select count(*) into n from jsonb_array_elements(o->'people') r
   where not (r ? 'designationId') or not (r ? 'chairId') or not (r ? 'seatingId');
  if n > 0 then
    raise exception 'FAIL  % row(s) carry no ids, so no dropdown can be '
                    'pre-selected', n;
  end if;
  raise notice 'PASS  every row carries the ids its dropdowns are keyed by';

  -- ------------------------------------------------------ nothing widened
  -- 241 and 244 both end with this sentence. So does this.
  if exists (select 1 from person p
              where p.employment_status = 'ACTIVE' and p.superseded_by is null
                and p.id <> p_hr
                and not exists (select 1 from perf_line(p_hr) l where l.person_id = p.id)
                and perf_may_set(p_hr, p.id)) then
    raise exception 'FAIL  Human Resources may now set measures outside their '
                    'line. 241 has been undone.';
  end if;
  raise notice 'PASS  and a designation is still not a performance measure';

  raise notice '--- assigning people: every assertion passed ---';
end $t$;

rollback;
