-- Behaviour tests for migrations 204 and 205: who may open what, and whose
-- figures they see when they do.
--
-- The published tool has always said of its own access table that it "is NOT
-- the permission check" and that "every service decides for itself". Until 204
-- no service did. What is asserted below is the half that a service can be
-- held to: the level a person resolves to, the screens it carries, and — the
-- one that actually leaks data — that business_record is matched against
-- coverage as (client, geography) PAIRS and not as two separate lists.
--
-- The pair test is the point. A person covering Client A in Zone 1 and Client
-- B in Zone 2 must see two rows out of four. Filtering on clients and zones
-- separately would show them all four and look entirely reasonable doing it.

\set ON_ERROR_STOP on
set client_min_messages to notice;

create or replace function t_ok(p_name text, p_cond boolean, p_saw text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'PASS  %', p_name;
  else
    raise exception 'FAIL  % %', p_name, coalesce('-- saw: ' || p_saw, '');
  end if;
end $$;

-- ===================================================================== seed
-- Re-runnable: everything it makes, it removes first.
delete from business_record where source_ref = 'scope-test';
delete from coverage_rule where person_id in
  (select id from person where work_email like '%@scope.test');
delete from chair_holder where person_id in
  (select id from person where work_email like '%@scope.test');
delete from person where work_email like '%@scope.test';
delete from branch where source_ref = 'scope-test';
delete from client where code in ('SCOPE-A','SCOPE-B');
delete from chair where code in ('SCOPE_BM','SCOPE_EXEC','SCOPE_MIS');
delete from geo_node where name in ('Scopeland North','Scopeland South');

do $$
declare
  pa uuid; pb uuid; padmin uuid;
  ch_bm uuid; ch_ex uuid; ch_mis uuid;
  cla uuid; clb uuid; za uuid; zb uuid;
  b_a_za uuid; b_a_zb uuid; b_b_za uuid; b_b_zb uuid;
begin
  -- Two chairs whose titles the access table already classifies, and one it
  -- does not, so the fallback is exercised too.
  insert into chair (code, title, level) values
    ('SCOPE_BM','Branch Manager','branch') returning id into ch_bm;
  insert into chair (code, title, level) values
    ('SCOPE_EXEC','Executive','executive') returning id into ch_ex;
  insert into chair (code, title, level) values
    ('SCOPE_MIS','A title nobody has classified','function') returning id into ch_mis;

  insert into person (employee_no, full_name, work_email, department,
                      app_role, employment_status)
  values ('SC-001','Asha Pair','asha@scope.test','Operations','MANAGER','ACTIVE')
  returning id into pa;
  insert into person (employee_no, full_name, work_email, department,
                      app_role, employment_status)
  values ('SC-002','Bal Exec','bal@scope.test','Operations','VIEWER','ACTIVE')
  returning id into pb;
  insert into person (employee_no, full_name, work_email, department,
                      app_role, employment_status)
  values ('SC-003','Ada Admin','ada@scope.test','Operations','ADMIN','ACTIVE')
  returning id into padmin;

  insert into chair_holder (chair_id, person_id, from_date, is_primary)
  values (ch_bm, pa, current_date, true), (ch_ex, pb, current_date, true);

  -- two clients, two states, four branches: every combination
  insert into client (code, name, status) values ('SCOPE-A','Scope Bank A','ACTIVE')
  returning id into cla;
  insert into client (code, name, status) values ('SCOPE-B','Scope Bank B','ACTIVE')
  returning id into clb;
  insert into geo_node (level, name) values ('STATE','Scopeland North') returning id into za;
  insert into geo_node (level, name) values ('STATE','Scopeland South') returning id into zb;

  insert into branch (code, name, client_id, geo_node_id, status, source_ref)
  values ('SC-A-N','A North', cla, za, 'ACTIVE','scope-test') returning id into b_a_za;
  insert into branch (code, name, client_id, geo_node_id, status, source_ref)
  values ('SC-A-S','A South', cla, zb, 'ACTIVE','scope-test') returning id into b_a_zb;
  insert into branch (code, name, client_id, geo_node_id, status, source_ref)
  values ('SC-B-N','B North', clb, za, 'ACTIVE','scope-test') returning id into b_b_za;
  insert into branch (code, name, client_id, geo_node_id, status, source_ref)
  values ('SC-B-S','B South', clb, zb, 'ACTIVE','scope-test') returning id into b_b_zb;

  -- Asha covers A in the north and B in the south. The diagonal, deliberately.
  insert into coverage_rule (person_id, role, scope_type, client_id, geo_node_id)
  values (pa, 'HANDLER', 'STATE', cla, za),
         (pa, 'HANDLER', 'STATE', clb, zb);

  -- one record per combination
  insert into business_record (period, business_date, client_id, geo_node_id,
                               mtd, day10, target, revenue, source_ref)
  values ('2026-09', '2026-09-30', cla, za, 100, 40, 120, 1000, 'scope-test'),
         ('2026-09', '2026-09-30', cla, zb, 200, 80, 220, 2000, 'scope-test'),
         ('2026-09', '2026-09-30', clb, za, 300, 120, 320, 3000, 'scope-test'),
         ('2026-09', '2026-09-30', clb, zb, 400, 160, 420, 4000, 'scope-test');
end $$;

-- =============================================== the level a person is at
do $$
declare pa uuid; pb uuid; padmin uuid; v text; s text[];
begin
  select id into pa     from person where work_email = 'asha@scope.test';
  select id into pb     from person where work_email = 'bal@scope.test';
  select id into padmin from person where work_email = 'ada@scope.test';

  perform t_ok('a Branch Manager is at branch level',
    access_level_of(pa) = 'branch', access_level_of(pa));
  perform t_ok('an Executive is at exec level',
    access_level_of(pb) = 'exec', access_level_of(pb));
  perform t_ok('an administrator is admin whatever chair they hold',
    access_level_of(padmin) = 'admin', access_level_of(padmin));

  -- what each one may open
  perform t_ok('a branch manager may open Reports',      access_may_open(pa, 'reports'));
  perform t_ok('an executive may not open Reports',  not access_may_open(pb, 'reports'));
  perform t_ok('an executive may open their own Performance', access_may_open(pb, 'perf'));
  perform t_ok('an executive may not open Automations', not access_may_open(pb, 'auto'));
  perform t_ok('an executive may not open the rate master', not access_may_open(pb, 'rates'));
  perform t_ok('an administrator may open anything',    access_may_open(padmin, 'auto')
                                                    and access_may_open(padmin, 'rates')
                                                    and access_may_open(padmin, 'data'));

  -- a child screen rides with its parent, which is how the rate master is
  -- reachable at all
  perform t_ok('the rate master follows Reports',
    access_may_open(pa, 'rates') = access_may_open(pa, 'reports'));
  perform t_ok('Places and coverage is not a branch screen',
    not access_may_open(pa, 'coverage'));

  -- nothing is open by accident
  perform t_ok('a screen nobody has heard of is refused',
    not access_may_open(pb, 'not-a-screen'));
  perform t_ok('an empty screen key is refused', not access_may_open(pb, ''));

  -- Seven from SCREENS, plus the two children of Performance. Appraisal and
  -- Bonus are reached from inside Performance, so anyone who carries
  -- Performance carries them; the navigation's allowed() says the same.
  s := access_screens(pb);
  perform t_ok('an executive carries their seven screens and the two inside Performance',
    array_length(s, 1) = 9 and s @> array['perf','pms','plb'], array_to_string(s, ','));
  s := access_screens(pa);
  perform t_ok('a branch manager carries Reports and its four children too',
    s @> array['reports','mis','tenday','rates','access'], array_to_string(s, ','));
end $$;

-- ================================================== the fallback, in order
do $$
declare p uuid; ch uuid;
begin
  select id into ch from chair where code = 'SCOPE_MIS';
  insert into person (employee_no, full_name, work_email, department,
                      app_role, employment_status)
  values ('SC-004','Uma Unclassified','uma@scope.test','Human Resources','VIEWER','ACTIVE')
  returning id into p;

  perform t_ok('no chair at all falls back to the department',
    access_level_of(p) = 'hr', access_level_of(p));

  insert into chair_holder (chair_id, person_id, from_date, is_primary)
  values (ch, p, current_date, true);
  perform t_ok('a chair nobody has classified still falls back to the department',
    access_level_of(p) = 'hr', access_level_of(p));

  update person set department = 'Something Nobody Configured' where id = p;
  perform t_ok('a person the tool cannot place sees the smallest list, not the largest',
    access_level_of(p) = 'exec', access_level_of(p));
end $$;

-- ============================================ the pair test: whose figures
do $$
declare
  pa uuid; cids uuid[]; gids uuid[]; n int; labels text;
begin
  select id into pa from person where work_email = 'asha@scope.test';

  -- exactly what ops/scope.ts recordScope() runs
  select array_agg(client_id), array_agg(geo_node_id) into cids, gids
    from (select distinct b.client_id, b.geo_node_id
            from coverage_rule r
            cross join lateral coverage_resolve(r) cr(branch_id)
            join branch b on b.id = cr.branch_id
           where r.person_id = pa
             and (r.effective_to is null or r.effective_to >= current_date)) q;

  perform t_ok('coverage resolves to two client-and-place pairs',
    array_length(cids, 1) = 2, array_length(cids, 1)::text);

  -- and exactly what ops/routes/mis.ts IN_SCOPE() runs
  select count(*), string_agg(c.code || '/' || g.name, ', ' order by c.code)
    into n, labels
    from business_record b
    join client c on c.id = b.client_id
    join geo_node g on g.id = b.geo_node_id
   where b.source_ref = 'scope-test'
     and (cids is null or exists (
           select 1 from unnest(cids, gids) as s(cid, gid)
            where s.cid = b.client_id and s.gid = b.geo_node_id));

  perform t_ok('four records exist and the covering person sees two of them',
    n = 2, n::text || ' -- ' || coalesce(labels,''));
  perform t_ok('and they are the two they cover, not the two that share a client',
    labels = 'SCOPE-A/Scopeland North, SCOPE-B/Scopeland South', labels);

  -- the failure this test exists to catch: clients and places matched apart
  select count(*) into n from business_record b
   where b.source_ref = 'scope-test'
     and b.client_id = any(cids) and b.geo_node_id = any(gids);
  perform t_ok('matching client and place separately would have shown all four',
    n = 4, n::text);

  -- an administrator passes nulls and gets everything
  select count(*) into n from business_record b
   where b.source_ref = 'scope-test'
     and (null::uuid[] is null or exists (
           select 1 from unnest(null::uuid[], null::uuid[]) as s(cid, gid)
            where s.cid = b.client_id and s.gid = b.geo_node_id));
  perform t_ok('an administrator sees all four', n = 4, n::text);
end $$;

-- ============================================ the ten-day view carries keys
do $$
declare n int;
begin
  perform t_ok('the ten-day view carries client_id and geo_node_id',
    (select count(*) from pg_attribute
      where attrelid = 'seam.tenday_snapshot'::regclass
        and attname in ('client_id','geo_node_id')) = 2);

  select count(*) into n from seam.tenday_snapshot t
   where t.period = '2026-09'
     and exists (select 1 from business_record b
                  where b.id::text = t.id and b.source_ref = 'scope-test');
  perform t_ok('and still returns every row it did before', n = 4, n::text);
end $$;

do $$ begin
  raise notice '--- % people, % records, % coverage rules in the scope fixture',
    (select count(*) from person where work_email like '%@scope.test'),
    (select count(*) from business_record where source_ref = 'scope-test'),
    (select count(*) from coverage_rule where person_id in
       (select id from person where work_email like '%@scope.test'));
end $$;
