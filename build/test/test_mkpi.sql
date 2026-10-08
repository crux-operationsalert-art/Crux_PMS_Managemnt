-- One monthly scorecard, saved whole (migration 257)
--
-- "The current KPI/target assignment journey is too complicated ... Redesign
--  the journey to be extremely simple."
--
-- Each assertion is one of the rules the owner set:
--
--   nobody sets their own
--   at least three measures
--   at most five -- but never a wall in front of somebody already over it
--   the weights add to a hundred, and rounding is not a mistake
--   every measure carries a target, and zero is one
--   a measure with numbers filed against it cannot be taken off
--   a refusal writes nothing at all
--   a parent's value comes from its sub-KPIs, summed or weighted
--   a filing against a parent is refused
--
-- Everything is rolled back.

begin;

do $t$
declare
  p_boss uuid; p_rep uuid; v_cycle uuid;
  k1 uuid; k2 uuid; k3 uuid; k4 uuid; k5 uuid; k6 uuid; kl uuid;
  a1 uuid; a2 uuid; a3 uuid; ap uuid; c1 uuid; c2 uuid;
  o jsonb; n int; v numeric; v_list jsonb;
begin
  insert into person (full_name, work_email, app_role)
    values ('MK Boss','mk.boss@example.invalid','MANAGER') returning id into p_boss;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('MK Rep','mk.rep@example.invalid','VIEWER', p_boss) returning id into p_rep;

  insert into kpi_definition (name, unit, active, position, accrual)
    values ('MK one','COUNT', true, 1, 'ADDS') returning id into k1;
  insert into kpi_definition (name, unit, active, position, accrual)
    values ('MK two','COUNT', true, 2, 'ADDS') returning id into k2;
  insert into kpi_definition (name, unit, active, position, accrual)
    values ('MK three','COUNT', true, 3, 'ADDS') returning id into k3;
  insert into kpi_definition (name, unit, active, position, accrual)
    values ('MK four','COUNT', true, 4, 'ADDS') returning id into k4;
  insert into kpi_definition (name, unit, active, position, accrual)
    values ('MK five','COUNT', true, 5, 'ADDS') returning id into k5;
  insert into kpi_definition (name, unit, active, position, accrual)
    values ('MK six','COUNT', true, 6, 'ADDS') returning id into k6;
  insert into kpi_definition (name, unit, active, position, accrual)
    values ('MK level','% of target', true, 7, 'REPLACES') returning id into kl;

  o := perf_cycle_open(p_boss, date_trunc('month', current_date)::date, 'MONTH');
  select id into v_cycle from perf_cycle
   where period_start = date_trunc('month', current_date)::date and period_kind = 'MONTH';

  -- ------------------------------------------------------- nobody's own
  if perf_kpis_set(p_rep, v_cycle, p_rep, jsonb_build_array(
       jsonb_build_object('kpiId', k1, 'weight', 100, 'target', 10)))
     ->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  a person set their own scorecard. Every other rule '
                    'in the scheme rests on not being able to.';
  end if;
  raise notice 'PASS  nobody sets their own monthly scorecard';

  -- --------------------------------------------------- at least three
  if perf_kpis_set(p_boss, v_cycle, p_rep, jsonb_build_array(
       jsonb_build_object('kpiId', k1, 'weight', 50, 'target', 10),
       jsonb_build_object('kpiId', k2, 'weight', 50, 'target', 20)))
     ->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  a scorecard of two measures was accepted';
  end if;
  raise notice 'PASS  a scorecard carries at least three measures';

  -- ------------------------------------------------- the weights add up
  if perf_kpis_set(p_boss, v_cycle, p_rep, jsonb_build_array(
       jsonb_build_object('kpiId', k1, 'weight', 50, 'target', 10),
       jsonb_build_object('kpiId', k2, 'weight', 50, 'target', 20),
       jsonb_build_object('kpiId', k3, 'weight', 50, 'target', 30)))
     ->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  weights of 150 were accepted';
  end if;
  raise notice 'PASS  the weights have to come to a hundred';

  -- ------------------------------------------- and rounding is not an error
  --
  -- Three measures at 33.33 come to 99.99. Of the hundred and one people
  -- carrying measures live, seventy-six sum to something other than exactly
  -- a hundred and every one is this. An exact test would refuse them all.
  o := perf_kpis_set(p_boss, v_cycle, p_rep, jsonb_build_array(
         jsonb_build_object('kpiId', k1, 'weight', 33.33, 'target', 10),
         jsonb_build_object('kpiId', k2, 'weight', 33.33, 'target', 20),
         jsonb_build_object('kpiId', k3, 'weight', 33.33, 'target', 30)));
  if o->>'error' is not null then
    raise exception 'FAIL  three measures at 33.33 were refused: %', o;
  end if;
  if (o->>'added')::int <> 3 then
    raise exception 'FAIL  the reply does not say it added three: %', o;
  end if;
  raise notice 'PASS  weights that round to a hundred are a hundred';

  -- ------------------------------------------ a target, and zero is one
  select id into a1 from perf_assignment
   where cycle_id = v_cycle and person_id = p_rep and kpi_id = k1 and part_of_id is null;
  select id into a2 from perf_assignment
   where cycle_id = v_cycle and person_id = p_rep and kpi_id = k2 and part_of_id is null;
  select id into a3 from perf_assignment
   where cycle_id = v_cycle and person_id = p_rep and kpi_id = k3 and part_of_id is null;

  if perf_kpis_set(p_boss, v_cycle, p_rep, jsonb_build_array(
       jsonb_build_object('assignmentId', a1, 'weight', 33.33),
       jsonb_build_object('assignmentId', a2, 'weight', 33.33, 'target', 20),
       jsonb_build_object('assignmentId', a3, 'weight', 33.34, 'target', 30)))
     ->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  a measure with no target was accepted. "One up '
                    'manager if has assigned a KPI should be assigning the '
                    'target too."';
  end if;
  o := perf_kpis_set(p_boss, v_cycle, p_rep, jsonb_build_array(
         jsonb_build_object('assignmentId', a1, 'weight', 33.33, 'target', 0),
         jsonb_build_object('assignmentId', a2, 'weight', 33.33, 'target', 20),
         jsonb_build_object('assignmentId', a3, 'weight', 33.34, 'target', 30)));
  if o->>'error' is not null then
    raise exception 'FAIL  a target of zero was refused: %', o;
  end if;
  if (select target_value from perf_assignment where id = a1) <> 0 then
    raise exception 'FAIL  a target of zero did not save as zero';
  end if;
  raise notice 'PASS  every measure carries a target, and zero is one of them';

  -- -------------------------------------------------------- at most five
  if perf_kpis_set(p_boss, v_cycle, p_rep, jsonb_build_array(
       jsonb_build_object('assignmentId', a1, 'weight', 16.66, 'target', 1),
       jsonb_build_object('assignmentId', a2, 'weight', 16.67, 'target', 2),
       jsonb_build_object('assignmentId', a3, 'weight', 16.67, 'target', 3),
       jsonb_build_object('kpiId', k4, 'weight', 16.67, 'target', 4),
       jsonb_build_object('kpiId', k5, 'weight', 16.67, 'target', 5),
       jsonb_build_object('kpiId', k6, 'weight', 16.66, 'target', 6)))
     ->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  a sixth measure was added. The ceiling is five.';
  end if;
  select count(*) into n from perf_assignment
   where cycle_id = v_cycle and person_id = p_rep and part_of_id is null
     and state <> 'WITHDRAWN';
  if n <> 3 then
    raise exception 'FAIL  the refusal changed the scorecard anyway: % rows', n;
  end if;
  raise notice 'PASS  a sixth measure is refused, and the refusal wrote nothing';

  -- Five is allowed.
  o := perf_kpis_set(p_boss, v_cycle, p_rep, jsonb_build_array(
         jsonb_build_object('assignmentId', a1, 'weight', 20, 'target', 1),
         jsonb_build_object('assignmentId', a2, 'weight', 20, 'target', 2),
         jsonb_build_object('assignmentId', a3, 'weight', 20, 'target', 3),
         jsonb_build_object('kpiId', k4, 'weight', 20, 'target', 4),
         jsonb_build_object('kpiId', k5, 'weight', 20, 'target', 5)));
  if o->>'error' is not null then
    raise exception 'FAIL  five measures were refused: %', o;
  end if;
  if coalesce((o->>'mayAdd')::boolean, true) then
    raise exception 'FAIL  the reply still offers to add a sixth: %', o;
  end if;
  raise notice 'PASS  five measures save, and the reply stops offering a sixth';

  -- --------------------------- and somebody already over it is not walled in
  --
  -- Nine people carry six measures today. A hard maximum would lock all nine
  -- out of their own scorecard until somebody deleted one -- and the person
  -- who would have to do that is the one locked out.
  insert into perf_assignment (cycle_id, person_id, kpi_id, name, unit,
                               target_value, weight_pct, set_by, state)
    values (v_cycle, p_rep, k6, 'MK six', 'COUNT', 6, 0.01, p_boss, 'ISSUED');
  o := perf_kpis_set(p_boss, v_cycle, p_rep, jsonb_build_array(
         jsonb_build_object('assignmentId', a1, 'weight', 20, 'target', 1),
         jsonb_build_object('assignmentId', a2, 'weight', 20, 'target', 2),
         jsonb_build_object('assignmentId', a3, 'weight', 20, 'target', 3),
         jsonb_build_object('kpiId', k4, 'weight', 20, 'target', 4),
         jsonb_build_object('kpiId', k5, 'weight', 10, 'target', 5),
         jsonb_build_object('kpiId', k6, 'weight', 10, 'target', 6)));
  if o->>'error' is not null then
    raise exception 'FAIL  somebody already carrying six was locked out of '
                    'their own scorecard: %', o;
  end if;
  raise notice 'PASS  a person already over the ceiling can still be edited';

  -- ----------------------------------- a filed measure cannot be taken off
  select id into a1 from perf_assignment
   where cycle_id = v_cycle and person_id = p_rep and kpi_id = k1 and part_of_id is null;
  o := perf_file(p_rep, a1, current_date, 4, 'a day''s work');
  if o->>'error' is not null then
    raise exception 'FAIL  a number could not be filed: %', o;
  end if;
  select jsonb_agg(jsonb_build_object('assignmentId', a.id, 'weight', 25,
                                      'target', coalesce(a.target_value,0)))
    into v_list from perf_assignment a
   where a.cycle_id = v_cycle and a.person_id = p_rep and a.part_of_id is null
     and a.state <> 'WITHDRAWN' and a.id <> a1 limit 4;
  if perf_kpis_set(p_boss, v_cycle, p_rep, v_list)->>'error'
     is distinct from 'invalid' then
    raise exception 'FAIL  a measure with a number filed against it was taken '
                    'off the scorecard';
  end if;
  raise notice 'PASS  a measure somebody has filed against cannot be removed';

  -- ------------------------------------------- the parent comes from its parts
  --
  -- This is the existing calculation and nothing here changes it: perf_value
  -- sums the children for a count, and target-weighted averages them for a
  -- level. The owner asked for sub-KPIs; the derivation was already right.
  select id into ap from perf_assignment
   where cycle_id = v_cycle and person_id = p_rep and kpi_id = k2 and part_of_id is null;
  o := perf_assign(p_boss, jsonb_build_object(
         'cycleId', v_cycle, 'personId', p_rep, 'name','Bank A',
         'unit','COUNT', 'target', 12, 'partOf', ap,
         'splitKind','OTHER', 'splitLabel','Bank A'));
  if o->>'error' is not null then raise exception 'FAIL  a sub-KPI could not be added: %', o; end if;
  o := perf_assign(p_boss, jsonb_build_object(
         'cycleId', v_cycle, 'personId', p_rep, 'name','Bank B',
         'unit','COUNT', 'target', 8, 'partOf', ap,
         'splitKind','OTHER', 'splitLabel','Bank B'));
  if o->>'error' is not null then raise exception 'FAIL  a second sub-KPI could not be added: %', o; end if;

  select id into c1 from perf_assignment where part_of_id = ap and name = 'Bank A';
  select id into c2 from perf_assignment where part_of_id = ap and name = 'Bank B';
  perform perf_file(p_rep, c1, current_date, 7, null);
  perform perf_file(p_rep, c2, current_date, 3, null);

  v := perf_value(ap);
  if v is distinct from 10 then
    raise exception 'FAIL  a counted parent did not sum its sub-KPIs: got %, '
                    'expected 10', v;
  end if;
  raise notice 'PASS  a counted parent is the sum of its sub-KPIs';

  -- And a filing straight at the parent is refused, which is why the screen
  -- greys it rather than inventing a rule of its own. perf_file answers in
  -- words the screen can show, so the screen does not have to guess either.
  o := perf_file(p_rep, ap, current_date, 99, null);
  if o->>'error' is distinct from 'has_parts' then
    raise exception 'FAIL  a number was filed against a parent measure: %', o;
  end if;
  if position('parts' in lower(coalesce(o->>'reason',''))) = 0 then
    raise exception 'FAIL  the refusal does not say why in words the screen '
                    'can show: %', o;
  end if;
  raise notice 'PASS  a filing against a parent is refused, so the screen greys it';

  -- --------------------------------- a level parent is weighted, not summed
  o := perf_kpis_set(p_boss, v_cycle, p_rep, jsonb_build_array(
         jsonb_build_object('assignmentId', a1, 'weight', 20, 'target', 1),
         jsonb_build_object('assignmentId', ap, 'weight', 20, 'target', 20),
         jsonb_build_object('assignmentId', a3, 'weight', 20, 'target', 3),
         jsonb_build_object('kpiId', k4, 'weight', 20, 'target', 4),
         jsonb_build_object('kpiId', kl, 'weight', 20, 'target', 90)));
  if o->>'error' is not null then
    raise exception 'FAIL  a level measure could not join the scorecard: %', o;
  end if;
  select id into a2 from perf_assignment
   where cycle_id = v_cycle and person_id = p_rep and kpi_id = kl and part_of_id is null;
  perform perf_assign(p_boss, jsonb_build_object(
    'cycleId', v_cycle, 'personId', p_rep, 'name','Branch X',
    'unit','% of target', 'target', 1, 'partOf', a2,
    'splitKind','OTHER', 'splitLabel','Branch X'));
  perform perf_assign(p_boss, jsonb_build_object(
    'cycleId', v_cycle, 'personId', p_rep, 'name','Branch Y',
    'unit','% of target', 'target', 3, 'partOf', a2,
    'splitKind','OTHER', 'splitLabel','Branch Y'));
  select id into c1 from perf_assignment where part_of_id = a2 and name = 'Branch X';
  select id into c2 from perf_assignment where part_of_id = a2 and name = 'Branch Y';
  perform perf_file(p_rep, c1, current_date, 100, null);
  perform perf_file(p_rep, c2, current_date, 60, null);

  -- (100*1 + 60*3) / (1+3) = 70
  v := perf_value(a2);
  if round(v, 2) <> 70 then
    raise exception 'FAIL  a level parent was not the target-weighted average '
                    'of its sub-KPIs: got %, expected 70', v;
  end if;
  raise notice 'PASS  a level parent is the target-weighted average of its sub-KPIs';

  -- ------------------------------------------ and the screen reads it all back
  o := perf_tree_for(p_boss, p_rep, v_cycle);
  if coalesce(jsonb_array_length(o->'measures'), 0) <> 5 then
    raise exception 'FAIL  the scorecard does not read back as five measures: %',
                    jsonb_array_length(o->'measures');
  end if;
  if not coalesce((o->>'maySet')::boolean, false) then
    raise exception 'FAIL  the manager is told they may not set';
  end if;
  if coalesce((perf_tree_for(p_rep, p_rep, v_cycle)->>'maySet')::boolean, false) then
    raise exception 'FAIL  a person is offered the controls for their own '
                    'measures, which every write behind them would refuse.';
  end if;
  raise notice 'PASS  one read gives the whole scorecard, and only the manager '
               'is offered the controls';

  raise notice '--- the monthly scorecard: every assertion passed ---';
end $t$;

rollback;
