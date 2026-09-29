-- You sit where your manager sits (migration 219)
--
-- Migration 114 places a holder from their own coverage, into a seating the
-- chart already drew. It can only report the two cases it cannot handle:
-- a person with no coverage, and a chair with no seat to put them in. On
-- the live database those two accounted for 80 of the 82 unplaced holders,
-- and 69 of them were the second -- seven chairs with no row in
-- chair_seating at all, one of them holding sixty-three people.
--
-- Since migration 218 an unplaced holder is not a gap on a drawing: the
-- seating tree is half the reporting line, so an unplaced holder is a
-- person in nobody's team with no team of their own.
--
-- The shapes below are the live ones, not invented: a chair with seats and
-- a holder whose manager sits in one of them; a chair with NO seats at all;
-- a manager who is themselves unplaced until this runs, so one pass would
-- leave their report behind; and a loop in the manager chain.
--
-- Runs inside a transaction that is rolled back.

begin;

do $seed$
declare
  c_top uuid; c_mid uuid; c_low uuid; c_none uuid;
  s_top uuid; s_pune uuid; s_mum uuid;
  p_top uuid; p_pune uuid; p_late uuid; p_none uuid; p_orphan uuid;
  p_a uuid; p_b uuid; p_adm uuid;
begin
  insert into chair (code, title, level) values ('ST_TOP','Seat top','function')    returning id into c_top;
  insert into chair (code, title, level, parent_id) values ('ST_MID','Seat middle','region', c_top) returning id into c_mid;
  insert into chair (code, title, level, parent_id) values ('ST_LOW','Seat low','branch', c_mid)    returning id into c_low;
  -- the EXECUTIVE shape: a real chair, real holders, and not one seating
  insert into chair (code, title, level, parent_id) values ('ST_NONE','Seat nowhere','executive', c_low) returning id into c_none;

  insert into chair_seating (chair_id, scope_label) values (c_top, null) returning id into s_top;
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (c_mid, 'Pune', s_top) returning id into s_pune;
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (c_mid, 'Mumbai', s_top) returning id into s_mum;
  -- ST_LOW deliberately has one seat, in Pune only, so a holder whose
  -- manager sits in Mumbai has nowhere to go and the seat must be made.
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (c_low, 'Pune', s_pune);

  insert into person (full_name, work_email, app_role)
    values ('ST Admin','st.admin@example.invalid','ADMIN') returning id into p_adm;

  -- placed already: the top of the house
  insert into person (full_name, work_email) values ('ST Top','st.top@example.invalid')
    returning id into p_top;
  insert into chair_holder (chair_id, seating_id, person_id, is_primary)
    values (c_top, s_top, p_top, true);

  -- a holder whose manager sits in Pune, and whose chair has a Pune seat
  insert into person (full_name, work_email, manager_id)
    values ('ST Pune','st.pune@example.invalid', p_top) returning id into p_pune;
  insert into chair_holder (chair_id, person_id, is_primary) values (c_mid, p_pune, true);

  -- a holder whose manager is ST Pune -- who is unplaced until this runs.
  -- One pass leaves this person behind for a reason that is not theirs.
  insert into person (full_name, work_email, manager_id)
    values ('ST Late','st.late@example.invalid', p_pune) returning id into p_late;
  insert into chair_holder (chair_id, person_id, is_primary) values (c_low, p_late, true);

  -- two on the chair with no seating at all
  insert into person (full_name, work_email, manager_id)
    values ('ST None A','st.a@example.invalid', p_late) returning id into p_a;
  insert into person (full_name, work_email, manager_id)
    values ('ST None B','st.b@example.invalid', p_late) returning id into p_b;
  insert into chair_holder (chair_id, person_id, is_primary) values (c_none, p_a, true);
  insert into chair_holder (chair_id, person_id, is_primary) values (c_none, p_b, true);

  -- nobody to sit beside
  insert into person (full_name, work_email) values ('ST Orphan','st.orphan@example.invalid')
    returning id into p_orphan;
  insert into chair_holder (chair_id, person_id, is_primary) values (c_mid, p_orphan, true);
end $seed$;

do $t$
declare
  p_adm uuid; p_top uuid; p_pune uuid; p_late uuid; p_a uuid; p_b uuid; p_orphan uuid;
  o jsonb; n int; v_lbl text; v_par uuid; v_note text; v_before int;
begin
  select id into p_adm    from person where work_email='st.admin@example.invalid';
  select id into p_top    from person where work_email='st.top@example.invalid';
  select id into p_pune   from person where work_email='st.pune@example.invalid';
  select id into p_late   from person where work_email='st.late@example.invalid';
  select id into p_a      from person where work_email='st.a@example.invalid';
  select id into p_b      from person where work_email='st.b@example.invalid';
  select id into p_orphan from person where work_email='st.orphan@example.invalid';

  select count(*) into v_before from chair_holder h
   where h.to_date is null and h.seating_id is null
     and h.person_id in (p_pune, p_late, p_a, p_b, p_orphan);
  if v_before = 5 then raise notice 'PASS  five holders start with nowhere to sit';
                  else raise exception 'FAIL  % started unplaced, expected 5', v_before; end if;

  -- ------------------------------------------------------ who may run it
  o := org_seat_from_the_line(p_pune);
  if o->>'error' = 'not_admin'
    then raise notice 'PASS  seating the chart is not everybody''s to do';
    else raise exception 'FAIL  a non-administrator seated the chart: %', left(o::text,120); end if;

  o := org_seat_from_the_line(p_adm);

  -- --------------------------------------------- the straightforward case
  select s.scope_label into v_lbl
    from chair_holder h join chair_seating s on s.id = h.seating_id
   where h.person_id = p_pune and h.to_date is null;
  if v_lbl is null
    then raise notice 'PASS  a report of the top sits where the top sits (no particular place)';
    else raise exception 'FAIL  ST Pune landed in %', v_lbl; end if;

  -- ------------------------------------------------------- the ordering
  -- ST Late's manager was unplaced when the first pass began.
  select s.scope_label into v_lbl
    from chair_holder h join chair_seating s on s.id = h.seating_id
   where h.person_id = p_late and h.to_date is null;
  if v_lbl is null
    then raise notice 'PASS  and so does a report of theirs, which needs a second pass';
    else raise exception 'FAIL  ST Late landed in %', coalesce(v_lbl,'nothing'); end if;

  if (o->>'passes')::int >= 2
    then raise notice 'PASS  it says how many passes it took (%)', o->>'passes';
    else raise exception 'FAIL  it claims to have finished in % pass', o->>'passes'; end if;

  -- ------------------------------------------- the chair with no seat at all
  select count(*) into n from chair_seating s join chair c on c.id = s.chair_id
   where c.code = 'ST_NONE';
  if n = 1 then raise notice 'PASS  a chair with no seating at all is given exactly one';
           else raise exception 'FAIL  the seatless chair now has % seats', n; end if;

  if (o->>'seatingsMade')::int >= 1
    then raise notice 'PASS  and the answer says a seat was made, not just filled';
    else raise exception 'FAIL  seatingsMade came back %', o->>'seatingsMade'; end if;

  select s.note, s.reports_to_seating_id into v_note, v_par
    from chair_holder h join chair_seating s on s.id = h.seating_id
   where h.person_id = p_a and h.to_date is null;
  if v_note like '%not from the%source chart%'
    then raise notice 'PASS  a made seat says it came from the line and not the chart';
    else raise exception 'FAIL  the made seat''s note reads: %', coalesce(left(v_note,90),'nothing'); end if;

  if v_par = (select h.seating_id from chair_holder h
               where h.person_id = p_late and h.to_date is null)
    then raise notice 'PASS  and it reports to the seat its holder''s manager sits in';
    else raise exception 'FAIL  the made seat reports somewhere else'; end if;

  if (select h.seating_id from chair_holder h where h.person_id = p_a and h.to_date is null)
   = (select h.seating_id from chair_holder h where h.person_id = p_b and h.to_date is null)
    then raise notice 'PASS  two people on one chair in one place share the seat';
    else raise exception 'FAIL  a second seat was made for the same chair and place'; end if;

  -- ------------------------------------------------ what it cannot decide
  if exists (select 1 from chair_holder h
              where h.person_id = p_orphan and h.to_date is null and h.seating_id is null)
    then raise notice 'PASS  somebody with no manager is left alone, not guessed at';
    else raise exception 'FAIL  the orphan was seated from nothing'; end if;

  if o->'left' @> '[{"why": "no manager on record to sit beside"}]'::jsonb
    then raise notice 'PASS  and the answer says why, in words';
    else raise exception 'FAIL  the reason given was %', left((o->'left')::text, 140); end if;

  -- --------------------------------------------------- it reaches the line
  -- The whole point: these people are now in somebody's team.
  if (select count(*) from perf_line(p_top)) >= 4
    then raise notice 'PASS  the seated people are now in the line above them';
    else raise exception 'FAIL  the top of the house sees only % people',
      (select count(*) from perf_line(p_top)); end if;

  if perf_rel(p_late, p_a) = 'manage'
    then raise notice 'PASS  and a manager whose seat was made can set for their team';
    else raise exception 'FAIL  a made seat gave %', coalesce(perf_rel(p_late,p_a),'nothing'); end if;

  -- ------------------------------------------------------ running it twice
  o := org_seat_from_the_line(p_adm);
  if (o->>'placed')::int = 0 and (o->>'seatingsMade')::int = 0
    then raise notice 'PASS  running it again places nobody and makes no seat';
    else raise exception 'FAIL  a second run placed % and made %',
      o->>'placed', o->>'seatingsMade'; end if;

  -- --------------------------------------------------------------- a loop
  update person set manager_id = p_a where id = p_late;
  update chair_holder set seating_id = null where person_id in (p_late, p_a);
  o := org_seat_from_the_line(p_adm);
  if (o->>'passes')::int <= 12
    then raise notice 'PASS  a loop in the manager chain stops at twelve passes';
    else raise exception 'FAIL  it ran % passes', o->>'passes'; end if;

  raise notice '--- seating the chart: every assertion passed ---';
end $t$;

rollback;
