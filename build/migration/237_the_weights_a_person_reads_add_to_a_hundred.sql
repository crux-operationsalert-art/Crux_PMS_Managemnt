-- The weights a person reads add to a hundred (237)
--
-- Two things a systematic sweep found, both small, one of them mine.
--
-- ONE. perf_assignment.weight_pct does not add to 100 for 92 of the 101
-- people who have measures. Sixty-three of them carry three measures whose
-- weights add to 1.59 -- 0.53 each.
--
-- The scores are NOT wrong. plb_month_suggest uses these as a weighted mean:
--
--     wsum := wsum + ratio * coalesce(r.weight_pct, 1);
--     w    := w + coalesce(r.weight_pct, 1);
--
-- and a weighted mean does not care about the scale of its weights, only
-- their ratios. Three equal weights give the same answer at 0.53 as at 33.3.
--
-- What IS wrong is the screen. Performance and appraisal prints the weight
-- beside each measure, so a person looks at three KPIs that between them
-- decide their bonus and reads "weight 0.53%" on each. That is not a rounding
-- artefact a reader can shrug off; it is a number that says the measure
-- barely counts, against a scheme document that says it counts for a third.
--
-- So this rescales each person's weights within each cycle to add to 100,
-- preserving every ratio exactly. The guard proves the scores did not move by
-- computing a weighted mean before and after and requiring it unchanged --
-- which is the only claim that matters and the only one worth asserting.
--
-- TWO. person_welcome_on_create, the trigger function added in 236, was left
-- executable by anon. Migration 228 took thirty such functions down to five
-- and named which five were deliberate; this made it six the same afternoon.
-- It is not reachable in practice -- Postgres refuses to call a trigger
-- function outside a trigger -- but "not currently exploitable" is a weaker
-- claim than "not granted", and the five that remain were each argued for.

-- ------------------------------------------------- one: the weights
-- The snapshot, the rescale and the proof that no score moved are one block,
-- so this holds whether or not the file is applied inside a transaction. A
-- guard that depends on a temp table surviving a commit is a guard that
-- quietly stops guarding.
do $weights$
declare
  r record; n_people int := 0; n_moved int := 0;
  before_wm jsonb := '{}'::jsonb; k text; v numeric;
begin
  -- Before: a weighted mean per person-cycle, standing in for any weighted
  -- mean the scheme computes over these rows.
  for r in
    select a.person_id::text || '|' || a.cycle_id::text as key,
           sum(a.target_value * a.weight_pct)
             / nullif(sum(a.weight_pct), 0) as wm
      from perf_assignment a
     where a.part_of_id is null and a.target_value is not null
     group by a.person_id, a.cycle_id
  loop
    before_wm := before_wm || jsonb_build_object(r.key, r.wm);
  end loop;

  for r in
    select a.person_id, a.cycle_id, sum(a.weight_pct) as total
      from perf_assignment a
     where a.part_of_id is null
     group by a.person_id, a.cycle_id
    having sum(a.weight_pct) is not null
       and sum(a.weight_pct) <> 0
       and abs(sum(a.weight_pct) - 100) > 0.01
  loop
    update perf_assignment a
       set weight_pct = round(a.weight_pct * 100.0 / r.total, 2)
     where a.person_id = r.person_id and a.cycle_id = r.cycle_id
       and a.part_of_id is null;
    n_people := n_people + 1;
  end loop;

  -- The claim that matters: no weighted mean moved. If one did, the rescale
  -- was not proportional and somebody's score has changed.
  for r in
    select a.person_id::text || '|' || a.cycle_id::text as key,
           sum(a.target_value * a.weight_pct)
             / nullif(sum(a.weight_pct), 0) as wm
      from perf_assignment a
     where a.part_of_id is null and a.target_value is not null
     group by a.person_id, a.cycle_id
  loop
    v := (before_wm->>r.key)::numeric;
    if v is null or abs(v - r.wm) > 0.0001 then
      n_moved := n_moved + 1;
    end if;
  end loop;

  if n_moved > 0 then
    raise exception 'Migration 237 moved % weighted mean(s). The rescale was '
                    'not proportional and a score has changed.', n_moved;
  end if;

  raise notice 'rescaled % person-cycle(s); no weighted mean moved', n_people;
end $weights$;

-- ------------------------------------------- two: the trigger function
revoke execute on function person_welcome_on_create() from public, anon, authenticated;

-- ------------------------------------------------------------- the guard
do $guard$
declare n int;
begin
  select count(*) into n from (
    select a.person_id from perf_assignment a
     where a.part_of_id is null
     group by a.person_id, a.cycle_id
    having sum(a.weight_pct) is not null and sum(a.weight_pct) <> 0
       and abs(sum(a.weight_pct) - 100) > 0.05) y;
  if n > 0 then
    raise exception 'Migration 237 left % person-cycle(s) not adding to 100', n;
  end if;

  if has_function_privilege('anon', 'person_welcome_on_create()', 'EXECUTE') then
    raise exception 'Migration 237 did not take the trigger function off anon';
  end if;

  -- Back to the five that 228 argued for, and no more.
  select count(*) into n from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.prosecdef
     and has_function_privilege('anon', p.oid, 'EXECUTE');
  if n <> 5 then
    raise exception 'Migration 237: % SECURITY DEFINER functions are callable '
                    'by anon, expected the 5 that 228 kept on purpose', n;
  end if;

  raise notice 'weights add to 100, no score moved, anon is back to five';
end $guard$;
