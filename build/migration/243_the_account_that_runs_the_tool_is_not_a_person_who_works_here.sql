-- The account that runs the tool is not a person who works here (243)
--
-- "Operations.alert is the admin or email to manage this tool and not an
-- employee to be reporting to anyone."
--
-- operations.alert@cruxindia.co.in holds ADMIN and is how the tool is
-- administered. It also sits in the person table as employee_type EMPLOYEE,
-- reporting to Manish Shukla, with no chair, no employee number, no
-- measures, no goal sheet and nobody reporting to it. So it is counted in
-- the headcount, drawn on the org chart under somebody, offered in people
-- pickers, and -- because it reports to Manish -- it is inside Manish's
-- team and inside Arun's line.
--
-- THE PRECEDENT. This is the second kind of row in `person` that is not a
-- member of staff. The first was the client-bank contacts, and migration
-- 238 did not invent a mechanism for them: employee_type = 'CLIENT_CONTACT'
-- already existed and fourteen functions already read it as "not staff".
--
-- So this adds one more value to that same column rather than a second
-- mechanism. Every place that already knows a contact is not staff is
-- widened, by substitution over its own source, to know that a service
-- account is not staff either. One idea -- "a person row that is not a
-- person who works here" -- said in one column, read in one place per
-- function.
--
-- WHAT IT DOES NOT TOUCH. The account keeps ADMIN and keeps signing in.
-- auth_login, auth_whoami, auth_gate and perf_rel's administrator branch
-- all read app_role and employment_status and none of them reads
-- employee_type, so nothing here takes the administrator's powers away.
-- That is the point: it administers the tool, it is not measured by it.
--
-- person_check still refuses SERVICE_ACCOUNT on the add-a-person form, and
-- that is left alone deliberately. A service account is not a joiner; it is
-- made by an administrator who knows what they are doing, not through the
-- form HR uses to hire somebody.

-- --------------------------------------------------------- the new value
-- The column is constrained to a list, so the list gains a sixth entry.
-- Checked first that the five expected are the five there, for the reason
-- migration 240 gave: rewriting a list from memory is how a value that is
-- already in use quietly becomes illegal.
do $kind$
declare v_name text; v_def text;
begin
  select c.conname, pg_get_constraintdef(c.oid) into v_name, v_def
    from pg_constraint c join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
   where n.nspname = 'public' and t.relname = 'person' and c.contype = 'c'
     and pg_get_constraintdef(c.oid) ilike '%employee_type%'
   limit 1;

  if v_name is null then
    raise exception 'Migration 243: person.employee_type is not constrained, '
                    'so this file cannot tell what the allowed values are.';
  elsif position('SERVICE_ACCOUNT' in v_def) > 0 then
    raise notice 'employee_type already allows SERVICE_ACCOUNT';
  else
    if (select count(*) from regexp_matches(v_def, '''[A-Z_]+''', 'g')) <> 5
       or position('CLIENT_CONTACT' in v_def) = 0 then
      raise exception 'Migration 243: employee_type is constrained to %, which '
                      'is not the five values this expected.', v_def;
    end if;
    execute format('alter table person drop constraint %I', v_name);
    execute format('alter table person add constraint %I check '
                || '(employee_type = any (array[''EMPLOYEE'',''PARTNER'',''INTERN'','
                || '''CONTRACT'',''CLIENT_CONTACT'',''SERVICE_ACCOUNT'']))', v_name);
    raise notice 'employee_type widened from % to six values', v_def;
  end if;
end $kind$;

-- ------------------------------------------------------------ the account
do $acct$
declare a person;
begin
  select * into a from person
   where lower(work_email) = 'operations.alert@cruxindia.co.in';
  if a.id is null then
    raise notice 'Migration 243: operations.alert is not in person; nothing marked.';
    return;
  end if;

  -- It must not be holding a chair or carrying measures. If it is, somebody
  -- has been using it as a person and this is not a safe thing to do
  -- silently.
  if exists (select 1 from chair_holder h where h.person_id = a.id and h.to_date is null)
     or exists (select 1 from perf_assignment x where x.person_id = a.id)
     or exists (select 1 from plb_goal_sheet s where s.person_id = a.id)
     or exists (select 1 from person r where r.manager_id = a.id) then
    raise exception 'Migration 243: operations.alert holds a chair, measures, a '
                    'goal sheet or reports. It is being used as a person; sort '
                    'that out before marking it a service account.';
  end if;

  insert into person_event (person_id, kind, note, at)
  values (a.id, 'TYPE_CHANGED',
          'Marked SERVICE_ACCOUNT by migration 243: this is the account the '
          'tool is administered from, not somebody who works here. Its '
          'reporting line was cleared at the same time.', now());

  update person
     set employee_type = 'SERVICE_ACCOUNT',
         manager_id = null,
         department = null
   where id = a.id;

  insert into audit_entry (actor_id, action, entity_type, entity_ref,
                           old_value, new_value)
  values (null, 'PERSON_TYPE_CHANGED', 'person', a.id::text,
          jsonb_build_object('employeeType', a.employee_type,
                             'managerId', a.manager_id,
                             'department', a.department),
          jsonb_build_object('employeeType', 'SERVICE_ACCOUNT',
                             'managerId', null, 'department', null,
                             'why', 'administers the tool; not staff'));

  raise notice 'operations.alert marked SERVICE_ACCOUNT and taken out of the line';
end $acct$;

-- ------------------------------- every place that already knows about staff
-- Fourteen functions carry the predicate. They write it in several shapes --
-- bare, p., q., pe., with and without a space after the comma -- so the
-- substitution is a regexp that keeps whatever qualifier was there and
-- changes only the comparison.
--
-- Over the source rather than by retyping each function, for the reason
-- migration 239 learned the hard way: a function retyped from memory loses a
-- clause nobody notices.
do $widen$
declare
  r record; v_src text; v_n int := 0;
begin
  for r in
    select p.proname,
           pg_get_function_identity_arguments(p.oid) as args,
           pg_get_function_result(p.oid) as ret,
           p.prosrc, p.provolatile, p.prosecdef, l.lanname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      join pg_language l on l.oid = p.prolang
     where n.nspname = 'public'
       and l.lanname in ('sql','plpgsql')
       and p.prosrc ~ 'coalesce\([a-z_]*\.?employee_type,\s*''EMPLOYEE''\)\s*<>\s*''CLIENT_CONTACT'''
  loop
    v_src := regexp_replace(
      r.prosrc,
      '(coalesce\([a-z_]*\.?employee_type,\s*''EMPLOYEE''\))\s*<>\s*''CLIENT_CONTACT''',
      '\1 not in (''CLIENT_CONTACT'',''SERVICE_ACCOUNT'')',
      'g');
    execute format(
      'create or replace function %I(%s) returns %s language %s %s %s '
      'set search_path to ''public'' as %L',
      r.proname, r.args, r.ret, r.lanname,
      case r.provolatile when 's' then 'stable'
                         when 'i' then 'immutable'
                         else '' end,
      case when r.prosecdef then 'security definer' else 'security invoker' end,
      v_src);
    v_n := v_n + 1;
    raise notice '  % now reads a service account as not-staff', r.proname;
  end loop;

  if v_n = 0 then
    raise notice 'no function carries the contact predicate; already widened';
  else
    raise notice '% function(s) widened', v_n;
  end if;
end $widen$;

-- ------------------------------------------------------------- the guard
do $guard$
declare v_id uuid; n int; v_name text;
begin
  select id, full_name into v_id, v_name from person
   where lower(work_email) = 'operations.alert@cruxindia.co.in';
  if v_id is null then
    raise notice 'Migration 243: no service account to check.';
    return;
  end if;

  -- It is in nobody's reporting line, as a person OR as a manager.
  select count(*) into n from person p
   where p.employment_status = 'ACTIVE' and p.superseded_by is null
     and p.id <> v_id
     and exists (select 1 from perf_line(p.id) l where l.person_id = v_id);
  if n > 0 then
    raise exception 'Migration 243: the service account is still inside % '
                    'person(s) reporting line', n;
  end if;

  -- It is in nobody's KPI subtree, so no manager is offered it.
  select count(*) into n from person p
   where p.employment_status = 'ACTIVE' and p.superseded_by is null
     and p.id <> v_id
     and exists (select 1 from kpi_subtree_people(p.id) s where s.person_id = v_id);
  if n > 0 then
    raise exception 'Migration 243: the service account is still offered to % '
                    'person(s) as somebody to set measures for', n;
  end if;

  -- And it is out of the headcount.
  select count(*) into n from person
   where employment_status = 'ACTIVE' and superseded_by is null
     and coalesce(employee_type,'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT');
  raise notice 'headcount is now % people', n;
  if n < 90 or n > 200 then
    raise exception 'Migration 243: headcount is %, which is not a company', n;
  end if;

  -- But it can still administer the tool. This is the half that must NOT
  -- have changed: the account signs in, holds ADMIN, and perf_rel still
  -- answers 'admin' for it over everybody.
  if not exists (select 1 from person
                  where id = v_id and app_role = 'ADMIN'
                    and employment_status = 'ACTIVE' and superseded_by is null) then
    raise exception 'Migration 243: the service account lost its ADMIN role';
  end if;
  select count(*) into n from person p
   where p.employment_status = 'ACTIVE' and p.superseded_by is null
     and p.id <> v_id
     and perf_rel(v_id, p.id) is distinct from 'admin';
  if n > 0 then
    raise exception 'Migration 243: the service account no longer reads as '
                    'administrator over % person/people', n;
  end if;

  raise notice '% is out of the staff list and still administers the tool', v_name;
end $guard$;
