-- =====================================================================
-- 224 · A target to start from, and a day to file
--
-- Asked for: "For now add dummy Targets to everyone based on the
-- dummy/suggestion KPIs that you have added which managers can change and
-- update later."
--
-- Migration 221 seeded every measure with the target deliberately blank,
-- and gave the reason: a target nobody agreed is multiplied into somebody's
-- pay at the end of the quarter. That reason has not changed. What has
-- changed is that a blank target makes the whole flow untestable -- with no
-- target there is no percentage, with no percentage there is nothing to
-- roll up, and a manager opening the screen has nothing to correct.
--
-- So: a starting number, marked as one.
--
-- Every target seeded here is target_source = 'SEEDED', which the screen
-- reads and says out loud, and which perf_cascade overwrites without
-- hesitation the moment a real number comes down from above. The instant a
-- manager types one it becomes 'MANUAL' and nothing overwrites it again.
-- A seeded target and an agreed target are different things and the
-- database knows which is which.
--
-- WHERE THE NUMBERS COME FROM
--
-- Not invented. The registry already states the standard in the unit text
-- for the measures that have one -- "target 95%", "target below 3%",
-- "target zero" -- and those are read out and used. For the rest:
--
--   LEVEL, "below" or "variance" in the unit   5    a ceiling: error
--                                                   rates, expense
--                                                   variance, attrition
--   LEVEL, everything else                     90   a floor: the common
--                                                   standard for an
--                                                   achievement percentage
--   SUM                                        the parent's share, or 100
--
-- Then the cascade runs from the top of every chain, so a branch's number
-- is its zone's number divided rather than a figure invented at the branch.
--
-- THE DAY
--
-- Every seeded measure becomes DAILY. All 173 registry measures said
-- MONTHLY, and a monthly measure falls due exactly once -- on the cycle's
-- closing date -- which is why perf_due returned nothing for anybody on any
-- ordinary day and the fortnight strip was empty for everyone.
--
-- perf_due already reads the cadence and already rolls a due date off a
-- Sunday or a holiday. Changing the cadence is the whole of "daily updates
-- in all departments": a person is asked for one number per measure per
-- working day, and perf_value moves the org total the moment they file.
--
-- The cadence stays a per-measure column. A measure that genuinely is
-- monthly is one UPDATE away from being monthly again.
-- =====================================================================

create or replace function perf_seed_targets(p_actor uuid, p_cycle uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_role role_kind; r record;
  v_set int := 0; v_kept int := 0; v_daily int := 0; v_moved int := 0;
  v_target numeric; v_stated numeric; u text;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Seeding the company''s targets is an administrator''s. A '
               'manager sets their own team''s, one at a time.');
  end if;

  -- ------------------------------------------------------------- the day
  update perf_assignment
     set cadence = 'DAILY'::kpi_cadence
   where cycle_id = p_cycle
     and coalesce(cadence::text, '') <> 'DAILY';
  get diagnostics v_daily = row_count;

  -- --------------------------------------------------------- the number
  for r in
    select a.id, a.unit, a.target_value, a.target_source,
           perf_accrual_kind(a.kpi_id, a.unit) as kind
      from perf_assignment a
     where a.cycle_id = p_cycle
       and a.part_of_id is null
     order by a.id
  loop
    -- Never touch a number a person agreed.
    if r.target_source = 'MANUAL' or r.target_value is not null then
      v_kept := v_kept + 1;
      continue;
    end if;

    u := lower(coalesce(r.unit, ''));

    -- The registry states the standard for some measures. Use its words
    -- rather than a number of my own where it has bothered to say.
    v_stated := nullif(substring(u from 'target (?:below |above )?([0-9]+(?:\.[0-9]+)?)'), '')::numeric;
    if u like '%target zero%' then v_stated := 0; end if;

    if v_stated is not null then
      v_target := v_stated;
    elsif r.kind = 'LEVEL' then
      -- A ceiling measure is a number you want small; a floor measure is
      -- one you want large. Seeding 90% for an error rate would be telling
      -- somebody to get nine in ten wrong.
      if perf_direction(r.unit) = 'CEILING' then
        v_target := 5;
      else
        v_target := 90;
      end if;
    else
      v_target := 100;
    end if;

    update perf_assignment
       set target_value = v_target, target_source = 'SEEDED'
     where id = r.id;
    v_set := v_set + 1;
  end loop;

  -- ------------------------------------------- and then it comes down
  -- From the top of every chain, so a branch's number is its zone's
  -- number divided rather than a figure invented at the branch. Only the
  -- tops: perf_cascade recurses the whole way on its own.
  for r in
    select a.id from perf_assignment a
     where a.cycle_id = p_cycle
       and a.rolls_into_id is null
       and a.part_of_id is null
       and exists (select 1 from perf_assignment c where c.rolls_into_id = a.id)
  loop
    v_moved := v_moved + perf_cascade(r.id);
  end loop;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'PERF_TARGETS_SEEDED', 'perf_cycle', p_cycle::text,
          jsonb_build_object('set', v_set, 'kept', v_kept,
                             'madeDaily', v_daily, 'sharesMoved', v_moved));

  return jsonb_build_object('ok', true,
    'set', v_set, 'kept', v_kept, 'madeDaily', v_daily, 'sharesMoved', v_moved,
    'note', v_set || ' target(s) given a starting number, ' || v_kept ||
            ' left as they were, ' || v_daily || ' measure(s) now due daily, ' ||
            v_moved || ' share(s) divided down the line. Every seeded target '
            'is marked as seeded and is overwritten the moment a real one arrives.');
end $function$;

comment on function perf_seed_targets(uuid,uuid) is
  'Gives every blank target a starting number, reading the standard out of '
  'the registry''s own unit text where it states one, and makes every '
  'measure due daily. Marks each as SEEDED so the screen can say so and '
  'the cascade can overwrite it. Never touches a target somebody agreed.';

-- ---------------------------------------------------- the org, upwards
--
-- The pyramid read from the top: for one person, every measure they carry,
-- what has been filed against it by everybody below them, and how far
-- through the target that puts them. perf_value does the arithmetic; this
-- is the shape the Org screen and the dashboard ask for.
create or replace function perf_org_rollup(p_actor uuid, p_cycle uuid,
                                           p_person uuid default null)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_who uuid; v_rel text;
begin
  v_who := coalesce(p_person, p_actor);
  v_rel := perf_rel(p_actor, v_who);
  if v_rel is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That person is not in your line.');
  end if;

  return jsonb_build_object(
    'rel', v_rel,
    'person', (select jsonb_build_object('personId', p.id, 'name', p.full_name,
                        'employeeNo', p.employee_no, 'department', p.department)
                 from person p where p.id = v_who),
    'teamSize', (select count(*) from perf_line(v_who)),
    'measures', coalesce((
      select jsonb_agg(jsonb_build_object(
               'assignmentId', a.id, 'name', a.name, 'unit', a.unit,
               'family', perf_family(a.unit),
               'kind', perf_accrual_kind(a.kpi_id, a.unit),
               'target', a.target_value,
               'targetSource', a.target_source,
               'value', perf_value(a.id),
               'pct', case when coalesce(a.target_value,0) = 0 then null
                           else round(100.0 * perf_value(a.id) / a.target_value, 1) end,
               'feeders', (select count(*) from perf_assignment c where c.rolls_into_id = a.id),
               'filedToday', exists (select 1 from perf_entry e
                                      where e.assignment_id = a.id and e.as_of = current_date),
               'lastFiled', (select max(e.as_of) from perf_entry e where e.assignment_id = a.id))
             order by a.name)
        from perf_assignment a
       where a.person_id = v_who and a.cycle_id = p_cycle and a.part_of_id is null),
      '[]'::jsonb));
end $function$;

comment on function perf_org_rollup(uuid,uuid,uuid) is
  'One person''s measures with everything below them already added in, and '
  'how far through the target that puts them. Refuses a person outside the '
  'asker''s line, like everything else that reads a number about somebody.';

revoke all on function perf_seed_targets(uuid,uuid)          from public, anon, authenticated;
revoke all on function perf_org_rollup(uuid,uuid,uuid)       from public, anon, authenticated;
