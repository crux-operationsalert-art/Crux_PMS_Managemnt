-- The Geography loader was upside down, and its duplicate rule refused the
-- only shape the file can have.
--
-- THE SHAPE. The live tree is ZONE -> STATE -> CITY: six compass zones at the
-- top, 37 states beneath them, 110 cities beneath those, with 1,407 branches
-- attached across all three levels. ua_geography built the opposite -- states
-- at the top with zones underneath -- so loading a real file would have grown
-- a second, contradictory hierarchy beside the one the branches hang off.
--
-- THE VOCABULARY. The file's `region` (East, South, North-East) is what
-- geo_node calls a ZONE. The file's `zone` (Kolkata, Amaravati, Patna) is the
-- OPERATING zone, which lives in op_node and is maintained under Configuration,
-- Locations. The loader was writing the operating zone into the geographic
-- zone level, which is how the two ever got confused. It is now recorded
-- alongside the place instead, in op_zone, and the tree is built from region.
--
-- THE DUPLICATE RULE. One row per city is the only sensible shape for this
-- file -- 57 rows covering 16 states -- so a zone necessarily repeats. The
-- validator partitioned on zone alone and refused every row after the first,
-- 50 of 57. A duplicate is the same region, state and city twice.
--
-- MOVING RATHER THAN SPLITTING. A state already on the master under a
-- different region is re-parented, not duplicated. Branches point at the
-- state's own id, so moving it keeps all of them and splitting it would strand
-- half. Every move is recorded in migration_review so it is a visible decision
-- rather than a silent one. The same applies to a near-duplicate spelling:
-- "Andaman and Nicobar Islands" is matched to the existing "...Island" instead
-- of becoming a second state with the branches divided between them.
--
-- Verified against the owner's own 57-row file: 57 of 57 validate, no state is
-- created twice, and the five states the file re-regions (Assam, Bihar,
-- Jharkhand, Chhattisgarh, Andaman) carry 139 branches between them, all of
-- which stay attached.

alter table geo_node add column if not exists op_zone text;
comment on column geo_node.op_zone is
  'The operating zone this place is served from, as named in the Geography '
  'file. The authoritative operating grouping is op_node; this is a label.';

-- East, West, North, South, Central, North East -- however they were typed.
create or replace function geo_region(p_in text)
returns text language sql immutable as $$
  select case lower(btrim(regexp_replace(coalesce(p_in,''), '[\s_-]+', ' ', 'g')))
    when 'east' then 'East' when 'west' then 'West'
    when 'north' then 'North' when 'south' then 'South'
    when 'central' then 'Central'
    when 'north east' then 'North East' when 'northeast' then 'North East'
    when 'ne' then 'North East'
    else null end;
$$;

create or replace function uv_geography(p_batch uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  update upload_row set error = null where batch_id = p_batch and error is not null;

  update upload_row r set error = e.msg from (
    select r2.id, nullif(concat_ws('; ',
      case when ul_txt(r2.raw,'region') is null
           then 'region is required - it is the top of the geography tree'
           when geo_region(ul_txt(r2.raw,'region')) is null
           then 'region must be East, West, North, South, Central or North East' end,
      case when ul_txt(r2.raw,'zone') is null then 'zone is required' end,
      case when ul_txt(r2.raw,'state') is null then 'state is required' end
    ), '') as msg
    from upload_row r2 where r2.batch_id = p_batch
  ) e where r.id = e.id and e.msg is not null;

  -- A duplicate is the same place twice. The same zone twice is the file
  -- doing its job: one row per city, many cities to a zone.
  update upload_row r set error = coalesce(r.error || '; ', '') ||
         'the same region, state and city appear on an earlier line'
    from (select id, row_number() over (
            partition by geo_region(ul_txt(raw,'region')),
                         lower(btrim(ul_txt(raw,'state'))),
                         lower(btrim(coalesce(ul_txt(raw,'city'),'')))
            order by row_no) rn
            from upload_row where batch_id = p_batch and error is null) d
   where r.id = d.id and d.rn > 1;

  -- A state cannot sit in two regions at once, so the file has to pick one.
  update upload_row r set error = coalesce(r.error || '; ', '') ||
         ul_txt(r.raw,'state') || ' is put in more than one region by this file'
    from (select a.id from upload_row a
            join upload_row b on a.batch_id = b.batch_id and a.id <> b.id
             and lower(btrim(ul_txt(a.raw,'state'))) = lower(btrim(ul_txt(b.raw,'state')))
             and geo_region(ul_txt(a.raw,'region')) is distinct from geo_region(ul_txt(b.raw,'region'))
           where a.batch_id = p_batch and a.error is null and b.error is null) x
   where r.id = x.id;
end $$;

create or replace function ua_geography(p_batch uuid, p_actor uuid)
returns void language plpgsql set search_path = public, extensions as $$
declare r record; v_zone uuid; v_state uuid; v_city uuid; v_old uuid;
        v_moved int := 0; v_spelling int := 0; v_city_moved int := 0;
begin
  for r in select row_no, raw from upload_row where batch_id = p_batch order by row_no loop

    -- 1 · the region is the top of the tree
    select id into v_zone from geo_node
     where level = 'ZONE' and lower(name) = lower(geo_region(ul_txt(r.raw,'region')));
    if v_zone is null then
      insert into geo_node (level, name) values ('ZONE', geo_region(ul_txt(r.raw,'region')))
      returning id into v_zone;
    end if;

    -- 2 · the state, found wherever it already sits
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

    -- 3 · the city under its state
    if ul_txt(r.raw,'city') is not null then
      select id into v_city from geo_node
       where level = 'CITY' and parent_id = v_state
         and lower(btrim(name)) = lower(btrim(ul_txt(r.raw,'city')));

      if v_city is null then
        -- the same city under a different state is that city, moved
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
          jsonb_build_object('states_moved', v_moved,
                             'cities_moved', v_city_moved,
                             'spellings_matched', v_spelling));
end $$;

-- the template should ask for what the loader reads, and say what each is for
update upload_column set rule =
  'Required. East, West, North, South, Central or North East. This is the top '
  'of the geography tree.'
 where kind = 'Geography' and name = 'region';
update upload_column set rule =
  'Required. The operating zone this place is served from - Pune, Kolkata, '
  'Amaravati. It repeats down the file: one row per city.'
 where kind = 'Geography' and name = 'zone';
update upload_column set rule = 'Required.'
 where kind = 'Geography' and name = 'state';
update upload_column set rule = 'Optional. One row per city is the usual shape.'
 where kind = 'Geography' and name = 'city';
