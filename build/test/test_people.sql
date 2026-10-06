-- One table of everybody (migration 244)
--
-- The claim being tested is not "the function returns rows". It is four
-- things, and each is asserted against something other than the function's
-- own opinion of itself:
--
--   1. only the administrator and Human Resources may read it, and anybody
--      else is refused WITH A REASON rather than handed an empty list;
--   2. the list is the staff list exactly -- the client contacts (238) and
--      the service account (243) are out of it;
--   3. every row it marks movable can actually be moved, by ATTEMPTING the
--      move, the way test_offer does. A table that offers a control the
--      write refuses is the defect migration 242 was written for;
--   4. reading the whole company does not widen what anybody may SET.
--      241 settled that HR runs the scheme and does not own the people, and
--      a flat list of names must not quietly undo it.
--
-- Everything is rolled back.

begin;

do $seed$
declare
  p_adm uuid; p_hr uuid; p_top uuid; p_mid uuid; p_low uuid;
  p_loose uuid; p_contact uuid; p_svc uuid; p_plain uuid;
  v_chair uuid; v_seat uuid; v_desig uuid;
begin
  --   top -> mid -> low          a line three deep
  --   loose                      nobody's report, nobody's manager
  --   adm, hr, plain             the three kinds of reader
  --   contact, svc               two rows in `person` who are not staff
  insert into person (full_name, work_email, app_role)
    values ('PT Admin', 'pt.adm@example.invalid', 'ADMIN') returning id into p_adm;
  insert into person (full_name, work_email, app_role, department)
    values ('PT HR', 'pt.hr@example.invalid', 'MANAGER', 'Human Resources')
    returning id into p_hr;
  insert into person (full_name, work_email, app_role)
    values ('PT Top', 'pt.top@example.invalid', 'MANAGER') returning id into p_top;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('PT Mid', 'pt.mid@example.invalid', 'MANAGER', p_top) returning id into p_mid;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('PT Low', 'pt.low@example.invalid', 'VIEWER', p_mid) returning id into p_low;
  insert into person (full_name, work_email, app_role)
    values ('PT Loose', 'pt.loose@example.invalid', 'VIEWER') returning id into p_loose;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('PT Plain', 'pt.plain@example.invalid', 'VIEWER', p_top)
    returning id into p_plain;

  insert into person (full_name, work_email, app_role, employee_type)
    values ('PT Contact', 'pt.contact@example.invalid', 'VIEWER', 'CLIENT_CONTACT')
    returning id into p_contact;
  insert into person (full_name, work_email, app_role, employee_type)
    values ('PT Service', 'pt.svc@example.invalid', 'ADMIN', 'SERVICE_ACCOUNT')
    returning id into p_svc;

  -- A chair with a seating that carries a place, so the location column has
  -- something to find. PT Mid is seated in it; nobody else is.
  insert into chair (code, title, level)
    values ('PT-CH-1', 'PT Branch Manager', 'BRANCH') returning id into v_chair;
  insert into chair_seating (chair_id, scope_label)
    values (v_chair, 'Pune') returning id into v_seat;
  insert into chair_holder (chair_id, person_id, is_primary, seating_id)
    values (v_chair, p_mid, true, v_seat);

  insert into designation (title) values ('PT Senior Executive')
    returning id into v_desig;
  update person set designation_id = v_desig, department = 'Operations'
   where id = p_mid;

  create temporary table _pt (k text primary key, v uuid) on commit drop;
  insert into _pt values ('adm',p_adm),('hr',p_hr),('top',p_top),('mid',p_mid),
                         ('low',p_low),('loose',p_loose),('plain',p_plain),
                         ('contact',p_contact),('svc',p_svc);
end $seed$;

do $t$
declare
  p_adm uuid; p_hr uuid; p_top uuid; p_mid uuid; p_low uuid;
  p_loose uuid; p_plain uuid; p_contact uuid; p_svc uuid;
  o jsonb; r jsonb; n int; v_staff int;
  v_key text; a uuid; v_moved boolean; v_marked boolean;
  n_bad int := 0; n_checked int := 0; v_first text := null;
begin
  select v into p_adm     from _pt where _pt.k = 'adm';
  select v into p_hr      from _pt where _pt.k = 'hr';
  select v into p_top     from _pt where _pt.k = 'top';
  select v into p_mid     from _pt where _pt.k = 'mid';
  select v into p_low     from _pt where _pt.k = 'low';
  select v into p_loose   from _pt where _pt.k = 'loose';
  select v into p_plain   from _pt where _pt.k = 'plain';
  select v into p_contact from _pt where _pt.k = 'contact';
  select v into p_svc     from _pt where _pt.k = 'svc';

  -- ------------------------------------------------------------ who may read
  o := org_people_table(p_plain);
  if coalesce((o->>'mayUse')::boolean, false) then
    raise exception 'FAIL  an ordinary person was handed the whole company';
  end if;
  if o->>'reason' is null or o->>'reason' = '' then
    raise exception 'FAIL  the refusal carries no reason';
  end if;
  if o ? 'people' then
    raise exception 'FAIL  the refusal still carries the list';
  end if;
  raise notice 'PASS  an ordinary person is refused, and told why';

  o := org_people_table(p_top);
  if coalesce((o->>'mayUse')::boolean, false) then
    raise exception 'FAIL  a manager with a team was handed the whole company';
  end if;
  raise notice 'PASS  and so is a manager, whose team is the chart';

  o := org_people_table(null);
  if o->>'error' is null then
    raise exception 'FAIL  a null actor was not refused';
  end if;
  raise notice 'PASS  a missing actor is an error, not an empty list';

  -- ---------------------------------------------------------- what is in it
  o := org_people_table(p_adm);
  if not coalesce((o->>'mayUse')::boolean, false) then
    raise exception 'FAIL  the administrator was refused their own company list';
  end if;

  select count(*) into v_staff from person
   where employment_status = 'ACTIVE' and superseded_by is null
     and coalesce(employee_type,'EMPLOYEE')
         not in ('CLIENT_CONTACT','SERVICE_ACCOUNT');
  n := jsonb_array_length(o->'people');
  if n <> v_staff then
    raise exception 'FAIL  the table holds % rows and there are % staff', n, v_staff;
  end if;
  raise notice 'PASS  the administrator sees every member of staff (%)', n;

  if exists (select 1 from jsonb_array_elements(o->'people') x
              where (x->>'personId')::uuid in (p_contact, p_svc)) then
    raise exception 'FAIL  a client contact or the service account is in the list';
  end if;
  raise notice 'PASS  and nobody who is not staff -- not a contact, not the service account';

  if (o->'summary'->>'people')::int <> v_staff then
    raise exception 'FAIL  the summary counts % and the table holds %',
      o->'summary'->>'people', v_staff;
  end if;
  select count(*) into n from person
   where employment_status = 'ACTIVE' and superseded_by is null
     and manager_id is null
     and coalesce(employee_type,'EMPLOYEE')
         not in ('CLIENT_CONTACT','SERVICE_ACCOUNT');
  if (o->'summary'->>'noManager')::int <> n then
    raise exception 'FAIL  the summary says % have no manager and % do',
      o->'summary'->>'noManager', n;
  end if;
  raise notice 'PASS  the summary counts agree with the rows they summarise';

  -- The counts are the whole point of the screen: somebody with no manager
  -- is invisible on a chart, so the list has to find them.
  if not exists (select 1 from jsonb_array_elements(o->'people') x
                  where (x->>'personId')::uuid = p_loose) then
    raise exception 'FAIL  somebody with no manager and no reports is missing';
  end if;
  raise notice 'PASS  somebody the chart cannot draw is in the list';

  -- ------------------------------------------------- what each row carries
  select count(*) into n from jsonb_array_elements(o->'people') x
   where x->>'personId' is null or x->>'name' is null;
  if n > 0 then
    raise exception 'FAIL  % row(s) carry no id or no name', n;
  end if;

  select x into r from jsonb_array_elements(o->'people') x
   where (x->>'personId')::uuid = p_mid;
  if r->>'reportsTo' <> 'PT Top' then
    raise exception 'FAIL  reportsTo says % and the manager is PT Top',
      coalesce(r->>'reportsTo','null');
  end if;
  if (r->>'managerId')::uuid <> p_top then
    raise exception 'FAIL  managerId does not match person.manager_id';
  end if;
  if r->>'designation' <> 'PT Senior Executive' then
    raise exception 'FAIL  the designation is % and not the one set',
      coalesce(r->>'designation','null');
  end if;
  if r->>'chair' <> 'PT Branch Manager' then
    raise exception 'FAIL  the chair is %', coalesce(r->>'chair','null');
  end if;
  if r->>'location' <> 'Pune' or r->>'locationFrom' <> 'chair' then
    raise exception 'FAIL  the location is % (from %) and not Pune from the chair',
      coalesce(r->>'location','null'), coalesce(r->>'locationFrom','null');
  end if;
  if (r->>'reports')::int <> 1 then
    raise exception 'FAIL  PT Mid has % report(s) and should have one',
      r->>'reports';
  end if;
  raise notice 'PASS  a row carries the designation, the chair, the place and who they report to';

  -- A gap is a gap and is said as one. PT Loose holds no chair, so the
  -- location is null rather than a guess.
  select x into r from jsonb_array_elements(o->'people') x
   where (x->>'personId')::uuid = p_loose;
  if r->>'location' is not null or r->>'locationFrom' is not null then
    raise exception 'FAIL  somebody with no chair was given a location: %',
      r->>'location';
  end if;
  if r->>'reportsTo' is not null then
    raise exception 'FAIL  somebody with no manager was given one';
  end if;
  raise notice 'PASS  and leaves a gap empty rather than filling it with a guess';

  -- ------------------------------------------------- HR reads the same list
  o := org_people_table(p_hr);
  if not coalesce((o->>'mayUse')::boolean, false) then
    raise exception 'FAIL  Human Resources was refused the list they clean';
  end if;
  if jsonb_array_length(o->'people') <> v_staff then
    raise exception 'FAIL  HR sees % of % staff',
      jsonb_array_length(o->'people'), v_staff;
  end if;
  raise notice 'PASS  Human Resources sees the same list';

  -- --------------------------------- the offer agrees with the write (242)
  -- Every row the table marks movable is attempted for real, under a person
  -- who is a leaf, and the result compared with the mark. A mark that does
  -- not match the write is a button that refuses.
  foreach v_key in array array['adm','hr'] loop
    select v into a from _pt where _pt.k = v_key;
    o := org_people_table(a);
    for r in select x from jsonb_array_elements(o->'people') x loop
      v_marked := coalesce((r->>'mayMove')::boolean, false);
      begin
        -- Under PT Loose, who has no manager and no reports. The
        -- destination matters: a person ABOVE the destination cannot be
        -- moved below it without closing the line into a ring, and PT Loose
        -- is above nobody. So every refusal left is about the person rather
        -- than about where they were being sent.
        v_moved := coalesce(
          (org_move_person(a, (r->>'personId')::uuid, p_loose)->>'ok')::boolean,
          false);
        raise exception using errcode = 'P0001', message = 'undo';
      exception
        when sqlstate 'P0001' then
          if sqlerrm <> 'undo' then v_moved := false; end if;
        when others then
          v_moved := false;
      end;
      n_checked := n_checked + 1;
      -- The claim is one-directional on purpose: a marked row must be
      -- movable. The reverse is not claimed, because PT Loose cannot be
      -- moved under themselves and that refusal is about the destination,
      -- not about the person being offered.
      if v_marked and not v_moved and (r->>'personId')::uuid <> p_loose then
        n_bad := n_bad + 1;
        if v_first is null then
          v_first := v_key || ' -> ' || (r->>'name');
        end if;
      end if;
    end loop;
  end loop;
  if n_bad > 0 then
    raise exception 'FAIL  % of % marked rows cannot actually be moved. First: %',
      n_bad, n_checked, v_first;
  end if;
  raise notice 'PASS  every row marked movable can be moved (% checked)', n_checked;

  -- Nobody is offered a move of themselves: org_move_person refuses that
  -- first thing, and an offer that refuses is the defect 242 was written for.
  o := org_people_table(p_adm);
  if exists (select 1 from jsonb_array_elements(o->'people') x
              where (x->>'personId')::uuid = p_adm
                and coalesce((x->>'mayMove')::boolean, false)) then
    raise exception 'FAIL  the administrator is offered a move of themselves';
  end if;
  raise notice 'PASS  and nobody is offered a move of themselves';

  -- --------------------------------------------- reading is not setting (241)
  -- The list hands HR every name in the company. It must not hand them
  -- anybody's targets.
  if exists (select 1 from person p
              where p.employment_status = 'ACTIVE' and p.superseded_by is null
                and p.id <> p_hr
                and not exists (select 1 from perf_line(p_hr) l
                                 where l.person_id = p.id)
                and perf_may_set(p_hr, p.id)) then
    raise exception 'FAIL  Human Resources may set measures outside their line. '
                    '241 has been undone.';
  end if;
  if perf_may_set(p_hr, p_mid) then
    raise exception 'FAIL  Human Resources may set PT Mid''s measures';
  end if;
  raise notice 'PASS  reading the whole company does not widen what HR may set';

  -- And the manager it does belong to still has it.
  if not perf_may_set(p_top, p_mid) then
    raise exception 'FAIL  PT Top may no longer set their own report''s measures';
  end if;
  raise notice 'PASS  and the manager it belongs to still has it';

  raise notice '--- one table of everybody: every assertion passed ---';
end $t$;

rollback;
