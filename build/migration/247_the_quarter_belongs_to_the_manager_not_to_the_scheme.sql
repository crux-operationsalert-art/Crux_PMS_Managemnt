-- The quarter belongs to the manager, not to the scheme (247)
--
-- "as a manager I am still not able to change the KPIs for quaterly score
--  card and add sub KPIs ... as well as Monthly targets"
-- "I can still update and change my own targets, which is wrong. Only my One
--  up should be able to do that and no one else. Not even my Manager's
--  manager, only my manager."
--
-- ONE DEFECT, TWO SYMPTOMS, and it is migration 242's again. The quarterly
-- side asked `maySetUp` -- who RUNS the scheme: HR, Business Excellence and
-- an administrator -- where it should have asked who MANAGES the person
-- whose sheet it is. So:
--
--   * a manager with a team saw no quarterly card at all, and
--   * an administrator saw every sheet INCLUDING THEIR OWN and could set
--     their own target.
--
-- plb_quarter has carried the right answer all along. Every sheet comes back
-- with `maySet` = perf_rel(you, them) in ('manage','admin'), and perf_rel
-- answers 'self' for your own sheet before it answers anything else, and
-- 'watch' for your manager's manager. That is exactly the rule the owner
-- asked for, already written, already tested, already used by the monthly
-- side -- and the quarterly side was not reading it.
--
-- WHERE THE RULE NOW LIVES. In the database, with the writes, because the
-- route-level `maySetUp` test is what the screen was mirroring and a rule
-- enforced in a route is a rule exactly one caller obeys. plb_actual_set had
-- NO actor check whatsoever; it was safe only because the route refused
-- first.
--
-- WHAT IS LEFT TO THE SCHEME. Locking, certifying and publishing stay HR's,
-- Business Excellence's and the administrator's. Those are acts of the
-- scheme over the company, not of a manager over a person, and the
-- Constitution says so. What moves is the three things the Constitution
-- already calls the reporting manager's: the target, the monthly split, and
-- the month's score.

-- --------------------------------------------- said once, read in four places
create or replace function plb_runs_scheme(p_actor uuid)
returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select exists (
    select 1 from person p
     where p.id = p_actor
       and p.employment_status = 'ACTIVE' and p.superseded_by is null
       and (p.app_role = 'ADMIN'
            or coalesce(p.department,'') in ('Human Resources','Business Excellence')));
$function$;

comment on function plb_runs_scheme(uuid) is
  'Who runs the PLB scheme: an administrator, Human Resources, Business '
  'Excellence. Running it is issuing, locking, certifying and publishing. It '
  'is NOT the same question as who may set one named person''s numbers -- '
  'that is perf_may_set, and migration 218 drew the line.';

-- ------------------------------------------------- the three that move
-- Each guard is inserted at an anchor in the function's OWN live source
-- rather than by retyping the body, for the reason migration 239 learned:
-- a function retyped from memory loses a clause nobody notices.
do $gate$
declare
  r record; v_src text; v_done text[] := '{}';
  -- proname, anchor, the guard that goes in front of it
  v_each jsonb := jsonb_build_array(
    jsonb_build_object(
      'fn','plb_sheet_issue',
      'anchor','if p_actor = p_person and not p_default then',
      'guard', 'if not (perf_may_set(p_actor, p_person) or plb_runs_scheme(p_actor)) then'
            || E'\n    return jsonb_build_object(''error'',''not_permitted'','
            || E'\n      ''reason'',''A goal sheet is issued by the person''''s own reporting manager, '
            || 'or by HR, Business Excellence or an administrator. Not by their manager''''s manager, '
            || 'and never by themselves.'');'
            || E'\n  end if;' || E'\n  '),
    jsonb_build_object(
      'fn','plb_score_month',
      'anchor','if s.person_id = p_actor then',
      'guard', 'if not (perf_may_set(p_actor, s.person_id) or plb_runs_scheme(p_actor)) then'
            || E'\n    return jsonb_build_object(''error'',''not_permitted'','
            || E'\n      ''reason'',''A month is scored by the person''''s own reporting manager, '
            || 'or by HR, Business Excellence or an administrator.'');'
            || E'\n  end if;' || E'\n  '),
    jsonb_build_object(
      'fn','plb_actual_set',
      'anchor','select data_frozen_at into v_frozen from plb_result where sheet_id = p_sheet;',
      'guard', 'if not exists (select 1 from plb_goal_sheet s2 where s2.id = p_sheet'
            || E'\n                  and (perf_may_set(p_actor, s2.person_id) or plb_runs_scheme(p_actor))) then'
            || E'\n    return jsonb_build_object(''error'',''not_permitted'','
            || E'\n      ''reason'',''An actual is recorded by the person''''s own reporting manager, '
            || 'or by HR, Business Excellence or an administrator.'');'
            || E'\n  end if;' || E'\n  ')
  );
  e jsonb;
begin
  for e in select * from jsonb_array_elements(v_each) loop
    select p.prosrc, p.provolatile, p.prosecdef, l.lanname,
           pg_get_function_arguments(p.oid) as args,
           pg_get_function_result(p.oid) as ret
      into r
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      join pg_language l on l.oid = p.prolang
     where n.nspname = 'public' and p.proname = e->>'fn';

    if r.prosrc is null then
      raise exception 'Migration 247: % is not there.', e->>'fn';
    end if;
    if position('plb_runs_scheme' in r.prosrc) > 0 then
      raise notice '% already asks who manages them', e->>'fn';
      continue;
    end if;
    if position((e->>'anchor') in r.prosrc) = 0 then
      raise exception 'Migration 247: % does not read the way this expected, so '
                      'the guard has nowhere to go.', e->>'fn';
    end if;

    v_src := replace(r.prosrc, e->>'anchor', (e->>'guard') || (e->>'anchor'));
    execute format(
      'create or replace function %I(%s) returns %s language %s %s %s '
      'set search_path to ''public'' as %L',
      e->>'fn', r.args, r.ret, r.lanname,
      case r.provolatile when 's' then 'stable' when 'i' then 'immutable' else '' end,
      case when r.prosecdef then 'security definer' else 'security invoker' end,
      v_src);
    v_done := v_done || (e->>'fn');
  end loop;
  raise notice 'guarded: %', coalesce(array_to_string(v_done, ', '), 'nothing, all already done');
end $gate$;

-- ------------------------------------------------------------- the guard
do $check$
declare
  p_boss uuid; p_rep uuid; p_above uuid; p_hr uuid; p_other uuid;
  v_sheet uuid; v_chair uuid; v_kpi uuid; o jsonb;
begin
  insert into person (full_name, work_email, app_role)
    values ('Q247 Above','q247.above@example.invalid','MANAGER') returning id into p_above;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('Q247 Boss','q247.boss@example.invalid','MANAGER', p_above) returning id into p_boss;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('Q247 Rep','q247.rep@example.invalid','VIEWER', p_boss) returning id into p_rep;
  insert into person (full_name, work_email, app_role, department)
    values ('Q247 HR','q247.hr@example.invalid','MANAGER','Human Resources') returning id into p_hr;
  insert into person (full_name, work_email, app_role)
    values ('Q247 Other','q247.other@example.invalid','VIEWER') returning id into p_other;

  insert into chair (code, title, level) values ('Q247-CH','Q247 Chair','BRANCH')
    returning id into v_chair;
  insert into kpi_definition (name, unit, active, position, chair_id)
    values ('Q247 measure','COUNT', true, 1, v_chair) returning id into v_kpi;
  insert into chair_holder (chair_id, person_id, is_primary) values (v_chair, p_rep, true);

  -- The manager may issue. This is the whole ask.
  o := plb_sheet_issue(p_boss, p_rep, date_trunc('quarter', current_date)::date,
         100000, '[]'::jsonb, false);
  if o->>'error' is not null then
    raise exception 'Migration 247: the reporting manager could not issue a goal '
                    'sheet: %', o;
  end if;
  v_sheet := (o->>'sheetId')::uuid;
  if v_sheet is null then
    select id into v_sheet from plb_goal_sheet where person_id = p_rep
     order by created_at desc limit 1;
  end if;

  -- The manager's manager may not.
  if plb_sheet_issue(p_above, p_rep, date_trunc('quarter', current_date)::date,
       100000, '[]'::jsonb, false)->>'error' is distinct from 'not_permitted' then
    raise exception 'Migration 247: the manager''s manager issued a sheet. The '
                    'owner asked for only the one up.';
  end if;

  -- A stranger may not.
  if plb_sheet_issue(p_other, p_rep, date_trunc('quarter', current_date)::date,
       100000, '[]'::jsonb, false)->>'error' is distinct from 'not_permitted' then
    raise exception 'Migration 247: a stranger issued a goal sheet.';
  end if;

  -- Nobody issues their own, administrators included. perf_rel answers
  -- 'self' before it answers 'admin'.
  if plb_sheet_issue(p_rep, p_rep, date_trunc('quarter', current_date)::date,
       100000, '[]'::jsonb, false)->>'error' is null then
    raise exception 'Migration 247: somebody issued their own goal sheet.';
  end if;

  -- HR still may, because running the scheme is theirs.
  if plb_sheet_issue(p_hr, p_rep, (date_trunc('quarter', current_date) - interval '3 months')::date,
       100000, '[]'::jsonb, false)->>'error' is not null then
    raise exception 'Migration 247: HR can no longer issue a sheet. The rule is '
                    'too narrow.';
  end if;

  if v_sheet is not null then
    -- The actual, which had no actor check at all before this.
    if plb_actual_set(p_other, v_sheet, v_kpi, 10)->>'error' is distinct from 'not_permitted' then
      raise exception 'Migration 247: a stranger recorded an actual.';
    end if;
    if plb_actual_set(p_rep, v_sheet, v_kpi, 10)->>'error' is distinct from 'not_permitted' then
      raise exception 'Migration 247: a person recorded their own actual.';
    end if;
    if plb_actual_set(p_boss, v_sheet, v_kpi, 10)->>'error' is not null then
      raise exception 'Migration 247: the reporting manager could not record an '
                      'actual: %', plb_actual_set(p_boss, v_sheet, v_kpi, 10);
    end if;

    -- And the month's score.
    if plb_score_month(p_above, v_sheet, date_trunc('month', current_date)::date, 8, 2, null)
       ->>'error' is distinct from 'not_permitted' then
      raise exception 'Migration 247: the manager''s manager scored a month.';
    end if;
  end if;

  raise notice 'the quarter answers who manages them, not who runs the scheme';
  raise exception using errcode = 'P0001', message = 'Q247 undo';
exception
  when sqlstate 'P0001' then
    if sqlerrm <> 'Q247 undo' then raise; end if;
    raise notice 'migration 247 checked itself against real rows and rolled them back';
end $check$;
