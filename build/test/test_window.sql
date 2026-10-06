-- The month can be reopened, and a measure can be taken back (migration 246)
--
-- The owner's P1: "set KPI is still not working and just like that most of
-- the Buttons in PMS are not working."
--
-- Measured in a browser first: every control on the Performance screen is
-- wired and clickable. The writes were being refused, and the clock was why.
-- perf_cycle_open gives five working days a month to set KPIs, and after
-- that perf_assign, perf_assign_edit and perf_assign_remove all answer
-- window_closed to anybody but an administrator -- with no way to reopen the
-- month short of hand-written SQL.
--
-- Four claims, each asserted by DOING the thing rather than by restating the
-- predicate:
--
--   1. the window really does refuse, and really does let an administrator
--      through, because that exception is what the screen's own rule copies;
--   2. the three who may open a cycle are the three who may reopen one, and
--      a reopening carries a reason and an audit row;
--   3. once reopened, the manager can set a KPI again -- which is the whole
--      point and the only thing the owner actually asked for;
--   4. taking a measure back WITHDRAWS it: the row stays as the evidence it
--      was asked for, what was filed against it still reads, and the same
--      measure can be given again afterwards.
--
-- Everything is rolled back.

begin;

do $seed$
declare
  p_adm uuid; p_hr uuid; p_bx uuid; p_boss uuid; p_rep uuid; p_plain uuid;
  v_cycle uuid; v_kpi uuid;
begin
  insert into person (full_name, work_email, app_role)
    values ('WN Admin','wn.adm@example.invalid','ADMIN') returning id into p_adm;
  insert into person (full_name, work_email, app_role, department)
    values ('WN HR','wn.hr@example.invalid','MANAGER','Human Resources')
    returning id into p_hr;
  insert into person (full_name, work_email, app_role, department)
    values ('WN BizEx','wn.bx@example.invalid','MANAGER','Business Excellence')
    returning id into p_bx;
  insert into person (full_name, work_email, app_role)
    values ('WN Boss','wn.boss@example.invalid','MANAGER') returning id into p_boss;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('WN Rep','wn.rep@example.invalid','VIEWER', p_boss) returning id into p_rep;
  insert into person (full_name, work_email, app_role)
    values ('WN Plain','wn.plain@example.invalid','VIEWER') returning id into p_plain;

  -- A month whose window is SHUT: closed yesterday, filing still open. That
  -- is the state the whole company is in for three weeks of every four.
  --
  -- Nine months back rather than a made-up far future, because perf_file
  -- refuses a day outside the period and a future period has no days in it
  -- that today can be. Far enough back that no other test file's fixture
  -- claims the same month.
  insert into perf_cycle (period_start, period_kind, assign_opens, assign_closes,
                          entry_closes, opened_by)
  values ((date_trunc('month', current_date) - interval '9 months')::date,
          'MONTH',
          (date_trunc('month', current_date) - interval '9 months')::date,
          current_date - 1, current_date + 30, p_adm)
  returning id into v_cycle;

  insert into kpi_definition (name, unit, active, position)
    values ('WN measure','COUNT', true, 1) returning id into v_kpi;

  create temporary table _wn (k text primary key, v uuid) on commit drop;
  insert into _wn values ('adm',p_adm),('hr',p_hr),('bx',p_bx),('boss',p_boss),
                         ('rep',p_rep),('plain',p_plain),('cycle',v_cycle),('kpi',v_kpi);
end $seed$;

do $t$
declare
  p_adm uuid; p_hr uuid; p_bx uuid; p_boss uuid; p_rep uuid; p_plain uuid;
  v_cycle uuid; v_kpi uuid; v_a uuid; o jsonb; n int; v_was date;
begin
  select v into p_adm   from _wn where _wn.k = 'adm';
  select v into p_hr    from _wn where _wn.k = 'hr';
  select v into p_bx    from _wn where _wn.k = 'bx';
  select v into p_boss  from _wn where _wn.k = 'boss';
  select v into p_rep   from _wn where _wn.k = 'rep';
  select v into p_plain from _wn where _wn.k = 'plain';
  select v into v_cycle from _wn where _wn.k = 'cycle';
  select v into v_kpi   from _wn where _wn.k = 'kpi';

  -- ------------------------------------------------ 1. the clock refuses
  o := perf_assign(p_boss, jsonb_build_object('cycleId', v_cycle,
         'personId', p_rep, 'kpiId', v_kpi, 'target', 10));
  if o->>'error' is distinct from 'window_closed' then
    raise exception 'FAIL  with the window shut perf_assign said %, not window_closed', o;
  end if;
  if o->>'reason' is null then
    raise exception 'FAIL  window_closed carries no reason, so the screen has '
                    'nothing to show';
  end if;
  raise notice 'PASS  a manager is refused once the month has shut, and told why';

  -- The administrator's exception is real, and the screen copies it. If this
  -- ever changed, pfSetWindowOpen would be offering a control that refuses.
  o := perf_assign(p_adm, jsonb_build_object('cycleId', v_cycle,
         'personId', p_rep, 'kpiId', v_kpi, 'target', 10));
  if o->>'error' is not null then
    raise exception 'FAIL  an administrator was refused outside the window: %', o;
  end if;
  v_a := (select id from perf_assignment
           where cycle_id = v_cycle and person_id = p_rep and kpi_id = v_kpi
             and state is distinct from 'WITHDRAWN' limit 1);
  if v_a is null then
    raise exception 'FAIL  the administrator''s assignment was not written';
  end if;
  raise notice 'PASS  and an administrator is not, which is what the screen copies';

  -- --------------------------------------------- 2. who may reopen a month
  if coalesce((perf_cycle_extend(p_plain, v_cycle, current_date + 5, 'x')->>'ok')::boolean, false) then
    raise exception 'FAIL  an ordinary person reopened a month';
  end if;
  if coalesce((perf_cycle_extend(p_boss, v_cycle, current_date + 5, 'x')->>'ok')::boolean, false) then
    raise exception 'FAIL  a manager reopened a month';
  end if;
  raise notice 'PASS  neither an ordinary person nor a manager can reopen a month';

  if perf_cycle_extend(p_hr, v_cycle, current_date + 5, '   ')->>'error'
     is distinct from 'reason_required' then
    raise exception 'FAIL  a month was reopened with no reason';
  end if;
  if perf_cycle_extend(p_hr, v_cycle, current_date - 3, 'x')->>'error'
     is distinct from 'already_past' then
    raise exception 'FAIL  a month was reopened to a date in the past';
  end if;
  if perf_cycle_extend(p_hr, v_cycle, current_date + 90, 'x')->>'error'
     is distinct from 'after_filing_closes' then
    raise exception 'FAIL  a month was reopened past the day filing closes';
  end if;
  if perf_cycle_extend(p_hr, v_cycle, current_date - 1, 'x')->>'error'
     is distinct from 'already_past' then
    raise exception 'FAIL  reopening to the day it already closed was allowed';
  end if;
  raise notice 'PASS  and it is never into the past, never past filing, never without a reason';

  -- Business Excellence may, and so may HR and an administrator -- the same
  -- three perf_cycle_open names. 242's rule: the offer and the write ask the
  -- same question.
  v_was := (select assign_closes from perf_cycle where id = v_cycle);
  o := perf_cycle_extend(p_bx, v_cycle, current_date + 5,
         'The team were still being given managers.');
  if not coalesce((o->>'ok')::boolean, false) then
    raise exception 'FAIL  Business Excellence could not reopen the month: %', o;
  end if;
  if (select assign_closes from perf_cycle where id = v_cycle) <> current_date + 5 then
    raise exception 'FAIL  it said it reopened and the date did not move';
  end if;
  if o->>'was' is null or (o->>'was')::date <> v_was then
    raise exception 'FAIL  the answer does not say what the date was before';
  end if;
  raise notice 'PASS  the three who open a month are the three who reopen it';

  select count(*) into n from audit_entry
   where action = 'PERF_CYCLE_EXTENDED' and entity_ref = v_cycle::text;
  if n <> 1 then
    raise exception 'FAIL  reopening the month wrote % audit row(s)', n;
  end if;
  if (select new_value->>'why' from audit_entry
       where action = 'PERF_CYCLE_EXTENDED' and entity_ref = v_cycle::text)
     <> 'The team were still being given managers.' then
    raise exception 'FAIL  the audit row does not carry the reason given';
  end if;
  raise notice 'PASS  and the reopening is recorded, with the reason and who did it';

  -- It only ever moves later.
  if perf_cycle_extend(p_hr, v_cycle, current_date + 2, 'shorter')->>'error'
     is distinct from 'not_later' then
    raise exception 'FAIL  a month was shut early, retrospectively';
  end if;
  raise notice 'PASS  and never shuts a window people are working inside';

  -- --------------------------------------- 3. the manager can work again
  o := perf_assign(p_boss, jsonb_build_object('cycleId', v_cycle,
         'personId', p_rep, 'kpiId', null, 'name','WN second','unit','COUNT'));
  if o->>'error' is not null then
    raise exception 'FAIL  the month was reopened and the manager still cannot '
                    'set a KPI: %', o;
  end if;
  raise notice 'PASS  once reopened, the manager can set a KPI again';

  -- ------------------------------------------ 4. taking a measure back
  -- Something filed against it, so the interesting case is covered.
  perform perf_file(p_rep, v_a, current_date, 3, null);
  select count(*) into n from perf_entry where assignment_id = v_a;
  if n = 0 then
    raise exception 'FAIL  the fixture could not file a figure to test with';
  end if;

  if coalesce((perf_assign_remove(p_rep, v_a)->>'ok')::boolean, false) then
    raise exception 'FAIL  a person took their own measure back';
  end if;
  raise notice 'PASS  nobody takes their own measure back';

  o := perf_assign_remove(p_boss, v_a);
  if not coalesce((o->>'ok')::boolean, false) then
    raise exception 'FAIL  the manager could not take the measure back: %', o;
  end if;
  if (select state from perf_assignment where id = v_a) <> 'WITHDRAWN' then
    raise exception 'FAIL  the measure was not marked WITHDRAWN';
  end if;
  if not exists (select 1 from perf_assignment where id = v_a) then
    raise exception 'FAIL  the measure was deleted. It is the evidence the '
                    'manager asked for it.';
  end if;
  raise notice 'PASS  a measure taken back is withdrawn, never deleted';

  select count(*) into n from perf_entry where assignment_id = v_a;
  if n = 0 then
    raise exception 'FAIL  the figures filed against it went with it';
  end if;
  raise notice 'PASS  and what was filed against it still reads back';

  if not exists (select 1 from audit_entry
                  where action = 'PERF_KPI_WITHDRAWN' and entity_ref = v_a::text) then
    raise exception 'FAIL  taking a measure back wrote no audit row';
  end if;
  -- The audit row points at something that still exists, which is the whole
  -- argument against deleting.
  if not exists (select 1 from audit_entry e join perf_assignment x
                   on x.id = e.entity_ref::uuid
                  where e.action = 'PERF_KPI_WITHDRAWN' and e.entity_ref = v_a::text) then
    raise exception 'FAIL  the audit row points at a measure that is not there';
  end if;
  raise notice 'PASS  and the audit row still points at the measure it describes';

  -- Taking it back twice is not an error, it is a no-op that says so.
  o := perf_assign_remove(p_boss, v_a);
  if not coalesce((o->>'ok')::boolean, false)
     or coalesce((o->>'changed')::boolean, true) then
    raise exception 'FAIL  taking back an already-withdrawn measure is not a '
                    'quiet no-op: %', o;
  end if;
  raise notice 'PASS  taking one back twice changes nothing and says so';

  -- And the same measure can be given again, which is what narrowing
  -- perf_assignment_once_top was for.
  o := perf_assign(p_boss, jsonb_build_object('cycleId', v_cycle,
         'personId', p_rep, 'kpiId', v_kpi, 'target', 20));
  if o->>'error' is not null then
    raise exception 'FAIL  a withdrawn measure still blocks giving the same '
                    'one again: %', o;
  end if;
  select count(*) into n from perf_assignment
   where cycle_id = v_cycle and person_id = p_rep and kpi_id = v_kpi
     and state is distinct from 'WITHDRAWN';
  if n <> 1 then
    raise exception 'FAIL  % live copies of the same measure for one person '
                    'in one month', n;
  end if;
  raise notice 'PASS  the same measure can be given again, and only once';

  -- ------------------------------------- 5. the other door onto the same act
  -- "Carry last month forward" gives somebody measures exactly as setting one
  -- does, but perf_carry_forward writes perf_assignment rows directly rather
  -- than through perf_assign -- so it carried no window guard at all and
  -- stayed open after Set a KPI had shut. Two doors, one act, two rules.
  update perf_cycle set assign_closes = current_date - 1 where id = v_cycle;
  o := perf_carry_forward(p_boss, v_cycle, p_rep, true);
  if o->>'error' is distinct from 'window_closed' then
    raise exception 'FAIL  carrying last month forward still works after the '
                    'window shut, while setting a KPI does not: %', o;
  end if;
  raise notice 'PASS  carrying last month forward answers the same clock';

  o := perf_carry_forward(p_adm, v_cycle, p_rep, true);
  if o->>'error' is not null then
    raise exception 'FAIL  an administrator could not carry forward: %', o;
  end if;
  raise notice 'PASS  and lets an administrator through, the same way';

  -- And it must not hand back the measures a manager took back. This is this
  -- change''s own doing: with measures withdrawn rather than deleted, a
  -- carry-forward that reads every row of last month would resurrect them.
  declare
    v_prev uuid; v_dead uuid; n_back int;
  begin
    insert into perf_cycle (period_start, period_kind, assign_opens,
                            assign_closes, entry_closes, opened_by)
    values ((date_trunc('month', current_date) - interval '10 months')::date,
            'MONTH',
            (date_trunc('month', current_date) - interval '10 months')::date,
            current_date + 10, current_date + 40, p_adm)
    returning id into v_prev;

    o := perf_assign(p_boss, jsonb_build_object('cycleId', v_prev,
           'personId', p_rep, 'name','WN taken back','unit','COUNT'));
    v_dead := (select id from perf_assignment
                where cycle_id = v_prev and person_id = p_rep
                  and name = 'WN taken back' limit 1);
    if v_dead is null then
      raise exception 'FAIL  the fixture could not set a measure to take back';
    end if;
    if not coalesce((perf_assign_remove(p_boss, v_dead)->>'ok')::boolean, false) then
      raise exception 'FAIL  the fixture could not take that measure back';
    end if;

    -- Now carry THAT month forward into the one after it.
    o := perf_carry_forward(p_adm, v_cycle, p_rep, true);
    select count(*) into n_back from perf_assignment
     where cycle_id = v_cycle and person_id = p_rep and name = 'WN taken back';
    if n_back > 0 then
      raise exception 'FAIL  a measure the manager took back was carried '
                      'forward into the next month';
    end if;
    raise notice 'PASS  and never carries back a measure that was taken back';
  end;

  raise notice '--- the month and the measure: every assertion passed ---';
end $t$;

rollback;
