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
