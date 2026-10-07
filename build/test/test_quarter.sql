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
  v_kpi uuid; v_sheet uuid; o jsonb; q date;
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

  raise notice '--- the quarter: every assertion passed ---';
end $t$;

rollback;
