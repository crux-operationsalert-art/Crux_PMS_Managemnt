-- The quarter belongs to the manager, not to the scheme (migration 247)
--
-- "as a manager I am still not able to change the KPIs for quaterly score
--  card ... as well as Monthly targets"
-- "I can still update and change my own targets, which is wrong. Only my One
--  up should be able to do that and no one else. Not even my Manager's
--  manager, only my manager."
--
-- One defect, two symptoms. The quarterly side asked who RUNS the scheme
-- where it should have asked who MANAGES the person. Every assertion below
-- is the owner's sentence, said in SQL:
--
--   only my one up            -> the manager may, the manager's manager may not
--   and no one else           -> a stranger may not
--   not me                    -> nobody touches their own, administrators
--                                included, because perf_rel answers 'self'
--                                before it answers 'admin'
--   HR still runs the scheme  -> and may still issue
--
-- Everything is rolled back.

begin;

do $seed$
declare
  p_above uuid; p_boss uuid; p_rep uuid; p_hr uuid; p_other uuid; p_adm uuid;
  v_chair uuid; v_kpi uuid;
begin
  insert into person (full_name, work_email, app_role)
    values ('QT Above','qt.above@example.invalid','MANAGER') returning id into p_above;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('QT Boss','qt.boss@example.invalid','MANAGER', p_above) returning id into p_boss;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('QT Rep','qt.rep@example.invalid','VIEWER', p_boss) returning id into p_rep;
  insert into person (full_name, work_email, app_role, department)
    values ('QT HR','qt.hr@example.invalid','MANAGER','Human Resources') returning id into p_hr;
  insert into person (full_name, work_email, app_role)
    values ('QT Other','qt.other@example.invalid','VIEWER') returning id into p_other;
  insert into person (full_name, work_email, app_role)
    values ('QT Admin','qt.adm@example.invalid','ADMIN') returning id into p_adm;

  insert into chair (code, title, level) values ('QT-CH','QT Chair','BRANCH')
    returning id into v_chair;
  insert into kpi_definition (name, unit, active, position, chair_id)
    values ('QT measure','COUNT', true, 1, v_chair) returning id into v_kpi;
  insert into chair_holder (chair_id, person_id, is_primary) values (v_chair, p_rep, true);
  insert into chair_holder (chair_id, person_id, is_primary) values (v_chair, p_adm, true);

  create temporary table _qt (k text primary key, v uuid) on commit drop;
  insert into _qt values ('above',p_above),('boss',p_boss),('rep',p_rep),
                         ('hr',p_hr),('other',p_other),('adm',p_adm),
                         ('chair',v_chair),('kpi',v_kpi);
end $seed$;

do $t$
declare
  p_above uuid; p_boss uuid; p_rep uuid; p_hr uuid; p_other uuid; p_adm uuid;
  v_kpi uuid; v_sheet uuid; v_gk uuid; o jsonb; q date; n int;
begin
  select v into p_above from _qt where _qt.k='above';
  select v into p_boss  from _qt where _qt.k='boss';
  select v into p_rep   from _qt where _qt.k='rep';
  select v into p_hr    from _qt where _qt.k='hr';
  select v into p_other from _qt where _qt.k='other';
  select v into p_adm   from _qt where _qt.k='adm';
  select v into v_kpi   from _qt where _qt.k='kpi';
  q := date_trunc('quarter', current_date)::date;

  -- ------------------------------------------------- who may issue a sheet
  o := plb_sheet_issue(p_boss, p_rep, q, 100000, '[]'::jsonb, false);
  if o->>'error' is not null then
    raise exception 'FAIL  the reporting manager could not issue a goal sheet: %', o;
  end if;
  raise notice 'PASS  the reporting manager issues the goal sheet';

  select id into v_sheet from plb_goal_sheet
   where person_id = p_rep and quarter = q order by created_at desc limit 1;
  if v_sheet is null then
    raise exception 'FAIL  the sheet the manager issued is not there';
  end if;

  if plb_sheet_issue(p_above, p_rep, q, 100000, '[]'::jsonb, false)->>'error'
     is distinct from 'not_permitted' then
    raise exception 'FAIL  the manager''s manager issued a sheet. The owner asked '
                    'for only the one up.';
  end if;
  raise notice 'PASS  and the manager''s manager does not';

  if plb_sheet_issue(p_other, p_rep, q, 100000, '[]'::jsonb, false)->>'error'
     is distinct from 'not_permitted' then
    raise exception 'FAIL  a stranger issued a goal sheet';
  end if;
  raise notice 'PASS  nor anybody outside the line';

  -- Nobody sets their own. perf_rel answers 'self' before it answers 'admin',
  -- so this holds for an administrator too -- which is the case the owner hit.
  if plb_sheet_issue(p_rep, p_rep, q, 100000, '[]'::jsonb, false)->>'error' is null then
    raise exception 'FAIL  a person issued their own goal sheet';
  end if;
  if plb_sheet_issue(p_adm, p_adm, q, 100000, '[]'::jsonb, false)->>'error' is null then
    raise exception 'FAIL  an ADMINISTRATOR issued their own goal sheet. That is '
                    'the one the owner reported.';
  end if;
  raise notice 'PASS  and nobody sets their own, administrators included';

  -- Running the scheme is still HR's, Business Excellence's and the
  -- administrator's. The rule must not have become narrower than it was.
  if plb_sheet_issue(p_hr, p_rep, (q - interval '3 months')::date, 100000,
       '[]'::jsonb, false)->>'error' is not null then
    raise exception 'FAIL  HR can no longer issue a sheet';
  end if;
  if plb_sheet_issue(p_adm, p_rep, (q - interval '6 months')::date, 100000,
       '[]'::jsonb, false)->>'error' is not null then
    raise exception 'FAIL  an administrator can no longer issue a sheet';
  end if;
  raise notice 'PASS  HR and an administrator still run the scheme';

  -- ---------------------------------------------------- recording an actual
  -- plb_actual_set had no actor check at all before 247: it was safe only
  -- because the route refused first, and a rule enforced in a route is a rule
  -- exactly one caller obeys.
  if plb_actual_set(p_other, v_sheet, v_kpi, 10)->>'error'
     is distinct from 'not_permitted' then
    raise exception 'FAIL  a stranger recorded somebody''s actual';
  end if;
  if plb_actual_set(p_rep, v_sheet, v_kpi, 10)->>'error'
     is distinct from 'not_permitted' then
    raise exception 'FAIL  a person recorded their own actual';
  end if;
  if plb_actual_set(p_above, v_sheet, v_kpi, 10)->>'error'
     is distinct from 'not_permitted' then
    raise exception 'FAIL  the manager''s manager recorded an actual';
  end if;
  if plb_actual_set(p_boss, v_sheet, v_kpi, 10)->>'error' is not null then
    raise exception 'FAIL  the reporting manager could not record an actual: %',
      plb_actual_set(p_boss, v_sheet, v_kpi, 10);
  end if;
  raise notice 'PASS  an actual is the reporting manager''s and nobody else''s';

  -- -------------------------------------------------- scoring the month
  if plb_score_month(p_above, v_sheet, date_trunc('month', current_date)::date, 8, 2, null)
     ->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  the manager''s manager scored a month';
  end if;
  if plb_score_month(p_other, v_sheet, date_trunc('month', current_date)::date, 8, 2, null)
     ->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  a stranger scored a month';
  end if;
  raise notice 'PASS  and so is the month''s score';

  -- -------------------------------- the screen reads the same answer
  -- plb_quarter carries maySet per sheet, and that is what the quarterly
  -- card now draws on. If this ever stopped agreeing with the writes above,
  -- the screen would be back to offering what the database refuses.
  o := plb_quarter(q, p_boss);
  if not exists (select 1 from jsonb_array_elements(o->'sheets') x
                  where (x->>'personId')::uuid = p_rep
                    and coalesce((x->>'maySet')::boolean,false)) then
    raise exception 'FAIL  the quarter does not tell the manager the sheet is theirs';
  end if;
  o := plb_quarter(q, p_above);
  if exists (select 1 from jsonb_array_elements(o->'sheets') x
              where (x->>'personId')::uuid = p_rep
                and coalesce((x->>'maySet')::boolean,false)) then
    raise exception 'FAIL  the quarter tells the manager''s manager the sheet is theirs';
  end if;
  o := plb_quarter(q, p_rep);
  if exists (select 1 from jsonb_array_elements(o->'sheets') x
              where (x->>'personId')::uuid = p_rep
                and coalesce((x->>'maySet')::boolean,false)) then
    raise exception 'FAIL  the quarter tells a person their own sheet is theirs to set';
  end if;
  raise notice 'PASS  and the screen is told exactly what the writes will allow';

  -- ============================================================ 249
  -- The quarter said in months, and split into its parts.
  --
  --   "add sub KPIs in both monthly and the quaterly score card"
  --   "use the same [format] for [the quarterly] too but should be linked
  --    with the quaterly"
  -- ------------------------------------------------------------------
  select gk.id into v_gk from plb_goal_kpi gk
   where gk.sheet_id = v_sheet and gk.kpi_id = v_kpi;
  if v_gk is null then
    raise exception 'FAIL  the sheet carries no row for its own measure';
  end if;

  -- Breaking a measure into parts follows the same rule as everything else
  -- on the sheet: the one up, and the people who run the scheme.
  if plb_kpi_part_set(p_other, v_gk, '[]'::jsonb)->>'error'
     is distinct from 'not_permitted' then
    raise exception 'FAIL  a stranger broke up somebody''s measure';
  end if;
  if plb_kpi_part_set(p_above, v_gk, '[]'::jsonb)->>'error'
     is distinct from 'not_permitted' then
    raise exception 'FAIL  the manager''s manager broke up a measure';
  end if;
  if plb_kpi_part_set(p_rep, v_gk, '[]'::jsonb)->>'error' is null then
    raise exception 'FAIL  a person broke up their own measure';
  end if;
  raise notice 'PASS  a sub-measure is the one up''s, exactly like the target';

  o := plb_kpi_part_set(p_boss, v_gk, jsonb_build_array(
         jsonb_build_object('label','Bank A','target',40),
         jsonb_build_object('label','Bank B','target',20)));
  if o->>'error' is not null then
    raise exception 'FAIL  the reporting manager could not add sub-measures: %', o;
  end if;
  select count(*) into n from plb_goal_kpi_part
   where goal_kpi_id = v_gk and removed_at is null;
  if n <> 2 then
    raise exception 'FAIL  % parts were written, not two', n;
  end if;
  raise notice 'PASS  and the reporting manager can add them';

  -- A part carries no weight and enters no arithmetic. The measure set a
  -- chair publishes has to stay identical for every seat of that chair, and
  -- the sheet says so on screen.
  select count(*) into n from plb_goal_kpi where sheet_id = v_sheet;
  if n <> 1 then
    raise exception 'FAIL  adding sub-measures changed the measure set: % rows', n;
  end if;
  raise notice 'PASS  the measure set is untouched: a part is a breakdown, '
               'not a second measure';

  -- A measure with no target of its own cannot be agreed or disagreed with,
  -- and the reply says so rather than guessing. The sheet here was issued
  -- without targets, which is the ordinary state before a manager sets them.
  if o->>'addsUp' is not null then
    raise exception 'FAIL  parts were compared against a target that is not '
                    'there: %', o;
  end if;

  -- Whether the parts add up is reported, never enforced. Refusing a
  -- breakdown halfway through writing one would make somebody do the
  -- arithmetic before the tool would take the first line.
  update plb_goal_kpi set target_value = 60 where id = v_gk;
  o := plb_kpi_part_set(p_boss, v_gk, jsonb_build_array(
         jsonb_build_object('label','Bank A','target',40),
         jsonb_build_object('label','Bank B','target',20)));
  if (o->>'addsUp')::boolean is not true then
    raise exception 'FAIL  40 and 20 against a target of 60 was not called '
                    'agreement: %', o;
  end if;
  o := plb_kpi_part_set(p_boss, v_gk, jsonb_build_array(
         jsonb_build_object('label','Bank A','target',40)));
  if (o->>'addsUp')::boolean is not false then
    raise exception 'FAIL  40 against a target of 60 was called agreement: %', o;
  end if;
  if o->>'error' is not null then
    raise exception 'FAIL  a breakdown that does not add up was REFUSED. It is '
                    'a normal state halfway through writing one: %', o;
  end if;
  raise notice 'PASS  a breakdown that does not add up is said, never refused';

  select count(*) into n from plb_goal_kpi_part
   where goal_kpi_id = v_gk and removed_at is null;
  if n <> 1 then
    raise exception 'FAIL  replacing the list left % rows', n;
  end if;
  o := plb_kpi_part_set(p_boss, v_gk, '[]'::jsonb);
  select count(*) into n from plb_goal_kpi_part
   where goal_kpi_id = v_gk and removed_at is null;
  if n <> 0 then
    raise exception 'FAIL  an empty list did not remove the breakdown';
  end if;
  raise notice 'PASS  the list is replaced whole, and an empty one removes it';

  -- Removed means withdrawn, not erased -- 246's rule, applied here. And a
  -- part put back comes back as ITSELF: one row per name for the life of the
  -- sheet, so "what was Bank A asked for in October" has one answer.
  select count(*) into n from plb_goal_kpi_part where goal_kpi_id = v_gk;
  if n = 0 then
    raise exception 'FAIL  the parts were erased. Three months later, in a '
                    'dispute, nothing can say what the breakdown used to be.';
  end if;
  o := plb_kpi_part_set(p_boss, v_gk, jsonb_build_array(
         jsonb_build_object('label','bank a ','target',55)));
  select count(*) into n from plb_goal_kpi_part where goal_kpi_id = v_gk;
  if n <> 2 then
    raise exception 'FAIL  putting Bank A back made a second row for it: % rows', n;
  end if;
  select count(*) into n from plb_goal_kpi_part
   where goal_kpi_id = v_gk and removed_at is null;
  if n <> 1 then
    raise exception 'FAIL  % parts are live after putting one back, not one', n;
  end if;
  raise notice 'PASS  a part taken off is withdrawn, and put back it is itself '
               'again';

  if plb_kpi_part_set(p_boss, v_gk, jsonb_build_array(
       jsonb_build_object('label','   ','target',10)))->>'error'
     is distinct from 'invalid' then
    raise exception 'FAIL  a part with no name was accepted';
  end if;
  raise notice 'PASS  and a part nobody can name is not a part of anything';

  -- ---------------------------------------- the monthly shape, and the link
  o := plb_kpi_months(p_boss, v_sheet);
  if o->>'error' is not null then
    raise exception 'FAIL  the quarter could not be read in months: %', o;
  end if;
  if jsonb_array_length(o->'measures') = 0 then
    raise exception 'FAIL  the quarter in months carries no measures';
  end if;
  select count(*) into n from jsonb_array_elements(o->'measures') x
   where jsonb_array_length(x->'months') <> 3;
  if n > 0 then
    raise exception 'FAIL  % measure(s) do not carry three months. A quarter '
                    'is three months whether or not any of them was filed.', n;
  end if;
  -- Each month says what the quarter's split implies it should be. That is
  -- the link: the two cards stop being two unrelated numbers.
  select count(*) into n from jsonb_array_elements(o->'measures') x,
                                jsonb_array_elements(x->'months') m
   where not (m ? 'implied') or not (m ? 'target') or not (m ? 'filed');
  if n > 0 then
    raise exception 'FAIL  % month(s) carry no implied target, real target or '
                    'filed figure. Without all three there is nothing to '
                    'compare.', n;
  end if;
  if not coalesce((o->>'maySet')::boolean, false) then
    raise exception 'FAIL  the reporting manager is told the quarter is not '
                    'theirs to set';
  end if;
  if coalesce((plb_kpi_months(p_rep, v_sheet)->>'maySet')::boolean, false) then
    raise exception 'FAIL  a person is told their own quarter is theirs to set';
  end if;
  if plb_kpi_months(p_other, v_sheet)->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  a stranger read somebody''s quarter';
  end if;
  raise notice 'PASS  the quarter reads in the monthly card''s shape, under '
               'the same rule as everything else on it';

  raise notice '--- the quarter: every assertion passed ---';
end $t$;

rollback;
