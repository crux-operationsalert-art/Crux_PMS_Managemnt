-- A measure can be changed after it is given (migration 240)
--
-- Two verbs, perf_assign_edit and perf_assign_remove, and the whole of what
-- they are for is who may call them and what they refuse to break.
--
-- The cycle is made here rather than found, so this says the same thing in
-- any month. Everything is rolled back.

begin;

do $seed$
declare p_boss uuid; p_mgr uuid; p_rep uuid; p_two uuid; p_hr uuid; v_cyc uuid;
begin
  -- A boss above the manager, because a manager's OWN measure is set by
  -- their manager and not by themselves -- which is the rule this whole
  -- migration is in service of, and which the first draft of this test
  -- forgot while testing it.
  insert into person (full_name, work_email, app_role)
    values ('ED Boss', 'ed.boss@example.invalid', 'MANAGER') returning id into p_boss;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('ED Manager', 'ed.mgr@example.invalid', 'MANAGER', p_boss) returning id into p_mgr;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('ED Report', 'ed.rep@example.invalid', 'VIEWER', p_mgr) returning id into p_rep;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('ED Second', 'ed.two@example.invalid', 'VIEWER', p_mgr) returning id into p_two;
  insert into person (full_name, work_email, app_role, department)
    values ('ED HR', 'ed.hr@example.invalid', 'MANAGER', 'Human Resources') returning id into p_hr;

  insert into perf_cycle (period_start, assign_opens, assign_closes, entry_closes)
  values (date_trunc('month', current_date)::date,
          date_trunc('month', current_date)::date,
          current_date + 5,
          (date_trunc('month', current_date) + interval '1 month - 1 day')::date)
  on conflict (period_start, period_kind) do update
     set assign_opens = excluded.assign_opens,
         assign_closes = excluded.assign_closes,
         entry_closes = excluded.entry_closes
  returning id into v_cyc;

  create temporary table _ed (k text primary key, v uuid) on commit drop;
  insert into _ed values ('boss',p_boss),('mgr',p_mgr),('rep',p_rep),
                         ('two',p_two),('hr',p_hr),('cyc',v_cyc);
end $seed$;

do $t$
declare
  p_boss uuid; p_mgr uuid; p_rep uuid; p_two uuid; p_hr uuid; v_cyc uuid;
  v_a uuid; v_b uuid; v_mine uuid; r jsonb; n int;
begin
  select v into p_boss from _ed where k='boss';
  select v into p_mgr from _ed where k='mgr';
  select v into p_rep from _ed where k='rep';
  select v into p_two from _ed where k='two';
  select v into p_hr  from _ed where k='hr';
  select v into v_cyc from _ed where k='cyc';

  -- ------------------------------------------------- a measure can be named
  -- perf_assign takes a free-text name with no kpiId, which is what makes
  -- "add a KPI" possible at all. Asserted here because the screen's assign
  -- form used to refuse to submit without a catalogue id, so this capability
  -- existed and was unreachable.
  r := perf_assign(p_mgr, jsonb_build_object(
         'personId', p_rep, 'cycleId', v_cyc,
         'name', 'Site visits completed', 'unit', 'visits', 'target', '20'));
  if coalesce((r->>'ok')::boolean,false) is not true then
    raise exception 'FAIL  a manager could not name a new measure: %', r;
  end if;
  v_a := (r->>'assignmentId')::uuid;
  raise notice 'PASS  a manager names a measure that is in no catalogue';

  -- -------------------------------------------------------------- the edit
  r := perf_assign_edit(p_rep, jsonb_build_object('assignmentId', v_a, 'name', 'Mine now'));
  if r->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  a person edited their own measure: %', r;
  end if;
  raise notice 'PASS  a person may not edit their own measure';

  r := perf_assign_edit(p_two, jsonb_build_object('assignmentId', v_a, 'name', 'Not mine'));
  if r->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  a colleague edited somebody else''s measure: %', r;
  end if;
  raise notice 'PASS  nor may a colleague on the same team';

  r := perf_assign_edit(p_mgr, jsonb_build_object(
         'assignmentId', v_a, 'name', 'Site visits', 'unit', 'branch visits',
         'weight', '40', 'cadence', 'WEEKLY'));
  if coalesce((r->>'ok')::boolean,false) is not true then
    raise exception 'FAIL  the manager could not edit: %', r;
  end if;
  select count(*) into n from perf_assignment
   where id = v_a and name = 'Site visits' and unit = 'branch visits'
     and weight_pct = 40 and cadence::text = 'WEEKLY';
  if n <> 1 then
    raise exception 'FAIL  the edit did not land on every field';
  end if;
  raise notice 'PASS  the manager changes the name, the unit, the weight and the cadence';

  -- And Human Resources may NOT, which is migration 218's rule and 241's.
  -- Running the scheme -- opening a cycle, issuing sheets, certifying a
  -- quarter -- is a different act from setting one named person's numbers,
  -- and a department is not a licence over everybody in the company.
  r := perf_assign_edit(p_hr, jsonb_build_object('assignmentId', v_a, 'note', 'checked by HR'));
  if r->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  Human Resources edited a stranger''s measure: %', r;
  end if;
  raise notice 'PASS  and being in Human Resources is not a licence over a stranger';

  -- The target is NOT one of the fields, because perf_target_set runs the
  -- cascade and two doors onto one number is how they disagree.
  select target_value into n from perf_assignment where id = v_a;
  r := perf_assign_edit(p_mgr, jsonb_build_object('assignmentId', v_a, 'target', '999'));
  if (select target_value from perf_assignment where id = v_a) <> n then
    raise exception 'FAIL  editing moved the target; that is perf_target_set''s job';
  end if;
  raise notice 'PASS  editing does not touch the target';

  r := perf_assign_edit(p_mgr, jsonb_build_object('assignmentId', v_a, 'name', '   '));
  if r->>'error' is distinct from 'no_name' then
    raise exception 'FAIL  a measure was renamed to nothing: %', r;
  end if;
  raise notice 'PASS  and will not rename a measure to nothing';

  r := perf_assign_edit(p_mgr, jsonb_build_object('assignmentId', v_a, 'cadence', 'HOURLY'));
  if r->>'error' is distinct from 'bad_cadence' then
    raise exception 'FAIL  an unknown cadence was accepted: %', r;
  end if;
  raise notice 'PASS  nor accept a cadence that does not exist';

  -- --------------------------------------------------- climbing into one
  r := perf_assign_edit(p_mgr, jsonb_build_object('assignmentId', v_a, 'rollsInto', v_a));
  if r->>'error' is distinct from 'rolls_into_itself' then
    raise exception 'FAIL  a measure was made its own parent: %', r;
  end if;
  raise notice 'PASS  a measure cannot climb into itself';

  r := perf_assign(p_mgr, jsonb_build_object(
         'personId', p_two, 'cycleId', v_cyc, 'name', 'Somebody else''s', 'unit', 'cases'));
  r := perf_assign_edit(p_mgr, jsonb_build_object(
         'assignmentId', v_a, 'rollsInto', (r->>'assignmentId')));
  if r->>'error' is distinct from 'not_your_measure' then
    raise exception 'FAIL  a measure climbed into one the setter does not hold: %', r;
  end if;
  raise notice 'PASS  nor into one belonging to somebody other than the setter';

  -- Given BY THE BOSS, because nobody sets their own -- including a
  -- manager who wants something for their team to climb into.
  r := perf_assign(p_mgr, jsonb_build_object(
         'personId', p_mgr, 'cycleId', v_cyc, 'name', 'My own roll-up', 'unit', 'visits'));
  if r->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  a manager gave themselves a measure: %', r;
  end if;
  raise notice 'PASS  a manager may not give themselves the measure to climb into';

  r := perf_assign(p_boss, jsonb_build_object(
         'personId', p_mgr, 'cycleId', v_cyc, 'name', 'My own roll-up', 'unit', 'visits'));
  v_mine := (r->>'assignmentId')::uuid;
  if v_mine is null then
    raise exception 'FAIL  the boss could not give the manager a measure: %', r;
  end if;
  raise notice 'PASS  their own manager gives it to them';
  r := perf_assign_edit(p_mgr, jsonb_build_object('assignmentId', v_a, 'rollsInto', v_mine));
  if coalesce((r->>'ok')::boolean,false) is not true then
    raise exception 'FAIL  a measure could not be made to climb into the setter''s: %', r;
  end if;
  raise notice 'PASS  and does climb into one the setter holds';

  -- ------------------------------------------------------------ the remove
  r := perf_assign_remove(p_rep, v_a);
  if r->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  a person removed their own measure: %', r;
  end if;
  raise notice 'PASS  a person may not take back their own measure';

  -- Something climbs into v_mine, so v_mine may not be removed yet. Asked
  -- of the BOSS, since v_mine is the manager's own and the manager is
  -- refused it on the previous grounds before ever reaching this one.
  r := perf_assign_remove(p_boss, v_mine);
  if r->>'error' is distinct from 'feeds_this' then
    raise exception 'FAIL  a measure other people feed was removed: %', r;
  end if;
  raise notice 'PASS  nor is a measure removed while others climb into it';

  -- Nothing filed: deleted outright.
  r := perf_assign_remove(p_mgr, v_a);
  if (r->>'withdrawn')::boolean is not false then
    raise exception 'FAIL  an unfiled measure was withdrawn rather than removed: %', r;
  end if;
  if exists (select 1 from perf_assignment where id = v_a) then
    raise exception 'FAIL  the measure survived its own removal';
  end if;
  raise notice 'PASS  a measure nothing was filed against is removed outright';

  -- Something filed: withdrawn, and the figure survives.
  r := perf_assign(p_mgr, jsonb_build_object(
         'personId', p_rep, 'cycleId', v_cyc, 'name', 'Filed against',
         'unit', 'cases', 'target', '10'));
  v_b := (r->>'assignmentId')::uuid;
  insert into perf_entry (assignment_id, as_of, value, filed_by)
    values (v_b, current_date, 3, p_rep);

  r := perf_assign_remove(p_mgr, v_b);
  if (r->>'withdrawn')::boolean is not true then
    raise exception 'FAIL  a filed-against measure was deleted: %', r;
  end if;
  if (select state from perf_assignment where id = v_b) <> 'WITHDRAWN' then
    raise exception 'FAIL  the measure was not marked WITHDRAWN';
  end if;
  if not exists (select 1 from perf_entry where assignment_id = v_b) then
    raise exception 'FAIL  removing took the filed figure with it';
  end if;
  raise notice 'PASS  one that was filed against is withdrawn, not deleted';
  raise notice 'PASS  and the figure somebody filed is still there';

  -- A state nothing reads is a state that means nothing. Withdrawing has to
  -- take the measure off the screen, out of the score, and off the to-do
  -- list -- otherwise "remove" removes it from the one place the manager
  -- was not looking.
  if (perf_tree(p_rep, v_cyc)->'measures') @> jsonb_build_array(
       jsonb_build_object('assignmentId', v_b)) then
    raise exception 'FAIL  a withdrawn measure is still on the screen';
  end if;
  if exists (select 1 from jsonb_array_elements(perf_tree(p_rep, v_cyc)->'measures') m
              where m->>'assignmentId' = v_b::text) then
    raise exception 'FAIL  a withdrawn measure is still in perf_tree';
  end if;
  raise notice 'PASS  a withdrawn measure is off the screen';

  if exists (select 1 from jsonb_array_elements(
               coalesce(perf_kpi_score(p_rep, v_cyc)->'measures','[]'::jsonb)) m
              where m->>'assignmentId' = v_b::text) then
    raise exception 'FAIL  a withdrawn measure still counts towards the score';
  end if;
  raise notice 'PASS  and out of the score that decides their bonus';

  if exists (select 1 from jsonb_array_elements(
               coalesce(perf_due(p_rep, current_date),'[]'::jsonb)) d
              where d->>'assignmentId' = v_b::text) then
    raise exception 'FAIL  a withdrawn measure is still being asked for';
  end if;
  raise notice 'PASS  and is no longer asked for';

  -- ------------------------------------------------------ it is recorded
  if not exists (select 1 from audit_entry
                  where actor_id = p_mgr and action = 'PERF_KPI_CHANGED') then
    raise exception 'FAIL  an edit left no audit row';
  end if;
  if not exists (select 1 from audit_entry
                  where actor_id = p_mgr and action = 'PERF_KPI_WITHDRAWN') then
    raise exception 'FAIL  a withdrawal left no audit row';
  end if;
  raise notice 'PASS  every change is recorded against whoever made it';

  -- ------------------------------------------------------- the window
  update perf_cycle set assign_closes = current_date - 1 where id = v_cyc;
  r := perf_assign_edit(p_mgr, jsonb_build_object('assignmentId', v_b, 'name', 'Too late'));
  if r->>'error' is distinct from 'window_closed' then
    raise exception 'FAIL  a measure was edited after the window shut: %', r;
  end if;
  raise notice 'PASS  once the assignment window shuts, a manager may not edit';

  raise notice '--- editing a measure: every assertion passed ---';
end $t$;

rollback;
