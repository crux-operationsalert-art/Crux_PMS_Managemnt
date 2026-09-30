-- What build/demo/cleanup.sql would remove. Writes nothing.
--
-- Run this before the cleanup and again after it: every count should be a
-- number before and zero after, except the last two, which must NOT move.

select 'filings seeded for the demo' as what,
       (select count(*) from perf_entry
         where note = 'Seeded for the demo') as rows,
       'goes to 0' as after
union all
select 'September scores',
       (select count(*) from plb_month_score where month = date '2026-09-01'),
       'goes to 0'
union all
select 'quarterly actuals on Q3 sheets',
       (select count(*) from plb_goal_kpi g join plb_goal_sheet s on s.id = g.sheet_id
         where s.quarter = date '2026-07-01' and g.actual_value is not null),
       'goes to 0'
union all
select 'illustrative rupee targets',
       (select count(*) from plb_goal_sheet
         where quarter = date '2026-07-01' and target_plb_inr > 0),
       'goes to 0'
union all
select 'zero targets overwritten for the demo',
       (select count(*) from plb_goal_kpi g
          join kpi_definition d on d.id = g.kpi_id
          join plb_goal_sheet s on s.id = g.sheet_id
         where s.quarter = date '2026-07-01'
           and d.unit like '%target zero%' and g.target_value <> 0),
       'goes to 0'
union all
select 'demo passwords',
       (select count(*) from person where password_hash is not null),
       'goes to 0'
union all
-- The two that prove the cleanup did not overreach.
select 'goal sheets in total  (MUST NOT MOVE)',
       (select count(*) from plb_goal_sheet), 'unchanged'
union all
select 'monthly targets in total  (MUST NOT MOVE)',
       (select count(*) from perf_assignment), 'unchanged';
