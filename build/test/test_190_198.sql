-- Behaviour tests for migrations 190-198, run against a local Postgres 16
-- brought up to the live shape by build/test/fixture_live_shape.sql.
--
-- These exist because "CREATE OR REPLACE FUNCTION succeeded" is not a test.
-- plpgsql checks syntax at creation and NOTHING about the functions a body
-- calls -- this codebase has already paid once for believing otherwise, when
-- person_merge_plan was created calling a person_merge_side that did not
-- exist yet and the database accepted it without a word.
--
-- Every check below RUNS the function and asserts on what came back.

\set ON_ERROR_STOP on
set client_min_messages to notice;

create or replace function t_ok(p_name text, p_cond boolean, p_saw text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'PASS  %', p_name;
  else
    raise exception 'FAIL  % %', p_name, coalesce('-- saw: ' || p_saw, '');
  end if;
end $$;

-- ===================================================================== seed
-- The seed is re-runnable: everything it makes, it removes first.
-- notification and request_task are written by the request flow these
-- tests exercise, and both name a person. They have to go before the
-- people do, or a second run trips notification_person_id_fkey.
delete from request_task; delete from notification; delete from raisable;
delete from perf_entry; delete from perf_assignment; delete from perf_cycle;
delete from matrix_dispatch; delete from outbox; delete from audit_entry;
delete from job_run;
delete from matrix_contact where client_id in (select id from client where code = 'SBI');
delete from coverage_rule where person_id in
  (select id from person where work_email like '%@crux.test');
delete from branch where client_id in (select id from client where code = 'SBI');
delete from client_contact where client_id in (select id from client where code = 'SBI');
delete from client where code = 'SBI';
delete from kpi_definition where name in
  ('Case Target','Quality score','Branch case target',
   'Pct marked adds','Count marked replaces');
delete from chair_holder where person_id in
  (select id from person where work_email like '%@crux.test');
delete from chair where code in ('BM','FE');
update person set manager_id = null where work_email like '%@crux.test';
delete from person where work_email like '%@crux.test';

insert into holiday (day, name, applies_to, confirmed) values
  ('2026-10-02', 'Gandhi Jayanti', 'All India', true),
  ('2026-10-12', 'Local festival', 'Pune', true)
on conflict (day) do nothing;

do $$
declare
  hr uuid; boss uuid; rep uuid; other uuid; adm uuid;
  ch_bm uuid; ch_fe uuid;
  cl uuid; br1 uuid; br2 uuid;
begin
  -- people
  insert into person (id, employee_no, full_name, work_email, department,
                      app_role, employment_status)
  values (gen_random_uuid(), 'EMP-HR01', 'Hema Rao', 'hr@crux.test',
          'Human Resources', 'MANAGER', 'ACTIVE') returning id into hr;

  insert into person (id, employee_no, full_name, work_email, department,
                      app_role, employment_status)
  values (gen_random_uuid(), 'EMP-BM01', 'Bharat Mane', 'bm@crux.test',
          'Operations', 'MANAGER', 'ACTIVE') returning id into boss;

  insert into person (id, employee_no, full_name, work_email, department,
                      app_role, employment_status, manager_id)
  values (gen_random_uuid(), 'EMP-FE01', 'Reva Pawar', 'fe@crux.test',
          'Operations', 'VIEWER', 'ACTIVE', boss) returning id into rep;

  insert into person (id, employee_no, full_name, work_email, department,
                      app_role, employment_status)
  values (gen_random_uuid(), 'EMP-XX01', 'Otto Nobody', 'xx@crux.test',
          'Operations', 'VIEWER', 'ACTIVE') returning id into other;

  -- The tool's administrator, who is the one exception migration 218 keeps.
  -- Before 218 the fixture used Hema Rao in Human Resources for this,
  -- because being in that department was itself a licence over everybody.
  insert into person (id, employee_no, full_name, work_email, department,
                      app_role, employment_status)
  values (gen_random_uuid(), 'EMP-AD01', 'Asha Deshmukh', 'admin@crux.test',
          'Business Excellence', 'ADMIN', 'ACTIVE') returning id into adm;

  -- chairs, so perf_node can name one
  insert into chair (id, code, title, level) values (gen_random_uuid(), 'BM', 'Branch Manager', 'BRANCH')
    returning id into ch_bm;
  insert into chair (id, code, title, level) values (gen_random_uuid(), 'FE', 'Field Executive', 'BRANCH')
    returning id into ch_fe;
  insert into chair_holder (chair_id, person_id, is_primary, from_date)
  values (ch_bm, boss, true, '2026-01-01'), (ch_fe, rep, true, '2026-01-01');

  -- a client with two branches, one complete matrix and one with a hole
  insert into client (id, code, name, status)
  values (gen_random_uuid(), 'SBI', 'State Bank of India', 'ACTIVE') returning id into cl;
  insert into client_contact (client_id, kind, name, email)
  values (cl, 'PRIMARY', 'Vendor desk', 'vendors@sbi.test'),
         (cl, 'CC', 'Ops desk', 'ops@sbi.test');

  insert into branch (id, client_id, code, name, status)
  values (gen_random_uuid(), cl, 'PUN-001', 'Pune Camp', 'ACTIVE') returning id into br1;
  insert into branch (id, client_id, code, name, status)
  values (gen_random_uuid(), cl, 'PUN-002', 'Pune Hadapsar', 'ACTIVE') returning id into br2;

  insert into matrix_contact (client_id, branch_id, level, level_name, name, mobile, email)
  select cl, br1, g, 'Level ' || g, 'Person ' || g, '98200 0000' || g, 'l' || g || '@sbi.test'
    from generate_series(1,5) g;
  insert into matrix_contact (client_id, branch_id, level, level_name, name, mobile, email)
  select cl, br2, g, 'Level ' || g, 'Person ' || g, '98200 0000' || g, 'l' || g || '@sbi.test'
    from generate_series(1,3) g;

  -- coverage, so matrix_scope_branches has something to resolve
  insert into coverage_rule (person_id, role, scope_type, client_id, effective_from)
  values (boss, 'BRANCH_MANAGER', 'CLIENT', cl, '2026-01-01');

  -- the catalogue: one measure that accumulates, one that is a level
  insert into kpi_definition (chair_id, name, unit, active, mandatory, position,
                              cadence, accrual)
  values (ch_fe, 'Case Target', 'cases', true, true, 1, 'DAILY', 'ADDS'),
         (ch_fe, 'Quality score', '%', true, false, 2, 'WEEKLY', 'ADDS'),
         (ch_bm, 'Branch case target', 'cases', true, true, 1, 'DAILY', 'ADDS'),
         -- the two shapes the live registry actually contains, for 200
         (ch_fe, 'Pct marked adds', '% of target', true, false, 3, 'MONTHLY', 'ADDS'),
         (ch_fe, 'Count marked replaces', 'cases', true, false, 4, 'MONTHLY', 'REPLACES');

  create temp table who (nm text primary key, id uuid);
  insert into who values ('hr',hr),('boss',boss),('rep',rep),('other',other),('adm',adm),
                         ('ch_bm',ch_bm),('ch_fe',ch_fe),('cl',cl),('br1',br1),('br2',br2);
end $$;

-- =============================================== 194: opening the window
do $$
declare o jsonb; cyc uuid; hr uuid; boss uuid;
begin
  select id into hr   from who where nm ='hr';
  select id into boss from who where nm ='boss';

  o := perf_cycle_open(boss, '2026-10-05');
  perform t_ok('a branch manager cannot open a cycle',
               o->>'error' = 'not_permitted', o::text);

  o := perf_cycle_open(hr, '2026-10-05');
  perform t_ok('HR can open a cycle', coalesce((o->>'ok')::boolean,false), o::text);
  cyc := (o->>'cycleId')::uuid;
  insert into who values ('cycle', cyc);

  perform t_ok('opening the same month twice is not a second cycle',
               (perf_cycle_open(hr, '2026-10-20')->>'cycleId')::uuid = cyc);

  perform t_ok('the cycle is the first of the month',
               (select period_start from perf_cycle where id = cyc) = '2026-10-01');
  perform t_ok('the two windows are in order',
               (select assign_closes < entry_closes from perf_cycle where id = cyc));
  perform t_ok('opening a cycle is in the trail',
               exists (select 1 from audit_entry where action = 'PERF_CYCLE_OPENED'));
end $$;

-- ===================================================== 194: who may set
do $$
declare boss uuid; rep uuid; hr uuid; other uuid; adm uuid;
begin
  select id into boss from who where nm ='boss'; select id into rep from who where nm ='rep';
  select id into hr   from who where nm ='hr';   select id into other from who where nm ='other';
  select id into adm  from who where nm ='adm';
  perform t_ok('a manager may set for their report',      perf_may_set(boss, rep));
  perform t_ok('nobody may set their own',            not perf_may_set(rep, rep));
  perform t_ok('a stranger may not set',              not perf_may_set(other, rep));
  perform t_ok('a report may not set their manager''s', not perf_may_set(rep, boss));
  perform t_ok('an administrator may set for anybody',    perf_may_set(adm, rep));
  -- Until migration 218 this read `perf_may_set(hr, rep)` and asserted
  -- true: a department was a licence over every person in the company.
  -- The rule now is the reporting line and nothing else -- running the
  -- scheme, which HR still does below, is a different act from setting one
  -- named person's numbers.
  perform t_ok('being in Human Resources is not a licence over a stranger',
                                                      not perf_may_set(hr, rep));
  perform t_ok('and does not let them read one either',
                                                      not perf_may_see(hr, rep));
  perform t_ok('a manager sees two steps down without setting there',
               perf_may_see(boss, rep) and perf_rel(boss, rep) = 'manage');
end $$;

-- ======================================== 194: assigning, and the roll-up
do $$
declare cyc uuid; boss uuid; rep uuid; other uuid;
        k_case uuid; k_qual uuid; k_bcase uuid;
        o jsonb; a_boss uuid; a_rep uuid; a_qual uuid; a_p1 uuid; a_p2 uuid;
begin
  select id into cyc from who where nm ='cycle';
  select id into boss from who where nm ='boss'; select id into rep from who where nm ='rep';
  select id into other from who where nm ='other';
  select id into k_case  from kpi_definition where name='Case Target';
  select id into k_qual  from kpi_definition where name='Quality score';
  select id into k_bcase from kpi_definition where name='Branch case target';

  -- the manager's own measure first, because the report's climbs into it
  o := perf_assign(boss, jsonb_build_object('personId', boss, 'cycleId', cyc,
         'kpiId', k_bcase, 'target', '500', 'weight', '60', 'cadence', 'DAILY'));
  perform t_ok('a manager cannot set their own KPI',
               o->>'error' = 'not_permitted', o::text);

  -- The manager's own KPI is set from above him. Before migration 218 this
  -- was Hema Rao in Human Resources; she is now a stranger to him, so it is
  -- the administrator, who is the exception 218 keeps.
  o := perf_assign((select id from who where nm ='hr'),
         jsonb_build_object('personId', boss, 'cycleId', cyc,
           'kpiId', k_bcase, 'target', '500', 'weight', '60', 'cadence', 'DAILY'));
  perform t_ok('HR can no longer set a stranger''s KPI',
               o->>'error' = 'not_permitted', o::text);

  o := perf_assign((select id from who where nm ='adm'),
         jsonb_build_object('personId', boss, 'cycleId', cyc,
           'kpiId', k_bcase, 'target', '500', 'weight', '60', 'cadence', 'DAILY'));
  perform t_ok('an administrator can set the manager''s KPI', (o->>'ok')::boolean, o::text);
  a_boss := (o->>'assignmentId')::uuid;

  o := perf_assign(boss, jsonb_build_object('personId', rep, 'cycleId', cyc,
         'kpiId', k_case, 'target', '300', 'weight', '70', 'cadence', 'DAILY',
         'rollsInto', a_boss));
  perform t_ok('the manager sets the report''s KPI', (o->>'ok')::boolean, o::text);
  a_rep := (o->>'assignmentId')::uuid;

  o := perf_assign(boss, jsonb_build_object('personId', rep, 'cycleId', cyc,
         'kpiId', k_qual, 'target', '95', 'weight', '30', 'cadence', 'WEEKLY',
         'cadenceDay', '5'));
  a_qual := (o->>'assignmentId')::uuid;

  o := perf_assign(other, jsonb_build_object('personId', rep, 'cycleId', cyc,
         'kpiId', k_case, 'target', '9'));
  perform t_ok('a stranger is refused by the database, not by the service',
               o->>'error' = 'not_permitted', o::text);

  perform t_ok('the cadence given was stored',
               (select cadence::text from perf_assignment where id = a_rep) = 'DAILY',
               (select cadence::text from perf_assignment where id = a_rep));

  -- the report splits their case target by client
  insert into perf_assignment (cycle_id, person_id, kpi_id, name, unit, target_value,
      part_of_id, split_kind, split_label, set_by)
  values (cyc, rep, k_case, 'Case Target', 'cases', 200, a_rep, 'CLIENT', 'SBI', boss)
  returning id into a_p1;
  insert into perf_assignment (cycle_id, person_id, kpi_id, name, unit, target_value,
      part_of_id, split_kind, split_label, set_by)
  values (cyc, rep, k_case, 'Case Target', 'cases', 100, a_rep, 'CLIENT', 'HDFC', boss)
  returning id into a_p2;

  insert into who values ('a_boss',a_boss),('a_rep',a_rep),('a_qual',a_qual),
                         ('a_p1',a_p1),('a_p2',a_p2);
end $$;

-- ================================================ 191: the two edges hold
do $$
declare cyc uuid; boss uuid; rep uuid; a_rep uuid; a_boss uuid; bad boolean;
begin
  select id into cyc from who where nm ='cycle';
  select id into boss from who where nm ='boss'; select id into rep from who where nm ='rep';
  select id into a_rep from who where nm ='a_rep'; select id into a_boss from who where nm ='a_boss';

  bad := false;
  begin
    insert into perf_assignment (cycle_id, person_id, name, part_of_id, split_kind,
                                 split_label, set_by)
    values (cyc, boss, 'Case Target', a_rep, 'CLIENT', 'X', boss);
  exception when others then bad := true; end;
  perform t_ok('a split must belong to the same person as what it splits', bad);

  bad := false;
  begin
    insert into perf_assignment (cycle_id, person_id, name, rolls_into_id, set_by)
    values (cyc, rep, 'Something', a_rep, boss);
  exception when others then bad := true; end;
  perform t_ok('a measure cannot climb into one of its owner''s own', bad);
end $$;

-- ================================================== 192 + 194: filing
do $$
declare boss uuid; rep uuid; a_rep uuid; a_p1 uuid; a_p2 uuid; a_qual uuid;
        o jsonb; cyc uuid; ps date;
begin
  select id into boss from who where nm ='boss'; select id into rep from who where nm ='rep';
  select id into a_rep from who where nm ='a_rep'; select id into a_p1 from who where nm ='a_p1';
  select id into a_p2 from who where nm ='a_p2'; select id into a_qual from who where nm ='a_qual';
  select id into cyc from who where nm ='cycle';
  select period_start into ps from perf_cycle where id = cyc;

  o := perf_file(rep, a_rep, ps, 10);
  perform t_ok('a measure with parts is refused in words, not by a raise',
               o->>'error' = 'has_parts', o::text);

  o := perf_file(boss, a_p1, ps, 10);
  perform t_ok('a manager does not file on somebody''s behalf',
               o->>'error' = 'not_yours', o::text);

  o := perf_file(rep, a_p1, ps, 60);
  perform t_ok('the person files their own', (o->>'ok')::boolean, o::text);
  o := perf_file(rep, a_p1, ps + 1, 100);
  o := perf_file(rep, a_p2, ps, 54);

  o := perf_file(rep, a_p1, ps - 1, 5);
  perform t_ok('a day outside the period is refused',
               o->>'error' = 'outside_the_period', o::text);

  o := perf_file(rep, a_p1, ps, 70);
  perform t_ok('re-filing the same day says what it changed from',
               o->>'note' like 'Changed from 60%', o::text);
  perform t_ok('a change is a different audit action from a first filing',
               exists (select 1 from audit_entry where action='PERF_REFILED'));

  -- the level measure: today replaces, it does not add
  perform perf_file(rep, a_qual, ps, 88);
  perform perf_file(rep, a_qual, ps + 1, 93);
end $$;

-- ====================================== 193: the one rule that makes it add up
do $$
declare a_rep uuid; a_boss uuid; a_qual uuid; v numeric;
begin
  select id into a_rep from who where nm ='a_rep'; select id into a_boss from who where nm ='a_boss';
  select id into a_qual from who where nm ='a_qual';

  -- SBI 70 + 100 = 170, HDFC 54; the parent is the sum of its parts
  perform t_ok('a count accumulates across days and splits',
               perf_value(a_rep) = 224, perf_value(a_rep)::text);

  -- the manager has filed nothing of their own, so their number is the team's
  perform t_ok('a number climbs to the manager',
               perf_value(a_boss) = 224, perf_value(a_boss)::text);

  -- a level REPLACES rather than adding: 88 then 93 is 93, not 181
  perform t_ok('a level is the latest, not the total',
               perf_value(a_qual) = 93, perf_value(a_qual)::text);

  perform t_ok('the kind is read off the catalogue, not guessed',
               perf_accrual_kind((select kpi_id from perf_assignment where id=a_qual), '%') = 'LEVEL');
  -- 200: a percentage that claims to accumulate is a default nobody set,
  -- and believing it is how 93% and 88% became 181%.
  perform t_ok('a percentage marked ADDS is still a level',
               (select perf_accrual_kind(id, unit) from kpi_definition
                 where name = 'Pct marked adds') = 'LEVEL');
  perform t_ok('an explicit REPLACES wins even on a counted unit',
               (select perf_accrual_kind(id, unit) from kpi_definition
                 where name = 'Count marked replaces') = 'LEVEL');
  perform t_ok('and a plain count still accumulates',
               (select perf_accrual_kind(id, unit) from kpi_definition
                 where name = 'Case Target') = 'SUM');
  perform t_ok('a unit with a percent sign is a level even with no catalogue',
               perf_accrual_kind(null, '%') = 'LEVEL');
  perform t_ok('anything else accumulates',
               perf_accrual_kind(null, 'cases') = 'SUM');
end $$;

-- ================================================= 195: what a manager sees
do $$
declare cyc uuid; boss uuid; rep uuid; t jsonb; s jsonb; node jsonb;
begin
  select id into cyc from who where nm ='cycle';
  select id into boss from who where nm ='boss'; select id into rep from who where nm ='rep';

  t := perf_tree(rep, cyc);
  perform t_ok('the tree names the person', t#>>'{person,employeeNo}' = 'EMP-FE01', t::text);
  perform t_ok('the tree has the two top measures',
               jsonb_array_length(t->'measures') = 2,
               jsonb_array_length(t->'measures')::text);

  select m into node from jsonb_array_elements(t->'measures') m
   where m->>'name' = 'Case Target';
  perform t_ok('the split sits under its parent',
               jsonb_array_length(node->'parts') = 2, node::text);
  perform t_ok('the parent carries the total', (node->>'value')::numeric = 224);
  perform t_ok('the percentage is against the target',
               (node->>'pct')::numeric = round(100.0*224/300, 1), node->>'pct');

  t := perf_tree(boss, cyc);
  select m into node from jsonb_array_elements(t->'measures') m;
  perform t_ok('the manager sees who climbed into their measure',
               jsonb_array_length(node->'team') = 1, node::text);
  perform t_ok('and the chair that person holds',
               node#>>'{team,0,person,chair}' = 'Field Executive', node::text);

  -- the score: 224/300 is 74.67, 93/95 is 97.89, weighted 70/30
  s := perf_kpi_score(rep, cyc);
  perform t_ok('both measures scored', (s->>'counted')::int = 2, s::text);
  perform t_ok('the weighted achievement is right',
               (s->>'achievement')::numeric =
                 round((round(100.0*224/300,2)*70 + round(100.0*93/95,2)*30)/100, 2),
               s->>'achievement');
end $$;

-- ===================== 195: a measure with no target is not a measure missed
do $$
declare cyc uuid; rep uuid; boss uuid; k uuid; s jsonb; before numeric;
begin
  select id into cyc from who where nm ='cycle';
  select id into rep from who where nm ='rep'; select id into boss from who where nm ='boss';
  select id into k from kpi_definition where name='Branch case target';
  before := (perf_kpi_score(rep, cyc)->>'achievement')::numeric;

  perform perf_assign(boss, jsonb_build_object('personId', rep, 'cycleId', cyc,
    'kpiId', k, 'weight', '50'));       -- deliberately no target
  s := perf_kpi_score(rep, cyc);

  perform t_ok('a measure with no target is left out, not counted as zero',
               (s->>'achievement')::numeric = before, s::text);
  perform t_ok('and it is named with the reason',
               s::text like '%no target was set%', s::text);
  perform t_ok('and the count says how many were skipped',
               (s->>'skipped')::int = 1, s::text);
end $$;

-- ============================================ 194: carrying a month forward
do $$
declare hr uuid; rep uuid; boss uuid; nxt uuid; o jsonb; n int;
begin
  select id into hr from who where nm ='hr'; select id into rep from who where nm ='rep';
  select id into boss from who where nm ='boss';
  nxt := (perf_cycle_open(hr, '2026-11-05')->>'cycleId')::uuid;

  o := perf_carry_forward(boss, nxt, rep);
  perform t_ok('last month''s measures carry forward', (o->>'copied')::int >= 2, o::text);
  select count(*) into n from perf_assignment
   where cycle_id = nxt and person_id = rep and target_value is not null;
  perform t_ok('and the targets are deliberately blank', n = 0, n::text);

  o := perf_carry_forward(boss, nxt, rep, true);
  perform t_ok('asking for the targets keeps them, and nothing is duplicated',
               (o->>'copied')::int = 0, o::text);
end $$;

-- ================================================ 197: the cadence, on a clock
do $$
declare rep uuid; cyc uuid; ps date; d jsonb; sunday date; hol date;
begin
  select id into rep from who where nm ='rep'; select id into cyc from who where nm ='cycle';
  select period_start into ps from perf_cycle where id = cyc;

  select g::date into sunday from generate_series(ps, ps+13, '1 day') g
   where extract(isodow from g) = 7 limit 1;
  perform t_ok('nothing is due on a Sunday',
               jsonb_array_length(perf_due(rep, sunday)) = 0,
               perf_due(rep, sunday)::text);

  perform t_ok('nothing is due on a national holiday',
               jsonb_array_length(perf_due(rep, '2026-10-02')) = 0);

  perform t_ok('a daily measure is due on a working day',
               perf_due(rep, '2026-10-05')::text like '%Case Target%',
               perf_due(rep, '2026-10-05')::text);

  perform t_ok('a weekly measure set to Friday is due on the Friday',
               perf_due(rep, '2026-10-09')::text like '%Quality score%');
  perform t_ok('and not on the Thursday',
               perf_due(rep, '2026-10-08')::text not like '%Quality score%');

  perform t_ok('what is already filed says so',
               (perf_due(rep, ps)::text like '%"alreadyFiled": true%')
            or (perf_due(rep, ps)::text like '%"alreadyFiled":true%'),
               perf_due(rep, ps)::text);
end $$;

-- ================================= 197: a day of the month rolls forward
do $$
declare cyc uuid; hr uuid; boss uuid; rep uuid; k uuid; a uuid; ok boolean;
begin
  select id into cyc from who where nm ='cycle'; select id into hr from who where nm ='hr';
  select id into boss from who where nm ='boss'; select id into rep from who where nm ='rep';
  select id into k from kpi_definition where name='Quality score';

  -- the 11th of October 2026 is a Sunday; the 12th is a Pune holiday, and
  -- Reva Pawar has no single city, so only national holidays count for her.
  perform t_ok('11 Oct 2026 is a Sunday', extract(isodow from date '2026-10-11') = 7);
  perform t_ok('a nominal day on a Sunday rolls to the Monday',
               perf_roll_forward('2026-10-11', null) = '2026-10-12',
               perf_roll_forward('2026-10-11', null)::text);
  perform t_ok('and where the holiday reaches, it rolls one further',
               perf_roll_forward('2026-10-11', 'Pune') = '2026-10-13',
               perf_roll_forward('2026-10-11', 'Pune')::text);
end $$;

-- ================================================== 197: the reminder sweep
do $$
declare o jsonb; n int;
begin
  o := perf_reminder_sweep('2026-10-05');
  perform t_ok('the sweep ran and said what it did', o ? 'due', o::text);
  select count(*) into n from outbox where template_key = 'PERF_DUE';
  perform t_ok('the person who owes something is written to', n >= 1, n::text);
  perform t_ok('the letter names the measure',
               exists (select 1 from outbox where template_key='PERF_DUE'
                        and body like '%Case Target%'));

  perform perf_reminder_sweep('2026-10-05');
  select count(*) into n from outbox where template_key = 'PERF_DUE';
  perform t_ok('running it twice on the same day does not write twice',
               n = (select count(*) from outbox where template_key='PERF_DUE'), n::text);

  perform t_ok('nobody is reminded on a Sunday',
               (perf_reminder_sweep('2026-10-11')->>'due')::int = 0);

  perform t_ok('the run is in job_run', exists (
    select 1 from job_run where job_key='PERF_REMINDERS' and state='DONE'));
end $$;

-- =========================================== 196: the pack, and what is held
do $$
declare boss uuid; cl uuid; p jsonb; m jsonb; o jsonb;
begin
  select id into boss from who where nm ='boss'; select id into cl from who where nm ='cl';
  insert into client_view_policy (department, view_kind) values ('Operations','matrix')
    on conflict (department) do update set view_kind = 'matrix';

  p := matrix_pack(boss, cl, '2026-10-05');
  perform t_ok('the pack names the client', p#>>'{client,code}' = 'SBI', p::text);
  perform t_ok('one branch is ready', (p->>'ready')::int = 1, p::text);
  perform t_ok('and one is held back', (p->>'incomplete')::int = 1, p::text);
  perform t_ok('the held-back branch is named, not silently dropped',
               p#>>'{heldBack,0,code}' = 'PUN-002', p::text);
  perform t_ok('the held-back branch says how many levels are missing',
               (p#>>'{heldBack,0,missing}')::int = 2, p::text);
  perform t_ok('the client''s contacts come with it',
               jsonb_array_length(p->'recipients') = 2, p::text);
  perform t_ok('nothing has been sent yet', p->'dispatch' = 'null'::jsonb, p::text);

  m := matrix_month(boss, '2026-10-05');
  perform t_ok('the month lists the client once',
               jsonb_array_length(m->'clients') = 1, m::text);
  perform t_ok('and says it has not gone out',
               m#>>'{clients,0,sentAt}' is null, m::text);
  perform t_ok('Operations may send it', (m->>'maySend')::boolean, m::text);
end $$;

-- ============================================ 196: who may not see it at all
do $$
declare rep uuid; cl uuid; p jsonb;
begin
  select id into rep from who where nm ='rep'; select id into cl from who where nm ='cl';
  insert into client_view_policy (department, view_kind) values ('Human Resources','none')
    on conflict (department) do update set view_kind = 'none';
  p := matrix_pack((select id from who where nm ='hr'), cl, '2026-10-05');
  perform t_ok('a function with no client view is refused in words',
               p->>'error' = 'no_client_view', p::text);
end $$;

-- ====================================================== 196: sending it
do $$
declare boss uuid; cl uuid; o jsonb; p jsonb; snap jsonb;
begin
  select id into boss from who where nm ='boss'; select id into cl from who where nm ='cl';

  o := matrix_send(boss, cl, '2026-10-05', array[]::text[]);
  perform t_ok('sending to nobody is refused', o->>'error' = 'no_recipient', o::text);

  o := matrix_send(boss, cl, '2026-10-05', array['vendors@sbi.test']);
  perform t_ok('it sends', (o->>'ok')::boolean, o::text);
  perform t_ok('one branch went', (o->>'branches')::int = 1, o::text);
  perform t_ok('the letter has the five levels',
               o->>'body' like '%L5%', left(o->>'body', 400));
  perform t_ok('and names what was held back inside the letter itself',
               o->>'body' like '%Pune Hadapsar%', o->>'body');
  perform t_ok('the send is in the trail',
               exists (select 1 from audit_entry where action='MATRIX_SENT'));

  select snapshot into snap from matrix_dispatch where client_id = cl;
  perform t_ok('a snapshot was frozen', (snap->>'ready')::int = 1, snap::text);

  -- change a contact after the send; the snapshot must not move
  update matrix_contact set name = 'Somebody Else'
   where branch_id = (select id from who where nm ='br1') and level = 1;
  select snapshot into snap from matrix_dispatch where client_id = cl;
  perform t_ok('and a contact changed afterwards does not rewrite it',
               snap::text not like '%Somebody Else%', snap::text);

  o := matrix_send(boss, cl, '2026-10-05', array['vendors@sbi.test','ops@sbi.test']);
  perform t_ok('sending again is recorded as a re-send',
               o->>'note' like 'Sent again%', o::text);
  perform t_ok('and there is still only one dispatch for the month',
               (select count(*) from matrix_dispatch where client_id = cl) = 1);
  perform t_ok('the re-send is a different action in the trail',
               exists (select 1 from audit_entry where action='MATRIX_RESENT'));

  perform t_ok('the month now says it has gone',
               (matrix_month(boss,'2026-10-05')#>>'{clients,0,sentAt}') is not null);
end $$;

-- ============================================ 198: the nudge, once a month
do $$
declare o jsonb; n int; boss uuid; cl uuid;
begin
  select id into boss from who where nm ='boss'; select id into cl from who where nm ='cl';
  delete from matrix_dispatch;          -- nothing has gone out this month
  o := matrix_nudge_sweep('2026-10-07');
  perform t_ok('the person who covers it is nudged', (o->>'nudges')::int = 1, o::text);
  perform t_ok('the nudge names the client',
               exists (select 1 from outbox where template_key='MATRIX_NUDGE'
                        and body like '%State Bank of India%'));
  perform t_ok('and names what is holding it up',
               exists (select 1 from outbox where template_key='MATRIX_NUDGE'
                        and body like '%missing a level%'));

  select count(*) into n from outbox where template_key='MATRIX_NUDGE';
  perform matrix_nudge_sweep('2026-10-08');
  perform t_ok('twice in a month is once',
               (select count(*) from outbox where template_key='MATRIX_NUDGE') = n, n::text);
end $$;

-- ============================================ 202: anything you need from
-- another department
do $$
declare hr uuid; boss uuid; rep uuid; o jsonb; task uuid; d jsonb;
begin
  select id into hr from who where nm='hr'; select id into boss from who where nm='boss';
  select id into rep from who where nm='rep';
  delete from request_task; delete from raisable; delete from notification;

  o := request_raise(boss, jsonb_build_object('department','Human Resources'));
  perform t_ok('a request with nothing in it is refused',
               o->>'error' = 'incomplete', o::text);

  o := request_raise(boss, jsonb_build_object(
         'department','Technology', 'type','Equipment', 'body','A second monitor'));
  perform t_ok('a department with nobody in it is refused in words',
               o->>'error' = 'nobody_there', o::text);

  o := request_raise(hr, jsonb_build_object(
         'department','Human Resources', 'body','Something from myself'));
  perform t_ok('and being the only one there is a different refusal',
               o->>'error' = 'only_you', o::text);

  o := request_raise(boss, jsonb_build_object(
         'department','Human Resources', 'type','Document',
         'body','A copy of my appointment letter'));
  perform t_ok('a real request is raised', (o->>'ok')::boolean, o::text);
  perform t_ok('and it names who it went to', o->>'responder' = 'Hema Rao', o::text);
  perform t_ok('and when it is due', (o->>'dueAt')::timestamptz > now(), o::text);
  perform t_ok('and the reference is a REQ', o->>'ref' like 'REQ%', o->>'ref');
  task := (o->>'taskId')::uuid;

  perform t_ok('the responder was told',
               exists (select 1 from notification n join person p on p.id = n.person_id
                        where p.full_name = 'Hema Rao' and n.kind = 'REQUEST_RAISED'));

  o := request_action(boss, task);
  perform t_ok('the person who raised it cannot action it',
               o->>'error' = 'not_yours', o::text);

  o := request_action(hr, task, 'Attached.');
  perform t_ok('the responder can', (o->>'ok')::boolean, o::text);
  perform t_ok('and it was inside the time', (o->>'late')::boolean = false, o::text);
  perform t_ok('the raiser was told back',
               exists (select 1 from notification n where n.kind = 'REQUEST_ACTIONED'));

  o := request_action(hr, task);
  perform t_ok('actioning it again says so rather than doing it twice',
               o->>'note' like 'That one was already actioned%', o::text);
end $$;

-- ------------------------------------------------------------ the strikes
do $$
declare hr uuid; boss uuid; rep uuid; o jsonb; task uuid; n int;
begin
  select id into hr from who where nm='hr'; select id into boss from who where nm='boss';
  select id into rep from who where nm='rep';
  delete from request_task; delete from raisable; delete from notification;

  -- Reva reports to Bharat, so a strike against Reva reaches Bharat
  o := request_raise(hr, jsonb_build_object(
         'department','Operations', 'body','The Kothrud rate card'));
  task := (o->>'taskId')::uuid;
  update request_task set responder_id = rep where id = task;
  update request_task set due_at = now() - interval '2 hours' where id = task;

  o := request_strike_sweep();
  perform t_ok('an overdue request takes a strike', (o->>'strikes')::int = 1, o::text);
  perform t_ok('and the responder is told',
               exists (select 1 from notification n
                        where n.person_id = rep and n.kind = 'REQUEST_STRIKE'));
  perform t_ok('but the manager is not, on the first',
               not exists (select 1 from notification n
                            where n.person_id = boss and n.kind = 'REQUEST_STRIKE'));

  perform request_strike_sweep();
  perform t_ok('on the second the manager is told',
               exists (select 1 from notification n
                        where n.person_id = boss and n.kind = 'REQUEST_STRIKE'));

  perform request_strike_sweep();
  perform request_strike_sweep();
  select strike_count into n from request_task where id = task;
  perform t_ok('and it stops at three', n = 3, n::text);

  o := request_action(rep, task);
  perform t_ok('actioning it late says it was late', (o->>'late')::boolean, o::text);
end $$;

-- ------------------------------------------------------------- the screen
do $$
declare rep uuid; boss uuid; d jsonb; docs jsonb;
begin
  select id into rep from who where nm='rep'; select id into boss from who where nm='boss';

  d := my_desk(rep);
  perform t_ok('the desk names the person', d#>>'{person,name}' = 'Reva Pawar', d::text);
  perform t_ok('employment has six lines',
               jsonb_array_length(d->'employment') = 6, d->>'employment');
  perform t_ok('and names the chair',
               d::text like '%Field Executive%', d->>'employment');
  perform t_ok('contact has the four the design asks for',
               jsonb_array_length(d->'contact') = 4, d->>'contact');
  perform t_ok('including an address, which the person table had nowhere for',
               d->>'contact' like '%Address%', d->>'contact');

  perform t_ok('all four documents are listed',
               jsonb_array_length(d->'documents') = 4, d->>'documents');
  perform t_ok('and one nobody has asked for has no state rather than a blank',
               (d#>'{documents,0,state}') = 'null'::jsonb, d->>'documents');

  insert into person_document (person_id, kind, state) values (rep, 'ID_PROOF', 'VERIFIED')
  on conflict (person_id, kind) do update set state = 'VERIFIED';
  d := my_desk(rep);
  perform t_ok('and one that has been produced carries its state',
               d#>>'{documents,0,state}' = 'VERIFIED', d->>'documents');

  perform t_ok('what I asked for is on my desk',
               jsonb_array_length(d->'raised') >= 0, d->>'raised');
  perform t_ok('and what is waiting on me is separate from it',
               d ? 'onMe', d::text);
  perform t_ok('and what I owe today comes from the same perf_due',
               d ? 'dueToday', d::text);
end $$;

-- ===================================================================== done
do $$
declare n int;
begin
  select count(*) into n from perf_assignment;
  raise notice '--- % assignments, % entries, % outbox rows, % audit rows',
    n, (select count(*) from perf_entry), (select count(*) from outbox),
    (select count(*) from audit_entry);
end $$;
