-- Which way a measure points, and a target of zero (migration 253)
--
-- "lower or higher depends on the KPI ... which would be defined by the one
--  up manager along with the KPI, we only suggest that xyz KPI can be given
--  then the one up manager decides and edits as per the requirement"
-- "There will never be 0 KPI ... Yes there is a possibility of 0 in KPIs like
--  0 escalation but then the one up manager should be adding 0 in the target
--  and not keep it blank."
--
-- Two sentences, and both are about the same thing: a judgement belongs to
-- the manager who set the measure, not to a rule the tool inferred from a
-- unit string.
--
-- Everything is rolled back.

begin;

do $t$
declare
  p_boss uuid; p_rep uuid; v_cycle uuid; v_kpi uuid; v_a uuid;
  v_chair uuid; v_sheet uuid; v_k2 uuid; v_g2 uuid; v_ach numeric;
  o jsonb; s jsonb; n int;
begin
  -- ------------------------------------------------------- the formula
  if perf_ratio('HIGHER', 100, 50) <> 50 then
    raise exception 'FAIL  the ordinary case moved. Every number that scores '
                    'today has to score the same afterwards.';
  end if;
  if perf_ratio('HIGHER', 100, 500) <> 150 then
    raise exception 'FAIL  the cap moved';
  end if;
  raise notice 'PASS  a measure that reads upward scores exactly as it did';

  if perf_ratio('LOWER', 2, 4) >= 100 then
    raise exception 'FAIL  doubling a ceiling still pays like beating a target. '
                    'That is the defect: 181 goal KPIs reward being worse.';
  end if;
  if perf_ratio('LOWER', 2, 1) <= 100 then
    raise exception 'FAIL  beating a ceiling does not pay above a hundred';
  end if;
  raise notice 'PASS  a measure that reads downward is turned the right way up';

  -- -------------------------------------------------------- zero is a target
  if perf_ratio('LOWER', 0, 0) <> 100 then
    raise exception 'FAIL  zero escalations against a target of zero is not '
                    'met. There is no beating zero, so meeting it is a hundred.';
  end if;
  if perf_ratio('LOWER', 0, 3) <> 0 then
    raise exception 'FAIL  three escalations against a target of zero scored '
                    'something';
  end if;
  raise notice 'PASS  a target of zero is a promise, kept or broken';

  -- --------------------------------------------- and null is NOT zero
  if perf_ratio('HIGHER', null, 5) is not null then
    raise exception 'FAIL  a measure nobody set a target for was scored';
  end if;
  if perf_ratio('HIGHER', 5, null) is not null then
    raise exception 'FAIL  a measure nothing was filed against was scored';
  end if;
  raise notice 'PASS  and a target nobody has set yet is not a target of zero';

  -- ------------------------------------------- the manager decides, per KPI
  insert into person (full_name, work_email, app_role)
    values ('RT Boss','rt.boss@example.invalid','MANAGER') returning id into p_boss;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('RT Rep','rt.rep@example.invalid','VIEWER', p_boss) returning id into p_rep;
  insert into kpi_definition (name, unit, active, position)
    values ('RT measure','COUNT', true, 1) returning id into v_kpi;

  o := perf_cycle_open(p_boss, date_trunc('month', current_date)::date, 'MONTH');
  select id into v_cycle from perf_cycle
   where period_start = date_trunc('month', current_date)::date and period_kind = 'MONTH';

  -- The window, held open for the length of this test. perf_cycle_open sets
  -- assign_closes five working days in, so a cycle the baseline carried in
  -- from an earlier month is already shut -- and then the assertions below
  -- fail on the calendar rather than on the rule they are there to test.
  -- A suite that goes red on a date is a suite people stop reading.
  -- Rolled back with everything else.
  update perf_cycle set assign_closes = current_date + 30,
                        entry_closes  = greatest(entry_closes, current_date + 30)
   where period_start = date_trunc('month', current_date)::date
     and period_kind = 'MONTH';

  -- The registry suggests; the manager decides. A COUNT suggests HIGHER, and
  -- this manager says this one is a ceiling.
  if perf_direction_of(v_kpi, 'COUNT') <> 'HIGHER' then
    raise exception 'FAIL  the registry does not suggest a direction for a count';
  end if;
  if perf_direction_of(v_kpi, 'COUNT', 'LOWER') <> 'LOWER' then
    raise exception 'FAIL  the manager''s answer did not win over the '
                    'registry''s suggestion';
  end if;
  raise notice 'PASS  the registry suggests and the one-up manager decides';

  o := perf_assign(p_boss, jsonb_build_object(
         'cycleId', v_cycle, 'personId', p_rep, 'kpiId', v_kpi,
         'target', 0, 'direction','LOWER'));
  if o->>'error' is not null then
    raise exception 'FAIL  a measure could not be given with a target of zero '
                    'and a direction: %', o;
  end if;
  select id into v_a from perf_assignment
   where cycle_id = v_cycle and person_id = p_rep and kpi_id = v_kpi
     and state is distinct from 'WITHDRAWN';
  if (select direction from perf_assignment where id = v_a) <> 'LOWER' then
    raise exception 'FAIL  the direction the manager chose was not kept';
  end if;
  if (select target_value from perf_assignment where id = v_a) <> 0 then
    raise exception 'FAIL  a target of zero did not save as zero';
  end if;
  raise notice 'PASS  the direction is set alongside the target, and zero saves';

  -- --------------------------------------- and the month's score reads both
  s := perf_kpi_score(p_rep, v_cycle);
  if s::text like '%no target has been set yet%' then
    raise exception 'FAIL  a target of zero was read as no target: %', s;
  end if;
  raise notice 'PASS  and the month''s score counts it rather than skipping it';

  -- ------------------------------------------- and in the quarter's money
  -- 260. plb_compute dropped a target of zero, which voided the whole
  -- sheet's Achievement, and divided actual by target whatever the measure
  -- was, which paid more for a worse ceiling number.
  select id into v_chair from chair order by title limit 1;
  insert into kpi_definition (name, unit, active, position)
    values ('RT ceiling','% of work returned', true, 2) returning id into v_k2;
  insert into plb_goal_sheet (person_id, chair_id, quarter, target_plb_inr, status)
    values (p_rep, v_chair, date '2031-01-01', 100000, 'ISSUED') returning id into v_sheet;
  insert into plb_goal_kpi (sheet_id, kpi_id, weight_pct, target_value, actual_value)
    values (v_sheet, v_kpi, 50, 100, 100);
  insert into plb_goal_kpi (sheet_id, kpi_id, weight_pct, target_value, actual_value, direction)
    values (v_sheet, v_k2, 50, 0, 0, 'LOWER') returning id into v_g2;

  v_ach := (plb_compute(v_sheet)->>'achievement')::numeric;
  if v_ach is distinct from 100 then
    raise exception 'FAIL  a zero target met exactly does not count in the bonus: '
                    'Achievement %', v_ach;
  end if;
  update plb_goal_kpi_all set actual_value = 1 where id = v_g2;
  v_ach := (plb_compute(v_sheet)->>'achievement')::numeric;
  if v_ach is distinct from 50 then
    raise exception 'FAIL  a zero target missed is not a zero: Achievement %', v_ach;
  end if;
  update plb_goal_kpi_all set target_value = 2, actual_value = 4 where id = v_g2;
  v_ach := (plb_compute(v_sheet)->>'achievement')::numeric;
  if v_ach is distinct from 75 then
    raise exception 'FAIL  a ceiling measure at twice its ceiling scored %, not '
                    '75 (it was being paid 100 for it)', v_ach;
  end if;
  update plb_goal_kpi_all set direction = null, target_value = 100, actual_value = 123.456
   where sheet_id = v_sheet and kpi_id = v_kpi;
  update plb_goal_kpi_all set target_value = 4, actual_value = 2 where id = v_g2;
  v_ach := (plb_compute(v_sheet)->>'achievement')::numeric;
  if v_ach is distinct from round(50 * 1.23456 + 50 * 1.5, 3) then
    raise exception 'FAIL  an ordinary measure moved in the bonus: %', v_ach;
  end if;
  raise notice 'PASS  in the quarter''s bonus a zero target counts, a ceiling '
               'is the right way up, and an ordinary measure did not move';

  raise notice '--- which way a measure points: every assertion passed ---';
end $t$;

rollback;
