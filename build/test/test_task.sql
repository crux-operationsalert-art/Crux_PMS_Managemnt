-- A task is a thing somebody asked for (migration 214)
--
-- One person asks another for something by a date. It is not an escalation
-- and not a KPI; it is the record A-3 -- contribution beyond your own chair --
-- is scored from, which the PLB Constitution requires to be a named artefact
-- rather than a manager's assertion.
--
-- Everything here runs inside a transaction that is rolled back, and seeds its
-- own chairs and people, so it can run on a database rebuilt from build/schema
-- alone and leaves nothing behind either way.

begin;


do $seed$
declare v_head uuid; v_seat uuid; v_boss uuid; v_a uuid; v_b uuid; v_c uuid; v_out uuid;
begin
  insert into chair (code, title, level) values ('TSK_HEAD','Test head','function')
    returning id into v_head;
  insert into chair (code, title, level, parent_id) values ('TSK_SEAT','Test seat','branch', v_head)
    returning id into v_seat;
  insert into chair (code, title, level) values ('TSK_OTHER','Test elsewhere','function')
    returning id into v_out;

  insert into person (full_name, work_email, app_role) values
    ('TSK Boss',   'tsk.boss@example.invalid',   'VIEWER') returning id into v_boss;
  insert into person (full_name, work_email) values ('TSK Aaa','tsk.a@example.invalid') returning id into v_a;
  insert into person (full_name, work_email) values ('TSK Bbb','tsk.b@example.invalid') returning id into v_b;
  insert into person (full_name, work_email) values ('TSK Ccc','tsk.c@example.invalid') returning id into v_c;

  insert into chair_holder (chair_id, person_id, is_primary) values
    (v_head, v_boss, true), (v_seat, v_a, true), (v_seat, v_b, true), (v_out, v_c, true);
end $seed$;

do $t$
declare
  v_boss uuid; v_a uuid; v_b uuid; v_c uuid; v_seat uuid;
  r jsonb; v_task uuid; v_sw jsonb; v_ev jsonb; n int; v_period text;
begin
  select id into v_boss from person where work_email = 'tsk.boss@example.invalid';
  select id into v_a    from person where work_email = 'tsk.a@example.invalid';
  select id into v_b    from person where work_email = 'tsk.b@example.invalid';
  select id into v_c    from person where work_email = 'tsk.c@example.invalid';
  select id into v_seat from chair  where code = 'TSK_SEAT';
  v_period := to_char(current_date + 7, 'YYYY-MM');

  -- ---------------------------------------------------------------- reach
  -- "I can create a task for a specific manager or all the managers"
  r := task_assign(v_boss, jsonb_build_object(
         'title','Visit the SBI branches in your area',
         'detail','Every SBI branch on your coverage list, this month.',
         'dueOn', to_char(current_date + 7,'YYYY-MM-DD'),
         'attributeWeight', 2,
         'chair', v_seat::text));
  if (r->>'created')::int = 2
    then raise notice 'PASS  one instruction reaches everybody in a chair';
    else raise exception 'FAIL  a chair of two took % tasks', r->>'created'; end if;

  -- ------------------------------------------------------- the clock decides
  select id into v_task from task where person_id = v_a;
  r := task_close(v_a, v_task, 'Eleven branches visited.');
  if r->>'status' = 'DONE'
    then raise notice 'PASS  closed on or before the date reads DONE';
    else raise exception 'FAIL  closing before the date read %', r->>'status'; end if;

  update task set due_on = current_date - 3 where person_id = v_b;
  select id into v_task from task where person_id = v_b;
  r := task_close(v_b, v_task, 'Done, a few days behind.');
  if r->>'status' = 'LATE'
    then raise notice 'PASS  closed after the date reads LATE, whoever closes it';
    else raise exception 'FAIL  closing after the date read %', r->>'status'; end if;

  -- --------------------------------------------------------------- the sweep
  r := task_assign(v_boss, jsonb_build_object(
         'title','Confirm the Nagpur cover',
         'dueOn', to_char(current_date - 1,'YYYY-MM-DD'),
         'people', jsonb_build_array(v_a::text)));
  v_sw := task_sweep();
  if (v_sw->>'tasks_missed')::int = 1
    then raise notice 'PASS  an open task past its date becomes missed';
    else raise exception 'FAIL  the sweep caught % of 1', v_sw->>'tasks_missed'; end if;
  if (v_sw->>'people_told')::int = 2
    then raise notice 'PASS  and both the person and whoever asked are told, once each';
    else raise exception 'FAIL  the sweep told % people, expected 2', v_sw->>'people_told'; end if;

  select count(*) into n from ops_alert where kind = 'TASK_MISSED';
  if n = 0
    then raise notice 'PASS  and nothing reaches the administrator''s Alerts screen';
    else raise exception 'FAIL  % task alerts went to a screen filtered by role, not person', n; end if;

  select count(*) into n from notification where kind = 'TASK_MISSED' and person_id = v_a and push;
  if n = 1
    then raise notice 'PASS  the person who missed it gets a push; it moves their score';
    else raise exception 'FAIL  the person who missed it got % pushed notifications', n; end if;

  -- running it twice must not tell anybody twice
  v_sw := task_sweep();
  if (v_sw->>'tasks_missed')::int = 0
    then raise notice 'PASS  the sweep is idempotent';
    else raise exception 'FAIL  a second sweep found % more', v_sw->>'tasks_missed'; end if;

  -- ------------------------------------------------------------- the evidence
  v_ev := task_evidence(v_b, v_period);
  if (v_ev->>'a3Suggested')::numeric = 1.00
    then raise notice 'PASS  one late task suggests half of A-3';
    else raise exception 'FAIL  one late task suggested %', v_ev->>'a3Suggested'; end if;

  v_ev := task_evidence(v_c, v_period);
  if (v_ev->>'a3Suggested') is null
    then raise notice 'PASS  a month nobody asked anything of you is not a zero';
    else raise exception 'FAIL  an empty month suggested %', v_ev->>'a3Suggested'; end if;

  -- ------------------------------------------------------------------ reach
  r := task_assign(v_a, jsonb_build_object('title','A task for my boss',
         'people', jsonb_build_array(v_boss::text)));
  if (r->>'created')::int = 0 and jsonb_array_length(r->'refused') = 1
    then raise notice 'PASS  you cannot task somebody who is not under you, and are told who';
    else raise exception 'FAIL  tasking upward created % and refused %',
      r->>'created', jsonb_array_length(r->'refused'); end if;

  r := task_assign(v_boss, jsonb_build_object('title','A task for another function',
         'people', jsonb_build_array(v_c::text)));
  if (r->>'created')::int = 0
    then raise notice 'PASS  and nor somebody in a chair outside your own';
    else raise exception 'FAIL  tasking across the tree created %', r->>'created'; end if;

  -- ------------------------------------------------------------- the weight
  r := task_assign(v_boss, jsonb_build_object('title','Worth more than an attribute',
         'attributeWeight', 5, 'people', jsonb_build_array(v_a::text)));
  if r->>'error' = 'bad_weight'
    then raise notice 'PASS  a task cannot be worth more than the attribute it feeds';
    else raise exception 'FAIL  a weight of 5 was accepted'; end if;

  -- --------------------------------------------------------------- the split
  if (select kpi_percent from pms_weighting where scope_all order by effective_from desc limit 1) = 75
   and (select attr_percent from pms_weighting where scope_all order by effective_from desc limit 1) = 25
    then raise notice 'PASS  the Constitution''s 75/25 split is a row, not a heading';
    else raise exception 'FAIL  the company-wide weighting is not 75/25'; end if;

  -- ------------------------------------- the two curves, against Annexure F
  if plb_payout_factor(49) = 0 and plb_payout_factor(65) = 42.857
     and plb_payout_factor(85) = 100 and plb_payout_factor(100) = 110
     and plb_payout_factor(115) = 125 and plb_payout_factor(130) = 125
    then raise notice 'PASS  the payout curve matches Annexure F at every published point';
    else raise exception 'FAIL  the payout curve has moved away from Annexure F'; end if;

  if plb_consistency(10) = 1.0 and plb_consistency(8) = 0.8 and plb_consistency(2) = 0.30
    then raise notice 'PASS  the release dial matches, floor and all';
    else raise exception 'FAIL  the release dial does not match the Scorecard Guide'; end if;

  -- the Constitution's own five worked examples, on its own base case
  if round(50000 * plb_payout_factor(100)/100.0 * plb_consistency(8.0), 2) = 44000
 and round(50000 * plb_payout_factor(78) /100.0 * plb_consistency(9.0), 2) = 36000
 and round(50000 * plb_payout_factor(110)/100.0 * plb_consistency(5.0), 2) = 30000
 and round(50000 * plb_payout_factor(110)/100.0 * plb_consistency(9.5), 2) = 57000
 and round(50000 * plb_payout_factor(49) /100.0 * plb_consistency(10.0), 2) = 0
    then raise notice 'PASS  all five worked examples reproduce to the rupee';
    else raise exception 'FAIL  a worked example from the Constitution no longer reproduces'; end if;

  raise notice '--- task and PLB arithmetic: every assertion passed ---';
end $t$;

rollback;
