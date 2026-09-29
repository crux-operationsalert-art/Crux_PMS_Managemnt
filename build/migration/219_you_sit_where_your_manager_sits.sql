-- =====================================================================
-- 219 · You sit where your manager sits
--
-- Reported: about a hundred people the org chart cannot place, most of
-- them with "no coverage to place them by", two with "their coverage is in
-- a place the chart has no seat for", and one whose "coverage spans North,
-- North East & East, other West locations, South".
--
-- The real count is 82 of the 101 seated holders, and the report's own
-- headline reason turns out to be the smaller half of it. Classified
-- against the live database:
--
--     the chair has no seating at all ................... 69
--     no coverage to place them by ...................... 11
--     coverage in a place the chart has no seat for ...... 1
--     coverage spans four regions ........................ 1
--
-- Sixty-nine of the eighty-two are not a missing-data problem. Seven
-- chairs -- EXECUTIVE (63 holders), CEO_MD, VP_FINANCE,
-- HEAD_HR_OPERATIONS, HEAD_FINANCE_OPERATIONS, HR_EXECUTIVE and
-- SALES_MANAGER -- have no row in chair_seating at all. There is no seat
-- to put anybody in. Migration 114 could only ever report that, because it
-- places a holder into an existing seating and never makes one.
--
-- WHY THIS MATTERS MORE THAN IT DID
--
-- An unplaced holder used to mean a gap on a drawing. Since migration 218
-- the seating tree is half the reporting line, so an unplaced holder is a
-- person who is in nobody's team and has no team of their own. 218 fails
-- closed, which is the right way round, and this is the other half of it.
--
-- THE RULE
--
-- A person sits where their manager sits, unless their own coverage
-- already said otherwise. That is not a guess: it is what the data says
-- when you ask it. Of the thirteen holders whose chairs do have seatings,
-- eight resolve to a place their own chair already has --
--
--     Parag Mayekar          Branch Manager   Pune
--     Adhi Gour              Team Leader      Hyderabad Zone
--     ASHISH PAWAR           Team Leader      Mumbai
--     GIRISH KATE            Team Leader      Pune
--     PARI VAITY             Team Leader      Mumbai
--     ROOPA R                Team Leader      Bengaluru + Rest Of Karnataka + Kerela
--     SHASHIKALA BHASKAR K   Team Leader      Bengaluru + Rest Of Karnataka + Kerela
--     Vinodh M               Team Leader      Bengaluru + Rest Of Karnataka + Kerela
--
-- -- and the sixty-three Executives resolve the same way, to the place
-- their own Team Leader sits in.
--
-- Where the manager's place has no seat on the person's chair, the seat is
-- CREATED rather than the person left out. Three Branch Manager and
-- Location Partner holders report to the West zonal manager and the chart
-- draws Branch Manager seats as cities, never as zones; a Location Partner
-- who reports to the West zone is a fact about the company whether or not
-- the source chart drew a box for it. Every seating made here carries a
-- note saying it came from the reporting line and not from the chart, so
-- nobody later mistakes it for something the chart said.
--
-- Ordering is why this runs in passes. Ashwini Reddy's manager is
-- SHASHIKALA BHASKAR K, who is herself unplaced until this migration
-- places her; one pass would leave Ashwini behind for a reason that has
-- nothing to do with Ashwini. It repeats until a pass changes nothing, and
-- stops at twelve so a loop in the manager chain cannot spin.
--
-- WHAT IS DELIBERATELY NOT DECIDED HERE
--
-- Vrunda Potdar is a Zonal Manager whose coverage spans four of the
-- chart's regions. The chart gives Zonal Manager eighteen seats, one per
-- zone, and none of them means "four of them". She is seated with no
-- particular place and a note saying which four she covers, rather than
-- being assigned to whichever one sorted first. She is then in the
-- reporting line, which is the thing that was actually broken; the label
-- is a question for whoever owns the chart.
-- =====================================================================

create or replace function org_seat_from_the_line(p_actor uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_role     role_kind;
  r          record;
  v_pass     int := 0;
  v_moved    int;
  v_placed   int := 0;
  v_made     int := 0;
  v_seat     uuid;
  v_detail   jsonb := '[]'::jsonb;
  v_left     jsonb := '[]'::jsonb;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Seating the org chart is an administrator''s to do.');
  end if;

  loop
    v_pass  := v_pass + 1;
    v_moved := 0;

    for r in
      select h.id as holder_id, h.chair_id, pe.full_name, c.code as chair_code,
             ms.id as mgr_seating, ms.scope_label as place, mp.full_name as mgr_name
        from chair_holder h
        join person pe on pe.id = h.person_id
        join chair  c  on c.id  = h.chair_id
        join person mp on mp.id = pe.manager_id and mp.id <> pe.id
        join chair_holder mh on mh.person_id = mp.id and mh.to_date is null
        join chair_seating ms on ms.id = mh.seating_id
       where h.to_date is null
         and h.seating_id is null
         and pe.employment_status = 'ACTIVE'
         and pe.superseded_by is null
       order by c.code, pe.full_name
    loop
      -- The seat on MY chair, in the place MY manager sits in. `is not
      -- distinct from` so that a manager with no particular place matches
      -- a seat with no particular place rather than matching nothing.
      select s.id into v_seat
        from chair_seating s
       where s.chair_id = r.chair_id
         and s.scope_label is not distinct from r.place
       order by s.id
       limit 1;

      if v_seat is null then
        insert into chair_seating (chair_id, scope_label, reports_to_seating_id, note)
        values (r.chair_id, r.place, r.mgr_seating,
                'Made by migration 219 from the reporting line, not from the '
                || 'source chart: ' || r.full_name || ' reports to ' || r.mgr_name
                || ', who sits in ' || coalesce(r.place, 'no particular place')
                || ', and this chair had no seat there.')
        returning id into v_seat;
        v_made := v_made + 1;
      end if;

      update chair_holder set seating_id = v_seat where id = r.holder_id;
      v_placed := v_placed + 1;
      v_moved  := v_moved + 1;
      v_detail := v_detail || jsonb_build_object(
        'person', r.full_name, 'chair', r.chair_code,
        'place', coalesce(r.place, 'No particular place'), 'from', r.mgr_name);
    end loop;

    exit when v_moved = 0 or v_pass >= 12;
  end loop;

  -- Whoever is still standing, and why -- in the same words migration 114
  -- uses, so the two reports read as one.
  select coalesce(jsonb_agg(jsonb_build_object(
           'person', q.full_name, 'chair', q.code, 'why', q.why)
         order by q.code, q.full_name), '[]'::jsonb)
    into v_left
    from (
      select pe.full_name, c.code,
             case
               when pe.manager_id is null then 'no manager on record to sit beside'
               when not exists (select 1 from chair_holder mh
                                 where mh.person_id = pe.manager_id and mh.to_date is null)
                 then 'their manager holds no chair'
               else 'their manager has no place either'
             end as why
        from chair_holder h
        join person pe on pe.id = h.person_id
        join chair  c  on c.id  = h.chair_id
       where h.to_date is null and h.seating_id is null
         and pe.employment_status = 'ACTIVE' and pe.superseded_by is null) q;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'CHAIR_HOLDERS_SEATED_FROM_LINE', 'chair_holder', 'bulk',
          jsonb_build_object('passes', v_pass, 'placed', v_placed,
                             'seatings_made', v_made,
                             'left', jsonb_array_length(v_left)));

  return jsonb_build_object(
    'passes', v_pass, 'placed', v_placed, 'seatingsMade', v_made,
    'detail', v_detail,
    'unplaced', jsonb_array_length(v_left), 'left', v_left);
end $function$;

comment on function org_seat_from_the_line(uuid) is
  'Seats every chair holder who has no place, in the place their manager '
  'sits in, making the seat if the chair has none there. Runs in passes so '
  'a person whose manager is themselves unplaced is not left behind, and '
  'stops at twelve so a loop in the manager chain cannot spin. Migration '
  '114''s chair_place_from_coverage runs first and decides from the '
  'person''s own coverage; this is what is left after it.';

revoke all on function org_seat_from_the_line(uuid) from public, anon, authenticated;

-- ------------------------------------------------ the one it cannot decide
--
-- A Zonal Manager whose coverage spans four of the chart's regions. Seated
-- with no particular place rather than assigned to whichever region sorted
-- first, so she is in the reporting line -- which is what was broken --
-- while the label stays an open question for whoever owns the chart.
do $$
declare v_person uuid; v_holder uuid; v_chair uuid; v_seat uuid; v_mgr uuid;
begin
  select pe.id, h.id, h.chair_id
    into v_person, v_holder, v_chair
    from person pe
    join chair_holder h on h.person_id = pe.id and h.to_date is null
    join chair c on c.id = h.chair_id
   where pe.full_name = 'Vrunda Potdar' and c.code = 'ZONAL_MANAGER'
     and h.seating_id is null
   limit 1;

  if v_holder is null then
    raise notice '219: Vrunda Potdar is already seated, or is no longer a Zonal Manager.';
    return;
  end if;

  select mh.seating_id into v_mgr
    from person pe join chair_holder mh
      on mh.person_id = pe.manager_id and mh.to_date is null
   where pe.id = v_person;

  select s.id into v_seat from chair_seating s
   where s.chair_id = v_chair and s.scope_label is null limit 1;

  if v_seat is null then
    insert into chair_seating (chair_id, scope_label, reports_to_seating_id, note)
    values (v_chair, null, v_mgr,
            'Made by migration 219. This holder''s coverage spans North, '
            || 'North East & East, other West locations and South. The chart '
            || 'gives Zonal Manager one seat per zone and none that means '
            || 'four of them, so the place is left open rather than guessed.')
    returning id into v_seat;
  end if;

  update chair_holder set seating_id = v_seat where id = v_holder;
end $$;
