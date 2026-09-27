-- The act of assigning, which perf_month never recorded.
--
-- Two different edges live on this table and they are deliberately NOT the
-- same column, because conflating them is how a roll-up starts
-- double-counting:
--
--   part_of_id    this row is a PART of another row of the SAME person.
--                 "Case Target" is the measure; "Case Target, SBI" and
--                 "Case Target, HDFC" are its parts. A parent's value is
--                 derived from its parts and is never typed in.
--
--   rolls_into_id this row CONTRIBUTES to a row belonging to somebody
--                 else -- the manager. This is the edge that makes numbers
--                 climb to the org level.
--
-- One column for both would mean a parent could not tell "my own splits"
-- from "my team's contributions", and would add them twice.

create table if not exists perf_assignment (
  id            uuid primary key default gen_random_uuid(),
  cycle_id      uuid not null references perf_cycle(id) on delete cascade,
  person_id     uuid not null references person(id),

  -- the catalogue measure, and a snapshot of it. The snapshot is the point:
  -- a measure renamed in March must not silently rewrite January's sheet.
  kpi_id        uuid references kpi_definition(id),
  name          text not null,
  unit          text,

  target_value  numeric,
  weight_pct    numeric check (weight_pct is null or (weight_pct > 0 and weight_pct <= 100)),

  -- when this person files. cadence_day is the day of the month for
  -- DAY_OF_MONTH and the ISO weekday for WEEKLY; null otherwise.
  cadence_day   int check (cadence_day is null or cadence_day between 1 and 28),

  part_of_id    uuid references perf_assignment(id) on delete cascade,
  split_kind    text check (split_kind in ('CLIENT','BRANCH','PLACE','OTHER')),
  split_ref     uuid,
  split_label   text,

  rolls_into_id uuid references perf_assignment(id) on delete set null,

  set_by        uuid not null references person(id),
  set_at        timestamptz not null default now(),
  state         text not null default 'ISSUED'
                  check (state in ('DRAFT','ISSUED','ACKNOWLEDGED','LOCKED')),

  -- which row last month this was copied from, so "carry forward and only
  -- change the target" is a fact about the row rather than a guess
  carried_from_id uuid references perf_assignment(id) on delete set null,
  note          text,

  constraint perf_assignment_not_its_own_part  check (part_of_id is distinct from id),
  constraint perf_assignment_not_its_own_parent check (rolls_into_id is distinct from id),
  -- a split has to say what it is a split OF and what it is a split BY
  constraint perf_assignment_split_is_complete check (
    (split_kind is null and split_ref is null and part_of_id is null)
    or (split_kind is not null and part_of_id is not null))
);

comment on table perf_assignment is
  'One KPI given to one person for one cycle: the target, when they file, which of their own measures it is a part of, and which of their manager''s measures it climbs into.';

-- The same measure, split the same way, must not be assigned twice in one
-- cycle. Two nulls are distinct in Postgres, so an unsplit row needs its own
-- index or the constraint would not bind it.
create unique index if not exists perf_assignment_once
  on perf_assignment (cycle_id, person_id, kpi_id, split_ref)
  where kpi_id is not null and split_ref is not null;

create unique index if not exists perf_assignment_once_unsplit
  on perf_assignment (cycle_id, person_id, kpi_id)
  where kpi_id is not null and split_ref is null;

create index if not exists perf_assignment_person  on perf_assignment (person_id, cycle_id);
create index if not exists perf_assignment_rollup  on perf_assignment (rolls_into_id)
  where rolls_into_id is not null;
create index if not exists perf_assignment_part    on perf_assignment (part_of_id)
  where part_of_id is not null;

revoke all on table perf_assignment from public, anon, authenticated;

-- cadence reuses the enum kpi_definition already has rather than inventing a
-- second vocabulary beside it. The type is discovered rather than named, so
-- this cannot drift from the catalogue.
do $$
declare t text;
begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'perf_assignment' and column_name = 'cadence') then
    select c.udt_name into t from information_schema.columns c
     where c.table_name = 'kpi_definition' and c.column_name = 'cadence';
    if t is null then
      raise exception 'kpi_definition.cadence is gone; this model was written against it';
    end if;
    execute format('alter table perf_assignment add column cadence %I', t);
  end if;
end $$;

-- A part must belong to the same person and the same cycle as its parent, and
-- a roll-up must cross to somebody else. Neither can be said in a CHECK,
-- because both look at another row.
create or replace function public.perf_assignment_edges()
returns trigger language plpgsql as $fn$
declare p perf_assignment;
begin
  if new.part_of_id is not null then
    select * into p from perf_assignment where id = new.part_of_id;
    if p.person_id <> new.person_id then
      raise exception 'a split belongs to the same person as the measure it splits';
    end if;
    if p.cycle_id <> new.cycle_id then
      raise exception 'a split belongs to the same cycle as the measure it splits';
    end if;
    if p.part_of_id is not null then
      raise exception 'a split cannot itself be split; one level is the whole idea';
    end if;
  end if;

  if new.rolls_into_id is not null then
    select * into p from perf_assignment where id = new.rolls_into_id;
    if p.person_id = new.person_id then
      raise exception 'a measure climbs into somebody else''s; use part_of_id for your own splits';
    end if;
  end if;
  return new;
end $fn$;

drop trigger if exists perf_assignment_edges_t on perf_assignment;
create trigger perf_assignment_edges_t
  before insert or update on perf_assignment
  for each row execute function public.perf_assignment_edges();
