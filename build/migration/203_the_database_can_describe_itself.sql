-- 203 · The database can describe itself
--
-- Forty-five of the 111 .sql files in this directory are prose with no
-- executable SQL in them at all. They read as though they built something,
-- and they did — but the SQL that did it went to the project through an API
-- call and was never written back. The consequence is not theoretical.
-- Three separate pieces of work in this project have had to recover a
-- function definition from the running database because it existed in no
-- file anywhere: next_ref, working_hours_after, and person_merge_side, which
-- turned out not to exist at all and had been called by a function that was
-- applied without it.
--
-- Measured against the live project — build/schema.sql, both patches and
-- every migration file counted together — the repository could create 120 of
-- the 155 tables and 110 of the 311 function names. Two hundred and one
-- functions, better than half a megabyte of them, existed in no file here.
-- That is not a backup. It is a story about a backup.
--
-- This migration adds the only thing that fixes it permanently: a read-only
-- function that asks the catalogues what the database is and returns the DDL
-- as text, one entry per file. .github/workflows/snapshot-schema.yml calls
-- it and commits the answer to build/schema, so the shape of the database is
-- written down by the database and not retyped by anybody.
--
-- It returns no row of anybody's data. Only the shape.
--
-- On the grant at the end: execute is given to anon so the publish runner
-- can call it with the publishable key, the same key the tool itself uses.
-- What comes back is exactly what is then committed to a public repository,
-- so the grant exposes nothing the commit does not. If this repository is
-- ever made private, revoke it and give the workflow a service-role key
-- instead — build/schema/REGENERATE.md has the two lines that change.

-- ------------------------------------------------ the catalogue, in pieces
create or replace function public.schema_snapshot_part(p_part text)
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $fn$
declare v text;
begin
  if p_part = 'types' then
    select coalesce(string_agg(s, E'\n' order by o, nm), '') into v from (
      select 1 as o, t.typname as nm,
             'create type public.' || quote_ident(t.typname) || ' as enum (' ||
             (select string_agg(quote_literal(e.enumlabel), ', ' order by e.enumsortorder)
                from pg_enum e where e.enumtypid = t.oid) || ');' as s
        from pg_type t join pg_namespace n on n.oid = t.typnamespace
       where n.nspname = 'public' and t.typtype = 'e'
       order by t.oid) q;

  elsif p_part = 'tables' then
    with cols as (
      select c.relname as tbl, a.attnum,
             quote_ident(a.attname) || ' ' || format_type(a.atttypid, a.atttypmod) ||
             -- pg_attrdef holds a generated column's expression in the same
             -- place it holds a default, and writing one out as the other
             -- produces a table Postgres refuses: "cannot use column
             -- reference in DEFAULT expression". There is exactly one such
             -- column, plb_month_score.monthly_score, and it is the whole
             -- reason this case exists.
             case
               when a.attgenerated = 's'
                 then ' generated always as (' || pg_get_expr(ad.adbin, ad.adrelid) || ') stored'
               else coalesce(' default ' || pg_get_expr(ad.adbin, ad.adrelid), '')
             end ||
             case when a.attnotnull then ' not null' else '' end as col
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
        left join pg_attrdef ad on ad.adrelid = c.oid and ad.adnum = a.attnum
       where n.nspname = 'public' and c.relkind = 'r')
    select coalesce(string_agg(t, E'\n\n' order by tbl), '') into v
      from (select tbl, 'create table if not exists public.' || quote_ident(tbl) || ' (' || E'\n  ' ||
                   string_agg(col, E',\n  ' order by attnum) || E'\n);' as t
              from cols group by tbl) q;

  elsif p_part in ('keys','checks','fkeys') then
    select coalesce(string_agg('alter table public.' || quote_ident(t.relname) ||
             ' add constraint ' || quote_ident(c.conname) || ' ' ||
             pg_get_constraintdef(c.oid) || ';',
             E'\n' order by (case c.contype when 'p' then 1 when 'u' then 2 else 3 end), t.relname, c.conname), '')
      into v
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
     where n.nspname = 'public'
       and c.contype = any (case p_part when 'keys' then array['p','u'] when 'checks' then array['c'] else array['f'] end);

  elsif p_part = 'indexes' then
    select coalesce(string_agg(def || ';', E'\n' order by iname), '') into v from (
      select i.relname as iname, pg_get_indexdef(i.oid) as def
        from pg_class i
        join pg_namespace n on n.oid = i.relnamespace
        join pg_index x on x.indexrelid = i.oid
       where n.nspname = 'public' and i.relkind = 'i'
         and not exists (select 1 from pg_constraint c where c.conindid = i.oid)) q;

  elsif p_part = 'triggers' then
    select coalesce(string_agg(pg_get_triggerdef(g.oid) || ';', E'\n' order by c.relname, g.tgname), '')
      into v
      from pg_trigger g
      join pg_class c on c.oid = g.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and not g.tgisinternal;

  elsif p_part = 'views' then
    select coalesce(string_agg(s, E'\n\n' order by nsp, nm), '') into v from (
      select n.nspname as nsp, c.relname as nm,
             'create or replace view ' || quote_ident(n.nspname) || '.' || quote_ident(c.relname) ||
             ' as' || E'\n' || pg_get_viewdef(c.oid, true) as s
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public','seam') and c.relkind = 'v') q;

  elsif p_part = 'comments' then
    select coalesce(string_agg(s, E'\n' order by s), '') into v from (
      select 'comment on table public.' || quote_ident(c.relname) || ' is ' ||
             quote_literal(d.description) || ';' as s
        from pg_description d
        join pg_class c on c.oid = d.objoid and d.objsubid = 0
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r'
      union all
      select 'comment on column public.' || quote_ident(c.relname) || '.' ||
             quote_ident(a.attname) || ' is ' || quote_literal(d.description) || ';'
        from pg_description d
        join pg_class c on c.oid = d.objoid and d.objsubid > 0
        join pg_attribute a on a.attrelid = c.oid and a.attnum = d.objsubid
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind in ('r','v')
      union all
      select 'comment on function public.' || quote_ident(p.proname) || '(' ||
             pg_get_function_identity_arguments(p.oid) || ') is ' ||
             quote_literal(d.description) || ';'
        from pg_description d
        join pg_proc p on p.oid = d.objoid and d.objsubid = 0
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public') q;

  else
    raise exception 'unknown part %', p_part;
  end if;

  return coalesce(v, '');
end $fn$;

-- The sequences are generated separately and before the tables, because a
-- column default that calls nextval on a sequence that does not exist yet is
-- a table that will not load. Which column owns which sequence is a separate
-- part, and a separate file, because ALTER SEQUENCE ... OWNED BY names a
-- table and so cannot be said until the tables are there. Without it a
-- dropped table leaves its sequence behind.
--
-- Row level security gets its own file for a reason worth writing down: it
-- is on for 150 of the 155 tables and 121 of those carry no policy at all.
-- A reader who does not know the design will read that as an oversight. It
-- is the design. The tool reaches the database through SECURITY DEFINER
-- functions and the service role, so RLS on with no policy is a table that
-- is closed to anon and to authenticated, which is what it should be.
create or replace function public.schema_snapshot_part2(p_part text)
returns text
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select case p_part

    when 'sequences' then coalesce((
      select string_agg('create sequence if not exists public.' || quote_ident(c.relname) || ';',
                        E'\n' order by c.relname)
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'S'), '')

    when 'sequence_owners' then coalesce((
      select string_agg('alter sequence public.' || quote_ident(c.relname) || ' owned by public.' ||
                        quote_ident(t.relname) || '.' || quote_ident(a.attname) || ';',
                        E'\n' order by c.relname)
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        join pg_depend d on d.objid = c.oid and d.deptype = 'a' and d.classid = 'pg_class'::regclass
        join pg_class t on t.oid = d.refobjid
        join pg_attribute a on a.attrelid = t.oid and a.attnum = d.refobjsubid
       where n.nspname = 'public' and c.relkind = 'S'), '')

    when 'rls' then coalesce((
      select string_agg(s, E'\n' order by o, s) from (
        select 1 as o, 'alter table public.' || quote_ident(c.relname) ||
               ' enable row level security;' as s
          from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
        union all
        select 2, 'create policy ' || quote_ident(p.policyname) ||
               ' on public.' || quote_ident(p.tablename) ||
               ' as ' || p.permissive ||
               ' for ' || p.cmd ||
               ' to ' || array_to_string(p.roles, ', ') ||
               coalesce(' using (' || p.qual || ')', '') ||
               coalesce(' with check (' || p.with_check || ')', '') || ';'
          from pg_policies p
         where p.schemaname = 'public') q), '')

    when 'grants' then coalesce((
      select string_agg(s, E'\n' order by s) from (
        select 'grant ' || string_agg(g.privilege_type, ', ' order by g.privilege_type) ||
               ' on public.' || quote_ident(g.table_name) ||
               ' to ' || quote_ident(g.grantee) || ';' as s
          from information_schema.role_table_grants g
         where g.table_schema = 'public'
           and g.grantee in ('anon','authenticated','service_role')
         group by g.table_name, g.grantee
        union all
        select 'grant execute on function public.' || quote_ident(p.proname) || '(' ||
               pg_get_function_identity_arguments(p.oid) || ') to ' || quote_ident(r.rolname) || ';'
          from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
          cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          join pg_roles r on r.oid = a.grantee
         where n.nspname = 'public' and p.prokind in ('f','p')
           and a.privilege_type = 'EXECUTE'
           and r.rolname in ('anon','authenticated','service_role')
           and p.proname not like 'schema\_snapshot%'
        union all
        select 'grant ' || string_agg(distinct a.privilege_type, ', ') ||
               ' on sequence public.' || quote_ident(c.relname) ||
               ' to ' || quote_ident(r.rolname) || ';'
          from pg_class c
          join pg_namespace n on n.oid = c.relnamespace
          cross join lateral aclexplode(coalesce(c.relacl, acldefault('S', c.relowner))) a
          join pg_roles r on r.oid = a.grantee
         where n.nspname = 'public' and c.relkind = 'S'
           and r.rolname in ('anon','authenticated','service_role')
         group by c.relname, r.rolname) q), '')

    else null end
$fn$;

-- The functions are the bulk of it: 314 of them, better than half a megabyte
-- of definition. They come back in four slices only so that no single file
-- is unreadable. They are ordered by name and not by dependency, so the
-- loader turns check_function_bodies off — which is correct here, because a
-- definition that came out of a working database does not need to be
-- re-proved against a half-built one.
create or replace function public.schema_snapshot_funcs(p_slice int, p_of int)
returns text
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select coalesce(string_agg(def || ';', E'\n\n' order by proname, args, oid), '')
    from (
      select p.oid, p.proname,
             pg_get_function_identity_arguments(p.oid) as args,
             pg_get_functiondef(p.oid) as def,
             ntile(p_of) over (order by p.proname,
                               pg_get_function_identity_arguments(p.oid), p.oid) as slice
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.prokind in ('f','p')
         and p.proname not like 'schema\_snapshot%'
    ) q
   where slice = p_slice
$fn$;

create or replace function public.schema_snapshot_cron()
returns text
language sql
stable
security definer
set search_path to 'public', 'cron'
as $fn$
  select coalesce(string_agg(
    'select cron.schedule(' || quote_literal(jobname) || ', ' ||
    quote_literal(schedule) || ', ' || quote_literal(command) || ');',
    E'\n' order by jobname), '')
  from cron.job
$fn$;

-- stg is where the legacy spreadsheets landed. It is not part of the running
-- tool, it carries no constraints and nothing in the application reads it --
-- but migration_coverage_shape and migration_unaccounted do, and a rebuild
-- without it is a rebuild two views short. That is exactly the kind of thing
-- a hand-written baseline forgets and a generated one cannot.
create or replace function public.schema_snapshot_stg()
returns text
language sql
stable
security definer
set search_path to 'public'
as $fn$
  with cols as (
    select c.relname as tbl, a.attnum,
           quote_ident(a.attname) || ' ' || format_type(a.atttypid, a.atttypmod) ||
           case
             when a.attgenerated = 's'
               then ' generated always as (' || pg_get_expr(ad.adbin, ad.adrelid) || ') stored'
             else coalesce(' default ' || pg_get_expr(ad.adbin, ad.adrelid), '')
           end ||
           case when a.attnotnull then ' not null' else '' end as col
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
      left join pg_attrdef ad on ad.adrelid = c.oid and ad.adnum = a.attnum
     where n.nspname = 'stg' and c.relkind = 'r')
  select 'create schema if not exists stg;' || E'\n\n' ||
         coalesce(string_agg(t, E'\n\n' order by tbl), '')
    from (select tbl, 'create table if not exists stg.' || quote_ident(tbl) || ' (' || E'\n  ' ||
                 string_agg(col, E',\n  ' order by attnum) || E'\n);' as t
            from cols group by tbl) q
$fn$;

-- ------------------------------------------------------- the whole picture
create or replace function public.schema_snapshot()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $fn$
  with b(f, title, note, body) as (values
    ('05_types.sql',        'types',            'Every enum the schema uses. Nothing here has a table behind it, so this file loads first and alone.', public.schema_snapshot_part('types')),
    ('08_sequences.sql',    'sequences',        'Created before the tables, because a column default that calls nextval on a sequence that does not exist is a table that will not load. Which column owns which sequence is in 11_sequence_owners.sql, because that cannot be said until the tables are there.', public.schema_snapshot_part2('sequences')),
    ('09_staging.sql',      'the staging schema', 'stg is where the legacy spreadsheets landed. It is not part of the running tool and carries no constraints, but two of the migration audit views read it, so a database without it is a database two views short.', public.schema_snapshot_stg()),
    ('10_tables.sql',       'tables',           'Columns and defaults only. Keys, checks, foreign keys and indexes each have their own file, so no table in here depends on another and load order is free.', public.schema_snapshot_part('tables')),
    ('11_sequence_owners.sql', 'sequence ownership', 'The other half of 08. Without it a dropped table leaves its sequence behind.', public.schema_snapshot_part2('sequence_owners')),
    ('20_keys.sql',         'primary keys and unique constraints', 'Added before the foreign keys, so every unique a foreign key needs is already in place.', public.schema_snapshot_part('keys')),
    ('21_checks.sql',       'check constraints', 'These come after the functions: person_mobile_shape calls person_mobile(), and a CHECK is resolved when the ALTER TABLE runs.', public.schema_snapshot_part('checks')),
    ('22_foreign_keys.sql', 'foreign keys',      'Last of the constraints, so the order the tables loaded in never mattered.', public.schema_snapshot_part('fkeys')),
    ('30_indexes.sql',      'indexes',           'The indexes no constraint owns. Several are the real uniqueness rules of the system: "only one open X", "only one live Y" live in the partial unique indexes here, and cannot be written as table constraints.', public.schema_snapshot_part('indexes')),
    ('40_functions_1.sql',  'functions, part 1 of 4', 'Ordered by name, not by dependency. Load with check_function_bodies off.', public.schema_snapshot_funcs(1,4)),
    ('40_functions_2.sql',  'functions, part 2 of 4', 'Ordered by name, not by dependency. Load with check_function_bodies off.', public.schema_snapshot_funcs(2,4)),
    ('40_functions_3.sql',  'functions, part 3 of 4', 'Ordered by name, not by dependency. Load with check_function_bodies off.', public.schema_snapshot_funcs(3,4)),
    ('40_functions_4.sql',  'functions, part 4 of 4', 'Ordered by name, not by dependency. Load with check_function_bodies off.', public.schema_snapshot_funcs(4,4)),
    ('50_views.sql',        'views',             'public and seam. The seam views are the prototype''s read-only window on the real tables.', public.schema_snapshot_part('views')),
    ('60_triggers.sql',     'triggers',          'The functions they call are in the 40 files.', public.schema_snapshot_part('triggers')),
    ('70_rls.sql',          'row level security', 'Row level security is on for nearly every table, and most of them carry no policy at all. That is deliberate: the tool reaches the database through SECURITY DEFINER functions and the service role, so a table with RLS on and no policy is closed to anon and to authenticated, which is what it should be.', public.schema_snapshot_part2('rls')),
    ('75_grants.sql',       'grants',            'What anon, authenticated and service_role may touch.', public.schema_snapshot_part2('grants')),
    ('80_comments.sql',     'comments',          'What the database says about itself.', public.schema_snapshot_part('comments')),
    ('90_cron.sql',         'scheduled jobs',    'Requires pg_cron. Each line is the schedule as it stands in the live project.', public.schema_snapshot_cron())
  )
  select jsonb_object_agg(f,
    '-- =====================================================================' || E'\n' ||
    '-- Crux baseline | ' || f || ' | ' || title || E'\n' ||
    '--' || E'\n' ||
    '-- GENERATED from the live project. Do not hand-edit: change the' || E'\n' ||
    '-- database with a migration, then regenerate. build/schema/REGENERATE.md' || E'\n' ||
    '-- says how, and build/migration/README.md says why this exists.' || E'\n' ||
    '--' || E'\n' ||
    '-- ' || note || E'\n' ||
    '-- =====================================================================' || E'\n\n' ||
    body || E'\n')
  from b
$fn$;

revoke all on function public.schema_snapshot() from public;
grant execute on function public.schema_snapshot() to anon;
