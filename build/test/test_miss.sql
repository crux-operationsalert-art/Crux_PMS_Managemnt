-- Windows, caps, and a missed window escalated by e-mail (269)
--
-- "Wait for the month to end before scoring. Set windows and caps. If
--  missed should raise escalations with emails." -- the owner, 16 Oct.
begin;

do $t$
declare
  p_top uuid; p_boss uuid; p_rep uuid; v_sys uuid; v_chair uuid; v_sheet uuid; v_cycle uuid;
  v_m date := date_trunc('month', current_date)::date; o jsonb; n int;
begin
  select id into v_sys from person where work_email = 'operations.alert@cruxindia.co.in';
  if v_sys is null then
    insert into person (full_name, work_email, app_role, employee_type)
      values ('Operations Alert', 'operations.alert@cruxindia.co.in', 'ADMIN', 'SERVICE_ACCOUNT')
      returning id into v_sys;
  end if;
  insert into person (full_name, work_email, app_role) values ('WM Top', 'wm.top@example.invalid', 'MANAGER')
    returning id into p_top;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('WM Boss', 'wm.boss@example.invalid', 'MANAGER', p_top) returning id into p_boss;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('WM Rep', 'wm.rep@example.invalid', 'VIEWER', p_boss) returning id into p_rep;
  select id into v_chair from chair order by title limit 1;
  insert into plb_goal_sheet (person_id, chair_id, quarter, target_plb_inr, status)
    values (p_rep, v_chair, date_trunc('quarter', current_date)::date, 0, 'ISSUED') returning id into v_sheet;
  o := perf_cycle_open(v_sys, v_m, 'MONTH');
  select id into v_cycle from perf_cycle where period_start = v_m and period_kind = 'MONTH';
  update perf_cycle set assign_closes = current_date - 1 where id = v_cycle;
  insert into app_setting (key, value, plain_language, group_name, editable_by)
    values ('window_escalations_from', (v_m - interval '2 months')::date::text, 'test', 'Performance', 'ADMIN')
    on conflict (key) do update set value = excluded.value;

  -- ---------------------------------------------------------------- caps
  if plb_score_month(p_boss, v_sheet, v_m, 11, 5)->>'error' is distinct from 'out_of_range' then
    raise exception 'FAIL  a KPI score of 11 out of 10 was not refused';
  end if;
  if plb_score_month(p_boss, v_sheet, (v_m - interval '1 year')::date, 5, 5)->>'error'
     is distinct from 'not_this_quarter' then
    raise exception 'FAIL  a month outside the sheet''s quarter was not refused';
  end if;
  if plb_self_eval(p_rep, v_sheet, v_m, -1, 5)->>'error' is distinct from 'out_of_range' then
    raise exception 'FAIL  a self-evaluation below nought was not refused';
  end if;
  if plb_self_eval(p_rep, gen_random_uuid(), v_m, 5, 5)->>'error' is distinct from 'no_such_sheet' then
    raise exception 'FAIL  a self-evaluation against no sheet was not refused';
  end if;
  raise notice 'PASS  scores are out of ten, and of the sheet''s own months';

  -- ------------------------------------------------- the month is over
  o := plb_score_month(p_boss, v_sheet, v_m, 8, 8);
  if o->>'error' is distinct from 'month_not_over' or position('due by' in o->>'reason') = 0 then
    raise exception 'FAIL  the month in progress could be scored: %', o;
  end if;
  if plb_self_eval(p_rep, v_sheet, v_m, 8, 8)->>'error' is distinct from 'month_not_over' then
    raise exception 'FAIL  the month in progress could be self-evaluated';
  end if;
  if plb_review_due(v_m) <= (v_m + interval '1 month - 1 day')::date then
    raise exception 'FAIL  the review falls due before the month has ended';
  end if;
  raise notice 'PASS  a month is scored once it is over, and its review has a due date after';

  -- --------------------------------------- a missed KPI window, escalated
  o := perf_window_sweep(current_date);
  select count(*) into n from window_miss where kind = 'KPI_NOT_SET' and manager_id = p_boss;
  if n <> 1 then raise exception 'FAIL  the missed KPI window was not recorded once: %', n; end if;
  if not exists (select 1 from person_escalation e where e.about_id = p_boss and e.routed_to = p_top
                  and e.subject like '%KPIs not set for 1 of your team%') then
    raise exception 'FAIL  no escalation about the manager, routed to their manager';
  end if;
  if not exists (select 1 from outbox where recipient = 'wm.boss@example.invalid'
                  and cc_addr = 'wm.top@example.invalid' and subject like 'Overdue:%'
                  and body like '%WM Rep: no KPIs set%') then
    raise exception 'FAIL  the manager was not e-mailed, with their manager copied';
  end if;
  o := perf_window_sweep(current_date);
  if (select count(*) from person_escalation where about_id = p_boss) <> 1
     or (select count(*) from outbox where recipient = 'wm.boss@example.invalid') <> 1 then
    raise exception 'FAIL  running the sweep twice raised it twice';
  end if;
  raise notice 'PASS  a missed KPI window is one escalation and one e-mail, never two';

  -- ------------------------------------ a missed review, once it is due
  o := perf_window_sweep((plb_review_due(v_m) + 1)::date);
  if not exists (select 1 from window_miss w where w.kind = 'REVIEW_NOT_DONE' and w.manager_id = p_boss
                  and w.period = v_m and w.people @> jsonb_build_array(jsonb_build_object('name', 'WM Rep'))) then
    raise exception 'FAIL  an unscored month past its due date was not escalated';
  end if;
  if exists (select 1 from window_miss where kind = 'REVIEW_NOT_DONE' and manager_id = p_top) then
    raise exception 'FAIL  a manager was escalated for a review that was not theirs';
  end if;
  raise notice 'PASS  a review not done by its due date is escalated to the manager''s manager';

  raise notice '--- windows and misses: every assertion passed ---';
end $t$;

rollback;
