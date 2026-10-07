-- The list that finds the gaps can now close them (248)
--
-- "I am able to update and change the managers, but nothing else designation,
--  chair, location, department and other important aspects."
-- "...and one that you missed about assigning People  No manager 1 · No chair 2
--  · No designation 49 · No department 49 · No location"
--
-- Migration 244 built the flat list of everybody and said, in its own words,
-- WHAT IT DOES NOT DO: "It does not write." That was the right call then --
-- moving somebody is org_move_person's and a second writer would be a second
-- set of rules to keep in step. But it left the list able to point at 49
-- people with no designation and unable to give one to any of them, which is
-- the defect the owner is reporting. A screen that can only name a problem is
-- half a tool.
--
-- So this is the writer, and it is built to 244's own rule rather than
-- against it:
--
--   * The reporting line is STILL org_move_person's. org_person_set does not
--     touch manager_id; it calls org_move_person and hands back whatever that
--     function says. One set of reporting rules, one audit row, one place to
--     fix a bug in them.
--   * Everything else -- designation, department, chair, location, employee
--     type, mobile, work e-mail, employee number, joining date -- is written
--     here, once, with the same gate 244 and org_move_person already use,
--     word for word: `app_role = 'ADMIN' or department = 'Human Resources'`.
--     Migration 242's lesson is that an offer must ask the question the write
--     asks. The list offers these fields; this is the write behind them.
--   * The application role is the one field an administrator may set and HR
--     may not, because it is the only one on the list that changes what
--     somebody can DO rather than what they are. HR cleaning up a department
--     must not be able to make somebody an administrator by typing in a box.
--
-- ATOMIC ON PURPOSE. Every field is validated before any field is written. A
-- form with six boxes in it, three of them wrong, must not save the other
-- three and leave the person guessing which. Nothing is saved and the reply
-- names each bad box.
--
-- WHAT IT STILL WILL NOT DO. It does not create a designation, a chair or a
-- seating that does not exist. Letting a free-typed title become a new
-- designation is how a company ends up with "Branch Manager", "branch mgr"
-- and "Br. Manager" as three different things, and the whole point of this
-- screen is to stop that. org_assign_options hands the screen the real lists
-- to pick from.
--
-- And it does not widen 241. A designation, a department, a chair and a place
-- are not performance. perf_rel, perf_may_set and perf_line are untouched:
-- HR still cannot set a named person's KPIs or targets.

-- =====================================================================
-- The pick-lists. The screen draws dropdowns, not text boxes, and these
-- are what is in them.
-- =====================================================================
create or replace function org_assign_options(p_actor uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  a person;
begin
  select * into a from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null then
    return jsonb_build_object('error','not_permitted','reason','Who is asking?');
  end if;

  -- The same words, again. If this ever diverges from org_people_table the
  -- screen will draw a dropdown nobody is allowed to use.
  if not (a.app_role = 'ADMIN' or coalesce(a.department,'') = 'Human Resources') then
    return jsonb_build_object('mayUse', false,
      'reason','Assigning people is the administrator''s and Human Resources''.');
  end if;

  return jsonb_build_object(
    'mayUse', true,
    -- Only an administrator may change what somebody is allowed to do.
    'maySetRole', a.app_role = 'ADMIN',

    'designations', coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'title', d.title,
                                          'seniority', d.seniority)
                       order by d.seniority, d.title)
        from designation d), '[]'::jsonb),

    -- Free text in the column, so the list is what is already in use. A
    -- department nobody is in is a department that should not be offered.
    'departments', coalesce((
      select jsonb_agg(distinct btrim(p.department))
        from person p
       where p.employment_status = 'ACTIVE' and p.superseded_by is null
         and coalesce(btrim(p.department),'') <> ''), '[]'::jsonb),

    'chairs', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'code', c.code,
                                          'title', c.title, 'level', c.level,
                                          'seats', (select count(*) from chair_seating cs
                                                     where cs.chair_id = c.id))
                       order by c.title)
        from chair c), '[]'::jsonb),

    -- A place is a seating OF a chair, which is why it is not a free list:
    -- picking Mumbai only means something once the chair is known.
    'seatings', coalesce((
      select jsonb_agg(jsonb_build_object('id', cs.id, 'chairId', cs.chair_id,
                                          'label', cs.scope_label)
                       order by cs.scope_label)
        from chair_seating cs
       where coalesce(btrim(cs.scope_label),'') <> ''), '[]'::jsonb),

    -- CLIENT_CONTACT and SERVICE_ACCOUNT are deliberately not offered. 238
    -- took the client contacts out of the staff list and 245 took the
    -- service account out; a dropdown that can put them back is a dropdown
    -- that undoes two migrations.
    'employeeTypes', jsonb_build_array('EMPLOYEE','PARTNER','INTERN','CONTRACT'),
    'appRoles', jsonb_build_array('VIEWER','MANAGER','ADMIN'),

    'note','Pick from these. A designation or a chair that is not on the list '
        || 'does not exist yet, and spelling one into being is how the same '
        || 'job ends up recorded three different ways.');
end
$function$;

comment on function org_assign_options(uuid) is
  'The dropdowns behind the All people table: designations, departments in '
  'use, chairs, the seatings of each chair, employee types and roles. Same '
  'gate as org_people_table, so an offer and its write agree.';

-- =====================================================================
-- The write.
-- =====================================================================
create or replace function org_person_set(p_actor uuid, p_person uuid,
                                          p_fields jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public'
as $function$
declare
  a person; s person;
  v_admin boolean; v_hr boolean;
  v_bad jsonb := '[]'::jsonb;
  v_changed jsonb := '[]'::jsonb;
  v_old jsonb := '{}'::jsonb;
  v_new jsonb := '{}'::jsonb;

  v_has_desig boolean; v_desig uuid;
  v_has_dept  boolean; v_dept text;
  v_has_chair boolean; v_chair uuid;
  v_has_seat  boolean; v_seat uuid;
  v_has_type  boolean; v_type text;
  v_has_mob   boolean; v_mob text;
  v_has_mail  boolean; v_mail text;
  v_has_no    boolean; v_no text;
  v_has_join  boolean; v_join date;
  v_has_role  boolean; v_role text;

  v_chair_now uuid; v_seat_now uuid;
  v_target_chair uuid;
  v_move jsonb;
  t text;
begin
  -- -------------------------------------------------------- who is asking
  select * into a from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null then
    return jsonb_build_object('error','not_permitted','reason','Who is asking?');
  end if;

  select * into s from person
   where id = p_person and employment_status = 'ACTIVE' and superseded_by is null;
  if s.id is null then
    return jsonb_build_object('error','no_such_person');
  end if;

  v_admin := a.app_role = 'ADMIN';
  v_hr    := coalesce(a.department,'') = 'Human Resources';

  if not (v_admin or v_hr) then
    return jsonb_build_object('error','not_permitted',
      'reason','Changing somebody''s designation, chair, place or department '
            || 'is the administrator''s and Human Resources''. Your own team '
            || 'is the chart above.');
  end if;

  -- The service account is not a person and nothing about it is editable.
  -- 245 put it outside the staff list; this keeps it there.
  if coalesce(s.employee_type,'EMPLOYEE') in ('SERVICE_ACCOUNT','CLIENT_CONTACT') then
    return jsonb_build_object('error','not_staff',
      'reason', s.full_name || ' is not a member of staff.');
  end if;

  if p_fields is null or jsonb_typeof(p_fields) <> 'object' then
    return jsonb_build_object('error','nothing_to_set',
      'reason','Send the fields to change.');
  end if;

  -- ===================================================================
  -- Validate everything first. A form with three bad boxes must not save
  -- the other three and leave somebody guessing which took.
  -- ===================================================================
  v_has_desig := p_fields ? 'designationId';
  if v_has_desig then
    v_desig := nullif(btrim(coalesce(p_fields->>'designationId','')),'')::uuid;
    if v_desig is not null and not exists (select 1 from designation d where d.id = v_desig) then
      v_bad := v_bad || jsonb_build_object('field','designation',
        'reason','That designation does not exist. Pick one from the list.');
    end if;
  end if;

  v_has_dept := p_fields ? 'department';
  if v_has_dept then
    v_dept := nullif(btrim(coalesce(p_fields->>'department','')),'');
    if v_dept is not null and length(v_dept) > 80 then
      v_bad := v_bad || jsonb_build_object('field','department',
        'reason','A department name longer than eighty characters is a sentence.');
    end if;
  end if;

  v_has_chair := p_fields ? 'chairId';
  if v_has_chair then
    v_chair := nullif(btrim(coalesce(p_fields->>'chairId','')),'')::uuid;
    if v_chair is not null and not exists (select 1 from chair c where c.id = v_chair) then
      v_bad := v_bad || jsonb_build_object('field','chair',
        'reason','That chair does not exist.');
    end if;
  end if;

  select h.chair_id, h.seating_id into v_chair_now, v_seat_now
    from chair_holder h
   where h.person_id = p_person and h.is_primary and h.to_date is null
   limit 1;

  v_has_seat := p_fields ? 'seatingId';
  if v_has_seat then
    v_seat := nullif(btrim(coalesce(p_fields->>'seatingId','')),'')::uuid;
    -- Which chair the seating has to belong to: the one being set in this
    -- same call if there is one, otherwise the one they already hold.
    v_target_chair := case when v_has_chair then v_chair else v_chair_now end;
    if v_seat is not null then
      if v_target_chair is null then
        v_bad := v_bad || jsonb_build_object('field','location',
          'reason','A place is a seating of a chair. Give them a chair first.');
      elsif not exists (select 1 from chair_seating cs
                         where cs.id = v_seat and cs.chair_id = v_target_chair) then
        v_bad := v_bad || jsonb_build_object('field','location',
          'reason','That place belongs to a different chair.');
      end if;
    end if;
  end if;

  v_has_type := p_fields ? 'employeeType';
  if v_has_type then
    v_type := nullif(btrim(coalesce(p_fields->>'employeeType','')),'');
    if v_type is null or v_type not in ('EMPLOYEE','PARTNER','INTERN','CONTRACT') then
      v_bad := v_bad || jsonb_build_object('field','employeeType',
        'reason','Employee, Partner, Intern or Contract.');
    end if;
  end if;

  v_has_mob := p_fields ? 'mobile';
  if v_has_mob then
    v_mob := nullif(btrim(coalesce(p_fields->>'mobile','')),'');
    if v_mob is not null then
      if person_mobile(v_mob) !~ '^[6-9][0-9]{9}$' then
        v_bad := v_bad || jsonb_build_object('field','mobile',
          'reason','An Indian mobile number: ten digits starting 6, 7, 8 or 9.');
      elsif exists (select 1 from person p where p.id <> p_person
                     and p.left_on is null
                     and person_mobile(p.mobile) = person_mobile(v_mob)) then
        v_bad := v_bad || jsonb_build_object('field','mobile',
          'reason','Somebody else already has that number.');
      end if;
    end if;
  end if;

  v_has_mail := p_fields ? 'workEmail';
  if v_has_mail then
    v_mail := lower(nullif(btrim(coalesce(p_fields->>'workEmail','')),''));
    if v_mail is not null then
      if v_mail !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-zA-Z]{2,}$' then
        v_bad := v_bad || jsonb_build_object('field','workEmail',
          'reason','That is not an e-mail address.');
      elsif exists (select 1 from person p where p.id <> p_person
                     and p.superseded_by is null and p.left_on is null
                     and lower(p.work_email) = v_mail) then
        v_bad := v_bad || jsonb_build_object('field','workEmail',
          'reason','Somebody else already has that address.');
      end if;
    end if;
  end if;

  v_has_no := p_fields ? 'employeeNo';
  if v_has_no then
    v_no := nullif(btrim(coalesce(p_fields->>'employeeNo','')),'');
    if v_no is not null then
      if v_no !~ '^[A-Za-z0-9][A-Za-z0-9/_-]{0,19}$' then
        v_bad := v_bad || jsonb_build_object('field','employeeNo',
          'reason','Letters, numbers, slash, dash or underscore. Twenty at most.');
      elsif exists (select 1 from person p where p.id <> p_person
                     and p.superseded_by is null
                     and lower(btrim(p.employee_no)) = lower(v_no)) then
        v_bad := v_bad || jsonb_build_object('field','employeeNo',
          'reason','Somebody else already has that employee number.');
      end if;
    end if;
  end if;

  v_has_join := p_fields ? 'joinedOn';
  if v_has_join then
    begin
      v_join := nullif(btrim(coalesce(p_fields->>'joinedOn','')),'')::date;
    exception when others then
      v_join := null;
      v_bad := v_bad || jsonb_build_object('field','joinedOn',
        'reason','A date, as 2026-10-07.');
    end;
    if v_join is not null and v_join > current_date then
      v_bad := v_bad || jsonb_build_object('field','joinedOn',
        'reason','That is in the future. A joining date that has not happened '
              || 'yet belongs on an offer, not on a person.');
    end if;
  end if;

  v_has_role := p_fields ? 'appRole';
  if v_has_role then
    v_role := upper(nullif(btrim(coalesce(p_fields->>'appRole','')),''));
    if not v_admin then
      v_bad := v_bad || jsonb_build_object('field','appRole',
        'reason','What somebody is allowed to DO is the administrator''s. '
              || 'Everything else on this row is yours.');
    elsif v_role is null or v_role not in ('VIEWER','MANAGER','ADMIN') then
      v_bad := v_bad || jsonb_build_object('field','appRole',
        'reason','Viewer, Manager or Admin.');
    elsif p_person = p_actor and v_role <> a.app_role::text then
      -- The same sentence perf_rel says about targets, said about privilege:
      -- nobody changes their own.
      v_bad := v_bad || jsonb_build_object('field','appRole',
        'reason','You cannot change your own role. Ask another administrator.');
    end if;
  end if;

  if jsonb_array_length(v_bad) > 0 then
    return jsonb_build_object('error','invalid',
      'fields', v_bad,
      'reason','Nothing was saved. Put these right and send it again.');
  end if;

  -- ===================================================================
  -- The reporting line, first and by delegation.
  --
  -- org_move_person owns every rule about who may move whom, refuses a
  -- ring, writes the person_event and writes the audit row. Re-stating
  -- any of that here would be a second copy to keep in step, and the
  -- first thing to go out of step would be the audit.
  -- ===================================================================
  if p_fields ? 'managerId' then
    v_move := org_move_person(p_actor, p_person,
                nullif(btrim(coalesce(p_fields->>'managerId','')),'')::uuid);
    if v_move->>'error' is not null then
      return v_move;   -- nothing else has been written yet
    end if;
    if coalesce((v_move->>'changed')::boolean, false) then
      v_changed := v_changed || jsonb_build_object('field','manager',
        'to', v_move->>'to', 'note', v_move->>'note');
    end if;
  end if;

  -- ===================================================================
  -- Everything else.
  -- ===================================================================
  if v_has_desig and s.designation_id is distinct from v_desig then
    v_old := v_old || jsonb_build_object('designationId', s.designation_id);
    v_new := v_new || jsonb_build_object('designationId', v_desig);
    update person set designation_id = v_desig where id = p_person;
    v_changed := v_changed || jsonb_build_object('field','designation',
      'from', (select d.title from designation d where d.id = s.designation_id),
      'to',   (select d.title from designation d where d.id = v_desig));
  end if;

  if v_has_dept and btrim(coalesce(s.department,'')) is distinct from coalesce(v_dept,'') then
    v_old := v_old || jsonb_build_object('department', s.department);
    v_new := v_new || jsonb_build_object('department', v_dept);
    update person set department = v_dept where id = p_person;
    v_changed := v_changed || jsonb_build_object('field','department',
      'from', s.department, 'to', v_dept);
  end if;

  if v_has_type and coalesce(s.employee_type,'EMPLOYEE') is distinct from v_type then
    v_old := v_old || jsonb_build_object('employeeType', s.employee_type);
    v_new := v_new || jsonb_build_object('employeeType', v_type);
    update person set employee_type = v_type where id = p_person;
    v_changed := v_changed || jsonb_build_object('field','employeeType',
      'from', s.employee_type, 'to', v_type);
  end if;

  if v_has_mob and s.mobile is distinct from v_mob then
    v_old := v_old || jsonb_build_object('mobile', s.mobile);
    v_new := v_new || jsonb_build_object('mobile', v_mob);
    -- A new number has not been proved to be theirs, so the proof goes with
    -- the old one rather than following them to the new one.
    update person set mobile = v_mob, mobile_verified_at = null where id = p_person;
    v_changed := v_changed || jsonb_build_object('field','mobile',
      'from', s.mobile, 'to', v_mob);
  end if;

  if v_has_mail and lower(coalesce(s.work_email,'')) is distinct from coalesce(v_mail,'') then
    v_old := v_old || jsonb_build_object('workEmail', s.work_email);
    v_new := v_new || jsonb_build_object('workEmail', v_mail);
    update person set work_email = v_mail where id = p_person;
    v_changed := v_changed || jsonb_build_object('field','workEmail',
      'from', s.work_email, 'to', v_mail);
  end if;

  if v_has_no and btrim(coalesce(s.employee_no,'')) is distinct from coalesce(v_no,'') then
    v_old := v_old || jsonb_build_object('employeeNo', s.employee_no);
    v_new := v_new || jsonb_build_object('employeeNo', v_no);
    update person set employee_no = v_no where id = p_person;
    v_changed := v_changed || jsonb_build_object('field','employeeNo',
      'from', s.employee_no, 'to', v_no);
  end if;

  if v_has_join and s.joined_on is distinct from v_join then
    v_old := v_old || jsonb_build_object('joinedOn', s.joined_on);
    v_new := v_new || jsonb_build_object('joinedOn', v_join);
    update person set joined_on = v_join where id = p_person;
    v_changed := v_changed || jsonb_build_object('field','joinedOn',
      'from', s.joined_on, 'to', v_join);
  end if;

  if v_has_role and s.app_role::text is distinct from v_role then
    v_old := v_old || jsonb_build_object('appRole', s.app_role);
    v_new := v_new || jsonb_build_object('appRole', v_role);
    update person set app_role = v_role::role_kind where id = p_person;
    insert into person_event (person_id, kind, note, at)
    values (p_person, 'ROLE_CHANGED',
            s.app_role::text || ' -> ' || v_role, now());
    v_changed := v_changed || jsonb_build_object('field','appRole',
      'from', s.app_role, 'to', v_role);
  end if;

  -- ------------------------------------------------------- chair and place
  -- A chair is held, not owned: the old holding is closed rather than
  -- overwritten, so last year's answer to "who sat there" survives.
  if v_has_chair and v_chair_now is distinct from v_chair then
    update chair_holder
       set to_date = current_date
     where person_id = p_person and is_primary and to_date is null;
    if v_chair is not null then
      insert into chair_holder (chair_id, person_id, is_primary, from_date, seating_id)
      values (v_chair, p_person, true, current_date,
              case when v_has_seat then v_seat else null end);
    end if;
    v_old := v_old || jsonb_build_object('chairId', v_chair_now);
    v_new := v_new || jsonb_build_object('chairId', v_chair);
    v_changed := v_changed || jsonb_build_object('field','chair',
      'from', (select c.title from chair c where c.id = v_chair_now),
      'to',   (select c.title from chair c where c.id = v_chair));
    v_seat_now := null;   -- the new holding starts from whatever was just set

  elsif v_has_seat and v_seat_now is distinct from v_seat then
    if v_chair_now is null then
      -- Already refused above; here only if the chair was cleared in the
      -- same call, which leaves nothing to seat.
      null;
    else
      update chair_holder set seating_id = v_seat
       where person_id = p_person and is_primary and to_date is null;
      v_old := v_old || jsonb_build_object('seatingId', v_seat_now);
      v_new := v_new || jsonb_build_object('seatingId', v_seat);
      v_changed := v_changed || jsonb_build_object('field','location',
        'from', (select cs.scope_label from chair_seating cs where cs.id = v_seat_now),
        'to',   (select cs.scope_label from chair_seating cs where cs.id = v_seat));
    end if;
  end if;

  if jsonb_array_length(v_changed) = 0 then
    return jsonb_build_object('ok', true, 'changed', false, 'personId', p_person,
      'fields','[]'::jsonb,
      'note','Nothing was different. Nothing was written.');
  end if;

  -- One audit row for the call, carrying only what actually moved. The
  -- reporting line, if it moved, already has its own from org_move_person.
  if v_old <> '{}'::jsonb then
    insert into audit_entry (actor_id, action, entity_type, entity_ref,
                             old_value, new_value)
    values (p_actor, 'PERSON_ASSIGNED', 'person', p_person::text, v_old, v_new);

    select string_agg(x->>'field', ', ' order by x->>'field') into t
      from jsonb_array_elements(v_changed) x where x->>'field' <> 'manager';
    insert into person_event (person_id, kind, note, at)
    values (p_person, 'DETAILS_CHANGED', coalesce(t,'details'), now());
  end if;

  return jsonb_build_object('ok', true, 'changed', true, 'personId', p_person,
    'name', s.full_name, 'fields', v_changed,
    'note', s.full_name || ': ' ||
            coalesce((select string_agg(x->>'field', ', ' order by x->>'field')
                        from jsonb_array_elements(v_changed) x), 'nothing') ||
            ' updated.');
end
$function$;

comment on function org_person_set(uuid, uuid, jsonb) is
  'Set a person''s designation, department, chair, place, employee type, '
  'mobile, work e-mail, employee number, joining date or role from the All '
  'people table. Validates every field before writing any, delegates the '
  'reporting line to org_move_person, and audits. Administrator and HR; the '
  'role is the administrator''s alone.';

-- =====================================================================
-- The same thing to many people at once -- which is what the gap chips
-- are for. "49 with no department" is not 49 separate decisions; it is
-- usually one decision applied to a group.
-- =====================================================================
create or replace function org_person_set_many(p_actor uuid, p_people jsonb,
                                               p_fields jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public'
as $function$
declare
  v_id uuid; o jsonb;
  v_done jsonb := '[]'::jsonb;
  v_failed jsonb := '[]'::jsonb;
  n_changed int := 0;
begin
  if p_people is null or jsonb_typeof(p_people) <> 'array'
     or jsonb_array_length(p_people) = 0 then
    return jsonb_build_object('error','nobody_chosen',
      'reason','Tick the people this applies to.');
  end if;
  -- A cap, because "everybody" typed by accident is a 103-row write with no
  -- undo. Fifty is more than any one gap on the list today.
  if jsonb_array_length(p_people) > 60 then
    return jsonb_build_object('error','too_many',
      'reason','Sixty people at a time. More than that is an import, not a tidy-up.');
  end if;

  for v_id in select (x #>> '{}')::uuid from jsonb_array_elements(p_people) x loop
    o := org_person_set(p_actor, v_id, p_fields);
    if o->>'error' is not null then
      -- One person's bad row must not stop the other forty-eight, and must
      -- not be silently dropped either.
      v_failed := v_failed || jsonb_build_object('personId', v_id,
        'name', (select full_name from person where id = v_id),
        'error', o->>'error', 'reason', o->>'reason', 'fields', o->'fields');
    else
      if coalesce((o->>'changed')::boolean, false) then n_changed := n_changed + 1; end if;
      v_done := v_done || jsonb_build_object('personId', v_id,
        'name', o->>'name', 'changed', coalesce((o->>'changed')::boolean,false));
    end if;
  end loop;

  return jsonb_build_object(
    'ok', jsonb_array_length(v_failed) = 0,
    'changed', n_changed,
    'asked', jsonb_array_length(p_people),
    'done', v_done, 'failed', v_failed,
    'note', n_changed || ' of ' || jsonb_array_length(p_people) || ' updated' ||
            case when jsonb_array_length(v_failed) > 0
                 then ', ' || jsonb_array_length(v_failed) || ' refused.'
                 else '.' end);
end
$function$;

comment on function org_person_set_many(uuid, jsonb, jsonb) is
  'org_person_set over a list of people, for the gap chips on the All people '
  'table. Carries on past one refusal and reports every one of them.';

-- =====================================================================
-- The reader gains the ids the writer needs.
--
-- 244 returned the designation TITLE and the chair TITLE, which is right
-- for reading and useless for a dropdown: a <select> is keyed by id. The
-- row now carries both, and says whether this reader may edit it.
-- =====================================================================
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

  v_may := a.app_role = 'ADMIN' or coalesce(a.department,'') = 'Human Resources';

  if not v_may then
    return jsonb_build_object(
      'mayUse', false,
      'reason', 'This list is every person in the company, so it is the '
             || 'administrator''s and Human Resources''. Your own team is '
             || 'the chart above.');
  end if;

  with staff as (
    select p.* from person p
     where p.employment_status = 'ACTIVE' and p.superseded_by is null
       and coalesce(p.employee_type,'EMPLOYEE')
           not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
  ), seat as (
    select distinct on (h.person_id)
           h.person_id, h.chair_id, h.seating_id,
           ch.title as chair, cs.scope_label
      from chair_holder h
      join chair ch on ch.id = h.chair_id
      left join chair_seating cs on cs.id = h.seating_id
     where h.to_date is null
     order by h.person_id, h.is_primary desc nulls last, ch.title
  ), cov as (
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
             'designationId', s.designation_id,
             'department',  s.department,
             'chair',       seat.chair,
             'chairId',     seat.chair_id,
             'seatingId',   seat.seating_id,
             'location',    coalesce(seat.scope_label, cov.place),
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
             'mayMove',     s.id <> p_actor,
             -- Everything but the reporting line and the role: those two
             -- have their own narrower rules and say so for themselves.
             'mayEdit',     true,
             'maySetRole',  a.app_role = 'ADMIN' and s.id <> p_actor
           ) as line
      from staff s
      left join designation d on d.id = s.designation_id
      left join seat on seat.person_id = s.id
      left join cov  on cov.person_id  = s.id
      left join person m on m.id = s.manager_id
      left join rep on rep.id = s.id
  )
  select jsonb_agg(line order by full_name) into v_rows from flat;

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

-- =====================================================================
-- The guard.
-- =====================================================================
do $guard$
declare
  v_admin uuid; v_hr uuid; v_other uuid; v_who uuid;
  v_desig uuid; v_desig2 uuid; v_chair uuid; v_seat uuid; v_wrong_seat uuid;
  o jsonb; n int;
begin
  -- A STAFF administrator. On the live project the account the tool is
  -- administered from is a service account (243, 245), and org_person_set
  -- refuses to edit one -- which is the right answer and the wrong actor for
  -- the self-role check below.
  select id into v_admin from person
   where employment_status='ACTIVE' and superseded_by is null and app_role='ADMIN'
     and coalesce(employee_type,'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
   limit 1;
  if v_admin is null then
    raise notice 'Migration 248: no staff administrator to check against.';
    return;
  end if;

  -- Somebody who is neither administrator nor HR is refused, with a reason.
  select id into v_other from person
   where employment_status='ACTIVE' and superseded_by is null
     and app_role is distinct from 'ADMIN'
     and coalesce(department,'') <> 'Human Resources'
     and coalesce(employee_type,'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
   limit 1;
  if v_other is not null then
    o := org_person_set(v_other, v_admin, jsonb_build_object('department','Nope'));
    if o->>'error' is distinct from 'not_permitted' then
      raise exception 'Migration 248: an ordinary person edited somebody: %', o;
    end if;
    if o->>'reason' is null then
      raise exception 'Migration 248: the refusal carries no reason.';
    end if;
    o := org_assign_options(v_other);
    if coalesce((o->>'mayUse')::boolean,false) then
      raise exception 'Migration 248: an ordinary person was handed the dropdowns.';
    end if;
  end if;

  -- The administrator is offered the dropdowns, and they are not empty.
  o := org_assign_options(v_admin);
  if not coalesce((o->>'mayUse')::boolean,false) then
    raise exception 'Migration 248: the administrator was refused the dropdowns.';
  end if;
  -- A notice, not an exception: the baseline this also runs against in
  -- build/test/run.sh is a schema with no rows in it, and "there are no
  -- designations yet" is a true statement about an empty database rather
  -- than a fault in the function being checked.
  if jsonb_array_length(o->'designations') = 0 then
    raise notice 'Migration 248: no designations exist yet.';
  end if;
  if jsonb_array_length(o->'chairs') = 0 then
    raise notice 'Migration 248: no chairs exist yet.';
  end if;

  -- The row the screen draws carries the ids the dropdowns are keyed by.
  o := org_people_table(v_admin);
  select count(*) into n from jsonb_array_elements(o->'people') r
   where not (r ? 'designationId') or not (r ? 'chairId') or not (r ? 'seatingId');
  if n > 0 then
    raise exception 'Migration 248: % row(s) carry no ids for the dropdowns.', n;
  end if;

  -- Nobody changes their own role, administrator or not.
  o := org_person_set(v_admin, v_admin, jsonb_build_object('appRole','VIEWER'));
  if o->>'error' is distinct from 'invalid' then
    raise exception 'Migration 248: an administrator demoted themselves: %', o;
  end if;

  -- The service account stays outside all of this. 245 took it out of the
  -- staff list; a form that can put a department on it puts it back.
  if exists (select 1 from person where employee_type = 'SERVICE_ACCOUNT') then
    o := org_person_set(v_admin,
           (select id from person where employee_type='SERVICE_ACCOUNT' limit 1),
           jsonb_build_object('department','Operations'));
    if o->>'error' is distinct from 'not_staff' then
      raise exception 'Migration 248: the service account was edited as a '
                      'person: %', o;
    end if;
  end if;

  -- An unknown designation is refused by name rather than written.
  select id into v_who from person
   where employment_status='ACTIVE' and superseded_by is null
     and id <> v_admin
     and coalesce(employee_type,'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
   limit 1;
  o := org_person_set(v_admin, v_who,
         jsonb_build_object('designationId','00000000-0000-0000-0000-000000000000'));
  if o->>'error' is distinct from 'invalid' then
    raise exception 'Migration 248: a designation that does not exist was accepted: %', o;
  end if;

  -- And a bad field does not let a good one through beside it.
  o := org_person_set(v_admin, v_who, jsonb_build_object(
         'designationId','00000000-0000-0000-0000-000000000000',
         'department','Should Not Land'));
  if exists (select 1 from person p where p.id = v_who and p.department = 'Should Not Land') then
    raise exception 'Migration 248: a good field saved beside a bad one. The '
                    'write is not atomic.';
  end if;

  -- A place that belongs to another chair is refused.
  select cs.id, cs.chair_id into v_seat, v_chair
    from chair_seating cs where coalesce(btrim(cs.scope_label),'') <> '' limit 1;
  select cs.id into v_wrong_seat from chair_seating cs
   where cs.chair_id is distinct from v_chair limit 1;
  if v_seat is not null and v_wrong_seat is not null then
    o := org_person_set(v_admin, v_who,
           jsonb_build_object('chairId', v_chair, 'seatingId', v_wrong_seat));
    if o->>'error' is distinct from 'invalid' then
      raise exception 'Migration 248: a place belonging to another chair was '
                      'accepted: %', o;
    end if;
  end if;

  -- The bulk form refuses an empty list rather than quietly doing nothing.
  o := org_person_set_many(v_admin, '[]'::jsonb, jsonb_build_object('department','X'));
  if o->>'error' is distinct from 'nobody_chosen' then
    raise exception 'Migration 248: the bulk form accepted nobody: %', o;
  end if;

  -- 241 still stands: none of this gave HR a measure it did not have.
  select id into v_hr from person
   where employment_status='ACTIVE' and superseded_by is null
     and coalesce(department,'') = 'Human Resources'
     and app_role is distinct from 'ADMIN' limit 1;
  if v_hr is not null then
    if coalesce((org_assign_options(v_hr)->>'maySetRole')::boolean, false) then
      raise exception 'Migration 248: Human Resources was offered the role box.';
    end if;
    if exists (select 1 from person p
                where p.employment_status='ACTIVE' and p.superseded_by is null
                  and p.id <> v_hr
                  and not exists (select 1 from perf_line(v_hr) l where l.person_id = p.id)
                  and perf_may_set(v_hr, p.id)) then
      raise exception 'Migration 248: HR may now set measures outside their line. '
                      '241 has been undone.';
    end if;
  end if;

  raise notice 'org_person_set: the gaps on the All people table can now be closed.';
end $guard$;
