-- 208 · A value goes under its own column
--
-- 207 built each VALUES row with jsonb_each_text(to_jsonb(x)), which does not
-- return keys in column order. jsonb orders its keys by LENGTH and then
-- bytewise, so for access_level (level, label, note) it produced:
--
--   insert into public.access_level (level, label, note) values
--     ('Nothing is hidden from it and it can change everything...', 'Administrator', 'admin'),
--
-- -- note, label and level, under the headings level, label and note. A
-- rebuild from that baseline would have come up with a level called
-- "Nothing is hidden from it..." and every access check answering false.
--
-- The guard in 207 was too weak to catch it: it checked the key order of ONE
-- table, access_level_screen, whose two columns happen to be 'level' and
-- 'screen' -- five and six characters, so length order and column order agree
-- by coincidence. A check that passes by coincidence is not a check.
--
-- This builds each row by walking the column list in attnum order and reading
-- each value by name, so a value can only appear under its own heading, and
-- asserts the first row of the first table literally.

create or replace function public.schema_snapshot_policy()
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $fn$
declare
  t text;
  cols text[];
  vals text;
  out text := '';
begin
  -- The five tables migration 204 created, in the order they must load: a
  -- level before the screens that reference it.
  foreach t in array array['access_level', 'access_level_screen',
                           'access_screen_parent', 'access_chair_level',
                           'access_department_level']
  loop
    select array_agg(a.attname::text order by a.attnum)
      into cols
      from pg_attribute a
      join pg_class c on c.oid = a.attrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = t
       and a.attnum > 0 and not a.attisdropped;

    -- Each value read BY NAME, in the order the column list was built, so the
    -- heading and the value cannot come apart. Every literal is quoted by the
    -- database, so a note containing an apostrophe cannot end it early.
    execute format(
      $q$select string_agg('  (' || (
             select string_agg(
                      case when z.v is null then 'null' else quote_literal(z.v) end,
                      ', ' order by k.ord)
               from unnest(%L::text[]) with ordinality as k(colname, ord),
                    lateral (select to_jsonb(x) ->> k.colname as v) z
           ) || ')', E',\n' order by x::text)
           from public.%I x$q$, cols, t)
      into vals;

    if vals is null then
      out := out || '-- ' || t || ' is empty' || E'\n\n';
    else
      out := out
        || 'insert into public.' || quote_ident(t) || ' ('
        || (select string_agg(quote_ident(c), ', ') from unnest(cols) c)
        || ') values' || E'\n'
        || vals || E'\non conflict do nothing;' || E'\n\n';
    end if;
  end loop;

  return out;
end $fn$;

comment on function public.schema_snapshot_policy() is
  'The access policy as INSERT statements, each value under its own column. '
  'The only rows the baseline carries, because they are the only rows without '
  'which the schema does not work.';

-- The check 207 should have had: not "are the keys in some order" but "is this
-- particular value where it belongs".
do $do$
declare s text;
begin
  s := schema_snapshot_policy();

  if position('insert into public.access_level (level, label, note) values' in s) = 0 then
    raise exception 'the access_level insert does not name its columns as expected';
  end if;
  if position(E'values\n  (''admin'', ''Administrator''' in s) = 0 then
    raise exception 'the first access_level row is not (admin, Administrator, ...): the '
                    'values are not in column order';
  end if;
  if position('(''analytics'', ''cases'')' in s) = 0 then
    raise exception 'access_level_screen is not emitting (level, screen) pairs in order';
  end if;
  if position('(''Branch Manager'', ''branch'')' in s) = 0 then
    raise exception 'access_chair_level is not emitting (chair_title, level) in order';
  end if;
  if position('(''rates'', ''reports'')' in s) = 0 then
    raise exception 'access_screen_parent is not emitting (screen, parent) in order';
  end if;
  if position('(''Human Resources'', ''hr'')' in s) = 0 then
    raise exception 'access_department_level is not emitting (department, level) in order';
  end if;

  raise notice '208: the policy snapshot is % bytes and every value is under its own column',
    length(s);
end $do$;
