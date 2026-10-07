-- The quarterly scorecard can be changed by the manager who owns it
--
-- "still not able to edit/update KPIs of quaterly scorecard"
--
-- And the owner was right: there was no way to. plb_goal_kpi rows were
-- written exactly once, by plb_sheet_issue, and after that the only things
-- that ever touched them were actual_value (computed from what was filed)
-- and target_value (moved by plb_phase_targets). Nothing could change which
-- measures were on a sheet, what each was worth, what it was asking for, or
-- which way it pointed. A sheet issued with the wrong measure stayed wrong
-- for the quarter.
--
-- WHO. The same rule the monthly side holds, and the one the owner stated
-- for KPIs generally: "the one up manager decides and edits as per the
-- requirement and even change or add a new KPI or reterm any". So
-- perf_may_set(actor, the sheet's person) OR plb_runs_scheme(actor) --
-- which answers 'self' for your own sheet and therefore refuses it.
--
-- UNTIL WHEN. Until the sheet LOCKS. A locked sheet is the promise the
-- quarter is scored against; changing a measure after that is changing the
-- question after the answer.
--
-- THE WHOLE LIST, NOT ONE ROW. Written as a replace-whole, for the reason
-- perf_split_set, plb_kpi_part_set and partner_file_set are: the invariant
-- is about the SET -- the weights add to a hundred -- and a set is checked
-- once, when it is complete. Editing row by row means every intermediate
-- state is invalid and the rule has to be relaxed to allow them.
--
-- =====================================================================
-- REMOVING A MEASURE, AND WHY THIS MIGRATION LOOKS THE WAY IT DOES
--
-- The obvious implementation is a DELETE. It was written that way first,
-- and it was wrong twice over.
--
-- The first draft instead used a `removed_at` flag, and that was worse:
-- FOURTEEN functions in this schema read plb_goal_kpi, and a flag that any
-- one of them forgot would silently count a withdrawn measure into
-- somebody's bonus. Fourteen chances to forget, and the forgetting is
-- invisible until a payout is wrong.
--
-- So neither. The flag is kept AND the forgetting is made impossible:
--
--     plb_goal_kpi  (the table)   ->  renamed plb_goal_kpi_all
--     plb_goal_kpi  (a view)      ->  the live rows, and only those
--
-- Every one of those fourteen functions goes on saying plb_goal_kpi and is
-- now, without being touched, reading only live rows. Not one of them has
-- to remember anything. The history is kept because the row is still there
-- in plb_goal_kpi_all, which is what an argument about an old payout needs.
--
-- This is the same move as the sentinel guard in build-tool.py and for the
-- same reason: an invariant that depends on everybody remembering is an
-- invariant that is already broken somewhere you have not looked. Make it
-- structural and there is nothing to remember.
--
-- The view's columns are listed out rather than written `select *`, because
-- `select *` is expanded once at creation: a column added to the base table
-- afterwards would silently not appear here, which is the same class of
-- trap again. The guard at the foot checks the two still match.
-- =====================================================================

alter table plb_goal_kpi add column if not exists removed_at timestamptz;

do $do$
begin
  -- Idempotent: if the view is already in place this migration has run.
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where n.nspname = 'public' and c.relname = 'plb_goal_kpi'
                and c.relkind = 'v') then
    raise notice 'Migration 255: plb_goal_kpi is already the view.';
    return;
  end if;

  alter table plb_goal_kpi rename to plb_goal_kpi_all;

  execute $v$
    create view plb_goal_kpi as
      select id, sheet_id, kpi_id, weight_pct, target_value, basis_level,
             basis_note, m1_share, m2_share, m3_share, actual_value,
             direction, removed_at
        from plb_goal_kpi_all
       where removed_at is null
  $v$;
end
$do$;

comment on view plb_goal_kpi is
  'The measures live on a quarterly goal sheet. A view, so that every reader '
  'sees only live rows without having to remember to ask -- fourteen '
  'functions read this name and not one of them knows a measure can be '
  'withdrawn. The withdrawn rows are still in plb_goal_kpi_all, because '
  '"what was this sheet asking for in October" is a question somebody asks '
  'about a payout months later.';

create index if not exists plb_goal_kpi_all_live
  on plb_goal_kpi_all (sheet_id) where removed_at is null;

-- =====================================================================
-- What may be put on a sheet.
--
-- The chair's own measure set first, because that is what this person is
-- measured on; then everything else active, because a manager correcting a
-- sheet in week three is not always choosing from the chair's list. Each
-- says whether it is already on the sheet, so the screen draws a list
-- rather than making somebody remember.
-- =====================================================================
create or replace function plb_sheet_measure_options(p_actor uuid, p_sheet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare s plb_goal_sheet; v_may boolean; v_chair uuid;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;

  v_may := perf_may_set(p_actor, s.person_id) or plb_runs_scheme(p_actor);
  if not v_may and p_actor <> s.person_id then
    return jsonb_build_object('error','not_permitted',
      'reason','That sheet is not in your line.');
  end if;

  select h.chair_id into v_chair from chair_holder h
   where h.person_id = s.person_id and h.to_date is null
   order by h.is_primary desc nulls last limit 1;

  return jsonb_build_object(
    'sheetId', p_sheet,
    'personId', s.person_id,
    'person', (select full_name from person where id = s.person_id),
    'quarter', s.quarter,
    'status', s.status,
    -- Two different answers, and the screen needs both: may I change this,
    -- and if not, is it because of who I am or because the sheet has locked.
    'maySet', v_may and s.status <> 'LOCKED',
    'locked', s.status = 'LOCKED',
    'why', case
      when s.status = 'LOCKED' then
        'This sheet is locked. It is the promise the quarter is scored '
        || 'against, so the measures on it do not change now.'
      when not v_may then
        'Changing somebody''s measures is their own manager''s, and Human '
        || 'Resources'' and Business Excellence''s. It is never your own.'
      else null end,
    'measures', coalesce((
      select jsonb_agg(jsonb_build_object(
               'kpiId', k.id, 'name', k.name, 'unit', k.unit,
               'ofTheChair', k.chair_id is not distinct from v_chair,
               'kind', perf_accrual_kind(k.id, k.unit),
               'suggests', k.direction,
               'onTheSheet', exists (select 1 from plb_goal_kpi g
                                      where g.sheet_id = p_sheet and g.kpi_id = k.id))
             order by (k.chair_id is not distinct from v_chair) desc,
                      k.position, k.name)
        from kpi_definition k
       where k.active and k.position < 100), '[]'::jsonb));
end
$function$;

comment on function plb_sheet_measure_options(uuid, uuid) is
  'What may be put on a quarterly goal sheet: the chair''s own measure set '
  'first, then everything else active, each saying whether it is already on '
  'the sheet. Says maySet and why not, so the screen draws a reason rather '
  'than a dead control.';

-- =====================================================================
-- Writing the whole list.
-- =====================================================================
create or replace function plb_sheet_measures_set(p_actor uuid, p_sheet uuid,
                                                  p_measures jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public'
as $function$
declare
  s plb_goal_sheet; x jsonb; i int := 0;
  v_bad jsonb := '[]'::jsonb;
  v_before jsonb; v_keep uuid[] := '{}'; v_kpi uuid;
  v_w numeric; v_sum numeric := 0;
  v_m1 numeric; v_m2 numeric; v_m3 numeric; v_dir text;
  v_gone int := 0; v_added int := 0; v_changed int := 0;
  r record;
begin
  select * into s from plb_goal_sheet where id = p_sheet;
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;

  if not (perf_may_set(p_actor, s.person_id) or plb_runs_scheme(p_actor)) then
    return jsonb_build_object('error','not_permitted',
      'reason','Changing somebody''s measures is their own manager''s, and '
            || 'Human Resources'' and Business Excellence''s. Nobody sets '
            || 'their own.');
  end if;
  if s.status = 'LOCKED' then
    return jsonb_build_object('error','sheet_locked',
      'reason','This sheet is locked. It is the promise the quarter is '
            || 'scored against, so the measures on it do not change now.');
  end if;
  if jsonb_typeof(coalesce(p_measures,'null'::jsonb)) <> 'array' then
    return jsonb_build_object('error','invalid',
      'reason','Send the measures as a list. This call carried '
            || coalesce(jsonb_typeof(p_measures),'nothing') || '.');
  end if;
  if jsonb_array_length(p_measures) = 0 then
    return jsonb_build_object('error','invalid',
      'reason','A goal sheet with no measures on it is not a goal sheet. '
            || 'Remove the sheet instead, or leave at least one.');
  end if;

  -- ------------------------------------------------------------ validate
  for x in select jsonb_array_elements(p_measures) loop
    i := i + 1;
    v_kpi := nullif(btrim(coalesce(x->>'kpiId','')),'')::uuid;
    if v_kpi is null then
      v_bad := v_bad || jsonb_build_object('at', i,
        'reason','Measure ' || i || ': choose which measure this is.');
    elsif not exists (select 1 from kpi_definition k where k.id = v_kpi and k.active) then
      v_bad := v_bad || jsonb_build_object('at', i,
        'reason','Measure ' || i || ' is not a measure anybody can be given.');
    elsif v_kpi = any(v_keep) then
      v_bad := v_bad || jsonb_build_object('at', i,
        'reason','Measure ' || i || ' is on the list twice. One row each, or '
              || 'the weights say one thing and the sheet shows another.');
    else
      v_keep := v_keep || v_kpi;
    end if;

    v_w := nullif(btrim(coalesce(x->>'weight','')),'')::numeric;
    if v_w is null or v_w <= 0 or v_w > 100 then
      v_bad := v_bad || jsonb_build_object('at', i,
        'reason','Measure ' || i || ' needs a weight between nought and a '
              || 'hundred.');
    else
      v_sum := v_sum + v_w;
    end if;

    -- The owner's rule, and the reason migration 253 exists: "one up manager
    -- if has assigned a KPI should be assigning the target too ... should be
    -- adding 0 in the target and not keep it blank."
    if nullif(btrim(coalesce(x->>'target','')),'') is null then
      v_bad := v_bad || jsonb_build_object('at', i,
        'reason','Measure ' || i || ' has no target. A measure with nothing '
              || 'to hit cannot be scored, and zero is a target you can type.');
    end if;

    v_dir := nullif(upper(btrim(coalesce(x->>'direction',''))),'');
    if v_dir is not null and v_dir not in ('HIGHER','LOWER') then
      v_bad := v_bad || jsonb_build_object('at', i,
        'reason','Measure ' || i || ': a bigger number is better, or a '
              || 'smaller one is.');
    end if;

    -- The split across the three months. The column is numeric not null
    -- default 0, and 0/0/0 is how this schema says "nobody has phased this
    -- yet" -- plb_phase_targets fills it later. So all-zero is allowed and
    -- means exactly that; anything else has to be a whole split.
    v_m1 := nullif(btrim(coalesce(x->>'m1','')),'')::numeric;
    v_m2 := nullif(btrim(coalesce(x->>'m2','')),'')::numeric;
    v_m3 := nullif(btrim(coalesce(x->>'m3','')),'')::numeric;
    if (v_m1 is not null or v_m2 is not null or v_m3 is not null) then
      if v_m1 is null or v_m2 is null or v_m3 is null then
        v_bad := v_bad || jsonb_build_object('at', i,
          'reason','Measure ' || i || ': give all three months of the split '
                || 'or none of them.');
      elsif coalesce(v_m1,0) + coalesce(v_m2,0) + coalesce(v_m3,0) <> 0
            and round(v_m1 + v_m2 + v_m3, 2) <> 100 then
        v_bad := v_bad || jsonb_build_object('at', i,
          'reason','Measure ' || i || ': the three months come to '
                || round(v_m1 + v_m2 + v_m3, 2) || ' and not a hundred. '
                || 'Leave all three empty to let the phasing set them.');
      end if;
    end if;
  end loop;

  -- The weights are about the SET, which is why the whole list arrives at
  -- once. Migration 237 is the record of what happens when they do not add
  -- up: ninety-two people out of a hundred and one carrying weights that
  -- summed to something else, and a score nobody could reproduce by hand.
  if jsonb_array_length(v_bad) = 0 and round(v_sum, 2) <> 100 then
    v_bad := v_bad || jsonb_build_object('at', null,
      'reason','The weights come to ' || round(v_sum,2) || ' and not a '
            || 'hundred. A person''s measures have to account for all of '
            || 'them, or the score cannot be worked out by hand.');
  end if;

  -- Nothing is withdrawn that has anything against it. Checked before any
  -- write, with the rest, so a list that is half-allowed changes nothing.
  for r in
    select g.id, g.kpi_id, k.name,
           g.actual_value is not null as has_actual,
           exists (select 1 from plb_goal_kpi_part p
                    where p.goal_kpi_id = g.id and p.removed_at is null) as has_parts
      from plb_goal_kpi g join kpi_definition k on k.id = g.kpi_id
     where g.sheet_id = p_sheet and not (g.kpi_id = any(v_keep))
  loop
    if r.has_actual or r.has_parts then
      v_bad := v_bad || jsonb_build_object('at', null,
        'reason', r.name || ' cannot come off this sheet: '
              || case when r.has_actual then 'a figure has already been '
                      || 'worked out against it' else 'it has a breakdown '
                      || 'written against it' end
              || '. Set its weight low if it no longer matters, or lock the '
              || 'quarter and leave it on the record.');
    end if;
  end loop;

  if jsonb_array_length(v_bad) > 0 then
    return jsonb_build_object('error','invalid', 'fields', v_bad,
      'reason','Nothing was saved. Put these right and send it again.');
  end if;

  -- --------------------------------------------------------------- write
  select jsonb_agg(jsonb_build_object('kpiId', g.kpi_id, 'name', k.name,
           'weight', g.weight_pct, 'target', g.target_value,
           'direction', g.direction,
           'm1', g.m1_share, 'm2', g.m2_share, 'm3', g.m3_share)
         order by k.position, k.name)
    into v_before
    from plb_goal_kpi g join kpi_definition k on k.id = g.kpi_id
   where g.sheet_id = p_sheet;

  -- Withdrawn on the BASE table, and from this moment invisible through the
  -- view to every one of the fourteen readers, none of which had to be told.
  update plb_goal_kpi_all
     set removed_at = now()
   where sheet_id = p_sheet and removed_at is null
     and not (kpi_id = any(v_keep));
  get diagnostics v_gone = row_count;

  i := 0;
  for x in select jsonb_array_elements(p_measures) loop
    i := i + 1;
    v_kpi := (x->>'kpiId')::uuid;
    -- A measure given, taken back and given again is one row, revived --
    -- the same shape migration 250 gave perf_assignment, and for the same
    -- reason: the second row is the one that makes two scores possible.
    if exists (select 1 from plb_goal_kpi_all g
                where g.sheet_id = p_sheet and g.kpi_id = v_kpi) then
      update plb_goal_kpi_all g
         set weight_pct   = (x->>'weight')::numeric,
             target_value = (x->>'target')::numeric,
             direction    = nullif(upper(btrim(coalesce(x->>'direction',''))),''),
             -- Only where the caller sent one. A form that carries no split
             -- must not wipe a phasing somebody has already run.
             m1_share     = coalesce(nullif(btrim(coalesce(x->>'m1','')),'')::numeric,
                                     g.m1_share),
             m2_share     = coalesce(nullif(btrim(coalesce(x->>'m2','')),'')::numeric,
                                     g.m2_share),
             m3_share     = coalesce(nullif(btrim(coalesce(x->>'m3','')),'')::numeric,
                                     g.m3_share),
             basis_note   = coalesce(nullif(btrim(coalesce(x->>'note','')),''),
                                     g.basis_note),
             removed_at   = null
       where g.sheet_id = p_sheet and g.kpi_id = v_kpi;
      if (select removed_at from plb_goal_kpi_all
           where sheet_id = p_sheet and kpi_id = v_kpi) is null then
        v_changed := v_changed + 1;
      end if;
    else
      insert into plb_goal_kpi_all (sheet_id, kpi_id, weight_pct, target_value,
                                    direction, m1_share, m2_share, m3_share,
                                    basis_level, basis_note)
      values (p_sheet, v_kpi, (x->>'weight')::numeric, (x->>'target')::numeric,
              nullif(upper(btrim(coalesce(x->>'direction',''))),''),
              coalesce(nullif(btrim(coalesce(x->>'m1','')),'')::numeric, 0),
              coalesce(nullif(btrim(coalesce(x->>'m2','')),'')::numeric, 0),
              coalesce(nullif(btrim(coalesce(x->>'m3','')),'')::numeric, 0),
              coalesce(nullif(btrim(coalesce(x->>'basisLevel','')),'')::int, 1),
              nullif(btrim(coalesce(x->>'note','')),''));
      v_added := v_added + 1;
    end if;
  end loop;

  insert into audit_entry (actor_id, action, entity_type, entity_ref,
                           old_value, new_value)
  values (p_actor, 'PLB_SHEET_MEASURES_SET', 'plb_goal_sheet', p_sheet::text,
          v_before, p_measures);

  return jsonb_build_object('ok', true, 'sheetId', p_sheet,
    'added', v_added, 'changed', v_changed, 'removed', v_gone,
    'weights', round(v_sum, 2),
    'note', case
      when v_added + v_gone = 0 then
        'Saved. The same ' || v_changed || ' measure(s), with what you changed.'
      else 'Saved. ' || v_added || ' added, ' || v_gone || ' taken off, '
           || v_changed || ' left in place. The weights add to a hundred.'
      end);
end
$function$;

comment on function plb_sheet_measures_set(uuid, uuid, jsonb) is
  'Replace the measures on a quarterly goal sheet -- which ones, what each '
  'is worth, what it asks for, which way it points and how it splits across '
  'the three months. The one-up manager''s, Human Resources'' and Business '
  'Excellence''s, until the sheet locks. Validated whole, because the rule '
  'that the weights add to a hundred is a rule about the set. A measure '
  'taken off is withdrawn, never erased, and disappears from every reader '
  'through the plb_goal_kpi view rather than by each of them remembering.';

-- ------------------------------------------------------------- the guard
do $guard$
declare
  v_sheet uuid; v_person uuid; v_boss uuid;
  o jsonb; n int; v_list jsonb; v_cols int;
begin
  -- The structure first, because everything below rests on it.
  if not exists (select 1 from pg_class c join pg_namespace n2 on n2.oid = c.relnamespace
                  where n2.nspname='public' and c.relname='plb_goal_kpi' and c.relkind='v') then
    raise exception 'Migration 255: plb_goal_kpi is not a view, so a withdrawn '
                    'measure would still be read by every function that asks '
                    'for it by name.';
  end if;
  -- The view lists its columns, so a column added to the base table later
  -- would silently not appear. That is the same trap in a new place, so it
  -- is checked rather than trusted.
  select count(*) into v_cols from (
    select column_name from information_schema.columns
      where table_name = 'plb_goal_kpi_all'
    except
    select column_name from information_schema.columns
      where table_name = 'plb_goal_kpi') q;
  if v_cols > 0 then
    raise exception 'Migration 255: % column(s) exist on plb_goal_kpi_all and '
                    'not on the plb_goal_kpi view. Add them to the view.', v_cols;
  end if;

  select s.id, s.person_id into v_sheet, v_person
    from plb_goal_sheet s
    join person p on p.id = s.person_id
   where s.status <> 'LOCKED' and p.manager_id is not null
     and exists (select 1 from plb_goal_kpi g where g.sheet_id = s.id)
   limit 1;
  if v_sheet is null then
    raise notice 'Migration 255: no unlocked sheet to check against.';
    return;
  end if;
  select manager_id into v_boss from person where id = v_person;

  -- Nobody edits their own.
  if plb_sheet_measures_set(v_person, v_sheet,
       jsonb_build_array(jsonb_build_object('kpiId', gen_random_uuid(),
         'weight', 100, 'target', 1)))->>'error' is distinct from 'not_permitted' then
    raise exception 'Migration 255: a person set their own measures.';
  end if;

  -- The weights have to add up.
  select jsonb_agg(jsonb_build_object('kpiId', g.kpi_id, 'weight', 10,
                                      'target', coalesce(g.target_value, 0)))
    into v_list from plb_goal_kpi g where g.sheet_id = v_sheet;
  o := plb_sheet_measures_set(v_boss, v_sheet, v_list);
  if o->>'error' is distinct from 'invalid' then
    raise exception 'Migration 255: weights that do not add to a hundred were '
                    'accepted: %', o;
  end if;

  -- A measure with no target is refused.
  select jsonb_agg(jsonb_build_object('kpiId', g.kpi_id,
           'weight', round(100.0 / count(*) over (), 4)))
    into v_list from plb_goal_kpi g where g.sheet_id = v_sheet;
  if plb_sheet_measures_set(v_boss, v_sheet, v_list)->>'error'
     is distinct from 'invalid' then
    raise exception 'Migration 255: a measure with no target was accepted.';
  end if;

  -- And the options list comes back.
  if jsonb_array_length(coalesce(
       plb_sheet_measure_options(v_boss, v_sheet)->'measures','[]'::jsonb)) = 0 then
    raise exception 'Migration 255: there is nothing to put on a sheet.';
  end if;

  -- Nothing above wrote anything.
  select count(*) into n from plb_goal_kpi where sheet_id = v_sheet;
  if n = 0 then
    raise exception 'Migration 255: a refusal emptied the sheet.';
  end if;

  raise notice 'plb_sheet_measures_set: the quarterly sheet is the manager''s '
               'until it locks, and a withdrawn measure is invisible by '
               'construction.';
end $guard$;
