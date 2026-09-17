-- =====================================================================
-- 100 · THE OPERATING STRUCTURE
--
-- A chair is a seat. The place it is held is a property of the seating,
-- not of the seat: one Branch Manager chair, many holders, each covering
-- one or more locations, and two holders may share a location when they
-- carry different clients or products. coverage_rule already carries
-- client, zone, geography, branch and product per person, so the scope
-- needs nothing new — the chair simply stops encoding the location.
--
-- The owner's document draws 70 chairs because it draws one per region.
-- Those 70 are kept whole in chair_seating so the collapse to 34 seats is
-- auditable and reversible. See docs/ORG_STRUCTURE.md.
-- =====================================================================

create table if not exists capability_track (
  id             uuid primary key default gen_random_uuid(),
  name           text not null unique,
  knowledge_test text,
  unlock         text
);

-- The L1-L5 ladder belongs to the track, not the chair: verified identical
-- across every chair sharing a track before it was normalised this way,
-- which is why this is 105 rows and not 350.
create table if not exists capability_level (
  track_id      uuid not null references capability_track(id) on delete cascade,
  level         text not null check (level in ('L1','L2','L3','L4','L5')),
  level_name    text not null,
  requirement   text,
  qualification text,
  experience    text,
  certification text,
  test_score    text,
  evidence      text,
  primary key (track_id, level)
);

create table if not exists capability_topic (
  track_id uuid not null references capability_track(id) on delete cascade,
  ord      int  not null,
  topic    text not null,
  primary key (track_id, ord)
);

create table if not exists capability_psychometric (
  track_id   uuid not null references capability_track(id) on delete cascade,
  ord        int  not null,
  instrument text not null,
  standard   text,
  primary key (track_id, ord)
);

alter table chair add column if not exists sg_level            text;
alter table chair add column if not exists function_name       text;
alter table chair add column if not exists band                text;
alter table chair add column if not exists purpose             text;
alter table chair add column if not exists capability_track_id uuid references capability_track(id);
alter table chair add column if not exists source_ref          text;

-- One row per chair the document drew: this seat, held for this place,
-- reporting to that seating. A seating reports to a seating, not to a
-- seat — the North back office answers to the North team leader, not to
-- every team leader everywhere.
create table if not exists chair_seating (
  id                    uuid primary key default gen_random_uuid(),
  chair_id              uuid not null references chair(id) on delete cascade,
  scope_label           text,
  reports_to_chair_id   uuid references chair(id),
  reports_to_seating_id uuid references chair_seating(id),
  holder_text           text,
  note                  text,
  source_ref            text unique
);
create index if not exists chair_seating_chair_idx on chair_seating(chair_id);

-- A process drawn once per region keeps its regional refs here, so L6, L7
-- and L9NO all still resolve to the one "Branch P&L".
create table if not exists process_scope (
  id          uuid primary key default gen_random_uuid(),
  process_id  uuid not null references process(id) on delete cascade,
  ref         text not null unique,
  scope_label text
);

create table if not exists chair_accountability (
  id uuid primary key default gen_random_uuid(),
  chair_id uuid not null references chair(id) on delete cascade,
  ord int not null, statement text not null
);
create table if not exists chair_measure (
  id uuid primary key default gen_random_uuid(),
  chair_id uuid not null references chair(id) on delete cascade,
  ord int not null, statement text not null
);
create table if not exists chair_authority (
  id uuid primary key default gen_random_uuid(),
  chair_id uuid not null references chair(id) on delete cascade,
  kind text not null check (kind in ('DECIDE','ESCALATE')),
  ord int not null, statement text not null
);
create table if not exists chair_task (
  id uuid primary key default gen_random_uuid(),
  chair_id uuid not null references chair(id) on delete cascade,
  ord int not null, task text not null
);
create table if not exists chair_subtask (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references chair_task(id) on delete cascade,
  ord int not null, statement text not null
);

alter table capability_track        enable row level security;
alter table capability_level        enable row level security;
alter table capability_topic        enable row level security;
alter table capability_psychometric enable row level security;
alter table chair_seating           enable row level security;
alter table process_scope           enable row level security;
alter table chair_accountability    enable row level security;
alter table chair_measure           enable row level security;
alter table chair_authority         enable row level security;
alter table chair_task              enable row level security;
alter table chair_subtask           enable row level security;
