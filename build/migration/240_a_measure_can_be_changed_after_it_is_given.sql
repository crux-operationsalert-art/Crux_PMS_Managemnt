-- A measure can be changed after it is given (240)
--
-- "Not able to add and edit KPIs" and "I can still add my own KPIs and
-- targets" are the same hole seen from both sides, and neither sentence was
-- quite about what I first thought.
--
-- WHAT WAS ACTUALLY THERE. The database already refuses a person their own:
-- kpi_save, perf_assign and perf_target_set each check perf_may_set, which
-- is false for 'self' whoever you are, administrator included. The one
-- screen that offers "Add a KPI" and "Retire" is vPms, and vPms is not in
-- NAV or FAMILY -- so currentTab() bounces it to Today. It has been
-- unreachable, which is why nobody could add a KPI; and because nobody
-- could, the Performance screen's own assign form was the only way in, and
-- that form offers a dropdown of the chair's registry and nothing else.
--
-- So: a manager can give somebody a measure the registry already names, and
-- can do nothing else. They cannot name a new one, cannot correct a typo,
-- cannot change a weight they got wrong, and cannot take back a measure
-- given to the wrong person. Every one of those is an ordinary Tuesday.
--
-- This adds the two verbs that were missing. It does NOT widen who may do
-- them: both call perf_may_set, so it is the person's own manager or an
-- administrator -- and never themselves, which is the other half of the
-- complaint and was already true.
--
--   perf_assign_edit    change a measure already given: its name, unit,
--                       weight, cadence, and which of the setter's own
--                       measures it climbs into. NOT its target -- that is
--                       perf_target_set, which also runs the cascade, and
--                       two doors onto one number is how they disagree.
--
--   perf_assign_remove  take a measure back. If anything has been filed
--                       against it the row is NOT deleted: a figure a
--                       person filed is a thing that happened, and a score
--                       already given against it still refers to it. It is
--                       marked WITHDRAWN instead, which perf_value and the
--                       screens read as "no longer asked for".
--
-- The window matters. perf_assign refuses after assign_closes unless the
-- actor is an administrator; both of these say the same, in the same words,
-- for the same reason: a measure changed after people have started filing
-- against it changes what they were asked to do halfway through.

-- --------------------------------------------------------------- state
-- perf_assignment.state is constrained to DRAFT, ISSUED, ACKNOWLEDGED and
-- LOCKED. WITHDRAWN is a fifth, and the constraint is widened here rather
-- than dropped: a column whose values are listed is the reason a typo in a
-- state name is caught at the write and not three screens later.
--
-- The constraint is found by what it constrains rather than by its name,
-- because a name is a thing that gets changed.
do $state$
declare v_name text; v_def text;
begin
  select c.conname, pg_get_constraintdef(c.oid) into v_name, v_def
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
   where n.nspname = 'public' and t.relname = 'perf_assignment' and c.contype = 'c'
     and pg_get_constraintdef(c.oid) like '%state%'
   limit 1;

  if v_name is null then
    -- No constraint to widen. Add one, so the five states are listed
    -- somewhere rather than nowhere.
    alter table perf_assignment add constraint perf_assignment_state_check
      check (state = any (array['DRAFT','ISSUED','ACKNOWLEDGED','LOCKED','WITHDRAWN']));
    raise notice 'perf_assignment had no state constraint; added one naming five states';
  elsif position('WITHDRAWN' in v_def) > 0 then
    raise notice 'perf_assignment.state already allows WITHDRAWN';
  else
    -- The replacement is written out in full, so it must be checked that
    -- nothing is being dropped on the way. If a fifth state has been added
    -- since this was written, rewriting the list from memory would silently
    -- outlaw rows that already exist.
    if position('DRAFT' in v_def) = 0 or position('ISSUED' in v_def) = 0
       or position('ACKNOWLEDGED' in v_def) = 0 or position('LOCKED' in v_def) = 0
       or (select count(*) from regexp_matches(v_def, '''[A-Z_]+''', 'g')) <> 4 then
      raise exception 'Migration 240: perf_assignment.state is constrained to %, '
                      'which is not the four states this expected. Re-read it '
                      'and widen it by hand rather than letting this guess.', v_def;
    end if;
    execute format('alter table perf_assignment drop constraint %I', v_name);
    execute format('alter table perf_assignment add constraint %I '
                || 'check (state = any (array[''DRAFT'',''ISSUED'',''ACKNOWLEDGED'','
                || '''LOCKED'',''WITHDRAWN'']))', v_name);
    raise notice 'perf_assignment.state widened from % to five states', v_def;
  end if;
end $state$;

-- -------------------------------------------------------- the edit
create or replace function perf_assign_edit(p_actor uuid, p_in jsonb)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  a perf_assignment; c perf_cycle; v_was jsonb; v_name text; v_cadence text;
begin
  select * into a from perf_assignment where id = (p_in->>'assignmentId')::uuid;
  if a.id is null then return jsonb_build_object('error','no_such_assignment'); end if;

  if not perf_may_set(p_actor, a.person_id) then
    return jsonb_build_object('error','not_permitted',
      'reason','A measure is changed by the person''s own manager or by an '
            || 'administrator -- and never by themselves.');
  end if;

  select * into c from perf_cycle where id = a.cycle_id;
  if current_date > c.assign_closes
     and not exists (select 1 from person where id = p_actor and app_role = 'ADMIN') then
    return jsonb_build_object('error','window_closed',
      'reason','Measures for ' || c.period_start || ' had to be settled by '
            || c.assign_closes || '. An administrator can still change them, '
            || 'and it is recorded.');
  end if;

  -- A split is a share of its parent and takes its name from it. Renaming
  -- one leaves a measure whose shares are called something else.
  if a.part_of_id is not null and (p_in ? 'name') then
    return jsonb_build_object('error','is_a_split',
      'reason','That row is one client''s share of a measure, not a measure. '
            || 'Rename the measure it belongs to and every share follows.');
  end if;

  v_name := nullif(btrim(coalesce(p_in->>'name', a.name)), '');
  if v_name is null then
    return jsonb_build_object('error','no_name','reason','Give the measure a name.');
  end if;

  v_cadence := nullif(p_in->>'cadence','');
  if v_cadence is not null and v_cadence not in ('DAILY','WEEKLY','MONTHLY','QUARTERLY') then
    return jsonb_build_object('error','bad_cadence',
      'reason','A cadence is DAILY, WEEKLY, MONTHLY or QUARTERLY.');
  end if;

  -- A measure may only climb into one the SETTER holds, and never into
  -- itself. Without the second test a measure can be made its own parent,
  -- and perf_cascade then walks for ever.
  if p_in ? 'rollsInto' and nullif(p_in->>'rollsInto','') is not null then
    if (p_in->>'rollsInto')::uuid = a.id then
      return jsonb_build_object('error','rolls_into_itself',
        'reason','A measure cannot climb into itself.');
    end if;
    if not exists (select 1 from perf_assignment x
                    where x.id = (p_in->>'rollsInto')::uuid
                      and x.person_id = p_actor) then
      return jsonb_build_object('error','not_your_measure',
        'reason','A measure climbs into one of your own. Pick one of yours, '
              || 'or leave it unlinked.');
    end if;
  end if;

  v_was := jsonb_build_object('name', a.name, 'unit', a.unit,
             'weight', a.weight_pct, 'cadence', a.cadence,
             'cadenceDay', a.cadence_day, 'rollsInto', a.rolls_into_id,
             'note', a.note);

  update perf_assignment set
    name        = v_name,
    unit        = case when p_in ? 'unit' then nullif(btrim(coalesce(p_in->>'unit','')),'') else unit end,
    weight_pct  = case when p_in ? 'weight' then nullif(p_in->>'weight','')::numeric else weight_pct end,
    cadence_day = case when p_in ? 'cadenceDay' then nullif(p_in->>'cadenceDay','')::int else cadence_day end,
    note        = case when p_in ? 'note' then nullif(btrim(coalesce(p_in->>'note','')),'') else note end,
    rolls_into_id = case when p_in ? 'rollsInto' then nullif(p_in->>'rollsInto','')::uuid else rolls_into_id end
   where id = a.id;

  -- cadence is an enum, and a dynamic cast of a possibly-absent key inside
  -- the statement above would fail on the absent case. Done separately and
  -- only when asked for, exactly as perf_assign does it.
  if v_cadence is not null then
    execute format('update perf_assignment set cadence = %L where id = %L',
                   v_cadence, a.id);
  end if;

  -- The shares follow the name, so a split measure does not end up with its
  -- pieces called one thing and the whole called another.
  if p_in ? 'name' then
    update perf_assignment set name = v_name where part_of_id = a.id;
  end if;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, 'PERF_KPI_CHANGED', 'perf_assignment', a.id::text, v_was, p_in);

  return jsonb_build_object('ok', true, 'assignmentId', a.id, 'name', v_name,
    'note', 'Changed. The target is set separately, so it has not moved.');
end $function$;

-- ------------------------------------------------------------ the remove
create or replace function perf_assign_remove(p_actor uuid, p_assignment uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  a perf_assignment; c perf_cycle; n_filed int; n_kids int; n_split int;
begin
  select * into a from perf_assignment where id = p_assignment;
  if a.id is null then return jsonb_build_object('error','no_such_assignment'); end if;

  if not perf_may_set(p_actor, a.person_id) then
    return jsonb_build_object('error','not_permitted',
      'reason','A measure is taken back by the person''s own manager or by '
            || 'an administrator -- and never by themselves.');
  end if;

  select * into c from perf_cycle where id = a.cycle_id;
  if current_date > c.assign_closes
     and not exists (select 1 from person where id = p_actor and app_role = 'ADMIN') then
    return jsonb_build_object('error','window_closed',
      'reason','Measures for ' || c.period_start || ' had to be settled by '
            || c.assign_closes || '.');
  end if;

  -- Somebody else's measure climbs into this one. Removing it would leave
  -- their number with nowhere to go, so it is refused by name rather than
  -- cascaded into silently.
  select count(*) into n_kids from perf_assignment x
   where x.rolls_into_id = a.id and x.person_id <> a.person_id;
  if n_kids > 0 then
    return jsonb_build_object('error','feeds_this',
      'reason', n_kids || ' measure(s) below this one climb into it. Move or '
             || 'remove those first, or their numbers have nowhere to add up to.');
  end if;

  select count(*) into n_filed from perf_entry e
   where e.assignment_id = a.id
      or e.assignment_id in (select x.id from perf_assignment x where x.part_of_id = a.id);

  if n_filed > 0 then
    -- Not deleted. A figure somebody filed is a thing that happened, and a
    -- month already scored against this measure still refers to it.
    update perf_assignment set state = 'WITHDRAWN'
     where id = a.id or part_of_id = a.id;
    insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
    values (p_actor, 'PERF_KPI_WITHDRAWN', 'perf_assignment', a.id::text,
            jsonb_build_object('name', a.name, 'state', a.state),
            jsonb_build_object('state','WITHDRAWN','filings', n_filed));
    return jsonb_build_object('ok', true, 'withdrawn', true, 'filings', n_filed,
      'note', n_filed || ' figure(s) have been filed against this, so it is '
           || 'withdrawn rather than deleted: it stops being asked for, and '
           || 'what was already filed still reads back.');
  end if;

  select count(*) into n_split from perf_assignment where part_of_id = a.id;
  delete from perf_assignment where part_of_id = a.id;
  delete from perf_assignment where id = a.id;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, 'PERF_KPI_REMOVED', 'perf_assignment', a.id::text,
          jsonb_build_object('name', a.name, 'unit', a.unit,
                             'target', a.target_value, 'person', a.person_id,
                             'splits', n_split),
          null);

  return jsonb_build_object('ok', true, 'withdrawn', false,
    'note', 'Removed. Nothing had been filed against it'
         || case when n_split > 0 then ', and its ' || n_split || ' client share(s) went with it' else '' end
         || '.');
end $function$;

-- Both are called through the service with the caller's own id, exactly as
-- perf_assign is. Neither is for anon.
revoke execute on function perf_assign_edit(uuid, jsonb) from public, anon, authenticated;
revoke execute on function perf_assign_remove(uuid, uuid) from public, anon, authenticated;

-- ------------------------------------- what WITHDRAWN has to mean elsewhere
-- A new state is worth nothing if the things that read assignments do not
-- know it. perf_due already asks for state in ('ISSUED','ACKNOWLEDGED'), so
-- a withdrawn measure stops being asked for the moment it is withdrawn.
--
-- perf_tree and perf_kpi_score do not filter on state at all, and they are
-- the screen and the score. Without this, "remove" would take a measure off
-- nobody's to-do list and leave it both on the page and in the weighted
-- mean that decides the person's bonus -- which is worse than not offering
-- remove at all.
--
-- One substitution, over whichever functions carry the scan, for the reason
-- given in 239: retyping a function is how a clause goes missing.
do $withdrawn$
declare
  r record; v_src text; v_n int := 0;
  v_old constant text := 'a.person_id = p_person and a.cycle_id = p_cycle';
  v_new constant text := 'a.person_id = p_person and a.cycle_id = p_cycle'
                      || E' and a.state <> ''WITHDRAWN''';
begin
  for r in
    select p.proname,
           pg_get_function_identity_arguments(p.oid) as args,
           pg_get_function_result(p.oid) as ret,
           p.prosrc, p.provolatile, p.prosecdef, l.lanname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      join pg_language l on l.oid = p.prolang
     where n.nspname = 'public'
       and l.lanname in ('sql','plpgsql')
       and position(v_old in p.prosrc) > 0
       and position('WITHDRAWN' in p.prosrc) = 0
  loop
    v_src := replace(r.prosrc, v_old, v_new);
    execute format(
      'create or replace function %I(%s) returns %s language %s %s %s '
      'set search_path to ''public'' as %L',
      r.proname, r.args, r.ret, r.lanname,
      case r.provolatile when 's' then 'stable'
                         when 'i' then 'immutable'
                         else '' end,
      case when r.prosecdef then 'security definer' else 'security invoker' end,
      v_src);
    v_n := v_n + 1;
    raise notice '  % no longer counts a withdrawn measure', r.proname;
  end loop;
  raise notice '% function(s) taught what WITHDRAWN means', v_n;
end $withdrawn$;

-- ---------------------------------------- the screen needs one more field
-- perf_node returns everything about a measure except which of the setter's
-- own measures it climbs into, so the edit form could show the list and
-- never show which one is already chosen. One key, added the same way.
do $rollsinto$
declare v_src text;
  v_old constant text := E'''weight'', a.weight_pct, ''state'', a.state,';
  v_new constant text := E'''weight'', a.weight_pct, ''state'', a.state,'
                      || E'\n    ''rollsInto'', a.rolls_into_id,';
begin
  select prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'perf_node';
  if v_src is null then
    raise exception 'Migration 240: perf_node is not there';
  elsif position('rollsInto' in v_src) > 0 then
    raise notice 'perf_node already returns rollsInto';
  elsif position(v_old in v_src) = 0 then
    raise exception 'Migration 240: perf_node does not carry the shape this '
                    'expected; add rollsInto to it by hand.';
  else
    execute 'create or replace function perf_node(p_assignment uuid, p_depth integer default 0) '
         || 'returns jsonb language plpgsql stable security definer '
         || 'set search_path to ''public'' as '
         || quote_literal(replace(v_src, v_old, v_new));
  end if;
end $rollsinto$;

do $withdrawn_guard$
declare n int;
begin
  if (select prosrc from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
       where ns.nspname = 'public' and p.proname = 'perf_node') not like '%rollsInto%' then
    raise exception 'Migration 240: perf_node does not return rollsInto';
  end if;
  -- perf_tree draws the screen and perf_kpi_score decides the bonus. If
  -- either still reads a withdrawn measure, remove is a lie.
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname in ('perf_tree','perf_kpi_score')
     and position('WITHDRAWN' in p.prosrc) = 0;
  if n > 0 then
    raise exception 'Migration 240: % of perf_tree / perf_kpi_score still '
                    'count a withdrawn measure', n;
  end if;
  if (select prosrc from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
       where ns.nspname = 'public' and p.proname = 'perf_due')
     not like '%ISSUED%' then
    raise exception 'Migration 240: perf_due no longer limits itself by state, '
                    'so a withdrawn measure is being asked for again';
  end if;
  raise notice 'a withdrawn measure is off the screen, out of the score and '
               'off the to-do list';
end $withdrawn_guard$;

-- ------------------------------------------------------------- the guard
do $guard$
declare
  v_mgr uuid; v_rep uuid; v_cyc uuid; v_a uuid; v_b uuid; r jsonb; n int;
begin
  -- A manager, a report, a cycle and two measures, all thrown away at the
  -- end. The guard proves the gate rather than the plumbing: the plumbing
  -- is proved by build/test/test_edit.sql, which runs on every build.
  insert into person (full_name, work_email, app_role)
    values ('M240 Manager', 'm240.mgr@example.invalid', 'MANAGER') returning id into v_mgr;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('M240 Report', 'm240.rep@example.invalid', 'VIEWER', v_mgr) returning id into v_rep;

  select id into v_cyc from perf_cycle
   where period_kind = 'MONTH' and current_date <= assign_closes
   order by period_start desc limit 1;
  if v_cyc is null then
    raise notice 'Migration 240: no open cycle, so the gate is unproven on data.';
    delete from person where id in (v_mgr, v_rep);
    return;
  end if;

  r := perf_assign(v_mgr, jsonb_build_object(
         'personId', v_rep, 'cycleId', v_cyc, 'name', 'M240 measure', 'unit', 'cases'));
  if coalesce((r->>'ok')::boolean, false) is not true then
    raise exception 'Migration 240: could not create the test measure: %', r;
  end if;
  v_a := (r->>'assignmentId')::uuid;

  -- The report may not change their own.
  r := perf_assign_edit(v_rep, jsonb_build_object('assignmentId', v_a, 'name', 'Mine now'));
  if r->>'error' is distinct from 'not_permitted' then
    raise exception 'Migration 240: a person edited their own measure: %', r;
  end if;
  r := perf_assign_remove(v_rep, v_a);
  if r->>'error' is distinct from 'not_permitted' then
    raise exception 'Migration 240: a person removed their own measure: %', r;
  end if;

  -- The manager may.
  r := perf_assign_edit(v_mgr, jsonb_build_object(
         'assignmentId', v_a, 'name', 'M240 renamed', 'weight', '40'));
  if coalesce((r->>'ok')::boolean, false) is not true then
    raise exception 'Migration 240: the manager could not edit: %', r;
  end if;
  select count(*) into n from perf_assignment
   where id = v_a and name = 'M240 renamed' and weight_pct = 40;
  if n <> 1 then
    raise exception 'Migration 240: the edit did not land';
  end if;

  -- A measure cannot be made its own parent.
  r := perf_assign_edit(v_mgr, jsonb_build_object('assignmentId', v_a, 'rollsInto', v_a));
  if r->>'error' is distinct from 'rolls_into_itself' then
    raise exception 'Migration 240: a measure was made its own parent: %', r;
  end if;

  -- With nothing filed, removing deletes.
  r := perf_assign_remove(v_mgr, v_a);
  if (r->>'withdrawn')::boolean is not false then
    raise exception 'Migration 240: an unfiled measure was withdrawn, not removed: %', r;
  end if;
  if exists (select 1 from perf_assignment where id = v_a) then
    raise exception 'Migration 240: the measure is still there after removal';
  end if;

  -- With something filed, it is withdrawn and the figure survives.
  r := perf_assign(v_mgr, jsonb_build_object(
         'personId', v_rep, 'cycleId', v_cyc, 'name', 'M240 filed', 'unit', 'cases',
         'target', '10'));
  v_b := (r->>'assignmentId')::uuid;
  insert into perf_entry (assignment_id, as_of, value, filed_by)
    values (v_b, current_date, 3, v_rep);
  r := perf_assign_remove(v_mgr, v_b);
  if (r->>'withdrawn')::boolean is not true then
    raise exception 'Migration 240: a filed-against measure was deleted: %', r;
  end if;
  if not exists (select 1 from perf_entry where assignment_id = v_b) then
    raise exception 'Migration 240: removing took the filed figure with it';
  end if;

  delete from perf_entry where assignment_id = v_b;
  delete from perf_assignment where person_id = v_rep;
  delete from audit_entry where actor_id in (v_mgr, v_rep);
  delete from person where id in (v_mgr, v_rep);

  raise notice 'edit and remove are the manager''s, not the person''s; '
               'a filed-against measure is withdrawn and its figures survive';
end $guard$;
