-- =====================================================================
-- 225 · The baseline carries the roll-up map too
--
-- Migration 223 put the measure-family map into perf_rollup_map, and
-- build/test/test_flow.sql failed on the next clean rebuild with
--
--     FAIL  EX1 climbs into nothing
--
-- for the reason migration 215 already wrote down once: the baseline in
-- build/schema carries SCHEMA, and the map is DATA. A rebuilt database
-- gets the table and none of its rows, so nothing climbs and a test that
-- passes against the live project fails against the repository -- which
-- is the repository being right and the baseline being incomplete.
--
-- 215 solved exactly this for the Constitution's 75/25 split by having
-- schema_snapshot_policy() emit the rows as inserts. The roll-up map
-- belongs in the same list and for the same reason: it is policy. It says
-- which measure a measure is part of, it was written down deliberately
-- with a sentence justifying every row, and a database that rebuilds
-- without it is a database where the pyramid is flat.
--
-- Nothing new is invented here. One name is added to an array.
-- =====================================================================

do $$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'schema_snapshot_policy';

  if v_def is null then
    -- The snapshot functions are deliberately left out of their own
    -- snapshot -- a generator that generates itself is a loop -- so a
    -- database rebuilt from build/schema alone has none of them. That is
    -- correct, and this migration has nothing to do there.
    raise notice '225: no schema_snapshot_policy here. This is a rebuilt '
                 'database, which never carries the snapshot generator.';
    return;
  end if;

  if v_def like '%perf_rollup_map%' then
    raise notice '225: schema_snapshot_policy already carries perf_rollup_map.';
    return;
  end if;

  -- The array the function walks, with one more name on the end. It goes
  -- last because it references nothing: the map is text to text, and a
  -- family code is not a row in another table.
  v_new := replace(v_def,
    $q$'pms_weighting', 'pms_curve_band', 'pms_impact']$q$,
    $q$'pms_weighting', 'pms_curve_band', 'pms_impact',
                           'perf_rollup_map']$q$);

  if v_new = v_def then
    raise exception 'migration 225: the table list in schema_snapshot_policy is '
                    'not where 215 left it. Look before changing it.';
  end if;

  execute v_new;
end $$;

-- And the same shape of check 215 makes on its own output, so a baseline
-- that silently stops carrying the map fails the regeneration rather than
-- the next test run.
do $$
declare v_out text;
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'schema_snapshot_policy') then
    return;
  end if;
  v_out := schema_snapshot_policy();
  if v_out not like '%insert into public.perf_rollup_map%' then
    raise exception 'migration 225: the policy file does not carry the roll-up map';
  end if;
  if v_out not like '%EX1%' then
    raise exception 'migration 225: the policy file carries the map but not its rows';
  end if;
end $$;
