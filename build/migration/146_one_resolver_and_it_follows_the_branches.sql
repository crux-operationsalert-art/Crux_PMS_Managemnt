-- One resolver, and it prefers the place that actually has branches.
--
-- 145 made the appliers read the operating tree. Checking the rates file
-- against it showed the two resolvers still disagreeing with each other:
--
--   the file says   op_location_for gave (branches)   op_zone_id gave (branches)
--   Kolkata         Kolkata Zone           22         Kolkata   INACTIVE    0
--   Patna           BIHAR/PATNA           157         Patna     INACTIVE    0
--   Guwahati        Guwahati Assam Zone    44         Guwahati               0
--   New Delhi       --                      0         New Delhi INACTIVE    0
--
-- So the 749 branches of the clients file went onto one node, and a rate
-- naming the same place would have been priced against a different, empty
-- one. 204 of the 850 rate rows, none of which would have looked wrong.
--
-- Three faults, all the same shape -- a match that is exact, or written
-- first, beating the match that is right:
--
--   1. "A / B" tried BOTH halves exactly before trying either as a word, so
--      "Pune / Latur" matched Pune exactly and never reached Latur (MM).
--      Same for "Patna / Jharkhand", which has its own location too.
--   2. An exact match onto a retired node with no branches still won.
--   3. Nothing ever preferred the candidate that carries branches.
--
-- op_place() replaces both resolvers. One candidate set per half -- exact and
-- whole-word together -- ranked: active first, then branches, then exact,
-- then location over zone. A retired node with no branches is never an
-- answer. Two names tied at the top refuse, and fall back to the single zone
-- carrying the word, which is how Lucknow still resolves.
--
-- op_location_for keeps its own rule -- active LOCATIONs only -- because a
-- branch has to sit on a location, and because 144 proved that rule against a
-- 749 row file. 146b asserts all seven of that file's zones still resolve to
-- exactly the node its branches sit on today.
--
-- What this does NOT fix, because it is the owner's call and not a resolver's:
--
--   New Delhi     124 rows. The only node of that name is retired and empty.
--                 The branches went to "Delhi". Refused, not guessed.
--   Bhubaneswar    36 rows. "Bhuvaneshvar ODISHA Zone" exists and is the only
--                 Odisha zone. Almost certainly the same place, spelt
--                 differently. Refused, not guessed.
--   Chandigarh     12 rows. Nothing of that name. There is a PUNJAB zone.
--                 Refused, not guessed.
--   Pune / Chhatrapati Sambhajinagar   4 rows. The location is filed as
--                 "Chhatrapati SambhajinaJar (AURANGABAD)" -- a J where the
--                 file has a g -- so the word match cannot see it and the row
--                 falls back to Pune. Coarser than it should be.

-- 146a. The one resolver.
create or replace function op_place(p_name text, p_locations_only boolean)
returns uuid language plpgsql stable set search_path = public as $$
declare s text; head text; tail text; re text; hit uuid; n int; halves text[];
begin
  s := btrim(coalesce(p_name, ''));
  if s = '' then return null; end if;

  -- "Zone / Location" is written in some files. The right-hand side is the
  -- more specific answer, so it is exhausted first -- exact AND word -- before
  -- the left-hand side is tried at all. That ordering is fault 1.
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
      -- a retired node with nothing on it is not an answer. Fault 2.
      select * from cand where active or branches > 0
    ), ranked as (
      -- where the work actually is beats how the name is spelt. Fault 3.
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

    -- tied across locations, but exactly one zone carries the word
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

create or replace function op_zone_id(p_name text)
returns uuid language sql stable set search_path = public as $$
  select op_place(p_name, false);
$$;

create or replace function op_location_for(p_name text)
returns uuid language sql stable set search_path = public as $$
  select op_place(p_name, true);
$$;

-- 146b. The expected mapping, written down and run. 33 assertions: the seven
-- zones of the applied clients file must still place a branch on exactly the
-- node its branches sit on today, and the rates file's zones must price the
-- node the work is on -- including three that must refuse rather than guess.
do $$
declare r record; got text; bad text := '';
  expect_loc text[][] := array[
    ['Mumbai',    'Mumbai'],
    ['Delhi',     'Delhi'],
    ['Amaravati', 'Amaravati'],
    ['Bhopal',    'Bhopal'],
    ['Patna',     'BIHAR/PATNA'],
    ['Kolkata',   'Kolkata Zone'],
    ['Guwahati',  'Guwahati Assam Zone']];
  expect_zone text[][] := array[
    ['Mumbai',                 'Mumbai'],
    ['Kolkata',                'Kolkata Zone'],
    ['Patna',                  'BIHAR/PATNA'],
    ['Patna / Bihar',          'BIHAR/PATNA'],
    ['Patna / Jharkhand',      'JHARKHAND (Firoz+ Crux)'],
    ['Guwahati',               'Guwahati Assam Zone'],
    ['Bhopal',                 'Bhopal'],
    ['Bhopal / Indore',        'Indore'],
    ['Bhopal / Gwalior',       'GWALIOR'],
    ['Pune',                   'Pune'],
    ['Pune / Pune',            'Pune'],
    ['Pune / Latur',           'Latur (MM)'],
    ['Pune / Nashik',          'NASHIK'],
    ['Pune / Kolhapur',        'KOLHAPUR'],
    ['Pune / Solapur',         'Solapur'],
    ['Pune / Nagpur (Sudhir)', 'NAGPUR (Sudhir)'],
    ['Pune / Nagpur (Yash)',   'NAGPUR (YASH)'],
    ['Mumbai / Goa',           'GOA'],
    ['Hyderabad',              'Hyderabad Zone'],
    ['Bengaluru',              'Bengaluru + Rest Of Karnataka + Kerela'],
    ['Chennai',                'Tamilnadu + Chennai'],
    ['Ahmedabad',              'AHMEDABAD'],
    ['Lucknow',                'Lucknow / ROUP Zone'],
    ['New Delhi',              '(none)'],
    ['Bhubaneswar',            '(none)'],
    ['Chandigarh',             '(none)']];
  i int;
begin
  for i in 1 .. array_length(expect_loc, 1) loop
    select coalesce(o.name, '(none)') into got
      from op_node o where o.id = op_location_for(expect_loc[i][1]);
    got := coalesce(got, '(none)');
    if got <> expect_loc[i][2] then
      bad := bad || format(E'\n  a branch in "%s" would move from %s to %s',
                           expect_loc[i][1], expect_loc[i][2], got);
    end if;
  end loop;

  for i in 1 .. array_length(expect_zone, 1) loop
    select coalesce(o.name, '(none)') into got
      from op_node o where o.id = op_zone_id(expect_zone[i][1]);
    got := coalesce(got, '(none)');
    if got <> expect_zone[i][2] then
      bad := bad || format(E'\n  a rate for "%s" should price %s, got %s',
                           expect_zone[i][1], expect_zone[i][2], got);
    end if;
  end loop;

  if bad <> '' then
    raise exception 'The resolver does not do what 146 says it does:%', bad;
  end if;
end $$;

-- 146c. The 142 harness, run again: every kind still accepts its own
-- documented example. 13 of 13. Staged and validated only, never applied,
-- and the batches removed.
do $$
declare k text; kinds text[] := array[
    'Chairs','People','Geography','Clients and branches','Assignments','Rates',
    'Collections','KPI targets','Past performance','Opening balances','Holidays',
    'SLA rules','Escalation matrix'];
  v_actor uuid; v_row jsonb; v_stage jsonb; v_batch uuid; v_err text;
  ok int := 0; bad text := '';
begin
  select id into v_actor from person
   where app_role = 'ADMIN' and employment_status = 'ACTIVE' and superseded_by is null limit 1;

  foreach k in array kinds loop
    select jsonb_object_agg(c.name, coalesce(c.example, '')) into v_row
      from public.upload_column c where c.kind = k;
    if v_row is null then
      bad := bad || format(E'\n  %s: no columns are documented', k); continue;
    end if;

    v_stage := upload_stage(k, 'zz 146 self test.csv', jsonb_build_array(v_row), v_actor);
    select t.v::uuid into v_batch
      from jsonb_each_text(v_stage) t(k2, v)
     where t.v ~ '^[0-9a-f]{8}-[0-9a-f]{4}-' limit 1;
    if v_batch is null then
      bad := bad || format(E'\n  %s: would not stage -- %s', k, v_stage::text); continue;
    end if;

    perform upload_validate(v_batch);
    select string_agg(distinct r.error, ' / ') into v_err
      from upload_row r where r.batch_id = v_batch and r.error is not null;

    if v_err is null then ok := ok + 1;
    else bad := bad || format(E'\n  %s: %s', k, v_err); end if;

    delete from upload_row where batch_id = v_batch;
    delete from upload_batch where id = v_batch;
  end loop;

  if bad <> '' then
    raise exception E'% of 13 kinds accept their own example. These do not:%', ok, bad;
  end if;
end $$;
