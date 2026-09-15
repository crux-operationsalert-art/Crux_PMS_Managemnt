create type penalty_state as enum ('PENDING','APPLIED','WAIVED','DISPUTED','REVERSED');
create type approval_state as enum ('DRAFT','AWAITING_HR','AWAITING_ADMIN','ACTIVE','REJECTED');
create type esc_party as enum ('RAISER','RESPONDENT','MANAGER','DESK','HR','ADMIN','INFORMED');

create table chair (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,
  title         text not null,
  desk_id       uuid references desk(id),
  parent_id     uuid references chair(id),
  level         text not null,
  reports_daily boolean not null default false
);

create table chair_holder (
  id         uuid primary key default gen_random_uuid(),
  chair_id   uuid not null references chair(id),
  person_id  uuid not null references person(id),
  is_primary boolean not null default false,
  from_date  date not null default current_date,
  to_date    date
);
create unique index chair_one_primary on chair_holder (chair_id) where is_primary and to_date is null;

create table process (
  id        uuid primary key default gen_random_uuid(),
  ref       text not null unique,
  function  text not null,
  name      text not null,
  owner_chair_id uuid not null references chair(id)
);

create table process_party (
  process_id uuid not null references process(id) on delete cascade,
  chair_id   uuid not null references chair(id),
  part       text not null,
  primary key (process_id, chair_id, part)
);

create table process_input (
  id         uuid primary key default gen_random_uuid(),
  process_id uuid not null references process(id) on delete cascade,
  what       text not null,
  from_chair_id uuid not null references chair(id)
);

create table kpi_definition (
  id         uuid primary key default gen_random_uuid(),
  chair_id   uuid references chair(id),
  person_id  uuid references person(id),
  name       text not null,
  unit       text,
  active     boolean not null default true,
  constraint kpi_scope check (chair_id is not null or person_id is not null)
);

create table kpi_target (
  id            uuid primary key default gen_random_uuid(),
  kpi_id        uuid not null references kpi_definition(id),
  person_id     uuid not null references person(id),
  period        text not null,
  target_value  numeric not null,
  set_by        uuid not null references person(id),
  set_at        timestamptz not null default now(),
  constraint kpi_target_uniq unique (kpi_id, person_id, period),
  constraint kpi_target_not_self check (set_by <> person_id)
);

create table daily_count (
  id           uuid primary key default gen_random_uuid(),
  person_id    uuid not null references person(id),
  count_date   date not null,
  kpi_id       uuid not null references kpi_definition(id),
  value        numeric not null,
  submitted_at timestamptz not null default now(),
  locked_at    timestamptz,
  reopened_by  uuid references person(id),
  reopen_reason text,
  constraint daily_count_uniq unique (person_id, count_date, kpi_id),
  constraint daily_reopen_needs_reason check (reopened_by is null or reopen_reason is not null)
);
create index daily_count_date_idx on daily_count (count_date, person_id);

create table penalty_rule (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,
  what          text not null,
  plain_language text not null,
  applies_to    text not null,
  frequency     text not null,
  cutoff_spec   text not null,
  amount        numeric not null,
  recovered_by  text not null,
  active        boolean not null default true,
  effective_from date not null default current_date,
  created_by    uuid references person(id)
);

create table penalty_instance (
  id            uuid primary key default gen_random_uuid(),
  rule_id       uuid not null references penalty_rule(id),
  person_id     uuid not null references person(id),
  period        text not null,
  occurred_on   date not null,
  cutoff_missed text not null,
  evidence      text not null,
  entity_type   text,
  entity_id     uuid,
  amount        numeric not null,
  state         penalty_state not null default 'APPLIED',
  waived_by     uuid references person(id),
  waive_reason  text,
  recovered_by  text not null,
  recovered_at  timestamptz,
  created_at    timestamptz not null default now(),
  constraint penalty_no_duplicate unique (rule_id, person_id, occurred_on, entity_id),
  constraint penalty_waiver_needs_reason check (state <> 'WAIVED' or (waived_by is not null and waive_reason is not null)),
  constraint penalty_amount_frozen check (amount >= 0)
);
create index penalty_person_period_idx on penalty_instance (person_id, period);
create index penalty_recovery_idx on penalty_instance (recovered_by, state, period);

create table escalation_party (
  case_id   uuid not null references "case"(id) on delete cascade,
  person_id uuid not null references person(id),
  part      esc_party not null,
  primary key (case_id, person_id, part)
);

create table escalation_action (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,
  label         text not null,
  pms_impact    boolean not null,
  unlock_after_working_days int,
  sets_tat_hours int,
  routes_to     text
);

create table escalation_action_log (
  id          uuid primary key default gen_random_uuid(),
  case_id     uuid not null references "case"(id),
  action_code text not null references escalation_action(code),
  actor_id    uuid not null references person(id),
  at          timestamptz not null default now(),
  note        text
);

create table letter (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null,
  person_id   uuid not null references person(id),
  case_id     uuid references "case"(id),
  issued_by   uuid not null references person(id),
  issued_at   timestamptz not null default now(),
  body        text not null,
  acknowledged_at timestamptz,
  due_ack_at  timestamptz not null,
  copied_to   text[]
);

create table person_request (
  id            uuid primary key default gen_random_uuid(),
  full_name     text not null,
  work_email    text not null,
  chair_id      uuid not null references chair(id),
  manager_id    uuid not null references person(id),
  requested_by  uuid not null references person(id),
  requested_at  timestamptz not null default now(),
  state         approval_state not null default 'AWAITING_HR',
  hr_by         uuid references person(id),
  hr_at         timestamptz,
  admin_by      uuid references person(id),
  admin_at      timestamptz,
  reject_reason text,
  person_id     uuid references person(id),
  constraint person_request_reject_reason check (state <> 'REJECTED' or reject_reason is not null)
);

create view branch_effective_matrix as
select b.id as branch_id, m.level, m.level_name, m.name, m.mobile, m.email, false as inherited
from branch b join matrix_contact m on m.branch_id = b.id
union all
select b.id, m.level, m.level_name, m.name, m.mobile, m.email, true as inherited
from branch b
join matrix_contact m on m.client_id = b.client_id and m.branch_id is null
where not exists (select 1 from matrix_contact x where x.branch_id = b.id);

create or replace view dispatch_eligible_branch_v2 as
select b.id as branch_id, b.client_id,
       bool_or(e.inherited) as using_client_default
from branch b
join client c on c.id = b.client_id
join branch_effective_matrix e on e.branch_id = b.id
where b.status = 'ACTIVE' and c.status = 'ACTIVE'
group by b.id, b.client_id
having count(*) filter (
         where e.name is not null and btrim(e.name) <> ''
           and (coalesce(btrim(e.mobile),'') <> '' or coalesce(btrim(e.email),'') <> '')
       ) = 5;

create table client_view_policy (
  department text primary key,
  view_kind  text not null check (view_kind in ('matrix','contacts','none'))
);
insert into client_view_policy (department, view_kind) values
  ('Operations','matrix'), ('Technology','matrix'),
  ('Finance & Accounts','contacts'), ('Business Development','contacts'),
  ('Compliance & Assurance','contacts'),
  ('Human Resources','none'), ('MIS','none');

create table push_subscription (
  id         uuid primary key default gen_random_uuid(),
  person_id  uuid not null references person(id),
  endpoint   text not null unique,
  keys       jsonb not null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

create table notification (
  id         uuid primary key default gen_random_uuid(),
  person_id  uuid not null references person(id),
  kind       text not null,
  text       text not null,
  entity_type text,
  entity_id  uuid,
  push       boolean not null default false,
  at         timestamptz not null default now(),
  read_at    timestamptz
);
create index notification_person_idx on notification (person_id, at desc);

create table migration_review (
  id          uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_ref  text not null,
  question    text not null,
  context     text,
  resolved_to text,
  resolved_by uuid references person(id),
  resolved_at timestamptz
);

create or replace function may_edit_penalty_rule(p_person uuid) returns boolean as $$
  select coalesce(
    (select department in ('Human Resources','Finance & Accounts') or app_role = 'ADMIN'
     from person where id = p_person), false);
$$ language sql stable;

alter table penalty_rule
  add column applies_to_list text[] not null default '{Everybody}';
comment on column penalty_rule.applies_to_list is
  'Multi-select: Everybody | a department | a named chair | Managers with reportees | Executives | Team Leaders | Branch Managers | Regional Managers | Franchise Partners | Interns';

alter table person
  add column if not exists employee_type text not null default 'EMPLOYEE'
    check (employee_type in ('EMPLOYEE','PARTNER'));
comment on column person.employee_type is
  'PARTNER = franchise partner: in scope for PMS/penalties but billed by Finance, not payroll.';

create or replace function penalty_recovery_for(p_person uuid, p_rule uuid) returns text as $$
  select case when (select employee_type from person where id = p_person) = 'PARTNER'
              then 'FINANCE'
              else (select recovered_by from penalty_rule where id = p_rule) end;
$$ language sql stable;