-- =====================================================================
-- Crux baseline · 10d · tables, R to Z
-- GENERATED.
-- =====================================================================

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
