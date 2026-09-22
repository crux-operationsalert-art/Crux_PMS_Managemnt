-- "The file passed validation but the database refused a row" is the one thing
-- the preview exists to prevent. person carries a unique index on mobile among
-- the people who have not left, and nothing checked it -- so a file with the
-- same person entered twice under two employee numbers sailed through the
-- preview and broke at apply, part-way through writing the batch.
--
-- Every unique index on person now has a rule in front of it:
--   employee_no  -> checked (duplicate employee_no in this file)
--   work_email   -> checked (duplicate work_email, and already belongs to)
--   mobile       -> added here, both within the file and against the master
-- user_id and auth_user_id are not set by upload, so they cannot collide.
--
-- The in-file message names the other line rather than just saying "duplicate",
-- because the thing you need in order to fix it is which two lines clash and
-- who they claim to be.

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
