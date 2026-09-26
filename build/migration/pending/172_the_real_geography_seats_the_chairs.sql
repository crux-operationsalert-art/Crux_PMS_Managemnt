-- The location chairs in the operating-structure recommendation were samples.
-- The owner has said so, and the data agrees: the recommendation seats the
-- geographic chairs against six labels -- North, North East & East, South,
-- West, Pune, Thane and "other West locations" -- while the operating
-- geography the tool actually runs on has fifteen zones and thirty-seven
-- locations, and coverage_rule names a branch manager for every one of them.
--
-- So the six sample labels are replaced by the real ones, generated from
-- op_node rather than typed, which means the org chart follows the geography
-- from here on instead of drifting from it.
--
--   Zonal Manager                     one seating per ZONE, under the AVP
--   Branch Manager                    one per LOCATION, under its zone's ZM
--   Location Partner / Franchisee     one per LOCATION, under its zone's ZM
--   Team Leader / Supervisor          one per LOCATION, under its BM
--   Back Office / Processing          one per LOCATION, under its TL
--   Branch Collection Executive       one per LOCATION, under its BM
--   Business Development Executive    one per LOCATION, under its BM
--   Field Executives / Verifiers      one per LOCATION, under its BM
--
-- Business Manager is left exactly as it is. It is a real chair with a real
-- holder between the Zonal and the Branch Manager in one zone only, and
-- guessing which of the fifteen zones it belongs to now would be inventing
-- structure rather than reading it.
--
-- WHAT THIS MIGRATION DOES NOT DO, on purpose: it does not put anybody in a
-- chair they were not already in. Seating a person in the Branch Manager
-- chair puts them in a bonus scheme, and that is a decision with a number
-- attached. Eighteen people hold an open BRANCH_MANAGER coverage rule today
-- and only eight of them sit in the Branch Manager chair; five are Location
-- Partners, whom the scheme deliberately excludes; one is a Team Leader, one
-- a Zonal Manager, and three are in no chair at all. Those last five are
-- surfaced by plb_unseated() for a person to look at and decide, with the
-- evidence beside them. Nothing here decides it for them.
--
-- What it DOES do to people: where somebody already holds a geographic chair
-- and coverage_rule says which place they run, their chair_holder row is
-- pointed at that place's seating instead of at a sample label. That is the
-- same person, in the same chair, at a named place rather than a made-up one.

do $mig$
declare
  v_avp uuid; v_zone record; v_loc record;
  v_zm uuid; v_bm uuid; v_tl uuid;
  c_zm uuid; c_bm uuid; c_lp uuid; c_tl uuid; c_bo uuid; c_ce uuid; c_bde uuid; c_fe uuid;
  n_seat int := 0; n_moved int := 0;
begin
  -- one seating per chair per scope label, or a second run doubles the tree
  create unique index if not exists chair_seating_scope_uniq
    on chair_seating (chair_id, coalesce(lower(btrim(scope_label)), ''));

  select id into c_zm  from chair where code = 'ZONAL_MANAGER';
  select id into c_bm  from chair where code = 'BRANCH_MANAGER';
  select id into c_lp  from chair where code = 'LOCATION_PARTNER';
  select id into c_tl  from chair where code = 'TEAM_LEADER';
  select id into c_bo  from chair where code = 'BO';
  select id into c_ce  from chair where code = 'CE';
  select id into c_bde from chair where code = 'BDE';
  select id into c_fe  from chair where code = 'FE';
  if c_zm is null or c_bm is null or c_lp is null or c_tl is null
     or c_bo is null or c_ce is null or c_bde is null or c_fe is null then
    raise exception 'one of the eight geographic chairs is missing';
  end if;

  select s.id into v_avp from chair_seating s join chair c on c.id = s.chair_id
   where c.code = 'AVP' limit 1;
  if v_avp is null then raise exception 'the AVP seating is missing'; end if;

  -- ------------------------------------------------------------ the zones
  for v_zone in select id, name from op_node where level = 'ZONE' and active order by sort, name
  loop
    insert into chair_seating (chair_id, scope_label, reports_to_seating_id, holder_text, source_ref)
    values (c_zm, v_zone.name, v_avp, 'from op_node', 'op_node:' || v_zone.id)
    on conflict (chair_id, coalesce(lower(btrim(scope_label)), '')) do update
      set reports_to_seating_id = excluded.reports_to_seating_id,
          source_ref = excluded.source_ref
    returning id into v_zm;
    if v_zm is null then
      select id into v_zm from chair_seating
       where chair_id = c_zm and lower(btrim(scope_label)) = lower(btrim(v_zone.name));
    end if;
    n_seat := n_seat + 1;

    -- -------------------------------------------------------- its locations
    for v_loc in select id, name from op_node
                  where parent_id = v_zone.id and level = 'LOCATION' and active
                  order by sort, name
    loop
      insert into chair_seating (chair_id, scope_label, reports_to_seating_id, holder_text, source_ref)
      values (c_bm, v_loc.name, v_zm, 'from op_node', 'op_node:' || v_loc.id)
      on conflict (chair_id, coalesce(lower(btrim(scope_label)), '')) do update
        set reports_to_seating_id = excluded.reports_to_seating_id,
            source_ref = excluded.source_ref
      returning id into v_bm;
      if v_bm is null then
        select id into v_bm from chair_seating
         where chair_id = c_bm and lower(btrim(scope_label)) = lower(btrim(v_loc.name));
      end if;

      insert into chair_seating (chair_id, scope_label, reports_to_seating_id, holder_text, source_ref)
      values (c_lp, v_loc.name, v_zm, 'from op_node', 'op_node:' || v_loc.id)
      on conflict (chair_id, coalesce(lower(btrim(scope_label)), '')) do update
        set reports_to_seating_id = excluded.reports_to_seating_id;

      insert into chair_seating (chair_id, scope_label, reports_to_seating_id, holder_text, source_ref)
      values (c_tl, v_loc.name, v_bm, 'from op_node', 'op_node:' || v_loc.id)
      on conflict (chair_id, coalesce(lower(btrim(scope_label)), '')) do update
        set reports_to_seating_id = excluded.reports_to_seating_id
      returning id into v_tl;
      if v_tl is null then
        select id into v_tl from chair_seating
         where chair_id = c_tl and lower(btrim(scope_label)) = lower(btrim(v_loc.name));
      end if;

      insert into chair_seating (chair_id, scope_label, reports_to_seating_id, holder_text, source_ref)
      values (c_bo, v_loc.name, v_tl, 'from op_node', 'op_node:' || v_loc.id)
      on conflict (chair_id, coalesce(lower(btrim(scope_label)), '')) do update
        set reports_to_seating_id = excluded.reports_to_seating_id;

      insert into chair_seating (chair_id, scope_label, reports_to_seating_id, holder_text, source_ref)
      select x, v_loc.name, v_bm, 'from op_node', 'op_node:' || v_loc.id
        from unnest(array[c_ce, c_bde, c_fe]) x
      on conflict (chair_id, coalesce(lower(btrim(scope_label)), '')) do update
        set reports_to_seating_id = excluded.reports_to_seating_id;

      n_seat := n_seat + 6;
    end loop;
  end loop;

  -- ------------------------------------- move people onto the real seatings
  -- Same person, same chair, at a named place rather than a sample label.
  -- Where somebody runs several places, the seating is the one they have run
  -- longest; coverage_rule keeps the full list, which is its job.
  with runs as (
    select distinct on (cr.person_id) cr.person_id, n.name as place
      from coverage_rule cr join op_node n on n.id = cr.op_node_id
     where cr.role = 'BRANCH_MANAGER' and cr.effective_to is null
     order by cr.person_id, cr.effective_from, n.name)
  update chair_holder h
     set seating_id = s.id
    from runs r
    join chair_seating s on lower(btrim(s.scope_label)) = lower(btrim(r.place))
   where h.person_id = r.person_id and h.to_date is null
     and s.chair_id = h.chair_id
     and coalesce(h.seating_id, '00000000-0000-0000-0000-000000000000'::uuid) <> s.id;
  get diagnostics n_moved = row_count;

  -- ------------------------------------------- retire the sample labels
  -- Only the ones nobody is sitting in. A sample label with a person still in
  -- it is a fact about that person, not a leftover, and deleting it would
  -- take their seat away without telling anyone.
  delete from chair_seating s
   where s.chair_id in (c_zm, c_bm, c_lp, c_tl, c_bo, c_ce, c_bde, c_fe)
     and s.scope_label in ('North','North East & East','South','West','Pune','Thane',
                           'other West locations')
     and not exists (select 1 from op_node n
                      where lower(btrim(n.name)) = lower(btrim(s.scope_label)) and n.active)
     and not exists (select 1 from chair_holder h where h.seating_id = s.id)
     and not exists (select 1 from chair_seating c where c.reports_to_seating_id = s.id);

  raise notice 'seatings touched %, holders moved %', n_seat, n_moved;
end $mig$;

-- Who runs a place and is not in a chair that the scheme can see. This is the
-- list a person looks at and decides on; nothing acts on it automatically.
create or replace function plb_unseated()
returns jsonb language sql stable security definer set search_path to 'public' as $fn$
  select coalesce(jsonb_agg(x order by x->>'person'), '[]'::jsonb) from (
    select jsonb_build_object(
      'personId', p.id, 'person', p.full_name,
      'employeeNo', p.employee_no, 'email', p.work_email,
      'places', (select count(*) from coverage_rule c2
                  where c2.person_id = p.id and c2.role = 'BRANCH_MANAGER'
                    and c2.effective_to is null),
      'placeList', (select string_agg(n2.name, ', ' order by n2.name)
                      from coverage_rule c3 join op_node n2 on n2.id = c3.op_node_id
                     where c3.person_id = p.id and c3.role = 'BRANCH_MANAGER'
                       and c3.effective_to is null),
      'chairs', (select coalesce(string_agg(ch.title, ' / ' order by ch.title), '')
                   from chair_holder h join chair ch on ch.id = h.chair_id
                  where h.person_id = p.id and h.to_date is null),
      'inScheme', exists (
        select 1 from chair_holder h join chair ch on ch.id = h.chair_id
         where h.person_id = p.id and h.to_date is null
           and exists (select 1 from kpi_definition k
                        where k.chair_id = ch.id and k.active and k.position < 100))
    ) as x
    from person p
   where p.employment_status = 'ACTIVE' and p.superseded_by is null
     and exists (select 1 from coverage_rule cr
                  where cr.person_id = p.id and cr.role = 'BRANCH_MANAGER'
                    and cr.effective_to is null)
     and not exists (
       select 1 from chair_holder h join chair ch on ch.id = h.chair_id
        where h.person_id = p.id and h.to_date is null
          and exists (select 1 from kpi_definition k
                       where k.chair_id = ch.id and k.active and k.position < 100))
  ) t;
$fn$;
revoke all on function plb_unseated() from public, anon, authenticated;
