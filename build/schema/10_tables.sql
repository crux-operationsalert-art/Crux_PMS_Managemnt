-- =====================================================================
-- Crux baseline | 10_tables.sql | tables
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- Columns and defaults only. Keys, checks, foreign keys and indexes each have their own file, so no table in here depends on another and load order is free.
-- =====================================================================

create table if not exists public.access_chair_level (
  chair_title text not null,
  level text not null
);

create table if not exists public.access_department_level (
  department text not null,
  level text not null
);

create table if not exists public.access_level (
  level text not null,
  label text not null,
  note text
);

create table if not exists public.access_level_screen (
  level text not null,
  screen text not null
);

create table if not exists public.access_screen_parent (
  screen text not null,
  parent text not null
);

create table if not exists public.ai_call (
  id uuid default gen_random_uuid() not null,
  ai_key_id uuid not null,
  touchpoint text not null,
  at timestamp with time zone default now() not null,
  latency_ms integer,
  ok boolean not null,
  error text,
  actor_id uuid
);

create table if not exists public.ai_key (
  id uuid default gen_random_uuid() not null,
  provider text not null,
  model text not null,
  key_encrypted bytea,
  endpoint text,
  chain_order integer not null,
  scope text default 'everything'::text not null,
  monthly_budget integer default 0 not null,
  used_this_month integer default 0 not null,
  state text default 'untested'::text not null,
  last_tested_at timestamp with time zone,
  last_latency_ms integer,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.app_page (
  slug text not null,
  html text not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.app_setting (
  key text not null,
  value text,
  plain_language text not null,
  group_name text not null,
  secret boolean default false not null,
  editable_by text default 'ADMIN'::text not null,
  updated_by uuid,
  updated_at timestamp with time zone default now() not null,
  in_force boolean default true not null
);

create table if not exists public.assignment (
  id uuid default gen_random_uuid() not null,
  ref text not null,
  case_id uuid not null,
  assignor_id uuid not null,
  assignor_chair_id uuid not null,
  from_location_id uuid not null,
  to_location_id uuid not null,
  allocated_to_id uuid,
  current_state text default 'DRAFT'::text not null,
  next_action_owner_id uuid,
  breach_cycle_no integer default 1 not null,
  delay_count integer default 0 not null,
  dispute_count integer default 0 not null,
  open_request_type text,
  priority_score integer default 0 not null,
  priority_bucket text default 'Normal'::text not null,
  self_assign_reason text,
  source_ref text,
  created_at timestamp with time zone default now() not null,
  closed_at timestamp with time zone
);

create table if not exists public.assignment_completion (
  id uuid default gen_random_uuid() not null,
  assignment_id uuid not null,
  breach_cycle_no integer not null,
  shared_at timestamp with time zone not null,
  submitted_at timestamp with time zone default now() not null,
  channel text not null,
  recipient text,
  message_ref text,
  force1_ref text,
  backdate_flagged boolean default false not null,
  other_remarks text,
  submitted_by uuid not null
);

create table if not exists public.assignment_event (
  id bigint default nextval('assignment_event_id_seq'::regclass) not null,
  assignment_id uuid not null,
  event_type text not null,
  occurred_at timestamp with time zone default now() not null,
  actor_id uuid,
  actor_chair_id uuid,
  is_system boolean default false not null,
  from_state text,
  to_state text,
  payload jsonb default '{}'::jsonb not null
);

create table if not exists public.assignment_request (
  id uuid default gen_random_uuid() not null,
  assignment_id uuid not null,
  breach_cycle_no integer not null,
  request_type text not null,
  seq_no integer not null,
  raised_by uuid not null,
  raised_at timestamp with time zone default now() not null,
  reason_id uuid,
  remarks text,
  delay_category text,
  expected_completion timestamp with time zone,
  sub_tat_minutes integer,
  sub_tat_due_at timestamp with time zone,
  sub_tat_breached boolean default false not null,
  pause_granted boolean default false not null,
  pause_minutes_credited integer default 0 not null,
  resolution text,
  resolved_by uuid,
  resolved_at timestamp with time zone,
  resolution_remarks text
);

create table if not exists public.assist_guide (
  key text not null,
  route text not null,
  title text not null,
  steps text[] not null,
  why text not null
);

create table if not exists public.audit_entry (
  id uuid default gen_random_uuid() not null,
  at timestamp with time zone default now() not null,
  actor_id uuid,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  entity_ref text,
  old_value jsonb,
  new_value jsonb,
  chair_id uuid,
  scope_path text,
  sentence text,
  scope_chair_id uuid
);

create table if not exists public.auth_session (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  created_at timestamp with time zone default now() not null,
  last_seen_at timestamp with time zone,
  expires_at timestamp with time zone not null,
  source text,
  revoked_at timestamp with time zone,
  revoked_by uuid,
  token_hash text,
  acting_actor_id uuid
);

create table if not exists public.automation (
  key text not null,
  title text not null,
  fires_on text not null,
  reads_setting text[],
  writes_kind text[],
  ladder_step integer,
  escalates_to text,
  enabled boolean default true not null,
  disabled_reason text,
  grp text,
  owner text,
  state text,
  trigger_on text[],
  conditions text[],
  actions text[],
  notifies text[],
  guard text
);

create table if not exists public.automation_run (
  id uuid default gen_random_uuid() not null,
  key text not null,
  started_at timestamp with time zone default now() not null,
  finished_at timestamp with time zone,
  outcome text,
  affected integer default 0 not null,
  detail text
);

create table if not exists public.branch (
  id uuid default gen_random_uuid() not null,
  client_id uuid not null,
  code text not null,
  name text not null,
  address text,
  geo_node_id uuid,
  client_zone_id uuid,
  status entity_status default 'ACTIVE'::entity_status not null,
  effective_from date,
  effective_to date,
  notes text,
  source_ref text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  op_node_id uuid
);

create table if not exists public.branch_contact (
  id uuid default gen_random_uuid() not null,
  branch_id uuid not null,
  role text not null,
  person_id uuid,
  name text,
  mobile text,
  email text,
  active boolean default true not null
);

create table if not exists public.branch_generation_map (
  old_branch_id uuid not null,
  new_branch_id uuid not null,
  old_client_id uuid not null,
  new_client_id uuid not null,
  matched_on text not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.business_calendar (
  id uuid default gen_random_uuid() not null,
  code text not null,
  geo_node_id uuid,
  window_start time without time zone default '10:00:00'::time without time zone not null,
  window_end time without time zone default '17:00:00'::time without time zone not null,
  works_saturday boolean default false not null,
  works_sunday boolean default false not null,
  timezone text default 'Asia/Kolkata'::text not null,
  effective_from date default CURRENT_DATE not null,
  effective_to date
);

create table if not exists public.business_record (
  id uuid default gen_random_uuid() not null,
  period character(7) not null,
  business_date date not null,
  client_id uuid not null,
  geo_node_id uuid not null,
  owner_id uuid,
  mtd integer default 0 not null,
  day10 integer default 0 not null,
  target integer default 0 not null,
  revenue numeric(14,2) default 0 not null,
  source_ref text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.capability_level (
  track_id uuid not null,
  level text not null,
  level_name text not null,
  requirement text,
  qualification text,
  experience text,
  certification text,
  test_score text,
  evidence text
);

create table if not exists public.capability_psychometric (
  track_id uuid not null,
  ord integer not null,
  instrument text not null,
  standard text
);

create table if not exists public.capability_topic (
  track_id uuid not null,
  ord integer not null,
  topic text not null
);

create table if not exists public.capability_track (
  id uuid default gen_random_uuid() not null,
  name text not null,
  knowledge_test text,
  unlock text
);

create table if not exists public."case" (
  id uuid default gen_random_uuid() not null,
  ref text not null,
  client_id uuid not null,
  branch_id uuid,
  category_id uuid not null,
  raised_by uuid not null,
  against_person_id uuid,
  against_text text,
  description text,
  owner_person_id uuid,
  desk_id uuid,
  status case_status default 'OPEN'::case_status not null,
  resolution_note text,
  resolved_at timestamp with time zone,
  auto_close_at timestamp with time zone,
  next_chase_at timestamp with time zone,
  strike_count integer default 0 not null,
  last_activity_at timestamp with time zone default now() not null,
  closed_at timestamp with time zone,
  source_ref text,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.case_event (
  id uuid default gen_random_uuid() not null,
  case_id uuid not null,
  at timestamp with time zone default now() not null,
  actor_id uuid,
  kind text,
  field text,
  old_value text,
  new_value text,
  note text
);

create table if not exists public.case_party (
  id uuid default gen_random_uuid() not null,
  case_id uuid not null,
  party_role text not null,
  seq_no integer not null,
  name text not null,
  contact text,
  address text,
  same_as_applicant boolean default false not null
);

create table if not exists public.case_verification_requirement (
  id uuid default gen_random_uuid() not null,
  case_id uuid not null,
  party_id uuid not null,
  verification_type_id uuid not null,
  force1_point_id text not null,
  attempt_no integer default 1 not null,
  lineage text default 'ORIGINAL'::text not null,
  supersedes_id uuid,
  status text default 'PENDING'::text not null,
  outcome text,
  remarks text,
  findings jsonb default '{}'::jsonb not null,
  reported_at timestamp with time zone,
  reported_by uuid
);

create table if not exists public.category (
  id uuid default gen_random_uuid() not null,
  name text not null,
  desk_id uuid not null,
  pinned boolean default false not null,
  chase_hours integer,
  active boolean default true not null
);

create table if not exists public.chair (
  id uuid default gen_random_uuid() not null,
  code text not null,
  title text not null,
  desk_id uuid,
  parent_id uuid,
  level text not null,
  reports_daily boolean default false not null,
  sg_level text,
  function_name text,
  band text,
  purpose text,
  capability_track_id uuid,
  source_ref text
);

create table if not exists public.chair_accountability (
  id uuid default gen_random_uuid() not null,
  chair_id uuid not null,
  ord integer not null,
  statement text not null,
  source_ref text
);

create table if not exists public.chair_authority (
  id uuid default gen_random_uuid() not null,
  chair_id uuid not null,
  kind text not null,
  ord integer not null,
  statement text not null,
  source_ref text
);

create table if not exists public.chair_holder (
  id uuid default gen_random_uuid() not null,
  chair_id uuid not null,
  person_id uuid not null,
  is_primary boolean default false not null,
  from_date date default CURRENT_DATE not null,
  to_date date,
  seating_id uuid
);

create table if not exists public.chair_measure (
  id uuid default gen_random_uuid() not null,
  chair_id uuid not null,
  ord integer not null,
  statement text not null,
  source_ref text
);

create table if not exists public.chair_seating (
  id uuid default gen_random_uuid() not null,
  chair_id uuid not null,
  scope_label text,
  reports_to_chair_id uuid,
  holder_text text,
  note text,
  source_ref text,
  reports_to_seating_id uuid
);

create table if not exists public.chair_subtask (
  id uuid default gen_random_uuid() not null,
  task_id uuid not null,
  ord integer not null,
  statement text not null
);

create table if not exists public.chair_task (
  id uuid default gen_random_uuid() not null,
  chair_id uuid not null,
  ord integer not null,
  task text not null
);

create table if not exists public.claim (
  id uuid default gen_random_uuid() not null,
  ref text not null,
  visit_id uuid,
  person_id uuid not null,
  amount numeric not null,
  stage claim_stage default 'DRAFT'::claim_stage not null,
  ops_by uuid,
  ops_at timestamp with time zone,
  hr_by uuid,
  hr_at timestamp with time zone,
  accounts_by uuid,
  accounts_at timestamp with time zone,
  paid_ref text,
  dispute_reason text,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.client (
  id uuid default gen_random_uuid() not null,
  code text not null,
  name text not null,
  status entity_status default 'ACTIVE'::entity_status not null,
  effective_from date,
  effective_to date,
  notes text,
  source_ref text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.client_contact (
  id uuid default gen_random_uuid() not null,
  client_id uuid not null,
  kind text not null,
  name text,
  email text not null,
  mobile text
);

create table if not exists public.client_view_policy (
  department text not null,
  view_kind text not null
);

create table if not exists public.client_zone (
  id uuid default gen_random_uuid() not null,
  client_id uuid not null,
  name text not null,
  geo_node_id uuid
);

create table if not exists public.coverage_rule (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  role text not null,
  scope_type scope_kind not null,
  client_id uuid,
  client_zone_id uuid,
  geo_node_id uuid,
  branch_id uuid,
  effective_from date default CURRENT_DATE not null,
  effective_to date,
  source_ref text,
  created_at timestamp with time zone default now() not null,
  is_assigned_handler boolean default false not null,
  product text,
  op_node_id uuid
);

create table if not exists public.cutover_check (
  id bigint default nextval('cutover_check_id_seq'::regclass) not null,
  at timestamp with time zone default now() not null,
  check_name text not null,
  expectation text not null,
  outcome text not null,
  detail text,
  result text not null
);

create table if not exists public.daily_count (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  count_date date not null,
  kpi_id uuid,
  value numeric,
  submitted_at timestamp with time zone default now() not null,
  locked_at timestamp with time zone,
  reopened_by uuid,
  reopen_reason text,
  entered_at timestamp with time zone not null,
  received_at timestamp with time zone default now() not null,
  entered_offline boolean default false not null,
  device_ref text,
  sync_attempts integer default 0 not null,
  late_sync boolean default false not null,
  clock_skew_flag boolean default false not null,
  counts_to_mis boolean default false not null,
  "values" jsonb
);

create table if not exists public.daily_note (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  note_date date not null,
  body text not null,
  classification note_class default 'UNCLASSIFIED'::note_class not null,
  attribute_heading text,
  model_reason text,
  classified_at timestamp with time zone,
  included_in_review boolean default true not null
);

create table if not exists public.day_reopen (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  day date not null,
  reason text not null,
  opened_by uuid not null,
  opened_at timestamp with time zone default now() not null,
  closes_at timestamp with time zone not null,
  closed_at timestamp with time zone
);

create table if not exists public.delivery (
  id uuid default gen_random_uuid() not null,
  outbox_id uuid,
  channel text default 'EMAIL'::text not null,
  recipient text not null,
  state text not null,
  error text,
  at timestamp with time zone default now() not null,
  provider_ref text,
  entity_type text,
  entity_id uuid
);

create table if not exists public.designation (
  id uuid default gen_random_uuid() not null,
  title text not null,
  desk_id uuid,
  is_desk_head boolean default false not null,
  seniority integer default 0 not null
);

create table if not exists public.desk (
  id uuid default gen_random_uuid() not null,
  name text not null,
  primary_person_id uuid,
  escalation_only boolean default false not null,
  fallback_desk_id uuid
);

create table if not exists public.email_domain_alias (
  wrong text not null,
  correct text not null,
  noted_by text,
  noted_at timestamp with time zone default now() not null
);

create table if not exists public.escalation_action (
  id uuid default gen_random_uuid() not null,
  code text not null,
  label text not null,
  pms_impact boolean not null,
  unlock_after_working_days integer,
  sets_tat_hours integer,
  routes_to text,
  sets_status case_status,
  valid_statuses case_status[],
  allowed_parts esc_party[] default '{}'::esc_party[] not null,
  needs_note boolean default false not null
);

create table if not exists public.escalation_action_log (
  id uuid default gen_random_uuid() not null,
  case_id uuid not null,
  action_code text not null,
  actor_id uuid not null,
  at timestamp with time zone default now() not null,
  note text
);

create table if not exists public.escalation_instance (
  id uuid default gen_random_uuid() not null,
  assignment_id uuid not null,
  breach_cycle_no integer not null,
  escalation_level integer not null,
  trigger_code text not null,
  idempotency_key text not null,
  resolved_to_id uuid,
  resolved_chair_id uuid,
  route_trace jsonb default '{}'::jsonb not null,
  fallback_used boolean default false not null,
  fallback_reason text,
  raised_at timestamp with time zone default now() not null,
  closed_at timestamp with time zone,
  closed_by uuid
);

create table if not exists public.escalation_party (
  case_id uuid not null,
  person_id uuid not null,
  part esc_party not null
);

create table if not exists public.forecast_config (
  id smallint default 1 not null,
  scenarios jsonb default '[{"key": "cons", "mult": 3.25, "label": "Conservative"}, {"key": "base", "mult": 3.5, "label": "Base"}, {"key": "stretch", "mult": 4, "label": "Stretch"}, {"key": "agg", "kept": true, "mult": 5, "label": "Aggressive"}]'::jsonb not null,
  updated_by uuid,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.geo_node (
  id uuid default gen_random_uuid() not null,
  parent_id uuid,
  level geo_level not null,
  name text not null,
  group_name text,
  region text,
  op_zone text
);

create table if not exists public.holiday (
  day date not null,
  name text not null,
  applies_to text default 'ALL'::text not null,
  source text,
  created_at timestamp with time zone default now() not null,
  confirmed boolean default true not null,
  batch_id uuid
);

create table if not exists public.holiday_centre_alias (
  city text not null,
  centre text not null,
  noted_by text,
  noted_at timestamp with time zone default now() not null
);

create table if not exists public.idea (
  id uuid default gen_random_uuid() not null,
  ref text not null,
  title text not null,
  body text not null,
  raised_by uuid not null,
  stage idea_stage default 'SUBMITTED'::idea_stage not null,
  sponsor_id uuid,
  owner_dept text,
  charter text,
  decided_by uuid,
  decided_at timestamp with time zone,
  decision_reason text,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.idea_collaborator (
  idea_id uuid not null,
  person_id uuid not null,
  role text default 'COLLABORATOR'::text not null
);

create table if not exists public.job_config (
  job_key text not null,
  enabled boolean default true not null,
  cron text not null,
  disabled_by uuid,
  disabled_at timestamp with time zone,
  reason text
);

create table if not exists public.job_run (
  id uuid default gen_random_uuid() not null,
  job_key text not null,
  started_at timestamp with time zone default now() not null,
  finished_at timestamp with time zone,
  state text,
  note text,
  result job_result,
  counts jsonb,
  error text,
  next_due_at timestamp with time zone
);

create table if not exists public.kpi_definition (
  id uuid default gen_random_uuid() not null,
  chair_id uuid,
  person_id uuid,
  name text not null,
  unit text,
  active boolean default true not null,
  mandatory boolean default true not null,
  "position" integer default 1 not null,
  parent_id uuid,
  cadence kpi_cadence default 'DAILY'::kpi_cadence not null,
  accrual kpi_accrual default 'ADDS'::kpi_accrual not null
);

create table if not exists public.kpi_eligibility (
  id uuid default gen_random_uuid() not null,
  kpi_id uuid,
  person_id uuid,
  chair_id uuid,
  scope_all boolean default false not null,
  gate text not null,
  on_miss text not null,
  deduct_points numeric,
  default_score numeric,
  set_by uuid
);

create table if not exists public.kpi_target (
  id uuid default gen_random_uuid() not null,
  kpi_id uuid not null,
  person_id uuid not null,
  period text not null,
  target_value numeric not null,
  set_by uuid not null,
  set_at timestamp with time zone default now() not null,
  parent_target_id uuid
);

create table if not exists public.letter (
  id uuid default gen_random_uuid() not null,
  kind text not null,
  person_id uuid not null,
  case_id uuid,
  issued_by uuid not null,
  issued_at timestamp with time zone default now() not null,
  body text not null,
  acknowledged_at timestamp with time zone,
  due_ack_at timestamp with time zone not null,
  copied_to text[]
);

create table if not exists public.login_attempt (
  id bigint default nextval('login_attempt_id_seq'::regclass) not null,
  at timestamp with time zone default now() not null,
  email text not null,
  ip text,
  ok boolean not null
);

create table if not exists public.mail_alias (
  id uuid default gen_random_uuid() not null,
  address text not null,
  verified boolean default false not null
);

create table if not exists public.mail_bounce (
  id uuid default gen_random_uuid() not null,
  address text not null,
  at timestamp with time zone default now() not null,
  hard boolean not null,
  strikes integer default 1 not null,
  unreachable boolean default false not null
);

create table if not exists public.mail_budget (
  day date not null,
  recipients_sent integer default 0 not null,
  cap integer default 1800 not null,
  reserve integer default 200 not null
);

create table if not exists public.mail_config (
  id smallint default 1 not null,
  mailbox text not null,
  auth_mode text not null,
  service_account_email text,
  delegation_client_id text,
  reply_to text,
  daily_budget integer default 1800 not null,
  used_today integer default 0 not null,
  signature_json jsonb,
  signature_logo_file uuid,
  test_mode boolean default false not null,
  test_address text,
  test_mode_expires_at timestamp with time zone,
  bounce_strikes integer default 3 not null,
  last_tested_at timestamp with time zone,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.matrix_contact (
  id uuid default gen_random_uuid() not null,
  client_id uuid not null,
  branch_id uuid,
  level integer not null,
  level_name text not null,
  person_id uuid,
  name text,
  mobile text,
  email text,
  updated_by uuid,
  updated_at timestamp with time zone default now() not null,
  source_ref text
);

create table if not exists public.matrix_dispatch (
  id uuid default gen_random_uuid() not null,
  client_id uuid not null,
  period date not null,
  snapshot jsonb not null,
  branch_count integer not null,
  held_back integer default 0 not null,
  recipients text[] default '{}'::text[] not null,
  prepared_by uuid not null,
  prepared_at timestamp with time zone default now() not null,
  sent_at timestamp with time zone,
  note text
);

create table if not exists public.migration_merge (
  id uuid default gen_random_uuid() not null,
  at timestamp with time zone default now() not null,
  entity_type text not null,
  kept_id uuid not null,
  merged_id uuid,
  merged_key text,
  rows_moved integer,
  rule text not null,
  reviewed_by uuid,
  reviewed_at timestamp with time zone
);

create table if not exists public.migration_review (
  id uuid default gen_random_uuid() not null,
  entity_type text not null,
  entity_ref text not null,
  question text not null,
  context text,
  resolved_to text,
  resolved_by uuid,
  resolved_at timestamp with time zone
);

create table if not exists public.mis_saved_view (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  name text not null,
  config jsonb not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.mis_view (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  name text not null,
  config jsonb not null,
  created_at timestamp with time zone default now() not null,
  used_at timestamp with time zone
);

create table if not exists public.notification (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  kind text not null,
  text text not null,
  entity_type text,
  entity_id uuid,
  push boolean default false not null,
  at timestamp with time zone default now() not null,
  read_at timestamp with time zone
);

create table if not exists public.ogl_attachment (
  id uuid default gen_random_uuid() not null,
  assignment_id uuid not null,
  party_kind ogl_party_kind not null,
  party_seq integer default 0 not null,
  doc_kind text not null,
  file_name text not null,
  storage_key text not null,
  bytes bigint,
  mime text,
  uploaded_by uuid not null,
  uploaded_at timestamp with time zone default now() not null,
  removed_at timestamp with time zone,
  removed_by uuid,
  requirement_id uuid,
  caption text
);

create table if not exists public.ogl_escalation_matrix (
  id uuid default gen_random_uuid() not null,
  client_id uuid,
  location_id uuid,
  branch_id uuid,
  escalation_level integer not null,
  chair_id uuid,
  person_id uuid,
  sequence_no integer default 1 not null,
  effective_from date default CURRENT_DATE not null,
  effective_to date
);

create table if not exists public.ogl_transition_rule (
  from_state text not null,
  to_state text not null,
  trigger_name text not null,
  guard_note text
);

create table if not exists public.onboarding (
  id uuid default gen_random_uuid() not null,
  person_request_id uuid,
  person_id uuid,
  induction_on date,
  buddy_id uuid,
  documents_ok boolean default false not null,
  completed_at timestamp with time zone
);

create table if not exists public.op_node (
  id uuid default gen_random_uuid() not null,
  parent_id uuid,
  level text not null,
  name text not null,
  active boolean default true not null,
  sort integer default 100 not null,
  source_ref text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.op_node_alias (
  written_as text not null,
  means text not null,
  note text,
  created_by uuid,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.ops_alert (
  id uuid default gen_random_uuid() not null,
  kind text not null,
  severity text default 'WARN'::text not null,
  title text not null,
  detail text,
  action_hint text,
  for_role text default 'ADMIN'::text not null,
  entity_type text,
  entity_id uuid,
  dedupe_key text not null,
  retry_at timestamp with time zone,
  opened_at timestamp with time zone default now() not null,
  last_seen_at timestamp with time zone default now() not null,
  occurrences integer default 1 not null,
  acknowledged_by uuid,
  acknowledged_at timestamp with time zone,
  resolved_at timestamp with time zone,
  resolved_note text
);

create table if not exists public.otp_challenge (
  id uuid default gen_random_uuid() not null,
  mobile text not null,
  code_hash bytea not null,
  purpose text not null,
  expires_at timestamp with time zone not null,
  consumed_at timestamp with time zone,
  attempts integer default 0 not null
);

create table if not exists public.outbox (
  id uuid default gen_random_uuid() not null,
  idempotency_key text not null,
  template_key text not null,
  entity_type text,
  entity_id uuid,
  recipient text not null,
  cc_addr text,
  subject text not null,
  body text not null,
  state outbox_state default 'QUEUED'::outbox_state not null,
  attempts integer default 0 not null,
  not_before timestamp with time zone default now() not null,
  sent_at timestamp with time zone,
  last_error text,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.penalty_instance (
  id uuid default gen_random_uuid() not null,
  rule_id uuid not null,
  person_id uuid not null,
  period text not null,
  occurred_on date not null,
  cutoff_missed text not null,
  evidence text not null,
  entity_type text,
  entity_id uuid,
  amount numeric not null,
  state penalty_state default 'APPLIED'::penalty_state not null,
  waived_by uuid,
  waive_reason text,
  recovered_by text not null,
  recovered_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  sync_evidence jsonb
);

create table if not exists public.penalty_rule (
  id uuid default gen_random_uuid() not null,
  code text not null,
  what text not null,
  plain_language text not null,
  applies_to text not null,
  frequency text not null,
  cutoff_spec text not null,
  amount numeric not null,
  recovered_by text not null,
  active boolean default true not null,
  effective_from date default CURRENT_DATE not null,
  created_by uuid,
  applies_to_list text[] default '{Everybody}'::text[] not null
);

create table if not exists public.perf_assignment (
  id uuid default gen_random_uuid() not null,
  cycle_id uuid not null,
  person_id uuid not null,
  kpi_id uuid,
  name text not null,
  unit text,
  target_value numeric,
  weight_pct numeric,
  cadence_day integer,
  part_of_id uuid,
  split_kind text,
  split_ref uuid,
  split_label text,
  rolls_into_id uuid,
  set_by uuid not null,
  set_at timestamp with time zone default now() not null,
  state text default 'ISSUED'::text not null,
  carried_from_id uuid,
  note text,
  cadence kpi_cadence
);

create table if not exists public.perf_collection (
  id uuid default gen_random_uuid() not null,
  client_id uuid not null,
  op_node_id uuid,
  branch_id uuid,
  period date not null,
  opening_outstanding_inr bigint not null,
  collected_inr bigint not null,
  closing_outstanding_inr bigint not null,
  owner_person_id uuid,
  source_ref text,
  loaded_by uuid,
  loaded_at timestamp with time zone default now() not null
);

create table if not exists public.perf_cycle (
  id uuid default gen_random_uuid() not null,
  period_start date not null,
  period_kind text default 'MONTH'::text not null,
  assign_opens date not null,
  assign_closes date not null,
  entry_closes date not null,
  state text default 'OPEN'::text not null,
  opened_by uuid,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.perf_entry (
  id uuid default gen_random_uuid() not null,
  assignment_id uuid not null,
  as_of date not null,
  value numeric not null,
  note text,
  filed_by uuid not null,
  filed_at timestamp with time zone default now() not null
);

create table if not exists public.perf_month (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  period date not null,
  kpi_id uuid,
  kpi_name text not null,
  sub_category text,
  unit text,
  target_value numeric,
  achieved numeric not null,
  mtd_achieved numeric,
  source text,
  source_ref text,
  loaded_by uuid,
  loaded_at timestamp with time zone default now() not null
);

create table if not exists public.perf_revenue (
  id uuid default gen_random_uuid() not null,
  client_id uuid not null,
  op_node_id uuid,
  branch_id uuid,
  period date not null,
  invoiced_inr bigint not null,
  realised_inr bigint not null,
  owner_person_id uuid,
  remarks text,
  source_ref text,
  loaded_by uuid,
  loaded_at timestamp with time zone default now() not null
);

create table if not exists public.person (
  id uuid default gen_random_uuid() not null,
  employee_no text,
  full_name text not null,
  work_email text,
  personal_email text,
  mobile text,
  designation_id uuid,
  department text,
  manager_id uuid,
  app_role role_kind default 'VIEWER'::role_kind not null,
  employment_status entity_status default 'ACTIVE'::entity_status not null,
  joined_on date,
  left_on date,
  superseded_by uuid,
  source_ref text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  employee_type text default 'EMPLOYEE'::text not null,
  user_id text,
  mobile_verified_at timestamp with time zone,
  password_hash text,
  password_salt text,
  auth_user_id uuid,
  address text,
  emergency_contact text
);

create table if not exists public.person_document (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  kind text not null,
  state text default 'WITH_HR'::text not null,
  note text,
  updated_by uuid,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.person_event (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  kind text not null,
  at timestamp with time zone default now() not null,
  start_on date,
  end_on date,
  note text,
  issued_by uuid,
  status text,
  outcome text,
  case_id uuid,
  source_ref text,
  note_class note_class default 'UNCLASSIFIED'::note_class not null,
  actor_id uuid
);

create table if not exists public.person_request (
  id uuid default gen_random_uuid() not null,
  full_name text not null,
  work_email text not null,
  chair_id uuid not null,
  manager_id uuid not null,
  requested_by uuid not null,
  requested_at timestamp with time zone default now() not null,
  state approval_state default 'AWAITING_HR'::approval_state not null,
  hr_by uuid,
  hr_at timestamp with time zone,
  admin_by uuid,
  admin_at timestamp with time zone,
  reject_reason text,
  person_id uuid,
  finance_state text default 'NOT_REQUIRED'::text,
  finance_by uuid,
  finance_at timestamp with time zone,
  finance_note text,
  due_at timestamp with time zone,
  returned_to uuid,
  created_at timestamp with time zone default now() not null,
  employee_type text default 'EMPLOYEE'::text not null
);

create table if not exists public.plb_correction (
  id uuid default gen_random_uuid() not null,
  what text not null,
  row_id uuid not null,
  field text not null,
  was text,
  now_is text,
  why text not null,
  who uuid not null,
  at timestamp with time zone default now() not null
);

create table if not exists public.plb_dispute (
  id uuid default gen_random_uuid() not null,
  sheet_id uuid not null,
  element text not null,
  kpi_id uuid,
  month date,
  claimed text not null,
  claimed_value numeric,
  evidence text not null,
  raised_by uuid not null,
  raised_at timestamp with time zone default now() not null,
  stage text default 'RAISED'::text not null,
  outcome text,
  respond_due date,
  response text,
  responded_by uuid,
  responded_at timestamp with time zone,
  escalate_due date,
  escalated_at timestamp with time zone,
  escalate_reason text,
  decide_due date,
  decided_by uuid,
  decided_at timestamp with time zone,
  decision text,
  ring_fenced_inr numeric,
  closed_at timestamp with time zone
);

create table if not exists public.plb_goal_attribute (
  id uuid default gen_random_uuid() not null,
  sheet_id uuid not null,
  kpi_id uuid not null,
  proposal text,
  approved_at timestamp with time zone,
  state text default 'EMPTY'::text not null,
  proposed_at timestamp with time zone,
  approved_by uuid,
  decided_note text,
  evidence_ref text,
  m1_milestone text,
  m2_milestone text,
  m3_milestone text,
  overlap_note text
);

create table if not exists public.plb_goal_kpi (
  id uuid default gen_random_uuid() not null,
  sheet_id uuid not null,
  kpi_id uuid not null,
  weight_pct numeric(6,3) not null,
  target_value numeric(16,4),
  basis_level integer,
  basis_note text,
  m1_share numeric(6,3) default 0 not null,
  m2_share numeric(6,3) default 0 not null,
  m3_share numeric(6,3) default 0 not null,
  actual_value numeric(16,4)
);

create table if not exists public.plb_goal_sheet (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  chair_id uuid not null,
  quarter date not null,
  target_plb_inr numeric(14,2) not null,
  status text default 'DRAFT'::text not null,
  issued_by uuid,
  issued_at timestamp with time zone,
  acknowledged_at timestamp with time zone,
  locked_at timestamp with time zone,
  is_default boolean default false not null,
  note text,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.plb_month_score (
  id uuid default gen_random_uuid() not null,
  sheet_id uuid not null,
  month date not null,
  kpi_points numeric(4,2),
  attr_points numeric(4,2),
  monthly_score numeric(5,3) generated always as (((0.75 * kpi_points) + (0.25 * attr_points))) stored,
  self_kpi numeric(4,2),
  self_attr numeric(4,2),
  self_at timestamp with time zone,
  scored_by uuid,
  scored_at timestamp with time zone,
  gap_reason text,
  locked_at timestamp with time zone,
  excluded boolean default false not null,
  excluded_why text,
  countersign_by uuid,
  countersign_at timestamp with time zone
);

create table if not exists public.plb_result (
  id uuid default gen_random_uuid() not null,
  sheet_id uuid not null,
  achievement numeric(7,3),
  payout_factor numeric(7,3),
  months_counted integer,
  monthly_mean numeric(5,3),
  consistency numeric(6,4),
  amount_inr numeric(14,2),
  data_frozen_at timestamp with time zone,
  computed_at timestamp with time zone,
  certified_by uuid,
  certified_at timestamp with time zone,
  published_at timestamp with time zone
);

create table if not exists public.pms_adjustment (
  id uuid default gen_random_uuid() not null,
  cycle_id uuid not null,
  source_kind raisable_kind not null,
  source_id uuid,
  half text not null,
  points numeric not null,
  applied boolean default true not null,
  capped boolean default false not null,
  reason text not null,
  at timestamp with time zone default now() not null,
  over_cap boolean default false not null,
  actor_id uuid
);

create table if not exists public.pms_band_result (
  cycle_id uuid not null,
  band_id uuid,
  final numeric not null,
  floored boolean default false not null,
  excluded boolean default false not null,
  at timestamp with time zone default now() not null
);

create table if not exists public.pms_component (
  id uuid default gen_random_uuid() not null,
  cycle_id uuid not null,
  kind text not null,
  raw numeric not null,
  weight_pct numeric not null,
  note text
);

create table if not exists public.pms_curve_band (
  id uuid default gen_random_uuid() not null,
  effective_fy text not null,
  rank integer not null,
  label text not null,
  share_pct numeric not null
);

create table if not exists public.pms_cycle (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  chair_id uuid,
  period date not null,
  state pms_cycle_state default 'PENDING'::pms_cycle_state not null,
  window_opens timestamp with time zone,
  window_closes timestamp with time zone,
  self_due timestamp with time zone,
  self_at timestamp with time zone,
  review_due timestamp with time zone,
  scored_at timestamp with time zone,
  closed_at timestamp with time zone,
  on_probation boolean default false not null,
  is_partner boolean default false not null
);

create table if not exists public.pms_dispute (
  id uuid default gen_random_uuid() not null,
  cycle_id uuid not null,
  raised_by uuid not null,
  raised_at timestamp with time zone default now() not null,
  reason text not null,
  hr_due timestamp with time zone not null,
  decided_by uuid,
  decided_at timestamp with time zone,
  outcome text,
  outcome_note text
);

create table if not exists public.pms_exception (
  id uuid default gen_random_uuid() not null,
  cycle_id uuid not null,
  requested_by uuid not null,
  requested_at timestamp with time zone default now() not null,
  reason text not null,
  hr_due timestamp with time zone not null,
  state text default 'PENDING'::text not null,
  decided_by uuid,
  decided_at timestamp with time zone,
  reopens_until timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  due_at timestamp with time zone
);

create table if not exists public.pms_impact (
  kind raisable_kind not null,
  points numeric not null,
  applies_to text default 'PERSON_CONCERNED'::text not null,
  set_by uuid,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.pms_score (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  period text not null,
  kpi_score numeric,
  attr_score numeric,
  final_score numeric,
  manager_score numeric,
  manager_note text,
  review_summary text,
  scored_by uuid,
  scored_at timestamp with time zone,
  hr_closed_by uuid,
  hr_closed_at timestamp with time zone
);

create table if not exists public.pms_weighting (
  id uuid default gen_random_uuid() not null,
  scope_all boolean default false not null,
  chair_id uuid,
  person_id uuid,
  kpi_percent numeric not null,
  attr_percent numeric not null,
  effective_from date default CURRENT_DATE not null,
  set_by uuid
);

create table if not exists public.portal_link (
  id uuid default gen_random_uuid() not null,
  client_id uuid,
  branch_id uuid,
  token_hash text not null,
  created_at timestamp with time zone default now() not null,
  rotated_at timestamp with time zone,
  revoked_at timestamp with time zone
);

create table if not exists public.process (
  id uuid default gen_random_uuid() not null,
  ref text not null,
  function text not null,
  name text not null,
  owner_chair_id uuid not null
);

create table if not exists public.process_input (
  id uuid default gen_random_uuid() not null,
  process_id uuid not null,
  what text not null,
  from_chair_id uuid not null
);

create table if not exists public.process_party (
  process_id uuid not null,
  chair_id uuid not null,
  part text not null
);

create table if not exists public.process_scope (
  id uuid default gen_random_uuid() not null,
  process_id uuid not null,
  ref text not null,
  scope_label text
);

create table if not exists public.pulse_response (
  id uuid default gen_random_uuid() not null,
  person_id uuid,
  period text not null,
  score numeric,
  comment text,
  at timestamp with time zone default now() not null
);

create table if not exists public.push_subscription (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  endpoint text not null,
  keys jsonb not null,
  created_at timestamp with time zone default now() not null,
  revoked_at timestamp with time zone
);

create table if not exists public.raisable (
  id uuid default gen_random_uuid() not null,
  kind raisable_kind not null,
  ref text not null,
  raised_by uuid not null,
  about_person uuid,
  department text,
  case_id uuid,
  body text,
  auto_source text,
  pms_points numeric,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.rate (
  id uuid default gen_random_uuid() not null,
  code text not null,
  client_id uuid not null,
  scope rate_scope not null,
  value numeric(12,2) not null,
  currency character(3) default 'INR'::bpchar not null,
  effective_from date not null,
  effective_to date,
  status text default 'active'::text not null,
  reason text,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_by uuid,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.rate_exception (
  id uuid default gen_random_uuid() not null,
  record_id uuid not null,
  kind text not null,
  configured numeric(12,2),
  implied numeric(12,2),
  detected_at timestamp with time zone default now() not null,
  resolved_at timestamp with time zone,
  resolved_by uuid,
  resolution text
);

create table if not exists public.rate_location (
  rate_id uuid not null,
  op_node_id uuid not null
);

create table if not exists public.reason_taxonomy (
  id uuid default gen_random_uuid() not null,
  context text not null,
  code text not null,
  label text not null,
  requires_remarks boolean default true not null,
  implied_attribution text,
  active boolean default true not null,
  pause_eligible boolean default false not null
);

create table if not exists public.ref_counter (
  prefix text not null,
  last_no bigint default 0 not null
);

create table if not exists public.repeat_point_decision (
  id uuid default gen_random_uuid() not null,
  force1_point_id text not null,
  prior_requirement_id uuid not null,
  new_requirement_id uuid,
  address_match text not null,
  match_score integer,
  proposed text not null,
  decision text,
  decided_by uuid,
  decided_at timestamp with time zone,
  reason text,
  asked_at timestamp with time zone default now() not null,
  case_id uuid,
  party_id uuid,
  verification_type_id uuid,
  new_address text,
  assignment_id uuid
);

create table if not exists public.request_task (
  id uuid default gen_random_uuid() not null,
  raisable_id uuid not null,
  responder_id uuid not null,
  due_at timestamp with time zone not null,
  actioned_at timestamp with time zone,
  strike_count integer default 0 not null,
  escalated_case_id uuid
);

create table if not exists public.role_change (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  from_chair_id uuid,
  to_chair_id uuid,
  from_title text,
  to_title text,
  kind text default 'MOVE'::text not null,
  from_date date not null,
  to_date date,
  reason text,
  approved_by uuid,
  recorded_at timestamp with time zone default now() not null
);

create table if not exists public.sample_row (
  table_name text not null,
  row_id uuid not null,
  seeded_at timestamp with time zone default now() not null
);

create table if not exists public.setting (
  key text not null,
  value text not null,
  updated_by uuid,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.sla_clock_segment (
  id uuid default gen_random_uuid() not null,
  sla_instance_id uuid not null,
  seq_no integer not null,
  segment_state text not null,
  attribution text not null,
  counts_to_sla boolean not null,
  counts_to_strike boolean not null,
  reason_id uuid,
  reason_text text,
  opened_at timestamp with time zone not null,
  closed_at timestamp with time zone,
  business_minutes integer,
  set_by uuid
);

create table if not exists public.sla_instance (
  id uuid default gen_random_uuid() not null,
  assignment_id uuid not null,
  breach_cycle_no integer not null,
  sla_rule_id uuid not null,
  rule_trace jsonb default '{}'::jsonb not null,
  calendar_id uuid not null,
  tat_business_minutes integer not null,
  started_at timestamp with time zone not null,
  due_at timestamp with time zone not null,
  extended_to timestamp with time zone,
  stopped_at timestamp with time zone,
  sla_status text default 'ON_TRACK'::text not null
);

create table if not exists public.sla_rule (
  id uuid default gen_random_uuid() not null,
  code text not null,
  version integer not null,
  client_id uuid,
  verification_type_id uuid,
  op_node_id uuid,
  qty_band_min integer,
  qty_band_max integer,
  priority text,
  tat_business_minutes integer not null,
  grace_minutes integer default 0 not null,
  at_risk_pct integer default 75 not null,
  specificity integer default 0 not null,
  effective_from date default CURRENT_DATE not null,
  effective_to date
);

create table if not exists public.strike_event (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  location_id uuid,
  assignment_id uuid,
  breach_cycle_no integer,
  trigger_code text not null,
  occurred_at timestamp with time zone default now() not null,
  attributable_minutes integer,
  strike_no integer,
  status text default 'ACTIVE'::text not null,
  waived_by uuid,
  waived_reason text,
  facts jsonb default '{}'::jsonb not null
);

create table if not exists public.submission_window (
  id uuid default gen_random_uuid() not null,
  kind text not null,
  person_id uuid not null,
  period text not null,
  state text not null,
  opened_by uuid,
  opened_at timestamp with time zone,
  closes_at timestamp with time zone,
  reason text
);

create table if not exists public.target (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  period text not null,
  category text,
  sub_category text,
  client_id uuid,
  target_value numeric,
  achieved_value numeric,
  notes text,
  updated_by uuid,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.task (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  assigned_by uuid not null,
  title text not null,
  detail text,
  due_on date,
  period text not null,
  status text default 'OPEN'::text not null,
  outcome text,
  attribute_weight numeric,
  closed_at timestamp with time zone,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.temp_participant_grant (
  id uuid default gen_random_uuid() not null,
  assignment_id uuid not null,
  person_id uuid not null,
  granted_by uuid not null,
  reason text not null,
  granted_at timestamp with time zone default now() not null,
  expires_at timestamp with time zone not null,
  revoked_at timestamp with time zone
);

create table if not exists public.template (
  id uuid default gen_random_uuid() not null,
  key text not null,
  version integer default 1 not null,
  subject text not null,
  body text not null,
  updated_by uuid,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.upload_batch (
  id uuid default gen_random_uuid() not null,
  kind text not null,
  file_name text not null,
  storage_key text,
  uploaded_by uuid not null,
  uploaded_at timestamp with time zone default now() not null,
  state text default 'PREVIEW'::text not null,
  rows_total integer default 0 not null,
  rows_ok integer default 0 not null,
  rows_error integer default 0 not null,
  applied_at timestamp with time zone,
  applied_by uuid,
  note text
);

create table if not exists public.upload_column (
  kind text not null,
  ord integer not null,
  name text not null,
  example text default ''::text not null,
  rule text default ''::text not null
);

create table if not exists public.upload_kind (
  kind text not null,
  load_order integer not null,
  needs text not null,
  implemented boolean default false not null,
  validator text,
  applier text
);

create table if not exists public.upload_row (
  id uuid default gen_random_uuid() not null,
  batch_id uuid not null,
  row_no integer not null,
  raw jsonb not null,
  error text
);

create table if not exists public.value_correction (
  id uuid default gen_random_uuid() not null,
  entity_type text not null,
  entity_id uuid not null,
  column_name text not null,
  previous_value text,
  new_value text,
  reason text not null,
  corrected_by uuid not null,
  corrected_at timestamp with time zone default now() not null,
  reopened_day date
);

create table if not exists public.verification_case (
  id uuid default gen_random_uuid() not null,
  force1_case_id text not null,
  client_id uuid not null,
  branch_id uuid,
  applicant_name text not null,
  applicant_contact text not null,
  applicant_address text not null,
  pincode text not null,
  completeness_score integer,
  created_by uuid not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.verification_type (
  id uuid default gen_random_uuid() not null,
  code text not null,
  label text not null,
  requires_point_id boolean default true not null,
  active boolean default true not null
);

create table if not exists public.visit (
  id uuid default gen_random_uuid() not null,
  person_id uuid not null,
  visited_on date not null,
  branch_id uuid,
  client_id uuid,
  purpose text,
  answers jsonb default '{}'::jsonb not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.visit_form_field (
  id uuid default gen_random_uuid() not null,
  department text not null,
  "position" integer not null,
  label text not null,
  field_type text default 'text'::text not null,
  required boolean default true not null
);

create table if not exists public.wa_bridge (
  id uuid default gen_random_uuid() not null,
  name text not null,
  device_kind text default 'laptop'::text not null,
  token_hash text not null,
  state text default 'NEW'::text not null,
  phone_number text,
  last_seen_at timestamp with time zone,
  last_sent_at timestamp with time zone,
  last_qr_at timestamp with time zone,
  qr_payload text,
  sent_day date,
  sent_today integer default 0 not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  disabled_at timestamp with time zone,
  note text,
  qr_image text
);

create table if not exists public.wa_bridge_event (
  id uuid default gen_random_uuid() not null,
  bridge_id uuid not null,
  at timestamp with time zone default now() not null,
  kind text not null,
  detail text
);

create table if not exists public.wa_budget (
  day date not null,
  recipients_sent integer default 0 not null,
  cap integer default 1000 not null,
  reserve integer default 0 not null
);

create table if not exists public.wa_outbox (
  id uuid default gen_random_uuid() not null,
  idempotency_key text not null,
  template_key text not null,
  entity_type text,
  entity_id uuid,
  recipient text not null,
  body text not null,
  template_name text,
  template_lang text default 'en'::text,
  template_vars jsonb,
  state outbox_state default 'QUEUED'::outbox_state not null,
  attempts integer default 0 not null,
  not_before timestamp with time zone default now() not null,
  sent_at timestamp with time zone,
  last_error text,
  provider_msg_id text,
  created_at timestamp with time zone default now() not null,
  bridge_id uuid
);

