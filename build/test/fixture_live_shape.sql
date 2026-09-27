-- A local Postgres brought up to the shape the LIVE database is actually in,
-- so migrations 190-198 can be executed and their behaviour tested before
-- they are applied for real.
--
-- READ THIS FIRST, because it is the reason this file has to exist.
--
-- build/migration cannot rebuild the database. Fifty-one of its files carry
-- no executable SQL at all: from 134 onwards they are notes that record what
-- was applied through the MCP tool, with an "Applied as:" header naming the
-- migration, and the SQL itself was never written back. So the live schema
-- from 134 on exists only inside Supabase, and a local replica has to be
-- reconstructed from the next best evidence.
--
-- Everything below is reconstructed from something that is running in
-- production, not from memory:
--
--   audit_entry.entity_ref     four deployed Edge Functions insert it
--                              (api, hr, ops, plb -- shim.ts line 39)
--   outbox.template_key        the same four, shim.ts line 161
--   outbox.recipient           "
--   job_run.state              migration 115, which is applied and whose
--                              penalty sweep writes it every night
--   kpi_definition.cadence     read off the live table earlier in this work
--   kpi_definition.accrual     "
--   holiday.confirmed          migration 92's holiday_applies filters on it
--
-- plb_wd_after is the one thing here that is NOT reconstructed from running
-- code, because there is no running code to reconstruct it from: migration
-- 168 announces it in a comment and defines nothing. What is below is a
-- stand-in that matches the behaviour 168 describes -- N working days after
-- a date, counted where the person is. It is good enough to test that
-- perf_cycle_open computes two sensible window dates. It is NOT evidence
-- about the real signature, and 194 should be applied with that in mind.

-- ------------------------------------------------- what the live tables have
alter table audit_entry add column if not exists entity_ref text;
alter table outbox      add column if not exists template_key text;
alter table outbox      add column if not exists recipient text;
alter table outbox      alter column kind    drop not null;
alter table outbox      alter column to_addr drop not null;
alter table job_run     add column if not exists state text;
alter table holiday     add column if not exists confirmed boolean not null default false;
alter table person      add column if not exists employee_type text;

-- The real labels, read off the live project. They are not the ones a
-- reader would guess: the accrual enum is ADDS/REPLACES, not SUM/LEVEL, and
-- the cadence enum has no day-of-month at all -- which is migration 201.
do $$ begin
  create type kpi_cadence as enum ('DAILY','WEEKLY','MONTHLY','QUARTERLY');
exception when duplicate_object then null; end $$;
do $$ begin
  create type kpi_accrual as enum ('ADDS','REPLACES');
exception when duplicate_object then null; end $$;

alter table kpi_definition add column if not exists cadence kpi_cadence;
alter table kpi_definition add column if not exists accrual kpi_accrual;

-- ------------------------------------------------------- the working clock
-- Verbatim from migration 92, which is a file that does carry its SQL.
create or replace function holiday_is_national(p_applies text) returns boolean
language sql immutable as $$
  select p_applies is null
      or btrim(lower(p_applies)) in ('all india', 'national', 'india', 'pan india');
$$;

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

-- Verbatim from migration 115. It is in that file, but 115 does not apply
-- cleanly against a database built from schema.sql alone, so a clean local
-- rebuild does not get it and perf_due falls over on its first line.
create or replace function person_centre(p_person uuid)
returns text language sql stable security definer set search_path to 'public' as $$
  select case when count(*) = 1 then min(city) end
  from (select distinct g.name as city
          from coverage_rule cr
          join branch b on b.id = cr.branch_id
          join geo_node g on g.id = b.geo_node_id
         where cr.person_id = p_person and g.level = 'CITY') q
$$;

-- Verbatim from migration 115.
create or replace function is_working_day(p_day date, p_centre text default null)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select case
    when extract(isodow from p_day) = 7 then false
    when extract(isodow from p_day) = 6
      and lower(coalesce((select value from app_setting where key='sat'),'')) like 'no%'
      then false
    else not holiday_applies(p_day, p_centre)
  end
$$;

insert into app_setting (key, value, plain_language, group_name)
values ('sat', 'Yes - half day', 'Saturday is a half day.', 'Working week')
on conflict (key) do nothing;

-- The stand-in. See the note at the top of this file.
create or replace function plb_wd_after(p_from date, p_days int, p_centre text)
returns date language plpgsql stable set search_path to 'public' as $$
declare d date := p_from; n int := 0; guard int := 0;
begin
  while n < p_days and guard < 120 loop
    d := d + 1; guard := guard + 1;
    if is_working_day(d, p_centre) then n := n + 1; end if;
  end loop;
  return d;
end $$;

-- pms_cfg and the working-hours clock, verbatim from migration 92. The same
-- reason as person_centre above: 92 is a file that carries its SQL, but it
-- does not apply cleanly against a database built from schema.sql alone, so
-- a clean local rebuild does not get these and request_raise falls over on
-- the line that works out when a request is due.
create or replace function pms_cfg(p_key text, p_default numeric)
returns numeric language sql stable set search_path to 'public' as $$
  select coalesce((select value::numeric from app_setting where key = p_key), p_default);
$$;

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

insert into app_setting (key, value, plain_language, group_name) values
  ('day_start','10:00','The working day starts at 10.','Working week'),
  ('day_end','19:00','The working day ends at 19:00.','Working week'),
  ('sat_hours','4','Hours counted on a Saturday.','Working week')
on conflict (key) do nothing;

-- next_ref, read off the live project with pg_get_functiondef because it is
-- in no migration file at all -- one more thing that exists only inside
-- Supabase. ref_counter is created here for the same reason.
create table if not exists ref_counter (
  prefix  text primary key,
  last_no bigint not null default 0
);

create or replace function next_ref(p_prefix text, p_width integer default 5)
returns text language plpgsql set search_path to 'public' as $fn$
declare v bigint;
begin
  insert into ref_counter (prefix, last_no) values (p_prefix, 0)
    on conflict (prefix) do nothing;
  update ref_counter set last_no = last_no + 1
   where prefix = p_prefix returning last_no into v;
  return p_prefix || '-' || lpad(v::text, p_width, '0');
end $fn$;
