-- =====================================================================
-- Crux baseline · 10b · tables, M to PENALTY
-- GENERATED.
-- =====================================================================

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
