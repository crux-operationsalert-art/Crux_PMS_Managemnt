-- One target, several clients (230)
--
-- The point of these assertions is that a split uses the CASCADE's
-- arithmetic, not a second opinion about it: a count divides, a percentage
-- is copied. Getting that backwards would tell somebody their quality
-- target was 31.67% when it is 95%, and they would be right to conclude
-- the tool was broken.
--
-- They also pin down the thing that cannot be undone: a share that has
-- been filed against must never be quietly deleted.
--
-- Runs inside a transaction that is rolled back.

begin;

do $seed$
declare
  c_br uuid; c_ex uuid; s_br uuid; s_ex uuid;
  p_bm uuid; p_ex uuid; cyc uuid;
  k_coll uuid; k_qual uuid; cl_a uuid; cl_b uuid; cl_c uuid;
begin
  insert into chair (code, title, level) values ('SP_B','Split branch','branch')
    returning id into c_br;
  insert into chair (code, title, level, parent_id)
    values ('SP_E','Split exec','executive', c_br) returning id into c_ex;
  insert into chair_seating (chair_id, scope_label) values (c_br,'Pune')
    returning id into s_br;
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (c_ex,'Pune', s_br) returning id into s_ex;

  insert into person (full_name, work_email) values ('SP Branch','sp.bm@example.invalid')
    returning id into p_bm;
  insert into person (full_name, work_email, manager_id)
    values ('SP Exec','sp.ex@example.invalid', p_bm) returning id into p_ex;
  insert into chair_holder (chair_id, seating_id, person_id, is_primary)
    values (c_br, s_br, p_bm, true), (c_ex, s_ex, p_ex, true);

  insert into client (code, name, status) values ('SPA','Split Bank A','ACTIVE')
    returning id into cl_a;
  insert into client (code, name, status) values ('SPB','Split Bank B','ACTIVE')
    returning id into cl_b;
  insert into client (code, name, status) values ('SPC','Split Bank C','ACTIVE')
    returning id into cl_c;

  -- A rupee figure, which divides, and a percentage, which does not.
  insert into kpi_definition (chair_id, name, unit, active, mandatory, position,
                              cadence, accrual)
  values (c_ex,'Collection against target','INR collected · SP1', true, true, 1,
          'DAILY','ADDS') returning id into k_coll;
  insert into kpi_definition (chair_id, name, unit, active, mandatory, position,
                              cadence, accrual)
  values (c_ex,'Quality score','% quality score · SP2', true, false, 2,
          'DAILY','REPLACES') returning id into k_qual;

  insert into perf_cycle (period_start, assign_opens, assign_closes, entry_closes)
  values (date_trunc('month', current_date)::date,
          date_trunc('month', current_date)::date,
          date_trunc('month', current_date)::date + 9,
          (date_trunc('month', current_date) + interval '1 month - 1 day')::date)
  on conflict (period_start, period_kind) do update
     set assign_opens = excluded.assign_opens,
         assign_closes = excluded.assign_closes,
         entry_closes = excluded.entry_closes
  returning id into cyc;

  insert into perf_assignment (cycle_id, person_id, kpi_id, name, unit,
                               target_value, weight_pct, cadence, set_by, state)
  values (cyc, p_ex, k_coll, 'Collection against target','INR collected · SP1',
          1000000, 50, 'DAILY', p_bm, 'ISSUED');
  insert into perf_assignment (cycle_id, person_id, kpi_id, name, unit,
                               target_value, weight_pct, cadence, set_by, state)
  values (cyc, p_ex, k_qual, 'Quality score','% quality score · SP2',
          95, 50, 'DAILY', p_bm, 'ISSUED');
end $seed$;

do $t$
declare
  p_bm uuid; p_ex uuid; a_coll uuid; a_qual uuid;
  cl_a uuid; cl_b uuid; cl_c uuid; o jsonb; n int; v numeric; d date;
begin
  select id into p_bm from person where work_email='sp.bm@example.invalid';
  select id into p_ex from person where work_email='sp.ex@example.invalid';
  select id into a_coll from perf_assignment where person_id=p_ex and unit like '%SP1%';
  select id into a_qual from perf_assignment where person_id=p_ex and unit like '%SP2%';
  select id into cl_a from client where code='SPA';
  select id into cl_b from client where code='SPB';
  select id into cl_c from client where code='SPC';

  -- ================================================== a count divides
  o := perf_split_set(p_bm, a_coll, jsonb_build_object('kind','CLIENT','parts',
        jsonb_build_array(
          jsonb_build_object('ref', cl_a, 'target', 500000),
          jsonb_build_object('ref', cl_b, 'target', 300000),
          jsonb_build_object('ref', cl_c))));
  if (o->>'ok')::boolean and (o->>'divides')::boolean
    then raise notice 'PASS  ten lakh splits across three banks, and it says it divided';
    else raise exception 'FAIL  the split was refused: %', left(o::text,200); end if;

  select target_value into v from perf_assignment
   where part_of_id = a_coll and split_ref = cl_c;
  if v = 200000
    then raise notice 'PASS  the bank left blank takes what is left -- 2,00,000, not a third';
    else raise exception 'FAIL  the blank share got %', coalesce(v::text,'nothing'); end if;

  select count(*) into n from perf_assignment where part_of_id = a_coll;
  if n = 3
    then raise notice 'PASS  three shares exist, one per bank';
    else raise exception 'FAIL  % shares were made', n; end if;

  if (select sum(target_value) from perf_assignment where part_of_id = a_coll) = 1000000
    then raise notice 'PASS  and they add back to the number being divided';
    else raise exception 'FAIL  the shares do not add to the target'; end if;

  -- ------------------------------------------- what was typed is pinned
  if (select target_source from perf_assignment
       where part_of_id = a_coll and split_ref = cl_a) = 'MANUAL'
     and (select target_source from perf_assignment
           where part_of_id = a_coll and split_ref = cl_c) = 'SHARED'
    then raise notice 'PASS  a share typed by hand is pinned, a share worked out is not';
    else raise exception 'FAIL  the shares are not marked apart'; end if;

  -- ---------------------------------------------- more than there is
  o := perf_split_set(p_bm, a_coll, jsonb_build_object('kind','CLIENT','parts',
        jsonb_build_array(jsonb_build_object('ref', cl_a, 'target', 900000),
                          jsonb_build_object('ref', cl_b, 'target', 900000))));
  if o->>'error' = 'over_the_target'
    then raise notice 'PASS  shares that add to more than the target are refused';
    else raise exception 'FAIL  the shares were allowed to exceed the target'; end if;

  -- ============================================ a percentage is copied
  o := perf_split_set(p_bm, a_qual, jsonb_build_object('kind','CLIENT','parts',
        jsonb_build_array(jsonb_build_object('ref', cl_a),
                          jsonb_build_object('ref', cl_b),
                          jsonb_build_object('ref', cl_c))));
  if (o->>'ok')::boolean and not (o->>'divides')::boolean
    then raise notice 'PASS  a percentage says plainly that it does not divide';
    else raise exception 'FAIL  %', left(o::text,200); end if;

  if (select count(*) from perf_assignment
       where part_of_id = a_qual and target_value = 95) = 3
    then raise notice 'PASS  95%% across three banks is 95%% each, not 31.67%% each';
    else raise exception 'FAIL  the percentage was divided'; end if;

  -- ====================================== the parts are what gets filed
  d := current_date;
  while not is_working_day(d, null) loop d := d - 1; end loop;

  select count(*) into n from jsonb_array_elements(perf_due(p_ex, d)) x
   where (x->>'split') is not null;
  if n = 6
    then raise notice 'PASS  the six shares are what the person is asked for today';
    else raise exception 'FAIL  % split rows were due', n; end if;

  select count(*) into n from jsonb_array_elements(perf_due(p_ex, d)) x
   where (x->>'assignmentId')::uuid in (a_coll, a_qual);
  if n = 0
    then raise notice 'PASS  and the measure they came from is not asked for as well';
    else raise exception 'FAIL  a split parent was still due, so a number filed '
      'against it would never have counted'; end if;

  -- -------------------------------------- and they add back up the tree
  perform perf_file(p_ex, (select id from perf_assignment
                            where part_of_id=a_coll and split_ref=cl_a), d, 400000);
  perform perf_file(p_ex, (select id from perf_assignment
                            where part_of_id=a_coll and split_ref=cl_b), d, 100000);
  if perf_value(a_coll) = 500000
    then raise notice 'PASS  what is filed per bank adds into the measure itself';
    else raise exception 'FAIL  the parent read % after two banks filed',
      coalesce(perf_value(a_coll)::text,'nothing'); end if;

  -- ============================ a filed share is never quietly removed
  o := perf_split_set(p_bm, a_coll, jsonb_build_object('kind','CLIENT','parts',
        jsonb_build_array(jsonb_build_object('ref', cl_c, 'target', 1000000))));
  if o->>'error' = 'has_filings'
    then raise notice 'PASS  dropping a bank that has filed numbers is refused, and names it';
    else raise exception 'FAIL  filed numbers were about to be deleted: %',
      left(o::text,200); end if;

  if (select count(*) from perf_assignment where part_of_id = a_coll) = 3
    then raise notice 'PASS  and the refusal changed nothing';
    else raise exception 'FAIL  a refused split still wrote'; end if;

  -- ======================================================= who may split
  o := perf_split_set(p_ex, a_coll, jsonb_build_object('kind','CLIENT','parts',
        jsonb_build_array(jsonb_build_object('ref', cl_a, 'target', 1000000))));
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  a person does not split their own target';
    else raise exception 'FAIL  somebody split their own target'; end if;

  -- --------------------------------------------- no split of a split
  o := perf_split_set(p_bm, (select id from perf_assignment
                              where part_of_id=a_coll limit 1),
        jsonb_build_object('kind','CLIENT','parts',
          jsonb_build_array(jsonb_build_object('ref', cl_b))));
  if o->>'error' = 'already_a_part'
    then raise notice 'PASS  a share cannot itself be split again';
    else raise exception 'FAIL  a split was nested'; end if;

  -- ------------------------------------------------------ and reading it
  o := perf_split_of(p_bm, a_coll);
  if jsonb_array_length(o->'parts') = 3 and (o->>'maySet')::boolean
    then raise notice 'PASS  the manager reads the split back with what each bank has reached';
    else raise exception 'FAIL  the split read %', left(o::text,200); end if;

  o := perf_split_of(p_ex, a_coll);
  if jsonb_array_length(o->'parts') = 3 and not (o->>'maySet')::boolean
    then raise notice 'PASS  and the person sees their own split without being able to set it';
    else raise exception 'FAIL  the person''s read of their own split was wrong'; end if;

  raise notice '--- one target, several clients: every assertion passed ---';
end $t$;

rollback;
