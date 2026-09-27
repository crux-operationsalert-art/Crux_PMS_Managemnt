-- 209 · The comments leave out what the functions do
--
-- schema_snapshot_funcs() excludes the snapshot's own functions from the
-- baseline: a file that re-creates the thing generating it is a loop nobody
-- needs, and they are recorded in build/migration like every other migration.
--
-- The comments part did not have the same exclusion, so 80_comments.sql
-- carried COMMENT ON FUNCTION public.schema_snapshot_policy(), and a rebuild
-- stopped there:
--
--   ERROR:  function public.schema_snapshot_policy() does not exist
--
-- Two rules about the same objects that did not agree. Now they do, and the
-- assertion below says so rather than leaving it to the next rebuild.

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
      -- A comment on the snapshot's own functions would name something the
      -- baseline does not create, and the load stops there. Same exclusion as
      -- schema_snapshot_funcs(); the two rules are about the same objects and
      -- have to agree.
      select 'comment on function public.' || quote_ident(p.proname) || '(' ||
             pg_get_function_identity_arguments(p.oid) || ') is ' ||
             quote_literal(d.description) || ';'
        from pg_description d
        join pg_proc p on p.oid = d.objoid and d.objsubid = 0
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname not like 'schema\_snapshot%') q;

  else
    raise exception 'unknown part %', p_part;
  end if;

  return coalesce(v, '');
end $fn$;

-- Every function the comments name must be a function the baseline creates.
do $do$
declare v text;
begin
  select string_agg(m[1], ', ') into v
    from regexp_matches(schema_snapshot_part('comments'),
                        'comment on function public\.([a-z0-9_]+)\(', 'g') m
   where not exists (
     select 1 from regexp_matches(
       schema_snapshot_funcs(1,1), 'FUNCTION public\.([a-z0-9_]+)\(', 'g') f
      where f[1] = m[1]);
  if v is not null then
    raise exception 'the comments name functions the baseline does not create: %', v;
  end if;
  raise notice '209: every function the comments name is one the baseline creates';
end $do$;
