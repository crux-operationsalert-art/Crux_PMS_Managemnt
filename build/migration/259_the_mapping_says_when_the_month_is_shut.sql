-- The mapping says when the month is shut, rather than offering a Save that
-- every write behind it refuses
--
-- perf_mapping answers maySet = perf_may_set(actor, person): "is this your
-- report". That is the right question for who may READ the controls, and the
-- wrong one for whether a save will land. perf_kpis_set does its work through
-- perf_assign, perf_assign_edit and perf_assign_remove, and all three answer
-- window_closed once current_date passes the cycle's assign_closes, for
-- anybody but an administrator. So from the day after the window shut --
-- 16 October this month, after 256 moved it to the 15th -- a manager opening
-- Performance mapping would be handed weight boxes, target boxes, Edit,
-- Remove, + and Save, type a whole scorecard, and be refused at the end.
-- That is migration 242's defect again: a control that is always refused is
-- worse than no control.
--
-- The old person panel (pfMeasureAdmin) knew this and hid its controls on
-- the clock. The mapping panel that replaced it asked only maySet, and the
-- check that would have caught it -- window_check.mjs -- was still pointed
-- at the deleted renderer, and had been throwing instead of failing since.
--
-- The rule is answered here, once, with the SAME predicate the three writers
-- use, so the screen cannot guess differently from them:
--   mayEdit = maySet and (assign_closes is null
--                         or current_date <= assign_closes
--                         or the actor is an ADMIN)
-- plus assignCloses, so the screen can say until when -- or since when.
--
-- maySet is left exactly as it is: it still decides whether the person is
-- told "these are your own measures" or "setting them is their manager's".
--
-- Written by substitution over the live body, as 258 was, so the parts
-- nobody is changing cannot drift while being retyped.
do $do$
declare src text; out_src text;
  v_anchor text := 'return t || jsonb_build_object(' || chr(10) || '    ''quarter'', v_q,';
begin
  select prosrc into src from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'perf_mapping' and p.pronargs = 3;
  if src is null then
    raise exception 'Migration 259: perf_mapping is not there to change.';
  end if;
  if position('''mayEdit''' in src) > 0 then
    raise notice 'Migration 259: perf_mapping already answers mayEdit.';
    return;
  end if;
  if position(v_anchor in src) = 0 then
    raise exception 'Migration 259: the return in perf_mapping is not where '
                    'this expects it, so a blind replace would be a silent no-op.';
  end if;

  out_src := replace(src, v_anchor,
    v_anchor || chr(10) ||
    '    -- 259: the same predicate perf_assign, perf_assign_edit and' || chr(10) ||
    '    -- perf_assign_remove refuse on. Offer only what will be accepted.' || chr(10) ||
    '    ''mayEdit'', coalesce((t->>''maySet'')::boolean, false)' || chr(10) ||
    '               and (c.assign_closes is null' || chr(10) ||
    '                    or current_date <= c.assign_closes' || chr(10) ||
    '                    or exists (select 1 from person' || chr(10) ||
    '                                where id = p_actor and app_role = ''ADMIN'')),' || chr(10) ||
    '    ''assignCloses'', c.assign_closes,');

  execute format(
    'create or replace function public.perf_mapping(p_actor uuid, p_person uuid, p_cycle uuid) '
    'returns jsonb language plpgsql stable security definer '
    'set search_path to ''public'' as %L', out_src);
end
$do$;

-- --------------------------------------------------------------- the proof
-- Run against whatever pair the database has, inside a subtransaction that
-- is rolled back: shut the window, ask, reopen, ask.
do $guard$
declare v_boss uuid; v_rep uuid; v_cycle uuid; o jsonb; v_close date;
begin
  select a.person_id, p.manager_id, a.cycle_id
    into v_rep, v_boss, v_cycle
    from perf_assignment a join person p on p.id = a.person_id
    join person b on b.id = p.manager_id
   where a.part_of_id is null and a.state <> 'WITHDRAWN'
     and b.app_role <> 'ADMIN'
     and coalesce((perf_tree_for(p.manager_id, a.person_id, a.cycle_id)->>'maySet')::boolean, false)
   limit 1;
  if v_rep is null then
    raise notice 'Migration 259: no manager-and-report pair to check against here.';
    return;
  end if;

  select assign_closes into v_close from perf_cycle where id = v_cycle;
  begin
    update perf_cycle set assign_closes = current_date - 1 where id = v_cycle;
    o := perf_mapping(v_boss, v_rep, v_cycle);
    if not coalesce((o->>'maySet')::boolean, false) then
      raise exception 'Migration 259: maySet changed, and it must not have.';
    end if;
    if coalesce((o->>'mayEdit')::boolean, true) then
      raise exception 'Migration 259: a shut month still offers the controls: %',
        o->'mayEdit';
    end if;
    update perf_cycle set assign_closes = current_date + 1 where id = v_cycle;
    o := perf_mapping(v_boss, v_rep, v_cycle);
    if not coalesce((o->>'mayEdit')::boolean, false) then
      raise exception 'Migration 259: an open month does not offer the controls.';
    end if;
    raise exception using errcode = 'P0001', message = '259-rollback';
  exception when others then
    if sqlerrm <> '259-rollback' then raise; end if;
  end;
  if (select assign_closes from perf_cycle where id = v_cycle) is distinct from v_close then
    raise exception 'Migration 259: the probe did not put the window back.';
  end if;
  raise notice 'perf_mapping: mayEdit follows the window, maySet does not.';
end $guard$;
