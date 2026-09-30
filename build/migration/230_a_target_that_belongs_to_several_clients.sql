-- =====================================================================
-- 230 · One target, several clients
--
-- Asked for: "Shantanu gets a target of collection on 10,00,000 but
-- distributed between SBI, BOM, IDBI etc. This sub category should also
-- get passed down."
--
-- Almost all of this already existed and none of it was reachable.
-- perf_assignment has carried part_of_id, split_kind, split_ref and
-- split_label since the table was built; perf_value already reads them --
-- it sums the parts for a count and takes a target-weighted mean for a
-- percentage; and perf_due already lists the parts, labels each with its
-- split, inherits the parent's cadence, and hides a parent that has parts
-- so nobody files a number against a measure that no longer counts its
-- own entries.
--
-- Nothing populated any of it. Zero rows in the whole database used a
-- split. What was missing was one function to create them, which is all
-- this migration is.
--
-- THE ARITHMETIC IS THE CASCADE'S, DELIBERATELY
--
-- A count divides and a percentage is copied -- the same rule migration
-- 223 gives for a target coming down to a team, for the same reason. Ten
-- lakh of collection across three banks is three shares that add to ten
-- lakh. A 95% quality target across three banks is 95% at each; it is not
-- 31.67% each, and a person told otherwise would reasonably conclude the
-- tool was broken.
--
-- WHO MAY SPLIT
--
-- Whoever may set the target may split it: perf_may_set, the rule already
-- tested everywhere else. The split comes down with the target, which is
-- what "should also get passed down" asks for.
--
-- A part that has been filed against is never silently removed. Deleting
-- it would delete somebody's filed numbers, so the refusal names it and
-- the caller decides.
-- =====================================================================

create or replace function perf_split_set(p_actor uuid, p_assignment uuid,
                                          p_in jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  a perf_assignment; v_kind text; v_split text;
  r jsonb; v_ref uuid; v_target numeric; v_label text;
  v_named uuid[] := '{}'; v_keep uuid[] := '{}';
  v_given numeric := 0; v_blank int := 0; v_left numeric;
  v_rows jsonb := '[]'::jsonb; v_del int := 0; v_stuck text;
  v_id uuid;
begin
  select * into a from perf_assignment where id = p_assignment;
  if a.id is null then return jsonb_build_object('error','no_such_assignment'); end if;

  if not perf_may_set(p_actor, a.person_id) then
    return jsonb_build_object('error','not_permitted',
      'reason','Splitting a target across clients is the same act as setting '
               'it, and belongs to the person they report to.');
  end if;

  -- One level only. A split of a split is a different feature and would
  -- make perf_value's recursion mean two things at once.
  if a.part_of_id is not null then
    return jsonb_build_object('error','already_a_part',
      'reason','That measure is itself one client''s share. Split the '
               'measure it belongs to, not the share.');
  end if;

  v_split := upper(coalesce(p_in->>'kind','CLIENT'));
  if v_split <> 'CLIENT' then
    return jsonb_build_object('error','unknown_split',
      'reason','Only a split by client is supported.');
  end if;

  v_kind := perf_accrual_kind(a.kpi_id, a.unit);

  -- --------------------------------------------------- read what was asked
  for r in select * from jsonb_array_elements(coalesce(p_in->'parts','[]'::jsonb)) loop
    v_ref := nullif(r->>'ref','')::uuid;
    if v_ref is null then
      return jsonb_build_object('error','missing_client',
        'reason','Every share has to name a client.');
    end if;
    if not exists (select 1 from client where id = v_ref) then
      return jsonb_build_object('error','no_such_client', 'clientId', v_ref);
    end if;
    if v_ref = any(v_named) then
      return jsonb_build_object('error','client_twice',
        'reason', (select name from client where id = v_ref) ||
                  ' appears twice. One share per client.');
    end if;
    v_named := v_named || v_ref;
    if (r->>'target') is not null and r->>'target' <> '' then
      v_given := v_given + (r->>'target')::numeric;
    else
      v_blank := v_blank + 1;
    end if;
  end loop;

  -- Naming nobody removes the split altogether, which is a legitimate act.
  if array_length(v_named,1) is null then
    select string_agg(c.split_label, ', ') into v_stuck
      from perf_assignment c
     where c.part_of_id = a.id
       and exists (select 1 from perf_entry e where e.assignment_id = c.id);
    if v_stuck is not null then
      return jsonb_build_object('error','has_filings',
        'reason','These shares already have numbers filed against them, so '
                 'removing the split would delete them: ' || v_stuck);
    end if;
    delete from perf_assignment where part_of_id = a.id;
    get diagnostics v_del = row_count;
    insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
    values (p_actor,'PERF_SPLIT_CLEARED','perf_assignment', a.id::text,
            jsonb_build_object('removed', v_del));
    return jsonb_build_object('ok', true, 'parts', 0, 'removed', v_del,
      'note','The split is gone. The measure is filed as one number again.');
  end if;

  -- ------------------------------------------------------- the arithmetic
  if v_kind = 'SUM' then
    if a.target_value is not null and v_given > a.target_value then
      return jsonb_build_object('error','over_the_target',
        'reason','The shares add to ' || v_given || ', which is more than the '
                 || a.target_value || ' being divided.');
    end if;
    v_left := case when a.target_value is null then null
                   else a.target_value - v_given end;
  end if;

  -- ------------------------------------------------------------ write them
  for r in select * from jsonb_array_elements(p_in->'parts') loop
    v_ref   := (r->>'ref')::uuid;
    v_label := (select name from client where id = v_ref);

    if v_kind = 'SUM' then
      v_target := case
        when (r->>'target') is not null and r->>'target' <> ''
          then (r->>'target')::numeric
        when v_left is null or v_blank = 0 then null
        else round(v_left / v_blank, 2) end;
    else
      -- A percentage is copied, never divided. perf_value weights a level
      -- by target_value, so equal targets make it a plain mean.
      v_target := a.target_value;
    end if;

    select c.id into v_id from perf_assignment c
      where c.part_of_id = a.id and c.split_ref = v_ref;

    if v_id is null then
      insert into perf_assignment
        (cycle_id, person_id, kpi_id, name, unit, target_value, weight_pct,
         cadence, cadence_day, part_of_id, split_kind, split_ref, split_label,
         set_by, state, target_source)
      values (a.cycle_id, a.person_id, a.kpi_id, a.name, a.unit, v_target,
              a.weight_pct, a.cadence, a.cadence_day, a.id, 'CLIENT', v_ref,
              v_label, p_actor, a.state,
              case when (r->>'target') is not null and r->>'target' <> ''
                   then 'MANUAL' else 'SHARED' end)
      returning id into v_id;
    else
      update perf_assignment
         set target_value = v_target,
             split_label  = v_label,
             target_source = case when (r->>'target') is not null and r->>'target' <> ''
                                  then 'MANUAL' else 'SHARED' end
       where id = v_id;
    end if;

    v_keep := v_keep || v_id;
    v_rows := v_rows || jsonb_build_object(
      'assignmentId', v_id, 'clientId', v_ref, 'client', v_label,
      'target', v_target);
  end loop;

  -- ------------------------------------- anything dropped from the list
  select string_agg(c.split_label, ', ') into v_stuck
    from perf_assignment c
   where c.part_of_id = a.id and not (c.id = any(v_keep))
     and exists (select 1 from perf_entry e where e.assignment_id = c.id);
  if v_stuck is not null then
    return jsonb_build_object('error','has_filings',
      'reason','These shares already have numbers filed against them and were '
               'left out of the new split, so nothing has been changed: ' || v_stuck);
  end if;
  delete from perf_assignment c where c.part_of_id = a.id and not (c.id = any(v_keep));
  get diagnostics v_del = row_count;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor,'PERF_SPLIT_SET','perf_assignment', a.id::text,
          jsonb_build_object('parts', jsonb_array_length(v_rows),
                             'removed', v_del, 'kind', v_kind));

  return jsonb_build_object('ok', true,
    'kind', v_kind,
    'divides', v_kind = 'SUM',
    'parts', v_rows,
    'removed', v_del,
    'note', case when v_kind = 'SUM'
      then 'A count, so the target divides: the shares add to what was being '
           'split, and a share left blank takes an even part of what is left.'
      else 'A percentage, so every client carries the same number. It is not '
           'divided -- 95% across three clients is 95% each.' end);
end $function$;

comment on function perf_split_set(uuid,uuid,jsonb) is
  'Splits one person''s measure across clients, creating the part_of_id '
  'rows perf_value and perf_due have always been able to read. A count '
  'divides and a percentage is copied, which is the cascade''s rule. A '
  'share that has been filed against is never silently removed.';

-- What a split looks like now, for the screen that draws it.
create or replace function perf_split_of(p_actor uuid, p_assignment uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare a perf_assignment;
begin
  select * into a from perf_assignment where id = p_assignment;
  if a.id is null then return jsonb_build_object('error','no_such_assignment'); end if;
  if perf_rel(p_actor, a.person_id) is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That measure is not in your line.');
  end if;

  return jsonb_build_object(
    'assignmentId', a.id,
    'name', a.name,
    'unit', a.unit,
    'target', a.target_value,
    'kind', perf_accrual_kind(a.kpi_id, a.unit),
    'divides', perf_accrual_kind(a.kpi_id, a.unit) = 'SUM',
    'maySet', perf_may_set(p_actor, a.person_id),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'assignmentId', c.id, 'clientId', c.split_ref,
               'client', c.split_label, 'target', c.target_value,
               'pinned', c.target_source = 'MANUAL',
               'value', perf_value(c.id),
               'filings', (select count(*) from perf_entry e
                            where e.assignment_id = c.id))
             order by c.split_label)
        from perf_assignment c where c.part_of_id = a.id), '[]'::jsonb),
    'clients', coalesce((
      select jsonb_agg(jsonb_build_object('id', cl.id, 'name', cl.name,
                                          'code', cl.code) order by cl.name)
        from client cl where cl.status = 'ACTIVE'), '[]'::jsonb));
end $function$;

comment on function perf_split_of(uuid,uuid) is
  'One measure''s split across clients, with what each share has reached '
  'and the list of clients to choose from.';

revoke all on function perf_split_set(uuid,uuid,jsonb) from public, anon, authenticated;
revoke all on function perf_split_of(uuid,uuid)        from public, anon, authenticated;
