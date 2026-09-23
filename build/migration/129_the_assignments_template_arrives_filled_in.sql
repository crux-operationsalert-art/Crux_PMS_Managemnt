-- The owner asked for the Assignments template to come down already filled in
-- with the client, location and product combinations that exist, and with a
-- suggested handler, so the job becomes correcting a list rather than writing
-- one. It is the right idea: the tool knows which clients have branches in
-- which operating zone -- 59 pairs -- and it knows who used to cover those
-- branches. Asking a person to retype that is asking them to make mistakes.
--
-- WHERE EACH SUGGESTION COMES FROM, because a filled-in cell that is wrong is
-- worse than an empty one unless you can see where it came from:
--
--   client_code, location   every client that has at least one branch in that
--                           operating zone, after the Clients file. Fact.
--   product                 left blank, which means every product. The tool
--                           has no product data yet.
--   handler_employee_no     whoever covers the most of that client's branches
--                           in that zone today, carried across from the
--                           coverage the old branch list still holds. A
--                           suggestion. 21 of the 59 rows get one.
--   location_head_...       who that handler reports to on the People file. A
--                           suggestion, and a weak one -- most of the company
--                           reports to one person -- so it is the first thing
--                           to correct.
--   effective_from          the first of the current month, so this month's
--                           work is covered. Change it if cover started earlier.
--
-- Nothing here is written to a master. It is a starting point in a CSV that
-- the owner edits, and the validator still judges every row on the way back in.
--
-- upload_seed is per-kind and returns nothing for the other twelve, which keep
-- the single example row they have always had.
--
-- Also corrects the People template's chair example, which still read
-- "Branch Manager — Pune" -- the exact thing the owner flagged when the chair
-- catalogue first came in. A chair is a job; where somebody works is
-- Assignments.

create or replace function upload_seed(p_kind text)
returns table(ord int, line text)
language sql stable security definer set search_path = public as $$
with pair as (          -- the older client row and the one the owner's file made
  select oc.id old_client, nc.id new_client
    from client oc
    join client nc on lower(btrim(oc.name)) = lower(btrim(nc.name))
                  and oc.code like 'CLI-%' and nc.code not like 'CLI-%'
), link as (            -- an old branch and the new one that replaced it
  select distinct on (ob.id) ob.id old_branch, nb.client_id new_client, nb.op_node_id
    from pair p
    join branch ob on ob.client_id = p.old_client
    join branch nb on nb.client_id = p.new_client
                  and lower(btrim(nb.name)) = lower(btrim(ob.name))
   where nb.op_node_id is not null
   order by ob.id, nb.created_at
), cov as (             -- who covers most of that client's branches in that zone
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
         csv_cell(coalesce(h.employee_no,'')), csv_cell(coalesce(m.employee_no,'')),
         csv_cell(to_char(date_trunc('month', current_date), 'YYYY-MM-DD')), csv_cell(''))
  from have
  join client  c on c.id = have.client_id
  join op_node o on o.id = have.op_node_id
  left join cov    on cov.new_client = have.client_id
                  and cov.op_node_id = have.op_node_id and cov.rn = 1
  left join person h on h.id = cov.person_id
  left join person m on m.id = h.manager_id
 where p_kind = 'Assignments'
 order by c.code, o.name;
$$;

create or replace function upload_template(p_kind text)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_csv text; v_seeded boolean;
begin
  if not exists (select 1 from upload_column where kind = p_kind) then return null; end if;
  select exists (select 1 from upload_seed(p_kind)) into v_seeded;

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
    -- either the rows the tool already knows, or the one worked example
    union all select 5 + s.ord, s.line from upload_seed(p_kind) s where v_seeded
    union all select 5, (select string_agg(csv_cell(example), ',' order by ord)
                           from upload_column where kind = p_kind) where not v_seeded
    union all select 1000000, ''
    union all select 1000001, 'NOTES'
    union all select 1000002, (select string_agg(csv_cell(name) || ',' || csv_cell(rule), E'\n' order by ord)
                                 from upload_column where kind = p_kind)
    union all select 1000003, '' where v_seeded
    union all select 1000004,
      'WHERE THE FILLED-IN VALUES CAME FROM' where v_seeded
    union all select 1000005,
      csv_cell('client_code and location') || ',' ||
      csv_cell('Every client with at least one branch in that operating zone. This is fact, not a guess.')
      where v_seeded
    union all select 1000006,
      csv_cell('handler_employee_no') || ',' ||
      csv_cell('Whoever covers most of that client''s branches in that zone today. A suggestion - check it.')
      where v_seeded
    union all select 1000007,
      csv_cell('location_head_employee_no') || ',' ||
      csv_cell('Who that handler reports to on the People file. A weak suggestion - correct it first.')
      where v_seeded
    union all select 1000008,
      csv_cell('effective_from') || ',' ||
      csv_cell('The first of this month, so this month is covered. Change it if cover started earlier.')
      where v_seeded
    union all select 1000009,
      csv_cell('a blank handler') || ',' ||
      csv_cell('Means the tool has no basis for a suggestion. You have to fill it in.')
      where v_seeded
  ) s;

  -- U+FEFF. Without it Excel opens the file as ANSI and every accented
  -- character, rupee sign and dash in it turns to mojibake.
  return E'﻿' || v_csv;
end $$;

update upload_column
   set example = 'BRANCH_MANAGER',
       rule = 'Required. The chair code or its exact title, from the Chairs file. '
              'A chair is a job, not a place - where someone works comes from Assignments.'
 where kind = 'People' and name = 'chair';
