-- A manager asks for a joiner, and HR makes the account (234)
--
-- The thing these assertions are really holding down is the boundary. A
-- manager may ask for anybody; a manager may create nobody. The approval is
-- not a rubber stamp that writes a row -- it runs person_add again, under the
-- approver, so a request cannot be a way of getting past a check that
-- person_add would have made.
--
-- Runs inside a transaction that is rolled back.

begin;

do $seed$
declare
  c_br uuid; c_ex uuid; p_bm uuid; p_ex uuid; p_hr uuid; p_other uuid; p_far uuid;
begin
  insert into chair (code, title, level) values ('JN_B','Join branch','branch')
    returning id into c_br;
  insert into chair (code, title, level, parent_id)
    values ('JN_E','Join exec','executive', c_br) returning id into c_ex;

  insert into person (full_name, work_email, department, app_role)
    values ('JN HR','jn.hr@example.invalid','Human Resources','MANAGER')
    returning id into p_hr;
  insert into person (full_name, work_email) values ('JN Branch','jn.bm@example.invalid')
    returning id into p_bm;
  insert into person (full_name, work_email, manager_id)
    values ('JN Exec','jn.ex@example.invalid', p_bm) returning id into p_ex;
  insert into person (full_name, work_email) values ('JN Other','jn.other@example.invalid')
    returning id into p_other;
  -- Somebody under the branch manager but not under the exec: the one the
  -- branch manager may MOVE, which is the other half of the + button.
  insert into person (full_name, work_email, manager_id)
    values ('JN Spare','jn.spare@example.invalid', p_bm) returning id into p_far;

  insert into chair_holder (chair_id, person_id, is_primary)
    values (c_br, p_bm, true), (c_ex, p_ex, true);
end $seed$;

do $t$
declare
  p_bm uuid; p_ex uuid; p_hr uuid; p_other uuid; p_far uuid;
  c_ex uuid; o jsonb; n int; v_req uuid; v_new uuid;
begin
  select id into p_bm from person where work_email='jn.bm@example.invalid';
  select id into p_ex from person where work_email='jn.ex@example.invalid';
  select id into p_hr from person where work_email='jn.hr@example.invalid';
  select id into p_other from person where work_email='jn.other@example.invalid';
  select id into p_far from person where work_email='jn.spare@example.invalid';
  select id into c_ex from chair where code='JN_E';

  -- ================================================ who gets a + at all
  if org_may_add_under(p_bm, p_bm) and org_may_add_under(p_bm, p_ex)
    then raise notice 'PASS  a manager may add to their own team and to a team below it';
    else raise exception 'FAIL  the manager got no + on their own tile'; end if;

  if not org_may_add_under(p_ex, p_bm)
    then raise notice 'PASS  and nobody adds a person above themselves';
    else raise exception 'FAIL  a report could add under their own manager'; end if;

  if not org_may_add_under(p_other, p_ex)
    then raise notice 'PASS  nor into somebody else''s team';
    else raise exception 'FAIL  a stranger got a + on another team'; end if;

  -- ============================================== the tiles carry it
  o := org_team_tree(p_bm, p_bm, null);
  select count(*) into n from jsonb_array_elements(o->'people') m
   where (m->>'mayAddUnder') = 'true';
  if n = 3
    then raise notice 'PASS  every tile in the manager''s own tree offers the +, not just the top';
    else raise exception 'FAIL  % of 3 tiles carried mayAddUnder', n; end if;

  -- ========================================= what the + actually offers
  o := org_add_options(p_bm, p_ex);
  if (o->>'mayRequest')::boolean and not (o->>'mayCreate')::boolean
    then raise notice 'PASS  a manager may ask for a joiner and may not create one';
    else raise exception 'FAIL  the manager''s options read %', left(o::text,200); end if;

  o := org_add_options(p_hr, p_ex);
  if (o->>'mayCreate')::boolean
    then raise notice 'PASS  HR skips the queue, because it would be a queue of one';
    else raise exception 'FAIL  HR was told to file a request with itself'; end if;

  o := org_add_options(p_bm, p_ex);
  select count(*) into n from jsonb_array_elements(o->'movable') m
   where (m->>'personId')::uuid = p_far;
  if n = 1
    then raise notice 'PASS  and somebody already employed here is offered as a move';
    else raise exception 'FAIL  the movable list did not hold the spare person'; end if;

  select count(*) into n from jsonb_array_elements(o->'movable') m
   where (m->>'personId')::uuid = p_bm;
  if n = 0
    then raise notice 'PASS  but never the person''s own manager -- that is a loop, not an option';
    else raise exception 'FAIL  a move that would loop was offered'; end if;

  o := org_add_options(p_other, p_ex);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  and a stranger is offered nothing at all';
    else raise exception 'FAIL  the options leaked outside the line'; end if;

  -- ===================================================== the ask
  o := person_request_open(p_bm, jsonb_build_object(
        'fullName','Nikhil Sawant','workEmail','nikhil.sawant@example.invalid',
        'chairId', c_ex, 'managerId', p_ex, 'employeeType','EMPLOYEE'));
  if (o->>'ok')::boolean
    then raise notice 'PASS  the manager files the ask and no account is made by it';
    else raise exception 'FAIL  the request was refused: %', left(o::text,200); end if;
  v_req := (o->>'requestId')::uuid;

  if not exists (select 1 from person where work_email='nikhil.sawant@example.invalid')
    then raise notice 'PASS  -- confirmed: the request created a request, not a person';
    else raise exception 'FAIL  filing a request created an account'; end if;

  if (select state from person_request where id = v_req) = 'AWAITING_HR'
    then raise notice 'PASS  and it is sitting with HR, which is whose job it is';
    else raise exception 'FAIL  the request did not land on HR'; end if;

  -- --------------------------------------------- the ways it is refused
  o := person_request_open(p_ex, jsonb_build_object(
        'fullName','Somebody Else','workEmail','x@example.invalid',
        'chairId', c_ex, 'managerId', p_bm));
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  nobody asks for a joiner into a team above them';
    else raise exception 'FAIL  a request reached upwards'; end if;

  o := person_request_open(p_bm, jsonb_build_object(
        'fullName','Dup Person','workEmail','jn.spare@example.invalid',
        'chairId', c_ex, 'managerId', p_ex));
  if o->>'error' = 'already_employed'
    then raise notice 'PASS  asking for somebody who already works here says to move them';
    else raise exception 'FAIL  a duplicate account was allowed to be asked for'; end if;

  o := person_request_open(p_bm, jsonb_build_object(
        'fullName','Nikhil Again','workEmail','nikhil.sawant@example.invalid',
        'chairId', c_ex, 'managerId', p_ex));
  if o->>'error' = 'already_asked'
    then raise notice 'PASS  and asking twice for the same address is one ask, not two';
    else raise exception 'FAIL  the same joiner was queued twice'; end if;

  o := person_request_open(p_bm, jsonb_build_object(
        'fullName','Bad Mail','workEmail','not-an-address',
        'chairId', c_ex, 'managerId', p_ex));
  if o->>'error' = 'bad_email'
    then raise notice 'PASS  an address that is not one is refused at the ask';
    else raise exception 'FAIL  a bad address was queued'; end if;

  -- ======================================================== the queue
  o := person_request_list(p_hr, null);
  if (o->>'isHr')::boolean and jsonb_array_length(o->'requests') = 1
    then raise notice 'PASS  HR reads the queue';
    else raise exception 'FAIL  HR''s queue read %', left(o::text,200); end if;

  o := person_request_list(p_bm, null);
  if jsonb_array_length(o->'requests') = 1 and not (o->>'isHr')::boolean
    then raise notice 'PASS  the manager reads their own ask and is not mistaken for HR';
    else raise exception 'FAIL  the manager''s queue read %', left(o::text,200); end if;

  o := person_request_list(p_other, null);
  if jsonb_array_length(o->'requests') = 0
    then raise notice 'PASS  and somebody outside sees an empty queue, not somebody else''s';
    else raise exception 'FAIL  the queue leaked'; end if;

  -- =================================================== deciding it
  o := person_request_decide(p_bm, v_req, 'APPROVE', '{}'::jsonb);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  the manager who asked cannot also approve their own ask';
    else raise exception 'FAIL  a manager approved their own request'; end if;

  o := person_request_decide(p_hr, v_req, 'REJECT', '{}'::jsonb);
  if o->>'error' = 'missing_reason'
    then raise notice 'PASS  a refusal without a reason is refused';
    else raise exception 'FAIL  a request was rejected silently'; end if;

  -- The approval runs person_add again: this one is missing everything
  -- person_add insists on, and the request does not excuse any of it.
  o := person_request_decide(p_hr, v_req, 'APPROVE', '{}'::jsonb);
  if o->>'error' = 'invalid'
    then raise notice 'PASS  approving runs every person_add check again, it does not skip them';
    else raise exception 'FAIL  approval bypassed person_add: %', left(o::text,220); end if;

  if (select state from person_request where id = v_req) = 'AWAITING_HR'
    then raise notice 'PASS  and a failed approval leaves the request where it was';
    else raise exception 'FAIL  a failed approval still moved the request'; end if;

  -- Now with what HR actually knows and the manager did not.
  o := person_request_decide(p_hr, v_req, 'APPROVE', jsonb_build_object(
        'employeeNo','EMP-9901', 'department','Operations',
        'mobile','9820011223', 'joinedOn', current_date::text,
        'appRole','VIEWER'));
  if (o->>'ok')::boolean
    then raise notice 'PASS  HR supplies the number and the date, and the account is made';
    else raise exception 'FAIL  the approval failed: %', left(o::text,260); end if;
  v_new := (o->>'personId')::uuid;

  if (select manager_id from person where id = v_new) = p_ex
    then raise notice 'PASS  and they land under the manager who asked for them';
    else raise exception 'FAIL  the joiner landed under the wrong manager'; end if;

  if (select work_email from person where id = v_new) = 'nikhil.sawant@example.invalid'
    then raise notice 'PASS  as the person who was asked for, not one swapped in at approval';
    else raise exception 'FAIL  the approved person is not the requested one'; end if;

  if (select state from person_request where id = v_req) = 'ACTIVE'
     and (select person_id from person_request where id = v_req) = v_new
    then raise notice 'PASS  the request now points at the account it became';
    else raise exception 'FAIL  the request was not closed against the person'; end if;

  o := person_request_decide(p_hr, v_req, 'REJECT',
        jsonb_build_object('reason','changed our mind'));
  if o->>'error' = 'already_decided'
    then raise notice 'PASS  and a decided request is not decided twice';
    else raise exception 'FAIL  a settled request was reopened'; end if;

  -- ============================== the joiner appears on the manager's tree
  o := org_team_tree(p_bm, p_bm, null);
  select count(*) into n from jsonb_array_elements(o->'people') m
   where (m->>'personId')::uuid = v_new;
  if n = 1
    then raise notice 'PASS  and the manager sees them on the team without being told to look';
    else raise exception 'FAIL  the new joiner is not on the tree'; end if;

  raise notice '--- asking for a joiner: every assertion passed ---';
end $t$;

rollback;
