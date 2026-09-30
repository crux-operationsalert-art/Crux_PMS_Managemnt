-- The number climbs, and the target comes down (migrations 222, 223, 224)
--
-- Asked for: "the urgent flow is from the bottom of the pyramid to the top
-- at Org end, which is everydays productivity or KPI numbers updated and
-- those numbers summing up and also vice versa, but only for targets, if my
-- manager updates my target it auto distributes evenly to all in my team
-- unless I edit and change it manually."
--
-- Four executives under a team leader under a branch manager, which is the
-- real shape. Two measures: one that counts, one that is a percentage,
-- because those two go up and come down by different arithmetic and getting
-- them the same way round is the whole difficulty.
--
--   cases   SUM   sums going up,   divides coming down
--   quality LEVEL averages going up, copies coming down
--
-- Runs inside a transaction that is rolled back.

begin;

do $seed$
declare
  c_bm uuid; c_tl uuid; c_ex uuid;
  s_bm uuid; s_tl uuid; s_ex uuid;
  p_adm uuid; p_bm uuid; p_tl uuid; p_e1 uuid; p_e2 uuid; p_e3 uuid; p_e4 uuid;
  cyc uuid;
begin
  insert into chair (code, title, level) values ('FL_BM','Flow branch','branch')      returning id into c_bm;
  insert into chair (code, title, level, parent_id) values ('FL_TL','Flow lead','executive', c_bm) returning id into c_tl;
  insert into chair (code, title, level, parent_id) values ('FL_EX','Flow exec','executive', c_tl) returning id into c_ex;

  insert into chair_seating (chair_id, scope_label) values (c_bm, 'Pune') returning id into s_bm;
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (c_tl, 'Pune', s_bm) returning id into s_tl;
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (c_ex, 'Pune', s_tl) returning id into s_ex;

  -- The registry's own shape: a name per chair, the family coded in the
  -- unit after a middle dot. No two levels share a name; the family is the
  -- only thing that links them.
  insert into kpi_definition (chair_id, name, unit, active, mandatory, position, cadence, accrual)
  values
    (c_ex, 'Cases completed against target', 'cases · EX1',            true, true,  1, 'MONTHLY','ADDS'),
    (c_ex, 'Work returned for correction',   '% of work returned · EX3',true, false, 2, 'MONTHLY','REPLACES'),
    (c_tl, 'Daily target achievement',       'cases · D3',             true, true,  1, 'MONTHLY','ADDS'),
    (c_tl, 'Error rate',                     '% of work returned · D21',true, false, 2, 'MONTHLY','REPLACES'),
    (c_bm, 'Cases completed within TAT',     'cases · D3',             true, true,  1, 'MONTHLY','ADDS'),
    (c_bm, 'Branch quality score',           '% score · D21',          true, false, 2, 'MONTHLY','REPLACES'),
    -- Same family, same direction, DIFFERENT kind. The registry really does
    -- this: "% of cases within TAT" at a branch and "branches operational
    -- against plan" at the top are both D3-shaped and one is a percentage
    -- while the other is a count. Nothing may climb between them.
    (c_bm, 'Branches operational against plan','count against plan · D8',true, false, 3, 'MONTHLY','ADDS');

  insert into person (full_name, work_email, app_role)
    values ('FL Admin','fl.admin@example.invalid','ADMIN') returning id into p_adm;
  insert into person (full_name, work_email) values ('FL Branch','fl.bm@example.invalid')
    returning id into p_bm;
  insert into person (full_name, work_email, manager_id)
    values ('FL Lead','fl.tl@example.invalid', p_bm) returning id into p_tl;
  insert into person (full_name, work_email, manager_id)
    values ('FL Exec 1','fl.e1@example.invalid', p_tl) returning id into p_e1;
  insert into person (full_name, work_email, manager_id)
    values ('FL Exec 2','fl.e2@example.invalid', p_tl) returning id into p_e2;
  insert into person (full_name, work_email, manager_id)
    values ('FL Exec 3','fl.e3@example.invalid', p_tl) returning id into p_e3;
  insert into person (full_name, work_email, manager_id)
    values ('FL Exec 4','fl.e4@example.invalid', p_tl) returning id into p_e4;

  insert into chair_holder (chair_id, seating_id, person_id, is_primary) values
    (c_bm, s_bm, p_bm, true), (c_tl, s_tl, p_tl, true),
    (c_ex, s_ex, p_e1, true), (c_ex, s_ex, p_e2, true),
    (c_ex, s_ex, p_e3, true), (c_ex, s_ex, p_e4, true);

  insert into perf_cycle (period_start, assign_opens, assign_closes, entry_closes)
  values (date_trunc('month', current_date)::date,
          date_trunc('month', current_date)::date,
          date_trunc('month', current_date)::date + 9,
          (date_trunc('month', current_date) + interval '1 month - 1 day')::date)
  returning id into cyc;

  perform perf_seed_from_registry(p_adm, cyc);
end $seed$;

do $t$
declare
  p_adm uuid; p_bm uuid; p_tl uuid; p_e1 uuid; p_e2 uuid; p_e3 uuid; p_e4 uuid;
  cyc uuid; o jsonb; n int; v numeric; v2 numeric; a_bm uuid; a_tl uuid;
  a_e1 uuid; a_e2 uuid; a_e3 uuid; a_e4 uuid; q_bm uuid; q_e1 uuid; d date;
begin
  select id into p_adm from person where work_email='fl.admin@example.invalid';
  select id into p_bm  from person where work_email='fl.bm@example.invalid';
  select id into p_tl  from person where work_email='fl.tl@example.invalid';
  select id into p_e1  from person where work_email='fl.e1@example.invalid';
  select id into p_e2  from person where work_email='fl.e2@example.invalid';
  select id into p_e3  from person where work_email='fl.e3@example.invalid';
  select id into p_e4  from person where work_email='fl.e4@example.invalid';
  select id into cyc   from perf_cycle where period_start = date_trunc('month', current_date)::date;

  -- ============================================================ the link
  o := perf_relink(p_tl, cyc);
  if o->>'error' = 'not_admin'
    then raise notice 'PASS  rebuilding the roll-up is not a manager''s to do';
    else raise exception 'FAIL  a manager rebuilt the roll-up'; end if;

  o := perf_relink(p_adm, cyc);

  select a.id into a_e1 from perf_assignment a
   where a.person_id = p_e1 and a.cycle_id = cyc and a.unit like '%EX1%';
  select a.id into a_e2 from perf_assignment a
   where a.person_id = p_e2 and a.cycle_id = cyc and a.unit like '%EX1%';
  select a.id into a_e3 from perf_assignment a
   where a.person_id = p_e3 and a.cycle_id = cyc and a.unit like '%EX1%';
  select a.id into a_e4 from perf_assignment a
   where a.person_id = p_e4 and a.cycle_id = cyc and a.unit like '%EX1%';
  select a.id into a_tl from perf_assignment a
   where a.person_id = p_tl and a.cycle_id = cyc and a.unit like '%D3%';
  select a.id into a_bm from perf_assignment a
   where a.person_id = p_bm and a.cycle_id = cyc and a.unit like '%D3%';
  select a.id into q_e1 from perf_assignment a
   where a.person_id = p_e1 and a.cycle_id = cyc and a.unit like '%EX3%';
  select a.id into q_bm from perf_assignment a
   where a.person_id = p_bm and a.cycle_id = cyc and a.unit like '%D21%';

  if (select rolls_into_id from perf_assignment where id = a_e1) = a_tl
    then raise notice 'PASS  an executive''s EX1 climbs into the lead''s D3, though they share no name';
    else raise exception 'FAIL  EX1 climbs into %',
      coalesce((select rolls_into_id from perf_assignment where id = a_e1)::text,'nothing'); end if;

  if (select rolls_into_id from perf_assignment where id = a_tl) = a_bm
    then raise notice 'PASS  and the lead''s D3 climbs into the branch''s D3, same code, two levels';
    else raise exception 'FAIL  D3 climbs into %',
      coalesce((select rolls_into_id from perf_assignment where id = a_tl)::text,'nothing'); end if;

  if (select rolls_into_id from perf_assignment where id = q_e1)
   = (select id from perf_assignment where person_id = p_tl and cycle_id = cyc and unit like '%D21%')
    then raise notice 'PASS  the quality measure climbs its own family, not the other one';
    else raise exception 'FAIL  EX3 climbed somewhere else'; end if;

  if (select rolls_into_id from perf_assignment where id = a_bm) is null
    then raise notice 'PASS  the top of a chain climbs nowhere, which is where a number stops';
    else raise exception 'FAIL  the top of the chain climbs somewhere'; end if;

  -- --------------------------------------- a chain stops at a change of kind
  -- The branch's own D3 is a count of cases. Its D8 is a count of
  -- branches. The lead's D3 is a count too, so THAT climbs; but a
  -- percentage never climbs into a count, whatever the family says.
  if (select count(*) from perf_assignment a
       where a.cycle_id = cyc and a.rolls_into_id =
             (select id from perf_assignment where person_id = p_bm
               and cycle_id = cyc and unit like '%D8%')) = 0
    then raise notice 'PASS  nothing climbs into the branches count -- a percentage is not a count';
    else raise exception 'FAIL  % measures climbed into a count of branches',
      (select count(*) from perf_assignment a where a.cycle_id = cyc and a.rolls_into_id =
        (select id from perf_assignment where person_id = p_bm and cycle_id = cyc and unit like '%D8%')); end if;

  -- ========================================================= the target
  o := perf_seed_targets(p_adm, cyc);

  if (o->>'madeDaily')::int >= 12
    then raise notice 'PASS  every measure is now due daily, not once a month (%)', o->>'madeDaily';
    else raise exception 'FAIL  only % became daily', o->>'madeDaily'; end if;

  select target_value into v from perf_assignment where id = a_bm;
  if v is not null and v > 0
    then raise notice 'PASS  a manager opens the screen to a starting number, not a blank';
    else raise exception 'FAIL  the branch target is %', coalesce(v::text,'blank'); end if;

  if (select target_source from perf_assignment where id = a_bm) = 'SEEDED'
    then raise notice 'PASS  and it says on its face that nobody has agreed it yet';
    else raise exception 'FAIL  the seeded target claims to be %',
      (select target_source from perf_assignment where id = a_bm); end if;

  -- a ceiling measure must not be seeded as a floor
  select target_value into v from perf_assignment where id = q_e1;
  if v <= 10
    then raise notice 'PASS  "work returned" is seeded as a ceiling (%), not a 90%% goal', v;
    else raise exception 'FAIL  a ceiling measure was seeded at %', v; end if;

  -- ================================================ the target comes down
  -- Nobody sets their own. At the top of a chain the number comes from
  -- outside the line -- the board, through an administrator -- which is
  -- the same exception perf_rel has carried since migration 218.
  o := perf_target_set(p_bm, a_bm, 600);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  nobody sets their own target, not even at the top of the chain';
    else raise exception 'FAIL  a person set their own target'; end if;

  o := perf_target_set(p_adm, a_bm, 600);
  if (o->>'ok')::boolean
    then raise notice 'PASS  an administrator sets the top of the chain, and it starts there';
    else raise exception 'FAIL  setting a target gave %', left(o::text,140); end if;

  select target_value into v from perf_assignment where id = a_tl;
  if v = 600
    then raise notice 'PASS  one report below takes the whole of it -- one team, one share';
    else raise exception 'FAIL  the lead got % of 600', coalesce(v::text,'nothing'); end if;

  select target_value into v from perf_assignment where id = a_e1;
  if v = 150
    then raise notice 'PASS  and four executives under them get 150 each, evenly';
    else raise exception 'FAIL  an executive got % of 600 split four ways', coalesce(v::text,'nothing'); end if;

  select count(*) into n from perf_assignment
   where id in (a_e1,a_e2,a_e3,a_e4) and target_value = 150 and target_source = 'SHARED';
  if n = 4 then raise notice 'PASS  all four, and each marked as a share rather than agreed';
           else raise exception 'FAIL  only % of four got an even share', n; end if;

  -- ------------------------------------------- a chain stops at a turn
  -- The registry gives D21 to two measures facing opposite ways: "Error
  -- rate" at Team Leader, which you want near zero, and "Branch quality
  -- score" at Branch Manager, which you want near a hundred. Nothing
  -- climbs from one into the other, and that is the point.
  if (select count(*) from perf_assignment where rolls_into_id = q_bm) = 0
    then raise notice 'PASS  nothing climbs from a ceiling into a floor, whatever the family code says';
    else raise exception 'FAIL  % measures climb into the branch quality score',
      (select count(*) from perf_assignment where rolls_into_id = q_bm); end if;

  -- a percentage does not divide -- tested along a chain that does hold,
  -- ceiling into ceiling: an executive's work returned into the lead's
  -- error rate.
  o := perf_target_set(p_bm, (select id from perf_assignment
                               where person_id = p_tl and cycle_id = cyc and unit like '%D21%'), 3);
  select target_value into v from perf_assignment
   where person_id = p_e1 and cycle_id = cyc and unit like '%EX3%';
  if v = 3
    then raise notice 'PASS  a percentage is copied down, not divided -- 3%% each, not 0.75%%';
    else raise exception 'FAIL  the percentage came down as %', coalesce(v::text,'nothing'); end if;

  -- ============================================ and a manual edit sticks
  o := perf_target_set(p_tl, a_e1, 300);
  select target_value into v from perf_assignment where id = a_e1;
  if v = 300 and (select target_source from perf_assignment where id = a_e1) = 'MANUAL'
    then raise notice 'PASS  a share typed by hand is pinned';
    else raise exception 'FAIL  the hand-typed share reads % / %',
      v, (select target_source from perf_assignment where id = a_e1); end if;

  select target_value into v from perf_assignment where id = a_e2;
  if v = 100
    then raise notice 'PASS  and the other three redivide what is left -- 300 of 600, 100 each';
    else raise exception 'FAIL  a sibling got % after 300 was pinned', coalesce(v::text,'nothing'); end if;

  -- and the pin survives the next cascade from above
  o := perf_target_set(p_adm, a_bm, 800);
  select target_value into v from perf_assignment where id = a_e1;
  select target_value into v2 from perf_assignment where id = a_e2;
  if v = 300 and v2 = 166.67
    then raise notice 'PASS  a later target from above leaves the pin alone and redivides around it';
    else raise exception 'FAIL  after 800, the pin reads % and a sibling %', v, v2; end if;

  -- ====================================== who may set, and who may not
  o := perf_target_set(p_bm, a_e1, 999);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  a manager two steps up cannot set a target directly';
    else raise exception 'FAIL  the branch manager set an executive''s target'; end if;

  if (select target_value from perf_assignment where id = a_e1) = 300
    then raise notice 'PASS  and the refusal changed nothing';
    else raise exception 'FAIL  a refused write still moved the number'; end if;

  -- ========================================== the number climbs, daily
  d := current_date;
  while not is_working_day(d, null) loop d := d - 1; end loop;

  perform perf_file(p_e1, a_e1, d, 40);
  perform perf_file(p_e2, a_e2, d, 30);
  perform perf_file(p_e3, a_e3, d, 20);
  perform perf_file(p_e4, a_e4, d, 10);

  if perf_value(a_tl) = 100
    then raise notice 'PASS  four executives filing 40/30/20/10 make the lead''s 100';
    else raise exception 'FAIL  the lead reads %', coalesce(perf_value(a_tl)::text,'nothing'); end if;

  if perf_value(a_bm) = 100
    then raise notice 'PASS  and the same 100 reaches the branch, two levels up, untouched by hand';
    else raise exception 'FAIL  the branch reads %', coalesce(perf_value(a_bm)::text,'nothing'); end if;

  perform perf_file(p_e1, a_e1, d - 1, 5);
  if perf_value(a_bm) = 105
    then raise notice 'PASS  one more day from one executive moves the org total the same moment';
    else raise exception 'FAIL  after a second day the branch reads %', perf_value(a_bm); end if;

  -- a percentage averages up rather than summing
  perform perf_file(p_e1, q_e1, d, 4);
  perform perf_file(p_e2, (select id from perf_assignment
                            where person_id = p_e2 and cycle_id = cyc and unit like '%EX3%'), d, 6);
  v := perf_value((select id from perf_assignment
                    where person_id = p_tl and cycle_id = cyc and unit like '%D21%'));
  if v > 0 and v < 10
    then raise notice 'PASS  a percentage averages going up (%), it does not sum to 10', round(v,2);
    else raise exception 'FAIL  two filings of 4 and 6 rolled up to %', coalesce(v::text,'nothing'); end if;

  -- ============================================== something is due today
  if is_working_day(current_date, null) then
    if jsonb_array_length(perf_due(p_e3, current_date)) >= 1
      then raise notice 'PASS  an executive is asked for a number today, on an ordinary working day';
      else raise exception 'FAIL  nothing is due from an executive on a working day'; end if;
  else
    raise notice 'NOTE  today is not a working day, so nothing being due is correct';
  end if;

  -- ================================================= the org, from above
  o := perf_org_rollup(p_bm, cyc);
  if (o->>'teamSize')::int = 5
    then raise notice 'PASS  the branch reads its whole pyramid -- five people below';
    else raise exception 'FAIL  the branch sees % below it', o->>'teamSize'; end if;

  select count(*) into n from jsonb_array_elements(o->'measures') m
   where (m->>'value')::numeric = 105 and (m->>'family') = 'D3';
  if n = 1 then raise notice 'PASS  with the pyramid''s 105 already added into the branch''s own line';
           else raise exception 'FAIL  the org roll-up did not carry the 105'; end if;

  select count(*) into n from jsonb_array_elements(o->'measures') m
   where (m->>'targetSource') is not null and (m->>'feeders')::int >= 0;
  if n = jsonb_array_length(o->'measures')
    then raise notice 'PASS  and every row says where its target came from and how many feed it';
    else raise exception 'FAIL  % of % rows are missing their provenance',
      jsonb_array_length(o->'measures') - n, jsonb_array_length(o->'measures'); end if;

  o := perf_org_rollup(p_e1, cyc, p_bm);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  and an executive cannot read it upwards';
    else raise exception 'FAIL  an executive read their branch manager''s roll-up'; end if;

  -- =========================================== the quarter, narrowed (222)
  o := plb_quarter(current_date);
  if o->>'error' = 'no_actor' and jsonb_array_length(o->'inScheme') = 0
    then raise notice 'PASS  the quarter asked with no actor answers nothing at all';
    else raise exception 'FAIL  the old plb_quarter returned % rows',
      jsonb_array_length(o->'inScheme'); end if;

  o := plb_quarter(current_date, p_e1);
  select count(*) into n from jsonb_array_elements(o->'inScheme') x
   where (x->>'personId')::uuid not in (select person_id from perf_line(p_e1))
     and (x->>'personId')::uuid <> p_e1;
  if n = 0 then raise notice 'PASS  and asked as an executive it holds nobody outside their line';
           else raise exception 'FAIL  the quarter held % people outside the line', n; end if;

  o := plb_quarter(current_date, p_bm);
  if jsonb_array_length(o->'inScheme') >= 5
    then raise notice 'PASS  while the branch manager sees their whole pyramid in it';
    else raise exception 'FAIL  the branch manager saw % in the quarter',
      jsonb_array_length(o->'inScheme'); end if;

  -- =================================== the handover, where a chain stops
  -- The branch's D8 is a count of branches; the lead's D3 is a count of
  -- cases. Nothing climbs between them, and that is right -- but the
  -- branch manager must still SEE what stopped below them before filing
  -- their own number. That is the whole of "if the KPI changes there, the
  -- chair must see the roll up and then update his own".
  o := perf_handover(p_bm, cyc);
  if jsonb_array_length(o->'from') >= 1
    then raise notice 'PASS  the chair above sees the reports whose numbers stopped';
    else raise exception 'FAIL  the handover came back empty'; end if;

  select count(*) into n
    from jsonb_array_elements(o->'from') f,
         jsonb_array_elements(f->'measures') m
   where (m->>'value') is not null;
  if n >= 1
    then raise notice 'PASS  and it carries what those numbers have reached, not just their names';
    else raise exception 'FAIL  the handover named measures but carried no values'; end if;

  -- It is a briefing about the line below, so it must obey the line.
  o := perf_handover(p_e1, cyc, p_bm);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  and an executive cannot read their branch manager''s briefing';
    else raise exception 'FAIL  the handover was readable upwards'; end if;

  -- Nothing climbing into the branch's D8 is still true, and the handover
  -- is what replaces it rather than a quiet null.
  if (select count(*) from perf_assignment a
       where a.cycle_id = cyc and a.rolls_into_id =
             (select id from perf_assignment where person_id = p_bm
               and cycle_id = cyc and unit like '%D8%')) = 0
    then raise notice 'PASS  the count of branches still takes no percentages by arithmetic';
    else raise exception 'FAIL  something climbed into the branches count'; end if;

  -- ============================================ the map says only same-quantity
  if not exists (select 1 from perf_rollup_map
                  where child_family = 'D3' and parent_family = 'D8')
    then raise notice 'PASS  cases no longer claim to be branches';
    else raise exception 'FAIL  D3 -> D8 is still in the map'; end if;

  if exists (select 1 from perf_rollup_map
              where child_family = 'HRE1' and parent_family = 'HRO2')
   and not exists (select 1 from perf_rollup_map
                    where child_family = 'HRE1' and parent_family = 'HRO1')
    then raise notice 'PASS  joiners on record climbs into joiners on record, not into chairs seated';
    else raise exception 'FAIL  HRE1 still points at HRO1'; end if;

  select count(*) into n from perf_rollup_map where child_family = 'EX2';
  if n = 3 then raise notice 'PASS  one family may have several parents -- days filed has three';
           else raise exception 'FAIL  EX2 has % parents, expected 3', n; end if;

  select count(*) into n from perf_rollup_map where child_family = parent_family;
  if n = 0 then raise notice 'PASS  and a code that does not change carries no row, because it needs none';
           else raise exception 'FAIL  % rows map a family to itself', n; end if;

  raise notice '--- the pyramid, both ways: every assertion passed ---';
end $t$;

rollback;
