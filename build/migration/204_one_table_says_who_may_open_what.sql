-- 204 · One table says who may open what
--
-- The published tool carries this, immediately above the table it is talking
-- about:
--
--   "It decides what appears in the navigation and what currentTab() will
--    open. It is NOT the permission check. Every service decides for itself
--    and refuses in its own words; hiding a screen stops somebody wandering
--    into it and does nothing about somebody typing the URL."
--
-- The first sentence is true. The second is not, for the ops service. Four of
-- its six route files check only that the caller holds a chair — any chair —
-- and a field executive's token reaches all of this:
--
--   GET /api/rates              every client's commercial rate, all 433 versions
--   GET /api/access             1,000 active people, their department and coverage
--   GET /api/access/person/:id  anybody's coverage and explicit grants
--   GET /api/access/joining     every in-flight hire and unactivated account
--   GET /api/auto               job configuration, cron lines, last errors
--   GET /api/mis                every row of business_record
--   GET /api/mis/tenday         every location's ten-day position
--   GET /api/mis/reports        company-wide counts, labelled "Your coverage"
--
-- The obvious fix is to write the eight-level table into the service. That
-- would give two copies of one policy, and two copies drift: the copy nobody
-- edits becomes the one that is wrong, and nothing says which is which.
--
-- So the table moves into the database, and both sides read it. The service
-- asks access_may_open(); auth_whoami hands the same answer to the browser,
-- and the navigation prefers it over its own copy. A change to the policy is
-- then a row, and it moves the navigation and the services together.
--
-- What is seeded here is exactly what the published tool does today, level for
-- level and screen for screen. Enforcing a policy is not the moment to change
-- it. Two things that look wrong are recorded at the bottom of this file
-- rather than quietly fixed.

-- --------------------------------------------------------------- the levels
create table if not exists public.access_level (
  level text primary key,
  label text not null,
  note  text
);

comment on table public.access_level is
  'The eight scope levels the design gives every chair, plus admin. Read by the '
  'ops service and by the navigation, through access_screens().';

insert into public.access_level (level, label, note) values
  ('exec',      'Executive',            'Their own work: the day, the case in front of them, their own performance.'),
  ('team',      'Team leader',          'Their own work and the team under them.'),
  ('branch',    'Branch and above',     'A place and what it owes. Branch, zonal, regional and the heads carry the same list; what differs is how far they see, which is the service''s question and not this one.'),
  ('partner',   'Location partner',     'A branch view, plus the penalty ledger they are charged against.'),
  ('hr',        'Human resources',      'People, joining, and the company''s messaging.'),
  ('finance',   'Finance',              'Money, penalties and the automations that raise them.'),
  ('analytics', 'MIS and analytics',    'Reporting and the data behind it. No client contact list.'),
  ('staff',     'Staff function',       'Excellence, risk, legal, company secretary: read across the company, own nothing operational.'),
  ('admin',     'Administrator',        'Nothing is hidden from it and it can change everything. Not derived from a seat.')
on conflict (level) do update set label = excluded.label, note = excluded.note;

-- ------------------------------------------------- what each level may open
create table if not exists public.access_level_screen (
  level  text not null references public.access_level(level) on delete cascade,
  screen text not null,
  primary key (level, screen)
);

comment on table public.access_level_screen is
  'One row per screen a level may open. admin holds no rows and needs none: '
  'access_may_open() answers true for it before it reads this table.';

-- Seeded from the published tool's SCREENS, unchanged.
insert into public.access_level_screen (level, screen)
select l, s from (values
  ('exec',      array['today','ogl','cases','perf','visits','ideas','profile']),
  ('team',      array['today','ogl','cases','perf','people','visits','ideas','profile']),
  ('branch',    array['today','ogl','cases','perf','clients','people','hiring','joining',
                      'visits','ideas','reports','history','profile']),
  ('partner',   array['today','ogl','cases','perf','clients','people','hiring','joining',
                      'visits','ideas','penalties','reports','history','profile']),
  ('hr',        array['today','cases','perf','people','hr','hiring','joining','visits',
                      'ideas','penalties','reports','history','mail','auto','config','profile']),
  ('finance',   array['today','cases','perf','clients','people','hiring','visits','ideas',
                      'penalties','reports','history','auto','config','profile']),
  ('analytics', array['today','cases','perf','people','ideas','data','coverage','reports',
                      'history','profile']),
  ('staff',     array['today','cases','perf','people','clients','visits','ideas','reports',
                      'history','profile'])
) as v(l, screens), lateral unnest(v.screens) as s
on conflict do nothing;

-- ------------------------------------- a screen reached from inside another
create table if not exists public.access_screen_parent (
  screen text primary key,
  parent text not null
);

comment on table public.access_screen_parent is
  'A screen the design reaches from inside a parent rather than from the top '
  'row follows its parent. The rate master is under Reports, which is why '
  'every level that carries Reports can read it.';

insert into public.access_screen_parent (screen, parent) values
  ('matrix','clients'), ('org','people'), ('whatsapp','mail'),
  ('pms','perf'), ('plb','perf'),
  ('mis','reports'), ('tenday','reports'), ('rates','reports'), ('access','reports')
on conflict (screen) do update set parent = excluded.parent;

-- ------------------------------------------------ which level a chair is at
create table if not exists public.access_chair_level (
  chair_title text primary key,
  level       text not null references public.access_level(level)
);

comment on table public.access_chair_level is
  'The chair decides the level, because the chair is what the design says '
  'drives everything. A title that is not here falls through to the '
  'department, and then to the smallest list there is.';

insert into public.access_chair_level (chair_title, level) values
  ('Executive','exec'),
  ('Field Executives / Verifiers','exec'),
  ('Back Office / Processing Executives','exec'),
  ('Branch Collection Executive','exec'),
  ('Central Collections Executives','exec'),
  ('Team Leader / Supervisor','team'),
  ('Partner Team Leader / Supervisor','team'),
  ('Branch Manager','branch'),
  ('Zonal Manager','branch'),
  ('Regional Manager','branch'),
  ('Assistant Vice President','branch'),
  ('Head — Operations','branch'),
  ('Operations Head','branch'),
  ('Sales Manager','branch'),
  ('Location Partner / Franchisee Partner','partner'),
  ('Head — HR Operations','hr'),
  ('HR Executive','hr'),
  ('Head — Human Resources','hr'),
  ('HR Operations','hr'),
  ('Head — Finance Operations','finance'),
  ('Finance Head','finance'),
  ('Vice President','finance'),
  ('Accounts','finance'),
  ('MIS & Business Analytics','analytics'),
  ('Business Excellence & PMO','staff'),
  ('Assurance, Risk & Compliance','staff'),
  ('Legal & Compliance','staff'),
  ('Company Secretary','staff'),
  ('Chief Executive Officer / Managing Director','admin'),
  ('Managing Director','admin')
on conflict (chair_title) do update set level = excluded.level;

-- ---------------------------------------------------- the department fallback
create table if not exists public.access_department_level (
  department text primary key,
  level      text not null references public.access_level(level)
);

comment on table public.access_department_level is
  'Used only when the person holds no chair, or holds one nobody has '
  'classified. A person the tool cannot place should see less, not more.';

insert into public.access_department_level (department, level) values
  ('Human Resources','hr'),
  ('Finance & Accounts','finance'),
  ('Finance','finance'),
  ('MIS','analytics')
on conflict (department) do update set level = excluded.level;

-- ----------------------------------------------------------- reading it back
-- Same order the published tool's myLevel() uses: administrator first, then
-- the primary chair, then the department, then the smallest list there is.
create or replace function public.access_level_of(p_person uuid)
returns text
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select coalesce(
    (select 'admin' from person p
      where p.id = p_person and p.app_role = 'ADMIN'
        and p.employment_status = 'ACTIVE' and p.superseded_by is null),
    (select cl.level
       from chair_holder h
       join chair ch on ch.id = h.chair_id
       join access_chair_level cl on cl.chair_title = ch.title
      where h.person_id = p_person and h.to_date is null
      order by h.is_primary desc, ch.title
      limit 1),
    (select dl.level from person p
       join access_department_level dl on dl.department = p.department
      where p.id = p_person),
    'exec')
$fn$;

comment on function public.access_level_of(uuid) is
  'The scope level this person is at. Administrator, then primary chair, then '
  'department, then exec.';

create or replace function public.access_screens(p_person uuid)
returns text[]
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select case when access_level_of(p_person) = 'admin'
    then (select array_agg(distinct s order by s)
            from (select screen as s from access_level_screen
                  union select screen from access_screen_parent) q)
    else (select coalesce(array_agg(distinct s order by s), '{}'::text[])
            from (
              select ls.screen as s
                from access_level_screen ls
               where ls.level = access_level_of(p_person)
              union
              -- a child screen comes with its parent, which is how the
              -- rate master rides under Reports
              select sp.screen
                from access_screen_parent sp
                join access_level_screen ls2
                  on ls2.screen = sp.parent
                 and ls2.level = access_level_of(p_person)) q)
  end
$fn$;

comment on function public.access_screens(uuid) is
  'Every screen key this person may open, children included. What auth_whoami '
  'hands the browser and what the ops service gates on.';

create or replace function public.access_may_open(p_person uuid, p_screen text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select case
    when p_screen is null or btrim(p_screen) = '' then false
    when access_level_of(p_person) = 'admin' then true
    else exists (
      select 1 from access_level_screen ls
       where ls.level = access_level_of(p_person)
         and ls.screen = coalesce(
               (select sp.parent from access_screen_parent sp where sp.screen = p_screen),
               p_screen))
  end
$fn$;

comment on function public.access_may_open(uuid, text) is
  'May this person open this screen. The one question the navigation and every '
  'service both ask, so that they cannot answer it differently.';

-- --------------------------------------------- the session carries it now
-- Additive. Everything auth_whoami returned before is returned unchanged; a
-- caller that does not know about scope_level and screens is unaffected.
create or replace function public.auth_whoami(p_token_hash text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_person uuid; v_actor uuid; p person%rowtype; a person%rowtype;
begin
  update auth_session s set last_seen_at = now()
   where s.token_hash = p_token_hash and s.revoked_at is null and s.expires_at > now()
   returning s.person_id, s.acting_actor_id into v_person, v_actor;
  if v_person is null then return null; end if;
  select * into p from person
   where id = v_person and employment_status = 'ACTIVE' and superseded_by is null;
  if not found then return null; end if;
  if v_actor is not null then select * into a from person where id = v_actor; end if;
  return jsonb_build_object(
    'id', p.id, 'full_name', p.full_name, 'work_email', p.work_email,
    'app_role', p.app_role, 'department', p.department,
    'designation', (select d.title from designation d where d.id = p.designation_id),
    'chair_title', (select ch.title from chair_holder h join chair ch on ch.id = h.chair_id
                     where h.person_id = p.id and h.to_date is null
                     order by h.is_primary desc, ch.title limit 1),
    'employee_no', p.employee_no,
    -- the two new ones: what this person may open, decided in one place
    'scope_level', access_level_of(p.id),
    'screens', to_jsonb(access_screens(p.id)),
    'acting', case when v_actor is null then null else jsonb_build_object(
        'by', a.full_name, 'byId', a.id, 'byEmail', a.work_email) end);
end $function$;

-- Looking at the tool as somebody else has to show their navigation, not the
-- administrator's, or the whole point of it is lost.
create or replace function public.auth_act_as(p_actor uuid, p_person uuid, p_chair uuid, p_token_hash text, p_ip text DEFAULT NULL::text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare a person%rowtype; t person%rowtype; n int; v_chair text;
begin
  select * into a from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null or a.app_role <> 'ADMIN' then
    return jsonb_build_object('error','not_permitted',
      'reason','Only an administrator can look at the tool as somebody else.');
  end if;

  if p_person is null and p_chair is not null then
    select count(*) into n from chair_holder h join person p2 on p2.id = h.person_id
     where h.chair_id = p_chair and h.to_date is null
       and p2.superseded_by is null and p2.employment_status = 'ACTIVE';
    select ch.title into v_chair from chair ch where ch.id = p_chair;
    if n = 0 then
      return jsonb_build_object('error','chair_is_empty',
        'reason', coalesce(v_chair,'That chair') || ' has nobody in it, so there is nobody to look at the tool as. Seat somebody first.');
    end if;
    if n > 1 then
      return jsonb_build_object('error','chair_is_shared',
        'reason', v_chair || ' is held by ' || n || ' people. Pick which of them.',
        'holders', (select jsonb_agg(jsonb_build_object('personId', p2.id, 'name', p2.full_name)
                      order by p2.full_name)
                      from chair_holder h join person p2 on p2.id = h.person_id
                     where h.chair_id = p_chair and h.to_date is null
                       and p2.superseded_by is null and p2.employment_status = 'ACTIVE'));
    end if;
    select p2.id into p_person from chair_holder h join person p2 on p2.id = h.person_id
     where h.chair_id = p_chair and h.to_date is null
       and p2.superseded_by is null and p2.employment_status = 'ACTIVE' limit 1;
  end if;

  if p_person is null then
    return jsonb_build_object('error','nobody_named',
      'reason','Name a person, or a chair somebody is sitting in.');
  end if;
  select * into t from person
   where id = p_person and employment_status = 'ACTIVE' and superseded_by is null;
  if t.id is null then
    return jsonb_build_object('error','no_such_person',
      'reason','That person is not active on the people master.');
  end if;
  if t.id = a.id then
    return jsonb_build_object('error','that_is_you',
      'reason','You are already signed in as yourself.');
  end if;

  insert into auth_session (person_id, expires_at, source, token_hash, acting_actor_id)
  values (t.id, now() + interval '2 hours', 'ACT_AS', p_token_hash, a.id);

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (a.id, 'ACTED_AS', 'person', t.id::text,
          jsonb_build_object('actor', a.full_name, 'actorEmail', a.work_email, 'ip', p_ip),
          jsonb_build_object('as', t.full_name, 'asEmail', t.work_email,
                             'asRole', t.app_role, 'viaChair', v_chair));

  return jsonb_build_object('id', t.id, 'full_name', t.full_name,
    'work_email', t.work_email, 'app_role', t.app_role, 'department', t.department,
    'chair_title', (select ch.title from chair_holder h join chair ch on ch.id = h.chair_id
                     where h.person_id = t.id and h.to_date is null
                     order by h.is_primary desc, ch.title limit 1),
    'employee_no', t.employee_no,
    'scope_level', access_level_of(t.id),
    'screens', to_jsonb(access_screens(t.id)),
    'acting', jsonb_build_object('by', a.full_name, 'byId', a.id, 'byEmail', a.work_email),
    'note', 'You are looking at Crux as ' || t.full_name || '. Everything you do here is recorded as ' || t.full_name || ', with your name against it in the audit trail.');
end $function$;

-- ------------------------------------------------------------------- locks
-- Same posture as every other table here: closed to anon and to authenticated,
-- reached only through the definer functions above and by the service role.
alter table public.access_level            enable row level security;
alter table public.access_level_screen     enable row level security;
alter table public.access_screen_parent    enable row level security;
alter table public.access_chair_level      enable row level security;
alter table public.access_department_level enable row level security;

revoke all on function public.access_level_of(uuid)      from public;
revoke all on function public.access_screens(uuid)       from public;
revoke all on function public.access_may_open(uuid,text) from public;

-- =====================================================================
-- Two things that look wrong, recorded rather than changed
--
-- 1. The rate master is a child of Reports, so every level that carries
--    Reports — branch, partner, hr, finance, analytics and staff — can read
--    every client's commercial rate. Finance and the administrator already own
--    WRITING a rate; reading one is open to six of the eight levels. If that
--    is not intended, the fix is one row:
--
--      update access_screen_parent set parent = 'config' where screen = 'rates';
--
--    and the rate master then follows Settings, which only hr, finance and the
--    administrator carry. Nothing else changes.
--
-- 2. The published tool declares ADMIN_TABS = { data, mail, whatsapp } and
--    never reads it. The intention is legible — those three were meant to be
--    the administrator's alone — but SCREENS gives 'mail' to hr and 'data' to
--    analytics, and SCREENS is what actually runs. What is seeded above is
--    what runs. If the intention was the real policy, delete those two screens
--    from those two levels and remove the dead variable.
-- =====================================================================
