-- Two constraints on perf_assignment contradicted each other, and the table
-- would have refused a row its own CHECK says is legal.
--
-- Found by running 190-198 against a local Postgres and actually splitting a
-- measure. The insert was refused by perf_assignment_once_unsplit.
--
-- 191 wrote the uniqueness in terms of split_ref:
--
--   perf_assignment_once         (cycle, person, kpi, split_ref)
--                                where kpi_id is not null and split_ref is not null
--   perf_assignment_once_unsplit (cycle, person, kpi)
--                                where kpi_id is not null and split_ref is null
--
-- but the CHECK in the same table defines a split by part_of_id, and says
-- nothing about split_ref at all:
--
--   check ((split_kind is null and split_ref is null and part_of_id is null)
--          or (split_kind is not null and part_of_id is not null))
--
-- So a split by something that is not a row in another table -- by a label
-- rather than by an id: "walk-ins", "over the counter", a client the tool
-- does not hold -- passes the CHECK and then collides with its own PARENT on
-- the unsplit index, because both have a null split_ref and the same
-- (cycle, person, kpi). The first person to split a measure by anything
-- other than a client id would have been told their KPI already existed.
--
-- The fix is to say what was meant: a TOP-LEVEL measure is one per person
-- per measure per cycle, and a SPLIT is one per parent per label. part_of_id
-- is what makes a row a split -- it is what the CHECK uses, what the trigger
-- uses, and what perf_value() walks -- so it is what the indexes use too.
--
-- And the CHECK is tightened: a split has to be identifiable by something.
-- A split with neither a ref nor a label cannot be drawn on a screen, cannot
-- be told apart from its siblings, and is not a split anybody meant.

drop index if exists perf_assignment_once;
drop index if exists perf_assignment_once_unsplit;

create unique index if not exists perf_assignment_once_top
  on perf_assignment (cycle_id, person_id, kpi_id)
  where kpi_id is not null and part_of_id is null;

create unique index if not exists perf_assignment_once_split
  on perf_assignment (part_of_id, coalesce(split_ref::text, lower(btrim(split_label))))
  where part_of_id is not null;

alter table perf_assignment drop constraint if exists perf_assignment_split_is_named;
alter table perf_assignment add constraint perf_assignment_split_is_named
  check (part_of_id is null
         or split_ref is not null
         or coalesce(btrim(split_label), '') <> '');
