-- A sub-KPI can be renamed, and answers to one name everywhere
--
-- "Edit KPI or Sub KPI, remove KPI or Sub KPI isnt working"
--
-- Three things were wrong and this file is the only one of them that needed
-- the database. The other two were in the screen: the weight and target
-- boxes called pfRender() on every keystroke, which rewrites the whole view
-- and destroys the input being typed into, so the caret went after one
-- character; and taking a KPI off dropped the weights below a hundred,
-- which greyed Save with nothing beside it to say why.
--
-- This one: a sub-KPI is an ordinary perf_assignment with part_of_id set,
-- and it carries its name in TWO columns -- `name`, which everything that
-- is not this screen reads, and `split_label`, which is what a part is
-- shown as. perf_assign_edit only ever wrote `name`. So renaming a sub-KPI
-- changed one of the two, and the measure began answering to a different
-- name depending on which screen you were looking at.
--
-- Written by substitution over the live body rather than by pasting
-- perf_assign_edit again, so the parts nobody is changing cannot drift
-- while being retyped.
do $do$
declare src text; out_src text;
  v_anchor text := 'update perf_assignment set' || chr(10) || '    name        = v_name,';
begin
  select prosrc into src from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'perf_assign_edit' and p.pronargs = 2;
  if src is null then
    raise exception 'Migration 258: perf_assign_edit is not there to change.';
  end if;
  if position('split_label =' in src) > 0
     and position('<> ''OTHER''' in src) > 0 then
    raise notice 'Migration 258: perf_assign_edit already keeps the two names together.';
    return;
  end if;
  if position(v_anchor in src) = 0 then
    raise exception 'Migration 258: the update in perf_assign_edit is not where '
                    'this expects it, so a blind replace would be a silent no-op.';
  end if;

  -- FIRST: a named sub-KPI is not a client's share, and the refusal that
  -- stops one being renamed was written for the other kind.
  --
  -- perf_assign_edit refused to rename ANY row with a part_of_id, in these
  -- words: "That row is one client's share of a measure, not a measure."
  -- That is exactly right for a CLIENT, BRANCH or PLACE split, where the
  -- share takes its identity from the thing it is a share OF -- renaming
  -- Bank A's share to something else leaves a measure whose shares are
  -- called something unrelated.
  --
  -- It is wrong for split_kind OTHER, which is the slot a named sub-KPI
  -- uses: there the label IS the sub-KPI, somebody typed it, and a typo in
  -- it is unfixable while this refusal applies to it too.
  out_src := replace(src,
    'if a.part_of_id is not null and (p_in ? ''name'') then',
    'if a.part_of_id is not null and (p_in ? ''name'')' || chr(10) ||
    '     and coalesce(a.split_kind, '''') <> ''OTHER'' then');
  if out_src = src then
    raise exception 'Migration 258: the split refusal in perf_assign_edit is '
                    'not where this expects it.';
  end if;
  src := out_src;

  -- THEN: both names move together. Only where the row IS a part, and only
  -- where a name was actually sent -- a measure that is not a part has no
  -- split_label and must not acquire one.
  out_src := replace(src, v_anchor,
    'update perf_assignment set' || chr(10) ||
    '    name        = v_name,' || chr(10) ||
    '    split_label = case when part_of_id is not null' || chr(10) ||
    '                        and nullif(btrim(coalesce(p_in->>''name'','''')),'''') is not null' || chr(10) ||
    '                       then v_name else split_label end,');

  execute 'create or replace function perf_assign_edit(p_actor uuid, p_in jsonb) '
       || 'returns jsonb language plpgsql volatile security definer '
       || 'set search_path to ''public'' as ' || quote_literal(out_src);
end
$do$;

-- ------------------------------------------------------------- the guard
do $guard$
declare
  v_cycle uuid; v_boss uuid; v_rep uuid; v_par uuid; v_sub uuid; o jsonb;
  v_name text; v_split text;
begin
  select id into v_cycle from perf_cycle
   where period_start = date_trunc('month', current_date)::date and period_kind = 'MONTH';
  if v_cycle is null then
    raise notice 'Migration 258: no cycle this month to check against.';
    return;
  end if;

  select a.person_id, p.manager_id, a.id into v_rep, v_boss, v_par
    from perf_assignment a join person p on p.id = a.person_id
   where a.cycle_id = v_cycle and a.part_of_id is null and a.state <> 'WITHDRAWN'
     and p.manager_id is not null
   limit 1;
  if v_rep is null then
    raise notice 'Migration 258: nobody with a manager and a measure.';
    return;
  end if;

  -- A part, renamed, must move both names together.
  o := perf_assign(v_boss, jsonb_build_object(
         'cycleId', v_cycle, 'personId', v_rep, 'name','258 probe',
         'unit','COUNT', 'target', 1, 'partOf', v_par,
         'splitKind','OTHER', 'splitLabel','258 probe'));
  if o->>'error' is not null then
    raise notice 'Migration 258: could not make a probe part (%), so the rename '
                 'is unchecked here.', o->>'error';
    return;
  end if;
  select id into v_sub from perf_assignment
   where part_of_id = v_par and name = '258 probe';

  o := perf_assign_edit(v_boss, jsonb_build_object(
         'assignmentId', v_sub, 'name','258 renamed'));
  if o->>'error' is not null then
    raise exception 'Migration 258: a sub-KPI could not be renamed: %', o;
  end if;
  select name, split_label into v_name, v_split
    from perf_assignment where id = v_sub;
  if v_name is distinct from '258 renamed' or v_split is distinct from '258 renamed' then
    raise exception 'Migration 258: the two names disagree after a rename: '
                    'name=%, split_label=%', v_name, v_split;
  end if;

  perform perf_assign_remove(v_boss, v_sub);
  raise notice 'perf_assign_edit: a sub-KPI answers to one name everywhere.';
end $guard$;
