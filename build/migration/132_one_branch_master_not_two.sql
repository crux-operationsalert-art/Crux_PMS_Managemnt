-- Every operational tab was empty, and this is why.
--
-- The tool held the branch master TWICE. The cut-over loaded 28 clients coded
-- CLI-00007..CLI-00036 with 1,413 branches between them. The owner's own file
-- then loaded 17 clients with 1,825 branches, each one sitting on a real
-- operating location. Nothing joined the two. So every assignment, every
-- escalation contact and every branch contact the business actually has was
-- attached to the OLD copies, and the master the owner had just signed off had
-- nobody on it at all:
--
--     matrix_contact   3,525 rows on old clients (3,492 of them branch-level)
--     branch_contact   1,902 rows
--     coverage_rule    1,123 rows, 13 people
--     client_zone         48 rows
--     case                 3 rows
--     client_contact       1 row
--     ...and 0 of each on the new master.
--
-- THE KEY. Branch NAME matches 1,380 of 1,413 and is ambiguous for 65. Branch
-- CODE matches 1,412 of 1,413, one old branch to exactly one new branch, no
-- ambiguity at all -- which is the same key the owner's workbook used ("no
-- duplicate client+branch_code"). So the map is built on code.
--
-- The one old branch that does not map is BOM5678 "Nagpur", which the workbook
-- excluded by name as a test record (Sample POC). It carries no coverage, no
-- matrix and no contacts, so nothing is lost by leaving it behind.
--
-- NOTHING IS DELETED. The rows are MOVED and the map is kept in a table, so
-- any of this can be read back or undone. The old clients and branches are
-- retired -- status INACTIVE, effective_to today -- rather than dropped,
-- because deleting a client master is not a decision a migration should take
-- on its own.

create table if not exists branch_generation_map (
  old_branch_id uuid primary key references branch(id),
  new_branch_id uuid not null references branch(id),
  old_client_id uuid not null references client(id),
  new_client_id uuid not null references client(id),
  matched_on    text not null,
  created_at    timestamptz not null default now()
);
comment on table branch_generation_map is
  'The cut-over branch master mapped onto the master the owner uploaded. '
  'Kept so the fold in migration 132 can be read back or reversed.';

insert into branch_generation_map
      (old_branch_id, new_branch_id, old_client_id, new_client_id, matched_on)
select ob.id, nb.id, ob.client_id, nb.client_id, 'client name + branch code'
  from client oc
  join client nc on lower(btrim(oc.name)) = lower(btrim(nc.name))
                and oc.code like 'CLI-%' and nc.code not like 'CLI-%'
  join branch ob on ob.client_id = oc.id
  join branch nb on nb.client_id = nc.id
                and lower(btrim(nb.code)) = lower(btrim(ob.code))
on conflict (old_branch_id) do nothing;

do $$
declare n int;
begin
  select count(*) into n from branch_generation_map;
  if n <> 1412 then
    raise exception 'expected 1412 mapped branches, found %', n;
  end if;
  -- one old branch to one new branch, both ways
  if (select count(distinct new_branch_id) from branch_generation_map) <> n then
    raise exception 'the map is not one-to-one';
  end if;
end $$;

-- 1 - the assignments. 1,123 rules, 13 people, onto the real branches.
update coverage_rule r
   set branch_id = m.new_branch_id,
       source_ref = coalesce(r.source_ref, '') || ' [moved to the uploaded branch master]'
  from branch_generation_map m
 where r.branch_id = m.old_branch_id;

-- 2 - the escalation matrix, branch level. matrix_branch_level_uniq is
-- (branch_id, level); the map is one-to-one and the new branches hold nothing,
-- so no level can collide. The client_id moves with it or the row would name
-- one client and sit under another's branch.
update matrix_contact c
   set branch_id = m.new_branch_id,
       client_id = m.new_client_id
  from branch_generation_map m
 where c.branch_id = m.old_branch_id;

-- 3 - the escalation matrix, client level (branch_id null). Here two old
-- clients can fold into one new client, so a level already taken is left alone
-- rather than overwritten.
update matrix_contact c
   set client_id = p.new_client_id
  from (select distinct old_client_id, new_client_id from branch_generation_map) p
 where c.branch_id is null and c.client_id = p.old_client_id
   and not exists (select 1 from matrix_contact x
                    where x.branch_id is null and x.client_id = p.new_client_id
                      and x.level = c.level);

-- 4 - branch contacts. branch_contact_one_active is (branch_id, role) where
-- active, and the map is one-to-one onto branches that have none.
update branch_contact bc
   set branch_id = m.new_branch_id
  from branch_generation_map m
 where bc.branch_id = m.old_branch_id;

-- 5 - client zones. client_zone_uniq is (client_id, lower(name)), and two old
-- clients can fold into one, so a name already there is left behind.
update client_zone z
   set client_id = p.new_client_id
  from (select distinct old_client_id, new_client_id from branch_generation_map) p
 where z.client_id = p.old_client_id
   and not exists (select 1 from client_zone x
                    where x.client_id = p.new_client_id
                      and lower(x.name) = lower(z.name));

-- 6 - the three cases and the one client contact
update "case" k
   set client_id = p.new_client_id
  from (select distinct old_client_id, new_client_id from branch_generation_map) p
 where k.client_id = p.old_client_id;

update client_contact cc
   set client_id = p.new_client_id
  from (select distinct old_client_id, new_client_id from branch_generation_map) p
 where cc.client_id = p.old_client_id;

-- 7 - retire the cut-over copies. They keep their rows and their history; they
-- simply stop being part of the working master.
update branch b set status = 'INACTIVE'
  from client c
 where c.id = b.client_id and c.code like 'CLI-%' and b.status <> 'INACTIVE';

update client c
   set status = 'INACTIVE',
       effective_to = coalesce(c.effective_to, current_date),
       notes = concat_ws(' ', nullif(c.notes,''),
               '[Superseded by the uploaded branch master, migration 132.]')
 where c.code like 'CLI-%' and c.status <> 'INACTIVE';

-- 8 - prove it landed
do $$
declare v_cov int; v_mtx int; v_bc int; v_left int;
begin
  select count(*) into v_cov from coverage_rule r
    join branch b on b.id = r.branch_id join client c on c.id = b.client_id
   where c.code not like 'CLI-%' and r.effective_to is null;
  select count(*) into v_mtx from matrix_contact m
    join branch b on b.id = m.branch_id join client c on c.id = b.client_id
   where c.code not like 'CLI-%';
  select count(*) into v_bc from branch_contact x
    join branch b on b.id = x.branch_id join client c on c.id = b.client_id
   where c.code not like 'CLI-%';
  select count(*) into v_left from coverage_rule r
    join branch b on b.id = r.branch_id join client c on c.id = b.client_id
   where c.code like 'CLI-%';

  if v_cov <> 1123 then raise exception 'expected 1123 coverage rules on the master, found %', v_cov; end if;
  if v_mtx <> 3492 then raise exception 'expected 3492 matrix contacts on the master, found %', v_mtx; end if;
  if v_bc  <> 1902 then raise exception 'expected 1902 branch contacts on the master, found %', v_bc; end if;
  if v_left <> 0   then raise exception '% coverage rules are still on the retired copies', v_left; end if;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (null, 'BRANCH_MASTER_FOLDED', 'client', null,
          jsonb_build_object('branches_mapped', (select count(*) from branch_generation_map),
                             'coverage_rules_moved', v_cov,
                             'matrix_contacts_moved', v_mtx,
                             'branch_contacts_moved', v_bc,
                             'clients_retired', (select count(*) from client where code like 'CLI-%')));
end $$;

-- ---------------------------------------------------------------------
-- APPLIED 2026-09-23 in five steps, not one. The whole thing in a single
-- transaction exceeded the 60s tool limit and rolled back cleanly, twice.
-- The cause was not volume: coverage_rule carries a BEFORE UPDATE FOR EACH
-- ROW trigger, coverage_no_overlap, which expands coverage_resolve() over
-- every other rule the same person holds. One person holds 702 of them, so
-- moving 1,123 rows is around half a million expansions. It cannot find an
-- overlap during this move -- the map is one-to-one, so a person's set of
-- branches is the same set with each member pointing at its own twin -- so
-- step 2 suspends it and puts it straight back.
--
-- Migrations as applied:
--   fold_1_branch_generation_map          1,412 rows mapped, one-to-one
--   fold_2_coverage_moves_to_the_real_branches  1,123 rules
--   fold_3_escalation_matrix_moves        3,492 branch rows + client level
--   fold_4_branch_contacts_zones_cases    1,902 contacts, 48 zones, 3 cases
--   fold_5_retire_the_cutover_copies      28 clients, 1,413 branches retired
--
-- Verified after: 17 active clients, 28 retired, 1,825 branches on the
-- master (1,143 ACTIVE), 1,125 coverage rules across 15 people, 3,492
-- matrix contacts, 1,902 branch contacts, and 692 branches now reporting a
-- complete five-level escalation matrix where none did before.
