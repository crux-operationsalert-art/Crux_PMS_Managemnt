-- The quarter, said in months and split into its parts (249)
--
-- "As a manager I am still not able to change the KPIs for quaterly score
--  card and add sub KPIs in both monthly and the quaterly score card as well
--  as Monthly targets"
-- "FOrmat/UI/UX of monthly score card is good and easy to understand, so use
--  the same for [the quarterly] too but should be linked with the quaterly."
--
-- Three different complaints were folded into those two sentences, and 247
-- answered the first of them: a manager may now set a quarterly target,
-- record an actual and score a month for the people who report to them.
-- This is the other two.
--
-- ---------------------------------------------------------------- SUB-KPIs
--
-- The monthly side has had these since migration 230: perf_assignment.
-- part_of_id, written by perf_split_set, so one target can be split across
-- several clients and the parts add back up to it. The quarterly side has
-- nothing of the kind.
--
-- It cannot have it the same way. plb_goal_kpi is UNIQUE (sheet_id, kpi_id)
-- and every reader of a goal sheet -- plb_compute above all -- joins on that
-- pair. A second row for the same measure would quietly double a weight, and
-- a doubled weight is somebody's bonus.
--
-- And it must not have it the OTHER obvious way either. The sheet says, on
-- screen, in the tool's own words: "Your manager selects no KPI, adds none
-- and removes none -- they come from your chair's published measure set,
-- identical for every seat of the chair." A sub-KPI that was a new scored
-- measure would make that sentence false, and it is a sentence about
-- fairness between people holding the same chair.
--
-- So a part is what it is monthly: a BREAKDOWN of one measure, not a second
-- measure. Its own table, its own targets, no weight of its own, and no
-- effect whatever on the arithmetic that pays a bonus. The measure set is
-- untouched, the weights still add to a hundred, and plb_compute is not
-- changed by a line. What the manager gains is the thing they were asking
-- for: "sixty cases" broken into "Bank A forty, Bank B twenty", with the
-- screen saying when the parts stop adding up to the whole.
--
-- --------------------------------------------- THE MONTHLY SHAPE, LINKED
--
-- The quarterly card shows a measure's monthly split as three percentages
-- -- "50 · 30 · 20" -- which is the phasing rule, not a scorecard. The
-- monthly card shows a target, what was filed against it and how that
-- reads. The owner is asking for the second shape on the quarterly card.
--
-- plb_kpi_months is that shape, and it is the LINK as well, because the
-- three numbers it draws per month are not invented for the drawing:
--
--   target    perf_assignment.target_value for that person, that measure,
--             that month -- the real monthly target in PMS
--   filed     what was actually filed against it, added for a count and
--             averaged for a percentage, the same way plb_quarter_from_months
--             already reads them
--   implied   what the quarterly target and its split SAY that month should
--             have been
--
-- Target against implied is plb_target_agreement's question asked month by
-- month instead of once for the quarter, so the card can show where the two
-- halves of the tool disagree rather than leaving somebody to find it.

-- =====================================================================
-- A part of a measure.
-- =====================================================================
create table if not exists plb_goal_kpi_part (
  id            uuid primary key default gen_random_uuid(),
  goal_kpi_id   uuid not null references plb_goal_kpi(id) on delete cascade,
  label         text not null,
  target_value  numeric,
  actual_value  numeric,
  position      int  not null default 0,
  note          text,
  set_by        uuid references person(id),
  set_at        timestamptz not null default now(),
  -- Taken off the breakdown, not erased from it. Migration 246 settled this
  -- for the monthly side -- perf_assign_remove withdraws and never deletes --
  -- and the reason is the same here: "the breakdown used to say Bank C" is a
  -- question somebody asks three months later, in a dispute, and a row that
  -- was deleted cannot answer it.
  removed_at    timestamptz,
  removed_by    uuid references person(id),
  constraint plb_goal_kpi_part_label_said check (btrim(label) <> '')
);

-- Two parts of one measure cannot be the same part. Case and spacing are
-- not a difference: "Bank A" and "bank a " are one client typed twice.
--
-- NOT partial on removed_at, and that is the design rather than an oversight.
-- A part is identified by its name within its measure, so "Bank A" is ONE
-- row for the life of the sheet: taken off the breakdown it is withdrawn,
-- put back on it the same row comes back carrying its own history. Two rows
-- called Bank A, one dead and one live, would make "what did Bank A used to
-- be asked for" a question with two answers.
create unique index if not exists plb_goal_kpi_part_once
  on plb_goal_kpi_part (goal_kpi_id, lower(btrim(label)));
create index if not exists plb_goal_kpi_part_by_kpi
  on plb_goal_kpi_part (goal_kpi_id, position);

-- Enabled with no policy, which is how every other table on this sheet is
-- protected: nothing reaches a part except through a SECURITY DEFINER
-- function that has already asked perf_rel who is looking.
alter table plb_goal_kpi_part enable row level security;

comment on table plb_goal_kpi_part is
  'A breakdown of ONE quarterly measure into named parts -- "sixty cases" as '
  '"Bank A forty, Bank B twenty". Carries no weight and enters no '
  'arithmetic: plb_compute does not read it. The measure set a chair '
  'publishes is unchanged, which is what keeps every seat of a chair '
  'comparable.';

-- =====================================================================
-- Writing them.
--
-- Replace-the-whole-list rather than add/edit/remove, for the reason
-- perf_split_set is written that way: the invariant being maintained is
-- about the SET of parts ("do they add up to the measure"), and a set is
-- checked once when it is complete, not three times while it is half
-- written.
-- =====================================================================
create or replace function plb_kpi_part_set(p_actor uuid, p_goal_kpi uuid,
                                            p_parts jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public'
as $function$
declare
  gk plb_goal_kpi; s plb_goal_sheet; k kpi_definition;
  v_frozen timestamptz;
  v_sum numeric := 0; n int := 0; i int := 0;
  x jsonb; v_label text;
begin
  select * into gk from plb_goal_kpi where id = p_goal_kpi;
  if gk.id is null then
    return jsonb_build_object('error','no_such_measure');
  end if;
  select * into s from plb_goal_sheet where id = gk.sheet_id;
  select * into k from kpi_definition where id = gk.kpi_id;

  -- The same gate 247 put on plb_sheet_issue, plb_actual_set and
  -- plb_score_month, in the same words. The owner's sentence: "Only my One
  -- up should be able to do that and no one else. Not even my Manager's
  -- manager, only my manager."
  if not (perf_may_set(p_actor, s.person_id) or plb_runs_scheme(p_actor)) then
    return jsonb_build_object('error','not_permitted',
      'reason','Breaking a measure into parts is the manager that person '
            || 'reports to, and the people who run the scheme.');
  end if;

  if s.locked_at is not null then
    return jsonb_build_object('error','sheet_locked',
      'reason','That goal sheet is locked. Parts of a measure change what '
            || 'the sheet says it is asking for.');
  end if;
  select data_frozen_at into v_frozen from plb_result where sheet_id = s.id;
  if v_frozen is not null then
    return jsonb_build_object('error','data_frozen',
      'reason','The quarter''s data was frozen on ' || v_frozen::date ||
               '. Nothing behind a computed result changes.');
  end if;

  if p_parts is null or jsonb_typeof(p_parts) <> 'array' then
    return jsonb_build_object('error','missing_parts',
      'reason','Send the parts. An empty list removes the breakdown.');
  end if;
  if jsonb_array_length(p_parts) > 20 then
    return jsonb_build_object('error','too_many',
      'reason','Twenty parts to a measure. Past that it is a measure of its own.');
  end if;

  -- Validate the whole list before writing any of it, the same rule
  -- org_person_set follows: a form that half-saves is worse than one that
  -- refuses.
  for x in select jsonb_array_elements(p_parts) loop
    i := i + 1;
    v_label := btrim(coalesce(x->>'label',''));
    if v_label = '' then
      return jsonb_build_object('error','invalid',
        'reason','Part ' || i || ' has no name. A part nobody can name is not '
              || 'a part of anything.');
    end if;
    if length(v_label) > 120 then
      return jsonb_build_object('error','invalid',
        'reason','Part ' || i || '''s name is longer than a name.');
    end if;
    if (x->>'target') is not null and (x->>'target') <> '' then
      v_sum := v_sum + (x->>'target')::numeric;
      n := n + 1;
    end if;
  end loop;

  -- The list is replaced whole: everything is withdrawn first, and then
  -- whatever is in the new list is written back over its own row. A part
  -- that stayed on the list never notices; a part that was taken off stays
  -- withdrawn; a part put back after a month away comes back as itself.
  update plb_goal_kpi_part
     set removed_at = now(), removed_by = p_actor
   where goal_kpi_id = p_goal_kpi and removed_at is null;

  i := 0;
  for x in select jsonb_array_elements(p_parts) loop
    i := i + 1;
    insert into plb_goal_kpi_part (goal_kpi_id, label, target_value,
                                   actual_value, position, note, set_by)
    values (p_goal_kpi, btrim(x->>'label'),
            nullif(btrim(coalesce(x->>'target','')),'')::numeric,
            nullif(btrim(coalesce(x->>'actual','')),'')::numeric,
            i, nullif(btrim(coalesce(x->>'note','')),''), p_actor)
    on conflict (goal_kpi_id, lower(btrim(label))) do update
       set target_value = excluded.target_value,
           actual_value = excluded.actual_value,
           position     = excluded.position,
           note         = excluded.note,
           set_by       = excluded.set_by,
           set_at       = now(),
           removed_at   = null,
           removed_by   = null;
  end loop;

  insert into audit_entry (actor_id, action, entity_type, entity_ref,
                           old_value, new_value)
  values (p_actor, 'PLB_PARTS_SET', 'plb_goal_kpi', p_goal_kpi::text,
          null, jsonb_build_object('parts', p_parts));

  return jsonb_build_object('ok', true,
    'goalKpiId', p_goal_kpi,
    'parts', jsonb_array_length(p_parts),
    'partsTotal', case when n = 0 then null else v_sum end,
    'measureTarget', gk.target_value,
    -- Said, never enforced. A breakdown that does not yet add up is a
    -- normal state halfway through writing one, and refusing it would make
    -- the manager do the arithmetic before the tool will take the first
    -- line. It is reported so nobody has to notice it themselves.
    'addsUp', case when n = 0 or gk.target_value is null then null
                   else round(v_sum, 2) = round(gk.target_value, 2) end,
    'note', case
      when jsonb_array_length(p_parts) = 0 then 'The breakdown was removed.'
      when n = 0 or gk.target_value is null then
        jsonb_array_length(p_parts) || ' part(s) saved.'
      when round(v_sum, 2) = round(gk.target_value, 2) then
        jsonb_array_length(p_parts) || ' part(s) saved, adding to ' ||
        gk.target_value || ' — the measure''s own target.'
      else jsonb_array_length(p_parts) || ' part(s) saved. They add to ' ||
        v_sum || ' and ' || coalesce(k.name,'the measure') || ' asks for ' ||
        gk.target_value || '. Nothing is refused; the card says so.'
      end);
end
$function$;

comment on function plb_kpi_part_set(uuid, uuid, jsonb) is
  'Replace the breakdown of one quarterly measure. The manager the person '
  'reports to, and the people who run the scheme -- the same gate 247 put on '
  'issuing a sheet. Reports whether the parts add up to the measure and '
  'refuses nothing for it.';

-- =====================================================================
-- Reading the quarter in the monthly card's shape.
-- =====================================================================
create or replace function plb_kpi_months(p_actor uuid, p_sheet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  s plb_goal_sheet;
  v_rows jsonb := '[]'::jsonb;
  v_off int := 0;
  r record; m record;
  v_months jsonb; v_share numeric; v_implied numeric; v_i int;
  v_aid uuid; v_atgt numeric; v_asrc text; v_filed numeric; v_n int;
  v_parts jsonb;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;
  -- The same reading rule plb_target_agreement uses: anybody in the line may
  -- look, only the one up may set.
  if perf_rel(p_actor, s.person_id) is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That person is not in your line.');
  end if;

  for r in
    select gk.id as goal_kpi_id, gk.kpi_id, k.name, k.unit,
           gk.target_value as quarterly, gk.actual_value as actual,
           gk.weight_pct as weight,
           gk.m1_share, gk.m2_share, gk.m3_share,
           perf_accrual_kind(k.id, k.unit) as kind
      from plb_goal_kpi gk join kpi_definition k on k.id = gk.kpi_id
     where gk.sheet_id = p_sheet
     order by k.position, k.name
  loop
    v_months := '[]'::jsonb;
    v_i := 0;
    for m in
      select (s.quarter + (g.n || ' months')::interval)::date as month, g.n
        from generate_series(0, 2) g(n)
      order by g.n
    loop
      v_i := v_i + 1;
      v_share := case v_i when 1 then r.m1_share
                          when 2 then r.m2_share
                          else r.m3_share end;
      -- No split means the quarter is spread evenly, which is what
      -- plb_phase_targets does when nobody has said otherwise.
      v_implied := case
        when r.quarterly is null then null
        when r.kind <> 'SUM' then r.quarterly
        when v_share is not null then round(r.quarterly * v_share / 100.0, 2)
        else round(r.quarterly / 3.0, 2) end;

      -- Reset first: SELECT ... INTO leaves the variables alone when it
      -- finds nothing, so a month with no assignment would otherwise show
      -- the previous month's target.
      v_aid := null; v_atgt := null; v_asrc := null;
      select a2.id, a2.target_value, a2.target_source
        into v_aid, v_atgt, v_asrc
        from perf_assignment a2
        join perf_cycle c2 on c2.id = a2.cycle_id
       where a2.person_id = s.person_id
         and a2.kpi_id = r.kpi_id
         and a2.part_of_id is null
         and a2.state is distinct from 'WITHDRAWN'
         and c2.period_start = m.month
       limit 1;

      -- Added for a count and averaged for a percentage, the same way
      -- plb_quarter_from_months already reads them. Adding percentages is
      -- the commonest way a scorecard comes to say 280%.
      v_filed := null; v_n := 0;
      if v_aid is not null then
        select case when r.kind = 'SUM' then sum(e.value) else avg(e.value) end,
               count(*)::int
          into v_filed, v_n
          from perf_entry e where e.assignment_id = v_aid;
      end if;

      v_months := v_months || jsonb_build_object(
        'month', m.month,
        'share', v_share,
        'implied', v_implied,
        -- The real monthly target in PMS, and what was filed against it.
        'target', v_atgt,
        'targetSource', v_asrc,
        'filed', v_filed,
        'entries', coalesce(v_n, 0),
        -- The one comparison the card is for: what the month is being asked
        -- for, against what the quarter promises it should be.
        'agrees', case when v_atgt is null or v_implied is null then null
                       else round(v_atgt, 2) = round(v_implied, 2) end);
    end loop;

    if exists (select 1 from jsonb_array_elements(v_months) x
                where (x->>'agrees') = 'false') then
      v_off := v_off + 1;
    end if;

    select coalesce(jsonb_agg(jsonb_build_object(
             'id', p.id, 'label', p.label, 'target', p.target_value,
             'actual', p.actual_value, 'note', p.note) order by p.position),
           '[]'::jsonb)
      into v_parts
      from plb_goal_kpi_part p
     where p.goal_kpi_id = r.goal_kpi_id and p.removed_at is null;

    v_rows := v_rows || jsonb_build_object(
      'goalKpiId', r.goal_kpi_id, 'kpiId', r.kpi_id,
      'name', r.name, 'unit', r.unit, 'kind', r.kind,
      'weight', r.weight, 'quarterly', r.quarterly, 'actual', r.actual,
      'months', v_months,
      'parts', v_parts,
      'partsTotal', (select sum(p.target_value) from plb_goal_kpi_part p
                      where p.goal_kpi_id = r.goal_kpi_id
                        and p.removed_at is null),
      'partsAddUp', case
        when not exists (select 1 from plb_goal_kpi_part p
                          where p.goal_kpi_id = r.goal_kpi_id
                            and p.removed_at is null
                            and p.target_value is not null) then null
        when r.quarterly is null then null
        else round((select sum(p.target_value) from plb_goal_kpi_part p
                     where p.goal_kpi_id = r.goal_kpi_id
                       and p.removed_at is null), 2)
             = round(r.quarterly, 2) end);
  end loop;

  return jsonb_build_object(
    'sheetId', p_sheet, 'quarter', s.quarter, 'personId', s.person_id,
    'measures', v_rows,
    'disagree', v_off,
    'maySet', perf_may_set(p_actor, s.person_id) or plb_runs_scheme(p_actor),
    'mayPhase', perf_may_set(p_actor, s.person_id),
    'note', case when v_off = 0
      then 'Every month is being asked for what the quarter promises.'
      else v_off || ' measure(s) ask for one thing in a month and promise '
           'another for the quarter. Phasing the quarter down fixes it and '
           'leaves alone anything somebody agreed by hand.' end);
end
$function$;

comment on function plb_kpi_months(uuid, uuid) is
  'A quarterly goal sheet in the monthly card''s shape: per measure, three '
  'months each carrying its real PMS target, what was filed against it, and '
  'what the quarter''s split says it should have been. The link between the '
  'two scorecards, with the breakdown of each measure beside it.';

-- =====================================================================
-- The guard.
-- =====================================================================
do $guard$
declare
  v_sheet uuid; v_gk uuid; v_boss uuid; v_above uuid; v_person uuid;
  o jsonb; n int;
begin
  select gk.id, gk.sheet_id into v_gk, v_sheet
    from plb_goal_kpi gk
    join plb_goal_sheet s on s.id = gk.sheet_id
   where s.locked_at is null
     and not exists (select 1 from plb_result r
                      where r.sheet_id = s.id and r.data_frozen_at is not null)
   limit 1;
  if v_gk is null then
    raise notice 'Migration 249: no open goal sheet to check against.';
    return;
  end if;
  select person_id into v_person from plb_goal_sheet where id = v_sheet;
  select manager_id into v_boss from person where id = v_person;

  -- A stranger may not break somebody's measure into parts.
  select id into v_above from person
   where employment_status='ACTIVE' and superseded_by is null
     and id <> v_person and id is distinct from v_boss
     and app_role is distinct from 'ADMIN'
     and coalesce(department,'') not in ('Human Resources','Business Excellence')
   limit 1;
  if v_above is not null then
    o := plb_kpi_part_set(v_above, v_gk, '[]'::jsonb);
    if o->>'error' is distinct from 'not_permitted' then
      raise exception 'Migration 249: a stranger set the parts of somebody''s '
                      'measure: %', o;
    end if;
  end if;

  -- And nobody sets their own, because perf_rel answers 'self' before
  -- anything else and plb_runs_scheme is about the scheme, not the person.
  o := plb_kpi_part_set(v_person, v_gk, '[]'::jsonb);
  if o->>'error' is null and not plb_runs_scheme(v_person) then
    raise exception 'Migration 249: a person broke up their own measure.';
  end if;

  -- The monthly shape reads, and carries three months for every measure.
  if v_boss is not null then
    o := plb_kpi_months(v_boss, v_sheet);
    if o->>'error' is not null then
      raise exception 'Migration 249: the manager could not read the quarter '
                      'in months: %', o;
    end if;
    select count(*) into n from jsonb_array_elements(o->'measures') x
     where jsonb_array_length(x->'months') <> 3;
    if n > 0 then
      raise exception 'Migration 249: % measure(s) do not carry three months.', n;
    end if;
    if not coalesce((o->>'maySet')::boolean, false) then
      raise exception 'Migration 249: the reporting manager is told the sheet '
                      'is not theirs to set. 247 has been undone.';
    end if;
    -- The employee reads their own and is told it is not theirs to set.
    o := plb_kpi_months(v_person, v_sheet);
    if coalesce((o->>'maySet')::boolean, false) and not plb_runs_scheme(v_person) then
      raise exception 'Migration 249: a person is told their own quarter is '
                      'theirs to set.';
    end if;
  end if;

  raise notice 'plb_kpi_months and plb_kpi_part_set: live.';
end $guard$;
