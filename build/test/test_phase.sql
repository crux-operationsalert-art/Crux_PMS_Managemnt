-- The quarter is the promise and the months are its phasing (232)
--
-- The fault this closes: a target was stored twice, once monthly and once
-- quarterly, and nothing compared them. These assertions pin down that
-- they now hold ONE number -- and that the agreement is what gives way
-- last, never first.
--
-- Runs inside a transaction that is rolled back.

begin;

do $seed$
declare
  c_br uuid; c_ex uuid; s_br uuid; s_ex uuid;
  p_bm uuid; p_ex uuid; p_hr uuid;
  k_cases uuid; k_qual uuid; q date; cyc1 uuid; cyc2 uuid;
begin
  q := date_trunc('quarter', current_date)::date;

  insert into chair (code, title, level) values ('PH_B','Phase branch','branch')
    returning id into c_br;
  insert into chair (code, title, level, parent_id)
    values ('PH_E','Phase exec','executive', c_br) returning id into c_ex;
  insert into chair_seating (chair_id, scope_label) values (c_br,'Pune')
    returning id into s_br;
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (c_ex,'Pune', s_br) returning id into s_ex;

  insert into person (full_name, work_email, department, app_role)
    values ('PH HR','ph.hr@example.invalid','Human Resources','MANAGER')
    returning id into p_hr;
  insert into person (full_name, work_email) values ('PH Branch','ph.bm@example.invalid')
    returning id into p_bm;
  insert into person (full_name, work_email, manager_id)
    values ('PH Exec','ph.ex@example.invalid', p_bm) returning id into p_ex;
  insert into chair_holder (chair_id, seating_id, person_id, is_primary)
    values (c_br, s_br, p_bm, true), (c_ex, s_ex, p_ex, true);

  insert into kpi_definition (chair_id, name, unit, active, mandatory, position,
                              cadence, accrual)
  values (c_ex,'Cases completed','cases · PH1', true, true, 1, 'DAILY','ADDS')
  returning id into k_cases;
  insert into kpi_definition (chair_id, name, unit, active, mandatory, position,
                              cadence, accrual)
  values (c_ex,'Quality score','% quality score · PH2', true, false, 2,
          'DAILY','REPLACES') returning id into k_qual;

  -- Two months inside the SAME quarter, which is what makes phasing
  -- across months testable at all.
  insert into perf_cycle (period_start, assign_opens, assign_closes, entry_closes)
  values (q, q, q + 9, (q + interval '1 month - 1 day')::date)
  on conflict (period_start, period_kind) do update
     set assign_opens = excluded.assign_opens,
         assign_closes = excluded.assign_closes,
         entry_closes = excluded.entry_closes
  returning id into cyc1;
  insert into perf_cycle (period_start, assign_opens, assign_closes, entry_closes)
  values ((q + interval '1 month')::date, (q + interval '1 month')::date,
          (q + interval '1 month')::date + 9,
          (q + interval '2 month - 1 day')::date)
  on conflict (period_start, period_kind) do update
     set assign_opens = excluded.assign_opens,
         assign_closes = excluded.assign_closes,
         entry_closes = excluded.entry_closes
  returning id into cyc2;

  -- Monthly targets that DISAGREE with the quarter about to be set: this
  -- is the state the fault produced.
  insert into perf_assignment (cycle_id, person_id, kpi_id, name, unit,
                               target_value, weight_pct, cadence, set_by,
                               state, target_source)
  values (cyc1, p_ex, k_cases,'Cases completed','cases · PH1', 40, 50,'DAILY',
          p_bm,'ISSUED','SEEDED'),
         (cyc2, p_ex, k_cases,'Cases completed','cases · PH1', 40, 50,'DAILY',
          p_bm,'ISSUED','SEEDED'),
         (cyc1, p_ex, k_qual,'Quality score','% quality score · PH2', 90, 50,
          'DAILY', p_bm,'ISSUED','SEEDED'),
         (cyc2, p_ex, k_qual,'Quality score','% quality score · PH2', 90, 50,
          'DAILY', p_bm,'ISSUED','SEEDED');
end $seed$;

do $t$
declare
  p_bm uuid; p_ex uuid; p_hr uuid; k_cases uuid; k_qual uuid;
  q date; sheet uuid; o jsonb; v numeric; n int;
begin
  select id into p_bm from person where work_email='ph.bm@example.invalid';
  select id into p_ex from person where work_email='ph.ex@example.invalid';
  select id into p_hr from person where work_email='ph.hr@example.invalid';
  select id into k_cases from kpi_definition where unit like '%PH1%';
  select id into k_qual  from kpi_definition where unit like '%PH2%';
  q := date_trunc('quarter', current_date)::date;

  -- ============================== what the months say, on their own
  if plb_quarter_from_months(p_ex, k_cases, q) = 80
    then raise notice 'PASS  two months of 40 cases make a quarter of 80 -- a count adds';
    else raise exception 'FAIL  the months read % for a count',
      coalesce(plb_quarter_from_months(p_ex, k_cases, q)::text,'nothing'); end if;

  if plb_quarter_from_months(p_ex, k_qual, q) = 90
    then raise notice 'PASS  and two months at 90%% make a quarter of 90%%, not 180%%';
    else raise exception 'FAIL  the months read % for a level',
      coalesce(plb_quarter_from_months(p_ex, k_qual, q)::text,'nothing'); end if;

  -- ================ a first sheet is read off the months, not retyped
  o := plb_sheet_from_perf(p_hr, p_ex, q, 50000);
  if (o->>'ok')::boolean and (o->>'fromMonths')::int = 2
    then raise notice 'PASS  a first goal sheet takes its targets from the months that exist';
    else raise exception 'FAIL  the sheet was not seeded from the months: %',
      left(o::text,200); end if;
  sheet := (o->>'sheetId')::uuid;

  select target_value into v from plb_goal_kpi
   where sheet_id = sheet and kpi_id = k_cases;
  if v = 80
    then raise notice 'PASS  so the quarter starts in agreement with the months (80)';
    else raise exception 'FAIL  the quarterly target was %',
      coalesce(v::text,'nothing'); end if;

  o := plb_target_agreement(p_bm, sheet);
  if (o->>'disagree')::int = 0
    then raise notice 'PASS  and the agreement report finds nothing to report';
    else raise exception 'FAIL  a freshly seeded sheet already disagreed: %',
      left(o::text,220); end if;

  -- ====================== now break it the way the fault used to
  update plb_goal_kpi set target_value = 300
   where sheet_id = sheet and kpi_id = k_cases;

  o := plb_target_agreement(p_bm, sheet);
  if (o->>'disagree')::int = 1
    then raise notice 'PASS  a quarter of 300 against months adding to 80 is reported, not ignored';
    else raise exception 'FAIL  the disagreement was missed: %', left(o::text,220); end if;

  select count(*) into n from jsonb_array_elements(o->'measures') m
   where (m->>'agrees') = 'false' and (m->>'why') like '%add to 80%';
  if n = 1
    then raise notice 'PASS  and it says in words which number is fighting which';
    else raise exception 'FAIL  the report did not name the disagreement'; end if;

  -- ============================================ phasing settles it
  o := plb_phase_targets(p_bm, sheet);
  if (o->>'ok')::boolean and (o->>'months')::int = 2
    then raise notice 'PASS  phasing spreads the quarter across the months that are open';
    else raise exception 'FAIL  phasing failed: %', left(o::text,220); end if;

  select count(*) into n from perf_assignment
   where person_id = p_ex and kpi_id = k_cases and target_value = 150;
  if n = 2
    then raise notice 'PASS  300 cases over two open months is 150 each -- a count divides';
    else raise exception 'FAIL  % months got 150', n; end if;

  select count(*) into n from perf_assignment
   where person_id = p_ex and kpi_id = k_qual and target_value = 90;
  if n = 2
    then raise notice 'PASS  and 90%% stays 90%% in each month -- a level is copied';
    else raise exception 'FAIL  the percentage was divided'; end if;

  select m1_share into v from plb_goal_kpi where sheet_id = sheet and kpi_id = k_cases;
  if v = 150
    then raise notice 'PASS  the sheet records the monthly share it phased (m1_share)';
    else raise exception 'FAIL  m1_share was %', coalesce(v::text,'nothing'); end if;

  o := plb_target_agreement(p_bm, sheet);
  if (o->>'disagree')::int = 0
    then raise notice 'PASS  and afterwards the two stores hold one number, not two';
    else raise exception 'FAIL  they still disagree after phasing: %',
      left(o::text,220); end if;

  -- =================== an agreed number is what gives way last
  -- The FIRST month of the quarter, chosen by its date. plb_quarter_cycles
  -- returns ids, and an id has no order worth having.
  update perf_assignment set target_value = 200, target_source = 'MANUAL'
   where person_id = p_ex and kpi_id = k_cases
     and cycle_id = (select c.id from perf_cycle c
                      where c.id in (select plb_quarter_cycles(q))
                      order by c.period_start limit 1);

  o := plb_phase_targets(p_bm, sheet);
  if (o->>'leftPinned')::int = 1
    then raise notice 'PASS  a monthly target agreed by hand is left alone by a re-phase';
    else raise exception 'FAIL  phasing overwrote an agreed target: %',
      left(o::text,220); end if;

  if (select target_value from perf_assignment
       where person_id = p_ex and kpi_id = k_cases
         and cycle_id = (select c.id from perf_cycle c
                          where c.id in (select plb_quarter_cycles(q))
                          order by c.period_start limit 1)) = 200
    then raise notice 'PASS  and it still reads what the person agreed, not what the sum wanted';
    else raise exception 'FAIL  the agreed target was overwritten'; end if;

  -- ========================================== and who may do it
  o := plb_phase_targets(p_ex, sheet);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  a person does not phase their own quarter into their own months';
    else raise exception 'FAIL  somebody phased their own targets'; end if;

  o := plb_sheet_from_perf(p_ex, p_ex, q, 1000);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  nor issues their own goal sheet';
    else raise exception 'FAIL  somebody issued their own sheet'; end if;

  raise notice '--- the quarter and its months: every assertion passed ---';
end $t$;

rollback;
