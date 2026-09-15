create type raisable_kind  as enum ('ESCALATION','WARNING','APPRECIATION','ASSISTANCE');
create type claim_stage    as enum ('DRAFT','OPS_APPROVAL','HR_APPROVAL','ACCOUNTS','DISPUTED','PAID','REJECTED');
create type idea_stage     as enum ('SUBMITTED','IN_REVIEW','ACCEPTED','INITIATED','ON_HOLD','REJECTED','DELIVERED');
create type note_class     as enum ('UNCLASSIFIED','ATTRIBUTE','FYI');

alter table kpi_definition
  add column mandatory boolean not null default true,
  add column position  int not null default 1,
  add column parent_id uuid references kpi_definition(id);

alter table kpi_target
  add column parent_target_id uuid references kpi_target(id);

create table kpi_eligibility (
  id            uuid primary key default gen_random_uuid(),
  kpi_id        uuid references kpi_definition(id),
  person_id     uuid references person(id),
  chair_id      uuid references chair(id),
  scope_all     boolean not null default false,
  gate          text not null,
  on_miss       text not null check (on_miss in ('DEDUCT','DEFAULT_SCORE')),
  deduct_points numeric,
  default_score numeric,
  set_by        uuid references person(id),
  constraint kpi_elig_effect check (
    (on_miss = 'DEDUCT' and deduct_points is not null) or
    (on_miss = 'DEFAULT_SCORE' and default_score is not null))
);

create table task (
  id           uuid primary key default gen_random_uuid(),
  person_id    uuid not null references person(id),
  assigned_by  uuid not null references person(id),
  title        text not null,
  detail       text,
  due_on       date,
  period       text not null,
  status       text not null default 'OPEN',
  outcome      text,
  attribute_weight numeric,
  closed_at    timestamptz,
  created_at   timestamptz not null default now()
);
create index task_person_period_idx on task (person_id, period);

create table daily_note (
  id            uuid primary key default gen_random_uuid(),
  person_id     uuid not null references person(id),
  note_date     date not null,
  body          text not null,
  classification note_class not null default 'UNCLASSIFIED',
  attribute_heading text,
  model_reason  text,
  classified_at timestamptz,
  included_in_review boolean not null default true
);
create index daily_note_person_idx on daily_note (person_id, note_date);

create table pms_weighting (
  id            uuid primary key default gen_random_uuid(),
  scope_all     boolean not null default false,
  chair_id      uuid references chair(id),
  person_id     uuid references person(id),
  kpi_percent   numeric not null,
  attr_percent  numeric not null,
  effective_from date not null default current_date,
  set_by        uuid references person(id),
  constraint pms_weight_sums check (kpi_percent + attr_percent = 100)
);

create table pms_impact (
  kind        raisable_kind primary key,
  points      numeric not null,
  applies_to  text not null default 'PERSON_CONCERNED',
  set_by      uuid references person(id),
  updated_at  timestamptz not null default now()
);

create table pms_score (
  id            uuid primary key default gen_random_uuid(),
  person_id     uuid not null references person(id),
  period        text not null,
  kpi_score     numeric,
  attr_score    numeric,
  final_score   numeric,
  manager_score numeric check (manager_score between 1 and 10),
  manager_note  text,
  review_summary text,
  scored_by     uuid references person(id),
  scored_at     timestamptz,
  hr_closed_by  uuid references person(id),
  hr_closed_at  timestamptz,
  constraint pms_score_uniq unique (person_id, period)
);

create table raisable (
  id            uuid primary key default gen_random_uuid(),
  kind          raisable_kind not null,
  ref           text not null unique,
  raised_by     uuid not null references person(id),
  about_person  uuid references person(id),
  department    text,
  case_id       uuid references "case"(id),
  body          text,
  auto_source   text,
  pms_points    numeric,
  created_at    timestamptz not null default now()
);

create table request_task (
  id            uuid primary key default gen_random_uuid(),
  raisable_id   uuid not null references raisable(id),
  responder_id  uuid not null references person(id),
  due_at        timestamptz not null,
  actioned_at   timestamptz,
  strike_count  int not null default 0,
  escalated_case_id uuid references "case"(id)
);
create index request_task_due_idx on request_task (due_at) where actioned_at is null;

create table visit_form_field (
  id          uuid primary key default gen_random_uuid(),
  department  text not null,
  position    int not null,
  label       text not null,
  field_type  text not null default 'text',
  required    boolean not null default true
);

create table visit (
  id          uuid primary key default gen_random_uuid(),
  person_id   uuid not null references person(id),
  visited_on  date not null,
  branch_id   uuid references branch(id),
  client_id   uuid references client(id),
  purpose     text,
  answers     jsonb not null default '{}',
  created_at  timestamptz not null default now()
);

create table claim (
  id            uuid primary key default gen_random_uuid(),
  ref           text not null unique,
  visit_id      uuid references visit(id),
  person_id     uuid not null references person(id),
  amount        numeric not null,
  stage         claim_stage not null default 'DRAFT',
  ops_by        uuid references person(id),
  ops_at        timestamptz,
  hr_by         uuid references person(id),
  hr_at         timestamptz,
  accounts_by   uuid references person(id),
  accounts_at   timestamptz,
  paid_ref      text,
  dispute_reason text,
  created_at    timestamptz not null default now(),
  constraint claim_dispute_reason check (stage <> 'DISPUTED' or dispute_reason is not null),
  constraint claim_paid_ref check (stage <> 'PAID' or paid_ref is not null)
);
create index claim_stage_idx on claim (stage);

create table idea (
  id           uuid primary key default gen_random_uuid(),
  ref          text not null unique,
  title        text not null,
  body         text not null,
  raised_by    uuid not null references person(id),
  stage        idea_stage not null default 'SUBMITTED',
  sponsor_id   uuid references person(id),
  owner_dept   text,
  charter      text,
  decided_by   uuid references person(id),
  decided_at   timestamptz,
  decision_reason text,
  created_at   timestamptz not null default now(),
  constraint idea_decision_reason check (stage not in ('REJECTED','ON_HOLD') or decision_reason is not null)
);

create table idea_collaborator (
  idea_id   uuid not null references idea(id) on delete cascade,
  person_id uuid not null references person(id),
  role      text not null default 'COLLABORATOR',
  primary key (idea_id, person_id)
);

create table onboarding (
  id           uuid primary key default gen_random_uuid(),
  person_request_id uuid references person_request(id),
  person_id    uuid references person(id),
  induction_on date,
  buddy_id     uuid references person(id),
  documents_ok boolean not null default false,
  completed_at timestamptz
);

create table pulse_response (
  id         uuid primary key default gen_random_uuid(),
  person_id  uuid references person(id),
  period     text not null,
  score      numeric check (score between 1 and 10),
  comment    text,
  at         timestamptz not null default now()
);

create table app_setting (
  key          text primary key,
  value        text,
  plain_language text not null,
  group_name   text not null,
  secret       boolean not null default false,
  editable_by  text not null default 'ADMIN',
  updated_by   uuid references person(id),
  updated_at   timestamptz not null default now()
);

create table assist_guide (
  key        text primary key,
  route      text not null,
  title      text not null,
  steps      text[] not null,
  why        text not null
);

create table ai_key (
  id              uuid primary key default gen_random_uuid(),
  provider        text not null,
  model           text not null,
  key_encrypted   bytea,
  endpoint        text,
  chain_order     int  not null unique,
  scope           text not null default 'everything'
                  check (scope in ('everything','short','long','fallback')),
  monthly_budget  int  not null default 0,
  used_this_month int  not null default 0,
  state           text not null default 'untested'
                  check (state in ('healthy','untested','erroring','no_key')),
  last_tested_at  timestamptz,
  last_latency_ms int,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table ai_call (
  id          uuid primary key default gen_random_uuid(),
  ai_key_id   uuid not null references ai_key(id),
  touchpoint  text not null,
  at          timestamptz not null default now(),
  latency_ms  int,
  ok          boolean not null,
  error       text,
  actor_id    uuid references person(id)
);
create index on ai_call (at desc);

create table mail_config (
  id                    smallint primary key default 1 check (id = 1),
  mailbox               text not null,
  auth_mode             text not null check (auth_mode in ('service_account','oauth','smtp')),
  service_account_email text,
  delegation_client_id  text,
  reply_to              text,
  daily_budget          int  not null default 1800,
  used_today            int  not null default 0,
  signature_json        jsonb,
  signature_logo_file   uuid,
  test_mode             boolean not null default false,
  test_address          text,
  test_mode_expires_at  timestamptz,
  bounce_strikes        int not null default 3,
  last_tested_at        timestamptz,
  updated_at            timestamptz not null default now(),
  check (test_mode = false or test_address is not null)
);

create table mail_alias (
  id       uuid primary key default gen_random_uuid(),
  address  text not null unique,
  verified boolean not null default false
);

create table mail_bounce (
  id        uuid primary key default gen_random_uuid(),
  address   text not null,
  at        timestamptz not null default now(),
  hard      boolean not null,
  strikes   int  not null default 1,
  unreachable boolean not null default false
);
create index on mail_bounce (address);