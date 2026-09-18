-- =====================================================================
-- 114 · A chair holder knows which place they sit in
--
-- Applied as migrations chair_holders_know_where_they_sit,
-- chair_place_from_coverage_fix, org_chair_places_are_fixable and
-- crux_app_page_place_a_chair_holder /
-- crux_app_page_place_everyone_the_evidence_places, 2026-09-18.
--
-- A chair is a seat; a seating is that seat in a place. One Branch Manager
-- chair is held in six places at once. chair_holder.seating_id says which
-- one a person actually sits in, and for 43 of 57 holders it was empty - so
-- the org chart showed them against every place, and a person's scope could
-- not be narrowed by where they work.
--
-- Nothing here guesses. A holder is placed only when the evidence already in
-- the database says exactly one place; what it cannot decide is returned and
-- shown to an administrator rather than filled in.
-- =====================================================================

-- Back Office, Field Executives and Team Leaders each have six seatings:
-- five regions and one with no label. Branch Manager has the same five
-- regions plus Pune. The unlabelled three are the Pune seatings of those
-- chairs - that is what made them 34 seats rather than 36 - and leaving the
-- label off made the org chart say "place not recorded" for a place that is
-- perfectly well known.
update chair_seating s
   set scope_label = 'Pune',
       note = coalesce(s.note || ' ', '') ||
              'Labelled Pune: the source chart gives this chair five regional ' ||
              'seatings and one unsuffixed one, exactly as it gives Branch ' ||
              'Manager five regions and Pune.'
  from chair c
 where c.id = s.chair_id
   and c.code in ('BO','FE','TL')
   and s.scope_label is null;

-- Which of the org chart's place buckets a geography falls in.
--
-- The chart splits the country five ways and pulls Pune and Thane out of
-- the West as their own places. Central has no bucket because the chart has
-- no Central chair; a Central branch therefore resolves to nothing and its
-- holder stays unplaced, which is the honest answer.
create or replace function geo_seat_scope(p_geo uuid)
returns text
language sql
stable security definer
set search_path to 'public'
as $$
  with recursive up as (
    select id, parent_id, level, name from geo_node where id = p_geo
    union all
    select g.id, g.parent_id, g.level, g.name
    from geo_node g join up u on u.parent_id = g.id),
  t as (
    select max(case when level='ZONE' then name end) as zone,
           max(case when level='CITY' then name end) as city
    from up)
  select case
           when city ilike 'pune'  then 'Pune'
           when city ilike 'thane' then 'Thane'
           when zone = 'North' then 'North'
           when zone in ('North East','East') then 'North East & East'
           when zone = 'South' then 'South'
           when zone = 'West'  then 'other West locations'
         end
  from t
$$;

comment on function geo_seat_scope(uuid) is
  'The org chart place bucket a geography belongs to, or null when the '
  'chart has no seat for it.';

-- Place the holders the evidence already places.
--
-- The place has to be unambiguous in the coverage itself, not merely
-- unambiguous after filtering to the places this chair happens to have -
-- otherwise a person covering two regions would be quietly assigned to
-- whichever one the chair had a seat in.
create or replace function chair_place_from_coverage(p_actor uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_role role_kind;
  r record;
  v_scopes text[];
  v_seating uuid;
  v_placed jsonb := '[]'::jsonb;
  v_left   jsonb := '[]'::jsonb;
  v_why    text;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Placing chair holders is an administrator''s to do.');
  end if;

  for r in
    select h.id as holder_id, h.person_id, h.chair_id,
           p.full_name, c.code, c.title,
           (select count(*) from chair_seating s where s.chair_id = h.chair_id) as places
    from chair_holder h
    join chair c on c.id = h.chair_id
    join person p on p.id = h.person_id
    where h.seating_id is null
    order by c.code, p.full_name
  loop
    v_seating := null;
    v_why     := null;

    if r.places = 1 then
      -- a chair held in exactly one place needs no evidence at all
      select s.id into v_seating from chair_seating s where s.chair_id = r.chair_id;
      if v_seating is null then v_why := 'the chair has no seating at all'; end if;
    else
      select array_agg(distinct sc) into v_scopes
        from (select geo_seat_scope(b.geo_node_id) as sc
                from coverage_rule cr
                join branch b on b.id = cr.branch_id
               where cr.person_id = r.person_id) q
       where sc is not null;

      if v_scopes is null or array_length(v_scopes, 1) = 0 then
        v_why := case when exists (select 1 from coverage_rule cr where cr.person_id = r.person_id)
                        then 'their coverage is in a place the chart has no seat for'
                        else 'no coverage to place them by' end;
      elsif array_length(v_scopes, 1) > 1 then
        v_why := 'their coverage spans ' || array_to_string(v_scopes, ', ');
      else
        select s.id into v_seating from chair_seating s
         where s.chair_id = r.chair_id and s.scope_label = v_scopes[1];
        if v_seating is null then
          v_why := 'the chair has no seating in ' || v_scopes[1];
        end if;
      end if;
    end if;

    if v_seating is null then
      v_left := v_left || jsonb_build_object(
        'person', r.full_name, 'chair', r.code, 'title', r.title, 'why', v_why);
    else
      update chair_holder set seating_id = v_seating where id = r.holder_id;
      v_placed := v_placed || jsonb_build_object(
        'person', r.full_name, 'chair', r.code,
        'place', (select coalesce(scope_label,'(the only place)')
                    from chair_seating where id = v_seating));
    end if;
  end loop;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'CHAIR_HOLDERS_PLACED', 'chair_holder', 'bulk',
          jsonb_build_object('placed', jsonb_array_length(v_placed),
                             'left', jsonb_array_length(v_left)));

  return jsonb_build_object(
    'placed', jsonb_array_length(v_placed), 'detail', v_placed,
    'unplaced', jsonb_array_length(v_left), 'left', v_left);
end $function$;

-- Put one person in one place. The seating has to belong to the chair the
-- person actually holds, or this is a way of quietly moving someone between
-- chairs without it appearing as a chair change.
create or replace function org_place_holder(p_actor uuid, p_holder uuid, p_seating uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_role role_kind; h chair_holder; s chair_seating; v_name text;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Recording where a chair is held is an administrator''s to do.');
  end if;

  select * into h from chair_holder where id = p_holder;
  if h.id is null then return jsonb_build_object('error','no_such_holder'); end if;

  if p_seating is null then
    update chair_holder set seating_id = null where id = p_holder;
    return jsonb_build_object('ok', true, 'place', null);
  end if;

  select * into s from chair_seating where id = p_seating;
  if s.id is null then return jsonb_build_object('error','no_such_place'); end if;
  if s.chair_id <> h.chair_id then
    return jsonb_build_object('error','wrong_chair',
      'reason','That place belongs to a different chair. Change the chair first.');
  end if;

  update chair_holder set seating_id = p_seating where id = p_holder;

  select full_name into v_name from person where id = h.person_id;
  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, 'CHAIR_HOLDER_PLACED', 'chair_holder', p_holder::text,
          jsonb_build_object('seating_id', h.seating_id),
          jsonb_build_object('seating_id', p_seating, 'person', v_name,
                             'place', s.scope_label));

  return jsonb_build_object('ok', true, 'person', v_name,
    'place', coalesce(s.scope_label, 'No particular place'));
end $function$;

-- Everyone on a chair with no place recorded, in one list, so it can be
-- worked through rather than hunted for chair by chair.
create or replace function org_unplaced()
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'holder', ch.id, 'name', pe.full_name,
           'chair', c.code, 'title', c.title,
           'places', coalesce((select jsonb_agg(jsonb_build_object(
                        'id', cs.id, 'scope', coalesce(cs.scope_label, 'No particular place'))
                        order by cs.scope_label nulls first)
                      from chair_seating cs where cs.chair_id = c.id), '[]'::jsonb))
         order by c.code, pe.full_name), '[]'::jsonb)
  from chair_holder ch
  join person pe on pe.id = ch.person_id
  join chair c on c.id = ch.chair_id
  where ch.to_date is null and ch.seating_id is null
$$;

revoke all on function geo_seat_scope(uuid) from public, anon, authenticated;
revoke all on function chair_place_from_coverage(uuid) from public, anon, authenticated;
revoke all on function org_place_holder(uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function org_unplaced() from public, anon, authenticated;

-- org_chair also gained a `places` list (the seatings the chair has) and its
-- `unplaced` entries became {holder, name} objects rather than bare names, so
-- the screen can offer a place instead of only reporting a missing one. The
-- full definition lives in the migration ledger under
-- org_chair_places_are_fixable.
