-- 212 · A branch says where it is
--
-- Loading the workbook (211) put 4,186 months of business into the database and
-- changed nothing for anybody but the administrator. This is why.
--
-- A person's business_record scope is the set of (client, place) pairs their
-- coverage reaches, and coverage reaches branches. 2,580 of the 3,987 branches
-- have no geo_node_id at all -- every branch of every really-named client
-- (IDBI, BOM, SBI, SVC, BOB...) came in from a bulk upload with its address
-- filled and its place empty. The 1,407 that DO have a place all belong to
-- the placeholder clients CLI-000xx. So the pairs the services can build and
-- the pairs the workbook writes had an intersection of exactly nothing, and
-- every MIS, Reports and ten-day screen was empty for all 635 people.
--
-- branch.op_node_id is not the answer. It is filled (2,574 of 2,580) and it is
-- wrong: the operating location "Mumbai" holds branches in Pune, Kolhapur,
-- Satara, Sangli, Ahmedabad, Surat, Nagpur, Rajkot, Solapur and Vadodara. It
-- records which desk loaded the file, not where the branch is.
--
-- The branch itself is the answer. Its address says where it is, in words, and
-- 2,008 of the 2,580 name exactly one of the 142 cities this database knows.
-- Where names nest -- NAVI MUMBAI inside MUMBAI, NEW DELHI inside DELHI,
-- BHILAI inside DURG-BHILAI -- the longer name is the answer, which is the
-- ordinary reading and is what this does.
--
-- The remaining 572 are not guessed. They are left with no place and counted
-- on the Alerts screen, because a branch in the wrong city is worse than a
-- branch in no city: the first is a number somebody will act on.
--
-- Nothing here touches a branch that already has a place.

create or replace function public.branch_place_from_address()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_before int;
  v_placed int;
  v_left   int;
begin
  select count(*) into v_before from branch where geo_node_id is null;

  with cand as (
    select b.id as branch_id, g.id as geo_id,
           row_number() over (partition by b.id
                              order by length(g.name) desc, g.name) as rn
      from branch b
      join geo_node g
        on g.level = 'CITY'
       and (b.address ~* ('\m' || g.name || '\M')
         or b.name    ~* ('\m' || g.name || '\M'))
     where b.geo_node_id is null)
  update branch b
     set geo_node_id = c.geo_id,
         updated_at  = now()
    from cand c
   where c.rn = 1 and b.id = c.branch_id;

  get diagnostics v_placed = row_count;
  select count(*) into v_left from branch where geo_node_id is null;

  return jsonb_build_object('was_unplaced', v_before, 'placed', v_placed, 'still_unplaced', v_left);
end $fn$;

comment on function public.branch_place_from_address() is
  'Puts a branch in the city its own address or name says it is in, where that '
  'is unambiguous (the longest matching city name wins, so NAVI MUMBAI beats '
  'MUMBAI). Only touches branches with no place. Guesses nothing: a branch '
  'whose address names no city this database knows is left alone and counted.';

-- The branches that are still nowhere, as a thing you can look at rather than
-- a number in a migration log.
create or replace view public.branch_without_place as
select b.id, b.code, b.name, b.address, c.code as client_code, c.name as client_name
  from branch b
  join client c on c.id = b.client_id
 where b.geo_node_id is null
   and b.status = 'ACTIVE';

comment on view public.branch_without_place is
  'Branches with no place. Coverage over one of these reaches no business '
  'record, so the person covering it sees an empty MIS and cannot tell why.';

grant select on public.branch_without_place to authenticated;

-- ------------------------------------------------------------------ run it

do $do$
declare
  r jsonb;
  v_pairs int;
  v_rows  int;
begin
  r := branch_place_from_address();
  raise notice '212: %', r::text;

  select count(*) into v_pairs from (select distinct client_id, geo_node_id from branch) x;
  select count(*) into v_rows from business_record r2
   where exists (select 1 from branch b
                  where b.client_id = r2.client_id and b.geo_node_id = r2.geo_node_id);
  raise notice '212: % distinct (client, place) pairs on branches, reaching % of % business records',
    v_pairs, v_rows, (select count(*) from business_record);

  if (r->>'still_unplaced')::int > 0 then
    perform ops_alert_raise(
      'DATA_GAP',
      (r->>'still_unplaced') || ' branches are in no city',
      'branch-without-place', 'WARN',
      (r->>'still_unplaced') || ' branches have no place on them. Their address '
        || 'does not name any of the 142 cities this database knows, so 212 left '
        || 'them alone rather than putting them somewhere plausible. Anyone whose '
        || 'coverage is one of these sees an empty MIS and no reason for it.',
      'They are listed in branch_without_place. Give each one a city -- or add '
        || 'the city to geo_node and run: select branch_place_from_address();');
  else
    update ops_alert set resolved_at = now(),
           resolved_note = 'Every branch has a place.'
     where dedupe_key = 'branch-without-place' and resolved_at is null;
  end if;
end $do$;
