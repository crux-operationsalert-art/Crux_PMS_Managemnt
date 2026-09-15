create extension if not exists "pgcrypto";

create type role_kind        as enum ('ADMIN','MANAGER','LOCATION_HEAD','VIEWER');
create type entity_status    as enum ('ACTIVE','INACTIVE');
create type geo_level        as enum ('ZONE','STATE','CITY');
create type scope_kind       as enum ('CLIENT','CLIENT_ZONE','STATE','BRANCH');
create type case_status      as enum ('OPEN','IN_PROGRESS','RESOLVED','CLOSED','BLOCKED');
create type outbox_state     as enum ('QUEUED','SENT','DEFERRED','ABANDONED');
create type job_result       as enum ('OK','NOOP','FAILED');
create type person_event_kind as enum ('NOTE','APPRECIATION','WARNING','PIP','ACTIVATION');

create table designation (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  desk_id       uuid,
  is_desk_head  boolean not null default false,
  seniority     int    not null default 0,
  constraint designation_title_uniq unique (title)
);

create table person (
  id                 uuid primary key default gen_random_uuid(),
  employee_no        text,
  full_name          text not null,
  work_email         text,
  personal_email     text,
  mobile             text,
  designation_id     uuid references designation(id),
  department         text,
  manager_id         uuid references person(id),
  app_role           role_kind not null default 'VIEWER',
  employment_status  entity_status not null default 'ACTIVE',
  joined_on          date,
  left_on            date,
  superseded_by      uuid references person(id),
  source_ref         text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create unique index person_work_email_uniq
  on person (lower(work_email))
  where employment_status = 'ACTIVE' and superseded_by is null and work_email is not null;
create unique index person_employee_no_uniq
  on person (employee_no) where employee_no is not null;

create table desk (
  id                uuid primary key default gen_random_uuid(),
  name              text not null unique,
  primary_person_id uuid references person(id),
  escalation_only   boolean not null default false,
  fallback_desk_id  uuid references desk(id),
  constraint desk_primary_or_fallback check (primary_person_id is not null or fallback_desk_id is not null)
);
alter table designation add constraint designation_desk_fk foreign key (desk_id) references desk(id);

create table geo_node (
  id        uuid primary key default gen_random_uuid(),
  parent_id uuid references geo_node(id),
  level     geo_level not null,
  name      text not null
);
create unique index geo_node_sibling_uniq on geo_node (coalesce(parent_id,'00000000-0000-0000-0000-000000000000'::uuid), lower(name));

create table client (
  id             uuid primary key default gen_random_uuid(),
  code           text not null,
  name           text not null,
  status         entity_status not null default 'ACTIVE',
  effective_from date,
  effective_to   date,
  notes          text,
  source_ref     text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint client_code_uniq unique (code)
);

create table client_contact (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid not null references client(id) on delete cascade,
  kind       text not null,
  name       text,
  email      text not null,
  mobile     text
);
create unique index client_contact_uniq on client_contact (client_id, kind, lower(email));

create table client_zone (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references client(id) on delete cascade,
  name        text not null,
  geo_node_id uuid references geo_node(id)
);
create unique index client_zone_uniq on client_zone (client_id, lower(name));

create table branch (
  id             uuid primary key default gen_random_uuid(),
  client_id      uuid not null references client(id),
  code           text not null,
  name           text not null,
  address        text,
  geo_node_id    uuid references geo_node(id),
  client_zone_id uuid references client_zone(id),
  status         entity_status not null default 'ACTIVE',
  effective_from date,
  effective_to   date,
  notes          text,
  source_ref     text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint branch_code_uniq unique (client_id, code)
);
create index branch_client_status_idx on branch (client_id, status);

create table branch_contact (
  id        uuid primary key default gen_random_uuid(),
  branch_id uuid not null references branch(id) on delete cascade,
  role      text not null,
  person_id uuid references person(id),
  name      text,
  mobile    text,
  email     text,
  active    boolean not null default true,
  constraint branch_contact_identified check (person_id is not null or name is not null)
);
create unique index branch_contact_one_active on branch_contact (branch_id, role) where active;

create table matrix_contact (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid not null references client(id),
  branch_id  uuid references branch(id) on delete cascade,
  level      int  not null check (level between 1 and 5),
  level_name text not null,
  person_id  uuid references person(id),
  name       text,
  mobile     text,
  email      text,
  updated_by uuid references person(id),
  updated_at timestamptz not null default now(),
  source_ref text
);
create unique index matrix_branch_level_uniq on matrix_contact (branch_id, level) where branch_id is not null;
create unique index matrix_client_level_uniq on matrix_contact (client_id, level) where branch_id is null;

create view branch_matrix_state as
select b.id as branch_id,
       b.client_id,
       count(*) filter (
         where m.name is not null and btrim(m.name) <> ''
           and (coalesce(btrim(m.mobile),'') <> '' or coalesce(btrim(m.email),'') <> '')
       ) as complete_levels
from branch b
left join matrix_contact m on m.branch_id = b.id
group by b.id, b.client_id;

create view dispatch_eligible_branch as
select b.id as branch_id, b.client_id
from branch b
join branch_matrix_state s on s.branch_id = b.id
join client c on c.id = b.client_id
where b.status = 'ACTIVE' and c.status = 'ACTIVE' and s.complete_levels = 5;

create table coverage_rule (
  id             uuid primary key default gen_random_uuid(),
  person_id      uuid not null references person(id),
  role           text not null,
  scope_type     scope_kind not null,
  client_id      uuid references client(id),
  client_zone_id uuid references client_zone(id),
  geo_node_id    uuid references geo_node(id),
  branch_id      uuid references branch(id),
  effective_from date not null default current_date,
  effective_to   date,
  source_ref     text,
  created_at     timestamptz not null default now(),
  constraint coverage_scope_shape check (
    (scope_type = 'CLIENT'      and client_id is not null and client_zone_id is null and geo_node_id is null and branch_id is null) or
    (scope_type = 'CLIENT_ZONE' and client_zone_id is not null and branch_id is null) or
    (scope_type = 'STATE'       and client_id is not null and geo_node_id is not null and branch_id is null) or
    (scope_type = 'BRANCH'      and branch_id is not null)
  )
);

create or replace function coverage_resolve(p_rule coverage_rule) returns setof uuid as $$
  select b.id from branch b
  left join client_zone cz on cz.id = b.client_zone_id
  where case p_rule.scope_type
    when 'CLIENT'      then b.client_id = p_rule.client_id
    when 'CLIENT_ZONE' then b.client_zone_id = p_rule.client_zone_id
    when 'STATE'       then b.client_id = p_rule.client_id and b.geo_node_id in (
                              with recursive t as (
                                select id from geo_node where id = p_rule.geo_node_id
                                union all select g.id from geo_node g join t on g.parent_id = t.id
                              ) select id from t)
    when 'BRANCH'      then b.id = p_rule.branch_id
  end;
$$ language sql stable;

create or replace function coverage_no_overlap() returns trigger as $$
declare clash record;
begin
  select r.id, r.scope_type, count(*) as n into clash
  from coverage_rule r
  cross join lateral (select 1 from coverage_resolve(r) x where x in (select coverage_resolve(new))) hit
  where r.person_id = new.person_id and r.role = new.role and r.id <> new.id
    and (r.effective_to is null or r.effective_to >= current_date)
  group by r.id, r.scope_type
  limit 1;
  if clash.id is not null then
    raise exception 'coverage overlap: % branches already covered by rule % (%)', clash.n, clash.id, clash.scope_type
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$ language plpgsql;

create trigger coverage_rule_no_overlap
  before insert or update on coverage_rule
  for each row execute function coverage_no_overlap();

create table category (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  desk_id     uuid not null references desk(id),
  pinned      boolean not null default false,
  chase_hours int,
  active      boolean not null default true
);

create table "case" (
  id                uuid primary key default gen_random_uuid(),
  ref               text not null unique,
  client_id         uuid not null references client(id),
  branch_id         uuid references branch(id),
  category_id       uuid not null references category(id),
  raised_by         uuid not null references person(id),
  against_person_id uuid references person(id),
  against_text      text,
  description       text,
  owner_person_id   uuid references person(id),
  desk_id           uuid references desk(id),
  status            case_status not null default 'OPEN',
  resolution_note   text,
  resolved_at       timestamptz,
  auto_close_at     timestamptz,
  next_chase_at     timestamptz,
  strike_count      int not null default 0,
  last_activity_at  timestamptz not null default now(),
  closed_at         timestamptz,
  source_ref        text,
  created_at        timestamptz not null default now(),
  constraint case_has_owner check (owner_person_id is not null or desk_id is not null or status = 'BLOCKED')
);
create index case_open_chase_idx on "case" (next_chase_at) where status in ('OPEN','IN_PROGRESS');
create index case_autoclose_idx  on "case" (auto_close_at) where status = 'RESOLVED';

create table case_event (
  id         uuid primary key default gen_random_uuid(),
  case_id    uuid not null references "case"(id) on delete cascade,
  at         timestamptz not null default now(),
  actor_id   uuid references person(id),
  kind       text,
  field      text,
  old_value  text,
  new_value  text,
  note       text
);
create index case_event_case_idx on case_event (case_id, at);

create table template (
  id         uuid primary key default gen_random_uuid(),
  key        text not null,
  version    int  not null default 1,
  subject    text not null,
  body       text not null,
  updated_by uuid references person(id),
  updated_at timestamptz not null default now(),
  constraint template_key_version_uniq unique (key, version)
);

create table outbox (
  id              uuid primary key default gen_random_uuid(),
  idempotency_key text not null,
  template_key    text not null,
  entity_type     text,
  entity_id       uuid,
  recipient       text not null,
  cc_addr         text,
  subject         text not null,
  body            text not null,
  state           outbox_state not null default 'QUEUED',
  attempts        int not null default 0,
  not_before      timestamptz not null default now(),
  sent_at         timestamptz,
  last_error      text,
  created_at      timestamptz not null default now(),
  constraint outbox_idempotency_uniq unique (idempotency_key)
);
create index outbox_due_idx on outbox (not_before) where state = 'QUEUED';

create table delivery (
  id           uuid primary key default gen_random_uuid(),
  outbox_id    uuid references outbox(id),
  channel      text not null default 'EMAIL',
  recipient    text not null,
  state        text not null,
  error        text,
  at           timestamptz not null default now(),
  provider_ref text,
  entity_type  text,
  entity_id    uuid
);
create index delivery_entity_idx on delivery (entity_type, entity_id, at);

create table mail_budget (
  day            date primary key,
  recipients_sent int not null default 0,
  cap            int not null default 1800,
  reserve        int not null default 200
);

create table job_run (
  id          uuid primary key default gen_random_uuid(),
  job_key     text not null,
  started_at  timestamptz not null default now(),
  finished_at timestamptz,
  state       text,
  note        text,
  result      job_result,
  counts      jsonb,
  error       text,
  next_due_at timestamptz
);
create index job_run_key_idx on job_run (job_key, started_at desc);

create table job_config (
  job_key      text primary key,
  enabled      boolean not null default true,
  cron         text not null,
  disabled_by  uuid references person(id),
  disabled_at  timestamptz,
  reason       text,
  constraint job_disable_needs_reason check (enabled or (reason is not null and disabled_by is not null))
);

create table submission_window (
  id         uuid primary key default gen_random_uuid(),
  kind       text not null,
  person_id  uuid not null references person(id),
  period     text not null,
  state      text not null,
  opened_by  uuid references person(id),
  opened_at  timestamptz,
  closes_at  timestamptz,
  reason     text,
  constraint submission_window_uniq unique (kind, person_id, period)
);

create table person_event (
  id         uuid primary key default gen_random_uuid(),
  person_id  uuid not null references person(id),
  kind       text not null,
  at         timestamptz not null default now(),
  start_on   date,
  end_on     date,
  note       text,
  issued_by  uuid references person(id),
  status     text,
  outcome    text,
  case_id    uuid references "case"(id),
  source_ref text
);
create index person_event_person_idx on person_event (person_id, at desc);

create table target (
  id         uuid primary key default gen_random_uuid(),
  person_id  uuid not null references person(id),
  period     text not null,
  category   text,
  sub_category text,
  client_id  uuid references client(id),
  target_value numeric,
  achieved_value numeric,
  notes      text,
  updated_by uuid references person(id),
  updated_at timestamptz not null default now(),
  constraint target_uniq unique (person_id, period, category, sub_category)
);

create table audit_entry (
  id          uuid primary key default gen_random_uuid(),
  at          timestamptz not null default now(),
  actor_id    uuid references person(id),
  action      text not null,
  entity_type text not null,
  entity_id   uuid,
  entity_ref  text,
  old_value   jsonb,
  new_value   jsonb
);
create index audit_entity_idx on audit_entry (entity_type, entity_id, at desc);
create index audit_actor_idx  on audit_entry (actor_id, at desc);

create table migration_merge (
  id           uuid primary key default gen_random_uuid(),
  at           timestamptz not null default now(),
  entity_type  text not null,
  kept_id      uuid not null,
  merged_id    uuid,
  merged_key   text,
  rows_moved   int,
  rule         text not null,
  reviewed_by  uuid references person(id),
  reviewed_at  timestamptz
);

create table auth_session (
  id           uuid primary key default gen_random_uuid(),
  person_id    uuid not null references person(id),
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz,
  expires_at   timestamptz not null,
  source       text,
  revoked_at   timestamptz,
  revoked_by   uuid references person(id)
);
create index auth_session_person_idx on auth_session (person_id) where revoked_at is null;

create table portal_link (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid references client(id),
  branch_id  uuid references branch(id),
  token_hash text not null unique,
  created_at timestamptz not null default now(),
  rotated_at timestamptz,
  revoked_at timestamptz,
  constraint portal_link_target check (client_id is not null or branch_id is not null)
);