-- =====================================================================
-- 15 · GEOGRAPHY MASTER — the owner's 98-row Crux geography, loaded as the
-- authority it is. 10_geography.sql seeded a 24-city guess (stg.city_state)
-- that left 572 of 1,413 branches with no geo_node at all.
--
-- The file's column order (group, region, zone, state, city) is misleading:
-- its `zone` sits BELOW state, not above it — Karnataka holds both
-- "Bengaluru Zone" and "Rest of Karnataka Zone". So the mapping is
--   geo_node ZONE  <- master.region   (East / North / South / West)
--   geo_node STATE <- master.state
--   geo_node CITY  <- master.city
-- and `zone`/`group` have no level in geo_level (ZONE, STATE, CITY only).
-- They stay in stg.geo_master rather than being dropped, and both are queued
-- as questions.
--
-- Rules
--   G-05 the master's state -> region wins over the seeded state_zone table
--        (Madhya Pradesh Central->West, Chhattisgarh Central->East,
--        Assam North East->East). Every move is logged.
--   G-06 geo_node held a second, PARENTLESS tree from the seeded demo data,
--        shaped STATE -> ZONE -> CITY, the inverse of ours. 49 branches
--        pointed into it. References merge into the node of the same name in
--        the real tree; nothing is deleted while anything still points at it.
--   G-07 what is left of that tree is deleted and listed in stg.geo_deleted.
--   G-08 a branch whose city the master does not know is attached to the node
--        its own Zone column names — CITY if we hold one, else STATE, else
--        ZONE. That is precision we can justify, not a guess, and the question
--        about the exact city stays open.
--   G-09 "Chandigarh" in BRANCHES.Zone means Chhattisgarh: of 43 such
--        branches, 21 carry a city that is unambiguously in Chhattisgarh.
--        The 6 that read Chandigarh in BOTH columns are left unplaced and
--        asked about, because nothing in the data decides them.
--   G-10 two union territories the branch data uses and no table held:
--        Andaman & Nicobar Islands and Daman & Diu.
--
-- Source: build/migration/masters/geography.tsv
-- =====================================================================
create table if not exists stg.geo_master (
  grp text, region text, zone_name text, state text, city text
);
comment on table stg.geo_master is
  'The owner''s geography master as uploaded, unaltered. geo_node carries the three levels geo_level allows; grp (Zone A/B tier) and zone_name (operating zone) live only here until they have a home.';
truncate stg.geo_master;
insert into stg.geo_master (grp, region, zone_name, state, city) values
('Zone B','East','Bhubaneswar Odisha Zone','Odisha','Bhubaneswar'),
('Zone B','East','Bhubaneswar Odisha Zone','Odisha','Cuttack'),
('Zone B','East','Bhubaneswar Odisha Zone','Odisha','Rourkela'),
('Zone B','East','Bhubaneswar Odisha Zone','Odisha','Sambalpur'),
('Zone A','West','Bhopal MP Zone','Madhya Pradesh','Bhopal'),
('Zone A','West','Bhopal MP Zone','Madhya Pradesh','Indore'),
('Zone B','West','Bhopal MP Zone','Madhya Pradesh','Gwalior'),
('Zone B','West','Bhopal MP Zone','Madhya Pradesh','Jabalpur'),
('Zone B','West','Bhopal MP Zone','Madhya Pradesh','Ujjain'),
('Zone A','South','Bengaluru Zone','Karnataka','Bengaluru'),
('Zone B','South','Rest of Karnataka Zone','Karnataka','Mysuru'),
('Zone B','South','Rest of Karnataka Zone','Karnataka','Mangaluru'),
('Zone B','South','Rest of Karnataka Zone','Karnataka','Hubballi-Dharwad'),
('Zone B','South','Rest of Karnataka Zone','Karnataka','Belagavi'),
('Zone B','South','Rest of Karnataka Zone','Karnataka','Kalaburagi'),
('Zone B','South','Rest of Karnataka Zone','Karnataka','Shivamogga'),
('Zone B','South','Kerala Zone','Kerala','Kochi'),
('Zone B','South','Kerala Zone','Kerala','Thiruvananthapuram'),
('Zone B','South','Kerala Zone','Kerala','Kozhikode'),
('Zone B','South','Kerala Zone','Kerala','Thrissur'),
('Zone B','South','Kerala Zone','Kerala','Kollam'),
('Zone B','South','Kerala Zone','Kerala','Kottayam'),
('Zone B','South','Rest of Tamil Nadu Zone','Tamil Nadu','Coimbatore'),
('Zone B','South','Rest of Tamil Nadu Zone','Tamil Nadu','Madurai'),
('Zone B','South','Rest of Tamil Nadu Zone','Tamil Nadu','Tiruchirappalli'),
('Zone B','South','Rest of Tamil Nadu Zone','Tamil Nadu','Salem'),
('Zone B','South','Rest of Tamil Nadu Zone','Tamil Nadu','Tiruppur'),
('Zone B','South','Rest of Tamil Nadu Zone','Tamil Nadu','Erode'),
('Zone B','South','Rest of Tamil Nadu Zone','Tamil Nadu','Vellore'),
('Zone B','South','Rest of Tamil Nadu Zone','Tamil Nadu','Thoothukudi'),
('Zone B','South','Chennai Zone','Tamil Nadu','Chennai'),
('Zone A','North','Delhi Zone','Delhi','Delhi'),
('Zone B','North','Punjab Zone','Punjab','Amritsar'),
('Zone B','North','Punjab Zone','Punjab','Ludhiana'),
('Zone B','North','Punjab Zone','Punjab','Jalandhar'),
('Zone B','West','Gujarat Zone','Gujarat','Ahmedabad'),
('Zone B','West','Gujarat Zone','Gujarat','Vadodara'),
('Zone B','West','Gujarat Zone','Gujarat','Surat'),
('Zone B','West','Gujarat Zone','Gujarat','Rajkot'),
('Zone B','West','Gujarat Zone','Gujarat','Gandhinagar'),
('Zone B','West','Gujarat Zone','Gujarat','Bhavnagar'),
('Zone B','West','Gujarat Zone','Gujarat','Jamnagar'),
('Zone B','West','Gujarat Zone','Gujarat','Bharuch'),
('Zone B','West','Gujarat Zone','Gujarat','Vapi'),
('Zone B','East','Guwahati Assam Zone','Assam','Guwahati'),
('Zone B','East','Guwahati Assam Zone','Assam','Dibrugarh'),
('Zone B','East','Guwahati Assam Zone','Assam','Silchar'),
('Zone A','South','Hyderabad Zone','Telangana','Hyderabad'),
('Zone B','South','Hyderabad Zone','Telangana','Warangal'),
('Zone B','South','Hyderabad Zone','Telangana','Karimnagar'),
('Zone B','South','Hyderabad Zone','Telangana','Nizamabad'),
('Zone A','East','Kolkata Zone','West Bengal','Kolkata'),
('Zone B','East','Kolkata Zone','West Bengal','Asansol'),
('Zone B','East','Kolkata Zone','West Bengal','Durgapur'),
('Zone B','East','Kolkata Zone','West Bengal','Siliguri'),
('Zone B','North','Uttar Pradesh Zone','Uttar Pradesh','Lucknow'),
('Zone B','North','Uttar Pradesh Zone','Uttar Pradesh','Kanpur'),
('Zone B','North','Uttar Pradesh Zone','Uttar Pradesh','Agra'),
('Zone B','North','Uttar Pradesh Zone','Uttar Pradesh','Noida'),
('Zone B','North','Uttar Pradesh Zone','Uttar Pradesh','Ghaziabad'),
('Zone B','North','Uttar Pradesh Zone','Uttar Pradesh','Varanasi'),
('Zone B','North','Uttar Pradesh Zone','Uttar Pradesh','Prayagraj'),
('Zone B','North','Uttar Pradesh Zone','Uttar Pradesh','Meerut'),
('Zone B','North','Uttar Pradesh Zone','Uttar Pradesh','Gorakhpur'),
('Zone A','West','Mumbai Zone','Maharashtra','Mumbai'),
('Zone B','West','Goa Zone','Goa','Panaji'),
('Zone B','West','Goa Zone','Goa','Margao'),
('Zone B','West','Rest of Maharashtra Zone','Maharashtra','Amravati'),
('Zone B','West','Rest of Maharashtra Zone','Maharashtra','Chhatrapati Sambhajinagar'),
('Zone B','West','Rest of Maharashtra Zone','Maharashtra','Nagpur'),
('Zone B','West','Rest of Maharashtra Zone','Maharashtra','Nashik'),
('Zone B','West','Rest of Maharashtra Zone','Maharashtra','Kolhapur'),
('Zone B','West','Rest of Maharashtra Zone','Maharashtra','Jalgaon'),
('Zone B','West','Rest of Maharashtra Zone','Maharashtra','Latur'),
('Zone B','West','Rest of Maharashtra Zone','Maharashtra','Nanded'),
('Zone B','West','Rest of Maharashtra Zone','Maharashtra','Solapur'),
('Zone B','West','Rest of Maharashtra Zone','Maharashtra','Sangli'),
('Zone B','West','Rest of Maharashtra Zone','Maharashtra','Satara'),
('Zone B','West','Rest of Maharashtra Zone','Maharashtra','Ahmednagar'),
('Zone B','West','Rest of Maharashtra Zone','Maharashtra','Akola'),
('Zone B','West','Rest of Maharashtra Zone','Maharashtra','Ratnagiri'),
('Zone B','West','Rest of Maharashtra Zone','Maharashtra','Wardha'),
('Zone A','West','Pune Zone','Maharashtra','Pune'),
('Zone B','East','Patna Zone','Bihar','Patna'),
('Zone B','East','Patna Zone','Bihar','Muzaffarpur'),
('Zone B','East','Patna Zone','Bihar','Gaya'),
('Zone B','East','Patna Zone','Bihar','Bhagalpur'),
('Zone B','East','Rest of Jharkhand Zone','Jharkhand','Ranchi'),
('Zone B','East','Rest of Jharkhand Zone','Jharkhand','Jamshedpur'),
('Zone B','East','Rest of Jharkhand Zone','Jharkhand','Dhanbad'),
('Zone B','East','Rest of Chhattisgarh Zone','Chhattisgarh','Raipur'),
('Zone B','East','Rest of Chhattisgarh Zone','Chhattisgarh','Bilaspur'),
('Zone B','East','Rest of Chhattisgarh Zone','Chhattisgarh','Durg-Bhilai'),
('Zone B','West','Rest of Maharashtra Zone','Maharashtra','Rest of Maharashtra'),
('Zone B','South','Rest of Karnataka Zone','Karnataka','Rest of Karnataka'),
('Zone B','South','Rest of Tamil Nadu Zone','Tamil Nadu','Rest of Tamil Nadu'),
('Zone B','East','Rest of Bihar Zone','Bihar','Rest of Bihar'),
('Zone B','East','Rest of Jharkhand Zone','Jharkhand','Rest of Jharkhand');

-- ------------------------------------------------ G-06 · the parentless tree
create table if not exists stg.geo_deleted (
  at timestamptz not null default now(), level text, name text, reason text
);
comment on table stg.geo_deleted is
  'Rule G-07. Every geo_node removed as seeded demo scaffolding, with the reason. Nothing referenced these rows when they were deleted.';

do $$
declare doomed uuid[]; r record; blocked text;
begin
  create temp table geo_demo_merge on commit drop as
  with recursive demo as (
    select id, name, level, parent_id from geo_node where parent_id is null and level = 'STATE'
    union all
    select c.id, c.name, c.level, c.parent_id from geo_node c join demo d on c.parent_id = d.id
  )
  select d.id as orphan_id,
         (select k.id from geo_node k
          where k.id <> d.id and lower(k.name) = lower(d.name)
            and not exists (select 1 from demo x where x.id = k.id)
          order by (k.level = 'CITY') desc limit 1) as keep_id
  from demo d;
  delete from geo_demo_merge where keep_id is null;

  for r in select c.relname tbl, a.attname col from pg_constraint con
           join pg_class c on c.oid = con.conrelid
           join pg_attribute a on a.attrelid = c.oid and a.attnum = any(con.conkey)
           where con.contype = 'f' and con.confrelid = 'geo_node'::regclass and c.relname <> 'geo_node'
  loop
    execute format('update %I t set %I = m.keep_id from geo_demo_merge m where t.%I = m.orphan_id',
                   r.tbl, r.col, r.col);
  end loop;

  -- a demo CITY with no counterpart but with branches keeps its identity
  update geo_node c
  set parent_id = ps.id
  from geo_node z, geo_node s, geo_node ps
  where c.level = 'CITY' and c.parent_id = z.id
    and z.level = 'ZONE' and z.parent_id = s.id
    and s.level = 'STATE' and s.parent_id is null
    and ps.level = 'STATE' and ps.parent_id is not null and lower(ps.name) = lower(s.name)
    and exists (select 1 from branch b where b.geo_node_id = c.id);

  -- G-07 · delete what is left, but only once nothing points at it
  with recursive roots as (
    select id from geo_node where parent_id is null and level = 'STATE'
    union all
    select c.id from geo_node c join roots x on c.parent_id = x.id
  )
  select array_agg(id) into doomed from roots;
  if doomed is null then return; end if;

  for r in select c.relname tbl, a.attname col from pg_constraint con
           join pg_class c on c.oid = con.conrelid
           join pg_attribute a on a.attrelid = c.oid and a.attnum = any(con.conkey)
           where con.contype = 'f' and con.confrelid = 'geo_node'::regclass and c.relname <> 'geo_node'
  loop
    execute format('select case when exists (select 1 from %I where %I = any($1)) then %L end',
                   r.tbl, r.col, r.tbl || '.' || r.col) into blocked using doomed;
    if blocked is not null then
      raise exception 'demo geography still referenced by % — nothing deleted', blocked;
    end if;
  end loop;

  insert into stg.geo_deleted (level, name, reason)
  select g.level::text, g.name,
         'G-07 seeded demo geography: STATE->ZONE->CITY inversion, references merged into the real tree first'
  from geo_node g where g.id = any(doomed);

  delete from geo_node where id = any(doomed);
end $$;

-- ------------------------------------------------------ the master, applied
insert into geo_node (parent_id, level, name)
select null, 'ZONE', r from (select distinct region from stg.geo_master) v(r)
on conflict do nothing;

-- G-05 receipt, written before the move so it can name where the state was
insert into migration_merge (entity_type, kept_id, merged_key, rows_moved, rule)
select 'geo_node', g.id, g.name, 1,
       'G-05 state re-parented from ' || z0.name || ' to ' || m.region || ' on the owner''s geography master'
from geo_node g
join geo_node z0 on z0.id = g.parent_id
join (select distinct state, region from stg.geo_master) m on m.state = g.name
where g.level = 'STATE' and z0.name <> m.region;

update geo_node g
set parent_id = z.id
from (select distinct state, region from stg.geo_master) m
join geo_node z on z.level = 'ZONE' and z.name = m.region
where g.level = 'STATE' and g.name = m.state and g.parent_id is distinct from z.id;

insert into geo_node (parent_id, level, name)
select z.id, 'STATE', m.state
from (select distinct state, region from stg.geo_master) m
join geo_node z on z.level = 'ZONE' and z.name = m.region
on conflict do nothing;

insert into geo_node (parent_id, level, name)
select s.id, 'CITY', m.city
from (select distinct state, city from stg.geo_master) m
join geo_node s on s.level = 'STATE' and s.name = m.state
on conflict do nothing;

update branch b
set geo_node_id = c.id
from stg.branches sb
join (select distinct state, city from stg.geo_master) m on lower(m.city) = lower(btrim(sb.city))
join geo_node s on s.level = 'STATE' and s.name = m.state
join geo_node c on c.level = 'CITY' and c.name = m.city and c.parent_id = s.id
where b.source_ref = 'BRANCHES!' || sb.row_no and b.geo_node_id is distinct from c.id;

-- G-04 · every branch the master still cannot place becomes a question
insert into migration_review (entity_type, entity_ref, question, context)
select 'branch', b.source_ref,
       case when not stg.present(sb.city) and not stg.present(sb.state)
              then 'No city or state on this branch — which city does it belong to?'
            else 'City "' || btrim(coalesce(sb.city, sb.state, sb.zone)) || '" is not in the geography master — which city or "Rest of <state>" does it belong to?' end,
       concat_ws(' | ', nullif(btrim(sb.address),''), nullif(btrim(sb.zone),''), nullif(btrim(sb.city),''))
from branch b
join stg.branches sb on b.source_ref = 'BRANCHES!' || sb.row_no
where b.geo_node_id is null
  and not exists (select 1 from migration_review r where r.entity_ref = b.source_ref and r.entity_type = 'branch');

insert into migration_review (entity_type, entity_ref, question, context)
select 'geo_node', 'MASTER', v.q, v.ctx
from (values
  ('The master names an operating zone under each state (Bengaluru Zone, Rest of Karnataka Zone, and 18 more). geo_level has ZONE, STATE and CITY only, so it is held in stg.geo_master. Add it as a fourth level, or keep it as a label?',
   '20 operating zones across 17 states'),
  ('The master tiers each city Zone A or Zone B. Nothing in the schema reads it. Should it drive rates, or is it reporting only?',
   '8 cities Zone A, 90 Zone B')
) v(q, ctx)
where not exists (select 1 from migration_review r where r.entity_type = 'geo_node' and r.question = v.q);

-- ----------------------------------------- G-08 · placed by the Zone column
update branch b
set geo_node_id = g.id
from stg.branches sb,
     lateral (
       select n.id
       from geo_node n
       where lower(n.name) = lower(btrim(
               case when upper(btrim(coalesce(sb.zone,''))) = 'ROMG' then 'Maharashtra' else sb.zone end))
       order by case n.level when 'CITY' then 1 when 'STATE' then 2 else 3 end
       limit 1
     ) g
where b.source_ref = 'BRANCHES!' || sb.row_no
  and b.geo_node_id is null
  and stg.present(sb.zone);

-- --------------------------------------------- G-09 / G-10 · the last cases
insert into geo_node (parent_id, level, name)
select z.id, 'STATE', v.state
from (values ('Chandigarh','North'),
             ('Andaman and Nicobar Island','South'),
             ('Daman and Diu','West')) v(state, zone)
join geo_node z on z.level = 'ZONE' and z.name = v.zone
on conflict do nothing;

insert into geo_node (parent_id, level, name)
select s.id, 'CITY', v.city
from (values ('Chandigarh','Chandigarh'),
             ('Andaman and Nicobar Island','Port Blair'),
             ('Daman and Diu','Daman')) v(state, city)
join geo_node s on s.level = 'STATE' and s.name = v.state
on conflict do nothing;

update branch b
set geo_node_id = c.id
from stg.branches sb
join (values ('Port Blair','Andaman and Nicobar Island'), ('Daman','Daman and Diu')) v(city, state)
  on lower(v.city) = lower(btrim(sb.city))
join geo_node s on s.level = 'STATE' and s.name = v.state
join geo_node c on c.level = 'CITY' and c.name = v.city and c.parent_id = s.id
where b.source_ref = 'BRANCHES!' || sb.row_no and b.geo_node_id is null;

update branch b
set geo_node_id = s.id
from stg.branches sb, geo_node s
where b.source_ref = 'BRANCHES!' || sb.row_no
  and b.geo_node_id is null
  and upper(btrim(coalesce(sb.zone,''))) = 'CHANDIGARH'
  and lower(btrim(coalesce(sb.city,''))) <> 'chandigarh'
  and s.level = 'STATE' and s.name = 'Chhattisgarh';

insert into migration_review (entity_type, entity_ref, question, context)
select 'branch', b.source_ref,
       'Zone read "Chandigarh" but the city is a Chhattisgarh town, and 21 other branches with the same Zone resolve to Raipur, Bilaspur, Korba, Bhilai, Durg and Raigarh. Filed under Chhattisgarh at state level (G-09). Confirm the state, and name the city so it can be placed precisely.',
       concat_ws(' | ', nullif(btrim(sb.city),''), nullif(btrim(sb.address),''))
from branch b
join stg.branches sb on b.source_ref = 'BRANCHES!' || sb.row_no
join geo_node s on s.id = b.geo_node_id and s.level = 'STATE' and s.name = 'Chhattisgarh'
where upper(btrim(coalesce(sb.zone,''))) = 'CHANDIGARH'
  and not exists (select 1 from migration_review r where r.entity_ref = b.source_ref and r.question like 'Zone read "Chandigarh"%');

insert into migration_review (entity_type, entity_ref, question, context)
select 'branch', b.source_ref,
       'Zone and city both read "Chandigarh". Every other branch with this Zone is in Chhattisgarh, so this is either the same misspelling or the real union territory. Which is it?',
       concat_ws(' | ', nullif(btrim(sb.address),''))
from branch b
join stg.branches sb on b.source_ref = 'BRANCHES!' || sb.row_no
where b.geo_node_id is null
  and upper(btrim(coalesce(sb.zone,''))) = 'CHANDIGARH'
  and not exists (select 1 from migration_review r where r.entity_ref = b.source_ref and r.question like 'Zone and city both read%');
