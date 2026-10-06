-- One table of everybody, so the assignments can be cleaned (244)
--
-- "for admin and HR in teams and structure, can you give a simple table with
--  name, details, designation, location, reporting to, etc with option to add
--  existing missing people of all the employees so I can easily clean the
--  assignments"
--
-- WHY A SECOND VIEW OF THE SAME PEOPLE. My team & structure draws the
-- reporting line as a tree, and a tree is the right drawing for "who works
-- for whom". It is the wrong drawing for the job being asked for here, which
-- is the opposite one: finding the people the tree does NOT show. Somebody
-- with no manager is not drawn under anybody, so on a chart they are simply
-- absent -- and absence is the one thing a chart cannot point at.
--
-- The measurement that made this worth building, taken today:
--
--     103 staff
--     100 have a manager            ->  3 do not (one is the MD, correctly)
--     101 hold a chair              ->  2 do not
--      54 have a designation        -> 49 do not
--      54 have a department         -> 49 do not
--      90 have a location           -> 13 do not
--
-- None of that is visible on the chart. All of it is visible in a list.
--
-- WHO MAY READ IT. The administrator, and Human Resources. The same two the
-- rest of the tool already treats as able to see the whole company:
-- /access uses `isAdmin or level = 'hr'`, person_add is HR's, and
-- org_move_person's own first question is `a.app_role = 'ADMIN'` or
-- `department = 'Human Resources'`.
--
-- That last one is the reason the test here is written the same way rather
-- than a better way. This table's whole purpose is to offer moves, and
-- migration 242 was written because org_add_options offered moves on a
-- different test from the one org_move_person applied -- so the tool put a
-- control in front of somebody that always refused. The way not to do that
-- again is to ask the same question in the same words.
--
-- Note what this does NOT widen. 241 settled that HR runs the scheme and
-- does not own the people: HR may not set a named person's KPIs or targets,
-- and perf_rel still answers null for them over somebody outside their line.
-- Nothing here touches perf_rel, perf_may_set or perf_line. A name, a chair,
-- a location and a manager are not performance; HR has been able to read all
-- four on the People screen since the tool was built.
--
-- WHAT IT DOES NOT DO. It does not write. Changing who somebody reports to
-- is org_move_person's, which already exists, already audits, already
-- refuses a loop and already refuses the move of a person into their own
-- subtree. A second way to write manager_id is a second set of rules to keep
-- in step, and the first thing that would go out of step is the audit row.

-- ------------------------------------------------------------- the reader
create or replace function org_people_table(p_actor uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  a person;
  v_may boolean;
  v_rows jsonb;
  v_sum jsonb;
begin
  select * into a from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null then
    return jsonb_build_object('error','not_permitted','reason','Who is asking?');
  end if;

  -- The same question org_move_person asks, in the same words (migration
  -- 242's lesson). If this ever diverges, the table will offer a move the
  -- move itself refuses.
  v_may := a.app_role = 'ADMIN' or coalesce(a.department,'') = 'Human Resources';

  if not v_may then
    return jsonb_build_object(
      'mayUse', false,
      'reason', 'This list is every person in the company, so it is the '
             || 'administrator''s and Human Resources''. Your own team is '
             || 'the chart above.');
  end if;

  with staff as (
    -- Not every row in `person` is somebody who works here: the client-bank
    -- contacts (238) and the account the tool is administered from (243).
    -- Written the same way the thirteen functions 243 swept write it.
    select p.* from person p
     where p.employment_status = 'ACTIVE' and p.superseded_by is null
       and coalesce(p.employee_type,'EMPLOYEE')
           not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
  ), seat as (
    -- The primary chair, and the seating that chair was placed in. One row
    -- per person: somebody can hold two chairs and the table has one line.
    select distinct on (h.person_id)
           h.person_id, ch.title as chair, cs.scope_label
      from chair_holder h
      join chair ch on ch.id = h.chair_id
      left join chair_seating cs on cs.id = h.seating_id
     where h.to_date is null
     order by h.person_id, h.is_primary desc nulls last, ch.title
  ), cov as (
    -- Where somebody is, when the chair does not say. The coverage rules
    -- carry an operating node either directly or through the branch, and
    -- its name is a place ("Mumbai", "JHARKHAND (Firoz+ Crux)"). It is a
    -- rougher answer than the chair's and it is labelled as such on screen,
    -- because a rough answer presented as an exact one is worse than a gap.
    select distinct on (cr.person_id) cr.person_id, o.name as place
      from coverage_rule cr
      join op_node o on o.id = coalesce(cr.op_node_id,
             (select b.op_node_id from branch b where b.id = cr.branch_id))
     where cr.effective_to is null
     order by cr.person_id, o.name
  ), rep as (
    select manager_id as id, count(*)::int as n
      from staff where manager_id is not null group by 1
  ), flat as (
    select s.full_name,
           jsonb_build_object(
             'personId',    s.id,
             'name',        s.full_name,
             'employeeNo',  s.employee_no,
             'workEmail',   s.work_email,
             'mobile',      s.mobile,
             'designation', d.title,
             'department',  s.department,
             'chair',       seat.chair,
             'location',    coalesce(seat.scope_label, cov.place),
             -- Which of the two answered, so the screen can say so rather
             -- than let a coverage area pass for a posting.
             'locationFrom', case
               when seat.scope_label is not null then 'chair'
               when cov.place is not null then 'coverage'
               else null end,
             'managerId',   s.manager_id,
             'reportsTo',   m.full_name,
             'reports',     coalesce(rep.n, 0),
             'employeeType', coalesce(s.employee_type,'EMPLOYEE'),
             'appRole',     s.app_role,
             'joinedOn',    s.joined_on,
             -- Nobody may be moved under themselves, and the actor may not
             -- move themselves at all. Every other refusal org_move_person
             -- makes is about a loop, which the screen works out from the
             -- managerId column it already has.
             'mayMove',     s.id <> p_actor
           ) as line
      from staff s
      left join designation d on d.id = s.designation_id
      left join seat on seat.person_id = s.id
      left join cov  on cov.person_id  = s.id
      left join person m on m.id = s.manager_id
      left join rep on rep.id = s.id
  )
  select jsonb_agg(line order by full_name) into v_rows from flat;

  -- The counts the chart cannot show. Each is a filter on the screen, so
  -- the number and the list behind it are the same question asked twice.
  select jsonb_build_object(
           'people',        count(*)::int,
           'noManager',     count(*) filter (where s.manager_id is null)::int,
           'noChair',       count(*) filter (where seat.person_id is null)::int,
           'noDesignation', count(*) filter (where s.designation_id is null)::int,
           'noDepartment',  count(*) filter (where s.department is null)::int,
           'noLocation',    count(*) filter
             (where seat.scope_label is null and cov.person_id is null)::int)
    into v_sum
    from person s
    left join (select distinct on (h.person_id) h.person_id, cs.scope_label
                 from chair_holder h
                 join chair ch on ch.id = h.chair_id
                 left join chair_seating cs on cs.id = h.seating_id
                where h.to_date is null
                order by h.person_id, h.is_primary desc nulls last, ch.title) seat
      on seat.person_id = s.id
    left join (select distinct on (cr.person_id) cr.person_id
                 from coverage_rule cr
                 join op_node o on o.id = coalesce(cr.op_node_id,
                        (select b.op_node_id from branch b where b.id = cr.branch_id))
                where cr.effective_to is null
                order by cr.person_id) cov
      on cov.person_id = s.id
   where s.employment_status = 'ACTIVE' and s.superseded_by is null
     and coalesce(s.employee_type,'EMPLOYEE')
         not in ('CLIENT_CONTACT','SERVICE_ACCOUNT');

  return jsonb_build_object(
    'mayUse',  true,
    'asAdministrator', a.app_role = 'ADMIN',
    'asHumanResources', coalesce(a.department,'') = 'Human Resources',
    'people',  coalesce(v_rows, '[]'::jsonb),
    'summary', v_sum,
    'note',    'Everybody who works here, whether or not the chart can draw '
            || 'them. Changing who somebody reports to is recorded and '
            || 'changes who can read their numbers.');
end
$function$;

comment on function org_people_table(uuid) is
  'Every member of staff as one flat row -- name, employee number, '
  'designation, chair, location, who they report to -- for the administrator '
  'and Human Resources, who are the two the rest of the tool already lets '
  'see the whole company. Reads only; org_move_person does the writing.';

-- ------------------------------------------------------------- the guard
do $guard$
declare
  o jsonb; n int; v_admin uuid; v_hr uuid; v_other uuid; v_staff int;
begin
  -- Somebody who is neither is refused, and told why rather than handed an
  -- empty list that looks like a company with nobody in it.
  select id into v_other from person
   where employment_status = 'ACTIVE' and superseded_by is null
     and app_role is distinct from 'ADMIN'
     and coalesce(department,'') <> 'Human Resources'
   limit 1;
  if v_other is not null then
    o := org_people_table(v_other);
    if coalesce((o->>'mayUse')::boolean, false) then
      raise exception 'Migration 244: an ordinary person was handed the whole '
                      'company list.';
    end if;
    if o->>'reason' is null then
      raise exception 'Migration 244: the refusal carries no reason.';
    end if;
  end if;

  select id into v_admin from person
   where employment_status = 'ACTIVE' and superseded_by is null
     and app_role = 'ADMIN' limit 1;
  if v_admin is null then
    raise notice 'Migration 244: no administrator to check against.';
    return;
  end if;

  o := org_people_table(v_admin);
  if not coalesce((o->>'mayUse')::boolean, false) then
    raise exception 'Migration 244: the administrator was refused their own '
                    'company list.';
  end if;

  -- The list is the staff list, exactly. Not the person table, which holds
  -- the client contacts and the service account as well.
  select count(*) into v_staff from person
   where employment_status = 'ACTIVE' and superseded_by is null
     and coalesce(employee_type,'EMPLOYEE')
         not in ('CLIENT_CONTACT','SERVICE_ACCOUNT');
  n := jsonb_array_length(o->'people');
  if n <> v_staff then
    raise exception 'Migration 244: the table holds % rows and there are % '
                    'members of staff.', n, v_staff;
  end if;
  if (o->'summary'->>'people')::int <> v_staff then
    raise exception 'Migration 244: the summary counts % and the table holds %.',
      o->'summary'->>'people', v_staff;
  end if;

  -- Every row carries the two things the screen cannot work out for itself.
  select count(*) into n from jsonb_array_elements(o->'people') r
   where r->>'personId' is null or r->>'name' is null;
  if n > 0 then
    raise exception 'Migration 244: % row(s) have no id or no name.', n;
  end if;

  -- The administrator is never offered a move of themselves, because
  -- org_move_person refuses it first thing and an offer that refuses is the
  -- defect migration 242 was written for.
  select count(*) into n from jsonb_array_elements(o->'people') r
   where r->>'personId' = v_admin::text
     and coalesce((r->>'mayMove')::boolean, false);
  if n > 0 then
    raise exception 'Migration 244: the administrator is offered a move of '
                    'themselves.';
  end if;

  -- And the service account is not in it.
  select count(*) into n from jsonb_array_elements(o->'people') r
   join person p on p.id = (r->>'personId')::uuid
   where coalesce(p.employee_type,'EMPLOYEE')
         in ('CLIENT_CONTACT','SERVICE_ACCOUNT');
  if n > 0 then
    raise exception 'Migration 244: % row(s) are not members of staff.', n;
  end if;

  select id into v_hr from person
   where employment_status = 'ACTIVE' and superseded_by is null
     and coalesce(department,'') = 'Human Resources'
     and app_role is distinct from 'ADMIN' limit 1;
  if v_hr is not null then
    o := org_people_table(v_hr);
    if not coalesce((o->>'mayUse')::boolean, false) then
      raise exception 'Migration 244: Human Resources was refused the list '
                      'they are meant to clean.';
    end if;
    -- 241 stands: a name and a reporting line are not performance. HR must
    -- still not be able to set a stranger's measures.
    if exists (select 1 from person p
                where p.employment_status = 'ACTIVE' and p.superseded_by is null
                  and p.id <> v_hr
                  and not exists (select 1 from perf_line(v_hr) l
                                   where l.person_id = p.id)
                  and perf_may_set(v_hr, p.id)) then
      raise exception 'Migration 244: Human Resources may now set measures '
                      'for somebody outside their line. 241 has been undone.';
    end if;
  else
    raise notice 'Migration 244: nobody is in Human Resources; HR path unchecked.';
  end if;

  raise notice 'org_people_table: % staff, % with no manager, % with no '
               'designation, % with no location',
    o->'summary'->>'people', o->'summary'->>'noManager',
    o->'summary'->>'noDesignation', o->'summary'->>'noLocation';
end $guard$;
