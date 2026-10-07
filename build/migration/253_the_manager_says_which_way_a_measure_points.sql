-- The manager says which way a measure points (253)
--
-- "lower or higher depends on the KPI for some KPIs it would be higher and
--  some KPI it would be lower, which would be defined by the one up manager
--  along with the KPI, we only suggest that xyz KPI can be given then the one
--  up manager decides and edits as per the requirement and even change or add
--  a new new KPI or reterm any"
-- "There will never be 0 KPI, one up manager if has assigned a KPI should be
--  assigning the target too. Yes there is a possibility of 0 in KPIs like 0
--  escalation but then the one up manager should be adding 0 in the target
--  and not keep it blank."
--
-- Two answers, and both of them say the same thing about where a judgement
-- belongs: with the manager who set the measure, not with a rule the tool
-- inferred.
--
-- ------------------------------------------------------- WHICH WAY IT POINTS
--
-- Today the tool GUESSES. perf_direction reads the unit text and decides
-- CEILING if it looks like a ceiling -- so "Escalation ratio, target below 2%
-- · D1" is scored one way and "% of cases escalated" might be scored the
-- other, on the strength of how somebody worded a unit. 181 goal KPIs are
-- scored so that a worse number pays more, and that is what the guess costs.
--
-- The owner's answer is that it is not a guess at all: the registry SUGGESTS
-- and the one-up manager DECIDES, alongside the target, when they set the
-- measure. So direction becomes a value somebody sets:
--
--   kpi_definition.direction   what the registry suggests
--   perf_assignment.direction  what the manager decided, this month
--   plb_goal_kpi.direction     what the manager decided, this quarter
--
-- Null on an assignment means "as the measure suggests", so nothing has to
-- be re-entered for a measure nobody disagrees with, and perf_direction's
-- guess survives exactly one more hop: as the seed for the registry column,
-- once, below. After that nothing reads a unit string to decide what a
-- number means.
--
-- --------------------------------------------------------- A TARGET OF ZERO
--
-- perf_kpi_score has always read `coalesce(r.target_value, 0) = 0` as "no
-- target was set" and dropped the measure out of the score. That makes a
-- target of zero unsayable -- and zero escalations is the clearest target in
-- the whole scheme.
--
-- Null and zero stop being the same thing. Null is "nobody has set one yet",
-- which is still not scored and still says so. Zero is a promise, and it is
-- scored like any other: met if the actual is zero, missed if it is not.
--
-- -------------------------------------------------------- WHAT DOES NOT MOVE
--
-- The payout curve. Every case that scores today scores the same number
-- afterwards: the over-achievement formula is carried across unchanged and
-- the cap is still 150. What changes is which measures are turned the right
-- way up, and whether a zero can be promised at all. Changing the curve as
-- well would have made it impossible to tell the correction from the change.

-- =====================================================================
-- The column, in three places.
-- =====================================================================
alter table kpi_definition  add column if not exists direction text;
alter table perf_assignment add column if not exists direction text;
alter table plb_goal_kpi    add column if not exists direction text;

do $do$
begin
  if not exists (select 1 from pg_constraint where conname = 'kpi_definition_direction_check') then
    alter table kpi_definition add constraint kpi_definition_direction_check
      check (direction is null or direction in ('HIGHER','LOWER'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'perf_assignment_direction_check') then
    alter table perf_assignment add constraint perf_assignment_direction_check
      check (direction is null or direction in ('HIGHER','LOWER'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'plb_goal_kpi_direction_check') then
    alter table plb_goal_kpi add constraint plb_goal_kpi_direction_check
      check (direction is null or direction in ('HIGHER','LOWER'));
  end if;
end
$do$;

comment on column kpi_definition.direction is
  'What the registry SUGGESTS: HIGHER when a bigger number is better, LOWER '
  'when a smaller one is. The one-up manager decides per person on the '
  'assignment; this is only the suggestion they start from.';
comment on column perf_assignment.direction is
  'What the manager decided for this person this month. Null means "as the '
  'measure suggests", so a measure nobody disagrees with needs no answer.';

-- The guess, used once, as the seed. After this nothing reads a unit string
-- to decide what a number means.
update kpi_definition k
   set direction = case when perf_direction(k.unit) = 'CEILING' then 'LOWER'
                        else 'HIGHER' end
 where k.direction is null;

-- =====================================================================
-- One formula, in one place.
--
-- Both scorers had their own copy and the copies disagreed: perf_kpi_score
-- never looked at direction at all, and plb_month_suggest looked at the unit
-- string. A number that decides somebody's bonus should be worked out once.
-- =====================================================================
create or replace function perf_ratio(p_direction text, p_target numeric,
                                      p_actual numeric)
returns numeric
language sql
immutable
as $$
  select case
    -- Nothing to compare. Null is NOT zero: null is "nobody set one yet" and
    -- the caller says so; zero is a promise and is scored below.
    when p_target is null or p_actual is null then null

    when coalesce(p_direction,'HIGHER') = 'LOWER' then
      case
        -- "Zero escalations." Met exactly, or not met at all; there is no
        -- beating zero, so meeting it is a hundred and not the cap.
        when p_target = 0 then case when p_actual = 0 then 100 else 0 end
        -- Over the ceiling, or under it. The formula above the line is the
        -- one that was there before, carried across unchanged so that every
        -- case which scores today scores the same number afterwards.
        when p_actual = 0 then 150
        else least(150, round(100.0 * p_target / p_actual, 2))
      end

    else
      case
        -- Asked for nothing and delivered something. Met at worst.
        when p_target = 0 then case when p_actual > 0 then 150 else 100 end
        else least(150, round(100.0 * p_actual / p_target, 2))
      end
  end;
$$;

comment on function perf_ratio(text, numeric, numeric) is
  'How a number reads against its target, as a percentage capped at 150. '
  'LOWER is a ceiling -- zero escalations against a target of zero is a '
  'hundred, not a bonus. A null target is "nobody set one"; a target of zero '
  'is a promise.';

-- Which way THIS measure points for THIS person: what the manager decided,
-- else what the registry suggests, else the old guess from the unit.
create or replace function perf_direction_of(p_kpi uuid, p_unit text,
                                             p_override text default null)
returns text
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(
    nullif(btrim(coalesce(p_override,'')),''),
    (select k.direction from kpi_definition k where k.id = p_kpi),
    case when perf_direction(p_unit) = 'CEILING' then 'LOWER' else 'HIGHER' end);
$$;

-- =====================================================================
-- The monthly score.
--
-- By substitution over the live body, so the parts nobody is changing cannot
-- drift while being retyped.
-- =====================================================================
do $do$
declare src text; out_src text;
  a1 text := '    if coalesce(r.target_value, 0) = 0 or v is null then';
  a2 text := '      ratio := least(150, round(100.0 * v / r.target_value, 2));';
begin
  select prosrc into src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'perf_kpi_score';
  if src is null then
    raise exception 'Migration 253: perf_kpi_score is not there to change.';
  end if;
  if position('perf_ratio(' in src) > 0 then
    raise notice 'Migration 253: perf_kpi_score already uses perf_ratio.';
    return;
  end if;
  if position(a1 in src) = 0 or position(a2 in src) = 0 then
    raise exception 'Migration 253: perf_kpi_score does not look as this '
                    'expects, so a blind replace would be a silent no-op.';
  end if;

  -- Null is unset; zero is a promise.
  out_src := replace(src, a1,
    '    if r.target_value is null or v is null then');
  out_src := replace(out_src,
    'case when coalesce(r.target_value, 0) = 0 then ''no target was set'' end',
    'case when r.target_value is null then ''no target has been set yet'' end');
  -- And the direction the manager chose.
  out_src := replace(out_src, a2,
    '      ratio := perf_ratio(perf_direction_of(r.kpi_id, r.unit, r.direction),'
    || chr(10) || '                          r.target_value, v);');

  execute 'create or replace function perf_kpi_score(p_person uuid, p_cycle uuid) '
       || 'returns jsonb language plpgsql stable security definer '
       || 'set search_path to ''public'' as ' || quote_literal(out_src);
end
$do$;

-- =====================================================================
-- The month the quarterly card suggests.
-- =====================================================================
do $do$
declare src text; out_src text;
  a text := '    ratio := case when perf_direction(r.unit) = ''CEILING''';
begin
  select prosrc into src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'plb_month_suggest';
  if src is null then
    raise exception 'Migration 253: plb_month_suggest is not there to change.';
  end if;
  if position('perf_ratio(' in src) > 0 then
    raise notice 'Migration 253: plb_month_suggest already uses perf_ratio.';
    return;
  end if;
  if position(a in src) = 0 then
    raise exception 'Migration 253: the ratio in plb_month_suggest is not where '
                    'this expects it.';
  end if;

  -- The loop has to carry the direction before the ratio can read it. The
  -- quarterly sheet holds the manager's decision on plb_goal_kpi, so that is
  -- what comes down -- and perf_direction_of falls back to what the registry
  -- suggests when the sheet says nothing.
  out_src := replace(src,
    'select gk.kpi_id, k.name, k.unit, gk.weight_pct',
    'select gk.kpi_id, k.name, k.unit, gk.weight_pct, gk.direction');
  if out_src = src then
    raise exception 'Migration 253: the measure loop in plb_month_suggest is '
                    'not where this expects it.';
  end if;

  -- A plain replace over the three lines exactly as they are written, rather
  -- than a pattern: a pattern that half-matches rewrites something nobody read.
  src := out_src;
  out_src := replace(src,
    '    ratio := case when perf_direction(r.unit) = ''CEILING''' || chr(10) ||
    '                  then case when v = 0 then 150 else least(150, round(100.0 * ratio / v, 2)) end' || chr(10) ||
    '                  else least(150, round(100.0 * v / ratio, 2)) end;',
    '    ratio := perf_ratio(perf_direction_of(r.kpi_id, r.unit, r.direction),' || chr(10) ||
    '                        ratio, v);');
  if out_src = src then
    raise exception 'Migration 253: the ratio block in plb_month_suggest did '
                    'not match.';
  end if;

  execute 'create or replace function plb_month_suggest(p_actor uuid, p_sheet uuid, '
       || 'p_month date) returns jsonb language plpgsql stable security definer '
       || 'set search_path to ''public'' as ' || quote_literal(out_src);
end
$do$;

-- =====================================================================
-- The manager sets it, alongside the target.
-- =====================================================================
do $do$
declare src text; out_src text;
begin
  -- perf_assign: carry direction in on the insert.
  select prosrc into src from pg_proc
   where proname = 'perf_assign' and pronargs = 2;
  if position('p_in->>''direction''' in src) = 0 then
    out_src := replace(src,
      'rolls_into_id, set_by, note)',
      'rolls_into_id, set_by, note, direction)');
    out_src := replace(out_src,
      '          p_actor, nullif(p_in->>''note'',''''))',
      '          p_actor, nullif(p_in->>''note'',''''),' || chr(10) ||
      '          nullif(upper(btrim(coalesce(p_in->>''direction'',''''))),''''))');
    if out_src = src then
      raise exception 'Migration 253: the insert in perf_assign is not where '
                      'this expects it.';
    end if;
    execute 'create or replace function perf_assign(p_actor uuid, p_in jsonb) '
         || 'returns jsonb language plpgsql volatile security definer '
         || 'set search_path to ''public'' as ' || quote_literal(out_src);
  end if;

  -- perf_assign_edit: and let it be changed afterwards, like the name.
  select prosrc into src from pg_proc
   where proname = 'perf_assign_edit' and pronargs = 2;
  if src is not null and position('direction' in src) = 0 then
    out_src := replace(src,
      'update perf_assignment set' || chr(10) || '    name        = v_name,',
      'update perf_assignment set' || chr(10) || '    name        = v_name,' || chr(10) ||
      '    direction   = case when p_in ? ''direction''' || chr(10) ||
      '                       then nullif(upper(btrim(coalesce(p_in->>''direction'',''''))),'''')' || chr(10) ||
      '                       else direction end,');
    if out_src <> src then
      execute 'create or replace function perf_assign_edit(p_actor uuid, p_in jsonb) '
           || 'returns jsonb language plpgsql volatile security definer '
           || 'set search_path to ''public'' as ' || quote_literal(out_src);
    else
      raise notice 'Migration 253: perf_assign_edit does not set name the way '
                   'this expects; direction is settable on assignment only.';
    end if;
  end if;
end
$do$;

-- ------------------------------------------------------------- the guard
do $guard$
declare n int;
begin
  -- The formula, against the sentences it has to obey.
  if perf_ratio('LOWER', 0, 0) <> 100 then
    raise exception 'Migration 253: zero escalations against a target of zero '
                    'did not read as met.';
  end if;
  if perf_ratio('LOWER', 0, 1) <> 0 then
    raise exception 'Migration 253: a breach against a target of zero scored '
                    'something.';
  end if;
  if perf_ratio('LOWER', 2, 1) <= 100 then
    raise exception 'Migration 253: beating a ceiling did not score above a '
                    'hundred.';
  end if;
  if perf_ratio('LOWER', 2, 4) >= 100 then
    raise exception 'Migration 253: doubling a ceiling scored a hundred or more. '
                    'That is the defect this migration is for.';
  end if;
  if perf_ratio('HIGHER', 100, 50) <> 50 then
    raise exception 'Migration 253: the ordinary case changed. It must not.';
  end if;
  if perf_ratio('HIGHER', 100, 500) <> 150 then
    raise exception 'Migration 253: the cap moved.';
  end if;
  if perf_ratio('HIGHER', null, 5) is not null
     or perf_ratio('HIGHER', 5, null) is not null then
    raise exception 'Migration 253: a missing target or a missing figure was '
                    'scored rather than left unanswered.';
  end if;

  -- Every measure in the registry now says which way it points.
  select count(*) into n from kpi_definition where direction is null;
  if n > 0 then
    raise exception 'Migration 253: % measure(s) still do not say which way '
                    'they point.', n;
  end if;

  -- And the scorers read it.
  if position('perf_ratio(' in
       (select prosrc from pg_proc where proname = 'perf_kpi_score')) = 0 then
    raise exception 'Migration 253: perf_kpi_score does not use perf_ratio.';
  end if;
  if position('perf_ratio(' in
       (select prosrc from pg_proc where proname = 'plb_month_suggest')) = 0 then
    raise exception 'Migration 253: plb_month_suggest does not use perf_ratio.';
  end if;

  raise notice 'perf_ratio: the manager says which way a measure points, and a '
               'target of zero is a promise.';
end $guard$;
