-- =====================================================================
-- Crux baseline | 09_staging.sql | the staging schema
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- stg is where the legacy spreadsheets landed. No part of the running tool reads it, but two of the migration audit views do -- tables, constraints, indexes and the five text normalisers they call.
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

alter table stg.audit_log add constraint audit_log_pkey PRIMARY KEY (row_no);
alter table stg.branch_assignments add constraint branch_assignments_pkey PRIMARY KEY (row_no);
alter table stg.branches add constraint branches_pkey PRIMARY KEY (row_no);
alter table stg.city_state add constraint city_state_pkey PRIMARY KEY (city);
alter table stg.clients add constraint clients_pkey PRIMARY KEY (row_no);
alter table stg.email_log add constraint email_log_pkey PRIMARY KEY (row_no);
alter table stg.escalation_events add constraint escalation_events_pkey PRIMARY KEY (row_no);
alter table stg.escalations add constraint escalations_pkey PRIMARY KEY (row_no);
alter table stg.holidays add constraint holidays_pkey PRIMARY KEY (row_no);
alter table stg.job_log add constraint job_log_pkey PRIMARY KEY (row_no);
alter table stg.matrix add constraint matrix_pkey PRIMARY KEY (row_no);
alter table stg.people_events add constraint people_events_pkey PRIMARY KEY (row_no);
alter table stg.people_events_copy add constraint people_events_copy_pkey PRIMARY KEY (row_no);
alter table stg.run add constraint run_pkey PRIMARY KEY (id);
alter table stg.settings add constraint settings_pkey PRIMARY KEY (row_no);
alter table stg.sheet4 add constraint sheet4_pkey PRIMARY KEY (row_no);
alter table stg.state_zone add constraint state_zone_pkey PRIMARY KEY (state);
alter table stg.targets add constraint targets_pkey PRIMARY KEY (row_no);
alter table stg.users add constraint users_pkey PRIMARY KEY (row_no);
alter table stg.warnings add constraint warnings_pkey PRIMARY KEY (row_no);

CREATE OR REPLACE FUNCTION stg.norm_email(t text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'stg', 'public'
AS $function$
  select case when not stg.present(t) then null else
    replace(lower(btrim(t)), 'cruxinida.co.in', 'cruxindia.co.in')
  end;
$function$
;

CREATE OR REPLACE FUNCTION stg.norm_mobile(t text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'stg', 'public'
AS $function$
  select case when not stg.present(t) then null else
    nullif(right(regexp_replace(t, '[^0-9]', '', 'g'), 10), '') end;
$function$
;

CREATE OR REPLACE FUNCTION stg.norm_name(t text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'stg', 'public'
AS $function$
  select case when not stg.present(t) then null else
    regexp_replace(initcap(lower(btrim(t))), '\s+', ' ', 'g') end;
$function$
;

CREATE OR REPLACE FUNCTION stg.present(t text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'stg', 'public'
AS $function$
  select t is not null and btrim(t) <> '' and btrim(t) <> '#N/A' and btrim(t) <> 'null';
$function$
;

CREATE OR REPLACE FUNCTION stg.ts(t text)
 RETURNS timestamp with time zone
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'stg', 'public'
AS $function$
  select case when not stg.present(t) then null else
    (case when t ~ '^\d{4}-\d{2}-\d{2}' then t::timestamptz
          when t ~ '^\d{1,2}/\d{1,2}/\d{4}' then to_timestamp(t, 'DD/MM/YYYY HH24:MI:SS')
          else null end) end;
$function$
;

