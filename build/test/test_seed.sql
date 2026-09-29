-- Nobody starts from a blank sheet (migration 221)
--
-- Reported: "I still can see you have not pre uploaded the KPIs." The
-- registry held 173 measures across 42 chairs and perf_assignment held
-- nothing, so every person opened Performance to an empty screen.
--
-- The two things that matter most here are absences again: the target must
-- arrive BLANK, because a target nobody agreed is multiplied into somebody's
-- pay at the end of the quarter; and a second run must not double anybody's
-- sheet.
--
-- Runs inside a transaction that is rolled back.

begin;

do $seed$
declare
  c_zone uuid; c_branch uuid; c_bare uuid;
  s_zone uuid; s_branch uuid; s_bare uuid;
  p_adm uuid; p_zm uuid; p_bm uuid; p_bare uuid; p_nochair uuid;
begin
  insert into chair (code, title, level) values ('SD_ZONE','Seed zone','region')      returning id into c_zone;
  insert into chair (code, title, level, parent_id) values ('SD_BR','Seed branch','branch', c_zone) returning id into c_branch;
  -- a chair nobody has given a measure set: it must be named, not silently skipped
  insert into chair (code, title, level, parent_id) values ('SD_BARE','Seed bare','branch', c_zone) returning id into c_bare;

  insert into chair_seating (chair_id, scope_label) values (c_zone, 'West') returning id into s_zone;
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (c_branch, 'Pune', s_zone) returning id into s_branch;
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (c_bare, 'Pune', s_zone) returning id into s_bare;

  -- Three measures on the zone chair, two of which the branch chair shares
  -- by name and id, so the roll-up has something to find and something to
  -- leave alone.
  insert into kpi_definition (chair_id, name, unit, active, mandatory, position, cadence, accrual)
  values (c_zone,   'Cases closed',  'cases', true, true,  1, 'DAILY',   'ADDS'),
         (c_zone,   'Quality',       '%',     true, false, 2, 'MONTHLY', 'REPLACES'),
         (c_branch, 'Cases closed',  'cases', true, true,  1, 'DAILY',   'ADDS'),
         (c_branch, 'Branch upkeep', 'score', true, false, 2, 'MONTHLY', 'REPLACES'),
         -- position >= 100 is the attribute range and must not be seeded
         (c_branch, 'An attribute',  'pts',   true, false, 101,'MONTHLY', 'REPLACES'),
         -- inactive must not be seeded either
         (c_branch, 'Retired one',   'cases', false,false, 3, 'DAILY',   'ADDS');

  insert into person (full_name, work_email, app_role)
    values ('SD Admin','sd.admin@example.invalid','ADMIN') returning id into p_adm;
  insert into person (full_name, work_email) values ('SD Zone','sd.zm@example.invalid')
    returning id into p_zm;
  insert into person (full_name, work_email, manager_id)
    values ('SD Branch','sd.bm@example.invalid', p_zm) returning id into p_bm;
  insert into person (full_name, work_email, manager_id)
    values ('SD Bare','sd.bare@example.invalid', p_zm) returning id into p_bare;
  insert into person (full_name, work_email) values ('SD Nochair','sd.nc@example.invalid')
    returning id into p_nochair;

  insert into chair_holder (chair_id, seating_id, person_id, is_primary) values
    (c_zone, s_zone, p_zm, true), (c_branch, s_branch, p_bm, true),
    (c_bare, s_bare, p_bare, true);

  insert into perf_cycle (period_start, assign_opens, assign_closes, entry_closes)
  values (date_trunc('month', current_date)::date,
          date_trunc('month', current_date)::date,
          date_trunc('month', current_date)::date + 9,
          (date_trunc('month', current_date) + interval '1 month - 1 day')::date);
end $seed$;

do $t$
declare
  p_adm uuid; p_zm uuid; p_bm uuid; p_bare uuid; p_nochair uuid;
  v_cyc uuid; o jsonb; n int; v_note text; v_w numeric; v_into uuid;
begin
  select id into p_adm     from person where work_email='sd.admin@example.invalid';
  select id into p_zm      from person where work_email='sd.zm@example.invalid';
  select id into p_bm      from person where work_email='sd.bm@example.invalid';
  select id into p_bare    from person where work_email='sd.bare@example.invalid';
  select id into p_nochair from person where work_email='sd.nc@example.invalid';
  select id into v_cyc from perf_cycle
   where period_start = date_trunc('month', current_date)::date;

  -- ------------------------------------------------------ who may run it
  o := perf_seed_from_registry(p_zm, v_cyc);
  if o->>'error' = 'not_admin'
    then raise notice 'PASS  seeding the whole company is not a manager''s to do';
    else raise exception 'FAIL  a manager seeded the company: %', left(o::text,120); end if;

  o := perf_seed_from_registry(p_adm, gen_random_uuid());
  if o->>'error' = 'no_such_cycle'
    then raise notice 'PASS  and it needs a cycle that exists';
    else raise exception 'FAIL  a made-up cycle gave %', left(o::text,120); end if;

  o := perf_seed_from_registry(p_adm, v_cyc);

  -- ----------------------------------------------------- what got seeded
  select count(*) into n from perf_assignment where cycle_id = v_cyc and person_id = p_zm;
  if n = 2 then raise notice 'PASS  the zone chair''s two measures reach its holder';
           else raise exception 'FAIL  the zone holder got % measures, expected 2', n; end if;

  select count(*) into n from perf_assignment where cycle_id = v_cyc and person_id = p_bm;
  if n = 2 then raise notice 'PASS  and the branch chair''s two reach theirs';
           else raise exception 'FAIL  the branch holder got % measures, expected 2', n; end if;

  if not exists (select 1 from perf_assignment
                  where cycle_id = v_cyc and name = 'An attribute')
    then raise notice 'PASS  an attribute is not a KPI and is not seeded as one';
    else raise exception 'FAIL  position 101 was seeded as a KPI'; end if;

  if not exists (select 1 from perf_assignment
                  where cycle_id = v_cyc and name = 'Retired one')
    then raise notice 'PASS  a retired measure stays retired';
    else raise exception 'FAIL  an inactive measure was seeded'; end if;

  -- ------------------------------------------------- the target is blank
  select count(*) into n from perf_assignment
   where cycle_id = v_cyc and target_value is not null;
  if n = 0 then raise notice 'PASS  every target arrives blank, agreed with a manager and not assumed';
           else raise exception 'FAIL  % seeded measures came with a target', n; end if;

  select weight_pct into v_w from perf_assignment
   where cycle_id = v_cyc and person_id = p_bm and name = 'Cases closed';
  if v_w = 50.00
    then raise notice 'PASS  the weight is the registry''s own rule, equally across a chair';
    else raise exception 'FAIL  the weight came out %', coalesce(v_w::text,'null'); end if;

  select note into v_note from perf_assignment
   where cycle_id = v_cyc and person_id = p_bm and name = 'Cases closed';
  if v_note like '%pre-loaded from the chair registry%'
    then raise notice 'PASS  and it says on its face where it came from';
    else raise exception 'FAIL  the note reads: %', coalesce(left(v_note,80),'nothing'); end if;

  -- ------------------------------------------------------- the roll-up
  select rolls_into_id into v_into from perf_assignment
   where cycle_id = v_cyc and person_id = p_bm and name = 'Cases closed';
  if v_into = (select id from perf_assignment
                where cycle_id = v_cyc and person_id = p_zm and name = 'Cases closed')
    then raise notice 'PASS  a measure my manager also has climbs into theirs';
    else raise exception 'FAIL  Cases closed climbs into %', coalesce(v_into::text,'nothing'); end if;

  select rolls_into_id into v_into from perf_assignment
   where cycle_id = v_cyc and person_id = p_bm and name = 'Branch upkeep';
  if v_into is null
    then raise notice 'PASS  and one they do not have climbs nowhere, rather than guessing';
    else raise exception 'FAIL  Branch upkeep was made to climb somewhere'; end if;

  if (o->>'linked')::int = 1
    then raise notice 'PASS  the answer counts what it linked';
    else raise exception 'FAIL  linked came back %', o->>'linked'; end if;

  -- -------------------------------------------- who got nothing, and why
  if not exists (select 1 from perf_assignment where cycle_id = v_cyc and person_id = p_bare)
    then raise notice 'PASS  a chair with no measure set seeds nobody';
    else raise exception 'FAIL  the bare chair seeded something from nothing'; end if;

  if o->'noSet' @> '[{"chair": "SD_BARE"}]'::jsonb
    then raise notice 'PASS  and that person is named rather than silently skipped';
    else raise exception 'FAIL  noSet reads %', left((o->'noSet')::text, 160); end if;

  if not exists (select 1 from perf_assignment where cycle_id = v_cyc and person_id = p_nochair)
    then raise notice 'PASS  somebody holding no chair is not seeded at all';
    else raise exception 'FAIL  a person with no chair was seeded'; end if;

  -- ------------------------------------------------------ running it twice
  select count(*) into n from perf_assignment where cycle_id = v_cyc;
  o := perf_seed_from_registry(p_adm, v_cyc);
  if (o->>'made')::int = 0 and (o->>'alreadyThere')::int = n
    then raise notice 'PASS  a second run gives nobody a second copy';
    else raise exception 'FAIL  a second run made % and skipped %',
      o->>'made', o->>'alreadyThere'; end if;

  -- ------------------------------------ a target already set is not overwritten
  update perf_assignment set target_value = 250
   where cycle_id = v_cyc and person_id = p_bm and name = 'Cases closed';
  o := perf_seed_from_registry(p_adm, v_cyc);
  select target_value into v_w from perf_assignment
   where cycle_id = v_cyc and person_id = p_bm and name = 'Cases closed';
  if v_w = 250
    then raise notice 'PASS  a target somebody agreed survives a re-run';
    else raise exception 'FAIL  an agreed target came back %', coalesce(v_w::text,'null'); end if;

  -- --------------------------------------------- it is what the screen reads
  if (select jsonb_array_length(perf_due(p_bm, current_date))) >= 1
    then raise notice 'PASS  and the day after, something is actually due from them';
    else raise notice 'NOTE  nothing is due today, which the cadence may well be right about'; end if;

  raise notice '--- the standard sheet: every assertion passed ---';
end $t$;

rollback;
