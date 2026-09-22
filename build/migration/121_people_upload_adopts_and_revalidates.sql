-- People upload: adopt who is already here, and let validation run twice.
--
-- Two faults, both found when 49 of 97 rows came back "work_email already
-- belongs to another person" against a file with no duplicates in it.
--
--  1 · Those 49 were the same people, already on the master from the
--      organisation document with no employee number yet. The refusal compared
--      the file's employee number against a NULL, which is never equal, so
--      every one of them looked like a stranger holding the address. An address
--      already here with no employee number is this person, about to be given
--      one -- so uv_people only refuses when the sitting person has a DIFFERENT
--      number, and ua_people adopts the row instead of inserting a second one.
--
--  2 · uv_people only ever added to upload_row.error, never cleared it. A batch
--      refused under an old rule stayed refused after the rule was corrected,
--      because re-validating could not take an error back. It now clears first,
--      then judges, so validation is repeatable.
--
-- Also removes a block that ended `and false` -- an employee number arriving
-- against a new address is an address change, which is allowed, so the block
-- could never fire and only confused the next reader.

create or replace function uv_people(p_batch uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  update upload_row set error = null where batch_id = p_batch and error is not null;

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
      case when ul_txt(r2.raw,'reports_to_employee_no') is not null
            and not exists (select 1 from person p where p.employee_no = ul_txt(r2.raw,'reports_to_employee_no'))
            and not exists (select 1 from upload_row r3 where r3.batch_id = p_batch
                              and ul_txt(r3.raw,'employee_no') = ul_txt(r2.raw,'reports_to_employee_no'))
           then 'reports_to_employee_no ' || ul_txt(r2.raw,'reports_to_employee_no') ||
                ' is neither in this file nor already on the people master' end,
      case when ul_txt(r2.raw,'reports_to_employee_no') = ul_txt(r2.raw,'employee_no')
           then 'a person cannot report to themselves' end,
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

create or replace function ua_people(p_batch uuid, p_actor uuid)
returns void language plpgsql set search_path = public as $$
declare v_adopted int := 0;
begin
  -- 1 · Adopt. Somebody already here by address, with no employee number, is
  --     this person. Give them the number and the rest of the file's detail
  --     rather than inserting a second row that the unique index would refuse
  --     anyway. This is what the org-document load left for People to finish.
  update person p set
      employee_no   = ul_txt(r.raw,'employee_no'),
      full_name     = ul_txt(r.raw,'full_name'),
      mobile        = coalesce(ul_mobile(ul_txt(r.raw,'mobile')), p.mobile),
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

  -- 2 · Everybody else, by employee number.
  insert into person (employee_no, full_name, work_email, mobile, employment_status,
                      employee_type, joined_on, app_role, source_ref)
  select ul_txt(raw,'employee_no'),
         ul_txt(raw,'full_name'),
         lower(ul_txt(raw,'work_email')),
         ul_mobile(ul_txt(raw,'mobile')),
         'ACTIVE',
         upper(coalesce(ul_txt(raw,'employment_type'),'EMPLOYEE')),
         ul_txt(raw,'date_of_joining')::date,
         'VIEWER',
         'bulk upload'
    from upload_row where batch_id = p_batch
  on conflict (employee_no) where employee_no is not null do update
    set full_name = excluded.full_name, work_email = excluded.work_email,
        mobile = coalesce(excluded.mobile, person.mobile),
        employee_type = excluded.employee_type,
        joined_on = excluded.joined_on, updated_at = now();

  -- managers second, so a person can report to someone created by this file
  update person p set manager_id = m.id
    from upload_row r join person m on m.employee_no = ul_txt(r.raw,'reports_to_employee_no')
   where r.batch_id = p_batch and p.employee_no = ul_txt(r.raw,'employee_no');

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
