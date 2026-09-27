-- =====================================================================
-- Crux baseline | 09_staging.sql | the staging schema
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- stg is where the legacy spreadsheets landed. It is not part of the running tool and carries no constraints, but two of the migration audit views read it, so a database without it is a database two views short.
-- =====================================================================

create schema if not exists stg;

create table if not exists stg._tmp_blockers (
  tbl text,
  col text,
  n bigint
);

create table if not exists stg._tmp_refs (
  tbl text,
  col text,
  n bigint
);

create table if not exists stg.audit_log (
  row_no integer not null,
  at text,
  actor_email text,
  action text,
  entity_type text,
  entity_ref text,
  old_value text,
  new_value text
);

create table if not exists stg.branch_assignments (
  row_no integer not null,
  user_email text,
  branch_code text,
  client_code text,
  role text,
  created_at text
);

create table if not exists stg.branches (
  row_no integer not null,
  client_code text,
  code text,
  name text,
  address text,
  zone text,
  state text,
  city text,
  status text,
  bm_name text,
  bm_mobile text,
  bm_email text,
  poc_email text,
  dublicate text,
  updated_at text
);

create table if not exists stg.city_state (
  city text not null,
  state text not null
);

create table if not exists stg.clients (
  row_no integer not null,
  code text,
  name text,
  status text,
  primary_email text,
  cc_email text,
  ho_email text,
  ho_cc_email text,
  zones text,
  notes text
);

create table if not exists stg.coverage_rejected (
  at timestamp with time zone default now() not null,
  person_email text,
  role text,
  scope_type text,
  scope_ref text,
  sheet_ref text,
  reason text
);

create table if not exists stg.email_log (
  row_no integer not null,
  at text,
  idempotency_key text,
  template_key text,
  recipient text,
  state text,
  error text,
  entity_ref text
);

create table if not exists stg.escalation_events (
  row_no integer not null,
  ref text,
  at text,
  actor_email text,
  kind text,
  note text
);

create table if not exists stg.escalations (
  row_no integer not null,
  ref text,
  client_code text,
  branch_code text,
  category text,
  raised_by text,
  against text,
  description text,
  status text,
  resolved_at text,
  strike_count text,
  created_at text
);

create table if not exists stg.geo_deleted (
  at timestamp with time zone default now() not null,
  level text,
  name text,
  reason text
);

create table if not exists stg.geo_master (
  grp text,
  region text,
  zone_name text,
  state text,
  city text
);

create table if not exists stg.holidays (
  row_no integer not null,
  holiday_date text,
  name text
);

create table if not exists stg.job_log (
  row_no integer not null,
  job_key text,
  started_at text,
  finished_at text,
  state text,
  note text
);

create table if not exists stg.matrix (
  row_no integer not null,
  client_code text,
  branch_code text,
  level text,
  level_name text,
  name text,
  mobile text,
  email text,
  updated_by text,
  updated_at text
);

create table if not exists stg.people_events (
  row_no integer not null,
  person_email text,
  at text,
  kind text,
  note text,
  actor_email text
);

create table if not exists stg.people_events_copy (
  row_no integer not null,
  person_email text,
  at text,
  kind text,
  note text,
  actor_email text
);

create table if not exists stg.run (
  id uuid default gen_random_uuid() not null,
  started_at timestamp with time zone default now() not null,
  finished_at timestamp with time zone,
  script text,
  rows_in integer,
  rows_out integer,
  rows_logged integer,
  notes text
);

create table if not exists stg.settings (
  row_no integer not null,
  key text,
  value text,
  updated_at text
);

create table if not exists stg.sheet4 (
  row_no integer not null,
  c1 text,
  c2 text,
  c3 text,
  c4 text,
  c5 text,
  c6 text
);

create table if not exists stg.sheet4_archive (
  row_no integer,
  c1 text,
  c2 text,
  c3 text,
  c4 text,
  c5 text,
  c6 text
);

create table if not exists stg.state_zone (
  state text not null,
  zone text not null
);

create table if not exists stg.targets (
  row_no integer not null,
  person_email text,
  period text,
  metric text,
  value text
);

create table if not exists stg.users (
  row_no integer not null,
  name text,
  email text,
  role text,
  designation text,
  department text,
  manager_email text,
  scope_client text,
  scope_zone text,
  scope_state text,
  scope_branch text,
  status text,
  access_token text,
  created_at text
);

create table if not exists stg.warnings (
  row_no integer not null,
  person_email text,
  at text,
  kind text,
  note text
);

