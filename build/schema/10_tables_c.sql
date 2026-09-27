-- =====================================================================
-- Crux baseline · 10c · tables, PERF to PUSH
-- GENERATED.
-- =====================================================================

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
  monthly_score numeric(5,3) default ((0.75 * kpi_points) + (0.25 * attr_points)),
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
