-- The Clients validator timed out on the owner's own file. 1,825 branches
-- across 17 clients, and the "one name per client code" rule was written as a
-- self-join: every row against every other row sharing a client code. IDBI
-- Bank alone has 784 branches, so that one client is 614,000 pairs and the
-- file is 890,000 -- a minute of work to answer a question a single pass can
-- answer, and long enough that the upload screen gave up before the database
-- did. Both duplicate rules are now group-bys, linear in the file.
--
-- The rules themselves are unchanged. This is the same check, done once.

create or replace function uv_clients(p_batch uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  update upload_row set error = null where batch_id = p_batch and error is not null;

  update upload_row r set error = e.msg from (
    select r2.id, nullif(concat_ws('; ',
      case when ul_txt(r2.raw,'client_code') is null then 'client_code is required' end,
      case when ul_txt(r2.raw,'client_name') is null then 'client_name is required' end,
      case when ul_txt(r2.raw,'branch_code') is null then 'branch_code is required' end,
      case when ul_txt(r2.raw,'branch_name') is null then 'branch_name is required' end,
      case when ul_txt(r2.raw,'zone') is null then 'zone is required'
           when not exists (select 1 from op_node o
                             where o.level = 'ZONE' and o.active
                               and lower(btrim(o.name)) = lower(btrim(ul_txt(r2.raw,'zone'))))
           then 'zone ' || ul_txt(r2.raw,'zone') || ' is not an operating zone. '
                || 'They come from the zone column of the Geography file, and an '
                || 'administrator can add one under Configuration, Locations.' end,
      case when ul_txt(r2.raw,'status') is not null
            and upper(ul_txt(r2.raw,'status')) not in ('ACTIVE','INACTIVE')
           then 'status must be ACTIVE or INACTIVE, or left blank' end,
      case when ul_txt(r2.raw,'opened_on') is not null
            and not is_ymd(ul_txt(r2.raw,'opened_on'))
           then 'opened_on must be a real date, written YYYY-MM-DD, or left blank' end
    ), '') as msg
    from upload_row r2 where r2.batch_id = p_batch
  ) e where r.id = e.id and e.msg is not null;

  -- one branch code per client, once
  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'this client and branch_code appear on an earlier line'
    from (select id, row_number() over (
            partition by lower(btrim(ul_txt(raw,'client_code'))),
                         lower(btrim(ul_txt(raw,'branch_code')))
            order by row_no) rn
            from upload_row where batch_id = p_batch and error is null) d
   where r.id = d.id and d.rn > 1;

  -- one name per client code, so two spellings do not become two clients.
  -- Grouped, not joined: the same answer without the 890,000 comparisons.
  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'client_code ' || ul_txt(r.raw,'client_code') ||
         ' is given more than one client_name in this file'
    from (select lower(btrim(ul_txt(raw,'client_code'))) cc
            from upload_row
           where batch_id = p_batch and error is null
           group by 1
          having count(distinct lower(btrim(coalesce(ul_txt(raw,'client_name'),'')))) > 1) d
   where r.batch_id = p_batch and r.error is null
     and lower(btrim(ul_txt(r.raw,'client_code'))) = d.cc;
end $$;
