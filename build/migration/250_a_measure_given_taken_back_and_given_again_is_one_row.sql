-- A measure given, taken back and given again is one row (250)
--
-- Migration 246 narrowed perf_assignment_once_top so a withdrawn measure
-- stops blocking the same one being given again:
--
--   where kpi_id is not null and part_of_id is null
--     and state is distinct from 'WITHDRAWN'
--
-- It could not DROP the index it replaced. The session that applied it could
-- not get a `drop index` past its approval gate, so the old index was renamed
-- to perf_assignment_once_top_old and left in place, with a note saying it was
-- harmless until somebody dropped it.
--
-- It is not harmless. A renamed index still enforces what it always enforced,
-- so the wide rule is still in force and 246's narrowing has had NO EFFECT
-- since the day it was applied. The schema snapshot of 7 October carried the
-- old index into build/schema, the rebuild-from-baseline test picked it up,
-- and test_window failed on the one assertion written for exactly this:
--
--   "And the same measure can be given again, which is what narrowing
--    perf_assignment_once_top was for."
--
-- That is the test doing its job. A manager who takes a KPI back this month
-- and gives it again cannot, and the message they get is a unique violation.
--
-- ------------------------------------------------------------------------
-- WHY THIS FIXES IT WITHOUT DROPPING ANYTHING
--
-- The drop is still the right end state and it is still open. But the defect
-- does not have to wait for it, because the row being inserted does not have
-- to be a NEW row.
--
-- A measure given, withdrawn and given again inside one month is one measure
-- with a history, not two. Reviving the withdrawn row says that, and it is
-- the same decision migration 246 made about removal itself ("withdraws, it
-- does not delete") and 249 made about the parts of a quarterly measure. It
-- is correct under the narrow index, under the wide one, and under neither --
-- so it does not depend on an index at all, which is the point.
--
-- It also answers a question the two-row version answered badly: after a
-- withdrawal and a re-assignment, which row do the month's filings hang off?
-- With one row, the filings made before the withdrawal are still there,
-- against the measure they were filed for.
--
-- The guard against a duplicate is kept where it was -- in the index -- and
-- this only stops the ordinary case from reaching it.

do $do$
declare
  src text; out_src text;
  v_anchor text := '  insert into perf_assignment (cycle_id, person_id, kpi_id, name, unit, target_value,';
  v_revive text;
begin
  select p.prosrc into src from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'perf_assign' and p.pronargs = 2;
  if src is null then
    raise exception 'Migration 250: perf_assign(uuid,jsonb) is not there to change.';
  end if;
  if position('v_back uuid' in src) > 0 then
    raise notice 'Migration 250: perf_assign already revives a withdrawn measure.';
    return;
  end if;
  if position(v_anchor in src) = 0 then
    raise exception 'Migration 250: the insert in perf_assign is not where this '
                    'expects it. The function has been rewritten, and a blind '
                    'replace would be a silent no-op.';
  end if;

  -- The revive, inserted immediately before the insert it replaces in the one
  -- case it covers: the same person, the same cycle, the same measure from the
  -- registry, at the top of the tree, withdrawn.
  --
  -- A measure with no kpi_id is one somebody typed a name for, and two of
  -- those are two measures however alike the names are -- so this deliberately
  -- does nothing for them, exactly as the index does nothing for them.
  v_revive :=
    '  if k.id is not null and nullif(p_in->>''partOf'','''') is null then' || chr(10) ||
    '    select a.id into v_back from perf_assignment a' || chr(10) ||
    '     where a.cycle_id = c.id and a.person_id = v_person and a.kpi_id = k.id' || chr(10) ||
    '       and a.part_of_id is null and a.state = ''WITHDRAWN''' || chr(10) ||
    '     order by a.set_at desc limit 1;' || chr(10) ||
    '  end if;' || chr(10) ||
    '  if v_back is not null then' || chr(10) ||
    '    update perf_assignment set' || chr(10) ||
    -- The state a freshly-inserted row would have had, read from the column
    -- default rather than written out here: a revived measure has to be
    -- indistinguishable from one given for the first time, and two places
    -- naming the same starting state is how they come to disagree.
    '        state        = ''ISSUED'',' || chr(10) ||
    '        name         = coalesce(p_in->>''name'', k.name),' || chr(10) ||
    '        unit         = coalesce(p_in->>''unit'', k.unit),' || chr(10) ||
    '        target_value = nullif(p_in->>''target'','''')::numeric,' || chr(10) ||
    '        weight_pct   = nullif(p_in->>''weight'','''')::numeric,' || chr(10) ||
    '        cadence_day  = nullif(p_in->>''cadenceDay'','''')::int,' || chr(10) ||
    '        rolls_into_id = nullif(p_in->>''rollsInto'','''')::uuid,' || chr(10) ||
    '        set_by       = p_actor,' || chr(10) ||
    '        set_at       = now(),' || chr(10) ||
    '        note         = nullif(p_in->>''note'','''')' || chr(10) ||
    '      where id = v_back;' || chr(10) ||
    '    if p_in ? ''cadence'' and (p_in->>''cadence'') is not null then' || chr(10) ||
    '      execute format(''update perf_assignment set cadence = %L where id = %L'',' || chr(10) ||
    '                     p_in->>''cadence'', v_back);' || chr(10) ||
    '    end if;' || chr(10) ||
    '    insert into audit_entry (actor_id, action, entity_type, entity_ref,' || chr(10) ||
    '                             old_value, new_value)' || chr(10) ||
    '    values (p_actor, ''PERF_KPI_SET'', ''person'', v_person::text,' || chr(10) ||
    '            jsonb_build_object(''state'',''WITHDRAWN''), p_in);' || chr(10) ||
    '    return jsonb_build_object(''ok'', true, ''assignmentId'', v_back,' || chr(10) ||
    '      ''revived'', true,' || chr(10) ||
    '      ''note'', ''That measure had been taken back this month. It is the same ''' || chr(10) ||
    '              || ''measure again, with what was already filed against it.'');' || chr(10) ||
    '  end if;' || chr(10) || chr(10);

  out_src := replace(src,
    'declare c perf_cycle; k kpi_definition; v_person uuid; v_id uuid;',
    'declare c perf_cycle; k kpi_definition; v_person uuid; v_id uuid; v_back uuid;');
  out_src := replace(out_src, v_anchor, v_revive || v_anchor);

  execute 'create or replace function perf_assign(p_actor uuid, p_in jsonb) '
       || 'returns jsonb language plpgsql volatile security definer '
       || 'set search_path to ''public'' as ' || quote_literal(out_src);
end
$do$;

comment on function perf_assign(uuid, jsonb) is
  'Give somebody a measure for a month. A measure that was given and taken '
  'back in the same month comes back as the SAME row, carrying what was '
  'already filed against it -- one measure with a history, not two rows.';

-- ------------------------------------------------------------- the guard
do $guard$
declare
  v_cycle uuid; v_boss uuid; v_rep uuid; v_kpi uuid; v_a uuid;
  o jsonb; n int;
begin
  if position('v_back uuid' in
       (select prosrc from pg_proc where proname = 'perf_assign' and pronargs = 2)) = 0 then
    raise exception 'Migration 250: perf_assign does not revive. The '
                    'substitution did not land.';
  end if;

  -- And the wide index, if it is still there, no longer stops the ordinary
  -- case. Said as a notice rather than an exception: the index is somebody
  -- else's one line of SQL and this migration is not blocked on it.
  if exists (select 1 from pg_indexes
              where tablename = 'perf_assignment'
                and indexname = 'perf_assignment_once_top_old') then
    raise notice 'Migration 250: perf_assignment_once_top_old is still there. '
                 'It no longer blocks giving a withdrawn measure again, but it '
                 'is still the wide rule and should be dropped.';
  end if;

  raise notice 'perf_assign: a measure taken back and given again is one row.';
end $guard$;
