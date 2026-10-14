-- A target of zero, and a measure that is met by being small, count in the
-- quarterly bonus
--
-- Found on 30 September and left for the owner, because how a bonus computes
-- is a commercial rule: plb_compute dropped every measure whose target is
-- zero out of Achievement, and then -- rightly -- refused to give an
-- Achievement at all unless the measures it used carried the whole weight.
-- So one "count, target zero" measure ("escalations: 0", "chairs left vacant
-- beyond a quarter: 0") made a whole sheet unpayable. Today that is the Q4
-- sheets of Virendra Pal and Sneha Radhe; fourteen registry chairs carry
-- such a measure.
--
-- The owner has since ruled on exactly this (7 Oct, migration 253): "there is
-- a possibility of 0 in KPIs like 0 escalation but then the one up manager
-- should be adding 0 in the target and not keep it blank." Zero is a promise;
-- null is "nobody has set one". And: direction is the one-up manager's, per
-- KPI. 253 put both into perf_ratio and taught perf_kpi_score and
-- plb_month_suggest to use it. It never reached plb_compute -- the function
-- that turns the quarter into money -- which still divided actual by target
-- whatever the measure was. Measured before this file: 89 of the 201 sheets
-- carry a ceiling measure (work returned for correction, error rate, cost
-- against budget, days to close) that it scored upside down, paying more for
-- a worse number, by up to 9.78 points of Achievement.
--
-- plb_month_suggest had the other half: it skipped a target of 0 as "no
-- target was set for this month" (coalesce(ratio,0) = 0).
--
-- What changes:
--   * plb_compute scores a LOWER measure, and any measure whose target is
--     zero, through perf_ratio -- the one function both other scorers use.
--   * A HIGHER measure with a non-zero target keeps its existing arithmetic,
--     least(actual / target, 1.5), to the last digit. Routing it through
--     perf_ratio as well would move nine sheets by up to 0.002 from
--     perf_ratio's rounding alone, and the payout curve does not move (253).
--   * plb_month_suggest skips only a target that is null.
--
-- Q3 sheets are ISSUED, not locked, and plb_compute is a STABLE read: no
-- amount is stored, so reverting this function reverts every number.
--
-- Written by substitution over the live bodies; raises rather than performing
-- a replace that matches nothing (239's lesson).
do $do$
declare src text; out_src text;
  v_old text := $a$  select sum(g.weight_pct * least(
             case when g.target_value is null or g.target_value = 0 then null
                  else g.actual_value / g.target_value end, 1.5))
           filter (where g.actual_value is not null and g.target_value is not null
                     and g.target_value <> 0),
         sum(g.weight_pct)
           filter (where g.actual_value is not null and g.target_value is not null
                     and g.target_value <> 0),
         sum(g.weight_pct),
         count(*) filter (where g.actual_value is null or g.target_value is null
                             or g.target_value = 0)
    into v_ach, v_weights, v_total, v_missing
    from plb_goal_kpi g where g.sheet_id = p_sheet;$a$;
  v_new text := $b$  -- 260: a ceiling, or a target of zero, through perf_ratio (253's rule);
  -- a plain HIGHER measure keeps its arithmetic exactly, so no sheet moves
  -- by rounding.
  select sum(g.weight_pct * case
             when g.target_value = 0 or perf_direction_of(g.kpi_id, k.unit, g.direction) = 'LOWER'
               then perf_ratio(perf_direction_of(g.kpi_id, k.unit, g.direction),
                               g.target_value, g.actual_value) / 100.0
             else least(g.actual_value / g.target_value, 1.5) end)
           filter (where g.actual_value is not null and g.target_value is not null),
         sum(g.weight_pct)
           filter (where g.actual_value is not null and g.target_value is not null),
         sum(g.weight_pct),
         count(*) filter (where g.actual_value is null or g.target_value is null)
    into v_ach, v_weights, v_total, v_missing
    from plb_goal_kpi g left join kpi_definition k on k.id = g.kpi_id
   where g.sheet_id = p_sheet;$b$;
begin
  select prosrc into src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'plb_compute' and p.pronargs = 1;
  if src is null then raise exception 'Migration 260: plb_compute is not there.'; end if;
  if position('260: a ceiling' in src) > 0 then
    raise notice 'Migration 260: plb_compute already scores through perf_ratio.';
  elsif position(v_old in src) = 0 then
    raise exception 'Migration 260: the Achievement select in plb_compute is not '
                    'where this expects it; a blind replace would be a silent no-op.';
  else
    out_src := replace(src, v_old, v_new);
    execute format('create or replace function public.plb_compute(p_sheet uuid) '
      'returns jsonb language plpgsql stable set search_path to ''public'' as %L', out_src);
  end if;

  select prosrc into src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'plb_month_suggest' and p.pronargs = 3;
  if src is null then raise exception 'Migration 260: plb_month_suggest is not there.'; end if;
  if position('if v is null or ratio is null then' in src) > 0 then
    raise notice 'Migration 260: plb_month_suggest already counts a target of zero.';
  elsif position('if v is null or coalesce(ratio, 0) = 0 then' in src) = 0 then
    raise exception 'Migration 260: the blank test in plb_month_suggest is not where '
                    'this expects it.';
  else
    out_src := replace(src, 'if v is null or coalesce(ratio, 0) = 0 then',
                       'if v is null or ratio is null then  -- 260: zero is a target');
    execute format('create or replace function public.plb_month_suggest('
      'p_actor uuid, p_sheet uuid, p_month date) returns jsonb language plpgsql '
      'stable security definer set search_path to ''public'' as %L', out_src);
  end if;
end
$do$;

-- --------------------------------------------------------------- the proof
-- Against every live sheet: a sheet with no ceiling and no zero target reads
-- exactly what it read before, to the third decimal; one whose ceiling
-- measures are now turned the right way up is counted and named in the
-- notice; and the arithmetic of a zero target is checked on its own.
do $guard$
declare n_same int; n_moved int; n_bad int;
begin
  with g as (
    select g.sheet_id, g.weight_pct w, g.target_value t, g.actual_value a,
           perf_direction_of(g.kpi_id, k.unit, g.direction) dir
      from plb_goal_kpi g left join kpi_definition k on k.id = g.kpi_id),
  s as (
    select sheet_id,
      sum(w * least(a / nullif(t, 0), 1.5)) filter (where a is not null and t is not null and t <> 0) old_v,
      sum(w) filter (where a is not null and t is not null and t <> 0) old_w,
      sum(w) tot,
      bool_or((dir = 'LOWER' or t = 0) and a is not null and t is not null) touched
    from g group by sheet_id),
  r as (
    select s.sheet_id, s.touched,
      case when old_w is null or abs(old_w - tot) > 0.001 then null else round(old_v, 3) end old_ach,
      (plb_compute(s.sheet_id)->>'achievement')::numeric new_ach
    from s)
  select count(*) filter (where not touched and old_ach is not distinct from new_ach),
         count(*) filter (where touched and old_ach is distinct from new_ach),
         count(*) filter (where not touched and old_ach is distinct from new_ach)
    into n_same, n_moved, n_bad from r;
  if n_bad > 0 then
    raise exception 'Migration 260: % sheet(s) with no ceiling and no zero target '
                    'moved. The payout curve does not move.', n_bad;
  end if;
  if perf_ratio('LOWER', 0, 0) <> 100 or perf_ratio('HIGHER', 0, 0) <> 100 then
    raise exception 'Migration 260: a zero target met exactly is not 100%%.';
  end if;
  raise notice 'plb_compute: % sheet(s) read exactly as before; % moved because a '
               'ceiling or a zero target is now scored the right way.', n_same, n_moved;
end $guard$;
