-- 207 · The baseline carries the policy
--
-- build/schema is the shape of the database and deliberately holds no data.
-- That was right until migration 204, which put the access policy into five
-- tables. Their SHAPE is in the baseline; their ROWS are not, so a database
-- rebuilt from this repository comes up with access_level_screen empty, and
-- an empty access_level_screen means access_may_open() answers false for
-- everybody and every screen. The rebuild produces a tool nobody can open.
--
-- build/test/run.sh found it the first time it rebuilt after 204:
--
--   FAIL  174 disagreement(s) out of 262 checked
--   FAIL  a Branch Manager is at branch level -- saw: exec
--
-- The policy is not business data. Nobody's name is in it, it is the same in
-- every environment, and the code will not run without it -- which is the test
-- of whether something belongs in a baseline. So the snapshot carries it, and
-- carries only it: not people, not clients, not one row of anybody's work.

create or replace function public.schema_snapshot_policy()
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $fn$
declare
  t text;
  cols text;
  vals text;
  out text := '';
begin
  -- The five tables migration 204 created, in the order they must load: a
  -- level before the screens that reference it.
  foreach t in array array['access_level', 'access_level_screen',
                           'access_screen_parent', 'access_chair_level',
                           'access_department_level']
  loop
    select string_agg(quote_ident(a.attname), ', ' order by a.attnum)
      into cols
      from pg_attribute a
      join pg_class c on c.oid = a.attrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = t
       and a.attnum > 0 and not a.attisdropped;

    -- One VALUES row per table row, every value quoted by the database
    -- rather than by string-building, so a note containing an apostrophe
    -- cannot end the literal early.
    execute format(
      $q$select string_agg('  (' || (
             select string_agg(
               case when v is null then 'null' else quote_literal(v) end, ', ')
               from jsonb_each_text(to_jsonb(x)) as e(k, v)) || ')',
             E',\n' order by x::text)
           from public.%I x$q$, t)
      into vals;

    if vals is null then
      out := out || '-- ' || t || ' is empty' || E'\n\n';
    else
      out := out
        || 'insert into public.' || quote_ident(t) || ' (' || cols || ') values' || E'\n'
        || vals || E'\non conflict do nothing;' || E'\n\n';
    end if;
  end loop;

  return out;
end $fn$;

comment on function public.schema_snapshot_policy() is
  'The access policy as INSERT statements. The only rows the baseline carries, '
  'because they are the only rows without which the schema does not work.';

-- jsonb_each_text does not promise key order, and a VALUES row has to line up
-- with its column list or the insert is silently wrong in the worst possible
-- way -- level and screen swapped, say. So the column list is taken from the
-- same source in the same order: to_jsonb() of a row orders its keys by
-- attnum, which is exactly what the cols query above orders by.
do $do$
declare n int; bad text;
begin
  select count(*) into n from access_level_screen;
  if n < 90 then
    raise exception 'access_level_screen holds % rows; 204 seeds 92', n;
  end if;
  select string_agg(k, ',') into bad
    from (select k from jsonb_object_keys(to_jsonb((select x from access_level_screen x limit 1))) as k) q;
  if bad <> 'level,screen' then
    raise exception 'to_jsonb key order is % and not the column order', bad;
  end if;
end $do$;

-- ------------------------------------------------- add it to the snapshot
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
    ('09_staging.sql',      'the staging schema', 'stg is where the legacy spreadsheets landed. No part of the running tool reads it, but two of the migration audit views do -- tables, constraints, indexes and the five text normalisers they call.', public.schema_snapshot_stg()),
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
    ('90_cron.sql',         'scheduled jobs',    'Requires pg_cron. Each line is the schedule as it stands in the live project.', public.schema_snapshot_cron()),
    ('95_access_policy.sql','the access policy', 'The ONLY rows the baseline carries. Who may open what is configuration, not data: nobody''s name is in it, it is the same in every environment, and with these tables empty access_may_open() answers false for everybody and the rebuilt tool opens for nobody.', public.schema_snapshot_policy())
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
