-- =====================================================================
-- The PMS data model: a manager sets KPIs and targets each month, people
-- file numbers on the cadence they were given, and the numbers climb.
-- =====================================================================
--
-- WHAT IS ALREADY THERE, and is not rebuilt here:
--
--   kpi_definition(id, chair_id, person_id, name, unit, active, mandatory,
--                  position, parent_id, cadence, accrual)
--       The catalogue. It ALREADY carries parent_id (so a measure can have
--       sub-measures), person_id (so a measure can be one person's), and
--       cadence and accrual as enums. This model uses all four rather than
--       inventing a second vocabulary beside them.
--
--   perf_month(person_id, period, kpi_id, kpi_name, sub_category, unit,
--              target_value, achieved, mtd_achieved, source, ...)
--       8,404 rows of loaded history. It is the UPLOAD surface and stays
--       exactly as it is. Nothing here writes to it.
--
--   plb_goal_sheet / plb_goal_kpi
--       The quarterly bonus sheet, proved against the five published
--       worked examples. The quarterly scorecard keeps using it; what
--       changes is where its KPI actuals come from.
--
-- WHAT WAS MISSING, and is what these tables are:
--
--   1. The ACT of assigning. perf_month has a target_value but no record
--      of who set it, when, inside which window, or what it rolls into.
--   2. The WINDOW itself. "At the start of the month" has to be a date
--      range somebody can see and an administrator can move, not a
--      convention.
--   3. The ROLL-UP LINK. "which of his own KPIs should this map to" is an
--      edge between two people's assignments, and there was nowhere to
--      put it.
--   4. A grain below the month. perf_month is monthly; daily, weekly and
--      day-of-month filings need their own rows or they overwrite each
--      other.

-- ------------------------------------------------------------ the window
create table if not exists perf_cycle (
  id            uuid primary key default gen_random_uuid(),
  period_start  date not null,
  period_kind   text not null default 'MONTH'
                  check (period_kind in ('MONTH','QUARTER')),
  -- when a manager may set KPIs and targets
  assign_opens  date not null,
  assign_closes date not null,
  -- after this, entries for the period are refused
  entry_closes  date not null,
  state         text not null default 'OPEN'
                  check (state in ('OPEN','ASSIGNED','ENTRY','SCORING','CLOSED')),
  opened_by     uuid references person(id),
  created_at    timestamptz not null default now(),
  unique (period_start, period_kind)
);

comment on table perf_cycle is
  'One month or quarter, and the two windows inside it: when a manager may set KPIs, and when the people they set them for may still file numbers.';

create index if not exists perf_cycle_period on perf_cycle (period_kind, period_start desc);

revoke all on table perf_cycle from public, anon, authenticated;
