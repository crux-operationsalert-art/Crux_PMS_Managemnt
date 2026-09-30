-- Undo the demo data of 30 September 2026
--
-- Everything the demo needed was added on one day and comes out in one
-- transaction. Nothing here touches a function, a migration, a person's
-- identity, or anything that existed before that morning.
--
-- Pure SQL, no psql meta-commands, so it runs from any console or from the
-- Supabase SQL editor. Safe to run twice: every step finds nothing the
-- second time.
--
-- Run build/demo/preview.sql first if you want to see what it will remove.
--
-- What is NOT removed, because it is not demo data:
--   * the goal sheets issued before this day, and the 728 monthly targets
--   * migrations 229-235 and everything they built
--   * anybody's account, chair or reporting line
--   * Google sign-in, which never depended on any of this

begin;

-- 1. The nine thousand filings, tagged on the way in for exactly this.
delete from perf_entry where note = 'Seeded for the demo';

-- 2. September's scores. The one step that removes a judgement rather than
--    an arithmetic result -- every one of them was written by the demo and
--    none by a manager doing a real review.
delete from plb_month_score where month = date '2026-09-01';

-- 3. The quarterly actuals, back to blank. plb_actual_from_perf computed
--    them from the filings in step 1, so with those gone they are
--    unsupported anyway.
update plb_goal_kpi g set actual_value = null
  from plb_goal_sheet s
 where s.id = g.sheet_id and s.quarter = date '2026-07-01';

-- 4. The zero targets put back. "No chair stays vacant beyond a quarter"
--    means zero; it was given a number only so the bonus would compute.
update plb_goal_kpi g set target_value = 0
  from kpi_definition d, plb_goal_sheet s
 where d.id = g.kpi_id and s.id = g.sheet_id
   and s.quarter = date '2026-07-01'
   and d.unit like '%target zero%';

-- 5. The illustrative rupee figures, invented to make the demo show money.
update plb_goal_sheet set target_plb_inr = 0
 where quarter = date '2026-07-01';

-- 6. No goal sheet is deleted, deliberately.
--
--    The first draft of this file removed "the sheet created on the demo
--    day", meaning the Managing Director's, which he had been missing. Every
--    one of the 101 Q3 sheets was created that day, so that step would have
--    deleted all of them. The guard below caught it -- the count fell under
--    its floor and the transaction rolled back -- which is the whole reason
--    the guard is there.
--
--    The MD's sheet stays. Steps 3 and 5 already blank its actuals and its
--    rupee figure along with every other sheet's, so nothing demo-shaped is
--    left on it, and a chair holder having a goal sheet is a gap closed
--    rather than a prop to strike.

-- 7. The fourteen demo passwords, and every session opened with one.
delete from auth_session where person_id in (
  select id from person where password_hash is not null);
update person set password_hash = null, password_salt = null
 where password_hash is not null;

-- ------------------------------------------------------------- the guard
-- A cleanup that half-ran is worse than one that did not run, because the
-- next person believes it. This refuses to commit unless every step took
-- AND nothing that predates the demo has gone with it.
do $guard$
declare n int;
begin
  select count(*) into n from perf_entry where note = 'Seeded for the demo';
  if n > 0 then raise exception 'cleanup: % seeded filings remain', n; end if;

  select count(*) into n from plb_month_score where month = date '2026-09-01';
  if n > 0 then raise exception 'cleanup: % September scores remain', n; end if;

  select count(*) into n from person where password_hash is not null;
  if n > 0 then raise exception 'cleanup: % passwords remain', n; end if;

  select count(*) into n from plb_goal_sheet
   where quarter = date '2026-07-01' and target_plb_inr > 0;
  if n > 0 then raise exception 'cleanup: % rupee targets remain', n; end if;

  select count(*) into n from plb_goal_sheet;
  if n < 190 then
    raise exception 'cleanup took goal sheets it should not have: % left', n;
  end if;

  select count(*) into n from perf_assignment;
  if n < 700 then
    raise exception 'cleanup took monthly targets: % left', n;
  end if;

  select count(*) into n from person where employment_status = 'ACTIVE';
  if n < 600 then
    raise exception 'cleanup took people: % left', n;
  end if;

  raise notice 'cleanup: every step took, and nothing older than the demo was touched';
end $guard$;

commit;
