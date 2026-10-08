-- The monthly KPI list is one scorecard, saved whole
--
-- "The current KPI/target assignment journey is too complicated, has too many
--  tabs/options, and is difficult to use."
--
-- The journey was: open the team card, open a person, open the measures
-- panel, open a form per measure, and set the target through a different
-- door again because perf_assign_edit deliberately does not take one. Five
-- places to go and two of them write the same row.
--
-- This is the monthly twin of plb_sheet_measures_set, deliberately the same
-- shape, because the owner asked for the quarterly journey and the monthly
-- journey to be the same thing: the WHOLE list arrives in one call, is
-- validated whole, and is written whole.
--
-- It writes nothing itself. Every row still goes through perf_assign,
-- perf_assign_edit, perf_target_set and perf_assign_remove, which hold the
-- permission checks, the cascade down to the team and the audit. A second
-- door onto a row is how two doors start disagreeing.
--
-- =====================================================================
-- THE RULES, AND WHY THEY ARE THE SHAPE THEY ARE
--
-- WEIGHTS ADD TO 100, within a tenth. Not exactly 100: of the 101 people
-- carrying measures this month, 76 sum to something other than 100 and
-- every one of them is a rounding artefact -- three measures at 33.33 come
-- to 99.99, four at 25 come to 100, six at 16.67 come to 100.02. The range
-- across the whole company is 99.99 to 100.02. An exact test would refuse
-- three quarters of the company a save while telling them their weights are
-- wrong, which is how a rule gets switched off. A tenth is far tighter than
-- any real mistake and far looser than any rounding.
--
-- BETWEEN THREE AND FIVE MEASURES -- but the maximum is a cap on ADDING,
-- not a wall in front of people who are already over it. Nine people carry
-- six measures today. A hard maximum of five would lock all nine out of
-- their own scorecard until somebody deleted one, and the person who would
-- have to do that is the one being locked out. So the ceiling for any one
-- save is the greater of five and what that person already has: you may
-- never add past five, and you are never stopped from fixing what you have.
--
-- EVERY MEASURE CARRIES A TARGET, zero included. The owner's rule, and the
-- reason migration 253 exists: "one up manager if has assigned a KPI should
-- be assigning the target too ... should be adding 0 in the target and not
-- keep it blank."
--
-- A MEASURE WITH SUB-KPIs KEEPS ITS TARGET. perf_value already derives the
-- parent's VALUE from its children -- summed for a count, target-weighted
-- averaged for a level -- and perf_entry_not_on_a_parent already refuses a
-- filing against a parent. The target is a different thing: it is what the
-- parent is being asked for, and the children divide it. Nothing here
-- changes either, because both are right.
-- =====================================================================

create or replace function perf_kpis_set(p_actor uuid, p_cycle uuid,
                                         p_person uuid, p_measures jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public'
as $function$
declare
  c perf_cycle; s person; x jsonb; i int := 0;
  v_bad jsonb := '[]'::jsonb; v_notes jsonb := '[]'::jsonb;
  v_w numeric; v_sum numeric := 0;
  v_keep uuid[] := '{}'; v_id uuid; v_have int; v_cap int;
  v_added int := 0; v_changed int := 0; v_gone int := 0;
  o jsonb; r record;
begin
  select * into c from perf_cycle where id = p_cycle;
  if c.id is null then return jsonb_build_object('error','no_such_cycle'); end if;
  select * into s from person
   where id = p_person and employment_status = 'ACTIVE' and superseded_by is null;
  if s.id is null then return jsonb_build_object('error','no_such_person'); end if;

  -- The one gate, asked of the database as every other write asks it.
  -- perf_may_set is 'manage' or 'admin' and answers 'self' first, so nobody
  -- reaches their own scorecard through here.
  if not perf_may_set(p_actor, p_person) then
    return jsonb_build_object('error','not_permitted',
      'reason','Setting somebody''s measures is their own manager''s and the '
            || 'administrator''s. Nobody sets their own.');
  end if;

  if jsonb_typeof(coalesce(p_measures,'null'::jsonb)) <> 'array' then
    return jsonb_build_object('error','invalid',
      'reason','Send the measures as a list. This call carried '
            || coalesce(jsonb_typeof(p_measures),'nothing') || '.');
  end if;

  -- What they carry today, so the ceiling can be the greater of five and it.
  select count(*) into v_have from perf_assignment a
   where a.cycle_id = p_cycle and a.person_id = p_person
     and a.part_of_id is null and a.state <> 'WITHDRAWN';
  v_cap := greatest(5, v_have);

  -- ------------------------------------------------------------ validate
  for x in select jsonb_array_elements(p_measures) loop
    i := i + 1;

    v_id := nullif(btrim(coalesce(x->>'assignmentId','')),'')::uuid;

    -- A measure already on the scorecard carries its own name. Demanding it
    -- back on every save would mean the screen had to resend every field it
    -- was not changing, which is the shape of form this whole change is
    -- getting rid of. Only a NEW measure has to say what it is.
    if v_id is null
       and btrim(coalesce(x->>'name','')) = ''
       and nullif(btrim(coalesce(x->>'kpiId','')),'') is null then
      v_bad := v_bad || jsonb_build_object('at', i,
        'reason','Measure ' || i || ': choose a measure or give it a name.');
    end if;

    v_w := nullif(btrim(coalesce(x->>'weight','')),'')::numeric;
    if v_w is null or v_w <= 0 or v_w > 100 then
      v_bad := v_bad || jsonb_build_object('at', i,
        'reason','Measure ' || i || ' needs a weight between nought and a hundred.');
    else
      v_sum := v_sum + v_w;
    end if;

    if nullif(btrim(coalesce(x->>'target','')),'') is null then
      v_bad := v_bad || jsonb_build_object('at', i,
        'reason','Measure ' || i || ' has no target. A measure with nothing to '
              || 'hit cannot be scored, and zero is a target you can type.');
    end if;

    if v_id is not null then
      if v_id = any(v_keep) then
        v_bad := v_bad || jsonb_build_object('at', i,
          'reason','Measure ' || i || ' is on the list twice.');
      end if;
      if not exists (select 1 from perf_assignment a
                      where a.id = v_id and a.cycle_id = p_cycle
                        and a.person_id = p_person and a.part_of_id is null) then
        v_bad := v_bad || jsonb_build_object('at', i,
          'reason','Measure ' || i || ' is not one of this person''s measures '
                || 'for this period.');
      end if;
      v_keep := v_keep || v_id;
    end if;
  end loop;

  if jsonb_array_length(p_measures) < 3 then
    v_bad := v_bad || jsonb_build_object('at', null,
      'reason','A scorecard carries at least three measures. This one carries '
            || jsonb_array_length(p_measures) || '.');
  end if;
  if jsonb_array_length(p_measures) > v_cap then
    v_bad := v_bad || jsonb_build_object('at', null,
      'reason','A scorecard carries at most five measures'
            || case when v_cap > 5 then ', and this person already carries '
                    || v_have || ', so no more may be added' else '' end
            || '. This one carries ' || jsonb_array_length(p_measures) || '.');
  end if;

  -- A tenth, for the reason at the head of this file.
  if jsonb_array_length(v_bad) = 0 and abs(round(v_sum, 2) - 100) > 0.1 then
    v_bad := v_bad || jsonb_build_object('at', null,
      'reason','The weights come to ' || round(v_sum,2) || ' and not a hundred. '
            || 'A person''s measures have to account for all of them, or the '
            || 'score cannot be worked out by hand.');
  end if;

  -- Nothing is taken away that has a number filed against it or parts
  -- hanging off it. Checked with the rest, before a single write, so a list
  -- that is half-allowed changes nothing at all.
  for r in
    select a.id, a.name,
           exists (select 1 from perf_entry e where e.assignment_id = a.id) as filed,
           exists (select 1 from perf_assignment ch where ch.part_of_id = a.id
                     and ch.state <> 'WITHDRAWN') as has_parts
      from perf_assignment a
     where a.cycle_id = p_cycle and a.person_id = p_person
       and a.part_of_id is null and a.state <> 'WITHDRAWN'
       and not (a.id = any(v_keep))
  loop
    if r.filed or r.has_parts then
      v_bad := v_bad || jsonb_build_object('at', null,
        'reason', r.name || ' cannot come off this scorecard: '
              || case when r.filed then 'a number has already been filed '
                      || 'against it' else 'it has sub-KPIs under it' end
              || '. Set its weight low if it no longer matters.');
    end if;
  end loop;

  if jsonb_array_length(v_bad) > 0 then
    return jsonb_build_object('error','invalid', 'fields', v_bad,
      'reason','Nothing was saved. Put these right and send it again.');
  end if;

  -- --------------------------------------------------------------- write
  -- Each row still goes through the function that owns it. Those carry the
  -- permission check, the cascade and the audit; this only decides which of
  -- them each row needs.
  for r in
    select a.id, a.name from perf_assignment a
     where a.cycle_id = p_cycle and a.person_id = p_person
       and a.part_of_id is null and a.state <> 'WITHDRAWN'
       and not (a.id = any(v_keep))
  loop
    o := perf_assign_remove(p_actor, r.id);
    if o->>'error' is not null then
      return jsonb_build_object('error', o->>'error',
        'reason', 'Taking ' || r.name || ' off was refused: '
               || coalesce(o->>'reason', o->>'error'));
    end if;
    v_gone := v_gone + 1;
  end loop;

  i := 0;
  for x in select jsonb_array_elements(p_measures) loop
    i := i + 1;
    v_id := nullif(btrim(coalesce(x->>'assignmentId','')),'')::uuid;

    if v_id is null then
      o := perf_assign(p_actor, jsonb_build_object(
             'cycleId', p_cycle, 'personId', p_person,
             'kpiId',   nullif(btrim(coalesce(x->>'kpiId','')),''),
             'name',    nullif(btrim(coalesce(x->>'name','')),''),
             'unit',    nullif(btrim(coalesce(x->>'unit','')),''),
             'target',  (x->>'target')::numeric,
             'weight',  (x->>'weight')::numeric,
             'cadence', nullif(btrim(coalesce(x->>'cadence','')),''),
             'cadenceDay', nullif(btrim(coalesce(x->>'cadenceDay','')),''),
             'direction',  nullif(btrim(coalesce(x->>'direction','')),''),
             'rollsInto',  nullif(btrim(coalesce(x->>'rollsInto','')),''),
             'note',       nullif(btrim(coalesce(x->>'note','')),'')));
      if o->>'error' is not null then
        return jsonb_build_object('error', o->>'error',
          'reason','Measure ' || i || ' could not be given: '
                || coalesce(o->>'reason', o->>'error'), 'at', i);
      end if;
      v_added := v_added + 1;
    else
      o := perf_assign_edit(p_actor, jsonb_build_object(
             'assignmentId', v_id,
             'name',    nullif(btrim(coalesce(x->>'name','')),''),
             'unit',    nullif(btrim(coalesce(x->>'unit','')),''),
             'weight',  (x->>'weight')::numeric,
             'cadence', nullif(btrim(coalesce(x->>'cadence','')),''),
             'cadenceDay', nullif(btrim(coalesce(x->>'cadenceDay','')),''),
             'direction',  nullif(btrim(coalesce(x->>'direction','')),''),
             'note',       nullif(btrim(coalesce(x->>'note','')),'')));
      if o->>'error' is not null then
        return jsonb_build_object('error', o->>'error',
          'reason','Measure ' || i || ' could not be changed: '
                || coalesce(o->>'reason', o->>'error'), 'at', i);
      end if;

      -- The target moves through its own door, which is also what runs the
      -- cascade down to the team and across the clients. Only when it has
      -- actually changed, so a save that touched a name does not re-pin a
      -- target somebody set by hand.
      if coalesce((select a.target_value from perf_assignment a where a.id = v_id), -1)
         is distinct from (x->>'target')::numeric then
        o := perf_target_set(p_actor, v_id, (x->>'target')::numeric, true);
        if o->>'error' is not null then
          return jsonb_build_object('error', o->>'error',
            'reason','The target on measure ' || i || ' could not be set: '
                  || coalesce(o->>'reason', o->>'error'), 'at', i);
        end if;
      end if;
      v_changed := v_changed + 1;
    end if;
  end loop;

  -- A measure whose parts do not add up to it is worth saying out loud
  -- rather than refusing: the parts are a plan for making the number and a
  -- manager may be mid-way through writing them.
  for r in
    select a.name, a.target_value as t, perf_accrual_kind(a.kpi_id, a.unit) as kind,
           (select sum(ch.target_value) from perf_assignment ch
             where ch.part_of_id = a.id and ch.state <> 'WITHDRAWN') as parts
      from perf_assignment a
     where a.cycle_id = p_cycle and a.person_id = p_person
       and a.part_of_id is null and a.state <> 'WITHDRAWN'
       and exists (select 1 from perf_assignment ch where ch.part_of_id = a.id
                     and ch.state <> 'WITHDRAWN')
  loop
    if r.kind = 'SUM' and r.parts is not null and r.t is not null
       and round(r.parts, 2) <> round(r.t, 2) then
      v_notes := v_notes || to_jsonb(r.name || ': its sub-KPIs come to '
                 || round(r.parts,2) || ' against a target of ' || round(r.t,2) || '.');
    end if;
  end loop;

  insert into audit_entry (actor_id, action, entity_type, entity_ref,
                           old_value, new_value)
  values (p_actor, 'PERF_KPIS_SET', 'person', p_person::text, null,
          jsonb_build_object('cycleId', p_cycle, 'measures', p_measures));

  return jsonb_build_object('ok', true,
    'personId', p_person, 'cycleId', p_cycle,
    'added', v_added, 'changed', v_changed, 'removed', v_gone,
    'weights', round(v_sum, 2), 'count', jsonb_array_length(p_measures),
    'mayAdd', jsonb_array_length(p_measures) < 5,
    'notes', v_notes,
    'note', 'Saved. ' || jsonb_array_length(p_measures) || ' measure(s), '
         || 'weights ' || round(v_sum, 2) || '.'
         || case when jsonb_array_length(v_notes) > 0
                 then ' ' || (v_notes->>0) else '' end);
end
$function$;

comment on function perf_kpis_set(uuid, uuid, uuid, jsonb) is
  'One person''s whole monthly KPI list, in one call. Validated whole -- '
  'three to five measures, weights to a hundred within a tenth, a target on '
  'every one -- then written row by row through perf_assign, '
  'perf_assign_edit, perf_target_set and perf_assign_remove, which keep the '
  'permission checks, the cascade and the audit. The monthly twin of '
  'plb_sheet_measures_set, deliberately the same shape.';

-- =====================================================================
-- A control that is offered and then refused.
--
-- perf_tree_for returned maySet = rel in ('self','manage','admin'), so a
-- person reading their OWN measures was handed every editing control on the
-- screen -- and perf_may_set, which is what the writes actually ask, says
-- 'manage' or 'admin' and nothing else. Every one of those controls was
-- going to be refused.
--
-- The screen's flag now matches the gate behind it.
-- =====================================================================
create or replace function perf_tree_for(p_actor uuid, p_person uuid, p_cycle uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare v_rel text; v_out jsonb;
begin
  v_rel := perf_rel(p_actor, p_person);
  if v_rel is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That person is not in your line. You see your own team, and the progress of everyone below them.');
  end if;
  v_out := perf_tree(p_person, p_cycle);
  if jsonb_typeof(v_out) = 'object' then
    v_out := v_out || jsonb_build_object(
      'rel', v_rel,
      /* The same question perf_may_set answers, so a control is drawn only
         where the write behind it will be allowed. */
      'maySet', perf_may_set(p_actor, p_person),
      'mine',   v_rel = 'self');
  end if;
  return v_out;
end
$function$;

-- =====================================================================
-- One read for the whole Performance Mapping panel.
--
-- "Inside My Team, I select a person. Immediately within the same page/tab,
--  show Performance Mapping. Do NOT send the user through unnecessary pages
--  or multiple navigation steps."
--
-- One click, one request. The monthly scorecard, the quarterly sheet that
-- goes with it, and the rules the screen has to obey -- how many measures
-- there are, what the weights come to, whether another may be added -- all
-- answered here rather than re-derived in JavaScript. A rule worked out in
-- two places is a rule that disagrees with itself, and the one in the
-- screen is the one that will be wrong.
-- =====================================================================
create or replace function perf_mapping(p_actor uuid, p_person uuid, p_cycle uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  t jsonb; c perf_cycle; v_q date; v_sheet uuid; v_n int; v_w numeric; v_have int;
begin
  t := perf_tree_for(p_actor, p_person, p_cycle);
  if t->>'error' is not null then return t; end if;

  select * into c from perf_cycle where id = p_cycle;
  v_q := date_trunc('quarter', coalesce(c.period_start, current_date))::date;

  -- The quarterly sheet for the same person and the quarter this month sits
  -- in. Null is an ordinary state -- no sheet has been issued -- and the
  -- screen says so rather than drawing an empty table.
  select s.id into v_sheet from plb_goal_sheet s
   where s.person_id = p_person and s.quarter = v_q
   order by s.created_at desc limit 1;

  select count(*), coalesce(sum(coalesce(a.weight_pct,0)), 0)
    into v_n, v_w
    from perf_assignment a
   where a.cycle_id = p_cycle and a.person_id = p_person
     and a.part_of_id is null and a.state <> 'WITHDRAWN';
  v_have := v_n;

  return t || jsonb_build_object(
    'quarter', v_q,
    'sheetId', v_sheet,
    'rules', jsonb_build_object(
      'min', 3,
      'max', 5,
      -- The ceiling for THIS person, which is five unless they are already
      -- above it. Nine people carry six today and a hard five would lock
      -- every one of them out of their own scorecard.
      'cap', greatest(5, v_have),
      'count', v_n,
      'weights', round(v_w, 2),
      'weightsOk', abs(round(v_w, 2) - 100) <= 0.1,
      'mayAdd', v_n < 5,
      'tooFew', v_n < 3,
      'says', case
        when v_n < 3 then 'A scorecard carries at least three measures. '
             || 'There ' || case when v_n = 1 then 'is 1' else 'are ' || v_n end
             || ' here.'
        when v_n >= 5 then 'Five measures is the most a scorecard carries.'
        else null end));
end
$function$;

comment on function perf_mapping(uuid, uuid, uuid) is
  'Everything the Performance Mapping panel needs for one person, in one '
  'request: the monthly scorecard, the quarterly sheet for the quarter that '
  'month sits in, and the rules the screen must obey. The rules are answered '
  'here rather than re-derived in JavaScript, because a rule worked out in '
  'two places is a rule that disagrees with itself.';

-- ------------------------------------------------------------- the guard
do $guard$
declare
  v_cycle uuid; v_boss uuid; v_rep uuid; o jsonb; v_list jsonb; n int; v_n int;
begin
  select id into v_cycle from perf_cycle
   where period_start = date_trunc('month', current_date)::date and period_kind = 'MONTH';
  if v_cycle is null then
    raise notice 'Migration 257: no cycle this month to check against.';
    return;
  end if;

  select a.person_id, p.manager_id into v_rep, v_boss
    from perf_assignment a join person p on p.id = a.person_id
   where a.cycle_id = v_cycle and a.part_of_id is null and a.state <> 'WITHDRAWN'
     and p.manager_id is not null
   group by a.person_id, p.manager_id
  having count(*) between 3 and 5
   limit 1;
  if v_rep is null then
    raise notice 'Migration 257: nobody with a manager and 3-5 measures.';
    return;
  end if;

  -- Nobody sets their own.
  if perf_kpis_set(v_rep, v_cycle, v_rep, '[]'::jsonb)->>'error'
     is distinct from 'not_permitted' then
    raise exception 'Migration 257: a person set their own scorecard.';
  end if;

  -- Fewer than three is refused.
  select jsonb_agg(jsonb_build_object('assignmentId', a.id, 'name', a.name,
                                      'weight', 100, 'target', coalesce(a.target_value,0)))
    into v_list from (select * from perf_assignment
                       where cycle_id = v_cycle and person_id = v_rep
                         and part_of_id is null and state <> 'WITHDRAWN'
                       limit 1) a;
  if perf_kpis_set(v_boss, v_cycle, v_rep, v_list)->>'error' is distinct from 'invalid' then
    raise exception 'Migration 257: a scorecard of one measure was accepted.';
  end if;

  -- Weights that do not add up are refused.
  select jsonb_agg(jsonb_build_object('assignmentId', a.id, 'name', a.name,
                                      'weight', 10, 'target', coalesce(a.target_value,0)))
    into v_list from perf_assignment a
   where a.cycle_id = v_cycle and a.person_id = v_rep
     and a.part_of_id is null and a.state <> 'WITHDRAWN';
  if perf_kpis_set(v_boss, v_cycle, v_rep, v_list)->>'error' is distinct from 'invalid' then
    raise exception 'Migration 257: weights that do not add to a hundred were accepted.';
  end if;

  -- A measure with no target is refused.
  select count(*) into v_n from perf_assignment a
   where a.cycle_id = v_cycle and a.person_id = v_rep
     and a.part_of_id is null and a.state <> 'WITHDRAWN';
  select jsonb_agg(jsonb_build_object('assignmentId', a.id, 'name', a.name,
                                      'weight', round(100.0 / v_n, 4)))
    into v_list from perf_assignment a
   where a.cycle_id = v_cycle and a.person_id = v_rep
     and a.part_of_id is null and a.state <> 'WITHDRAWN';
  if perf_kpis_set(v_boss, v_cycle, v_rep, v_list)->>'error' is distinct from 'invalid' then
    raise exception 'Migration 257: a measure with no target was accepted.';
  end if;

  -- Nothing above wrote anything.
  select count(*) into n from perf_assignment
   where cycle_id = v_cycle and person_id = v_rep
     and part_of_id is null and state <> 'WITHDRAWN';
  if n = 0 then
    raise exception 'Migration 257: a refusal emptied the scorecard.';
  end if;

  -- And the screen is no longer offered a control the write would refuse.
  if coalesce((perf_tree_for(v_rep, v_rep, v_cycle)->>'maySet')::boolean, false) then
    raise exception 'Migration 257: a person is still offered the controls for '
                    'their own measures.';
  end if;

  -- And one read answers the whole panel.
  o := perf_mapping(v_boss, v_rep, v_cycle);
  if o->>'error' is not null then
    raise exception 'Migration 257: perf_mapping refused the manager: %', o;
  end if;
  if not (o ? 'rules') or not (o ? 'measures') or not (o ? 'quarter') then
    raise exception 'Migration 257: perf_mapping does not carry the scorecard, '
                    'the rules and the quarter in one answer.';
  end if;

  raise notice 'perf_kpis_set: the monthly scorecard is one list, saved whole.';
end $guard$;
