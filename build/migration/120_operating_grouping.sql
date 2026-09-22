-- =====================================================================
-- 120 · The operating grouping, and what it fixes
--
-- Applied 2026-09-22 as migrations the_operating_grouping_from_the_zonal_tracker,
-- assignments_name_a_location_not_a_compass_point, client_contacts_are_not_staff,
-- nothing_messages_a_client_contact_as_staff,
-- an_administrator_edits_the_operating_grouping and
-- crux_app_page_locations_on_the_configuration_screen.
--
-- The owner sent the Live Zonewise Monthly Business Tracker and said the
-- places the tool was using were wrong. They were. This is what reading the
-- tracker's own formulas established, and what changed because of it.
--
-- ---------------------------------------------------------------------
-- 1 · WHERE THE REAL GROUPING LIVES
--
-- The four roll-up rows at the bottom of Main Tracker read
--     =SUMIF(C4:C526, C529, E4:E526)
-- grouping by column C - a tag that appears only on the "Total <zone>" rows.
-- So the shape is: compass group, holding zones, holding locations, holding
-- one row per client. Four groups, fourteen zones, twenty-eight locations.
--
-- The places the tool had - North, North East & East, other West locations,
-- Pune, South, Thane - came from suffixes on chair titles in the operating
-- structure document. They are not how the business is grouped, Pune is a
-- location inside Rest Of Maharashtra rather than a place of its own, and
-- Thane does not appear in the tracker at all.
--
-- This cannot be folded into geo_node. That tree is Crux Zone -> State ->
-- City; this one crosses states on purpose ("Bengaluru + Rest Of Karnataka +
-- Kerela" is one operating unit over three states). They answer two different
-- questions - where a branch is, and who runs it - so they are two trees.
--
-- Seeded exactly as the tracker has it, including what looks wrong, because
-- it is the company's current grouping and not mine to correct. Two things
-- for an administrator's eye, both now editable on the Configuration screen:
--   · NAGPUR (YASH) and NAGPUR (Sudhir) are one city split by who handles it,
--     and the same for Lucknow/ROUP (Ajay Pathak) and (Mukesh Yadav). A
--     location named after a person is the same confusion this work removes
--     from chairs.
--   · The tracker's Total rows disagree with its own data rows in five
--     places - DEL(B) for Delhi, JOA for GOA, JALJAON for JALGAON, SOL(A)
--     for Solapur, UP for Lucknow / ROUP Zone. The data rows are used.
--
-- ---------------------------------------------------------------------
-- 2 · THE TEMPLATE WAS TEACHING THE WRONG MODEL
--
-- The Chairs template's example row read:
--     chair_code  BM_PUNE
--     title       Branch Manager — Pune
-- which is precisely the thing being removed, in the one place people copy
-- from. It now reads BM and Branch Manager, and the rule says a chair is a
-- job and not a place.
--
-- The em-dash arriving as "Branch Manager ��� Pune" was a second fault: the
-- CSV had no byte order mark, so Excel decoded UTF-8 as ANSI. upload_template
-- now returns U+FEFF first.
--
-- ---------------------------------------------------------------------
-- 3 · AN ASSIGNMENT NAMED A COMPASS POINT
--
-- The Assignments file asked for a "zone" and resolved it against geo_node
-- level ZONE, which holds six values: North, South, East, West, Central,
-- North East. The only way to file an assignment for Pune was to write
-- "West", and writing "Pune" was refused. The granularity was wrong in the
-- one place the whole scope model rests on.
--
-- It now names a location from op_node, and coverage_rule carries
-- op_node_id beside geo_node_id. Chair, location and client stay three
-- separate things: the chair comes from the person, the location from the
-- grouping, the client from the file - one row per client, because a person
-- covers several.
--
-- ua_assignments also used to insert nothing at all when a join found no
-- row, saying nothing about it. It now raises.
--
-- ---------------------------------------------------------------------
-- 4 · THE DUPLICATE DATA
--
-- 532 of the 606 rows in `person` were not Crux people. They are branch
-- managers and coordinators at Bank of Maharashtra, Axis Bank, DNSB and the
-- rest, turned into people by migration rule P-02 - "an address that appears
-- only in BRANCH_ASSIGNMENTS still becomes a person". That rule exists so a
-- coverage owner is never lost; it swept up every client-side contact too.
--
-- Checked one relationship at a time before touching anything. Of those 532:
-- none holds a chair, none holds coverage, none is referenced by
-- matrix_contact, none is a party to an escalation, and the single one with a
-- Crux address is "Sample Manager".
--
-- They are the duplicates that were really there - two Anjula Kumaris are two
-- different bank managers, three people called "Na" are three branches whose
-- contact was never filled in. Nothing is deleted; they are marked
-- CLIENT_CONTACT, so the people master is the seventy-odd Crux staff again
-- and a client contact cannot be seated, scored, penalised or messaged as an
-- employee. person_is_staff() answers the question once for everybody.
--
-- wa_status counted all 532 as "reachable". That was the number a person
-- would have read before pressing send.
--
-- 568 branch codes read 1006.0, 108.0, 2.0 - a number column saved through a
-- spreadsheet, the same defect already fixed for mobile numbers. Checked
-- first that no client had both "108" and "108.0", then stripped. ul_code()
-- stops it happening on the next upload.
-- =====================================================================

create table if not exists op_node (
  id          uuid primary key default gen_random_uuid(),
  parent_id   uuid references op_node(id) on delete cascade,
  level       text not null check (level in ('GROUP','ZONE','LOCATION')),
  name        text not null,
  active      boolean not null default true,
  sort        int not null default 100,
  source_ref  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- one name per parent, case-insensitively: "Pune" and "pune" under the same
-- zone is the duplicate this whole exercise is about
create unique index if not exists op_node_unique_child
  on op_node (coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(btrim(name)));
create index if not exists op_node_parent_idx on op_node (parent_id, level);
alter table op_node enable row level security;

alter table coverage_rule add column if not exists op_node_id uuid references op_node(id);
create index if not exists coverage_rule_op_idx on coverage_rule (op_node_id);

alter table person drop constraint if exists person_employee_type_check;
alter table person add constraint person_employee_type_check
  check (employee_type = any (array['EMPLOYEE','PARTNER','INTERN','CONTRACT','CLIENT_CONTACT']));

-- A code out of a spreadsheet. Strips the .0 a number column picks up.
create or replace function ul_code(p text)
returns text
language sql
immutable
as $$
  select case
    when p is null then null
    when btrim(p) ~ '^\d+\.0+$' then split_part(btrim(p), '.', 1)
    else nullif(btrim(p), '')
  end
$$;

-- Who counts as staff, answered once so every caller gets the same answer.
create or replace function person_is_staff(p_person uuid)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from person p
     where p.id = p_person
       and p.superseded_by is null
       and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT')
$$;

revoke all on function ul_code(text) from public, anon, authenticated;
revoke all on function person_is_staff(uuid) from public, anon, authenticated;

-- The seed, op_tree, op_save, op_retire, the rewritten uv_assignments and
-- ua_assignments, the upload_column changes, the BOM on upload_template and
-- the staff-only wa_status are in the migration ledger under the names at the
-- top of this file.
