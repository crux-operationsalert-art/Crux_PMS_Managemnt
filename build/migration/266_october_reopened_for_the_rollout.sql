-- October's KPI window is reopened to 31 October, for the rollout
--
-- It shut on the 15th (256 had already moved it from the 7th). Since then
-- every manager's Performance mapping has been read-only -- no weight or
-- target box, no Edit, no +, no Remove -- because perf_assign,
-- perf_assign_edit and perf_assign_remove refuse after assign_closes, and
-- 259 made the panel stop offering what they refuse. The owner, 16 Oct:
-- "the option to edit the KPIs is gone, tool is not allowing me or has an
-- easy direct option to edit it" -- and, asked, chose to reopen October to
-- the 31st. October's scorecards were only reset on the 14th (264) and
-- reached 103 people that day; a window that shuts the next morning leaves
-- nobody time to correct them.
--
-- Through perf_cycle_extend, so who reopened it and why is recorded. The
-- five-working-day rule is untouched: November opens with it.
do $do$
declare o jsonb;
  v_admin uuid := (select id from person where work_email = 'operations.alert@cruxindia.co.in');
  v_cycle uuid := (select id from perf_cycle where period_start = date '2026-10-01');
begin
  if (select assign_closes from perf_cycle where id = v_cycle) >= date '2026-10-31' then
    raise notice 'Migration 266: October already runs to the 31st.';
    return;
  end if;
  o := perf_cycle_extend(v_admin, v_cycle, date '2026-10-31',
         'Rollout: October''s scorecards were reset from the business plan on 14 Oct (264) '
         || 'and sent to 103 people that day; managers need the month to correct them. '
         || 'Owner''s decision, 16 Oct.');
  if o->>'error' is not null then
    raise exception 'Migration 266: October could not be reopened: %', o;
  end if;
  if (select assign_closes from perf_cycle where id = v_cycle) <> date '2026-10-31' then
    raise exception 'Migration 266: the window did not move.';
  end if;
  raise notice 'Migration 266: October''s KPIs can be set until 31 October.';
end
$do$;
