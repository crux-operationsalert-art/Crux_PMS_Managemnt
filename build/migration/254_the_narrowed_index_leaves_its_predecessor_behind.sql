-- The index 246 replaced is still enforcing the rule 246 replaced
--
-- Migration 246 narrowed perf_assignment's "one top-level measure per person
-- per cycle" so that a WITHDRAWN row no longer blocks giving the measure back:
--
--   perf_assignment_once_top
--     (cycle_id, person_id, kpi_id)
--     where kpi_id is not null and part_of_id is null
--       and state is distinct from 'WITHDRAWN'
--
-- The new index went in. The one it replaced stayed, renamed _old, still
-- unique and still without the state clause:
--
--   perf_assignment_once_top_old
--     (cycle_id, person_id, kpi_id)
--     where kpi_id is not null and part_of_id is null
--
-- So 246's narrowing had no effect from the day it was applied. Both indexes
-- are unique over the same three columns and the wider one wins every
-- argument: an INSERT that the narrow index would allow is refused by the
-- wide one. Nobody noticed because nothing in the tool tried, until the
-- rebuild-from-baseline suite put the stale index into the baseline and the
-- test that asserts the narrowing went red.
--
-- Migration 250 is what made the tool correct rather than this: perf_assign
-- now REVIVES a withdrawn row instead of inserting a second one, so the
-- insert this index would refuse never happens. That is why this is not
-- urgent, and it is also exactly why it should go. An index that enforces a
-- rule the tool no longer holds is a trap set for whoever next writes an
-- INSERT against this table and reads the index list to learn what is
-- allowed.
--
-- One statement, guarded both ways: it does nothing if the old index is
-- already gone, and it refuses to run at all if the narrowed one is missing,
-- because leaving this table with no uniqueness rule would be worse than
-- leaving it with the wrong one.
--
-- NOT YET APPLIED. The Supabase approval gate in this session refuses every
-- statement containing the word it needs, and that refusal is not something
-- to work around. Run it from the SQL editor, or from any session whose gate
-- allows it.

do $d$
begin
  if exists (select 1 from pg_class where relname = 'perf_assignment_once_top_old') then
    execute 'drop index perf_assignment_once_top_old';
    raise notice 'perf_assignment_once_top_old is gone; 246''s narrowing is '
                 'now the only rule on the table.';
  else
    raise notice 'perf_assignment_once_top_old was already gone.';
  end if;

  if not exists (select 1 from pg_class where relname = 'perf_assignment_once_top') then
    raise exception 'Migration 254: the narrowed index is not there, so this '
                    'would leave perf_assignment with no uniqueness rule at '
                    'all. Apply 246 first.';
  end if;
end
$d$;
