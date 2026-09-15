alter table person
  add column if not exists user_id text,
  add column if not exists mobile_verified_at timestamptz;

create unique index person_user_id_key on person (lower(user_id)) where left_on is null;
create unique index person_mobile_key  on person (mobile)         where left_on is null;

drop index if exists person_work_email_uniq;
comment on column person.work_email is
  'Optional. Often a shared branch inbox, so NOT unique and NOT a credential.';
comment on column person.mobile is
  'Required and unique. The identity for sign-in, OTP activation and password reset.';
comment on column person.user_id is
  'Chosen at activation, unique, what the person types to sign in.';

create table otp_challenge (
  id         uuid primary key default gen_random_uuid(),
  mobile     text not null,
  code_hash  bytea not null,
  purpose    text not null check (purpose in ('activate','reset')),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  attempts   int not null default 0
);
create index on otp_challenge (mobile, purpose);

create table holiday (
  day         date primary key,
  name        text not null,
  applies_to  text not null default 'ALL',
  source      text,
  created_at  timestamptz not null default now()
);

insert into app_setting (key, value, plain_language, group_name) values
  ('day_start',  '10:00', 'Start of the working day. Every TAT counts only minutes inside the window.', 'clocks'),
  ('day_end',    '19:00', 'End of the working day.', 'clocks'),
  ('sat',        'Yes - half day', 'Yes - half day | Yes - full day | No.', 'clocks'),
  ('sat_hours',  '4',     'Hours counted on a Saturday when it is a half day: 10:00-14:00.', 'clocks')
on conflict (key) do nothing;

create type pms_cycle_state as enum
  ('PENDING','SELF_DONE','AWAITING_REVIEW','SCORED','DISPUTED','CLOSED');

create table pms_cycle (
  id            uuid primary key default gen_random_uuid(),
  person_id     uuid not null references person(id),
  chair_id      uuid references chair(id),
  period        date not null,
  state         pms_cycle_state not null default 'PENDING',
  window_opens  timestamptz,
  window_closes timestamptz,
  self_due      timestamptz,
  self_at       timestamptz,
  review_due    timestamptz,
  scored_at     timestamptz,
  closed_at     timestamptz,
  on_probation  boolean not null default false,
  is_partner    boolean not null default false,
  constraint pms_cycle_uniq unique (person_id, period)
);
create index pms_cycle_period_idx on pms_cycle (period, state);
create index pms_cycle_review_due_idx on pms_cycle (review_due) where state = 'AWAITING_REVIEW';

create or replace function pms_window_may_open(p_person uuid, p_period date)
returns boolean as $$
  select not exists (
    select 1
    from chair_holder ch
    join chair c on c.id = ch.chair_id
    join chair_holder sub_h on true
    join chair sub on sub.id = sub_h.chair_id and sub.parent_id = c.id
    left join pms_cycle pc on pc.person_id = sub_h.person_id and pc.period = p_period
    where ch.person_id = p_person and ch.to_date is null and sub_h.to_date is null
      and coalesce(pc.state, 'PENDING') <> 'CLOSED'
  )
  or not (select coalesce(value, 'Yes') like 'Y%' from app_setting where key = 'pms_bottom_up');
$$ language sql stable;

create table pms_component (
  id          uuid primary key default gen_random_uuid(),
  cycle_id    uuid not null references pms_cycle(id) on delete cascade,
  kind        text not null check (kind in ('KPI','ATTRIBUTE','TEAM')),
  raw         numeric not null,
  weight_pct  numeric not null,
  note        text,
  constraint pms_component_uniq unique (cycle_id, kind)
);

create table pms_adjustment (
  id           uuid primary key default gen_random_uuid(),
  cycle_id     uuid not null references pms_cycle(id) on delete cascade,
  source_kind  raisable_kind not null,
  source_id    uuid,
  half         text not null check (half in ('ATTRIBUTE','KPI')),
  points       numeric not null,
  applied      boolean not null default true,
  capped       boolean not null default false,
  reason       text not null,
  at           timestamptz not null default now()
);
create index pms_adjustment_cycle_idx on pms_adjustment (cycle_id, half);

create or replace function pms_attribute_balance(p_cycle uuid) returns numeric as $$
  select greatest(0, coalesce(sum(points), 0))
  from pms_adjustment where cycle_id = p_cycle and half = 'ATTRIBUTE' and applied;
$$ language sql stable;

create table pms_dispute (
  id           uuid primary key default gen_random_uuid(),
  cycle_id     uuid not null references pms_cycle(id) on delete cascade,
  raised_by    uuid not null references person(id),
  raised_at    timestamptz not null default now(),
  reason       text not null,
  hr_due       timestamptz not null,
  decided_by   uuid references person(id),
  decided_at   timestamptz,
  outcome      text check (outcome in ('SCORE_STANDS','RESCORE','WITHDRAWN')),
  outcome_note text,
  constraint pms_dispute_outcome check (decided_at is null or outcome is not null)
);
create index pms_dispute_due_idx on pms_dispute (hr_due) where decided_at is null;

create table pms_exception (
  id           uuid primary key default gen_random_uuid(),
  cycle_id     uuid not null references pms_cycle(id) on delete cascade,
  requested_by uuid not null references person(id),
  requested_at timestamptz not null default now(),
  reason       text not null,
  hr_due       timestamptz not null,
  state        text not null default 'PENDING'
                 check (state in ('PENDING','GRANTED','REFUSED','EXPIRED')),
  decided_by   uuid references person(id),
  decided_at   timestamptz,
  reopens_until timestamptz
);
create index pms_exception_due_idx on pms_exception (hr_due) where state = 'PENDING';

create table pms_curve_band (
  id         uuid primary key default gen_random_uuid(),
  effective_fy text not null,
  rank       int not null check (rank between 1 and 5),
  label      text not null,
  share_pct  numeric not null,
  constraint pms_curve_uniq unique (effective_fy, rank)
);

insert into pms_curve_band (effective_fy, rank, label, share_pct) values
  ('2026-27', 1, 'Outstanding', 5),
  ('2026-27', 2, 'Exceeds', 15),
  ('2026-27', 3, 'Meets', 60),
  ('2026-27', 4, 'Below', 15),
  ('2026-27', 5, 'Unsatisfactory', 5)
on conflict do nothing;

create table pms_band_result (
  cycle_id  uuid primary key references pms_cycle(id) on delete cascade,
  band_id   uuid references pms_curve_band(id),
  final     numeric not null,
  floored   boolean not null default false,
  excluded  boolean not null default false,
  at        timestamptz not null default now()
);

create table automation (
  key          text primary key,
  title        text not null,
  fires_on     text not null,
  reads_setting text[],
  writes_kind  text[],
  ladder_step  int,
  escalates_to text,
  enabled      boolean not null default true,
  disabled_reason text,
  constraint automation_pause_reason check (enabled or disabled_reason is not null)
);

create table automation_run (
  id           uuid primary key default gen_random_uuid(),
  key          text not null references automation(key),
  started_at   timestamptz not null default now(),
  finished_at  timestamptz,
  outcome      text check (outcome in ('OK','NOOP','ERROR')),
  affected     int not null default 0,
  detail       text
);
create index automation_run_key_idx on automation_run (key, started_at desc);

alter table person_request
  add column if not exists chair_id      uuid references chair(id),
  add column if not exists finance_state text default 'NOT_REQUIRED'
      check (finance_state in ('NOT_REQUIRED','AWAITING','APPROVED','REFUSED')),
  add column if not exists finance_by    uuid references person(id),
  add column if not exists finance_at    timestamptz,
  add column if not exists finance_note  text,
  add column if not exists due_at        timestamptz,
  add column if not exists returned_to   uuid references person(id);
create index if not exists person_request_overdue_idx
  on person_request (due_at) where finance_state = 'AWAITING';

create or replace view chair_status as
select c.id as chair_id, c.id, c.code, c.title,
  h.person_id,
  case
    when h.person_id is not null then 'FILLED'
    when r.id is not null and r.due_at < now() then 'OVERDUE'
    when r.id is not null then 'REQUESTED'
    else 'DORMANT'
  end as state,
  r.due_at,
  (h.person_id is null) as vacant,
  case when r.id is not null and r.due_at < now()
       then greatest(0, extract(day from now() - r.due_at)::int) else 0 end as overdue_days
from chair c
left join chair_holder h on h.chair_id = c.id and h.to_date is null and h.is_primary
left join person_request r on r.chair_id = c.id and r.state in ('DRAFT','AWAITING_HR','AWAITING_ADMIN');

alter table audit_entry
  add column if not exists chair_id   uuid references chair(id),
  add column if not exists scope_path text,
  add column if not exists sentence   text;
create index if not exists audit_entry_scope_idx on audit_entry (scope_path, at desc);

create type rate_scope as enum ('exact','group','client');

create table rate (
  id             uuid primary key default gen_random_uuid(),
  code           text unique not null,
  client_id      uuid not null references client(id),
  scope          rate_scope not null,
  value          numeric(12,2) not null check (value >= 0),
  currency       char(3) not null default 'INR',
  effective_from date not null,
  effective_to   date,
  status         text not null default 'active',
  reason         text,
  created_by     uuid references person(id),
  created_at     timestamptz not null default now(),
  updated_by     uuid references person(id),
  updated_at     timestamptz not null default now(),
  check (effective_to is null or effective_to > effective_from)
);

create table rate_location (
  rate_id     uuid not null references rate(id) on delete cascade,
  geo_node_id uuid not null references geo_node(id),
  primary key (rate_id, geo_node_id)
);

create index rate_lookup on rate (client_id, scope, effective_from desc)
  where status = 'active';

create table business_record (
  id            uuid primary key default gen_random_uuid(),
  period        char(7) not null,
  business_date date not null,
  client_id     uuid not null references client(id),
  geo_node_id   uuid not null references geo_node(id),
  owner_id      uuid references person(id),
  mtd           integer not null default 0 check (mtd >= 0),
  day10         integer not null default 0 check (day10 >= 0),
  target        integer not null default 0 check (target >= 0),
  revenue       numeric(14,2) not null default 0,
  source_ref    text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (period, client_id, geo_node_id)
);

create table rate_exception (
  id           uuid primary key default gen_random_uuid(),
  record_id    uuid not null references business_record(id),
  kind         text not null,
  configured   numeric(12,2),
  implied      numeric(12,2),
  detected_at  timestamptz not null default now(),
  resolved_at  timestamptz,
  resolved_by  uuid references person(id),
  resolution   text
);

create table forecast_config (
  id        smallint primary key default 1 check (id = 1),
  scenarios jsonb not null default
    '[{"key":"cons","label":"Conservative","mult":3.25},
      {"key":"base","label":"Base","mult":3.5},
      {"key":"stretch","label":"Stretch","mult":4},
      {"key":"agg","label":"Aggressive","mult":5,"kept":true}]'::jsonb,
  updated_by uuid references person(id),
  updated_at timestamptz not null default now()
);

create table mis_saved_view (
  id         uuid primary key default gen_random_uuid(),
  person_id  uuid not null references person(id),
  name       text not null,
  config     jsonb not null,
  created_at timestamptz not null default now(),
  unique (person_id, name)
);