-- =====================================================================
-- 227 · What was filed becomes the month, and the month becomes the quarter
--
-- Asked for: "fix the quarterly score card and monthly Target setting
-- linked with these updatings."
--
-- Until now the two layers did not touch. A person filed a number every
-- working day into perf_entry; then, separately, somebody typed a quarterly
-- actual into plb_goal_kpi.actual_value by hand, and somebody typed a
-- monthly KPI score into plb_month_score.kpi_points by hand. The same
-- quantity, entered twice, from two places, with nothing checking that the
-- two agreed. That is not a link; that is two systems in one database.
--
-- THE DIVIDING LINE
--
-- Facts are computed. Judgements are offered and never taken.
--
--   A quarterly ACTUAL is a fact. It is what the person filed, rolled up
--   over the quarter's three months, by the same arithmetic the daily
--   screen already uses. Nobody should type it and nobody should be able
--   to disagree with it quietly. plb_actual_from_perf() writes it.
--
--   A monthly SCORE is a judgement. The Constitution gives each KPI two
--   points -- 2.0 landed in the month, 1.0 partly or late, 0.0 not -- and
--   "partly or late" is a person's call about a person, not a threshold.
--   plb_month_suggest() computes what the numbers say and shows its
--   working. It writes nothing. A manager reads it and scores.
--
-- Getting that line in the wrong place is how a performance system starts
-- lying. If the tool scored people automatically, the score would be the
-- tool's opinion wearing a manager's name; if the tool made somebody
-- re-type an actual it already holds, the two copies would differ within a
-- quarter and the argument would be about which screen to believe.
--
-- HOW A QUARTER FINDS ITS NUMBERS
--
-- plb_goal_kpi carries kpi_id, and so does perf_assignment. That is the
-- whole join. For each KPI on the sheet, every assignment the same person
-- holds for the same measure in any monthly cycle inside the quarter is
-- rolled up -- summed where the measure is a count, averaged where it is a
-- percentage, which is what perf_accrual_kind has always decided and what
-- perf_value already does inside a month.
--
-- Where a measure has nothing filed, the actual is left ALONE rather than
-- written as zero. A zero that means "nobody filed" and a zero that means
-- "they achieved nothing" are different facts, and the second one is the
-- only one that should ever reduce somebody's pay.
--
-- THE FREEZE IS RESPECTED
--
-- plb_actual_set refuses once plb_result.data_frozen_at is set, and this
-- refuses in the same words. A quarter whose data is frozen is frozen
-- against arithmetic as well as against typing -- otherwise the freeze
-- would only stop the honest route.
-- =====================================================================

-- ------------------------------------------- the quarter's three months
create or replace function plb_quarter_cycles(p_quarter date)
returns setof uuid
language sql
stable
set search_path to 'public'
as $function$
  select c.id from perf_cycle c
   where c.period_kind = 'MONTH'
     and c.period_start >= date_trunc('quarter', p_quarter)::date
     and c.period_start <  (date_trunc('quarter', p_quarter) + interval '3 months')::date
   order by c.period_start
$function$;

comment on function plb_quarter_cycles(date) is
  'The monthly cycles inside one quarter. A quarter is three months of '
  'daily filing, and this is how the quarterly sheet reaches them.';

-- --------------------------------- what one person filed, over a quarter
--
-- Summed where the measure counts, averaged where it is a level -- the
-- same question perf_accrual_kind answers inside a single month, asked
-- again across three of them. Returns null, never zero, when nothing was
-- filed at all.
create or replace function perf_quarter_value(p_person uuid, p_kpi uuid, p_quarter date)
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
   limit 1;
  if v_kind is null then return null; end if;

  if v_kind = 'SUM' then
    select sum(perf_value(a.id)) into v
      from perf_assignment a
     where a.person_id = p_person and a.kpi_id = p_kpi
       and a.part_of_id is null
       and a.cycle_id in (select plb_quarter_cycles(p_quarter));
  else
    -- A percentage across three months is the average of the months that
    -- have one, not of three months two of which are silent.
    select avg(x) into v from (
      select perf_value(a.id) as x
        from perf_assignment a
       where a.person_id = p_person and a.kpi_id = p_kpi
         and a.part_of_id is null
         and a.cycle_id in (select plb_quarter_cycles(p_quarter))) q
     where x is not null;
  end if;
  return v;
end $function$;

comment on function perf_quarter_value(uuid,uuid,date) is
  'What one person actually filed against one measure across a quarter: '
  'summed if it counts, averaged if it is a level. Null when nothing was '
  'filed, because a zero that means "nobody filed" and a zero that means '
  '"they achieved nothing" are different facts.';

-- ----------------------------------- the quarterly actuals, from the filings
create or replace function plb_actual_from_perf(p_actor uuid, p_sheet uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  s plb_goal_sheet; v_rel text; v_frozen timestamptz;
  r record; v numeric; v_set int := 0; v_blank int := 0;
  v_rows jsonb := '[]'::jsonb;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;

  v_rel := perf_rel(p_actor, s.person_id);
  if v_rel not in ('manage','admin') then
    return jsonb_build_object('error','not_permitted',
      'reason','Pulling a quarter''s actuals is the reporting manager''s, or '
               'an administrator''s. You may read the sheet either way.');
  end if;

  select data_frozen_at into v_frozen from plb_result where sheet_id = p_sheet;
  if v_frozen is not null then
    return jsonb_build_object('error','frozen',
      'reason','The KPI source data for that quarter is frozen.');
  end if;

  for r in
    select gk.kpi_id, k.name, k.unit, gk.target_value, gk.actual_value
      from plb_goal_kpi gk
      join kpi_definition k on k.id = gk.kpi_id
     where gk.sheet_id = p_sheet
     order by k.position, k.name
  loop
    v := perf_quarter_value(s.person_id, r.kpi_id, s.quarter);

    if v is null then
      v_blank := v_blank + 1;
      v_rows := v_rows || jsonb_build_object(
        'name', r.name, 'unit', r.unit, 'target', r.target_value,
        'actual', r.actual_value, 'filled', false,
        'why', 'nothing was filed against this measure in the quarter, so the '
               'actual is left as it was rather than written as a zero');
    else
      update plb_goal_kpi set actual_value = v
       where sheet_id = p_sheet and kpi_id = r.kpi_id;
      v_set := v_set + 1;
      v_rows := v_rows || jsonb_build_object(
        'name', r.name, 'unit', r.unit, 'target', r.target_value,
        'was', r.actual_value, 'actual', v, 'filled', true,
        'pct', case when coalesce(r.target_value,0) = 0 then null
                    else round(100.0 * v / r.target_value, 1) end);
    end if;
  end loop;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'PLB_ACTUALS_FROM_FILINGS', 'plb_goal_sheet', p_sheet::text,
          jsonb_build_object('quarter', s.quarter, 'set', v_set, 'blank', v_blank));

  return jsonb_build_object('ok', true, 'set', v_set, 'blank', v_blank,
    'rows', v_rows,
    'note', v_set || ' actual(s) taken from what was filed day by day' ||
            case when v_blank > 0
                 then ', and ' || v_blank || ' left alone because nothing was filed against them'
                 else '' end || '.');
end $function$;

comment on function plb_actual_from_perf(uuid,uuid) is
  'Fills a quarterly goal sheet''s actuals from what the person filed daily, '
  'by the same arithmetic the daily screen uses. A fact, so it writes. '
  'Leaves a measure with no filings alone rather than writing a zero.';

-- ------------------------------------------ the month's points, suggested
--
-- The Constitution gives each KPI two points: 2.0 landed in the month,
-- 1.0 partly or late, 0.0 not. This computes what the numbers say and
-- SHOWS ITS WORKING. It writes nothing at all.
--
-- The thresholds are stated here rather than hidden: at or past target is
-- two, at least half way is one, below that is nothing. A manager who
-- disagrees is not overriding the tool -- they are doing the job, and the
-- suggestion exists so that they start from the numbers instead of from
-- memory.
create or replace function plb_month_suggest(p_actor uuid, p_sheet uuid, p_month date)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  s plb_goal_sheet; v_rel text; c perf_cycle;
  r record; v numeric; ratio numeric; pts numeric;
  v_sum numeric := 0; v_n int := 0; v_blank int := 0;
  v_rows jsonb := '[]'::jsonb; v_now jsonb;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;

  v_rel := perf_rel(p_actor, s.person_id);
  if v_rel is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That person is not in your line.');
  end if;

  select * into c from perf_cycle
   where period_kind = 'MONTH'
     and period_start = date_trunc('month', p_month)::date;
  if c.id is null then
    return jsonb_build_object('error','no_such_cycle',
      'reason','No monthly cycle has been opened for ' ||
               to_char(date_trunc('month', p_month), 'Mon YYYY') || '.');
  end if;

  for r in
    select gk.kpi_id, k.name, k.unit, gk.weight_pct
      from plb_goal_kpi gk
      join kpi_definition k on k.id = gk.kpi_id
     where gk.sheet_id = p_sheet
     order by k.position, k.name
  loop
    select perf_value(a.id), a.target_value into v, ratio
      from perf_assignment a
     where a.person_id = s.person_id and a.kpi_id = r.kpi_id
       and a.cycle_id = c.id and a.part_of_id is null
     limit 1;

    if v is null or coalesce(ratio, 0) = 0 then
      v_blank := v_blank + 1;
      v_rows := v_rows || jsonb_build_object(
        'name', r.name, 'unit', r.unit, 'points', null, 'counted', false,
        'why', case when v is null then 'nothing filed in this month'
                    else 'no target was set for this month' end);
      continue;
    end if;

    -- A ceiling measure is met by being small. Turning it the right way up
    -- here rather than in the caller is the difference between rewarding a
    -- low error rate and punishing it.
    ratio := case when perf_direction(r.unit) = 'CEILING'
                  then case when v = 0 then 150 else least(150, round(100.0 * ratio / v, 2)) end
                  else least(150, round(100.0 * v / ratio, 2)) end;

    pts := case when ratio >= 100 then 2.0
                when ratio >= 50  then 1.0
                else 0.0 end;

    v_sum := v_sum + pts; v_n := v_n + 1;
    v_rows := v_rows || jsonb_build_object(
      'name', r.name, 'unit', r.unit, 'value', v,
      'pct', ratio, 'points', pts, 'counted', true,
      'why', case when pts = 2 then 'at or past the target'
                  when pts = 1 then 'part of the way there'
                  else 'short of half the target' end);
  end loop;

  select jsonb_build_object('kpiPoints', ms.kpi_points, 'attrPoints', ms.attr_points,
                            'monthlyScore', ms.monthly_score,
                            'lockedAt', ms.locked_at, 'scoredAt', ms.scored_at)
    into v_now
    from plb_month_score ms
   where ms.sheet_id = p_sheet and ms.month = date_trunc('month', p_month)::date;

  return jsonb_build_object(
    'month', date_trunc('month', p_month)::date,
    'rel', v_rel,
    'maySet', v_rel in ('manage','admin'),
    'measures', v_rows,
    'counted', v_n, 'blank', v_blank,
    -- Out of ten, because the Constitution's KPI half is scored out of ten
    -- and the arithmetic downstream expects it that way.
    'suggested', case when v_n = 0 then null
                      else round(10.0 * v_sum / (2.0 * v_n), 2) end,
    'now', v_now,
    'says', case
      when v_n = 0 then 'Nothing can be suggested: no measure has both a target and a number this month.'
      else 'Suggested from ' || v_n || ' measure(s) with a target and a number' ||
           case when v_blank > 0 then ', ' || v_blank || ' left out and each one says why' else '' end ||
           '. This is what the filings say. The score is yours.' end,
    'note', 'Two points a measure: at or past the target is two, at least '
            'half way is one, short of that is none. Nothing here has been '
            'written -- it is a reading of the month, not a verdict on it.');
end $function$;

comment on function plb_month_suggest(uuid,uuid,date) is
  'What the daily filings say one month of a goal sheet is worth, out of '
  'ten, with the arithmetic shown per measure. Writes nothing: a monthly '
  'score is a judgement, and the suggestion exists so a manager starts '
  'from the numbers rather than from memory.';

revoke all on function plb_quarter_cycles(date)             from public, anon, authenticated;
revoke all on function perf_quarter_value(uuid,uuid,date)   from public, anon, authenticated;
revoke all on function plb_actual_from_perf(uuid,uuid)      from public, anon, authenticated;
revoke all on function plb_month_suggest(uuid,uuid,date)    from public, anon, authenticated;
