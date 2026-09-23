-- "zone doesn't exist, but I have uploaded these zones" -- and they had. This
-- is the other half of 126 and it was mine to finish.
--
-- 126 separated the two things that had been sharing the word "zone": the
-- geography (region -> state -> city, which the branches hang off) and the
-- OPERATING zone the owner actually works in -- Mumbai, Amaravati, Patna. It
-- put the operating zone on geo_node.op_zone as a label and moved the tree
-- over to region. What it did not do was tell the Clients loader, which still
-- looked the zone up as a geographic ZONE and so refused all 1,825 rows.
--
-- The operating grouping already has a home: op_node, which is what
-- Configuration, Locations edits and what the Assignments loader resolves
-- against. A branch belongs to an operating zone, so branch now carries
-- op_node_id and the Clients loader resolves against op_node like Assignments
-- does. geo_node keeps answering "where is this place"; op_node answers "who
-- runs it". No column means both any more.
--
-- The seven zones in the Geography file already applied are created here from
-- what that upload recorded, so the owner does not have to load it again. Each
-- sits under the group its region implies -- Amaravati under South, Guwahati
-- under North East, Mumbai and Bhopal under West, Patna and New Delhi under
-- North, Kolkata under East -- and North East is added as a group because the
-- operating grouping had only four.
--
-- Verified: the owner's 1,825-row file validates 1,825 of 1,825.

alter table branch add column if not exists op_node_id uuid references op_node(id);
comment on column branch.op_node_id is
  'The operating zone that runs this branch, from op_node. geo_node_id says '
  'where the branch is; this says who runs it.';
create index if not exists branch_op_node_idx on branch(op_node_id);

-- 1 · the groups the applied geography implies, then the zones under them
insert into op_node (level, name, active, source_ref)
select distinct 'GROUP', z.name, true, 'Geography upload'
  from geo_node g
  join geo_node s on s.id = g.parent_id
  join geo_node z on z.id = s.parent_id and z.level = 'ZONE'
 where g.op_zone is not null
   and not exists (select 1 from op_node o
                    where o.level='GROUP' and lower(btrim(o.name)) = lower(btrim(z.name)));

insert into op_node (level, name, parent_id, active, source_ref)
select 'ZONE', x.op_zone, grp.id, true, 'Geography upload'
  from (
    select g.op_zone, z.name as region,
           row_number() over (partition by g.op_zone order by count(*) desc, z.name) rn
      from geo_node g
      join geo_node s on s.id = g.parent_id
      join geo_node z on z.id = s.parent_id and z.level = 'ZONE'
     where g.op_zone is not null
     group by g.op_zone, z.name
  ) x
  join op_node grp on grp.level='GROUP' and lower(btrim(grp.name)) = lower(btrim(x.region))
 where x.rn = 1
   and not exists (select 1 from op_node o
                    where o.level='ZONE' and lower(btrim(o.name)) = lower(btrim(x.op_zone)));

-- 2 · going forward the Geography upload keeps them in step. Same as 126 but
--     with the operating zone created as a node rather than only labelled.
create or replace function ua_geography(p_batch uuid, p_actor uuid)
returns void language plpgsql set search_path = public, extensions as $$
declare r record; v_zone uuid; v_state uuid; v_city uuid; v_old uuid; v_grp uuid; v_op uuid;
        v_moved int := 0; v_spelling int := 0; v_city_moved int := 0; v_ops int := 0;
begin
  for r in select row_no, raw from upload_row where batch_id = p_batch order by row_no loop

    select id into v_zone from geo_node
     where level = 'ZONE' and lower(name) = lower(geo_region(ul_txt(r.raw,'region')));
    if v_zone is null then
      insert into geo_node (level, name) values ('ZONE', geo_region(ul_txt(r.raw,'region')))
      returning id into v_zone;
    end if;

    -- the operating zone is a real place in the operating grouping, not a
    -- label, because a branch has to be able to point at it
    if ul_txt(r.raw,'zone') is not null then
      select id into v_grp from op_node
       where level='GROUP' and lower(btrim(name)) = lower(geo_region(ul_txt(r.raw,'region')));
      if v_grp is null then
        insert into op_node (level, name, active, source_ref)
        values ('GROUP', geo_region(ul_txt(r.raw,'region')), true, 'Geography upload')
        returning id into v_grp;
      end if;
      select id into v_op from op_node
       where level='ZONE' and lower(btrim(name)) = lower(btrim(ul_txt(r.raw,'zone')));
      if v_op is null then
        insert into op_node (level, name, parent_id, active, source_ref)
        values ('ZONE', ul_txt(r.raw,'zone'), v_grp, true, 'Geography upload');
        v_ops := v_ops + 1;
      end if;
    end if;

    select id into v_state from geo_node
     where level = 'STATE' and lower(btrim(name)) = lower(btrim(ul_txt(r.raw,'state')))
     limit 1;

    if v_state is null then
      select id into v_state from geo_node
       where level = 'STATE'
         and extensions.levenshtein(lower(btrim(name)),
                                    lower(btrim(ul_txt(r.raw,'state')))) between 1 and 2
       order by extensions.levenshtein(lower(btrim(name)),
                                       lower(btrim(ul_txt(r.raw,'state')))), name
       limit 1;
      if v_state is not null then
        v_spelling := v_spelling + 1;
        insert into migration_review (entity_type, entity_ref, question, context)
        select 'geo_node', v_state::text,
               'Is "' || ul_txt(r.raw,'state') || '" the same state as "' || g.name || '"?',
               'The Geography file spelled it differently. It was matched to the ' ||
               'existing row rather than added again, so the branches already on ' ||
               'it stay together. Rename it if the file is right.'
          from geo_node g where g.id = v_state
         and not exists (select 1 from migration_review m
                          where m.entity_type='geo_node' and m.entity_ref = v_state::text);
      end if;
    end if;

    if v_state is null then
      insert into geo_node (level, name, parent_id, group_name, op_zone)
      values ('STATE', ul_txt(r.raw,'state'), v_zone,
              ul_txt(r.raw,'group'), ul_txt(r.raw,'zone'))
      returning id into v_state;
    else
      select parent_id into v_old from geo_node where id = v_state;
      if v_old is distinct from v_zone then
        v_moved := v_moved + 1;
        insert into migration_review (entity_type, entity_ref, question, context)
        select 'geo_node', v_state::text,
               'Should ' || g.name || ' sit in ' || geo_region(ul_txt(r.raw,'region')) || '?',
               'It was in ' || coalesce(o.name,'no region') || '. The Geography file ' ||
               'moved it. Every branch stayed attached - a branch points at the ' ||
               'state, not at the region above it.'
          from geo_node g left join geo_node o on o.id = v_old
         where g.id = v_state;
        update geo_node set parent_id = v_zone where id = v_state;
      end if;
      update geo_node set group_name = coalesce(ul_txt(r.raw,'group'), group_name),
                          op_zone    = coalesce(ul_txt(r.raw,'zone'), op_zone)
       where id = v_state;
    end if;

    if ul_txt(r.raw,'city') is not null then
      select id into v_city from geo_node
       where level = 'CITY' and parent_id = v_state
         and lower(btrim(name)) = lower(btrim(ul_txt(r.raw,'city')));

      if v_city is null then
        select id into v_city from geo_node g
         where g.level = 'CITY' and lower(btrim(g.name)) = lower(btrim(ul_txt(r.raw,'city')))
           and (select count(*) from geo_node x
                 where x.level='CITY' and lower(btrim(x.name)) = lower(btrim(ul_txt(r.raw,'city')))) = 1
         limit 1;
        if v_city is not null then
          v_city_moved := v_city_moved + 1;
          update geo_node set parent_id = v_state where id = v_city;
        end if;
      end if;

      if v_city is null then
        insert into geo_node (level, name, parent_id, group_name, op_zone)
        values ('CITY', ul_txt(r.raw,'city'), v_state,
                ul_txt(r.raw,'group'), ul_txt(r.raw,'zone'));
      else
        update geo_node set group_name = coalesce(ul_txt(r.raw,'group'), group_name),
                            op_zone    = coalesce(ul_txt(r.raw,'zone'), op_zone)
         where id = v_city;
      end if;
    end if;
  end loop;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'GEOGRAPHY_UPLOADED', 'upload_batch', p_batch::text,
          jsonb_build_object('states_moved', v_moved, 'cities_moved', v_city_moved,
                             'spellings_matched', v_spelling, 'operating_zones_added', v_ops));
end $$;

-- 3 · the Clients loader records who runs the branch
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
         ul_txt(r.raw,'address'), o.id,
         upper(coalesce(ul_txt(r.raw,'status'),'ACTIVE'))::entity_status,
         ul_date(ul_txt(r.raw,'opened_on')), 'bulk upload'
    from upload_row r
    join client c  on c.code = ul_txt(r.raw,'client_code')
    join op_node o on o.level = 'ZONE' and o.active
                  and lower(btrim(o.name)) = lower(btrim(ul_txt(r.raw,'zone')))
   where r.batch_id = p_batch
  on conflict (client_id, code) do update
    set name = excluded.name, address = excluded.address,
        op_node_id = excluded.op_node_id, status = excluded.status,
        -- where a branch is stays whatever geography already knew; this file
        -- says who runs it, not where it is
        effective_from = coalesce(excluded.effective_from, branch.effective_from),
        updated_at = now();

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'CLIENTS_UPLOADED', 'upload_batch', p_batch::text,
          jsonb_build_object('rows', (select count(*) from upload_row where batch_id = p_batch)));
end $$;

update upload_column set rule =
  'Required. The operating zone that runs the branch - the same names as the '
  'zone column of the Geography file. An administrator can add one under '
  'Configuration, Locations.'
 where kind = 'Clients and branches' and name = 'zone';
