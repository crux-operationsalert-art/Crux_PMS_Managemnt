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

  raise notice '--- which way a measure points: every assertion passed ---';
end $t$;

rollback;
