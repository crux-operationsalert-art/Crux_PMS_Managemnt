-- Three names the resolver refused to guess, settled by the owner.
--
--   New Delhi     124 rate rows. The only node of that name is retired and
--                 empty; the branches are on Delhi. Alias.
--   Chandigarh     12 rate rows. Nothing of that name. The owner places that
--                 work under PUNJAB. Alias.
--   Bhubaneswar    36 rate rows. The owner's instruction is to RENAME, not
--                 alias: "Bhuvaneshvar ODISHA Zone" becomes "Bhubaneswar", so
--                 the tree spells it the way the business does. The old
--                 spelling is kept as an alias, so a file written before today
--                 still loads.
--
-- An alias says "this written form means that place". It is a row, not a
-- deploy, so the next one an owner meets is an insert here.
--
-- This does NOT make the resolver willing to guess: 147d still asserts that a
-- name nobody has mapped resolves to nothing.

-- 147a. The table.
create table if not exists op_node_alias (
  written_as text primary key,
  means      text not null,
  note       text,
  created_by uuid references person(id),
  created_at timestamptz not null default now()
);

comment on table op_node_alias is
  'What a name written in a file means, when it is not what the operating tree calls the place. written_as is compared lower-cased and trimmed; means is resolved by op_place as though the file had said it. A row here, never a deploy.';

alter table op_node_alias enable row level security;

drop policy if exists op_node_alias_read on op_node_alias;
create policy op_node_alias_read on op_node_alias for select using (true);
drop policy if exists op_node_alias_admin_write on op_node_alias;
create policy op_node_alias_admin_write on op_node_alias for all
  using (app_is_admin()) with check (app_is_admin());

-- 147b. The rename, and the three rows.
do $$
declare n int;
begin
  select count(*) into n from op_node where name = 'Bhuvaneshvar ODISHA Zone';
  if n = 0 then
    raise exception 'Nothing is named "Bhuvaneshvar ODISHA Zone" -- has it already been renamed?';
  end if;

  update op_node set name = 'Bhubaneswar' where name = 'Bhuvaneshvar ODISHA Zone';

  select count(*) into n from op_node where name = 'Bhubaneswar';
  if n <> 2 then
    raise exception 'Expected the zone and its location to be renamed, found % row(s).', n;
  end if;
end $$;

insert into op_node_alias (written_as, means, note) values
  ('new delhi', 'Delhi',
   'The rates file writes New Delhi. The only node of that name is retired and empty; the branches are on Delhi.'),
  ('chandigarh', 'PUNJAB',
   'The rates file writes Chandigarh. There is no node of that name; the owner places that work under PUNJAB.'),
  ('bhuvaneshvar odisha zone', 'Bhubaneswar',
   'What the tree called the Odisha zone until 147b renamed it. Kept so a file written before that still loads.')
on conflict (written_as) do update
  set means = excluded.means, note = excluded.note;

-- 147c. The resolver reads the alias first. Per half, so "Zone / Chandigarh"
-- works as well as "Chandigarh".
create or replace function op_place(p_name text, p_locations_only boolean)
returns uuid language plpgsql stable set search_path = public as $$
declare s text; head text; tail text; re text; hit uuid; n int;
        halves text[]; v_means text;
begin
  s := btrim(coalesce(p_name, ''));
  if s = '' then return null; end if;

  if position('/' in s) > 0 then
    head := btrim(split_part(s, '/', 1));
    tail := btrim(split_part(s, '/', 2));
  else
    head := s; tail := null;
  end if;
  halves := case when tail is null or lower(tail) = lower(head)
                 then array[head] else array[tail, head] end;

  foreach s in array halves loop
    hit := null;
    v_means := null;

    -- what this written form means, when the owner has said so
    select a.means into v_means from op_node_alias a where a.written_as = lower(btrim(s));
    if v_means is not null then s := v_means; end if;

    re := case when length(s) >= 4
               then '(^|[^[:alnum:]])'
                    || regexp_replace(s, '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g')
                    || '([^[:alnum:]]|$)'
               else null end;

    with cand as (
      select o.id, o.name, o.active, o.level,
             (lower(btrim(o.name)) = lower(s)) as is_exact,
             (select count(*) from branch b where b.op_node_id = o.id) as branches
        from op_node o
       where (not p_locations_only or (o.level = 'LOCATION' and o.active))
         and (lower(btrim(o.name)) = lower(s) or (re is not null and o.name ~* re))
    ), live as (
      select * from cand where active or branches > 0
    ), ranked as (
      select live.*,
             row_number() over (order by active desc, branches desc, is_exact desc,
                                         (level = 'LOCATION') desc, length(name), name) as rn,
             dense_rank() over (order by active desc, branches desc, is_exact desc,
                                         (level = 'LOCATION') desc) as tier
        from live
    )
    select rk.id,
           (select count(distinct lower(btrim(r2.name))) from ranked r2 where r2.tier = 1)
      into hit, n
      from ranked rk where rk.rn = 1;

    if hit is not null and n = 1 then return hit; end if;

    if not p_locations_only and re is not null then
      select count(distinct lower(btrim(o.name))) into n
        from op_node o where o.level = 'ZONE' and o.active and o.name ~* re;
      if n = 1 then
        select o.id into hit from op_node o
         where o.level = 'ZONE' and o.active and o.name ~* re limit 1;
        return hit;
      end if;
    end if;
  end loop;

  return null;
end $$;

-- 147d. The whole mapping again, now including the three the owner settled --
-- and Timbuktu, which must still resolve to nothing, so that adding an alias
-- table has not quietly made the resolver willing to guess.
do $$
declare got text; bad text := ''; i int;
  el text[][] := array[
    ['Mumbai','Mumbai'],['Delhi','Delhi'],['Amaravati','Amaravati'],['Bhopal','Bhopal'],
    ['Patna','BIHAR/PATNA'],['Kolkata','Kolkata Zone'],['Guwahati','Guwahati Assam Zone']];
  ez text[][] := array[
    ['Mumbai','Mumbai'],['Kolkata','Kolkata Zone'],['Patna','BIHAR/PATNA'],
    ['Patna / Bihar','BIHAR/PATNA'],['Patna / Jharkhand','JHARKHAND (Firoz+ Crux)'],
    ['Guwahati','Guwahati Assam Zone'],['Bhopal','Bhopal'],['Bhopal / Indore','Indore'],
    ['Bhopal / Gwalior','GWALIOR'],['Pune','Pune'],['Pune / Pune','Pune'],
    ['Pune / Latur','Latur (MM)'],['Pune / Nashik','NASHIK'],['Pune / Kolhapur','KOLHAPUR'],
    ['Pune / Solapur','Solapur'],['Pune / Nagpur (Sudhir)','NAGPUR (Sudhir)'],
    ['Pune / Nagpur (Yash)','NAGPUR (YASH)'],['Mumbai / Goa','GOA'],
    ['Hyderabad','Hyderabad Zone'],['Bengaluru','Bengaluru + Rest Of Karnataka + Kerela'],
    ['Chennai','Tamilnadu + Chennai'],['Ahmedabad','AHMEDABAD'],
    ['Lucknow','Lucknow / ROUP Zone'],
    ['New Delhi','Delhi'],['Chandigarh','PUNJAB'],['Bhubaneswar','Bhubaneswar'],
    ['Bhuvaneshvar ODISHA Zone','Bhubaneswar'],['Timbuktu','(none)']];
begin
  for i in 1 .. array_length(el, 1) loop
    select coalesce(o.name, '(none)') into got from op_node o where o.id = op_location_for(el[i][1]);
    got := coalesce(got, '(none)');
    if got <> el[i][2] then
      bad := bad || format(E'\n  branch "%s": expected %s, got %s', el[i][1], el[i][2], got);
    end if;
  end loop;

  for i in 1 .. array_length(ez, 1) loop
    select coalesce(o.name, '(none)') into got from op_node o where o.id = op_zone_id(ez[i][1]);
    got := coalesce(got, '(none)');
    if got <> ez[i][2] then
      bad := bad || format(E'\n  rate "%s": expected %s, got %s', ez[i][1], ez[i][2], got);
    end if;
  end loop;

  if bad <> '' then
    raise exception 'The resolver does not do what 146 and 147 say it does:%', bad;
  end if;
end $$;
