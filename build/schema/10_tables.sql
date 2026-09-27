-- =====================================================================
-- Crux baseline | 10_tables.sql | tables
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- Columns and defaults only. Keys, checks, foreign keys and indexes each have their own file, so no table in here depends on another and load order is free.
-- =====================================================================

create table if not exists public.ai_call (
  id uuid not null default gen_random_uuid(),
  ai_key_id uuid not null,
  touchpoint text not null,
  at timestamp with time zone not null default now(),
  latency_ms integer,
  ok boolean not null,
  error text,
  actor_id uuid
);

create table if not exists public.ai_key (
  id uuid not null default gen_random_uuid(),
  provider text not null,
  model text not null,
  key_encrypted bytea,
  endpoint text,
  chain_order integer not null,
  scope text not null default 'everything'::text,
  monthly_budget integer not null default 0,
  used_this_month integer not null default 0,
  state text not null default 'untested'::text,
  last_tested_at timestamp with time zone,
  last_latency_ms integer,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.app_page (
  slug text not null,
  html text not null,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.app_setting (
  key text not null,
  value text,
  plain_language text not null,
  group_name text not null,
  secret boolean not null default false,
  editable_by text not null default 'ADMIN'::text,
  updated_by uuid,
  updated_at timestamp with time zone not null default now(),
  in_force boolean not null default true
);

create table if not exists public.assignment (
  id uuid not null default gen_random_uuid(),
  ref text not null,
  case_id uuid not null,
  assignor_id uuid not null,
  assignor_chair_id uuid not null,
  from_location_id uuid not null,
  to_location_id uuid not null,
  allocated_to_id uuid,
  current_state text not null default 'DRAFT'::text,
  next_action_owner_id uuid,
  breach_cycle_no integer not null default 1,
  delay_count integer not null default 0,
  dispute_count integer not null default 0,
  open_request_type text,
  priority_score integer not null default 0,
  priority_bucket text not null default 'Normal'::text,
  self_assign_reason text,
  source_ref text,
  created_at timestamp with time zone not null default now(),
  closed_at timestamp with time zone
);

create table if not exists public.assignment_completion (
  id uuid not null default gen_random_uuid(),
  assignment_id uuid not null,
  breach_cycle_no integer not null,
  shared_at timestamp with time zone not null,
  submitted_at timestamp with time zone not null default now(),
  channel text not null,
  recipient text,
  message_ref text,
  force1_ref text,
  backdate_flagged boolean not null default false,
  other_remarks text,
  submitted_by uuid not null
);

create table if not exists public.assignment_event (
  id bigint not null default nextval('assignment_event_id_seq'::regclass),
  assignment_id uuid not null,
  event_type text not null,
  occurred_at timestamp with time zone not null default now(),
  actor_id uuid,
  actor_chair_id uuid,
  is_system boolean not null default false,
  from_state text,
  to_state text,
  payload jsonb not null default '{}'::jsonb
);

create table if not exists public.assignment_request (
  id uuid not null default gen_random_uuid(),
  assignment_id uuid not null,
  breach_cycle_no integer not null,
  request_type text not null,
  seq_no integer not null,
  raised_by uuid not null,
  raised_at timestamp with time zone not null default now(),
  reason_id uuid,
  remarks text,
  delay_category text,
  expected_completion timestamp with time zone,
  sub_tat_minutes integer,
  sub_tat_due_at timestamp with time zone,
  sub_tat_breached boolean not null default false,
  pause_granted boolean not null default false,
  pause_minutes_credited integer not null default 0,
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
  id uuid not null default gen_random_uuid(),
  at timestamp with time zone not null default now(),
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
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  created_at timestamp with time zone not null default now(),
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
  enabled boolean not null default true,
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
  id uuid not null default gen_random_uuid(),
  key text not null,
  started_at timestamp with time zone not null default now(),
  finished_at timestamp with time zone,
  outcome text,
  affected integer not null default 0,
  detail text
);

create table if not exists public.branch (
  id uuid not null default gen_random_uuid(),
  client_id uuid not null,
  code text not null,
  name text not null,
  address text,
  geo_node_id uuid,
  client_zone_id uuid,
  status entity_status not null default 'ACTIVE'::entity_status,
  effective_from date,
  effective_to date,
  notes text,
  source_ref text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  op_node_id uuid
);

create table if not exists public.branch_contact (
  id uuid not null default gen_random_uuid(),
  branch_id uuid not null,
  role text not null,
  person_id uuid,
  name text,
  mobile text,
  email text,
  active boolean not null default true
);

create table if not exists public.branch_generation_map (
  old_branch_id uuid not null,
  new_branch_id uuid not null,
  old_client_id uuid not null,
  new_client_id uuid not null,
  matched_on text not null,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.business_calendar (
  id uuid not null default gen_random_uuid(),
  code text not null,
  geo_node_id uuid,
  window_start time without time zone not null default '10:00:00'::time without time zone,
  window_end time without time zone not null default '17:00:00'::time without time zone,
  works_saturday boolean not null default false,
  works_sunday boolean not null default false,
  timezone text not null default 'Asia/Kolkata'::text,
  effective_from date not null default CURRENT_DATE,
  effective_to date
);

create table if not exists public.business_record (
  id uuid not null default gen_random_uuid(),
  period character(7) not null,
  business_date date not null,
  client_id uuid not null,
  geo_node_id uuid not null,
  owner_id uuid,
  mtd integer not null default 0,
  day10 integer not null default 0,
  target integer not null default 0,
  revenue numeric(14,2) not null default 0,
  source_ref text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
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
  id uuid not null default gen_random_uuid(),
  name text not null,
  knowledge_test text,
  unlock text
);

create table if not exists public."case" (
  id uuid not null default gen_random_uuid(),
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
  status case_status not null default 'OPEN'::case_status,
  resolution_note text,
  resolved_at timestamp with time zone,
  auto_close_at timestamp with time zone,
  next_chase_at timestamp with time zone,
  strike_count integer not null default 0,
  last_activity_at timestamp with time zone not null default now(),
  closed_at timestamp with time zone,
  source_ref text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.case_event (
  id uuid not null default gen_random_uuid(),
  case_id uuid not null,
  at timestamp with time zone not null default now(),
  actor_id uuid,
  kind text,
  field text,
  old_value text,
  new_value text,
  note text
);

create table if not exists public.case_party (
  id uuid not null default gen_random_uuid(),
  case_id uuid not null,
  party_role text not null,
  seq_no integer not null,
  name text not null,
  contact text,
  address text,
  same_as_applicant boolean not null default false
);

create table if not exists public.case_verification_requirement (
  id uuid not null default gen_random_uuid(),
  case_id uuid not null,
  party_id uuid not null,
  verification_type_id uuid not null,
  force1_point_id text not null,
  attempt_no integer not null default 1,
  lineage text not null default 'ORIGINAL'::text,
  supersedes_id uuid,
  status text not null default 'PENDING'::text,
  outcome text,
  remarks text,
  findings jsonb not null default '{}'::jsonb,
  reported_at timestamp with time zone,
  reported_by uuid
);

create table if not exists public.category (
  id uuid not null default gen_random_uuid(),
  name text not null,
  desk_id uuid not null,
  pinned boolean not null default false,
  chase_hours integer,
  active boolean not null default true
);

create table if not exists public.chair (
  id uuid not null default gen_random_uuid(),
  code text not null,
  title text not null,
  desk_id uuid,
  parent_id uuid,
  level text not null,
  reports_daily boolean not null default false,
  sg_level text,
  function_name text,
  band text,
  purpose text,
  capability_track_id uuid,
  source_ref text
);

create table if not exists public.chair_accountability (
  id uuid not null default gen_random_uuid(),
  chair_id uuid not null,
  ord integer not null,
  statement text not null,
  source_ref text
);

create table if not exists public.chair_authority (
  id uuid not null default gen_random_uuid(),
  chair_id uuid not null,
  kind text not null,
  ord integer not null,
  statement text not null,
  source_ref text
);

create table if not exists public.chair_holder (
  id uuid not null default gen_random_uuid(),
  chair_id uuid not null,
  person_id uuid not null,
  is_primary boolean not null default false,
  from_date date not null default CURRENT_DATE,
  to_date date,
  seating_id uuid
);

create table if not exists public.chair_measure (
  id uuid not null default gen_random_uuid(),
  chair_id uuid not null,
  ord integer not null,
  statement text not null,
  source_ref text
);

create table if not exists public.chair_seating (
  id uuid not null default gen_random_uuid(),
  chair_id uuid not null,
  scope_label text,
  reports_to_chair_id uuid,
  holder_text text,
  note text,
  source_ref text,
  reports_to_seating_id uuid
);

create table if not exists public.chair_subtask (
  id uuid not null default gen_random_uuid(),
  task_id uuid not null,
  ord integer not null,
  statement text not null
);

create table if not exists public.chair_task (
  id uuid not null default gen_random_uuid(),
  chair_id uuid not null,
  ord integer not null,
  task text not null
);

create table if not exists public.claim (
  id uuid not null default gen_random_uuid(),
  ref text not null,
  visit_id uuid,
  person_id uuid not null,
  amount numeric not null,
  stage claim_stage not null default 'DRAFT'::claim_stage,
  ops_by uuid,
  ops_at timestamp with time zone,
  hr_by uuid,
  hr_at timestamp with time zone,
  accounts_by uuid,
  accounts_at timestamp with time zone,
  paid_ref text,
  dispute_reason text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.client (
  id uuid not null default gen_random_uuid(),
  code text not null,
  name text not null,
  status entity_status not null default 'ACTIVE'::entity_status,
  effective_from date,
  effective_to date,
  notes text,
  source_ref text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.client_contact (
  id uuid not null default gen_random_uuid(),
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
  id uuid not null default gen_random_uuid(),
  client_id uuid not null,
  name text not null,
  geo_node_id uuid
);

create table if not exists public.coverage_rule (
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  role text not null,
  scope_type scope_kind not null,
  client_id uuid,
  client_zone_id uuid,
  geo_node_id uuid,
  branch_id uuid,
  effective_from date not null default CURRENT_DATE,
  effective_to date,
  source_ref text,
  created_at timestamp with time zone not null default now(),
  is_assigned_handler boolean not null default false,
  product text,
  op_node_id uuid
);

create table if not exists public.cutover_check (
  id bigint not null default nextval('cutover_check_id_seq'::regclass),
  at timestamp with time zone not null default now(),
  check_name text not null,
  expectation text not null,
  outcome text not null,
  detail text,
  result text not null
);

create table if not exists public.daily_count (
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  count_date date not null,
  kpi_id uuid,
  value numeric,
  submitted_at timestamp with time zone not null default now(),
  locked_at timestamp with time zone,
  reopened_by uuid,
  reopen_reason text,
  entered_at timestamp with time zone not null,
  received_at timestamp with time zone not null default now(),
  entered_offline boolean not null default false,
  device_ref text,
  sync_attempts integer not null default 0,
  late_sync boolean not null default false,
  clock_skew_flag boolean not null default false,
  counts_to_mis boolean not null default false,
  "values" jsonb
);

create table if not exists public.daily_note (
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  note_date date not null,
  body text not null,
  classification note_class not null default 'UNCLASSIFIED'::note_class,
  attribute_heading text,
  model_reason text,
  classified_at timestamp with time zone,
  included_in_review boolean not null default true
);

create table if not exists public.day_reopen (
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  day date not null,
  reason text not null,
  opened_by uuid not null,
  opened_at timestamp with time zone not null default now(),
  closes_at timestamp with time zone not null,
  closed_at timestamp with time zone
);

create table if not exists public.delivery (
  id uuid not null default gen_random_uuid(),
  outbox_id uuid,
  channel text not null default 'EMAIL'::text,
  recipient text not null,
  state text not null,
  error text,
  at timestamp with time zone not null default now(),
  provider_ref text,
  entity_type text,
  entity_id uuid
);

create table if not exists public.designation (
  id uuid not null default gen_random_uuid(),
  title text not null,
  desk_id uuid,
  is_desk_head boolean not null default false,
  seniority integer not null default 0
);

create table if not exists public.desk (
  id uuid not null default gen_random_uuid(),
  name text not null,
  primary_person_id uuid,
  escalation_only boolean not null default false,
  fallback_desk_id uuid
);

create table if not exists public.email_domain_alias (
  wrong text not null,
  correct text not null,
  noted_by text,
  noted_at timestamp with time zone not null default now()
);

create table if not exists public.escalation_action (
  id uuid not null default gen_random_uuid(),
  code text not null,
  label text not null,
  pms_impact boolean not null,
  unlock_after_working_days integer,
  sets_tat_hours integer,
  routes_to text,
  sets_status case_status,
  valid_statuses case_status[],
  allowed_parts esc_party[] not null default '{}'::esc_party[],
  needs_note boolean not null default false
);

create table if not exists public.escalation_action_log (
  id uuid not null default gen_random_uuid(),
  case_id uuid not null,
  action_code text not null,
  actor_id uuid not null,
  at timestamp with time zone not null default now(),
  note text
);

create table if not exists public.escalation_instance (
  id uuid not null default gen_random_uuid(),
  assignment_id uuid not null,
  breach_cycle_no integer not null,
  escalation_level integer not null,
  trigger_code text not null,
  idempotency_key text not null,
  resolved_to_id uuid,
  resolved_chair_id uuid,
  route_trace jsonb not null default '{}'::jsonb,
  fallback_used boolean not null default false,
  fallback_reason text,
  raised_at timestamp with time zone not null default now(),
  closed_at timestamp with time zone,
  closed_by uuid
);

create table if not exists public.escalation_party (
  case_id uuid not null,
  person_id uuid not null,
  part esc_party not null
);

create table if not exists public.forecast_config (
  id smallint not null default 1,
  scenarios jsonb not null default '[{"key": "cons", "mult": 3.25, "label": "Conservative"}, {"key": "base", "mult": 3.5, "label": "Base"}, {"key": "stretch", "mult": 4, "label": "Stretch"}, {"key": "agg", "kept": true, "mult": 5, "label": "Aggressive"}]'::jsonb,
  updated_by uuid,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.geo_node (
  id uuid not null default gen_random_uuid(),
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
  applies_to text not null default 'ALL'::text,
  source text,
  created_at timestamp with time zone not null default now(),
  confirmed boolean not null default true,
  batch_id uuid
);

create table if not exists public.holiday_centre_alias (
  city text not null,
  centre text not null,
  noted_by text,
  noted_at timestamp with time zone not null default now()
);

create table if not exists public.idea (
  id uuid not null default gen_random_uuid(),
  ref text not null,
  title text not null,
  body text not null,
  raised_by uuid not null,
  stage idea_stage not null default 'SUBMITTED'::idea_stage,
  sponsor_id uuid,
  owner_dept text,
  charter text,
  decided_by uuid,
  decided_at timestamp with time zone,
  decision_reason text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.idea_collaborator (
  idea_id uuid not null,
  person_id uuid not null,
  role text not null default 'COLLABORATOR'::text
);

create table if not exists public.job_config (
  job_key text not null,
  enabled boolean not null default true,
  cron text not null,
  disabled_by uuid,
  disabled_at timestamp with time zone,
  reason text
);

create table if not exists public.job_run (
  id uuid not null default gen_random_uuid(),
  job_key text not null,
  started_at timestamp with time zone not null default now(),
  finished_at timestamp with time zone,
  state text,
  note text,
  result job_result,
  counts jsonb,
  error text,
  next_due_at timestamp with time zone
);

create table if not exists public.kpi_definition (
  id uuid not null default gen_random_uuid(),
  chair_id uuid,
  person_id uuid,
  name text not null,
  unit text,
  active boolean not null default true,
  mandatory boolean not null default true,
  "position" integer not null default 1,
  parent_id uuid,
  cadence kpi_cadence not null default 'DAILY'::kpi_cadence,
  accrual kpi_accrual not null default 'ADDS'::kpi_accrual
);

create table if not exists public.kpi_eligibility (
  id uuid not null default gen_random_uuid(),
  kpi_id uuid,
  person_id uuid,
  chair_id uuid,
  scope_all boolean not null default false,
  gate text not null,
  on_miss text not null,
  deduct_points numeric,
  default_score numeric,
  set_by uuid
);

create table if not exists public.kpi_target (
  id uuid not null default gen_random_uuid(),
  kpi_id uuid not null,
  person_id uuid not null,
  period text not null,
  target_value numeric not null,
  set_by uuid not null,
  set_at timestamp with time zone not null default now(),
  parent_target_id uuid
);

create table if not exists public.letter (
  id uuid not null default gen_random_uuid(),
  kind text not null,
  person_id uuid not null,
  case_id uuid,
  issued_by uuid not null,
  issued_at timestamp with time zone not null default now(),
  body text not null,
  acknowledged_at timestamp with time zone,
  due_ack_at timestamp with time zone not null,
  copied_to text[]
);

create table if not exists public.login_attempt (
  id bigint not null default nextval('login_attempt_id_seq'::regclass),
  at timestamp with time zone not null default now(),
  email text not null,
  ip text,
  ok boolean not null
);

create table if not exists public.mail_alias (
  id uuid not null default gen_random_uuid(),
  address text not null,
  verified boolean not null default false
);

create table if not exists public.mail_bounce (
  id uuid not null default gen_random_uuid(),
  address text not null,
  at timestamp with time zone not null default now(),
  hard boolean not null,
  strikes integer not null default 1,
  unreachable boolean not null default false
);

create table if not exists public.mail_budget (
  day date not null,
  recipients_sent integer not null default 0,
  cap integer not null default 1800,
  reserve integer not null default 200
);

create table if not exists public.mail_config (
  id smallint not null default 1,
  mailbox text not null,
  auth_mode text not null,
  service_account_email text,
  delegation_client_id text,
  reply_to text,
  daily_budget integer not null default 1800,
  used_today integer not null default 0,
  signature_json jsonb,
  signature_logo_file uuid,
  test_mode boolean not null default false,
  test_address text,
  test_mode_expires_at timestamp with time zone,
  bounce_strikes integer not null default 3,
  last_tested_at timestamp with time zone,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.matrix_contact (
  id uuid not null default gen_random_uuid(),
  client_id uuid not null,
  branch_id uuid,
  level integer not null,
  level_name text not null,
  person_id uuid,
  name text,
  mobile text,
  email text,
  updated_by uuid,
  updated_at timestamp with time zone not null default now(),
  source_ref text
);

create table if not exists public.matrix_dispatch (
  id uuid not null default gen_random_uuid(),
  client_id uuid not null,
  period date not null,
  snapshot jsonb not null,
  branch_count integer not null,
  held_back integer not null default 0,
  recipients text[] not null default '{}'::text[],
  prepared_by uuid not null,
  prepared_at timestamp with time zone not null default now(),
  sent_at timestamp with time zone,
  note text
);

create table if not exists public.migration_merge (
  id uuid not null default gen_random_uuid(),
  at timestamp with time zone not null default now(),
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
  id uuid not null default gen_random_uuid(),
  entity_type text not null,
  entity_ref text not null,
  question text not null,
  context text,
  resolved_to text,
  resolved_by uuid,
  resolved_at timestamp with time zone
);

create table if not exists public.mis_saved_view (
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  name text not null,
  config jsonb not null,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.mis_view (
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  name text not null,
  config jsonb not null,
  created_at timestamp with time zone not null default now(),
  used_at timestamp with time zone
);

create table if not exists public.notification (
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  kind text not null,
  text text not null,
  entity_type text,
  entity_id uuid,
  push boolean not null default false,
  at timestamp with time zone not null default now(),
  read_at timestamp with time zone
);

create table if not exists public.ogl_attachment (
  id uuid not null default gen_random_uuid(),
  assignment_id uuid not null,
  party_kind ogl_party_kind not null,
  party_seq integer not null default 0,
  doc_kind text not null,
  file_name text not null,
  storage_key text not null,
  bytes bigint,
  mime text,
  uploaded_by uuid not null,
  uploaded_at timestamp with time zone not null default now(),
  removed_at timestamp with time zone,
  removed_by uuid,
  requirement_id uuid,
  caption text
);

create table if not exists public.ogl_escalation_matrix (
  id uuid not null default gen_random_uuid(),
  client_id uuid,
  location_id uuid,
  branch_id uuid,
  escalation_level integer not null,
  chair_id uuid,
  person_id uuid,
  sequence_no integer not null default 1,
  effective_from date not null default CURRENT_DATE,
  effective_to date
);

create table if not exists public.ogl_transition_rule (
  from_state text not null,
  to_state text not null,
  trigger_name text not null,
  guard_note text
);

create table if not exists public.onboarding (
  id uuid not null default gen_random_uuid(),
  person_request_id uuid,
  person_id uuid,
  induction_on date,
  buddy_id uuid,
  documents_ok boolean not null default false,
  completed_at timestamp with time zone
);

create table if not exists public.op_node (
  id uuid not null default gen_random_uuid(),
  parent_id uuid,
  level text not null,
  name text not null,
  active boolean not null default true,
  sort integer not null default 100,
  source_ref text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.op_node_alias (
  written_as text not null,
  means text not null,
  note text,
  created_by uuid,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.ops_alert (
  id uuid not null default gen_random_uuid(),
  kind text not null,
  severity text not null default 'WARN'::text,
  title text not null,
  detail text,
  action_hint text,
  for_role text not null default 'ADMIN'::text,
  entity_type text,
  entity_id uuid,
  dedupe_key text not null,
  retry_at timestamp with time zone,
  opened_at timestamp with time zone not null default now(),
  last_seen_at timestamp with time zone not null default now(),
  occurrences integer not null default 1,
  acknowledged_by uuid,
  acknowledged_at timestamp with time zone,
  resolved_at timestamp with time zone,
  resolved_note text
);

create table if not exists public.otp_challenge (
  id uuid not null default gen_random_uuid(),
  mobile text not null,
  code_hash bytea not null,
  purpose text not null,
  expires_at timestamp with time zone not null,
  consumed_at timestamp with time zone,
  attempts integer not null default 0
);

create table if not exists public.outbox (
  id uuid not null default gen_random_uuid(),
  idempotency_key text not null,
  template_key text not null,
  entity_type text,
  entity_id uuid,
  recipient text not null,
  cc_addr text,
  subject text not null,
  body text not null,
  state outbox_state not null default 'QUEUED'::outbox_state,
  attempts integer not null default 0,
  not_before timestamp with time zone not null default now(),
  sent_at timestamp with time zone,
  last_error text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.penalty_instance (
  id uuid not null default gen_random_uuid(),
  rule_id uuid not null,
  person_id uuid not null,
  period text not null,
  occurred_on date not null,
  cutoff_missed text not null,
  evidence text not null,
  entity_type text,
  entity_id uuid,
  amount numeric not null,
  state penalty_state not null default 'APPLIED'::penalty_state,
  waived_by uuid,
  waive_reason text,
  recovered_by text not null,
  recovered_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  sync_evidence jsonb
);

create table if not exists public.penalty_rule (
  id uuid not null default gen_random_uuid(),
  code text not null,
  what text not null,
  plain_language text not null,
  applies_to text not null,
  frequency text not null,
  cutoff_spec text not null,
  amount numeric not null,
  recovered_by text not null,
  active boolean not null default true,
  effective_from date not null default CURRENT_DATE,
  created_by uuid,
  applies_to_list text[] not null default '{Everybody}'::text[]
);

create table if not exists public.perf_assignment (
  id uuid not null default gen_random_uuid(),
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
  set_at timestamp with time zone not null default now(),
  state text not null default 'ISSUED'::text,
  carried_from_id uuid,
  note text,
  cadence kpi_cadence
);

create table if not exists public.perf_collection (
  id uuid not null default gen_random_uuid(),
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
  loaded_at timestamp with time zone not null default now()
);

create table if not exists public.perf_cycle (
  id uuid not null default gen_random_uuid(),
  period_start date not null,
  period_kind text not null default 'MONTH'::text,
  assign_opens date not null,
  assign_closes date not null,
  entry_closes date not null,
  state text not null default 'OPEN'::text,
  opened_by uuid,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.perf_entry (
  id uuid not null default gen_random_uuid(),
  assignment_id uuid not null,
  as_of date not null,
  value numeric not null,
  note text,
  filed_by uuid not null,
  filed_at timestamp with time zone not null default now()
);

create table if not exists public.perf_month (
  id uuid not null default gen_random_uuid(),
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
  loaded_at timestamp with time zone not null default now()
);

create table if not exists public.perf_revenue (
  id uuid not null default gen_random_uuid(),
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
  loaded_at timestamp with time zone not null default now()
);

create table if not exists public.person (
  id uuid not null default gen_random_uuid(),
  employee_no text,
  full_name text not null,
  work_email text,
  personal_email text,
  mobile text,
  designation_id uuid,
  department text,
  manager_id uuid,
  app_role role_kind not null default 'VIEWER'::role_kind,
  employment_status entity_status not null default 'ACTIVE'::entity_status,
  joined_on date,
  left_on date,
  superseded_by uuid,
  source_ref text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  employee_type text not null default 'EMPLOYEE'::text,
  user_id text,
  mobile_verified_at timestamp with time zone,
  password_hash text,
  password_salt text,
  auth_user_id uuid,
  address text,
  emergency_contact text
);

create table if not exists public.person_document (
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  kind text not null,
  state text not null default 'WITH_HR'::text,
  note text,
  updated_by uuid,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.person_event (
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  kind text not null,
  at timestamp with time zone not null default now(),
  start_on date,
  end_on date,
  note text,
  issued_by uuid,
  status text,
  outcome text,
  case_id uuid,
  source_ref text,
  note_class note_class not null default 'UNCLASSIFIED'::note_class,
  actor_id uuid
);

create table if not exists public.person_request (
  id uuid not null default gen_random_uuid(),
  full_name text not null,
  work_email text not null,
  chair_id uuid not null,
  manager_id uuid not null,
  requested_by uuid not null,
  requested_at timestamp with time zone not null default now(),
  state approval_state not null default 'AWAITING_HR'::approval_state,
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
  created_at timestamp with time zone not null default now(),
  employee_type text not null default 'EMPLOYEE'::text
);

create table if not exists public.plb_correction (
  id uuid not null default gen_random_uuid(),
  what text not null,
  row_id uuid not null,
  field text not null,
  was text,
  now_is text,
  why text not null,
  who uuid not null,
  at timestamp with time zone not null default now()
);

create table if not exists public.plb_dispute (
  id uuid not null default gen_random_uuid(),
  sheet_id uuid not null,
  element text not null,
  kpi_id uuid,
  month date,
  claimed text not null,
  claimed_value numeric,
  evidence text not null,
  raised_by uuid not null,
  raised_at timestamp with time zone not null default now(),
  stage text not null default 'RAISED'::text,
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
  id uuid not null default gen_random_uuid(),
  sheet_id uuid not null,
  kpi_id uuid not null,
  proposal text,
  approved_at timestamp with time zone,
  state text not null default 'EMPTY'::text,
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
  id uuid not null default gen_random_uuid(),
  sheet_id uuid not null,
  kpi_id uuid not null,
  weight_pct numeric(6,3) not null,
  target_value numeric(16,4),
  basis_level integer,
  basis_note text,
  m1_share numeric(6,3) not null default 0,
  m2_share numeric(6,3) not null default 0,
  m3_share numeric(6,3) not null default 0,
  actual_value numeric(16,4)
);

create table if not exists public.plb_goal_sheet (
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  chair_id uuid not null,
  quarter date not null,
  target_plb_inr numeric(14,2) not null,
  status text not null default 'DRAFT'::text,
  issued_by uuid,
  issued_at timestamp with time zone,
  acknowledged_at timestamp with time zone,
  locked_at timestamp with time zone,
  is_default boolean not null default false,
  note text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.plb_month_score (
  id uuid not null default gen_random_uuid(),
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
  excluded boolean not null default false,
  excluded_why text,
  countersign_by uuid,
  countersign_at timestamp with time zone
);

create table if not exists public.plb_result (
  id uuid not null default gen_random_uuid(),
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
  id uuid not null default gen_random_uuid(),
  cycle_id uuid not null,
  source_kind raisable_kind not null,
  source_id uuid,
  half text not null,
  points numeric not null,
  applied boolean not null default true,
  capped boolean not null default false,
  reason text not null,
  at timestamp with time zone not null default now(),
  over_cap boolean not null default false,
  actor_id uuid
);

create table if not exists public.pms_band_result (
  cycle_id uuid not null,
  band_id uuid,
  final numeric not null,
  floored boolean not null default false,
  excluded boolean not null default false,
  at timestamp with time zone not null default now()
);

create table if not exists public.pms_component (
  id uuid not null default gen_random_uuid(),
  cycle_id uuid not null,
  kind text not null,
  raw numeric not null,
  weight_pct numeric not null,
  note text
);

create table if not exists public.pms_curve_band (
  id uuid not null default gen_random_uuid(),
  effective_fy text not null,
  rank integer not null,
  label text not null,
  share_pct numeric not null
);

create table if not exists public.pms_cycle (
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  chair_id uuid,
  period date not null,
  state pms_cycle_state not null default 'PENDING'::pms_cycle_state,
  window_opens timestamp with time zone,
  window_closes timestamp with time zone,
  self_due timestamp with time zone,
  self_at timestamp with time zone,
  review_due timestamp with time zone,
  scored_at timestamp with time zone,
  closed_at timestamp with time zone,
  on_probation boolean not null default false,
  is_partner boolean not null default false
);

create table if not exists public.pms_dispute (
  id uuid not null default gen_random_uuid(),
  cycle_id uuid not null,
  raised_by uuid not null,
  raised_at timestamp with time zone not null default now(),
  reason text not null,
  hr_due timestamp with time zone not null,
  decided_by uuid,
  decided_at timestamp with time zone,
  outcome text,
  outcome_note text
);

create table if not exists public.pms_exception (
  id uuid not null default gen_random_uuid(),
  cycle_id uuid not null,
  requested_by uuid not null,
  requested_at timestamp with time zone not null default now(),
  reason text not null,
  hr_due timestamp with time zone not null,
  state text not null default 'PENDING'::text,
  decided_by uuid,
  decided_at timestamp with time zone,
  reopens_until timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  due_at timestamp with time zone
);

create table if not exists public.pms_impact (
  kind raisable_kind not null,
  points numeric not null,
  applies_to text not null default 'PERSON_CONCERNED'::text,
  set_by uuid,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pms_score (
  id uuid not null default gen_random_uuid(),
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
  id uuid not null default gen_random_uuid(),
  scope_all boolean not null default false,
  chair_id uuid,
  person_id uuid,
  kpi_percent numeric not null,
  attr_percent numeric not null,
  effective_from date not null default CURRENT_DATE,
  set_by uuid
);

create table if not exists public.portal_link (
  id uuid not null default gen_random_uuid(),
  client_id uuid,
  branch_id uuid,
  token_hash text not null,
  created_at timestamp with time zone not null default now(),
  rotated_at timestamp with time zone,
  revoked_at timestamp with time zone
);

create table if not exists public.process (
  id uuid not null default gen_random_uuid(),
  ref text not null,
  function text not null,
  name text not null,
  owner_chair_id uuid not null
);

create table if not exists public.process_input (
  id uuid not null default gen_random_uuid(),
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
  id uuid not null default gen_random_uuid(),
  process_id uuid not null,
  ref text not null,
  scope_label text
);

create table if not exists public.pulse_response (
  id uuid not null default gen_random_uuid(),
  person_id uuid,
  period text not null,
  score numeric,
  comment text,
  at timestamp with time zone not null default now()
);

create table if not exists public.push_subscription (
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  endpoint text not null,
  keys jsonb not null,
  created_at timestamp with time zone not null default now(),
  revoked_at timestamp with time zone
);

create table if not exists public.raisable (
  id uuid not null default gen_random_uuid(),
  kind raisable_kind not null,
  ref text not null,
  raised_by uuid not null,
  about_person uuid,
  department text,
  case_id uuid,
  body text,
  auto_source text,
  pms_points numeric,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.rate (
  id uuid not null default gen_random_uuid(),
  code text not null,
  client_id uuid not null,
  scope rate_scope not null,
  value numeric(12,2) not null,
  currency character(3) not null default 'INR'::bpchar,
  effective_from date not null,
  effective_to date,
  status text not null default 'active'::text,
  reason text,
  created_by uuid,
  created_at timestamp with time zone not null default now(),
  updated_by uuid,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.rate_exception (
  id uuid not null default gen_random_uuid(),
  record_id uuid not null,
  kind text not null,
  configured numeric(12,2),
  implied numeric(12,2),
  detected_at timestamp with time zone not null default now(),
  resolved_at timestamp with time zone,
  resolved_by uuid,
  resolution text
);

create table if not exists public.rate_location (
  rate_id uuid not null,
  op_node_id uuid not null
);

create table if not exists public.reason_taxonomy (
  id uuid not null default gen_random_uuid(),
  context text not null,
  code text not null,
  label text not null,
  requires_remarks boolean not null default true,
  implied_attribution text,
  active boolean not null default true,
  pause_eligible boolean not null default false
);

create table if not exists public.ref_counter (
  prefix text not null,
  last_no bigint not null default 0
);

create table if not exists public.repeat_point_decision (
  id uuid not null default gen_random_uuid(),
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
  asked_at timestamp with time zone not null default now(),
  case_id uuid,
  party_id uuid,
  verification_type_id uuid,
  new_address text,
  assignment_id uuid
);

create table if not exists public.request_task (
  id uuid not null default gen_random_uuid(),
  raisable_id uuid not null,
  responder_id uuid not null,
  due_at timestamp with time zone not null,
  actioned_at timestamp with time zone,
  strike_count integer not null default 0,
  escalated_case_id uuid
);

create table if not exists public.role_change (
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  from_chair_id uuid,
  to_chair_id uuid,
  from_title text,
  to_title text,
  kind text not null default 'MOVE'::text,
  from_date date not null,
  to_date date,
  reason text,
  approved_by uuid,
  recorded_at timestamp with time zone not null default now()
);

create table if not exists public.sample_row (
  table_name text not null,
  row_id uuid not null,
  seeded_at timestamp with time zone not null default now()
);

create table if not exists public.setting (
  key text not null,
  value text not null,
  updated_by uuid,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.sla_clock_segment (
  id uuid not null default gen_random_uuid(),
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
  id uuid not null default gen_random_uuid(),
  assignment_id uuid not null,
  breach_cycle_no integer not null,
  sla_rule_id uuid not null,
  rule_trace jsonb not null default '{}'::jsonb,
  calendar_id uuid not null,
  tat_business_minutes integer not null,
  started_at timestamp with time zone not null,
  due_at timestamp with time zone not null,
  extended_to timestamp with time zone,
  stopped_at timestamp with time zone,
  sla_status text not null default 'ON_TRACK'::text
);

create table if not exists public.sla_rule (
  id uuid not null default gen_random_uuid(),
  code text not null,
  version integer not null,
  client_id uuid,
  verification_type_id uuid,
  op_node_id uuid,
  qty_band_min integer,
  qty_band_max integer,
  priority text,
  tat_business_minutes integer not null,
  grace_minutes integer not null default 0,
  at_risk_pct integer not null default 75,
  specificity integer not null default 0,
  effective_from date not null default CURRENT_DATE,
  effective_to date
);

create table if not exists public.strike_event (
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  location_id uuid,
  assignment_id uuid,
  breach_cycle_no integer,
  trigger_code text not null,
  occurred_at timestamp with time zone not null default now(),
  attributable_minutes integer,
  strike_no integer,
  status text not null default 'ACTIVE'::text,
  waived_by uuid,
  waived_reason text,
  facts jsonb not null default '{}'::jsonb
);

create table if not exists public.submission_window (
  id uuid not null default gen_random_uuid(),
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
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  period text not null,
  category text,
  sub_category text,
  client_id uuid,
  target_value numeric,
  achieved_value numeric,
  notes text,
  updated_by uuid,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.task (
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  assigned_by uuid not null,
  title text not null,
  detail text,
  due_on date,
  period text not null,
  status text not null default 'OPEN'::text,
  outcome text,
  attribute_weight numeric,
  closed_at timestamp with time zone,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.temp_participant_grant (
  id uuid not null default gen_random_uuid(),
  assignment_id uuid not null,
  person_id uuid not null,
  granted_by uuid not null,
  reason text not null,
  granted_at timestamp with time zone not null default now(),
  expires_at timestamp with time zone not null,
  revoked_at timestamp with time zone
);

create table if not exists public.template (
  id uuid not null default gen_random_uuid(),
  key text not null,
  version integer not null default 1,
  subject text not null,
  body text not null,
  updated_by uuid,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.upload_batch (
  id uuid not null default gen_random_uuid(),
  kind text not null,
  file_name text not null,
  storage_key text,
  uploaded_by uuid not null,
  uploaded_at timestamp with time zone not null default now(),
  state text not null default 'PREVIEW'::text,
  rows_total integer not null default 0,
  rows_ok integer not null default 0,
  rows_error integer not null default 0,
  applied_at timestamp with time zone,
  applied_by uuid,
  note text
);

create table if not exists public.upload_column (
  kind text not null,
  ord integer not null,
  name text not null,
  example text not null default ''::text,
  rule text not null default ''::text
);

create table if not exists public.upload_kind (
  kind text not null,
  load_order integer not null,
  needs text not null,
  implemented boolean not null default false,
  validator text,
  applier text
);

create table if not exists public.upload_row (
  id uuid not null default gen_random_uuid(),
  batch_id uuid not null,
  row_no integer not null,
  raw jsonb not null,
  error text
);

create table if not exists public.value_correction (
  id uuid not null default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  column_name text not null,
  previous_value text,
  new_value text,
  reason text not null,
  corrected_by uuid not null,
  corrected_at timestamp with time zone not null default now(),
  reopened_day date
);

create table if not exists public.verification_case (
  id uuid not null default gen_random_uuid(),
  force1_case_id text not null,
  client_id uuid not null,
  branch_id uuid,
  applicant_name text not null,
  applicant_contact text not null,
  applicant_address text not null,
  pincode text not null,
  completeness_score integer,
  created_by uuid not null,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.verification_type (
  id uuid not null default gen_random_uuid(),
  code text not null,
  label text not null,
  requires_point_id boolean not null default true,
  active boolean not null default true
);

create table if not exists public.visit (
  id uuid not null default gen_random_uuid(),
  person_id uuid not null,
  visited_on date not null,
  branch_id uuid,
  client_id uuid,
  purpose text,
  answers jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.visit_form_field (
  id uuid not null default gen_random_uuid(),
  department text not null,
  "position" integer not null,
  label text not null,
  field_type text not null default 'text'::text,
  required boolean not null default true
);

create table if not exists public.wa_bridge (
  id uuid not null default gen_random_uuid(),
  name text not null,
  device_kind text not null default 'laptop'::text,
  token_hash text not null,
  state text not null default 'NEW'::text,
  phone_number text,
  last_seen_at timestamp with time zone,
  last_sent_at timestamp with time zone,
  last_qr_at timestamp with time zone,
  qr_payload text,
  sent_day date,
  sent_today integer not null default 0,
  created_by uuid,
  created_at timestamp with time zone not null default now(),
  disabled_at timestamp with time zone,
  note text,
  qr_image text
);

create table if not exists public.wa_bridge_event (
  id uuid not null default gen_random_uuid(),
  bridge_id uuid not null,
  at timestamp with time zone not null default now(),
  kind text not null,
  detail text
);

create table if not exists public.wa_budget (
  day date not null,
  recipients_sent integer not null default 0,
  cap integer not null default 1000,
  reserve integer not null default 0
);

create table if not exists public.wa_outbox (
  id uuid not null default gen_random_uuid(),
  idempotency_key text not null,
  template_key text not null,
  entity_type text,
  entity_id uuid,
  recipient text not null,
  body text not null,
  template_name text,
  template_lang text default 'en'::text,
  template_vars jsonb,
  state outbox_state not null default 'QUEUED'::outbox_state,
  attempts integer not null default 0,
  not_before timestamp with time zone not null default now(),
  sent_at timestamp with time zone,
  last_error text,
  provider_msg_id text,
  created_at timestamp with time zone not null default now(),
  bridge_id uuid
);

