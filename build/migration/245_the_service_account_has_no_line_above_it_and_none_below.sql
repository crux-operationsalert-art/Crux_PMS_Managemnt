-- The service account has no line above it, and none below (245)
--
-- Migration 243 marked operations.alert@cruxindia.co.in SERVICE_ACCOUNT,
-- cleared its manager and widened thirteen functions that already knew a
-- client contact is not staff. Two things it did not reach were then found
-- by measuring rather than by reading, and this closes both.
--
-- ------------------------------------------------------------- the first
-- THE PEOPLE UPLOAD TEMPLATE STILL CARRIED IT, so the next upload would
-- have quietly put it back.
--
--     select count(*) from upload_seed('People')   ->  104
--     ... where the row mentions operations.alert  ->    1
--
-- upload_seed fills the template from `is_staff`, and is_staff is a SECOND
-- staff test that does not read employee_type at all. It asks whether the
-- person has an employee number, OR an address at our own domain, OR a
-- chair. The service account has no employee number and no chair -- but its
-- address is operations.alert@cruxindia.co.in, so the domain arm answered
-- yes.
--
-- Two functions, is_staff and person_is_staff, disagreed about the same
-- person: person_is_staff said false (243 widened it) and is_staff said
-- true. They are not merged here, because they genuinely ask different
-- questions and only one of them has a caller; what is fixed is the thing
-- they must agree on, which is that a row which is not a member of staff is
-- not a member of staff whichever way you ask.
--
-- ------------------------------------------------------------ the second
-- THREE LINE WALKERS HAVE NO EMPLOYEE_TYPE TEST AT ALL -- org_subtree,
-- which Team & structure and org_move_person are built on; app_subtree,
-- which feeds ten row-level security policies; and the reports count on
-- each tile in org_team_tree. perf_reminder_sweep joins the same way, and
-- that one sends mail.
--
-- None of them carries the service account today, and that was measured
-- rather than assumed:
--
--     non-staff rows with a manager        ->  0
--     non-staff rows managing somebody     ->  0
--
-- They are clean only because 243 set manager_id to null. The predicate is
-- absent, not satisfied, so the moment anybody gives a service account a
-- manager -- or makes somebody report to one -- all four carry it again.
--
-- WHY A RULE AND NOT FOUR MORE COPIES OF A PREDICATE. The obvious fix is to
-- add `employee_type not in (...)` to each of the four. That is a fifth,
-- sixth, seventh and eighth copy of one sentence, in four function bodies
-- that have already drifted apart once -- which is exactly how is_staff and
-- person_is_staff came to disagree, and exactly what the audit above found.
--
-- So the sentence is said once, to the table, as a rule the database keeps:
-- a service account is not in the reporting line, in either direction. The
-- four walkers then cannot carry one whatever their text says, and a fifth
-- walker written next year is covered without being told.
--
-- This is also the honest statement of what was asked for -- "not an
-- employee to be reporting to anyone" -- with the other half said as well,
-- because an account nobody can manage that forty people report to would be
-- just as wrong.

-- ----------------------------------------------- is_staff reads the type
-- Rewritten over the live source rather than from memory, keeping all three
-- arms of the original test. Only the new line is new.
create or replace function is_staff(p_person uuid)
returns boolean
language sql
stable
as $function$
  select exists (
    select 1 from person p
     where p.id = p_person
       and p.superseded_by is null
       -- Added by 245. A row in `person` that is not somebody who works
       -- here is not staff, whichever of the three arms below says yes --
       -- and the service account says yes on the domain arm, because the
       -- address really is at our own domain. That is what put it in the
       -- People upload template.
       and coalesce(p.employee_type,'EMPLOYEE')
           not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
       and (p.employee_no is not null
            or lower(p.work_email) like '%@cruxindia.co.in'
            or exists (select 1 from chair_holder h
                        where h.person_id = p.id and h.to_date is null)));
$function$;

-- ------------------------------------- a service account reports to nobody
-- A CHECK is the right shape for this half: it is a statement about one
-- row, so the database can keep it without being asked, on every insert and
-- every update, from every code path including the uploads.
do $up$
begin
  if exists (select 1 from pg_constraint c
              join pg_class t on t.oid = c.conrelid
              join pg_namespace n on n.oid = t.relnamespace
             where n.nspname = 'public' and t.relname = 'person'
               and c.conname = 'person_service_account_reports_to_nobody') then
    raise notice 'the constraint is already there';
  else
    -- Checked first, because adding a constraint that existing rows break
    -- fails the whole migration with a message about a row rather than
    -- about the idea.
    if exists (select 1 from person
                where employee_type = 'SERVICE_ACCOUNT' and manager_id is not null) then
      raise exception 'Migration 245: % service account(s) still have a manager. '
                      'Clear it before this rule can be kept.',
        (select count(*) from person
          where employee_type = 'SERVICE_ACCOUNT' and manager_id is not null);
    end if;
    alter table person add constraint person_service_account_reports_to_nobody
      check (employee_type is distinct from 'SERVICE_ACCOUNT' or manager_id is null);
    raise notice 'a service account may no longer be given a manager';
  end if;
end $up$;

-- ------------------------------------- and nobody reports to one
-- The other half is a statement about two rows, which a CHECK cannot make,
-- so it is a trigger. It fires only where manager_id is being set, and only
-- looks at one row, so it costs a single indexed read on the one write path
-- that could break the rule.
create or replace function person_manager_is_not_a_service_account()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare v_name text;
begin
  if new.manager_id is null then
    return new;
  end if;
  select full_name into v_name from person
   where id = new.manager_id and employee_type = 'SERVICE_ACCOUNT';
  if v_name is not null then
    raise exception using
      errcode = '23514',
      message = format('%s is the account the tool is administered from, not '
                    || 'somebody who works here, so nobody can report to it.',
                       v_name),
      hint = 'Choose the person who actually manages them.';
  end if;
  return new;
end
$function$;

drop trigger if exists person_manager_is_not_a_service_account on person;
create trigger person_manager_is_not_a_service_account
  before insert or update of manager_id on person
  for each row execute function person_manager_is_not_a_service_account();

comment on function person_manager_is_not_a_service_account() is
  'Refuses a reporting line INTO a service account. The other direction -- a '
  'service account with a manager -- is the check constraint '
  'person_service_account_reports_to_nobody. Together they are why '
  'org_subtree, app_subtree, org_team_tree and perf_reminder_sweep need no '
  'employee_type test of their own.';

-- ------------------------------------------------------------- the guard
do $guard$
declare
  v_id uuid; v_name text; n int; n_all int; v_victim uuid; v_caught boolean;
begin
  select id, full_name into v_id, v_name from person
   where lower(work_email) = 'operations.alert@cruxindia.co.in';

  -- ----------------------------------------------- the upload template
  if v_id is not null then
    if is_staff(v_id) then
      raise exception 'Migration 245: is_staff still calls the service account staff.';
    end if;
    if person_is_staff(v_id) then
      raise exception 'Migration 245: person_is_staff still calls it staff.';
    end if;
    raise notice 'both staff tests now agree about %', v_name;

    -- The template is only worth measuring where there is a company in the
    -- table. A fresh schema with a handful of fixture rows has neither, and
    -- a row count asserted against it would fail for being empty rather
    -- than for being wrong.
    select count(*) into n_all from upload_seed('People') t;
    select count(*) into n from upload_seed('People') t
     where t::text ilike '%operations.alert%';
    if n > 0 then
      raise exception 'Migration 245: the People upload template still carries '
                      'the service account, so the next upload would put it back.';
    end if;
    -- It took out ONE row and not a hundred. A staff test that had quietly
    -- become stricter than intended would show here as a template with half
    -- the company missing.
    if n_all < 90 then
      raise exception 'Migration 245: the People template is down to % rows, '
                      'which is not the company.', n_all;
    end if;
    raise notice 'the People upload template is % rows and the service account '
                 'is not one of them', n_all;
  end if;

  -- Everybody who IS staff is still in it.
  select count(*) into n from person p
   where p.employment_status = 'ACTIVE' and p.superseded_by is null
     and coalesce(p.employee_type,'EMPLOYEE')
         not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
     and not is_staff(p.id);
  if n > 0 then
    raise exception 'Migration 245: % member(s) of staff are no longer read '
                    'as staff.', n;
  end if;
  raise notice 'every member of staff still reads as staff';

  -- --------------------------------------------- the rule, both directions
  if v_id is not null then
    -- Downward: nobody may be made to report to it.
    select id into v_victim from person
     where employment_status = 'ACTIVE' and superseded_by is null
       and id <> v_id and app_role is distinct from 'ADMIN'
     limit 1;
    if v_victim is not null then
      -- The write is attempted for real and then always unwound: the block
      -- raises its own exception on the path where the rule FAILED to
      -- fire, so the subtransaction rolls back either way and this guard
      -- never leaves a changed row behind. (The pattern test_offer uses.)
      v_caught := false;
      begin
        update person set manager_id = v_id where id = v_victim;
        raise exception using errcode = 'P0001', message = 'it went through';
      exception
        when sqlstate 'P0001' then
          v_caught := sqlerrm <> 'it went through';
        when others then
          v_caught := true;
      end;
      if not v_caught then
        raise exception 'Migration 245: somebody was given the service '
                        'account as their manager.';
      end if;
      raise notice 'nobody can be made to report to the service account';
    end if;

    -- Upward: it may not be given one.
    select id into v_victim from person
     where employment_status = 'ACTIVE' and superseded_by is null
       and id <> v_id limit 1;
    v_caught := false;
    begin
      update person set manager_id = v_victim where id = v_id;
      raise exception using errcode = 'P0001', message = 'it went through';
    exception
      when sqlstate 'P0001' then
        v_caught := sqlerrm <> 'it went through';
      when others then
        v_caught := true;
    end;
    if not v_caught then
      raise exception 'Migration 245: the service account was given a manager.';
    end if;
    raise notice 'and it cannot be given one';
  end if;

  -- ------------------------------------------- and an ordinary move still works
  -- A rule that refuses the one case must not refuse the hundred others.
  -- This is the move Team & structure makes, attempted for real and undone.
  declare
    v_a uuid; v_b uuid; v_ok boolean;
  begin
    select id into v_a from person
     where employment_status = 'ACTIVE' and superseded_by is null
       and manager_id is not null
       and coalesce(employee_type,'EMPLOYEE')
           not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
     limit 1;
    select id into v_b from person
     where employment_status = 'ACTIVE' and superseded_by is null
       and id <> v_a and manager_id is distinct from v_a
       and coalesce(employee_type,'EMPLOYEE')
           not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
     limit 1;
    if v_a is not null and v_b is not null then
      -- Unwound the same way, so a guard that proves a move still works
      -- does not itself move anybody.
      v_ok := false;
      begin
        update person set manager_id = v_b where id = v_a;
        v_ok := true;
        raise exception using errcode = 'P0001', message = 'undo';
      exception
        when sqlstate 'P0001' then
          if sqlerrm <> 'undo' then v_ok := false; end if;
        when others then
          v_ok := false;
      end;
      if not v_ok then
        raise exception 'Migration 245: an ordinary move between two people '
                        'is now refused. The rule is too wide.';
      end if;
      raise notice 'an ordinary move between two people is untouched';
    end if;
  end;

  -- ------------------------------------------- and the walkers are clean
  if v_id is not null then
    select count(*) into n from person p
     where p.employment_status = 'ACTIVE' and p.superseded_by is null
       and p.id <> v_id
       and exists (select 1 from org_subtree(p.id) s where s.person_id = v_id);
    if n > 0 then
      raise exception 'Migration 245: the service account is still inside % '
                      'org_subtree(s).', n;
    end if;
    raise notice 'and it is in nobody''s subtree';
  end if;
end $guard$;
