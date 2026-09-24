-- "Fix the department and manager columns in the People upload."
--
-- WHAT WAS ACTUALLY WRONG, which is not what the checklist said.
--
-- The headline I wrote after the last round -- 581 people with no department,
-- 533 with no manager -- counted the wrong people. Of the 636 rows in person,
-- 533 are not employees at all. They arrived from the client branch master
-- (source_ref BRANCHES!nnn) and the escalation matrix (MATRIX!nn), they hold
-- no chair, carry no employee number, have no coverage, are VIEWER, and every
-- single one of them has an e-mail at a client: 208 bankofmaharashtra.bank.in,
-- 120 idbi.co.in, 106 sbi.co.in, 43 svcbank.com, 25 axisbank.com, 20
-- lichousing.com and the rest. All 531 of the BRANCHES rows are branch
-- contacts. They are the client's staff, sitting in person because that is
-- where a contact's name had to go.
--
-- Take them out and the real picture is small and precise:
--
--     103 people are staff        (a chair, or an employee number, or a
--                                  cruxindia.co.in address -- two independent
--                                  definitions, source_ref and that one,
--                                  agree on the same 103)
--      48 of them have no department
--       0 of them have no manager
--       6 of them have no employee number yet
--
-- So the two columns fail in two different ways:
--
--   DEPARTMENT is not in the People template at all. Eight columns, none of
--   them department. It can therefore never be set by an upload, and the 48
--   people the People file loaded have none -- every one of them. The 55 who
--   do have one got it at cut-over from the organisation document. Department
--   is what client_view_policy reads to decide whether somebody sees client
--   data at all, so those 48 see none of it and nothing in the tool could
--   have given it to them.
--
--   MANAGER is in the template and works -- all 103 staff have one. What is
--   broken is the rule around it. The column says "Required except for the
--   top chair" and nothing enforced that, so a file could leave the whole
--   column blank and pass. Nothing checked for a loop either: A reports to B
--   and B reports to A passes validation today and leaves the org chart and
--   every manager-subtree walk without a top. And the number is unreadable on
--   its own -- the same complaint that was made about Assignments, "along
--   with the EMP ID I would need the names too".
--
-- WHAT THIS DOES
--
--   1 department joins the template, between chair and reports_to.
--   2 reports_to_name joins it too, ignored on upload, so the line can be read.
--   3 dept_canon() accepts what a person would actually type -- HR, Ops, IT,
--     Sales, "Finance and Accounts" -- and returns the one canonical name, or
--     null for anything that is not a department. It reads client_view_policy,
--     so adding a department there is enough; nothing here needs changing.
--   4 uv_people refuses an unknown department, requires one for anybody new,
--     requires a manager for anybody new who is not on the top chair, and
--     refuses a reporting line that loops.
--   5 ua_people writes department, in both the adopt branch and the insert
--     branch. It did neither before.
--   6 The four departments already recorded that client_view_policy does not
--     recognise are corrected: HR -> Human Resources (2), Finance -> Finance &
--     Accounts (1), Other -> Business Development (1, on the Sales Manager
--     chair under function Commercial). Until now those four silently fell
--     through to view_kind 'none', and the two HR people could not approve a
--     hire because the api compares department against 'Human Resources'.
--   7 The template downloads filled in with all 103 staff -- number, name,
--     chair, department, manager number AND manager name -- so it is corrected
--     rather than authored. Where department is blank the chair suggests one,
--     and every one of the 48 is covered: 47 sit on chairs whose function is
--     Operations, 1 on Finance.
--
-- WHAT THIS DELIBERATELY DOES NOT DO. It does not write those 48 departments
-- into person. Operations resolves to view_kind 'matrix', the widest view
-- there is, and granting 47 people a view of client data is a decision with a
-- name on it, not something a migration should do quietly. The suggestion goes
-- in the file; one upload of the file applies it.
--
-- AND ONE REPAIR IN PASSING. migration 132 moved every coverage rule off the
-- cut-over branches onto the real master, which killed the Assignments seed --
-- its cov CTE reads coverage through link.old_branch, and there is nothing on
-- the old branches any more. It still returns 59 rows and every handler cell
-- in all 59 is now blank, where it filled 21 before the fold. Coverage sits on
-- the real branches now, so the indirection is not needed at all and the seed
-- reads coverage_rule directly.

-- ---------------------------------------------------------------- 1. columns
-- upload_column is keyed on (kind, ord), so the existing columns move out of
-- the way from the bottom up before the two new ones drop in.

update upload_column set ord = 10 where kind='People' and name='employment_type';
update upload_column set ord =  9 where kind='People' and name='date_of_joining';
update upload_column set ord =  7 where kind='People' and name='reports_to_employee_no';

insert into upload_column (kind, ord, name, example, rule) values
  ('People', 6, 'department', 'Operations',
   'Required for anybody new. Leave it blank for somebody already on the '
   'people master and what is recorded today is kept. This is the column that '
   'decides whether a person sees client data at all, and what kind - the '
   'allowed values are listed at the foot of this file.'),
  ('People', 8, 'reports_to_name', 'Shantanu Suravase',
   'Ignored on upload. Here so you can read the reporting line.');

update upload_column
   set rule = 'Required for anybody new, except on the top chair. Leave it '
              'blank for somebody already on the people master and their '
              'current manager is kept. May name someone created by this same '
              'file. A line that loops back on itself is refused.'
 where kind='People' and name='reports_to_employee_no';

-- -------------------------------------------------------------- 2. the names
-- One place that knows what a department is called. It reads the policy table
-- rather than a list written here, so a department added under Configuration
-- is understood by the upload the moment it exists. The aliases are the things
-- a person types; everything else is compared with spacing, punctuation and
-- "and" versus "&" ignored, so "finance and accounts" and "Finance & Accounts"
-- are the same answer.

create or replace function dept_canon(p_text text)
returns text language sql stable set search_path = public as $$
  with k as (
    select regexp_replace(
             regexp_replace(lower(btrim(coalesce(p_text,''))), '\s+and\s+', ' & ', 'g'),
             '[^a-z]', '', 'g') as key
  ), want as (
    select case (select key from k)
             when 'hr'         then 'humanresources'
             when 'humanresource' then 'humanresources'
             when 'people'     then 'humanresources'
             when 'ops'        then 'operations'
             when 'bd'         then 'businessdevelopment'
             when 'sales'      then 'businessdevelopment'
             when 'it'         then 'technology'
             when 'tech'       then 'technology'
             when 'finance'    then 'financeaccounts'
             when 'accounts'   then 'financeaccounts'
             when 'compliance' then 'complianceassurance'
             when 'assurance'  then 'complianceassurance'
             else (select key from k)
           end as key
  )
  select d.department
    from client_view_policy d, want w
   where w.key <> ''
     and regexp_replace(
           regexp_replace(lower(d.department), '\s+and\s+', ' & ', 'g'),
           '[^a-z]', '', 'g') = w.key
   limit 1;
$$;
comment on function dept_canon(text) is
  'The one canonical department name for whatever was typed, or null if it is '
  'not a department. Reads client_view_policy, so the allowed set is whatever '
  'Configuration says it is.';

-- The chair can suggest a department, and for the 48 people who have none it
-- suggests one for every single one of them. Only the functions that mean
-- exactly one department are mapped. "Assurance & People" is deliberately
-- absent because it splits two ways -- Compliance & Assurance sees client
-- contacts, Human Resources sees none, and guessing between them either leaks
-- or blocks. "Executive" is absent because it spans the company.
create or replace function dept_from_chair(p_person uuid)
returns text language sql stable set search_path = public as $$
  select dept_canon(case c.function_name
                      when 'Operations' then 'Operations'
                      when 'Finance'    then 'Finance & Accounts'
                      when 'Commercial' then 'Business Development'
                      when 'MIS'        then 'MIS'
                      when 'Technology' then 'Technology'
                      else null end)
    from chair_holder h
    join chair c on c.id = h.chair_id
   where h.person_id = p_person and h.to_date is null
   order by h.is_primary desc, h.from_date
   limit 1;
$$;

-- Who counts as staff. The client's own branch contacts live in person too --
-- 533 of them -- and they must never appear in a staff template. A person is
-- staff if they hold a chair, or carry an employee number, or are at the
-- company's own domain. That gives 103, and source_ref gives the same 103.
create or replace function is_staff(p_person uuid)
returns boolean language sql stable set search_path = public as $$
  select exists (
    select 1 from person p
     where p.id = p_person
       and p.superseded_by is null
       and (p.employee_no is not null
            or lower(p.work_email) like '%@cruxindia.co.in'
            or exists (select 1 from chair_holder h
                        where h.person_id = p.id and h.to_date is null)));
$$;

-- ----------------------------------------------------------- 3. the validator
create or replace function uv_people(p_batch uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare v_depts text;
begin
  update upload_row set error = null where batch_id = p_batch and error is not null;

  -- read once rather than per row
  select string_agg(department, ', ' order by department) into v_depts from client_view_policy;

  update upload_row r set error = e.msg from (
    select r2.id, nullif(concat_ws('; ',
      case when ul_txt(r2.raw,'employee_no') is null then 'employee_no is required' end,
      case when ul_txt(r2.raw,'full_name') is null then 'full_name is required' end,
      case when ul_txt(r2.raw,'work_email') is null then 'work_email is required'
           when ul_txt(r2.raw,'work_email') !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$'
           then 'work_email is not a valid address' end,
      case when ul_mobile(ul_txt(r2.raw,'mobile')) is not null
            and ul_mobile(ul_txt(r2.raw,'mobile')) !~ '^[0-9]{10,13}$'
           then 'mobile must be 10 to 13 digits, or left blank' end,
      case when ul_txt(r2.raw,'chair') is null then 'chair is required'
           when not exists (select 1 from chair c
                             where c.title = ul_txt(r2.raw,'chair')
                                or c.code  = ul_txt(r2.raw,'chair'))
           then 'chair ' || ul_txt(r2.raw,'chair') || ' does not exist - load Chairs first' end,

      -- department. Written but not a department at all is always refused.
      -- Left blank is refused only for somebody the master does not already
      -- hold a department for, so a partial file does not have to restate it.
      case when ul_txt(r2.raw,'department') is not null
            and dept_canon(ul_txt(r2.raw,'department')) is null
           then 'department ' || ul_txt(r2.raw,'department') || ' is not one of ' || v_depts end,
      case when ul_txt(r2.raw,'department') is null
            and not exists (select 1 from person p
                             where p.employee_no = ul_txt(r2.raw,'employee_no')
                               and p.superseded_by is null
                               and p.department is not null)
           then 'department is required - it is what decides whether this person '
                'sees client data at all. One of ' || v_depts end,

      -- the reporting line
      case when ul_txt(r2.raw,'reports_to_employee_no') is not null
            and not exists (select 1 from person p where p.employee_no = ul_txt(r2.raw,'reports_to_employee_no')
                              and p.superseded_by is null)
            and not exists (select 1 from upload_row r3 where r3.batch_id = p_batch
                              and ul_txt(r3.raw,'employee_no') = ul_txt(r2.raw,'reports_to_employee_no'))
           then 'reports_to_employee_no ' || ul_txt(r2.raw,'reports_to_employee_no') ||
                ' is neither in this file nor already on the people master' end,
      case when ul_txt(r2.raw,'reports_to_employee_no') = ul_txt(r2.raw,'employee_no')
           then 'a person cannot report to themselves' end,
      case when ul_txt(r2.raw,'reports_to_employee_no') is null
            and not exists (select 1 from chair c
                             where (c.title = ul_txt(r2.raw,'chair') or c.code = ul_txt(r2.raw,'chair'))
                               and c.parent_id is null)
            and not exists (select 1 from person p
                             where p.employee_no = ul_txt(r2.raw,'employee_no')
                               and p.superseded_by is null
                               and p.manager_id is not null)
           then 'reports_to_employee_no is required - a manager sees their team''s '
                'work through it, and nobody sees this person''s work without it. '
                'Only the top chair may leave it blank' end,

      case when ul_txt(r2.raw,'date_of_joining') is not null
            and not is_ymd(ul_txt(r2.raw,'date_of_joining'))
           then 'date_of_joining must be a real date, written YYYY-MM-DD' end,
      case when lower(coalesce(ul_txt(r2.raw,'employment_type'),'employee'))
                not in ('employee','partner','intern','contract')
           then 'employment_type must be Employee, Partner, Intern or Contract' end
    ), '') as msg
    from upload_row r2 where r2.batch_id = p_batch
  ) e where r.id = e.id and e.msg is not null;

  update upload_row r set error = coalesce(r.error || '; ', '') || 'duplicate employee_no in this file'
    from (select id, row_number() over (partition by lower(ul_txt(raw,'employee_no')) order by row_no) rn
            from upload_row where batch_id = p_batch and error is null) d
   where r.id = d.id and d.rn > 1;

  update upload_row r set error = coalesce(r.error || '; ', '') || 'duplicate work_email in this file'
    from (select id, row_number() over (partition by lower(ul_txt(raw,'work_email')) order by row_no) rn
            from upload_row where batch_id = p_batch and error is null) d
   where r.id = d.id and d.rn > 1;

  -- One mobile, two rows. Almost always the same human entered twice under two
  -- employee numbers, so the message names the other row rather than just
  -- saying "duplicate" -- that is the bit you need to decide which one to keep.
  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'mobile ' || d.mob || ' is also on line ' || d.other_row ||
         ', ' || d.other_name || ' (' || d.other_emp || ')' ||
         ' - if that is the same person, delete one of the two lines'
    from (
      select r2.id,
             ul_mobile(ul_txt(r2.raw,'mobile')) mob,
             min(r3.row_no) other_row,
             min(ul_txt(r3.raw,'full_name')) other_name,
             min(ul_txt(r3.raw,'employee_no')) other_emp
        from upload_row r2
        join upload_row r3
          on r3.batch_id = r2.batch_id and r3.id <> r2.id and r3.error is null
         and ul_mobile(ul_txt(r3.raw,'mobile')) = ul_mobile(ul_txt(r2.raw,'mobile'))
       where r2.batch_id = p_batch and r2.error is null
         and ul_mobile(ul_txt(r2.raw,'mobile')) is not null
       group by r2.id, ul_mobile(ul_txt(r2.raw,'mobile'))
    ) d
   where r.id = d.id;

  -- The address is somebody else's only if that somebody already has a
  -- different employee number. One with none is this same person, already on
  -- the master from the org document, about to be given a number.
  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'work_email already belongs to ' || p.full_name ||
         ' (' || p.employee_no || '), who is a different person'
    from upload_row r2
    join person p on lower(btrim(p.work_email)) = lower(btrim(ul_txt(r2.raw,'work_email')))
                 and p.superseded_by is null
   where r.id = r2.id and r2.batch_id = p_batch and r2.error is null
     and p.employee_no is not null
     and p.employee_no <> ul_txt(r2.raw,'employee_no');

  -- and the same for the mobile, against everybody who has not left
  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'mobile ' || ul_mobile(ul_txt(r2.raw,'mobile')) || ' already belongs to ' ||
         p.full_name || ' (' || p.employee_no || '), who is a different person'
    from upload_row r2
    join person p on p.mobile = ul_mobile(ul_txt(r2.raw,'mobile')) and p.left_on is null
   where r.id = r2.id and r2.batch_id = p_batch and r2.error is null
     and p.employee_no is not null
     and p.employee_no <> ul_txt(r2.raw,'employee_no');

  -- A reporting line that loops has no top, so the org chart never finishes
  -- drawing and no manager's subtree ever resolves. The file can make a loop
  -- by itself -- A reports to B, B reports to A -- or by joining onto the
  -- master, where B already reports to A. Both are found by walking the line
  -- upward from every row in the file, reading the file wherever the file
  -- names that person and the master everywhere else, which is exactly the
  -- picture that would exist after apply.
  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'the reporting line from ' || ul_txt(r.raw,'employee_no') ||
         ' comes back round to ' || ul_txt(r.raw,'employee_no') ||
         ' - somebody in that chain has the wrong manager'
    from (
      with recursive edge as (
        select ul_txt(x.raw,'employee_no') emp, ul_txt(x.raw,'reports_to_employee_no') mgr
          from upload_row x
         where x.batch_id = p_batch and ul_txt(x.raw,'employee_no') is not null
        union
        select p.employee_no, m.employee_no
          from person p join person m on m.id = p.manager_id
         where p.superseded_by is null and m.superseded_by is null
           and p.employee_no is not null and m.employee_no is not null
           and not exists (select 1 from upload_row x2 where x2.batch_id = p_batch
                             and ul_txt(x2.raw,'employee_no') = p.employee_no)
      ), walk as (
        select e.emp as start_emp, e.mgr as at, 1 as depth
          from edge e
         where e.mgr is not null
           and exists (select 1 from upload_row x3 where x3.batch_id = p_batch
                         and ul_txt(x3.raw,'employee_no') = e.emp)
        union all
        select w.start_emp, e.mgr, w.depth + 1
          from walk w join edge e on e.emp = w.at
         where e.mgr is not null and w.depth < 60 and w.at <> w.start_emp
      )
      select distinct start_emp from walk where at = start_emp
    ) c
   where r.batch_id = p_batch and r.error is null
     and ul_txt(r.raw,'employee_no') = c.start_emp;

  -- The near-duplicate domain check. A misspelt domain is one edit away from
  -- the one everybody else uses, and it is how the old system ended up with a
  -- second person holding 583 coverage rows.
  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'work_email domain ' || split_part(ul_txt(r.raw,'work_email'),'@',2) ||
         ' looks like a misspelling of ' || m.common_domain ||
         ' - correct it, or load it alone if it is genuinely a different domain'
    from (
      select (select lower(split_part(ul_txt(x.raw,'work_email'),'@',2)) as d
                from upload_row x where x.batch_id = p_batch and x.error is null
               group by 1 order by count(*) desc, 1 limit 1) as common_domain
    ) m
   where r.batch_id = p_batch and r.error is null
     and m.common_domain is not null
     and lower(split_part(ul_txt(r.raw,'work_email'),'@',2)) <> m.common_domain
     and extensions.levenshtein(lower(split_part(ul_txt(r.raw,'work_email'),'@',2)), m.common_domain) between 1 and 2;
end $$;

-- ------------------------------------------------------------- 4. the applier
create or replace function ua_people(p_batch uuid, p_actor uuid)
returns void language plpgsql set search_path = public as $$
declare v_adopted int := 0;
begin
  -- 1 - Adopt. Somebody already here by address, with no employee number, is
  --     this person. Give them the number and the rest of the file's detail
  --     rather than inserting a second row that the unique index would refuse
  --     anyway. This is what the org-document load left for People to finish.
  --     A blank department keeps what is recorded; it never clears it.
  update person p set
      employee_no   = ul_txt(r.raw,'employee_no'),
      full_name     = ul_txt(r.raw,'full_name'),
      mobile        = coalesce(ul_mobile(ul_txt(r.raw,'mobile')), p.mobile),
      department    = coalesce(dept_canon(ul_txt(r.raw,'department')), p.department),
      employee_type = upper(coalesce(ul_txt(r.raw,'employment_type'),'EMPLOYEE')),
      joined_on     = coalesce(ul_txt(r.raw,'date_of_joining')::date, p.joined_on),
      source_ref    = coalesce(p.source_ref, 'bulk upload'),
      updated_at    = now()
    from upload_row r
   where r.batch_id = p_batch
     and lower(btrim(p.work_email)) = lower(btrim(ul_txt(r.raw,'work_email')))
     and p.superseded_by is null
     and p.employee_no is null;
  get diagnostics v_adopted = row_count;

  -- 2 - Everybody else, by employee number.
  insert into person (employee_no, full_name, work_email, mobile, department,
                      employment_status, employee_type, joined_on, app_role, source_ref)
  select ul_txt(raw,'employee_no'),
         ul_txt(raw,'full_name'),
         lower(ul_txt(raw,'work_email')),
         ul_mobile(ul_txt(raw,'mobile')),
         dept_canon(ul_txt(raw,'department')),
         'ACTIVE',
         upper(coalesce(ul_txt(raw,'employment_type'),'EMPLOYEE')),
         ul_txt(raw,'date_of_joining')::date,
         'VIEWER',
         'bulk upload'
    from upload_row where batch_id = p_batch
  on conflict (employee_no) where employee_no is not null do update
    set full_name = excluded.full_name, work_email = excluded.work_email,
        mobile = coalesce(excluded.mobile, person.mobile),
        department = coalesce(excluded.department, person.department),
        employee_type = excluded.employee_type,
        joined_on = excluded.joined_on, updated_at = now();

  -- managers second, so a person can report to someone created by this file.
  -- A blank column leaves the manager alone rather than clearing it, because
  -- the join simply does not match.
  update person p set manager_id = m.id
    from upload_row r join person m on m.employee_no = ul_txt(r.raw,'reports_to_employee_no')
                                   and m.superseded_by is null
   where r.batch_id = p_batch and p.employee_no = ul_txt(r.raw,'employee_no')
     and p.superseded_by is null
     and p.manager_id is distinct from m.id;

  -- seat each person in their chair; an existing seat is vacated first so a
  -- move shows as a move rather than two people holding one chair
  update chair_holder ch set to_date = current_date
    from upload_row r
    join person p on p.employee_no = ul_txt(r.raw,'employee_no')
   where r.batch_id = p_batch and ch.person_id = p.id and ch.to_date is null
     and ch.chair_id <> (select c.id from chair c
                          where c.title = ul_txt(r.raw,'chair') or c.code = ul_txt(r.raw,'chair') limit 1);

  insert into chair_holder (chair_id, person_id, is_primary, from_date)
  select c.id, p.id,
         not exists (select 1 from chair_holder x
                      where x.person_id = p.id and x.is_primary and x.to_date is null),
         coalesce(ul_txt(r.raw,'date_of_joining')::date, current_date)
    from upload_row r
    join person p on p.employee_no = ul_txt(r.raw,'employee_no')
    join lateral (select c2.id from chair c2
                   where c2.title = ul_txt(r.raw,'chair') or c2.code = ul_txt(r.raw,'chair')
                   limit 1) c on true
   where r.batch_id = p_batch
     and not exists (select 1 from chair_holder x
                      where x.person_id = p.id and x.chair_id = c.id and x.to_date is null);

  -- a person loaded without a mobile is a question for HR, not a blocker
  insert into migration_review (entity_type, entity_ref, question, context)
  select 'person', 'UPLOAD!' || ul_txt(r.raw,'employee_no'),
         'What is the mobile number for ' || ul_txt(r.raw,'full_name') || '?',
         'Loaded without one. Sign-in by OTP needs it where there is no Google account.'
    from upload_row r
   where r.batch_id = p_batch
     and ul_mobile(ul_txt(r.raw,'mobile')) is null
     and not exists (select 1 from migration_review x
                      where x.entity_type = 'person'
                        and x.entity_ref = 'UPLOAD!' || ul_txt(r.raw,'employee_no'));

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'PEOPLE_UPLOADED', 'upload_batch', p_batch::text,
          jsonb_build_object('adopted_existing', v_adopted));
end $$;

-- ---------------------------------------------- 5. correct what is on record
-- Four people carry a department client_view_policy has never heard of, so all
-- four fall through to view_kind 'none' and see nothing. Two of them are the
-- HR pair, and the api compares department against the exact string
-- 'Human Resources' before it will let anybody approve a hire -- so Crux has
-- had two HR people and no one who could approve a hire.
--
--   HR      -> Human Resources    EMP-0088 P P Valsan (Head - HR Operations)
--                                 EMP-0089 Arti Sonawane (HR Executive)
--   Finance -> Finance & Accounts EMP-0090 Sneha Radhe (Vice President,
--                                 chair function Finance)
--
-- Both are handled by dept_canon, which knows those two as aliases.
update person p
   set department = dept_canon(p.department), updated_at = now()
 where p.superseded_by is null
   and p.department is not null
   and dept_canon(p.department) is not null
   and dept_canon(p.department) <> p.department;

-- "Other" is not an alias of anything, so it is named on its own. The one
-- person holding it is EMP-0087 Anuja Adhali on the Sales Manager chair, whose
-- function is Commercial; Business Development is the only department in the
-- policy that means selling.
update person p
   set department = 'Business Development', updated_at = now()
  from chair_holder h
  join chair c on c.id = h.chair_id
 where h.person_id = p.id and h.to_date is null
   and p.superseded_by is null
   and p.department = 'Other'
   and c.function_name = 'Commercial';

-- Nothing is written for the 48 with no department. Operations resolves to
-- view_kind 'matrix', the widest view there is, and handing 47 people a view
-- of client data is a decision with a name on it. The suggestion goes in the
-- template instead; one upload of that file applies all 48.

do $$
declare v_bad int;
begin
  select count(*) into v_bad
    from person p
   where p.superseded_by is null
     and p.department is not null
     and not exists (select 1 from client_view_policy d where d.department = p.department);
  if v_bad <> 0 then
    raise exception '% people still carry a department the policy does not know', v_bad;
  end if;
end $$;

-- -------------------------------------------------------------- 6. the seeds
-- upload_seed grew a second kind, so it stops being one query with a
-- "where p_kind = ..." on the end and becomes a dispatch.
create or replace function upload_seed(p_kind text)
returns table(ord int, line text)
language plpgsql stable security definer set search_path = public as $$
begin

  -- ASSIGNMENTS. Every client that has a branch at an operating location, with
  -- whoever covers most of that client's branches there today.
  --
  -- This used to reach coverage through branch_generation_map's ancestor -- a
  -- name match from the cut-over branches to the uploaded ones -- because that
  -- was where the coverage was. migration 132 moved all 1,123 rules onto the
  -- real master, which left that path reading an empty set: the seed still
  -- produced 59 rows and every handler cell in all 59 came out blank, where it
  -- had filled 21 before the fold. Coverage sits on the branches themselves
  -- now, so it is read from there.
  if p_kind = 'Assignments' then
    return query
    with cov as (
      -- branch-level rules only; a client-level or zone-level rule names no
      -- branch, so it cannot say which location it belongs to
      select b.client_id, b.op_node_id, cr.person_id,
             row_number() over (partition by b.client_id, b.op_node_id
                                order by count(*) desc, min(cr.created_at)) rn
        from coverage_rule cr
        join branch b on b.id = cr.branch_id
       where cr.effective_to is null and b.op_node_id is not null
       group by b.client_id, b.op_node_id, cr.person_id
    ), have as (
      select distinct b.client_id, b.op_node_id
        from branch b join client c on c.id = b.client_id
       where b.op_node_id is not null and c.status = 'ACTIVE'
    )
    select row_number() over (order by c.code, o.name)::int,
           concat_ws(',',
             csv_cell(c.code), csv_cell(o.name), csv_cell(''),
             csv_cell(coalesce(h.employee_no,'')), csv_cell(coalesce(h.full_name,'')),
             csv_cell(coalesce(m.employee_no,'')), csv_cell(coalesce(m.full_name,'')),
             csv_cell(to_char(date_trunc('month', current_date), 'YYYY-MM-DD')), csv_cell(''))
      from have
      join client  c on c.id = have.client_id
      join op_node o on o.id = have.op_node_id and o.active
      left join cov    on cov.client_id = have.client_id
                      and cov.op_node_id = have.op_node_id and cov.rn = 1
      left join person h on h.id = cov.person_id
      left join person m on m.id = h.manager_id
     order by c.code, o.name;

  -- PEOPLE. Everybody on the staff, as the tool holds them now, so the file is
  -- corrected rather than authored. The client's own branch contacts live in
  -- person as well -- 533 of them, every one at a client's domain -- and they
  -- are not staff, so is_staff keeps them out.
  --
  -- Two columns carry a suggestion rather than a fact. A blank department
  -- takes one from the chair where the chair means exactly one department,
  -- which covers all 48 of the people who have none. Six people have no
  -- employee number yet, so their first cell comes down blank on purpose --
  -- fill it and the file loads; leave it and it will not, which is the point.
  elsif p_kind = 'People' then
    return query
    select row_number() over (order by coalesce(p.employee_no,'ZZZZ'), p.full_name)::int,
           concat_ws(',',
             csv_cell(coalesce(p.employee_no,'')),
             csv_cell(p.full_name),
             csv_cell(coalesce(p.work_email,'')),
             csv_cell(coalesce(p.mobile,'')),
             csv_cell(coalesce(ch.title,'')),
             csv_cell(coalesce(p.department, dept_from_chair(p.id), '')),
             csv_cell(coalesce(m.employee_no,'')),
             csv_cell(coalesce(m.full_name,'')),
             csv_cell(coalesce(to_char(p.joined_on,'YYYY-MM-DD'),'')),
             csv_cell(initcap(lower(coalesce(p.employee_type::text,'EMPLOYEE')))))
      from person p
      left join lateral (
             select c.title from chair_holder h join chair c on c.id = h.chair_id
              where h.person_id = p.id and h.to_date is null
              order by h.is_primary desc, h.from_date limit 1) ch on true
      left join person m on m.id = p.manager_id
     where p.superseded_by is null
       and p.employment_status = 'ACTIVE'
       and is_staff(p.id)
     order by coalesce(p.employee_no,'ZZZZ'), p.full_name;
  end if;
end $$;

-- ---------------------------------------------------- 7. the key at the foot
create or replace function upload_key(p_kind text)
returns table(ord int, line text)
language sql stable security definer set search_path = public as $$
  select 1, 'YOUR LOCATIONS - the location column must be one of these'
   where p_kind = 'Assignments'
  union all
  select 2 + (row_number() over (order by l.name))::int,
         concat_ws(',', csv_cell(l.name), csv_cell(coalesce(z.name,'')))
    from op_node l left join op_node z on z.id = l.parent_id
   where p_kind = 'Assignments' and l.level = 'LOCATION' and l.active
  union all
  select 500, '' where p_kind = 'Assignments'
  union all
  select 501, 'WHO HOLDS A CHAIR - any of these can be a handler or a location head'
   where p_kind = 'Assignments'
  union all
  select 502 + (row_number() over (order by p.employee_no))::int,
         concat_ws(',', csv_cell(p.employee_no), csv_cell(p.full_name), csv_cell(ch.title))
    from person p
    join chair_holder h on h.person_id = p.id and h.to_date is null
    join chair ch on ch.id = h.chair_id
   where p_kind = 'Assignments' and p.employee_no is not null
     and p.employment_status = 'ACTIVE'

  -- People
  union all
  select 1, 'YOUR DEPARTMENTS - the department column must be one of these, and '
            'what each one is allowed to see of a client'
   where p_kind = 'People'
  union all
  select 2 + (row_number() over (order by d.department))::int,
         concat_ws(',', csv_cell(d.department), csv_cell(
           case d.view_kind
             when 'matrix'   then 'The full escalation matrix, for the clients they cover'
             when 'contacts' then 'Client and branch contacts only, for the clients they cover'
             else 'No client data at all' end))
    from client_view_policy d
   where p_kind = 'People'
  union all
  select 500, '' where p_kind = 'People'
  union all
  select 501, 'YOUR CHAIRS - the chair column must be one of these, either the code or the title'
   where p_kind = 'People'
  union all
  select 502 + (row_number() over (order by c.code))::int,
         concat_ws(',', csv_cell(c.code), csv_cell(c.title), csv_cell(coalesce(c.function_name,'')))
    from chair c
   where p_kind = 'People';
$$;

-- Where a filled-in value came from, per kind. This used to be written into
-- upload_template as nine hardcoded lines naming Assignments' own columns, so
-- every other kind would have described itself using the wrong ones.
create or replace function upload_provenance(p_kind text)
returns table(ord int, line text)
language sql stable security definer set search_path = public as $$
  select 1, csv_cell('client_code and location') || ',' ||
            csv_cell('Every client with at least one branch at that location. Fact, not a guess.')
   where p_kind = 'Assignments'
  union all
  select 2, csv_cell('handler_employee_no') || ',' ||
            csv_cell('Whoever covers most of that client''s branches there today. A suggestion - check it.')
   where p_kind = 'Assignments'
  union all
  select 3, csv_cell('location_head_employee_no') || ',' ||
            csv_cell('Who that handler reports to on the People file. A weak suggestion - correct it first.')
   where p_kind = 'Assignments'
  union all
  select 4, csv_cell('a blank handler') || ',' ||
            csv_cell('The tool has no basis for a suggestion. Look the number up in the key below.')
   where p_kind = 'Assignments'

  union all
  select 1, csv_cell('everything except department') || ',' ||
            csv_cell('What the tool holds for that person today. Fact, not a guess.')
   where p_kind = 'People'
  union all
  select 2, csv_cell('department, where it was already set') || ',' ||
            csv_cell('What the tool holds. Fact.')
   where p_kind = 'People'
  union all
  select 3, csv_cell('department, where it was blank') || ',' ||
            csv_cell('Taken from the chair, where the chair means exactly one department. '
                     'A suggestion - it has never been confirmed by anyone, and it decides '
                     'what this person can see. Check every one.')
   where p_kind = 'People'
  union all
  select 4, csv_cell('a blank department') || ',' ||
            csv_cell('The chair spans more than one department, so the tool will not guess. Fill it in.')
   where p_kind = 'People'
  union all
  select 5, csv_cell('a blank employee_no') || ',' ||
            csv_cell('That person has never been given one. The file will not load until you do - '
                     'that is deliberate, it is the only way they can be told apart.')
   where p_kind = 'People'
  union all
  select 6, csv_cell('reports_to_name') || ',' ||
            csv_cell('Ignored on upload. It is there so you can read the reporting line '
                     'without looking every number up.')
   where p_kind = 'People';
$$;

-- ---------------------------------------------------------- 8. the template
create or replace function upload_template(p_kind text)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_csv text; v_seeded boolean; v_keyed boolean; v_prov boolean;
begin
  if not exists (select 1 from upload_column where kind = p_kind) then return null; end if;
  select exists (select 1 from upload_seed(p_kind))       into v_seeded;
  select exists (select 1 from upload_key(p_kind))        into v_keyed;
  select exists (select 1 from upload_provenance(p_kind)) into v_prov;

  select string_agg(line, E'\n' order by ord) into v_csv from (
    select 0 as ord, 'Crux bulk upload template,' || csv_cell(p_kind) as line
    union all select 1, case when v_seeded
      then 'The rows below are filled in from what the tool already knows. Check '
           'them, correct them, and add anything missing.'
      else 'Row below the header is an example - delete it before uploading.' end
    union all select 2, 'A file with any error applies zero rows.'
    union all select 3, ''
    union all select 4, (select string_agg(csv_cell(name), ',' order by ord)
                           from upload_column where kind = p_kind)
    union all select 5 + s.ord, s.line from upload_seed(p_kind) s where v_seeded
    union all select 5, (select string_agg(csv_cell(example), ',' order by ord)
                           from upload_column where kind = p_kind) where not v_seeded
    union all select 1000000, ''
    union all select 1000001, 'NOTES'
    union all select 1000002, (select string_agg(csv_cell(name) || ',' || csv_cell(rule), E'\n' order by ord)
                                 from upload_column where kind = p_kind)
    union all select 1000003, '' where v_prov
    union all select 1000004, 'WHERE THE FILLED-IN VALUES CAME FROM' where v_prov
    union all select 1000004 + v.ord, v.line from upload_provenance(p_kind) v where v_prov
    union all select 2000000, '' where v_keyed
    union all select 2000000 + k.ord, k.line from upload_key(p_kind) k where v_keyed
  ) s;

  -- U+FEFF. Without it Excel opens the file as ANSI and every accented
  -- character, rupee sign and dash in it turns to mojibake.
  return E'﻿' || v_csv;
end $$;

-- ------------------------------------------- 9. the reporting line had no top
-- Found by the new cycle check, on the very first dry run of the seeded People
-- file -- and it is in person today, not in the file:
--
--   EMP-0001 Virendra Pal   (Chief Executive Officer / Managing Director)
--            reports to EMP-0002
--   EMP-0002 Arun Bodupali  (Managing Director)
--            reports to EMP-0001
--
-- Two people at the top of the company reporting to each other. The reporting
-- line therefore has no top at all, so every walk up it -- the org chart, a
-- manager's subtree, the scope resolution that decides who may see whose work
-- -- either runs to its depth limit or never terminates. Nothing had ever
-- checked for this, because nothing ever looked past "a person cannot report
-- to themselves".
--
-- The chair tree does not settle it on its own: MD sits under Board of
-- Directors at level 'board', CEO_MD sits under Chairperson - Board of
-- Directors at level 'function', and neither is under the other. What it does
-- say is that one of the two is a board seat and the other is an executive
-- seat, and a board seat is not below an executive one. So the edge removed is
-- the one pointing from the board seat down into the executive seat: Arun
-- Bodupali, Managing Director, becomes the top of the line and reports to
-- nobody. Virendra Pal's line is untouched.
--
-- One edge, the minimum that breaks the loop -- and it names two real people,
-- so it also goes to the review queue for the owner to confirm or reverse
-- rather than being quietly settled here.

update person p
   set manager_id = null, updated_at = now()
  from person m
 where p.employee_no = 'EMP-0002'
   and m.id = p.manager_id
   and m.employee_no = 'EMP-0001'
   and p.superseded_by is null;

insert into migration_review (entity_type, entity_ref, question, context)
select 'person', 'EMP-0002',
       'Who is at the top of the reporting line - Arun Bodupali or Virendra Pal?',
       'The two were recorded reporting to each other, which left the org chart '
       'with no top. Arun Bodupali (Managing Director, a board seat) is now the '
       'top and Virendra Pal (Chief Executive Officer / Managing Director) '
       'reports to him. If it is the other way round, swap the two on the '
       'People file - it will be refused if it makes a loop again.'
 where not exists (select 1 from migration_review x
                    where x.entity_type = 'person' and x.entity_ref = 'EMP-0002');

do $$
declare v_loops int;
begin
  with recursive edge as (
    select p.employee_no emp, m.employee_no mgr
      from person p join person m on m.id = p.manager_id
     where p.superseded_by is null and m.superseded_by is null
       and p.employee_no is not null and m.employee_no is not null
  ), walk as (
    select e.emp start_emp, e.mgr at, 1 depth from edge e where e.mgr is not null
    union all
    select w.start_emp, e.mgr, w.depth + 1
      from walk w join edge e on e.emp = w.at
     where e.mgr is not null and w.depth < 60 and w.at <> w.start_emp
  )
  select count(distinct start_emp) into v_loops from walk where at = start_emp;
  if v_loops <> 0 then
    raise exception '% people are still on a reporting line that loops', v_loops;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- APPLIED 2026-09-24, in five parts, because one tool call carries one
-- migration and this is five separable pieces of work:
--
--   139a_people_template_learns_department        columns, dept_canon,
--                                                 dept_from_chair, is_staff
--   139b_people_validation_and_apply_carry_department
--   139c_four_departments_the_policy_never_knew   the 4 repairs
--   139d_people_template_comes_down_filled_in     seed, key, provenance,
--                                                 template
--   139e_the_reporting_line_had_no_top            the EMP-0001/EMP-0002 loop
--
-- VERIFIED, in this order:
--
--   * the template's columns come back employee_no, full_name, work_email,
--     mobile, chair, department, reports_to_employee_no, reports_to_name,
--     date_of_joining, employment_type -- the two new ones in place and the
--     old ones intact.
--   * dept_canon answers on every shape that matters: HR -> Human Resources,
--     "finance and accounts" -> Finance & Accounts, ops -> Operations,
--     "  Technology " -> Technology, and null for Other, for '' and for null.
--   * the four wrong departments are gone. Every department on the staff now
--     matches a client_view_policy row: Operations 51, Human Resources 2,
--     Finance & Accounts 1, Business Development 1, and 48 still to be set.
--   * the People seed returns 103 rows -- the staff, none of the 533 client
--     branch contacts. Department filled on all 103, manager number AND
--     manager name filled on all 103, 6 employee numbers blank on purpose,
--     1 chair blank (the operations.alert admin account, which holds none).
--   * the Assignments seed fills 21 of 59 handlers again, the same 21 it
--     filled before migration 132 broke it -- now read from the real branches.
--   * the whole seeded file was staged through upload_stage and validated for
--     real: 103 rows, 95 ok, 8 refused. Zero department errors, zero
--     "manager is required" errors -- and the 8 are exactly the 6 people with
--     no employee number and the 2 ends of the reporting loop, which is the
--     new check finding a fault nobody knew was there. The dry-run batch was
--     cancelled; nothing was applied.
