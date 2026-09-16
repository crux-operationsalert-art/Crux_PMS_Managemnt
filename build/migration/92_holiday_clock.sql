-- =====================================================================
-- 92 · R-03 · THE STRIKE CLOCK COULD NOT READ THE OWNER'S HOLIDAY LIST.
--
-- working_hours_after() tested holidays like this:
--
--     or exists (select 1 from holiday h where h.day = cur::date and h.confirmed)
--
-- Location-blind, and confirmed-only. Two consequences, both live:
--
--   * 37 of the owner's 43 RBI 2026 dates are per banking centre — Mumbai,
--     Kolkata, Aizawl and 27 more. The clock had no way to ask "where?", so
--     they sat unconfirmed and counted for nothing. Only the 6 All-India dates
--     moved a deadline.
--   * Had they been confirmed, it would have been worse: a festival observed
--     only in Aizawl would have stopped the clock on a Mumbai case, because
--     any confirmed row anywhere stopped every clock.
--
-- R-03 drives next_chase_at, which drives strikes, which drive penalties. A
-- deadline computed against the wrong calendar is money.
--
-- The fix is an overload that takes a place, not a rewrite of the callers:
--   holiday_applies(day, centre)           national, or that centre
--   working_hours_after(from, hrs, centre) the location-aware clock
--   working_hours_after(from, hrs)         unchanged signature, NEW meaning:
--                                          national holidays only
--
-- That last line is a deliberate behaviour change, which is why it is written
-- down. If the caller cannot say where the work is, the only holiday that can
-- honestly be applied is a national one.
--
-- Proved, not assumed — cutover_check 'R-03 holiday clock is location-aware':
--   Republic Day (All India)  from Guwahati  -> next day      skipped
--   1 Jan (Aizawl and 7 more) in Aizawl      -> Sat 3 Jan     skipped, and so
--                                                             was 2 Jan, which
--                                                             Aizawl also has
--   the same 1 Jan            in Guwahati    -> same day       worked
-- =====================================================================

-- 'National' and 'All India' are the same claim in two vocabularies: the RBI
-- list says one, September's test CSVs said the other.
create or replace function holiday_is_national(p_applies text) returns boolean
language sql immutable as $$
  select p_applies is null
      or btrim(lower(p_applies)) in ('all india', 'national', 'india', 'pan india');
$$;

-- applies_to holds a comma-separated list of banking centres.
create or replace function holiday_applies(p_day date, p_centre text)
returns boolean language sql stable set search_path to 'public' as $$
  select exists (
    select 1 from holiday h
    where h.day = p_day
      and h.confirmed
      and ( holiday_is_national(h.applies_to)
            or ( p_centre is not null and exists (
                   select 1 from unnest(string_to_array(h.applies_to, ',')) c
                   where lower(btrim(c)) = lower(btrim(p_centre)) ) ) )
  );
$$;

-- Which RBI centre a branch answers to. Identity matches are seeded; anything
-- else is a question for the owner rather than a guess, because "does a Pune
-- branch observe Mumbai's centre holidays?" is a business answer, not a
-- geographic one. An unmapped city falls back to national-only, which is the
-- conservative reading: it never invents a day off.
create table if not exists holiday_centre_alias (
  city     text primary key,
  centre   text not null,
  noted_by text,
  noted_at timestamptz not null default now()
);
comment on table holiday_centre_alias is
  'Maps a branch city onto the RBI banking centre whose holiday list it follows. Only exact name matches are seeded; the rest are asked about, because whether a non-centre city observes a nearby centre''s holidays is the owner''s call.';

insert into holiday_centre_alias (city, centre, noted_by)
select distinct g.name, c.centre, 'identity match, seeded'
from branch b
join geo_node g on g.id = b.geo_node_id and g.level = 'CITY'
join (select distinct btrim(x) centre
        from holiday h, unnest(string_to_array(h.applies_to, ',')) x
       where h.source = 'RBI 2026 (owner)' and btrim(x) <> 'All India') c
  on lower(c.centre) = lower(g.name)
on conflict (city) do nothing;

create or replace function branch_centre(p_branch uuid)
returns text language sql stable set search_path to 'public' as $$
  select a.centre
  from branch b
  join geo_node g on g.id = b.geo_node_id
  join holiday_centre_alias a on lower(a.city) = lower(g.name)
  where b.id = p_branch;
$$;

-- The location-aware clock. Same arithmetic as the two-argument version; the
-- only difference is which holidays it believes.
create or replace function working_hours_after(
  p_from timestamptz, p_hours numeric, p_centre text)
returns timestamptz language plpgsql stable set search_path to 'public' as $$
declare
  cur     timestamptz := p_from;
  left_   numeric     := p_hours;
  open_h  int := coalesce((select split_part(value, ':', 1)::int from app_setting where key = 'day_start'), 10);
  close_h int := coalesce((select split_part(value, ':', 1)::int from app_setting where key = 'day_end'), 19);
  sat_h   numeric := pms_cfg('sat_hours', 4);
  sat_on  boolean := coalesce((select value ilike 'y%' from app_setting where key = 'sat'), true);
  day_cap numeric;
  avail   numeric;
begin
  while left_ > 0 loop
    if extract(dow from cur) = 0
       or (extract(dow from cur) = 6 and not sat_on)
       or holiday_applies(cur::date, p_centre) then
      cur := date_trunc('day', cur) + interval '1 day' + (open_h || ' hours')::interval;
      continue;
    end if;
    day_cap := case when extract(dow from cur) = 6 then sat_h else close_h - open_h end;
    if cur::time < (open_h || ':00')::time then
      cur := date_trunc('day', cur) + (open_h || ' hours')::interval;
    end if;
    avail := least(day_cap, extract(epoch from ((date_trunc('day', cur) + ((open_h + day_cap) || ' hours')::interval) - cur)) / 3600.0);
    if avail <= 0 then
      cur := date_trunc('day', cur) + interval '1 day' + (open_h || ' hours')::interval;
      continue;
    end if;
    if left_ <= avail then
      return cur + (left_ || ' hours')::interval;
    end if;
    left_ := left_ - avail;
    cur := date_trunc('day', cur) + interval '1 day' + (open_h || ' hours')::interval;
  end loop;
  return cur;
end $$;

-- The two-argument form now delegates, with no centre: national holidays only.
create or replace function working_hours_after(p_from timestamptz, p_hours numeric)
returns timestamptz language sql stable set search_path to 'public' as $$
  select working_hours_after(p_from, p_hours, null::text);
$$;

-- The owner's RBI list is the official one, and the clock can now read a
-- centre, so the 37 per-centre dates stop being inert. Only the owner's own
-- source is confirmed; September's test CSVs are left as they are and asked
-- about instead.
update holiday set confirmed = true
where source = 'RBI 2026 (owner)' and not confirmed;
