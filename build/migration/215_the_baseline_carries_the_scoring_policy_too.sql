-- 215 · The baseline carries the scoring policy too
--
-- 214 put the Constitution's 75/25 split into pms_weighting, and the test
-- suite immediately failed on a database rebuilt from build/schema alone:
--
--     FAIL  the company-wide weighting is not 75/25
--
-- which is right, and is the same hole 207 closed for the access policy. The
-- baseline carries schema. A split that lives in a row does not survive a
-- rebuild, so a freshly built Crux computes no monthly score for anybody and
-- says nothing about why. "The engine is built and nothing is configured" is
-- the failure this whole week has been about; it should not be reintroduced by
-- the one file that is supposed to make the repository sufficient.
--
-- So schema_snapshot_policy() carries the scoring policy as well:
--
--   pms_weighting   the KPI/Attributes split -- 0.75 and 0.25, Annexure F
--   pms_curve_band  the five appraisal bands and their shares
--   pms_impact      what an escalation, warning or appreciation moves
--
-- All three are configuration in the same sense as who may open what: no
-- person's name is in them, they are the same in every environment, and with
-- them empty the tool is silently inert rather than obviously broken.
--
-- One thing had to change to allow it. pms_weighting can be scoped to a chair
-- or a person, and records who set it, so its rows CAN carry a reference to
-- somebody. The baseline seeds no people and no chairs, so such a row would
-- fail to load. Rather than hand-picking columns, the generator now nulls any
-- column that is a foreign key to person or chair. That keeps the promise the
-- file's own header makes -- nobody's name is in it -- and it means a
-- company-wide policy travels while a policy somebody set for one team does
-- not. That is the correct line: a rule for everybody is policy, a rule for
-- one named team is data about that team.

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
  nullcols text[];
  vals text;
  out text := '';
begin
  -- The five access tables from 204, then the three scoring tables, each in
  -- the order it must load: a level before the screens that reference it.
  foreach t in array array['access_level', 'access_level_screen',
                           'access_screen_parent', 'access_chair_level',
                           'access_department_level',
                           'pms_weighting', 'pms_curve_band', 'pms_impact']
  loop
    select array_agg(a.attname::text order by a.attnum)
      into cols
      from pg_attribute a
      join pg_class c on c.oid = a.attrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = t
       and a.attnum > 0 and not a.attisdropped;

    if cols is null then
      out := out || '-- ' || t || ' is not in this database' || E'\n\n';
      continue;
    end if;

    -- Columns pointing at somebody or at a chair. The baseline seeds neither,
    -- so a row carrying one could not load; and a policy that names a person
    -- is not policy.
    select coalesce(array_agg(distinct a.attname::text), '{}')
      into nullcols
      from pg_constraint k
      join pg_class c on c.oid = k.conrelid
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = k.conrelid and a.attnum = any (k.conkey)
     where n.nspname = 'public' and c.relname = t and k.contype = 'f'
       and k.confrelid in ('public.person'::regclass, 'public.chair'::regclass);

    -- Each value read BY NAME, in the order the column list was built, so the
    -- heading and the value cannot come apart. Every literal is quoted by the
    -- database, so a note containing an apostrophe cannot end it early.
    execute format(
      $q$select string_agg('  (' || (
             select string_agg(
                      case when k.colname = any (%L::text[]) then 'null'
                           when z.v is null then 'null'
                           else quote_literal(z.v) end,
                      ', ' order by k.ord)
               from unnest(%L::text[]) with ordinality as k(colname, ord),
                    lateral (select to_jsonb(x) ->> k.colname as v) z
           ) || ')', E',\n' order by x::text)
           from public.%I x$q$,
      nullcols, cols, t)
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
  'The rows the baseline carries: who may open what (204), and how a month is '
  'scored (the Constitution''s 75/25 split, the appraisal bands, and what a '
  'raisable moves). Any column that is a foreign key to person or chair is '
  'emitted as null -- the baseline seeds neither, and a policy that names '
  'somebody is not policy.';

-- ---------------------------------------------------------------- checks

do $do$
declare v_out text; v_lines int;
begin
  v_out := schema_snapshot_policy();

  if v_out not like '%insert into public.pms_weighting%' then
    raise exception '215: the weighting did not reach the policy file';
  end if;
  if v_out not like '%insert into public.pms_curve_band%' then
    raise exception '215: the appraisal bands did not reach the policy file';
  end if;
  if v_out not like '%insert into public.access_level_screen%' then
    raise exception '215: the access policy fell out of the policy file';
  end if;

  -- the administrator's uuid must not be in it
  if v_out like '%' || (select coalesce(set_by::text, 'no-set-by')
                          from pms_weighting where scope_all
                         order by effective_from desc limit 1) || '%' then
    raise exception '215: a person''s id reached a file that promises not to carry one';
  end if;

  select count(*) into v_lines from regexp_split_to_table(v_out, E'\n') x where x like 'insert into%';
  raise notice '215: the policy file now carries % inserts', v_lines;
end $do$;
