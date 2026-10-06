-- The people you may move are the people you are offered (migration 242)
--
-- The claim is not "the list has rows in it". The claim is that the list
-- and org_move_person agree: every person offered can actually be moved,
-- and every person who could be moved is offered. That is asserted by
-- ATTEMPTING the move for each one, inside a savepoint, rather than by
-- restating the predicate -- a test that restates the predicate passes
-- whenever the predicate is self-consistently wrong.
--
-- Everything is rolled back.

begin;

do $seed$
declare
  p_adm uuid; p_hr uuid; p_top uuid; p_mid uuid; p_low uuid;
  p_other uuid; p_far uuid;
begin
  -- A line four deep, a second line beside it, an administrator and an
  -- HR person who stand outside both.
  --   top -> mid -> low
  --   other (no manager)
  --   far -> (nobody)
  insert into person (full_name, work_email, app_role)
    values ('OF Admin', 'of.adm@example.invalid', 'ADMIN') returning id into p_adm;
  insert into person (full_name, work_email, app_role, department)
    values ('OF HR', 'of.hr@example.invalid', 'MANAGER', 'Human Resources') returning id into p_hr;
  insert into person (full_name, work_email, app_role)
    values ('OF Top', 'of.top@example.invalid', 'MANAGER') returning id into p_top;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('OF Mid', 'of.mid@example.invalid', 'MANAGER', p_top) returning id into p_mid;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('OF Low', 'of.low@example.invalid', 'VIEWER', p_mid) returning id into p_low;
  insert into person (full_name, work_email, app_role)
    values ('OF Other', 'of.oth@example.invalid', 'VIEWER') returning id into p_other;
  insert into person (full_name, work_email, app_role)
    values ('OF Far', 'of.far@example.invalid', 'VIEWER') returning id into p_far;

  create temporary table _of (k text primary key, v uuid) on commit drop;
  insert into _of values ('adm',p_adm),('hr',p_hr),('top',p_top),('mid',p_mid),
                         ('low',p_low),('other',p_other),('far',p_far);
end $seed$;

do $t$
declare
  p_adm uuid; p_hr uuid; p_top uuid; p_mid uuid; p_low uuid;
  p_other uuid; p_far uuid;
  r record; v_offered boolean; v_allowed boolean; o jsonb;
  n_bad int := 0; n_checked int := 0; v_first text := null;
  actors text[] := array['adm','hr','top','mid'];
  v_key text; a uuid; u uuid;
begin
  select v into p_adm   from _of where _of.k = 'adm';
  select v into p_hr    from _of where _of.k = 'hr';
  select v into p_top   from _of where _of.k = 'top';
  select v into p_mid   from _of where _of.k = 'mid';
  select v into p_low   from _of where _of.k = 'low';
  select v into p_other from _of where _of.k = 'other';
  select v into p_far   from _of where _of.k = 'far';

  -- ---------------------------------------------- the list and the gate
  foreach v_key in array actors loop
    select v into a from _of where _of.k = v_key;
    -- Two destinations: the actor themselves, and somebody in the middle.
    foreach u in array array[a, p_mid] loop
      if not org_may_add_under(a, u) then continue; end if;

      for r in
        select q.id, q.full_name from person q
         where q.employment_status = 'ACTIVE' and q.superseded_by is null
           and coalesce(q.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
         order by q.full_name
      loop
        v_offered := exists (
          select 1 from jsonb_array_elements(org_add_options(a, u)->'movable') m
           where (m->>'personId')::uuid = r.id);

        -- Try it for real, then put the world back exactly as it was.
        begin
          -- Three arguments. A fourth made every call raise
          -- "function does not exist", which the handler below turned
          -- into "not allowed" -- and the test then read 39 perfectly
          -- good offers as disagreements.
          o := org_move_person(a, r.id, u);
          -- ok with changed=false is "they already report there". That is
          -- not a move, and offering it would be offering nothing.
          v_allowed := coalesce((o->>'ok')::boolean, false)
                   and coalesce((o->>'changed')::boolean, false);
          raise exception using errcode = 'P0001', message = 'undo';
        exception
          when sqlstate 'P0001' then
            if sqlerrm <> 'undo' then v_allowed := false; end if;
          when others then
            v_allowed := false;
        end;

        n_checked := n_checked + 1;
        if v_offered <> v_allowed then
          n_bad := n_bad + 1;
          if v_first is null then
            v_first := v_key || ' -> ' || r.full_name
                    || ': offered=' || v_offered || ' allowed=' || v_allowed;
          end if;
        end if;
      end loop;
    end loop;
  end loop;

  if n_bad > 0 then
    raise exception 'FAIL  % of % offers disagree with the gate. First: %',
      n_bad, n_checked, v_first;
  end if;
  raise notice 'PASS  every offer agrees with org_move_person (% checked)', n_checked;

  -- ------------------------------------------- the specific complaints
  -- HR could move anybody and was offered nobody. That was the bug.
  if jsonb_array_length(org_add_options(p_hr, p_hr)->'movable') < 5 then
    raise exception 'FAIL  Human Resources is offered only % people',
      jsonb_array_length(org_add_options(p_hr, p_hr)->'movable');
  end if;
  raise notice 'PASS  Human Resources is offered the people it may move';

  if jsonb_array_length(org_add_options(p_adm, p_adm)->'movable') < 5 then
    raise exception 'FAIL  an administrator is offered only % people',
      jsonb_array_length(org_add_options(p_adm, p_adm)->'movable');
  end if;
  raise notice 'PASS  and so is an administrator';

  -- A manager reaches their whole subtree, not just one step. Low is two
  -- steps under Top, and org_move_person has always allowed it.
  if not exists (select 1 from jsonb_array_elements(
                   org_add_options(p_top, p_top)->'movable') m
                  where (m->>'personId')::uuid = p_low) then
    raise exception 'FAIL  a manager is not offered somebody two steps down';
  end if;
  raise notice 'PASS  a manager is offered their whole subtree, not one step of it';

  -- And reaches nobody outside it.
  if exists (select 1 from jsonb_array_elements(
               org_add_options(p_top, p_top)->'movable') m
              where (m->>'personId')::uuid in (p_other, p_far)) then
    raise exception 'FAIL  a manager is offered somebody outside their team';
  end if;
  raise notice 'PASS  and nobody outside it';

  -- Nobody is offered themselves, at any level.
  if exists (select 1 from jsonb_array_elements(
               org_add_options(p_adm, p_adm)->'movable') m
              where (m->>'personId')::uuid = p_adm)
     or exists (select 1 from jsonb_array_elements(
                  org_add_options(p_top, p_top)->'movable') m
                 where (m->>'personId')::uuid = p_top) then
    raise exception 'FAIL  somebody is offered themselves';
  end if;
  raise notice 'PASS  nobody is offered themselves';

  -- Somebody already reporting to the destination is not offered: there is
  -- nothing to do.
  if exists (select 1 from jsonb_array_elements(
               org_add_options(p_top, p_top)->'movable') m
              where (m->>'personId')::uuid = p_mid) then
    raise exception 'FAIL  somebody already under the destination is offered';
  end if;
  raise notice 'PASS  nor is anybody already under the destination';

  -- A move that would make a circle is not offered. Top is above Mid, so
  -- Top cannot be moved under Mid.
  if exists (select 1 from jsonb_array_elements(
               org_add_options(p_adm, p_mid)->'movable') m
              where (m->>'personId')::uuid = p_top) then
    raise exception 'FAIL  a move that closes the line into a circle is offered';
  end if;
  raise notice 'PASS  and nor is a move that would turn the line into a circle';

  raise notice '--- who you may move: every assertion passed ---';
end $t$;

rollback;
