-- =====================================================================
-- 221 · Nobody starts from a blank sheet
--
-- Reported: "I still can see you have not pre uploaded the KPIs."
--
-- Correct, and the shape of it is worth being precise about, because two
-- different things get called "the KPIs":
--
--   kpi_definition   173 rows across 42 chairs -- the REGISTRY. What a
--                    chair is measured on. Loaded, and has been.
--   perf_assignment  0 rows -- what one PERSON is measured on, this
--                    cycle, with a target.
--   kpi_target       0 rows
--   plb_goal_sheet   0 rows
--
-- So the registry is there and not one person has been given anything out
-- of it. Everybody opens Performance to an empty screen, and the screen is
-- telling the truth.
--
-- WHAT THE CONSTITUTION ALREADY SAYS TO DO
--
-- This is not a new policy. The PLB Constitution issues a goal sheet by
-- day 10 and has a day-15 backstop: where no sheet has been issued, the
-- chair's standard sheet applies. Seeding every seated person with their
-- own chair's measures IS that backstop, written down.
--
-- WHAT IS DELIBERATELY LEFT BLANK
--
-- target_value. Every measure arrives; not one arrives with a number.
--
-- A KPI without a target is a person who knows what they are measured on
-- and is waiting to agree how much. A KPI with a target nobody agreed is
-- a person being held to a figure they never saw, and at the end of the
-- quarter that figure is multiplied into somebody's pay. The first is an
-- honest starting point. The second is the failure the whole scheme
-- exists to prevent, and it would be the tool that caused it.
--
-- weight_pct is filled, because it is not a judgement: the registry's own
-- rule, the one the /registry route has always shown, is equal weighting
-- across a chair's measures -- round(100 / count, 2).
--
-- WHAT CLIMBS INTO WHAT
--
-- A second pass links each seeded measure to the same measure on the
-- person's manager, where the manager has one. That is what makes a
-- number typed at a branch reach the zone without anybody re-keying it.
-- It is a second pass because a manager's row may not exist yet when
-- their report's is written, and the trigger on perf_assignment refuses a
-- measure that climbs into its own holder's.
--
-- Seeded rows carry a note saying where they came from, so a manager
-- looking at a sheet can tell "this is the chair's standard set, nobody
-- has looked at it yet" from "this is what my manager and I agreed".
-- =====================================================================

create or replace function perf_seed_from_registry(p_actor uuid, p_cycle uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_role    role_kind;
  c         perf_cycle;
  r         record;
  v_made    int := 0;
  v_linked  int := 0;
  v_people  int := 0;
  v_skipped int := 0;
  v_noset   jsonb := '[]'::jsonb;
  v_last    uuid;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Seeding the whole company from the registry is an '
               'administrator''s. A manager sets their own team''s, one at a time.');
  end if;

  select * into c from perf_cycle where id = p_cycle;
  if c.id is null then
    return jsonb_build_object('error','no_such_cycle');
  end if;

  -- ------------------------------------------------------------ pass one
  -- Every seated person, every measure their own chair is measured on.
  for r in
    select pe.id as person_id, pe.full_name, ch.id as chair_id, ch.code as chair_code,
           k.id as kpi_id, k.name, k.unit, k.cadence,
           round(100.0 / count(*) over (partition by ch.id), 2) as weight
      from chair_holder h
      join person pe on pe.id = h.person_id
      join chair  ch on ch.id = h.chair_id
      join kpi_definition k on k.chair_id = ch.id and k.active and k.position < 100
     where h.to_date is null
       and pe.employment_status = 'ACTIVE'
       and pe.superseded_by is null
       and coalesce(pe.employee_type, 'EMPLOYEE') <> 'CLIENT_CONTACT'
       and h.id = (select h2.id from chair_holder h2
                    where h2.person_id = pe.id and h2.to_date is null
                    order by h2.is_primary desc nulls last, h2.id limit 1)
     order by pe.full_name, k.position
  loop
    -- No unique key covers (cycle, person, kpi), so the check is explicit
    -- rather than an ON CONFLICT that would quietly do nothing.
    if exists (select 1 from perf_assignment a
                where a.cycle_id = c.id and a.person_id = r.person_id
                  and a.kpi_id = r.kpi_id) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    insert into perf_assignment (cycle_id, person_id, kpi_id, name, unit,
        target_value, weight_pct, cadence, set_by, state, note)
    values (c.id, r.person_id, r.kpi_id, r.name, r.unit,
            null,                      -- the target is the manager's to agree
            r.weight, r.cadence, p_actor, 'ISSUED',
            'The standard set for ' || r.chair_code || ', pre-loaded from the '
            || 'chair registry. The target is deliberately blank: it is agreed '
            || 'with the reporting manager, not assumed here.')
    returning id into v_last;
    v_made := v_made + 1;
  end loop;

  select count(distinct person_id) into v_people
    from perf_assignment where cycle_id = c.id;

  -- ------------------------------------------------------------ pass two
  -- The same measure on my manager is the one mine climbs into. Written
  -- separately because a manager's row may not have existed when their
  -- report's was written, and because the trigger refuses a measure that
  -- climbs into one of the same person's.
  --
  -- Matched by NAME and unit, not by kpi_id. The registry is per chair:
  -- "Cases closed" on the Zonal Manager chair and "Cases closed" on the
  -- Branch Manager chair are two different kpi_definition rows with two
  -- different ids, so matching on the id linked nothing at all. That is
  -- what build/test/test_seed.sql caught. The unit has to agree too, or a
  -- percentage climbs into a count and the total is nonsense.
  for r in
    select a.id,
           (select m.id from perf_assignment m
             where m.cycle_id = a.cycle_id
               and m.person_id = pe.manager_id
               and m.name = a.name
               and m.unit is not distinct from a.unit
               and m.part_of_id is null
             order by m.id limit 1) as into_id
      from perf_assignment a
      join person pe on pe.id = a.person_id
     where a.cycle_id = c.id
       and a.rolls_into_id is null
       and a.part_of_id is null
       and pe.manager_id is not null
       and pe.manager_id <> pe.id
  loop
    continue when r.into_id is null;
    update perf_assignment set rolls_into_id = r.into_id where id = r.id;
    v_linked := v_linked + 1;
  end loop;

  -- ------------------------------------------ who got nothing, and why
  select coalesce(jsonb_agg(jsonb_build_object(
           'person', q.full_name, 'chair', q.chair, 'why', q.why)
         order by q.chair, q.full_name), '[]'::jsonb)
    into v_noset
    from (
      select pe.full_name,
             coalesce(ch.code, '(no chair)') as chair,
             case when ch.id is null then 'they hold no chair'
                  else 'their chair has no measure set in the registry' end as why
        from person pe
        left join chair_holder h on h.person_id = pe.id and h.to_date is null
        left join chair ch on ch.id = h.chair_id
       where pe.employment_status = 'ACTIVE' and pe.superseded_by is null
         and coalesce(pe.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
         and not exists (select 1 from perf_assignment a
                          where a.cycle_id = c.id and a.person_id = pe.id)
         and exists (select 1 from chair_holder h3 where h3.person_id = pe.id
                                                     and h3.to_date is null)) q;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'PERF_SEEDED_FROM_REGISTRY', 'perf_cycle', c.id::text,
          jsonb_build_object('period', c.period_start, 'made', v_made,
                             'linked', v_linked, 'people', v_people,
                             'alreadyThere', v_skipped));

  return jsonb_build_object(
    'ok', true, 'period', c.period_start,
    'made', v_made, 'linked', v_linked, 'people', v_people,
    'alreadyThere', v_skipped,
    'withoutAMeasureSet', jsonb_array_length(v_noset), 'noSet', v_noset,
    'note', v_made || ' measure(s) given to ' || v_people || ' people for '
            || c.period_start || ', with the targets blank. '
            || v_linked || ' of them climb into a manager''s.');
end $function$;

comment on function perf_seed_from_registry(uuid,uuid) is
  'Gives every seated person the measures their own chair is measured on, '
  'for one cycle, with the target left blank. This is the PLB '
  'Constitution''s day-15 backstop -- where no goal sheet has been issued, '
  'the chair''s standard sheet applies -- written down. Safe to run twice: '
  'a person who already has a measure keeps the one they have.';

revoke all on function perf_seed_from_registry(uuid,uuid) from public, anon, authenticated;
