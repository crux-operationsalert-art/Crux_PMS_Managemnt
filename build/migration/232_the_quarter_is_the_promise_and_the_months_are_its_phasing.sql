-- =====================================================================
-- 232 · The quarter is the promise; the months are how it is phased
--
-- Found by tracing the target flow end to end after "I don't think it's
-- correct". It is not correct, and this is what is wrong:
--
--   A TARGET IS STORED TWICE AND NOTHING CONNECTS THE TWO.
--
--     perf_assignment.target_value          the monthly target
--     plb_goal_kpi.target_value             the quarterly target
--     plb_goal_kpi.m1_share/m2/m3           its split across the months
--
-- perf_seed_targets fills the first from the registry. plb_sheet_issue
-- fills the second from WHATEVER THE CALLER TYPES -- it never reads the
-- monthly targets, and no function in the database compares them. Of every
-- function that touches plb_goal_kpi, exactly one also touches
-- perf_assignment, and it reads them independently.
--
-- So a person can hold a monthly target of 100 cases and a quarterly
-- target of 250. Both are "valid". The monthly score out of ten is
-- computed against the first and the quarterly scorecard against the
-- second, and nobody is told the two disagree. That is a performance
-- system quietly keeping two sets of books.
--
-- WHICH ONE IS THE TRUTH
--
-- The quarter. PLB is earned and paid quarterly, so the quarterly number
-- is the commitment a person is actually held to; the months are how that
-- commitment is spread so somebody can be asked for a number in March
-- rather than only on the last day of the quarter. m1_share, m2_share and
-- m3_share already exist on the goal sheet to say exactly this, and
-- nothing ever wrote them.
--
-- THE SAME RULE, A THIRD TIME
--
-- A count divides and a percentage is copied. That is already the rule
-- for a target coming DOWN to a team (223) and ACROSS to clients (230).
-- A quarter spread ACROSS ITS MONTHS is the same act on a third axis, so
-- it is the same arithmetic: 300 cases a quarter is 100 a month, and a
-- 95% quality target is 95% in each of the three months, not 31.67%.
--
-- WHAT IS NEVER OVERWRITTEN
--
-- A monthly target whose target_source is MANUAL was agreed by a person.
-- Phasing leaves it alone and says so, exactly as the team cascade does.
-- The arithmetic gives way to the agreement, never the other way round.
-- =====================================================================

-- ------------------------------------------- what the months actually say
-- The other direction: given the monthly targets that exist, what quarter
-- do they add up to? Used to seed a first sheet from data already there,
-- and to report a disagreement.
create or replace function plb_quarter_from_months(p_person uuid, p_kpi uuid,
                                                   p_quarter date)
returns numeric
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_kind text; v numeric;
begin
  select perf_accrual_kind(a.kpi_id, a.unit) into v_kind
    from perf_assignment a
   where a.person_id = p_person and a.kpi_id = p_kpi
     and a.cycle_id in (select plb_quarter_cycles(p_quarter))
     and a.part_of_id is null
   limit 1;
  if v_kind is null then return null; end if;

  if v_kind = 'SUM' then
    select sum(a.target_value) into v from perf_assignment a
     where a.person_id = p_person and a.kpi_id = p_kpi
       and a.part_of_id is null
       and a.cycle_id in (select plb_quarter_cycles(p_quarter));
  else
    -- A level is not added across months. Three months at 95% is a 95%
    -- quarter, not a 285% one.
    select avg(a.target_value) into v from perf_assignment a
     where a.person_id = p_person and a.kpi_id = p_kpi
       and a.part_of_id is null and a.target_value is not null
       and a.cycle_id in (select plb_quarter_cycles(p_quarter));
  end if;
  return v;
end $function$;

comment on function plb_quarter_from_months(uuid,uuid,date) is
  'What the monthly targets for one measure add up to across a quarter: '
  'summed if it counts, averaged if it is a level. The inverse of phasing, '
  'used to seed a first goal sheet from targets that already exist.';

-- ----------------------------------------------- do the two agree at all
-- The report the audit wanted: per measure, the quarterly promise beside
-- what the months are actually asking for.
create or replace function plb_target_agreement(p_actor uuid, p_sheet uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare s plb_goal_sheet; v_rows jsonb := '[]'::jsonb; v_off int := 0; r record;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;
  if perf_rel(p_actor, s.person_id) is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That person is not in your line.');
  end if;

  for r in
    select gk.kpi_id, k.name, k.unit, gk.target_value as quarterly,
           plb_quarter_from_months(s.person_id, gk.kpi_id, s.quarter) as monthly,
           perf_accrual_kind(k.id, k.unit) as kind
      from plb_goal_kpi gk join kpi_definition k on k.id = gk.kpi_id
     where gk.sheet_id = p_sheet
     order by k.position, k.name
  loop
    -- Rounded to two places before comparing: a third of 100 is 33.33
    -- three times over, and 99.99 against 100 is agreement, not a fault.
    if r.quarterly is not null and r.monthly is not null
       and round(r.quarterly, 2) <> round(r.monthly, 2) then
      v_off := v_off + 1;
    end if;
    v_rows := v_rows || jsonb_build_object(
      'kpiId', r.kpi_id, 'name', r.name, 'unit', r.unit, 'kind', r.kind,
      'quarterly', r.quarterly, 'monthly', r.monthly,
      'agrees', case when r.quarterly is null or r.monthly is null then null
                     else round(r.quarterly,2) = round(r.monthly,2) end,
      'why', case
        when r.quarterly is null then 'no quarterly target has been set'
        when r.monthly is null then 'no monthly target exists for this measure'
        when round(r.quarterly,2) = round(r.monthly,2) then null
        when r.kind = 'SUM' then 'the months add to ' || r.monthly ||
             ' against a quarter of ' || r.quarterly
        else 'the months average ' || r.monthly ||
             ' against a quarter of ' || r.quarterly end);
  end loop;

  return jsonb_build_object(
    'sheetId', p_sheet, 'quarter', s.quarter,
    'measures', v_rows, 'disagree', v_off,
    'mayPhase', perf_may_set(p_actor, s.person_id),
    'note', case when v_off = 0
      then 'Every measure''s months agree with its quarter.'
      else v_off || ' measure(s) are asking for one thing every month and '
           'promising another for the quarter. Phasing the quarter down '
           'fixes it, and leaves alone anything a person agreed by hand.' end);
end $function$;

comment on function plb_target_agreement(uuid,uuid) is
  'Per measure: the quarterly target beside what its monthly targets add '
  'up to, and whether they agree. A performance system holding two '
  'different numbers for the same promise is the fault this reports.';

-- ------------------------------------------------- push the quarter down
create or replace function plb_phase_targets(p_actor uuid, p_sheet uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  s plb_goal_sheet; r record; c record;
  v_cycles uuid[]; v_n int; v_share numeric; v_kind text;
  v_set int := 0; v_pinned int := 0; v_blank int := 0; v_rows jsonb := '[]'::jsonb;
  v_shares numeric[]; i int;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;

  if not perf_may_set(p_actor, s.person_id) then
    return jsonb_build_object('error','not_permitted',
      'reason','Phasing a quarter into months sets somebody''s targets, and '
               'belongs to the person they report to.');
  end if;
  if s.status = 'LOCKED' then
    return jsonb_build_object('error','locked',
      'reason','That goal sheet is locked.');
  end if;

  select array_agg(q order by q) into v_cycles
    from plb_quarter_cycles(s.quarter) q;
  v_n := coalesce(array_length(v_cycles,1), 0);
  if v_n = 0 then
    return jsonb_build_object('error','no_cycles',
      'reason','No monthly period has been opened inside that quarter, so '
               'there is nothing to phase the target into.');
  end if;

  for r in
    select gk.kpi_id, gk.target_value, k.name, k.unit,
           perf_accrual_kind(k.id, k.unit) as kind
      from plb_goal_kpi gk join kpi_definition k on k.id = gk.kpi_id
     where gk.sheet_id = p_sheet
     order by k.position, k.name
  loop
    if r.target_value is null then
      v_blank := v_blank + 1;
      v_rows := v_rows || jsonb_build_object('name', r.name, 'set', 0,
        'why','no quarterly target to phase');
      continue;
    end if;

    -- The same rule a third time: a count divides, a level is copied.
    if r.kind = 'SUM' then
      v_share := round(r.target_value / v_n, 2);
    else
      v_share := r.target_value;
    end if;

    -- The three share columns are NOT NULL and default to zero, so a
    -- quarter with fewer than three months open writes zero for the
    -- months that do not exist. Zero is the honest value: there is no
    -- cycle to ask anybody for a number in.
    v_shares := '{}';
    for i in 1..3 loop
      v_shares := v_shares || case when i <= v_n then v_share else 0 end;
    end loop;
    update plb_goal_kpi
       set m1_share = v_shares[1], m2_share = v_shares[2], m3_share = v_shares[3]
     where sheet_id = p_sheet and kpi_id = r.kpi_id;

    -- Write each month's assignment, except where somebody agreed one by
    -- hand. The arithmetic gives way to the agreement.
    for c in
      select a.id, a.target_source
        from perf_assignment a
       where a.person_id = s.person_id and a.kpi_id = r.kpi_id
         and a.part_of_id is null
         and a.cycle_id = any(v_cycles)
    loop
      if c.target_source = 'MANUAL' then
        v_pinned := v_pinned + 1;
      else
        update perf_assignment
           set target_value = v_share, target_source = 'SHARED'
         where id = c.id;
        v_set := v_set + 1;
      end if;
    end loop;

    v_rows := v_rows || jsonb_build_object(
      'name', r.name, 'kind', r.kind, 'quarterly', r.target_value,
      'eachMonth', v_share, 'months', v_n,
      'divides', r.kind = 'SUM');
  end loop;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor,'PLB_TARGETS_PHASED','plb_goal_sheet', p_sheet::text,
          jsonb_build_object('set', v_set, 'pinned', v_pinned,
                             'months', v_n, 'quarter', s.quarter));

  return jsonb_build_object('ok', true,
    'months', v_n, 'set', v_set, 'leftPinned', v_pinned, 'noTarget', v_blank,
    'measures', v_rows,
    'note', v_set || ' monthly target(s) now come from the quarter' ||
      case when v_pinned > 0
           then ', and ' || v_pinned || ' agreed by hand were left alone'
           else '' end ||
      case when v_n < 3
           then '. Only ' || v_n || ' month(s) of that quarter are open, so the '
                'target divided across those.'
           else '.' end);
end $function$;

comment on function plb_phase_targets(uuid,uuid) is
  'Spreads a quarterly goal-sheet target across the months of its quarter '
  'and writes each month''s perf_assignment target from it, so the two '
  'stores hold one number rather than two. A count divides and a level is '
  'copied, as everywhere else. A monthly target agreed by hand is left.';

-- ------------------------------------- issue a sheet from what exists
-- The first sheet has no quarterly targets to phase, and inventing them
-- would be worse than having none. The monthly targets DO exist -- seeded
-- from the registry by 224 -- so the quarter is read off them.
create or replace function plb_sheet_from_perf(p_actor uuid, p_person uuid,
                                               p_quarter date,
                                               p_plb_inr numeric default 0)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_sheet uuid; o jsonb; r record; v_n int := 0; v numeric; a person;
begin
  select * into a from person where id = p_actor
     and employment_status = 'ACTIVE' and superseded_by is null;

  -- Running the scheme is HR's and Business Excellence's; managing the
  -- person is their manager's. Either may issue a sheet, which is the set
  -- plb_sheet_issue has always served. Gating this on perf_may_set alone
  -- would have stopped HR doing their own job.
  if not (perf_may_set(p_actor, p_person)
          or a.app_role = 'ADMIN'
          or coalesce(a.department,'') in ('Human Resources','Business Excellence')) then
    return jsonb_build_object('error','not_permitted',
      'reason','Issuing somebody''s goal sheet belongs to the person they '
               'report to, or to HR.');
  end if;
  if p_actor = p_person then
    return jsonb_build_object('error','not_permitted',
      'reason','Nobody issues their own goal sheet.');
  end if;

  -- Issue it empty, so the registry decides the measures and the weights.
  o := plb_sheet_issue(p_actor, p_person, p_quarter, p_plb_inr,
                       '[]'::jsonb, false);
  if o->>'error' is not null then return o; end if;
  v_sheet := (o->>'sheetId')::uuid;

  for r in select gk.kpi_id from plb_goal_kpi gk where gk.sheet_id = v_sheet loop
    v := plb_quarter_from_months(p_person, r.kpi_id,
                                 date_trunc('quarter', p_quarter)::date);
    if v is not null then
      update plb_goal_kpi set target_value = v
       where sheet_id = v_sheet and kpi_id = r.kpi_id;
      v_n := v_n + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'sheetId', v_sheet, 'fromMonths', v_n,
    'note', v_n || ' quarterly target(s) read off the monthly targets that '
            'already existed, rather than typed in again. Where the months '
            'said nothing, the quarter is left blank.');
end $function$;

comment on function plb_sheet_from_perf(uuid,uuid,date,numeric) is
  'Issues a goal sheet whose quarterly targets are read off the monthly '
  'targets already seeded, so the first sheet starts in agreement with the '
  'months instead of being retyped and drifting from them.';

revoke all on function plb_quarter_from_months(uuid,uuid,date)   from public, anon, authenticated;
revoke all on function plb_target_agreement(uuid,uuid)           from public, anon, authenticated;
revoke all on function plb_phase_targets(uuid,uuid)              from public, anon, authenticated;
revoke all on function plb_sheet_from_perf(uuid,uuid,date,numeric) from public, anon, authenticated;
