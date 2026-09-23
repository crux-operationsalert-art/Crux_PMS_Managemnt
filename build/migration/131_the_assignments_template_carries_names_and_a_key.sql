-- "Along with the EMP ID I would need the names too, I am not able to see those
-- anywhere to map them" -- which is fair: a file of EMP-0043 and EMP-0086 is
-- unusable unless you already know the numbers by heart, and nothing in the
-- tool showed them next to a name.
--
-- Three changes:
--   * handler_name and location_head_name sit beside each number. The loader
--     ignores them; they are there so a person can read the file.
--   * the rows are seeded at LOCATION, which is the level the Assignments
--     validator has always required and the level the owner actually works at
--     -- eleven branch managers and two zonal managers across seven locations,
--     so a zone was never fine enough.
--   * the file ends with a key: every location that exists, and every person
--     who holds a chair, with their number, their name and their chair. That
--     is the thing that was missing -- somewhere to look the numbers up.
--
-- upload_column is keyed on (kind, ord), so the existing columns move out of
-- the way before the two new ones drop in.
--
-- Verified by staging the seeded rows and validating them: 21 of 59 pass, and
-- the 38 that fail all fail on "handler_employee_no is required" -- which is
-- the point. Every location in the seed resolves.

update upload_column set ord = 9 where kind='Assignments' and name='effective_to';
update upload_column set ord = 8 where kind='Assignments' and name='effective_from';
update upload_column set ord = 6 where kind='Assignments' and name='location_head_employee_no';

insert into upload_column (kind, ord, name, example, rule) values
  ('Assignments', 5, 'handler_name', 'Aniket Chalke',
   'Ignored on upload. Here so you can read the file.'),
  ('Assignments', 7, 'location_head_name', 'Shantanu Suravase',
   'Ignored on upload. Here so you can read the file.');

update upload_column set example = 'Mumbai',
       rule = 'Required. One of your locations - they are listed at the foot of this '
              'file, and in Configuration, Locations.'
 where kind='Assignments' and name='location';

create or replace function upload_seed(p_kind text)
returns table(ord int, line text)
language sql stable security definer set search_path = public as $$
with pair as (
  select oc.id old_client, nc.id new_client
    from client oc
    join client nc on lower(btrim(oc.name)) = lower(btrim(nc.name))
                  and oc.code like 'CLI-%' and nc.code not like 'CLI-%'
), link as (
  select distinct on (ob.id) ob.id old_branch, nb.client_id new_client, nb.op_node_id
    from pair p
    join branch ob on ob.client_id = p.old_client
    join branch nb on nb.client_id = p.new_client
                  and lower(btrim(nb.name)) = lower(btrim(ob.name))
   where nb.op_node_id is not null
   order by ob.id, nb.created_at
), cov as (
  select l.new_client, l.op_node_id, cr.person_id,
         row_number() over (partition by l.new_client, l.op_node_id
                            order by count(*) desc, min(cr.created_at)) rn
    from coverage_rule cr
    join link l on l.old_branch = cr.branch_id
   where cr.effective_to is null
   group by l.new_client, l.op_node_id, cr.person_id
), have as (
  select distinct b.client_id, b.op_node_id from branch b where b.op_node_id is not null
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
  left join cov    on cov.new_client = have.client_id
                  and cov.op_node_id = have.op_node_id and cov.rn = 1
  left join person h on h.id = cov.person_id
  left join person m on m.id = h.manager_id
 where p_kind = 'Assignments'
 order by c.code, o.name;
$$;

-- the key at the foot of the file: where to look the numbers up
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
     and p.employment_status = 'ACTIVE';
$$;

create or replace function upload_template(p_kind text)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_csv text; v_seeded boolean; v_keyed boolean;
begin
  if not exists (select 1 from upload_column where kind = p_kind) then return null; end if;
  select exists (select 1 from upload_seed(p_kind)) into v_seeded;
  select exists (select 1 from upload_key(p_kind))  into v_keyed;

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
    union all select 1000003, '' where v_seeded
    union all select 1000004, 'WHERE THE FILLED-IN VALUES CAME FROM' where v_seeded
    union all select 1000005,
      csv_cell('client_code and location') || ',' ||
      csv_cell('Every client with at least one branch at that location. Fact, not a guess.') where v_seeded
    union all select 1000006,
      csv_cell('handler_employee_no') || ',' ||
      csv_cell('Whoever covers most of that client''s branches there today. A suggestion - check it.') where v_seeded
    union all select 1000007,
      csv_cell('location_head_employee_no') || ',' ||
      csv_cell('Who that handler reports to on the People file. A weak suggestion - correct it first.') where v_seeded
    union all select 1000008,
      csv_cell('a blank handler') || ',' ||
      csv_cell('The tool has no basis for a suggestion. Look the number up in the key below.') where v_seeded
    union all select 2000000, '' where v_keyed
    union all select 2000000 + k.ord, k.line from upload_key(p_kind) k where v_keyed
  ) s;

  -- U+FEFF. Without it Excel opens the file as ANSI and every accented
  -- character, rupee sign and dash in it turns to mojibake.
  return E'﻿' || v_csv;
end $$;
