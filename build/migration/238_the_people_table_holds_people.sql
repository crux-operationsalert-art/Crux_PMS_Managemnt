-- The people table holds people (238)
--
-- 531 of the 633 active rows in `person` are not employees. They are the
-- contacts at the client banks -- Bank of Maharashtra 208, IDBI 120, SBI 106,
-- SVC 43, Axis 25, LIC Housing 20 -- and every one of them is already held
-- properly in branch_contact, which is the table for exactly this.
--
-- They arrived through a bulk upload that did not distinguish "somebody we
-- write to" from "somebody who works here", and the cost is not storage. It
-- is that 84% of the staff list is not staff: every people picker, every
-- count of headcount, and every list an administrator opens is mostly bank
-- managers. It is also why "the data looks like it is leaking" was a
-- reasonable thing to think when looking at the people screen.
--
-- Before writing anything, each of these was checked to be referenced by
-- nothing: no KPI, no goal sheet, no filing, no session, nobody reporting to
-- them, and no message ever sent to them. All seven counts were zero.
--
-- This sets employment_status to INACTIVE. It does not delete a row, so
-- nothing that might yet point at one breaks, the branch_contact record they
-- duplicate is untouched, and the way back is one statement, printed at the
-- foot of this file.
--
-- The test for "is this a person or a contact" is deliberately four things at
-- once rather than the e-mail domain alone: no employee number, no chair, a
-- non-company address, AND already present in branch_contact. An employee on
-- a personal gmail address -- of whom there are 56 -- fails the last test and
-- is left alone.

do $bank$
declare n_found int; n_done int;
begin
  create temporary table _bank_contacts on commit drop as
  select p.id, p.full_name, p.work_email
    from person p
   where p.employment_status = 'ACTIVE'
     and p.superseded_by is null
     and p.employee_no is null
     and not exists (select 1 from chair_holder h
                      where h.person_id = p.id and h.to_date is null)
     and p.work_email !~* 'cruxindia\.co\.in$'
     and exists (select 1 from branch_contact bc
                  where lower(bc.email) = lower(p.work_email));

  select count(*) into n_found from _bank_contacts;

  -- Nothing may point at any of them. Re-checked here rather than trusted
  -- from the survey, because the survey and the write are different moments.
  if exists (select 1 from perf_assignment a where a.person_id in (select id from _bank_contacts))
     or exists (select 1 from plb_goal_sheet s where s.person_id in (select id from _bank_contacts))
     or exists (select 1 from auth_session x where x.person_id in (select id from _bank_contacts))
     or exists (select 1 from person r where r.manager_id in (select id from _bank_contacts))
     or exists (select 1 from chair_holder h where h.person_id in (select id from _bank_contacts))
  then
    raise exception 'Migration 238: something now references a contact. '
                    'Nothing was changed.';
  end if;

  -- A row on the person's own record, so this is answerable in a year from
  -- the person rather than only from a migration file.
  insert into person_event (person_id, kind, note, at)
  select id, 'DEACTIVATED',
         'Not an employee: a client-bank contact, already held in '
         || 'branch_contact. Set inactive by migration 238.', now()
    from _bank_contacts;

  update person p set employment_status = 'INACTIVE'
   where p.id in (select id from _bank_contacts);
  get diagnostics n_done = row_count;

  insert into audit_entry (actor_id, action, entity_type, entity_ref,
                           old_value, new_value)
  values (null, 'BULK_DEACTIVATED', 'person', 'migration-238',
          jsonb_build_object('status','ACTIVE','count', n_found),
          jsonb_build_object('status','INACTIVE','count', n_done,
            'why','client-bank contacts, not employees'));

  raise notice 'found % contact(s), set % inactive', n_found, n_done;
end $bank$;

do $guard$
declare n_people int; n_left int; n_contacts int;
begin
  -- What must be left: the real staff. 102 at the time of writing, and the
  -- floor is set low enough to survive ordinary joiners and leavers but high
  -- enough to catch this migration having taken the wrong set.
  select count(*) into n_people from person
   where employment_status = 'ACTIVE' and superseded_by is null;
  if n_people < 90 then
    raise exception 'Migration 238 left only % active people. It has '
                    'deactivated employees.', n_people;
  end if;
  if n_people > 200 then
    raise exception 'Migration 238 left % active people, so it did not do '
                    'its job.', n_people;
  end if;

  -- Everybody holding a chair must still be active. A chair holder is by
  -- definition somebody who works here.
  select count(*) into n_left from chair_holder h
    join person p on p.id = h.person_id
   where h.to_date is null and p.employment_status <> 'ACTIVE';
  if n_left > 0 then
    raise exception 'Migration 238 deactivated % chair holder(s)', n_left;
  end if;

  -- And the contacts themselves are still on file where they belong.
  select count(*) into n_contacts from branch_contact;
  if n_contacts = 0 then
    raise exception 'Migration 238: branch_contact is empty, so the contacts '
                    'have nowhere else to live';
  end if;

  raise notice '% active people left, every chair holder still active, % contacts on file',
    n_people, n_contacts;
end $guard$;

-- ---------------------------------------------------------- the way back
-- If this was wrong, one statement undoes it and the person_event rows say
-- which rows it touched:
--
--   update person set employment_status = 'ACTIVE'
--    where id in (select person_id from person_event
--                  where kind = 'DEACTIVATED'
--                    and note like '%migration 238%');
