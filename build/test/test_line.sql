-- My team is the people who report to me (migration 218)
--
-- The rule being asserted, in the words it was given in:
--
--   "One should only be able to see and update things for his team and see
--    the details and progress from level 2 and below. So 1st layer/level I
--    work as a manager and below my level I just see and see the progress
--    performance etc."
--
-- Two lines, and the third that neither says out loud: somebody who is not
-- below me at all is not mine to see. That third line is the one that was
-- broken -- a Team Leader came back with seventy-one people in their team
-- -- so most of what is below asserts an absence.
--
-- Everything runs inside a transaction that is rolled back, and seeds its
-- own chairs, seatings and people, so it runs on a database rebuilt from
-- build/schema alone and leaves nothing behind either way.

begin;

do $seed$
declare
  v_top uuid; v_mid uuid; v_low uuid; v_out uuid;
  s_top uuid; s_mw uuid; s_me uuid; s_lw uuid; s_le uuid; s_out uuid;
  p_top uuid; p_mw uuid; p_me uuid; p_lw uuid; p_le uuid; p_out uuid;
  p_hr uuid; p_adm uuid; p_free uuid; p_boss uuid;
begin
  -- Four chairs. The middle chair is held in two places at once, which is
  -- the shape the real chart has and the shape the old function could not
  -- tell apart: one Branch Manager chair, thirty-nine places.
  insert into chair (code, title, level) values ('LN_TOP','Line top','function')
    returning id into v_top;
  insert into chair (code, title, level, parent_id) values ('LN_MID','Line middle','region', v_top)
    returning id into v_mid;
  insert into chair (code, title, level, parent_id) values ('LN_LOW','Line bottom','branch', v_mid)
    returning id into v_low;
  insert into chair (code, title, level) values ('LN_OUT','Line elsewhere','function')
    returning id into v_out;

  insert into chair_seating (chair_id, scope_label) values (v_top, null) returning id into s_top;
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (v_mid, 'West', s_top) returning id into s_mw;
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (v_mid, 'South', s_top) returning id into s_me;
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (v_low, 'West', s_mw) returning id into s_lw;
  insert into chair_seating (chair_id, scope_label, reports_to_seating_id)
    values (v_low, 'South', s_me) returning id into s_le;
  insert into chair_seating (chair_id, scope_label) values (v_out, null) returning id into s_out;

  insert into person (full_name, work_email) values ('LN Top',  'ln.top@example.invalid')  returning id into p_top;
  insert into person (full_name, work_email) values ('LN MidW', 'ln.mw@example.invalid')   returning id into p_mw;
  insert into person (full_name, work_email) values ('LN MidS', 'ln.ms@example.invalid')   returning id into p_me;
  insert into person (full_name, work_email) values ('LN LowW', 'ln.lw@example.invalid')   returning id into p_lw;
  insert into person (full_name, work_email) values ('LN LowS', 'ln.ls@example.invalid')   returning id into p_le;
  insert into person (full_name, work_email) values ('LN Out',  'ln.out@example.invalid')  returning id into p_out;

  insert into chair_holder (chair_id, seating_id, person_id, is_primary) values
    (v_top, s_top, p_top, true),
    (v_mid, s_mw,  p_mw,  true),
    (v_mid, s_me,  p_me,  true),
    (v_low, s_lw,  p_lw,  true),
    (v_low, s_le,  p_le,  true),
    (v_out, s_out, p_out, true);

  -- The other way the company records a line, on a person with no seat at
  -- all. Both edges have to count or somebody's team goes blank for a
  -- reason that has nothing to do with who they manage.
  insert into person (full_name, work_email) values ('LN Boss', 'ln.boss@example.invalid')
    returning id into p_boss;
  insert into person (full_name, work_email, manager_id)
    values ('LN Free', 'ln.free@example.invalid', p_boss) returning id into p_free;

  -- The two who used to be able to set anybody's score.
  insert into person (full_name, work_email, department)
    values ('LN HR', 'ln.hr@example.invalid', 'Human Resources') returning id into p_hr;
  insert into person (full_name, work_email, app_role)
    values ('LN Admin', 'ln.admin@example.invalid', 'ADMIN') returning id into p_adm;

  -- A month to ask about. perf_tree wants a real cycle; without one it
  -- answers no_such_cycle_or_person, and the assertions below would be
  -- testing that message rather than the gate in front of it.
  insert into perf_cycle (period_start, assign_opens, assign_closes, entry_closes)
  values (date_trunc('month', current_date)::date,
          date_trunc('month', current_date)::date,
          date_trunc('month', current_date)::date + 9,
          (date_trunc('month', current_date) + interval '1 month - 1 day')::date)
  on conflict (period_start, period_kind) do update
     set assign_opens = excluded.assign_opens,
         assign_closes = excluded.assign_closes,
         entry_closes = excluded.entry_closes;
end $seed$;

do $t$
declare
  p_top uuid; p_mw uuid; p_me uuid; p_lw uuid; p_le uuid; p_out uuid;
  p_hr uuid; p_adm uuid; p_free uuid; p_boss uuid;
  n int; d int; r jsonb; v_rel text; v_cyc uuid;
begin
  select id into p_top  from person where work_email='ln.top@example.invalid';
  select id into p_mw   from person where work_email='ln.mw@example.invalid';
  select id into p_me   from person where work_email='ln.ms@example.invalid';
  select id into p_lw   from person where work_email='ln.lw@example.invalid';
  select id into p_le   from person where work_email='ln.ls@example.invalid';
  select id into p_out  from person where work_email='ln.out@example.invalid';
  select id into p_hr   from person where work_email='ln.hr@example.invalid';
  select id into p_adm  from person where work_email='ln.admin@example.invalid';
  select id into p_free from person where work_email='ln.free@example.invalid';
  select id into p_boss from person where work_email='ln.boss@example.invalid';
  select id into v_cyc  from perf_cycle
   where period_start = date_trunc('month', current_date)::date;

  -- ------------------------------------------------- the line, and its depth
  select depth into d from perf_line(p_top) where person_id = p_mw;
  if d = 1 then raise notice 'PASS  my own report is one step below me';
           else raise exception 'FAIL  a direct report came back at depth %', coalesce(d::text,'nothing'); end if;

  select depth into d from perf_line(p_top) where person_id = p_lw;
  if d = 2 then raise notice 'PASS  and their report is two';
           else raise exception 'FAIL  a report''s report came back at depth %', coalesce(d::text,'nothing'); end if;

  select count(*) into n from perf_line(p_top);
  if n = 4 then raise notice 'PASS  the whole line below the top is four people, not the company';
           else raise exception 'FAIL  the top of the line sees % people, expected 4', n; end if;

  -- ------------------------------------------------ the sibling's team
  -- This is the report, exactly: "people are seeing the team of other
  -- people". West's manager has no business with South's branch.
  if perf_rel(p_mw, p_le) is null
    then raise notice 'PASS  I cannot see the team of the manager beside me';
    else raise exception 'FAIL  West reached South''s report as %', perf_rel(p_mw, p_le); end if;

  if perf_rel(p_mw, p_me) is null
    then raise notice 'PASS  nor the manager beside me';
    else raise exception 'FAIL  West reached South as %', perf_rel(p_mw, p_me); end if;

  if perf_rel(p_mw, p_top) is null
    then raise notice 'PASS  nor my own manager, looking upwards';
    else raise exception 'FAIL  a report reached their manager as %', perf_rel(p_mw, p_top); end if;

  if perf_rel(p_mw, p_out) is null
    then raise notice 'PASS  nor somebody in another line entirely';
    else raise exception 'FAIL  reached another line as %', perf_rel(p_mw, p_out); end if;

  -- ------------------------------------------ see and set are not the same
  if perf_rel(p_mw, p_lw) = 'manage'
    then raise notice 'PASS  my own team reads as mine to manage';
    else raise exception 'FAIL  a direct report read as %', coalesce(perf_rel(p_mw,p_lw),'nothing'); end if;

  if perf_rel(p_top, p_lw) = 'watch'
    then raise notice 'PASS  two steps down reads as mine to watch';
    else raise exception 'FAIL  two steps down read as %', coalesce(perf_rel(p_top,p_lw),'nothing'); end if;

  if perf_may_see(p_top, p_lw) and not perf_may_set(p_top, p_lw)
    then raise notice 'PASS  and watching is seeing without setting';
    else raise exception 'FAIL  level 2 came back see=% set=%',
      perf_may_see(p_top,p_lw), perf_may_set(p_top,p_lw); end if;

  if perf_may_set(p_mw, p_lw)
    then raise notice 'PASS  level 1 is seeing and setting both';
    else raise exception 'FAIL  a manager could not set their own report'; end if;

  -- --------------------------------------------- the list matches the gate
  select count(*) into n from kpi_subtree_people(p_top);
  if n = 2 then raise notice 'PASS  the list I may write to is my team, not my line';
           else raise exception 'FAIL  the write list held % people, expected 2', n; end if;

  if not exists (select 1 from kpi_subtree_people(p_top) s where s.person_id = p_lw)
    then raise notice 'PASS  and it stops at one step down';
    else raise exception 'FAIL  the write list reached two steps down'; end if;

  select count(*) into n
    from person p where perf_may_set(p_top, p.id)
     and not exists (select 1 from kpi_subtree_people(p_top) s where s.person_id = p.id);
  if n = 0 then raise notice 'PASS  nobody the gate allows is missing from the list';
           else raise exception 'FAIL  % people pass the gate but are not offered', n; end if;

  -- ------------------------------------------------------------ myself
  if perf_rel(p_mw, p_mw) = 'self' and not perf_may_set(p_mw, p_mw)
    then raise notice 'PASS  I am myself, and I do not set my own score';
    else raise exception 'FAIL  self read as % / set %',
      perf_rel(p_mw,p_mw), perf_may_set(p_mw,p_mw); end if;

  -- ---------------------------------------- a department is not a licence
  -- Until 218 anyone in Human Resources or Business Excellence could set
  -- any person in the company. Running the scheme is a different act.
  if not perf_may_set(p_hr, p_lw) and not perf_may_see(p_hr, p_lw)
    then raise notice 'PASS  being in Human Resources is not a reason to see somebody';
    else raise exception 'FAIL  HR reached a stranger: see=% set=%',
      perf_may_see(p_hr,p_lw), perf_may_set(p_hr,p_lw); end if;

  if perf_may_set(p_adm, p_lw) and perf_rel(p_adm, p_lw) = 'admin'
    then raise notice 'PASS  an administrator still reaches everybody, and says so';
    else raise exception 'FAIL  the administrator was refused'; end if;

  -- ------------------------------------------- the other way a line is kept
  if perf_rel(p_boss, p_free) = 'manage'
    then raise notice 'PASS  a manager recorded on the person record counts too';
    else raise exception 'FAIL  manager_id gave %', coalesce(perf_rel(p_boss,p_free),'nothing'); end if;

  if perf_rel(p_free, p_boss) is null
    then raise notice 'PASS  and it only points one way';
    else raise exception 'FAIL  manager_id read upwards as %', perf_rel(p_free,p_boss); end if;

  -- ----------------------------------------------- the reads that had no gate
  r := perf_tree_for(p_mw, p_le, v_cyc);
  if r->>'error' = 'not_permitted'
    then raise notice 'PASS  asking for another line''s tree by id is refused';
    else raise exception 'FAIL  perf_tree_for handed over a stranger''s tree: %', left(r::text, 120); end if;

  r := perf_history_for(p_mw, p_le, null, null, 6);
  if r->>'error' = 'not_permitted'
    then raise notice 'PASS  and so is their six months of history';
    else raise exception 'FAIL  perf_history_for answered for a stranger'; end if;

  r := perf_kpi_score_for(p_mw, p_le, v_cyc);
  if r->>'error' = 'not_permitted'
    then raise notice 'PASS  and so is their score';
    else raise exception 'FAIL  perf_kpi_score_for answered for a stranger'; end if;

  r := perf_tree_for(p_mw, p_lw, v_cyc);
  if r->>'error' is null and r->>'rel' = 'manage' and (r->>'maySet')::boolean
    then raise notice 'PASS  my own report''s tree comes back, marked as mine to set';
    else raise exception 'FAIL  my own report''s tree came back as %', left(r::text, 160); end if;

  r := perf_tree_for(p_top, p_lw, v_cyc);
  if r->>'error' is null and r->>'rel' = 'watch' and not (r->>'maySet')::boolean
    then raise notice 'PASS  two steps down comes back marked read-only';
    else raise exception 'FAIL  two steps down came back as %', left(r::text, 160); end if;

  -- ------------------------------------------------------------- a cycle
  -- Two people recorded as each other's manager is a data error, not a
  -- reason for the Performance screen to hang.
  update person set manager_id = p_free where id = p_boss;
  select count(*) into n from perf_line(p_boss);
  if n >= 1 then raise notice 'PASS  a loop in the reporting line terminates (% people)', n;
            else raise exception 'FAIL  a loop returned nothing'; end if;
  update person set manager_id = null where id = p_boss;

  -- ----------------------------------------------------- nobody by default
  if (select count(*) from perf_line(p_out)) = 0 and perf_rel(p_out, p_lw) is null
    then raise notice 'PASS  somebody with no reports has no team, and sees nobody';
    else raise exception 'FAIL  a person with no reports saw somebody'; end if;

  raise notice '--- who may see whom: every assertion passed ---';
end $t$;

rollback;
