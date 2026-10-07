-- Editing the quarterly scorecard (migration 255)
--
-- "still not able to edit/update KPIs of quaterly scorecard"
--
-- Each assertion is one sentence about who may change a quarterly sheet and
-- what stops them:
--
--   nobody edits their own
--   the one-up manager does
--   the weights add to a hundred
--   every measure carries a target, and zero counts
--   a measure can be added and one can be taken off
--   a measure with a figure against it cannot be taken off
--   a locked sheet does not change
--   a refusal writes nothing
--
-- Everything is rolled back.

begin;

do $t$
declare
  p_boss uuid; p_rep uuid; p_other uuid;
  v_k1 uuid; v_k2 uuid; v_k3 uuid; v_sheet uuid; v_gk uuid; v_chair uuid;
  o jsonb; n int; v_q date;
begin
  v_q := date_trunc('quarter', current_date)::date;

  insert into person (full_name, work_email, app_role)
    values ('QE Boss','qe.boss@example.invalid','MANAGER') returning id into p_boss;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('QE Rep','qe.rep@example.invalid','VIEWER', p_boss) returning id into p_rep;
  insert into person (full_name, work_email, app_role)
    values ('QE Other','qe.other@example.invalid','VIEWER') returning id into p_other;

  select id into v_chair from chair order by title limit 1;

  insert into kpi_definition (name, unit, active, position)
    values ('QE one','COUNT', true, 1) returning id into v_k1;
  insert into kpi_definition (name, unit, active, position)
    values ('QE two','COUNT', true, 2) returning id into v_k2;
  insert into kpi_definition (name, unit, active, position)
    values ('QE three','COUNT', true, 3) returning id into v_k3;

  insert into plb_goal_sheet (person_id, chair_id, quarter, target_plb_inr, status)
    values (p_rep, v_chair, v_q, 50000, 'ISSUED') returning id into v_sheet;
  insert into plb_goal_kpi (sheet_id, kpi_id, weight_pct, target_value)
    values (v_sheet, v_k1, 60, 100);
  insert into plb_goal_kpi (sheet_id, kpi_id, weight_pct, target_value)
    values (v_sheet, v_k2, 40, 20);

  -- ------------------------------------------------------ nobody's own
  if plb_sheet_measures_set(p_rep, v_sheet, jsonb_build_array(
       jsonb_build_object('kpiId', v_k1, 'weight', 100, 'target', 100)))
     ->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  a person changed the measures on their own sheet. '
                    'Every other rule in the scheme rests on not being able to.';
  end if;
  if plb_sheet_measures_set(p_other, v_sheet, jsonb_build_array(
       jsonb_build_object('kpiId', v_k1, 'weight', 100, 'target', 100)))
     ->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  somebody outside the line changed a sheet';
  end if;
  raise notice 'PASS  nobody edits their own quarterly sheet, and nor does a '
               'stranger';

  -- --------------------------------------------------- the weights add up
  if plb_sheet_measures_set(p_boss, v_sheet, jsonb_build_array(
       jsonb_build_object('kpiId', v_k1, 'weight', 60, 'target', 100),
       jsonb_build_object('kpiId', v_k2, 'weight', 60, 'target', 20)))
     ->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  weights of 60 and 60 were accepted. Migration 237 '
                    'is the record of what that costs.';
  end if;
  raise notice 'PASS  the weights on a sheet add to a hundred';

  -- ------------------------------------------------ a target, and zero counts
  if plb_sheet_measures_set(p_boss, v_sheet, jsonb_build_array(
       jsonb_build_object('kpiId', v_k1, 'weight', 100)))
     ->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  a measure with no target was accepted. "One up '
                    'manager if has assigned a KPI should be assigning the '
                    'target too."';
  end if;
  o := plb_sheet_measures_set(p_boss, v_sheet, jsonb_build_array(
         jsonb_build_object('kpiId', v_k1, 'weight', 100, 'target', 0,
                            'direction','LOWER')));
  if o->>'error' is not null then
    raise exception 'FAIL  a target of zero was refused: %', o;
  end if;
  if (select target_value from plb_goal_kpi
       where sheet_id = v_sheet and kpi_id = v_k1) <> 0 then
    raise exception 'FAIL  a target of zero did not save as zero';
  end if;
  if (select direction from plb_goal_kpi
       where sheet_id = v_sheet and kpi_id = v_k1) <> 'LOWER' then
    raise exception 'FAIL  the direction the manager chose was not kept';
  end if;
  raise notice 'PASS  every measure carries a target, and zero is one of them';

  -- ----------------------------------------- one came off, one went on
  select count(*) into n from plb_goal_kpi where sheet_id = v_sheet;
  if n <> 1 then
    raise exception 'FAIL  % measures are on the sheet after a list of one', n;
  end if;
  o := plb_sheet_measures_set(p_boss, v_sheet, jsonb_build_array(
         jsonb_build_object('kpiId', v_k1, 'weight', 50, 'target', 10),
         jsonb_build_object('kpiId', v_k3, 'weight', 50, 'target', 5)));
  if o->>'error' is not null then
    raise exception 'FAIL  a measure could not be added: %', o;
  end if;
  if (o->>'added')::int <> 1 then
    raise exception 'FAIL  the reply does not say what it added: %', o;
  end if;
  select count(*) into n from plb_goal_kpi
   where sheet_id = v_sheet and kpi_id = v_k3;
  if n <> 1 then raise exception 'FAIL  the new measure is not on the sheet'; end if;
  raise notice 'PASS  a measure can be added and one can be taken off';

  -- ---------------------------------------- the split across three months
  if plb_sheet_measures_set(p_boss, v_sheet, jsonb_build_array(
       jsonb_build_object('kpiId', v_k1, 'weight', 100, 'target', 10,
                          'm1', 50, 'm2', 30)))
     ->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  two months out of three were accepted';
  end if;
  if plb_sheet_measures_set(p_boss, v_sheet, jsonb_build_array(
       jsonb_build_object('kpiId', v_k1, 'weight', 100, 'target', 10,
                          'm1', 50, 'm2', 30, 'm3', 30)))
     ->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  a split of 50, 30 and 30 was accepted';
  end if;
  o := plb_sheet_measures_set(p_boss, v_sheet, jsonb_build_array(
         jsonb_build_object('kpiId', v_k1, 'weight', 100, 'target', 10,
                            'm1', 50, 'm2', 30, 'm3', 20)));
  if o->>'error' is not null then
    raise exception 'FAIL  a split of 50, 30 and 20 was refused: %', o;
  end if;
  raise notice 'PASS  the three months of a split are all there and add up';

  -- ------------------------------- a measure with something against it stays
  update plb_goal_kpi set actual_value = 7
   where sheet_id = v_sheet and kpi_id = v_k1;
  if plb_sheet_measures_set(p_boss, v_sheet, jsonb_build_array(
       jsonb_build_object('kpiId', v_k2, 'weight', 100, 'target', 3)))
     ->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  a measure with a figure worked out against it was '
                    'taken off the sheet. That is erasing a quarter, not '
                    'correcting a sheet.';
  end if;
  select count(*) into n from plb_goal_kpi where sheet_id = v_sheet;
  if n <> 1 then
    raise exception 'FAIL  the refusal changed the sheet anyway: % rows', n;
  end if;
  raise notice 'PASS  a measure with a figure against it cannot be removed, '
               'and the refusal wrote nothing';

  -- ------------------------------------------------------- once it locks
  update plb_goal_kpi set actual_value = null where sheet_id = v_sheet;
  update plb_goal_sheet set status = 'LOCKED' where id = v_sheet;
  if plb_sheet_measures_set(p_boss, v_sheet, jsonb_build_array(
       jsonb_build_object('kpiId', v_k1, 'weight', 100, 'target', 99)))
     ->>'error' is distinct from 'sheet_locked' then
    raise exception 'FAIL  a locked sheet was changed. It is the promise the '
                    'quarter is scored against.';
  end if;
  if (select target_value from plb_goal_kpi
       where sheet_id = v_sheet and kpi_id = v_k1) = 99 then
    raise exception 'FAIL  the locked sheet changed anyway';
  end if;
  raise notice 'PASS  a locked sheet does not change';

  -- ------------------------------------------------------- what may go on
  update plb_goal_sheet set status = 'ISSUED' where id = v_sheet;
  o := plb_sheet_measure_options(p_boss, v_sheet);
  if not coalesce((o->>'maySet')::boolean,false) then
    raise exception 'FAIL  the manager is told they may not set: %', o;
  end if;
  if jsonb_array_length(coalesce(o->'measures','[]'::jsonb)) < 3 then
    raise exception 'FAIL  the measures that may go on a sheet are not offered';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(o->'measures') m
     where (m->>'kpiId')::uuid = v_k1 and (m->>'onTheSheet')::boolean) then
    raise exception 'FAIL  the list does not say which are already on';
  end if;
  o := plb_sheet_measure_options(p_rep, v_sheet);
  if coalesce((o->>'maySet')::boolean,false) then
    raise exception 'FAIL  a person is offered their own measures to set';
  end if;
  raise notice 'PASS  the list says what may go on, and what is already on';

  -- ------------------------- a withdrawn measure is invisible BY CONSTRUCTION
  --
  -- Not "every reader remembers to filter it out" -- fourteen functions read
  -- plb_goal_kpi and not one of them knows a measure can be withdrawn. They
  -- are right not to know: plb_goal_kpi is a view over the live rows. This
  -- asserts the property they are all relying on.
  o := plb_sheet_measures_set(p_boss, v_sheet, jsonb_build_array(
         jsonb_build_object('kpiId', v_k1, 'weight', 100, 'target', 7)));
  if o->>'error' is not null then
    raise exception 'FAIL  the sheet would not reduce to one measure: %', o;
  end if;
  select count(*) into n from plb_goal_kpi where sheet_id = v_sheet;
  if n <> 1 then
    raise exception 'FAIL  % measures are visible through the view after '
                    'reducing the sheet to one. Every scoring function reads '
                    'that view.', n;
  end if;
  select count(*) into n from plb_goal_kpi_all where sheet_id = v_sheet;
  if n < 2 then
    raise exception 'FAIL  a measure taken off the sheet was erased. "What was '
                    'this sheet asking for in October" is a question somebody '
                    'asks about a payout months later.';
  end if;
  raise notice 'PASS  a measure taken off is invisible to every reader and '
               'still on the record';

  -- And putting it back is the same row again, not a second one.
  o := plb_sheet_measures_set(p_boss, v_sheet, jsonb_build_array(
         jsonb_build_object('kpiId', v_k1, 'weight', 50, 'target', 7),
         jsonb_build_object('kpiId', v_k3, 'weight', 50, 'target', 2)));
  if o->>'error' is not null then
    raise exception 'FAIL  a withdrawn measure could not be put back: %', o;
  end if;
  select count(*) into n from plb_goal_kpi_all
   where sheet_id = v_sheet and kpi_id = v_k3;
  if n <> 1 then
    raise exception 'FAIL  putting a measure back made a second row (% rows). '
                    'Two rows for one measure is two scores for one promise.', n;
  end if;
  raise notice 'PASS  a measure taken off and put back is one row, revived';

  raise notice '--- the quarterly sheet is editable: every assertion passed ---';
end $t$;

rollback;
