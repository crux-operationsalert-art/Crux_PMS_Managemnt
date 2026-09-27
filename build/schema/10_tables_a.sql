-- =====================================================================
-- Crux baseline · 10a · tables, A to L
-- GENERATED. Columns and defaults only; keys, checks and indexes are in 20
-- and 30, so a circular foreign key cannot make the load order impossible.
-- =====================================================================

create sequence if not exists public.assignment_event_id_seq;
create sequence if not exists public.cutover_check_id_seq;
create sequence if not exists public.login_attempt_id_seq;

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
