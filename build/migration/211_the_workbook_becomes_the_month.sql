-- 211 · The workbook becomes the month
--
-- business_record had nought rows. Every screen that reads it -- MIS, the ten
-- day view, Reports, the performance pages -- was therefore honest and empty,
-- which reads exactly like a tool that does not work.
--
-- The workbook (Full_Data.xlsx: 4,202 rows, 79 month ends from January 2020 to
-- September 2026, 35 locations, 37 clients, 21 people) lands in stg.bl_dim /
-- stg.bl_fact / stg.bl_own. Loading it is not the hard part. The hard part is
-- that the workbook names things in its own words -- "Bengaluru + Rest Of
-- Karnataka + Kerela", "NAGPUR (YASH)", "BOB Car Loan +" -- and the database
-- names them in its. Somebody has to say which is which, and that somebody
-- must be able to be wrong in public.
--
-- So the mapping is a TABLE, not a CASE buried in a script:
--
--   business_import_alias (kind, source_text, target_id, is_guess, note)
--
-- Every one of the 93 names the workbook uses gets a row. Three of them are
-- guesses and say so; they are also written to migration_review so they appear
-- where unanswered questions appear rather than in a comment nobody reads.
-- Next month's workbook uses the same table, so this is done once.
--
-- Two notes on what the workbook does NOT contain:
--
--   * Revenue = MTD x Rate, exactly, in all 4,202 rows -- the Rate column is
--     derived in the sheet, not configured. Rates therefore do not load into
--     the rate master from here; they would be a fact wearing a policy's
--     clothes. MTD and Revenue load; Rate is left where it came from.
--   * There is no day-10 figure and no target. Both stay 0, and the MIS goes
--     on saying "No targets are set for this period", which is true.
--
-- Sixteen of the 4,202 rows merge: two Lucknow rows, two Nagpur rows and one
-- client spelled two ways all land on the same (period, client, place). They
-- are summed, and the owner of the larger half keeps the row. 4,202 in,
-- 4,186 out, and the money is the same on both sides -- asserted below.
--
-- Running this on a database rebuilt from build/schema alone loads nothing,
-- because the staging tables are empty there. It still creates the alias table
-- and the loader, which is the part the repository owes.

-- ---------------------------------------------------------------- the map

create table if not exists public.business_import_alias (
  kind        text not null check (kind in ('location','client','person')),
  source_text text not null,
  target_id   uuid,
  is_guess    boolean not null default false,
  note        text,
  created_at  timestamptz not null default now(),
  primary key (kind, source_text)
);

comment on table public.business_import_alias is
  'What the monthly business workbook calls a place, a client or a person, and '
  'which row in this database that is. target_id null means the workbook names '
  'somebody or something this database does not have. is_guess marks a mapping '
  'that was inferred rather than matched, and each of those also has an open '
  'migration_review row.';

alter table public.business_import_alias enable row level security;
do $$ begin
  create policy business_import_alias_read on public.business_import_alias
    for select to authenticated using (true);
exception when duplicate_object then null; end $$;
grant select on public.business_import_alias to authenticated;

-- ------------------------------------------------------- places (35 names)
-- Matched on the CITY name. Three are inferences: the workbook names a state
-- where the database has a city, and the state has more than one.

with m(src, city, guess, note) as (values
  ('AHMEDABAD','Ahmedabad',false,null),
  ('Amaravati','Amaravati',false,null),
  ('BHAVNAGAR','Bhavnagar',false,null),
  ('BIHAR/PATNA','Patna',false,null),
  ('Bengaluru + Rest Of Karnataka + Kerela','Bengaluru',false,'One workbook line covers Bengaluru, the rest of Karnataka and Kerala; it lands on Bengaluru.'),
  ('Bhopal','Bhopal',false,null),
  ('Bhuvaneshvar ODISHA Zone','Bhubaneswar',false,null),
  ('Bilaspur','Bilaspur',false,null),
  ('Chhatrapati SambhajinaJar (AURANGABAD)','Chhatrapati Sambhajinagar',false,null),
  ('Delhi','Delhi',false,null),
  ('GANDHINAGAR','Gandhinagar',false,null),
  ('GOA','Panaji',true,'The workbook says GOA. The database has no Goa; Panaji is the only city in it that is in Goa.'),
  ('GWALIOR','Gwalior',false,null),
  ('Guwahati Assam Zone','Guwahati',false,null),
  ('Hyderabad Zone','Hyderabad',false,null),
  ('Indore','Indore',false,null),
  ('JALGAON','Jalgaon',false,null),
  ('JHARKHAND','Rest of Jharkhand',true,'The workbook says JHARKHAND. Ranchi and "Rest of Jharkhand" both exist; the state-wide line was read as the remainder.'),
  ('KOLHAPUR','Kolhapur',false,null),
  ('Kolkata Zone','Kolkata',false,null),
  ('Latur (MM)','Latur',false,null),
  ('Lucknow/ROUP -  (Ajay Pathak)','Lucknow',false,'Lucknow is split across two workbook lines by owner; both land on Lucknow and are summed.'),
  ('Lucknow/ROUP -  (Mukesh Yadav)','Lucknow',false,'Lucknow is split across two workbook lines by owner; both land on Lucknow and are summed.'),
  ('Mumbai','Mumbai',false,null),
  ('NAGPUR','Nagpur',false,'Nagpur is split across two workbook lines by owner; both land on Nagpur and are summed.'),
  ('NAGPUR (YASH)','Nagpur',false,'Nagpur is split across two workbook lines by owner; both land on Nagpur and are summed.'),
  ('NASHIK','Nashik',false,null),
  ('PUNJAB','Ludhiana',true,'The workbook says PUNJAB. The database has Ludhiana and Amritsar; the state-wide line was read as Ludhiana.'),
  ('Pune','Pune',false,null),
  ('RAJKOT','Rajkot',false,null),
  ('Raipur','Raipur',false,null),
  ('Solapur','Solapur',false,null),
  ('Surat','Surat',false,null),
  ('Tamilnadu + Chennai','Chennai',false,'One workbook line covers Chennai and the rest of Tamil Nadu; it lands on Chennai.'),
  ('VADODARA','Vadodara',false,null))
insert into public.business_import_alias (kind, source_text, target_id, is_guess, note)
select 'location', m.src, g.id, m.guess, m.note
  from m left join geo_node g on g.level = 'CITY' and lower(g.name) = lower(m.city)
on conflict (kind, source_text) do update
  set target_id = excluded.target_id, is_guess = excluded.is_guess, note = excluded.note;

-- ------------------------------------------------------ clients (37 names)
-- Matched on client.code, ignoring case, repeated spaces and the space the
-- workbook puts before a trailing "+". Thirty-six match outright; the sole
-- survivor of that rule is "BOB Car Loan +", which is "BOB CAR LOAN+" here.

insert into public.business_import_alias (kind, source_text, target_id, is_guess, note)
select 'client', d.v, c.id, false, null
  from stg.bl_dim d
  left join client c
    on upper(replace(regexp_replace(trim(c.code), '\s+', ' ', 'g'), ' +', '+'))
     = upper(replace(regexp_replace(trim(d.v ), '\s+', ' ', 'g'), ' +', '+'))
 where d.kind = 'client'
on conflict (kind, source_text) do update
  set target_id = excluded.target_id, is_guess = excluded.is_guess, note = excluded.note;

-- ------------------------------------------------------- people (21 names)
-- Eighteen match on full_name exactly. Two match on nothing but are plainly
-- the same person and are recorded as guesses. One is not in this database.

insert into public.business_import_alias (kind, source_text, target_id, is_guess, note)
select 'person', d.v, p.id, false, null
  from stg.bl_dim d
  left join person p
    on p.superseded_by is null
   and lower(regexp_replace(trim(p.full_name), '\s+', ' ', 'g'))
     = lower(regexp_replace(trim(d.v),         '\s+', ' ', 'g'))
 where d.kind in ('mgr','handler')
on conflict (kind, source_text) do update
  set target_id = excluded.target_id, is_guess = excluded.is_guess, note = excluded.note;

update public.business_import_alias a
   set target_id = p.id, is_guess = true,
       note = 'The workbook says "Yash Desai"; this database holds the same person under the login-shaped name "yash.desai" (' || p.employee_no || ', Operations). Matched on that.'
  from person p
 where a.kind = 'person' and a.source_text = 'Yash Desai'
   and a.target_id is null
   and p.full_name = 'yash.desai' and p.superseded_by is null;

update public.business_import_alias a
   set target_id = p.id, is_guess = true,
       note = 'The workbook says "Shiva Kumar"; this database holds "Shivakumar V" (' || p.employee_no || ', Operations), who covers Bengaluru and Chennai -- the two places the workbook gives Shiva Kumar. Matched on that.'
  from person p
 where a.kind = 'person' and a.source_text = 'Shiva Kumar'
   and a.target_id is null
   and p.full_name = 'Shivakumar V' and p.superseded_by is null;

-- ------------------------------------------------ the questions, out loud

insert into public.migration_review (entity_type, entity_ref, question, context)
select 'geo_node', 'business-import:' || a.source_text,
       'The monthly business workbook says "' || a.source_text || '". Is ' ||
         (select g.name from geo_node g where g.id = a.target_id) || ' the right place for it?',
       a.note
  from public.business_import_alias a
 where a.kind = 'location' and a.is_guess
   and not exists (select 1 from migration_review r
                    where r.entity_ref = 'business-import:' || a.source_text);

insert into public.migration_review (entity_type, entity_ref, question, context)
select 'person', 'business-import:' || a.source_text,
       'The monthly business workbook says "' || a.source_text || '". Is that ' ||
         coalesce((select p.full_name from person p where p.id = a.target_id), 'somebody this database does not have') || '?',
       coalesce(a.note,
         'No person in this database is called that, and nothing is close enough to guess from. '
         || 'Their rows load with no owner, so the money is counted and the credit is not.')
  from public.business_import_alias a
 where a.kind = 'person' and (a.is_guess or a.target_id is null)
   and not exists (select 1 from migration_review r
                    where r.entity_ref = 'business-import:' || a.source_text);

-- ----------------------------------------------------------- the loader

create or replace function public.business_import_run()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_in    int;
  v_out   int;
  v_mtd   bigint;
  v_rev   numeric;
  v_noown int;
begin
  if to_regclass('stg.bl_fact') is null then
    return jsonb_build_object('loaded', 0, 'note', 'no staging table');
  end if;

  create temp table _bi on commit drop as
  select to_char(dd.v::date, 'YYYY-MM')::bpchar                    as period,
         max(dd.v::date)                                           as business_date,
         cl.target_id                                              as client_id,
         lo.target_id                                              as geo_node_id,
         -- the owner of the larger half keeps a merged row; a row whose owner
         -- this database does not have never displaces one whose owner it does
         (array_agg(pe.target_id
                    order by (pe.target_id is null), f.revenue desc, f.mtd desc))[1] as owner_id,
         sum(f.mtd)::int                                           as mtd,
         sum(f.revenue)::numeric(14,2)                             as revenue,
         'Full_Data.xlsx: ' || string_agg(distinct dl.v || ' / ' || dc.v, '; ' order by dl.v || ' / ' || dc.v) as source_ref
    from stg.bl_fact f
    join stg.bl_dim  dd on dd.kind = 'date'   and dd.n = f.d
    join stg.bl_dim  dl on dl.kind = 'loc'    and dl.n = f.loc
    join stg.bl_dim  dc on dc.kind = 'client' and dc.n = f.cl
    join business_import_alias lo on lo.kind = 'location' and lo.source_text = dl.v
    join business_import_alias cl on cl.kind = 'client'   and cl.source_text = dc.v
    left join stg.bl_own o on o.loc = f.loc and o.cl = f.cl
    left join stg.bl_dim dm on dm.kind = 'mgr' and dm.n = o.mgr
    left join business_import_alias pe on pe.kind = 'person' and pe.source_text = dm.v
   where lo.target_id is not null and cl.target_id is not null
   group by 1, 3, 4;

  select count(*) into v_in  from stg.bl_fact;
  select count(*), sum(mtd), sum(revenue), count(*) filter (where owner_id is null)
    into v_out, v_mtd, v_rev, v_noown from _bi;

  insert into business_record
        (period, business_date, client_id, geo_node_id, owner_id, mtd, revenue, source_ref)
  select period, business_date, client_id, geo_node_id, owner_id, mtd, revenue, source_ref
    from _bi
      on conflict (period, client_id, geo_node_id) do update
     set business_date = excluded.business_date,
         owner_id      = excluded.owner_id,
         mtd           = excluded.mtd,
         revenue       = excluded.revenue,
         source_ref    = excluded.source_ref,
         updated_at    = now();

  return jsonb_build_object(
    'rows_in',        v_in,
    'rows_written',   v_out,
    'mtd',            v_mtd,
    'revenue',        v_rev,
    'without_owner',  v_noown);
end $fn$;

comment on function public.business_import_run() is
  'Resolves stg.bl_fact into business_record through business_import_alias. '
  'Idempotent: a period/client/place already there is overwritten, not doubled. '
  'Rows whose place or client the alias table cannot name are left out and '
  'counted, so a silent shortfall is not possible.';

-- ------------------------------------------------------------- run it

do $do$
declare
  r jsonb;
  v_mtd bigint; v_rev numeric; v_rows int; v_src int;
begin
  r := business_import_run();
  raise notice '211: %', r::text;

  select count(*) into v_src from stg.bl_fact;
  if v_src = 0 then
    raise notice '211: staging is empty -- the alias table and the loader are in place, nothing to load.';
    return;
  end if;

  -- the money on the way in must be the money on the way out
  select count(*), sum(mtd), sum(revenue) into v_rows, v_mtd, v_rev
    from business_record where source_ref like 'Full_Data.xlsx:%';

  if (r->>'mtd')::bigint <> (select sum(mtd) from stg.bl_fact) then
    raise exception '211: MTD does not tally: % written, % staged',
      r->>'mtd', (select sum(mtd) from stg.bl_fact);
  end if;
  if (r->>'revenue')::numeric <> (select sum(revenue) from stg.bl_fact) then
    raise exception '211: revenue does not tally: % written, % staged',
      r->>'revenue', (select sum(revenue) from stg.bl_fact);
  end if;
  if v_rows <> (r->>'rows_written')::int then
    raise exception '211: % rows written but % present', r->>'rows_written', v_rows;
  end if;
  if (r->>'rows_in')::int <> 4202 then
    raise exception '211: expected 4202 staged rows, found %', r->>'rows_in';
  end if;

  raise notice '211: % rows, MTD %, revenue %, % with no owner',
    v_rows, v_mtd, v_rev, r->>'without_owner';
end $do$;
