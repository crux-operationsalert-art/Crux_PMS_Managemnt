-- I got the operating grouping wrong twice and this undoes the second one.
--
-- 127 created the owner's seven file zones -- Mumbai, Amaravati, Patna,
-- Bhopal, Guwahati, Kolkata, New Delhi -- as new ZONE rows in op_node. They
-- should never have been created at all: six of the seven already existed as
-- LOCATIONs, put there by the owner's own operating grouping, and the seventh
-- is BIHAR/PATNA. So op_node grew eleven duplicate names, and the Assignments
-- validator -- which has always required level = 'LOCATION' -- would have
-- refused every row of the template 129 had just filled in.
--
--   Amaravati  -> Amaravati               Mumbai    -> Mumbai
--   Bhopal     -> Bhopal                  New Delhi -> Delhi
--   Guwahati   -> Guwahati Assam Zone     Patna     -> BIHAR/PATNA
--   Kolkata    -> Kolkata Zone
--
-- The 1,825 branches move to the location, the seven duplicates are switched
-- off rather than deleted -- the owner's rule since op_retire -- and the
-- Clients and Geography loaders now resolve a file zone to a LOCATION, which
-- is the level the whole rest of the tool already worked at.

create temporary table remap on commit drop as
select z.id as dup_zone, l.id as location_id, z.name as file_zone, l.name as location_name
  from op_node z
  join op_node l on l.level = 'LOCATION' and l.active
                and lower(btrim(l.name)) = lower(btrim(
                      case lower(btrim(z.name))
                        when 'new delhi' then 'Delhi'
                        when 'patna'     then 'BIHAR/PATNA'
                        when 'guwahati'  then 'Guwahati Assam Zone'
                        when 'kolkata'   then 'Kolkata Zone'
                        else z.name end))
 where z.level = 'ZONE' and z.source_ref = 'Geography upload';

do $$ begin
  if (select count(*) from remap) <> 7 then
    raise exception 'expected 7 zone-to-location matches, found %', (select count(*) from remap);
  end if;
end $$;

update branch b set op_node_id = r.location_id from remap r where b.op_node_id = r.dup_zone;

insert into audit_entry (action, entity_type, entity_ref, old_value, new_value)
select 'OP_NODE_RETIRED', 'op_node', r.file_zone,
       jsonb_build_object('level','ZONE','name',r.file_zone,'why','created in error by migration 127'),
       jsonb_build_object('branches_moved_to', r.location_name)
  from remap r;

update op_node set active = false, updated_at = now()
 where id in (select dup_zone from remap);

-- the North East group 127 added has nothing under it now
update op_node set active = false where level='GROUP' and name='North East'
   and not exists (select 1 from op_node c where c.parent_id = op_node.id and c.active);

-- ------------------------------------------------- the loaders follow suit
create or replace function op_location_for(p_name text)
returns uuid language sql stable as $$
  select id from op_node
   where level = 'LOCATION' and active and lower(btrim(name)) = lower(btrim(p_name))
   limit 1;
$$;

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
           when op_location_for(ul_txt(r2.raw,'zone')) is null
           then 'zone ' || ul_txt(r2.raw,'zone') || ' is not one of your locations. '
                || 'Configuration, Locations lists them, and that is also where '
                || 'a new one is added.' end,
      case when ul_txt(r2.raw,'status') is not null
            and upper(ul_txt(r2.raw,'status')) not in ('ACTIVE','INACTIVE')
           then 'status must be ACTIVE or INACTIVE, or left blank' end,
      case when ul_txt(r2.raw,'opened_on') is not null
            and not is_ymd(ul_txt(r2.raw,'opened_on'))
           then 'opened_on must be a real date, written YYYY-MM-DD, or left blank' end
    ), '') as msg
    from upload_row r2 where r2.batch_id = p_batch
  ) e where r.id = e.id and e.msg is not null;

  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'this client and branch_code appear on an earlier line'
    from (select id, row_number() over (
            partition by lower(btrim(ul_txt(raw,'client_code'))),
                         lower(btrim(ul_txt(raw,'branch_code')))
            order by row_no) rn
            from upload_row where batch_id = p_batch and error is null) d
   where r.id = d.id and d.rn > 1;

  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'client_code ' || ul_txt(r.raw,'client_code') ||
         ' is given more than one client_name in this file'
    from (select lower(btrim(ul_txt(raw,'client_code'))) cc
            from upload_row where batch_id = p_batch and error is null
           group by 1
          having count(distinct lower(btrim(coalesce(ul_txt(raw,'client_name'),'')))) > 1) d
   where r.batch_id = p_batch and r.error is null
     and lower(btrim(ul_txt(r.raw,'client_code'))) = d.cc;
end $$;

create or replace function ua_clients(p_batch uuid, p_actor uuid)
returns void language plpgsql set search_path = public as $$
begin
  insert into client (code, name, status, source_ref)
  select distinct on (ul_txt(raw,'client_code'))
         ul_txt(raw,'client_code'), ul_txt(raw,'client_name'), 'ACTIVE', 'bulk upload'
    from upload_row where batch_id = p_batch
   order by ul_txt(raw,'client_code'), row_no
  on conflict (code) do update set name = excluded.name, updated_at = now();

  insert into branch (client_id, code, name, address, op_node_id, status,
                      effective_from, source_ref)
  select c.id, ul_txt(r.raw,'branch_code'), ul_txt(r.raw,'branch_name'),
         ul_txt(r.raw,'address'), op_location_for(ul_txt(r.raw,'zone')),
         upper(coalesce(ul_txt(r.raw,'status'),'ACTIVE'))::entity_status,
         ul_date(ul_txt(r.raw,'opened_on')), 'bulk upload'
    from upload_row r
    join client c on c.code = ul_txt(r.raw,'client_code')
   where r.batch_id = p_batch and op_location_for(ul_txt(r.raw,'zone')) is not null
  on conflict (client_id, code) do update
    set name = excluded.name, address = excluded.address,
        op_node_id = excluded.op_node_id, status = excluded.status,
        effective_from = coalesce(excluded.effective_from, branch.effective_from),
        updated_at = now();

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'CLIENTS_UPLOADED', 'upload_batch', p_batch::text,
          jsonb_build_object('rows', (select count(*) from upload_row where batch_id = p_batch)));
end $$;

update upload_column set rule =
  'Required. The location that runs the branch, from Configuration, Locations '
  '- the same names as the zone column of the Geography file.'
 where kind = 'Clients and branches' and name = 'zone';
