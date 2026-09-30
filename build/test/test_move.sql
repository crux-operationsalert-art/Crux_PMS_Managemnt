-- Moving a person in the reporting line (229)
--
-- person.manager_id is what every visibility rule in 218-226 is built on,
-- so a drag on a tile is not a cosmetic act: it changes who can read whose
-- numbers. These assertions are the reason the rules live in the database
-- and not in the screen that draws the tiles.
--
-- Runs inside a transaction that is rolled back.

begin;

do $seed$
declare
  c_zone uuid; c_br uuid; c_ex uuid;
  s_zone uuid; s_br1 uuid; s_br2 uuid; s_ex uuid;
  p_adm uuid; p_hr uuid; p_zm uuid; p_bm1 uuid; p_bm2 uuid;
  p_e1 uuid; p_e2 uuid; p_out uuid;
begin
  insert into chair (code, title, level) values ('MV_Z','Move zone','zone')
    returning id into c_zone;
  insert into chair (code, title, level, parent_id)
    values ('MV_B','Move branch','branch', c_zone) returning id into c_br;
  insert into chair (code, title, level, parent_id)
    values ('MV_E','Move exec','executive', c_br) returning id into c_ex;
  insert into chair_seating (chair_id, scope_label) values (c_zone,'West')
    returning id into s_zone;
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (c_br,'Pune', s_zone) returning id into s_br1;
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (c_br,'Nashik', s_zone) returning id into s_br2;
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (c_ex,'Pune', s_br1) returning id into s_ex;

  insert into person (full_name, work_email, app_role)
    values ('MV Admin','mv.admin@example.invalid','ADMIN') returning id into p_adm;
  insert into person (full_name, work_email, department, app_role)
    values ('MV HR','mv.hr@example.invalid','Human Resources','MANAGER')
    returning id into p_hr;
  insert into person (full_name, work_email) values ('MV Zone','mv.zm@example.invalid')
    returning id into p_zm;
  insert into person (full_name, work_email, manager_id)
    values ('MV Branch One','mv.bm1@example.invalid', p_zm) returning id into p_bm1;
  insert into person (full_name, work_email, manager_id)
    values ('MV Branch Two','mv.bm2@example.invalid', p_zm) returning id into p_bm2;
  insert into person (full_name, work_email, manager_id)
    values ('MV Exec One','mv.e1@example.invalid', p_bm1) returning id into p_e1;
  insert into person (full_name, work_email, manager_id)
    values ('MV Exec Two','mv.e2@example.invalid', p_bm1) returning id into p_e2;
  -- Somebody in nobody's line, to prove a stranger cannot be reached.
  insert into person (full_name, work_email) values ('MV Outsider','mv.out@example.invalid')
    returning id into p_out;

  insert into chair_holder (chair_id, seating_id, person_id, is_primary) values
    (c_zone, s_zone, p_zm, true),
    (c_br,   s_br1,  p_bm1, true),
    (c_br,   s_br2,  p_bm2, true),
    (c_ex,   s_ex,   p_e1, true);
end $seed$;

do $t$
declare
  p_adm uuid; p_hr uuid; p_zm uuid; p_bm1 uuid; p_bm2 uuid;
  p_e1 uuid; p_e2 uuid; p_out uuid; o jsonb; n int;
begin
  select id into p_adm from person where work_email='mv.admin@example.invalid';
  select id into p_hr  from person where work_email='mv.hr@example.invalid';
  select id into p_zm  from person where work_email='mv.zm@example.invalid';
  select id into p_bm1 from person where work_email='mv.bm1@example.invalid';
  select id into p_bm2 from person where work_email='mv.bm2@example.invalid';
  select id into p_e1  from person where work_email='mv.e1@example.invalid';
  select id into p_e2  from person where work_email='mv.e2@example.invalid';
  select id into p_out from person where work_email='mv.out@example.invalid';

  -- ================================================== the subtree itself
  select count(*) into n from org_subtree(p_zm);
  if n = 5
    then raise notice 'PASS  a subtree holds the person and everybody under them (5)';
    else raise exception 'FAIL  the zone subtree held % people', n; end if;

  if (select depth from org_subtree(p_zm) where person_id = p_e1) = 2
    then raise notice 'PASS  and depth counts the steps down, not the rows';
    else raise exception 'FAIL  the executive was not two steps below the zone'; end if;

  -- ===================================================== rule 3, myself
  o := org_move_person(p_bm1, p_bm1, p_bm2);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  nobody moves themselves';
    else raise exception 'FAIL  a person moved themselves: %', left(o::text,120); end if;

  o := org_move_person(p_bm1, p_zm, p_bm2);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  and nobody moves the person they report to';
    else raise exception 'FAIL  somebody re-parented their own manager'; end if;

  -- =============================================== rule 1, my own team
  o := org_move_person(p_bm1, p_e1, p_e2);
  if (o->>'ok')::boolean and (o->>'changed')::boolean
    then raise notice 'PASS  a manager re-hangs one of their people under another';
    else raise exception 'FAIL  a legitimate move was refused: %', left(o::text,160); end if;

  if (select manager_id from person where id = p_e1) = p_e2
    then raise notice 'PASS  and the reporting line actually changed';
    else raise exception 'FAIL  the move reported success and changed nothing'; end if;

  -- put it back, so the later assertions read a tidy tree
  perform org_move_person(p_bm1, p_e1, p_bm1);

  -- ------------------------------------------ outside my team, refused
  o := org_move_person(p_bm1, p_out, p_bm1);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  a stranger cannot be pulled into somebody''s team';
    else raise exception 'FAIL  a manager adopted somebody outside their line'; end if;

  o := org_move_person(p_bm1, p_e1, p_bm2);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  nor pushed out to a manager they cannot see';
    else raise exception 'FAIL  a person was moved out of the mover''s own team'; end if;

  -- =============================================== rule 4, the ring
  o := org_move_person(p_adm, p_zm, p_e1);
  if o->>'error' = 'would_loop'
    then raise notice 'PASS  a move that would make somebody their own ancestor is refused';
    else raise exception 'FAIL  the reporting line was allowed to become a ring: %',
      left(o::text,160); end if;

  if (select manager_id from person where id = p_zm) is null
    then raise notice 'PASS  and the refusal changed nothing';
    else raise exception 'FAIL  a refused move still wrote'; end if;

  o := org_move_person(p_adm, p_e1, p_e1);
  if o->>'error' = 'would_loop'
    then raise notice 'PASS  and nobody reports to themselves';
    else raise exception 'FAIL  a person was made their own manager'; end if;

  -- ===================================================== rule 2, HR
  o := org_move_person(p_hr, p_e1, p_bm2);
  if (o->>'ok')::boolean
    then raise notice 'PASS  HR moves a person between two managers who cannot see each other';
    else raise exception 'FAIL  HR was refused: %', left(o::text,160); end if;

  o := org_move_person(p_adm, p_out, p_bm1);
  if (o->>'ok')::boolean
    then raise notice 'PASS  and an administrator places somebody who was in no line at all';
    else raise exception 'FAIL  the administrator was refused: %', left(o::text,160); end if;

  -- --------------------------------------------- a move that is no move
  o := org_move_person(p_adm, p_out, p_bm1);
  if (o->>'ok')::boolean and not (o->>'changed')::boolean
    then raise notice 'PASS  moving somebody where they already are changes nothing and says so';
    else raise exception 'FAIL  a no-op move reported a change'; end if;

  -- -------------------------------------------------- it leaves a trail
  if exists (select 1 from audit_entry
              where action = 'REPORTING_CHANGED' and entity_ref = p_e1::text)
    then raise notice 'PASS  every move is on the record, because visibility moved with it';
    else raise exception 'FAIL  a reporting change left no audit row'; end if;

  -- ======================================================== the tree read
  -- Six, not the five the fixture started with: the administrator placed
  -- the Outsider under Branch One a few assertions ago, and HR moved Exec
  -- One across to Branch Two. The tree is read after those moves, so it
  -- must show them -- a count of five here would mean the tree was stale.
  o := org_team_tree(p_zm, null, null);
  select count(*) into n from jsonb_array_elements(o->'people');
  if n = 6
    then raise notice 'PASS  a manager reads their whole line as tiles, moves included (6)';
    else raise exception 'FAIL  the tree held % tiles', n; end if;

  if (select (t->>'managerId')::uuid from jsonb_array_elements(o->'people') t
       where (t->>'personId')::uuid = p_e1) = p_bm2
    then raise notice 'PASS  and it shows the new manager, not the one from before the move';
    else raise exception 'FAIL  the tree still reported the old reporting line'; end if;

  select count(*) into n from jsonb_array_elements(o->'people') t
   where (t->>'mayMove')::boolean;
  if n >= 1
    then raise notice 'PASS  and each tile says whether this viewer may move it';
    else raise exception 'FAIL  no tile was movable by the manager of the whole tree'; end if;

  if (select (t->>'mayMove')::boolean from jsonb_array_elements(o->'people') t
       where (t->>'depth')::int = 0) = false
    then raise notice 'PASS  the root of your own tree is not draggable, which is right';
    else raise exception 'FAIL  somebody could drag the root of their own tree'; end if;

  -- ----------------------------------------------- and it obeys the line
  o := org_team_tree(p_e2, p_zm, null);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  an executive cannot read the zone''s tree by asking for it';
    else raise exception 'FAIL  the tree was readable upwards'; end if;

  raise notice '--- moving a person: every assertion passed ---';
end $t$;

rollback;
