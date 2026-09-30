-- What was filed becomes the month, and the month becomes the quarter (227)
--
-- Until 227 the two layers did not touch: a person filed a number every
-- working day, and then somebody typed the quarterly actual in by hand. The
-- same quantity entered twice, from two places, with nothing checking they
-- agreed.
--
-- The line this test defends is where facts stop and judgements start.
--
--   A quarterly ACTUAL is a fact -- what was filed, rolled up. It is
--   written.
--   A monthly SCORE is a judgement -- the Constitution's "partly or late"
--   is a person's call about a person. It is suggested and never written.
--
-- Getting that line in the wrong place is how a performance system starts
-- lying, so both halves are asserted: that the actual IS written, and that
-- the suggestion writes NOTHING.
--
-- Runs inside a transaction that is rolled back.

begin;

do $seed$
declare
  c_bm uuid; c_ex uuid; s_bm uuid; s_ex uuid;
  p_adm uuid; p_hr uuid; p_bm uuid; p_ex uuid;
  k_cases uuid; k_err uuid; cyc uuid; q date;
  a1 uuid; a2 uuid; d date; sheet uuid;
begin
  q := date_trunc('quarter', current_date)::date;

  insert into chair (code, title, level) values ('LK_BM','Link branch','branch') returning id into c_bm;
  insert into chair (code, title, level, parent_id) values ('LK_EX','Link exec','executive', c_bm) returning id into c_ex;
  insert into chair_seating (chair_id, scope_label) values (c_bm,'Pune') returning id into s_bm;
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (c_ex,'Pune', s_bm) returning id into s_ex;

  -- One that counts and one that is a ceiling, because they roll up over a
  -- quarter by different arithmetic and are scored the right way up by
  -- different arithmetic again.
  insert into kpi_definition (chair_id, name, unit, active, mandatory, position, cadence, accrual)
  values (c_ex, 'Cases completed', 'cases · LK1', true, true, 1, 'DAILY','ADDS')
  returning id into k_cases;
  insert into kpi_definition (chair_id, name, unit, active, mandatory, position, cadence, accrual)
  values (c_ex, 'Work returned for correction', '% of work returned · LK2', true, false, 2, 'DAILY','REPLACES')
  returning id into k_err;

  insert into person (full_name, work_email, app_role)
    values ('LK Admin','lk.admin@example.invalid','ADMIN') returning id into p_adm;
  insert into person (full_name, work_email, department, app_role)
    values ('LK HR','lk.hr@example.invalid','Human Resources','MANAGER') returning id into p_hr;
  insert into person (full_name, work_email) values ('LK Branch','lk.bm@example.invalid')
    returning id into p_bm;
  insert into person (full_name, work_email, manager_id)
    values ('LK Exec','lk.ex@example.invalid', p_bm) returning id into p_ex;

  insert into chair_holder (chair_id, seating_id, person_id, is_primary) values
    (c_bm, s_bm, p_bm, true), (c_ex, s_ex, p_ex, true);

  -- This month's cycle, inside the current quarter.
  insert into perf_cycle (period_start, assign_opens, assign_closes, entry_closes)
  values (date_trunc('month', current_date)::date,
          date_trunc('month', current_date)::date,
          date_trunc('month', current_date)::date + 9,
          (date_trunc('month', current_date) + interval '1 month - 1 day')::date)
  returning id into cyc;

  insert into perf_assignment (cycle_id, person_id, kpi_id, name, unit,
                               target_value, weight_pct, cadence, set_by, state)
  values (cyc, p_ex, k_cases, 'Cases completed', 'cases · LK1',
          100, 50, 'DAILY', p_adm, 'ISSUED') returning id into a1;
  insert into perf_assignment (cycle_id, person_id, kpi_id, name, unit,
                               target_value, weight_pct, cadence, set_by, state)
  values (cyc, p_ex, k_err, 'Work returned for correction', '% of work returned · LK2',
          5, 50, 'DAILY', p_adm, 'ISSUED') returning id into a2;

  -- Three working days of filing: 40 + 30 + 20 cases, and an error rate
  -- that finishes at 4 against a ceiling of 5.
  d := current_date;
  while not is_working_day(d, null) loop d := d - 1; end loop;
  perform perf_file(p_ex, a1, d,     40);
  perform perf_file(p_ex, a1, d - 1, 30);
  perform perf_file(p_ex, a1, d - 2, 20);
  perform perf_file(p_ex, a2, d,     4);

  -- A goal sheet for the same person, the same quarter, the same measures.
  sheet := (plb_sheet_issue(p_hr, p_ex, q, 60000,
             jsonb_build_array(
               jsonb_build_object('kpiId', k_cases, 'weight', 50, 'target', 300),
               jsonb_build_object('kpiId', k_err,   'weight', 50, 'target', 5)),
             false)->>'sheetId')::uuid;
  if sheet is null then
    raise exception 'the fixture could not issue a goal sheet: %',
      plb_sheet_issue(p_hr, p_ex, q, 60000, '[]'::jsonb, false);
  end if;
end $seed$;

do $t$
declare
  p_adm uuid; p_bm uuid; p_ex uuid; sheet uuid; q date;
  o jsonb; n int; v numeric; k_cases uuid; k_err uuid;
begin
  select id into p_adm from person where work_email='lk.admin@example.invalid';
  select id into p_bm  from person where work_email='lk.bm@example.invalid';
  select id into p_ex  from person where work_email='lk.ex@example.invalid';
  select id into k_cases from kpi_definition where unit like '%LK1%';
  select id into k_err   from kpi_definition where unit like '%LK2%';
  q := date_trunc('quarter', current_date)::date;
  select id into sheet from plb_goal_sheet where person_id = p_ex and quarter = q;

  -- ============================================ the quarter reads the filings
  if perf_quarter_value(p_ex, k_cases, q) = 90
    then raise notice 'PASS  a count rolls up across the quarter: 40 + 30 + 20 = 90';
    else raise exception 'FAIL  the quarter read % cases',
      coalesce(perf_quarter_value(p_ex, k_cases, q)::text,'nothing'); end if;

  if perf_quarter_value(p_ex, k_err, q) = 4
    then raise notice 'PASS  and a percentage is averaged, not summed';
    else raise exception 'FAIL  the error rate read %',
      coalesce(perf_quarter_value(p_ex, k_err, q)::text,'nothing'); end if;

  if perf_quarter_value(p_ex, gen_random_uuid(), q) is null
    then raise notice 'PASS  a measure with nothing filed reads nothing, not zero';
    else raise exception 'FAIL  an unfiled measure read a number'; end if;

  -- ------------------------------------------------------- who may pull it
  o := plb_actual_from_perf(p_ex, sheet);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  nobody pulls their own quarter''s actuals';
    else raise exception 'FAIL  a person pulled their own actuals'; end if;

  o := plb_actual_from_perf(p_bm, sheet);
  if (o->>'ok')::boolean and (o->>'set')::int = 2
    then raise notice 'PASS  their manager pulls both actuals in one go';
    else raise exception 'FAIL  the pull gave %', left(o::text, 160); end if;

  select actual_value into v from plb_goal_kpi where sheet_id = sheet and kpi_id = k_cases;
  if v = 90
    then raise notice 'PASS  and the sheet now carries what was actually filed, not a retyped guess';
    else raise exception 'FAIL  the sheet carries % against a filed 90', coalesce(v::text,'nothing'); end if;

  -- ------------------------------------ a blank stays blank, never a zero
  update plb_goal_kpi set actual_value = null where sheet_id = sheet and kpi_id = k_err;
  delete from perf_entry e using perf_assignment a
   where e.assignment_id = a.id and a.person_id = p_ex and a.kpi_id = k_err;
  o := plb_actual_from_perf(p_bm, sheet);
  select actual_value into v from plb_goal_kpi where sheet_id = sheet and kpi_id = k_err;
  if v is null and (o->>'blank')::int = 1
    then raise notice 'PASS  a measure nobody filed is left blank rather than scored as zero';
    else raise exception 'FAIL  an unfiled measure was written as %', coalesce(v::text,'null'); end if;

  -- ======================================= the month suggests and writes nothing
  o := plb_month_suggest(p_bm, sheet, current_date);
  if (o->>'suggested') is not null
    then raise notice 'PASS  the month suggests a score out of ten (%)', o->>'suggested';
    else raise exception 'FAIL  the month suggested nothing: %', left(o::text,180); end if;

  select count(*) into n from jsonb_array_elements(o->'measures') m
   where (m->>'counted')::boolean and (m->>'why') is not null;
  if n >= 1
    then raise notice 'PASS  and every measure it counted says why it scored what it did';
    else raise exception 'FAIL  the suggestion showed no working'; end if;

  if not exists (select 1 from plb_month_score
                  where sheet_id = sheet and month = date_trunc('month', current_date)::date
                    and kpi_points is not null)
    then raise notice 'PASS  and it wrote nothing -- a score is a judgement, not a calculation';
    else raise exception 'FAIL  the suggestion wrote a score into plb_month_score'; end if;

  -- ------------------------------ the ceiling is scored the right way up
  -- 90 cases against a target of 100 is 90% -- part of the way, one point.
  select (m->>'points')::numeric into v
    from jsonb_array_elements(o->'measures') m where m->>'name' = 'Cases completed';
  if v = 1
    then raise notice 'PASS  ninety against a hundred is part of the way -- one point, not two';
    else raise exception 'FAIL  90 of 100 scored % points', coalesce(v::text,'nothing'); end if;

  -- ---------------------------------------------- it obeys the line too
  o := plb_month_suggest(p_ex, sheet, current_date);
  if (o->>'suggested') is not null and not (o->>'maySet')::boolean
    then raise notice 'PASS  the person can read their own month and cannot score it';
    else raise exception 'FAIL  maySet came back % for the person themselves', o->>'maySet'; end if;

  -- ----------------------------------------------------- and the freeze
  insert into plb_result (sheet_id, data_frozen_at) values (sheet, now())
    on conflict (sheet_id) do update set data_frozen_at = now();
  o := plb_actual_from_perf(p_bm, sheet);
  if o->>'error' = 'frozen'
    then raise notice 'PASS  a frozen quarter is frozen against arithmetic, not only against typing';
    else raise exception 'FAIL  a frozen quarter accepted a pull'; end if;

  raise notice '--- the day, the month and the quarter: every assertion passed ---';
end $t$;

rollback;
