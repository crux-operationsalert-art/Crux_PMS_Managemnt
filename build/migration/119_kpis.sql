-- =====================================================================
-- 119 · A KPI can be defined
--
-- Applied as migrations a_kpi_can_be_defined,
-- kpi_subtree_respects_the_place_a_chair_is_held_in and
-- crux_app_page_kpis_can_be_set_and_filed, 2026-09-22.
--
-- kpi_definition had been empty since the schema was created, and there was
-- no way to fill it. The API has PUT /kpi/:id/target, which sets a target on
-- a KPI that already exists, and nothing that creates one; the bulk upload
-- has "KPI targets" for the same reason - it presupposes the KPI.
--
-- So the daily count card had nothing to ask anybody for, PMS had nothing to
-- score, and penalty rule P-01 could never fire. This is the half that was
-- missing.
--
-- Two rules the owner settled, enforced in the database rather than in a
-- screen, so a second caller cannot get round them by asking differently:
--   · Nobody defines their own. kpi_target already carries
--     check (set_by <> person_id); the same has to hold one level up, or a
--     person defines the thing their target is set against.
--   · A manager acts on chairs at or below their own (D7).
--
-- Five per person is the agreed shape and is enforced; three mandatory and
-- two optional is shown but not enforced, because a manager adds them one at
-- a time and must not be blocked halfway through.
-- =====================================================================

-- ------------------------------------------------ whose KPIs are mine to set
-- The first cut of this walked the chair tree and stopped there, which put 41
-- people under one branch manager: every field executive, back-office person
-- and team leader in the country, because those chairs sit below Branch
-- Manager and the walk does not know that one chair is held in six places at
-- once. A manager in Pune setting a KPI for a field executive in Patna is not
-- a theoretical problem; it is the first thing that would have happened.
--
-- So where both people have a place recorded, it must be the same place.
-- Where either does not, place cannot narrow anything and the chair
-- relationship stands alone - the same rule used to place chair holders: act
-- on the evidence, and where there is none, do not invent it.
--
-- Measured: a placed branch manager reaches 31 people instead of 41, and that
-- number falls further as the Assignments upload places the rest.
create or replace function kpi_subtree_people(p_actor uuid)
returns table (person_id uuid)
language sql
stable security definer
set search_path to 'public'
as $$
  with mine as (
    select ch.chair_id, ch.seating_id from chair_holder ch
     where ch.person_id = p_actor and ch.to_date is null
  ),
  my_places as (
    select distinct s.scope_label from mine m
     join chair_seating s on s.id = m.seating_id
     where s.scope_label is not null
  ),
  below as (
    select distinct c.id
      from chair c
     where exists (
       with recursive t as (
         select chair_id as id from mine
         union all
         select k.id from chair k join t on k.parent_id = t.id)
       select 1 from t where t.id = c.id)
  )
  select distinct h.person_id
    from chair_holder h
    join person p on p.id = h.person_id
    left join chair_seating s on s.id = h.seating_id
   where h.chair_id in (select id from below)
     and h.to_date is null
     and p.employment_status = 'ACTIVE'
     and p.superseded_by is null
     and h.person_id <> p_actor
     and (
       -- nobody has a place on record, so place cannot decide anything
       not exists (select 1 from my_places)
       or s.scope_label is null
       or s.scope_label in (select scope_label from my_places)
     )
$$;

revoke all on function kpi_subtree_people(uuid) from public, anon, authenticated;

-- kpi_mine, kpi_save and kpi_retire are in the migration ledger under
-- a_kpi_can_be_defined. The guards each one carries, proven by test against
-- real people and cleaned up afterwards:
--
--   defining one for yourself      refused: "Nobody sets their own KPI."
--   defining one outside your tree refused: "chairs at or below your own"
--   a sixth top-level KPI          refused, naming the two ways forward:
--                                  retire one, or make it a sub-category
--   a sub-category of an existing  allowed - it is not one of the five
--   retiring one                   allowed, and then a sixth fits
--
-- A KPI is retired, never deleted: a cycle already scored against it still
-- refers to it, and a score whose KPI has vanished cannot be explained to the
-- person who got it.
--
-- Served by a new edge function, kpi, for the same reason org, wa and cfg
-- have their own.

-- ------------------------------------------------------------- the screen
-- The daily filing box asked for raw JSON - a textarea whose placeholder was
-- {"Field verifications completed": 42}. That only ever worked for somebody
-- who already knew the exact names, which is to say for nobody. It is now one
-- labelled box per KPI, generated from that person's own definitions, each
-- saying its cadence and whether today's figure adds to the period or
-- replaces the period-to-date level. A person with no KPI is told so, rather
-- than shown an empty box they cannot fill.
--
-- The Performance screen also gained the other half: each person below you,
-- their KPIs, and a button to add or retire one. Somebody with nobody below
-- them is told that plainly instead of being shown an empty list.
