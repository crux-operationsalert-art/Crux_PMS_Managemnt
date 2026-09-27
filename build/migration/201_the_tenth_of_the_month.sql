-- "sets when I should be updating it daily, weekly, 10th day, 15th day,
--  monthly (date) etc"
--
-- kpi_cadence is (DAILY, WEEKLY, MONTHLY, QUARTERLY). There is no
-- day-of-the-month in it at all, so the one the owner named twice -- the
-- 10th, the 15th -- could not be chosen. perf_due already knows how to
-- handle it and perf_assignment already carries cadence_day to say which
-- day; the only thing missing was a label to put in the box.
--
-- Found by reading the live enum while testing migration 200, after the
-- local harness had been built with labels a reader would guess rather than
-- the ones the project actually has.
--
-- Adding a value to an enum is additive: nothing that reads the old four
-- changes, and nothing has to be rewritten. MONTH_END goes in beside it
-- because "the last working day" and "the 25th" are different instructions
-- and MONTHLY does not say which one it means -- perf_due treats a bare
-- MONTHLY as month end, which is a guess it should not have to make.

alter type kpi_cadence add value if not exists 'DAY_OF_MONTH' after 'WEEKLY';
alter type kpi_cadence add value if not exists 'MONTH_END' after 'MONTHLY';
