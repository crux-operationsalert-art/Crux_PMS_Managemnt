-- What somebody files, at the grain they were asked to file it.
--
-- perf_month is monthly and is the upload surface; it stays as it is. A
-- person told to file daily needs a row per day or each filing overwrites
-- the last, and the month-to-date figure becomes whatever was typed most
-- recently rather than the sum of the month.
--
-- as_of is the day the number is FOR, not the day it was typed. Those are
-- different whenever somebody files Monday's count on Tuesday, which is
-- most Tuesdays.

create table if not exists perf_entry (
  id            uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references perf_assignment(id) on delete cascade,
  as_of         date not null,
  value         numeric not null,
  note          text,
  filed_by      uuid not null references person(id),
  filed_at      timestamptz not null default now(),
  unique (assignment_id, as_of)
);

comment on table perf_entry is
  'One filing against one assignment for one day. as_of is the day the number is for; filed_at is when somebody typed it.';

create index if not exists perf_entry_asof on perf_entry (as_of);

revoke all on table perf_entry from public, anon, authenticated;

-- A parent measure is derived from its parts and must never be typed into,
-- or the total and the parts can disagree -- which is how 93% and 88% became
-- 286% in the design's own note.
create or replace function public.perf_entry_not_on_a_parent()
returns trigger language plpgsql as $fn$
begin
  if exists (select 1 from perf_assignment a
              where a.part_of_id = new.assignment_id) then
    raise exception 'that measure is split into parts; file against the parts and the total follows';
  end if;
  return new;
end $fn$;

drop trigger if exists perf_entry_not_on_a_parent_t on perf_entry;
create trigger perf_entry_not_on_a_parent_t
  before insert or update on perf_entry
  for each row execute function public.perf_entry_not_on_a_parent();
