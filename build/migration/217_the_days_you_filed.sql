-- 217 · The days you filed
--
-- The blueprint's Performance screen has a strip of fourteen day cells above
-- the KPI list -- "Your last fourteen days" -- with a note and a legend. A
-- daily cadence you cannot see the record of is just a form, which is the
-- point it is making.
--
-- Nothing in this database answers it. perf_history() is per-measure and
-- monthly: six months of one KPI, for setting a target against what actually
-- happened. The strip is a different question -- on which DAYS did this person
-- file anything at all -- and it is one query nobody had written.
--
-- It counts days, not numbers, and deliberately says nothing about whether a
-- day's figure was good. A streak is a record of showing up. Reading it as
-- performance is the mistake the Scorecard Guide warns about in another
-- context: "a target you cannot measure is an opinion with a number on it".
--
-- Working days come from the same calendar the dispute window runs on, so a
-- Sunday is not a gap in somebody's run and a national holiday is not either.

create or replace function public.perf_filed_days(p_person uuid, p_days int default 14,
                                                 p_to date default current_date)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $fn$
  with span as (
    select generate_series(p_to - (greatest(p_days, 1) - 1), p_to, interval '1 day')::date as d
  ),
  filed as (
    select distinct e.as_of
      from perf_entry e
      join perf_assignment a on a.id = e.assignment_id
     where a.person_id = p_person
       and e.as_of between p_to - (greatest(p_days, 1) - 1) and p_to
  ),
  mark as (
    select s.d,
           is_working_day(s.d, null) as wd,
           (f.as_of is not null)     as ok
      from span s left join filed f on f.as_of = s.d
  ),
  -- The most recent working day nobody filed on. Everything after it is the
  -- current run; a Sunday or a national holiday cannot end one.
  gap as (select max(d) as d from mark where wd and not ok)
  select jsonb_build_object(
    'from', (select min(d) from mark),
    'to',   (select max(d) from mark),
    'days', (select coalesce(jsonb_agg(jsonb_build_object(
                      'day', m.d, 'dow', to_char(m.d, 'Dy'), 'dd', to_char(m.d, 'FMDD'),
                      'working', m.wd, 'filed', m.ok) order by m.d), '[]'::jsonb)
               from mark m),
    'filedDays',   (select count(*) from mark where ok),
    'workingDays', (select count(*) from mark where wd),
    'run',         (select count(*) from mark m, gap
                     where m.ok and (gap.d is null or m.d > gap.d)));
$fn$;

comment on function public.perf_filed_days(uuid, int, date) is
  'Which days in the last fortnight this person filed anything, for the strip '
  'the design puts above the KPI list. Counts days, not numbers: a run is a '
  'record of showing up and says nothing about whether the figures were good. '
  'A run is only broken by a WORKING day nobody filed on, so a Sunday is not a '
  'gap and nor is a national holiday.';

grant execute on function public.perf_filed_days(uuid, int, date) to authenticated;

-- ------------------------------------------------------------------ checks

do $do$
declare o jsonb; v_any uuid;
begin
  select id into v_any from person where employment_status = 'ACTIVE' and superseded_by is null limit 1;

  o := perf_filed_days(v_any, 14);
  if jsonb_array_length(o->'days') <> 14 then
    raise exception '217: asked for fourteen days, got %', jsonb_array_length(o->'days');
  end if;
  if (o->>'filedDays')::int <> 0 then
    raise exception '217: nobody has filed anything, yet % days came back filed', o->>'filedDays';
  end if;
  if (o->>'run')::int <> 0 then
    raise exception '217: an empty fortnight produced a run of %', o->>'run';
  end if;
  if (o->>'workingDays')::int not between 1 and 14 then
    raise exception '217: % working days in a fortnight is not possible', o->>'workingDays';
  end if;

  -- one day is one day, not an error
  o := perf_filed_days(v_any, 1);
  if jsonb_array_length(o->'days') <> 1 then
    raise exception '217: a single day came back as % days', jsonb_array_length(o->'days');
  end if;

  raise notice '217: the fortnight strip has a source -- % working days in the last fourteen',
    (perf_filed_days(v_any, 14)->>'workingDays');
end $do$;
