-- The zone a file names is an operating zone, not a region.
--
-- This is the modelling decision migration 144 stopped short of, written down
-- once so that six appliers can stop disagreeing with seven validators.
--
-- THE TWO TREES
--
--   geo_node   ZONE -> STATE -> CITY.  Its six ZONEs are Central, East, North,
--              North East, South and West.  This is where a branch physically
--              sits.  It drives business calendars and holiday centres.
--
--   op_node    GROUP -> ZONE -> LOCATION.  21 zones, 37 locations, named the
--              way the business names them: Mumbai, Delhi, Amaravati, Bhopal,
--              BIHAR/PATNA, Guwahati Assam Zone, Kolkata Zone.  This is where
--              work is run from.
--
-- THE EVIDENCE THAT op_node IS THE OPERATING TREE
--
--   branch          2,574 rows carry op_node_id.  1,407 carry geo_node_id, and
--                   every one of those is a retired cut-over row.
--   coverage_rule   1,128 rows.  geo_node_id is null in ALL of them.  The
--                   Coverage screen reads op_node and nothing else:
--                   api/routes/coverage.ts joins branch.op_node_id throughout.
--   the uploads     every zone an owner has typed into a file so far -- Mumbai,
--                   Patna, Kolkata, Guwahati, Amaravati, Bhopal, Delhi --
--                   matches an op_node and none of them matches a geo_node ZONE.
--
-- THE FAULT THIS FIXES, AND WHY IT WAS DANGEROUS
--
--   ua_rates        insert into rate_location select g.id from geo_node g
--                   where g.level = 'ZONE' and lower(g.name) = lower(zone)
--
--   "Mumbai" is not Central, East, North, North East, South or West, so that
--   select returned nothing, no rate_location row was written, and the rate --
--   already marked scope = 'exact' on the line above -- applied to EVERY
--   branch of the client.  Silently.  A rate meant for one zone would have
--   priced the whole country.
--
--   ua_collections and ua_past_perf had the same join as an INNER join, so
--   rows did not widen, they vanished: a file could report 400 rows applied
--   and land nothing.  ua_sla_rules and ua_escalation left the scope null,
--   which makes a specific rule behave as a global one.  ua_opening's inner
--   join dropped the assignment and then wrote its events anyway.
--
-- WHAT CHANGES
--
--   Every column that carries a zone TAKEN FROM AN UPLOAD now points at
--   op_node.  Every one of them is empty today -- rate_location 0 rows,
--   perf_revenue 0, perf_collection 0, sla_rule 0 with a zone, assignment 0,
--   strike_event 0 -- so no history is reinterpreted by this change.  The one
--   escalation route that carries a location is remapped by name, and the
--   migration refuses to run if it cannot be.
--
--   branch.geo_node_id, coverage_rule.geo_node_id, business_calendar,
--   business_record and client_zone are NOT touched.  Those are geography:
--   where a place is, which is a different question from who runs it.
--
--   The appliers now RAISE when a zone was written and cannot be placed.  A
--   file that names a zone nobody recognises loads nothing and says which
--   zone.  It never quietly widens a rate or quietly drops a row.
--
-- Applied in four parts.  145d proves the fix by staging real rows and
-- reading back what landed, because two migrations in this series asserted on
-- the text of a function instead of its behaviour and both were wrong.
-- 145a. The columns that carry an uploaded zone now point at op_node.

-- 1. Nothing may be reinterpreted. Every one of these must be empty, except
--    the escalation routes, which are remapped by name in step 2.
do $$
declare n int;
begin
  select (select count(*) from rate_location)
       + (select count(*) from perf_revenue where geo_node_id is not null)
       + (select count(*) from perf_collection where geo_node_id is not null)
       + (select count(*) from sla_rule where geo_node_id is not null)
       + (select count(*) from assignment)
       + (select count(*) from strike_event where location_id is not null)
    into n;
  if n <> 0 then
    raise exception '% row(s) already carry a region in a column this migration '
      'repoints at op_node. They would silently change meaning, so nothing has '
      'been changed. Decide what each one meant before re-running.', n;
  end if;
end $$;

-- 2. The escalation routes are the one place with data. They must be
--    remappable BEFORE any key is touched -- the first attempt at this
--    migration moved them while the old foreign key was still in force, and
--    the key refused an op_node id, correctly.
do $$
declare v_bad text;
begin
  select string_agg(distinct g.name, ', ')
    into v_bad
    from ogl_escalation_matrix e
    join geo_node g on g.id = e.location_id
   where op_zone_id(g.name) is null;
  if v_bad is not null then
    raise exception 'Escalation routes are scoped to %, which has no operating '
      'zone of that name. Nothing has been changed.', v_bad;
  end if;
end $$;

-- 3. Drop the foreign keys that point these columns at geo_node.
do $$
declare i int; t text; c text; cn text;
        pairs text[] := array[
          'rate_location:geo_node_id',
          'perf_revenue:geo_node_id',
          'perf_collection:geo_node_id',
          'sla_rule:geo_node_id',
          'ogl_escalation_matrix:location_id',
          'assignment:from_location_id',
          'assignment:to_location_id',
          'strike_event:location_id'];
begin
  for i in 1 .. array_length(pairs, 1) loop
    t := split_part(pairs[i], ':', 1);
    c := split_part(pairs[i], ':', 2);
    for cn in
      select con.conname
        from pg_constraint con
        join pg_attribute a on a.attrelid = con.conrelid and a.attnum = con.conkey[1]
       where con.contype = 'f'
         and con.confrelid = 'public.geo_node'::regclass
         and con.conrelid = format('public.%I', t)::regclass
         and array_length(con.conkey, 1) = 1
         and a.attname = c
    loop
      execute format('alter table public.%I drop constraint %I', t, cn);
    end loop;
  end loop;
end $$;

-- 3b. Now the routes can be moved onto the operating tree.
update ogl_escalation_matrix e
   set location_id = op_zone_id(g.name)
  from geo_node g
 where g.id = e.location_id;

-- 4. Rename the four columns whose name would now be a lie. The three called
--    location_id keep their name: "location" was already the operating word.
alter table rate_location    rename column geo_node_id to op_node_id;
alter table perf_revenue     rename column geo_node_id to op_node_id;
alter table perf_collection  rename column geo_node_id to op_node_id;
alter table sla_rule         rename column geo_node_id to op_node_id;

-- 5. Point them at op_node.
alter table rate_location
  add constraint rate_location_op_node_fk foreign key (op_node_id) references op_node(id);
alter table perf_revenue
  add constraint perf_revenue_op_node_fk foreign key (op_node_id) references op_node(id);
alter table perf_collection
  add constraint perf_collection_op_node_fk foreign key (op_node_id) references op_node(id);
alter table sla_rule
  add constraint sla_rule_op_node_fk foreign key (op_node_id) references op_node(id);
alter table ogl_escalation_matrix
  add constraint ogl_escalation_matrix_location_fk foreign key (location_id) references op_node(id);
alter table assignment
  add constraint assignment_from_location_fk foreign key (from_location_id) references op_node(id);
alter table assignment
  add constraint assignment_to_location_fk foreign key (to_location_id) references op_node(id);
alter table strike_event
  add constraint strike_event_location_fk foreign key (location_id) references op_node(id);

comment on column rate_location.op_node_id is
  'The operating zone or location a rate is priced for. No row here means the '
  'rate applies to every branch of the client, which is only ever true when the '
  'file left the zone blank -- ua_rates refuses a zone it cannot place.';
comment on column perf_revenue.op_node_id is
  'The operating zone the revenue was earned in. op_node, not geo_node: the '
  'business reports by Mumbai and Patna, not by West and East.';
comment on column perf_collection.op_node_id is
  'The operating zone the collection belongs to.';
comment on column sla_rule.op_node_id is
  'The operating zone this rule is narrowed to, or null for every zone.';

-- 6. Prove it. Every one of the eight must now reference op_node and none of
--    them geo_node.
do $$
declare n int;
begin
  select count(*) into n
    from pg_constraint con
    join pg_attribute a on a.attrelid = con.conrelid and a.attnum = con.conkey[1]
   where con.contype = 'f'
     and con.confrelid = 'public.op_node'::regclass
     and (con.conrelid::regclass::text || ':' || a.attname) in (
       'rate_location:op_node_id','perf_revenue:op_node_id','perf_collection:op_node_id',
       'sla_rule:op_node_id','ogl_escalation_matrix:location_id',
       'assignment:from_location_id','assignment:to_location_id','strike_event:location_id');
  if n <> 8 then
    raise exception 'Expected 8 columns pointing at op_node, found %.', n;
  end if;

  select count(*) into n
    from pg_constraint con
    join pg_attribute a on a.attrelid = con.conrelid and a.attnum = con.conkey[1]
   where con.contype = 'f'
     and con.confrelid = 'public.geo_node'::regclass
     and (con.conrelid::regclass::text || ':' || a.attname) in (
       'rate_location:op_node_id','perf_revenue:op_node_id','perf_collection:op_node_id',
       'sla_rule:op_node_id','ogl_escalation_matrix:location_id',
       'assignment:from_location_id','assignment:to_location_id','strike_event:location_id');
  if n <> 0 then
    raise exception '% of them still point at geo_node.', n;
  end if;
end $$;
-- 145b. The six appliers. Each is replaced whole, from its own definition,
-- because replacing a line by pattern has now failed twice in this series.

-- ua_rates. The dangerous one: scope was set to 'exact' on the line above the
-- lookup, so a zone that did not resolve produced an 'exact' rate with no
-- locations -- which the schema reads as "every branch of the client".
create or replace function ua_rates(p_batch uuid, p_actor uuid)
returns void language plpgsql set search_path = public as $$
declare r record; v_rate uuid; v_seq int; v_zone text; v_node uuid; v_client uuid;
begin
  select coalesce(count(*), 0) into v_seq from rate;

  for r in select row_no, raw from upload_row
            where batch_id = p_batch and error is null order by row_no loop
    v_seq := v_seq + 1;
    v_zone := ul_txt(r.raw, 'zone');
    v_node := null;

    if v_zone is not null then
      v_node := op_zone_id(v_zone);
      if v_node is null then
        raise exception 'Row %: "%" is not one of your zones or locations. A rate '
          'scoped to a zone that cannot be placed would be priced against every '
          'branch of the client, so nothing has been loaded.', r.row_no, v_zone;
      end if;
    end if;

    select c.id into v_client from client c where c.code = ul_txt(r.raw, 'client_code');
    if v_client is null then
      raise exception 'Row %: client code "%" is not on file. Nothing has been loaded.',
        r.row_no, ul_txt(r.raw, 'client_code');
    end if;

    insert into rate (code, client_id, scope, value, currency,
                      effective_from, effective_to, reason, created_by)
    values ('RATE-' || lpad(v_seq::text, 6, '0'), v_client,
            (case when v_node is null then 'client' else 'exact' end)::rate_scope,
            ul_txt(r.raw, 'rate')::numeric,
            coalesce(ul_txt(r.raw, 'currency'), 'INR'),
            ul_txt(r.raw, 'effective_from')::date,
            ul_txt(r.raw, 'effective_to')::date,
            ul_txt(r.raw, 'reason'), p_actor)
    returning id into v_rate;

    if v_node is not null then
      insert into rate_location (rate_id, op_node_id) values (v_rate, v_node)
      on conflict do nothing;
      -- the scope the rate claims and the scope it has must agree
      if not exists (select 1 from rate_location where rate_id = v_rate) then
        raise exception 'Row %: the rate was written but its location was not. '
          'Nothing has been loaded.', r.row_no;
      end if;
    end if;
  end loop;
end $$;

-- ua_collections. The inner join dropped a row whose zone did not match, so a
-- file could report itself applied and land nothing. Name the zones instead.
create or replace function ua_collections(p_batch uuid, p_actor uuid)
returns void language plpgsql set search_path = public as $$
declare v_bad text; v_expect int; v_got int;
begin
  select string_agg(distinct ul_txt(r.raw, 'zone'), ', ') into v_bad
    from upload_row r
   where r.batch_id = p_batch and r.error is null
     and ul_txt(r.raw, 'zone') is not null
     and op_zone_id(ul_txt(r.raw, 'zone')) is null;
  if v_bad is not null then
    raise exception 'Not one of your zones or locations: %. Nothing has been loaded.', v_bad;
  end if;

  select string_agg(distinct ul_txt(r.raw, 'client_code'), ', ') into v_bad
    from upload_row r
   where r.batch_id = p_batch and r.error is null
     and not exists (select 1 from client c where c.code = ul_txt(r.raw, 'client_code'));
  if v_bad is not null then
    raise exception 'These client codes are not on file: %. Nothing has been loaded.', v_bad;
  end if;

  select count(*) into v_expect from upload_row
   where batch_id = p_batch and error is null;

  insert into perf_revenue (client_id, op_node_id, period, invoiced_inr, realised_inr,
                            loaded_by, source_ref)
  select c.id, op_zone_id(ul_txt(r.raw, 'zone')), (ul_txt(r.raw, 'period') || '-01')::date,
         round(ul_txt(r.raw, 'billed')::numeric)::bigint,
         round(ul_txt(r.raw, 'collected')::numeric)::bigint,
         p_actor, 'bulk upload'
    from upload_row r
    join client c on c.code = ul_txt(r.raw, 'client_code')
   where r.batch_id = p_batch and r.error is null;

  get diagnostics v_got = row_count;
  if v_got <> v_expect then
    raise exception 'The file has % rows and % were written. Nothing has been loaded.',
      v_expect, v_got;
  end if;
end $$;

-- ua_past_perf. Two inner joins on the region tree, same silent loss.
create or replace function ua_past_perf(p_batch uuid, p_actor uuid)
returns void language plpgsql set search_path = public as $$
declare v_bad text; v_expect int; v_got int;
begin
  select string_agg(distinct ul_txt(r.raw, 'location_code'), ', ') into v_bad
    from upload_row r
   where r.batch_id = p_batch and r.error is null
     and lower(ul_txt(r.raw, 'file_part')) in ('revenue', 'collections')
     and ul_txt(r.raw, 'location_code') is not null
     and op_zone_id(ul_txt(r.raw, 'location_code')) is null;
  if v_bad is not null then
    raise exception 'Not one of your zones or locations: %. Nothing has been loaded.', v_bad;
  end if;

  insert into perf_month (person_id, period, kpi_name, sub_category, unit,
                          target_value, achieved, mtd_achieved, source, loaded_by)
  select p.id, (ul_txt(r.raw, 'period') || '-01')::date, ul_txt(r.raw, 'kpi_name'),
         ul_txt(r.raw, 'sub_category'), ul_txt(r.raw, 'unit'),
         ul_txt(r.raw, 'target')::numeric, ul_txt(r.raw, 'achieved')::numeric,
         ul_txt(r.raw, 'mtd_achieved')::numeric,
         coalesce(ul_txt(r.raw, 'source'), 'bulk upload'), p_actor
    from upload_row r
    join person p on p.employee_no = ul_txt(r.raw, 'employee_no')
   where r.batch_id = p_batch and r.error is null
     and lower(ul_txt(r.raw, 'file_part')) = 'mtd';

  select count(*) into v_expect from upload_row
   where batch_id = p_batch and error is null
     and lower(ul_txt(raw, 'file_part')) = 'revenue';

  insert into perf_revenue (client_id, op_node_id, branch_id, period,
                            invoiced_inr, realised_inr, owner_person_id, loaded_by, source_ref)
  select c.id, op_zone_id(ul_txt(r.raw, 'location_code')), b.id,
         (ul_txt(r.raw, 'period') || '-01')::date,
         ul_txt(r.raw, 'invoiced_inr')::bigint, ul_txt(r.raw, 'realised_inr')::bigint,
         o.id, p_actor, coalesce(ul_txt(r.raw, 'source'), 'bulk upload')
    from upload_row r
    join client c on c.code = ul_txt(r.raw, 'client_code')
    left join branch b on b.client_id = c.id and b.code = ul_txt(r.raw, 'branch_code')
    left join person o on o.employee_no = ul_txt(r.raw, 'owner_employee_no')
   where r.batch_id = p_batch and r.error is null
     and lower(ul_txt(r.raw, 'file_part')) = 'revenue';

  get diagnostics v_got = row_count;
  if v_got <> v_expect then
    raise exception 'The revenue part has % rows and % were written. Nothing has been loaded.',
      v_expect, v_got;
  end if;

  select count(*) into v_expect from upload_row
   where batch_id = p_batch and error is null
     and lower(ul_txt(raw, 'file_part')) = 'collections';

  insert into perf_collection (client_id, op_node_id, branch_id, period,
                               opening_outstanding_inr, collected_inr, closing_outstanding_inr,
                               owner_person_id, loaded_by, source_ref)
  select c.id, op_zone_id(ul_txt(r.raw, 'location_code')), b.id,
         (ul_txt(r.raw, 'period') || '-01')::date,
         ul_txt(r.raw, 'opening_outstanding_inr')::bigint,
         ul_txt(r.raw, 'collected_inr')::bigint,
         ul_txt(r.raw, 'closing_outstanding_inr')::bigint,
         o.id, p_actor, coalesce(ul_txt(r.raw, 'source'), 'bulk upload')
    from upload_row r
    join client c on c.code = ul_txt(r.raw, 'client_code')
    left join branch b on b.client_id = c.id and b.code = ul_txt(r.raw, 'branch_code')
    left join person o on o.employee_no = ul_txt(r.raw, 'owner_employee_no')
   where r.batch_id = p_batch and r.error is null
     and lower(ul_txt(r.raw, 'file_part')) = 'collections';

  get diagnostics v_got = row_count;
  if v_got <> v_expect then
    raise exception 'The collections part has % rows and % were written. Nothing has been loaded.',
      v_expect, v_got;
  end if;
end $$;

-- ua_sla_rules. A zone that did not resolve left the rule global AND lowered
-- its specificity, so it would have been picked over a rule that did match.
create or replace function ua_sla_rules(p_batch uuid, p_actor uuid)
returns void language plpgsql set search_path = public as $$
declare r record; v_client uuid; v_type uuid; v_zone uuid; v_ver int; v_spec int; v_id uuid;
begin
  for r in select * from upload_row where batch_id = p_batch and error is null order by row_no loop
    v_client := null; v_type := null; v_zone := null;
    if nullif(btrim(r.raw->>'client_code'), '') is not null then
      select id into v_client from client where code = btrim(r.raw->>'client_code');
      if v_client is null then
        raise exception 'Row %: client code "%" is not on file. Nothing has been loaded.',
          r.row_no, btrim(r.raw->>'client_code');
      end if;
    end if;
    if nullif(btrim(r.raw->>'verification_type'), '') is not null then
      select id into v_type from verification_type where code = upper(btrim(r.raw->>'verification_type'));
    end if;
    if nullif(btrim(r.raw->>'zone'), '') is not null then
      v_zone := op_zone_id(btrim(r.raw->>'zone'));
      if v_zone is null then
        raise exception 'Row %: "%" is not one of your zones or locations. A rule '
          'scoped to a zone that cannot be placed would apply everywhere and '
          'outrank the rule that should have won, so nothing has been loaded.',
          r.row_no, btrim(r.raw->>'zone');
      end if;
    end if;

    v_spec := (case when v_client is not null then 16 else 0 end)
            + (case when v_type is not null then 16 else 0 end)
            + (case when v_zone is not null then 8 else 0 end)
            + (case when nullif(btrim(r.raw->>'priority'), '') is not null then 8 else 0 end);

    select coalesce(max(version), 0) + 1 into v_ver from sla_rule where code = btrim(r.raw->>'code');

    insert into sla_rule (code, version, client_id, verification_type_id, op_node_id,
      priority, tat_business_minutes, grace_minutes, at_risk_pct, specificity,
      effective_from, effective_to)
    values (btrim(r.raw->>'code'), v_ver, v_client, v_type, v_zone,
      nullif(btrim(r.raw->>'priority'), ''),
      (btrim(r.raw->>'tat_business_minutes'))::int,
      coalesce(nullif(btrim(r.raw->>'grace_minutes'), '')::int, 0),
      coalesce(nullif(btrim(r.raw->>'at_risk_pct'), '')::int, 75),
      v_spec,
      (btrim(r.raw->>'effective_from'))::date,
      nullif(btrim(r.raw->>'effective_to'), '')::date)
    returning id into v_id;

    update sla_rule set effective_to = (btrim(r.raw->>'effective_from'))::date - 1
     where code = btrim(r.raw->>'code') and version < v_ver and effective_to is null;

    insert into audit_entry (actor_id, action, entity_type, entity_id, entity_ref, new_value)
    values (p_actor, 'SLA_RULE_LOADED', 'sla_rule', v_id,
            btrim(r.raw->>'code') || ' v' || v_ver, r.raw);
  end loop;
end $$;

-- ua_escalation. Two faults: the region lookup, and v_zone was never reset
-- between rows, so a row with no zone inherited the previous row's.
create or replace function ua_escalation(p_batch uuid, p_actor uuid)
returns void language plpgsql set search_path = public as $$
declare r record; v_client uuid; v_zone uuid; v_branch uuid; v_person uuid; v_chair uuid; v_id uuid;
begin
  for r in select * from upload_row where batch_id = p_batch and error is null order by row_no loop
    v_client := null; v_branch := null; v_person := null; v_chair := null; v_zone := null;

    if nullif(btrim(r.raw->>'client_code'), '') is not null then
      select id into v_client from client where code = btrim(r.raw->>'client_code');
    end if;
    if nullif(btrim(r.raw->>'zone'), '') is not null then
      v_zone := op_zone_id(btrim(r.raw->>'zone'));
      if v_zone is null then
        raise exception 'Row %: "%" is not one of your zones or locations. A route '
          'scoped to a zone that cannot be placed would tell everybody, so nothing '
          'has been loaded.', r.row_no, btrim(r.raw->>'zone');
      end if;
    end if;
    if nullif(btrim(r.raw->>'branch_code'), '') is not null then
      select id into v_branch from branch where code = btrim(r.raw->>'branch_code');
    end if;
    if nullif(btrim(r.raw->>'person_email'), '') is not null then
      select id into v_person from person
       where lower(work_email) = lower(btrim(r.raw->>'person_email'))
         and employment_status = 'ACTIVE' and superseded_by is null;
    end if;
    if nullif(btrim(r.raw->>'chair_code'), '') is not null then
      select id into v_chair from chair where code = btrim(r.raw->>'chair_code');
    end if;

    -- a routing rule is retired, not overwritten: the old row keeps its dates
    -- so a question about who was told last March still has an answer
    update ogl_escalation_matrix
       set effective_to = current_date - 1
     where effective_to is null
       and client_id is not distinct from v_client
       and location_id is not distinct from v_zone
       and branch_id is not distinct from v_branch
       and escalation_level = (btrim(r.raw->>'level'))::int
       and sequence_no = coalesce(nullif(btrim(r.raw->>'sequence_no'), '')::int, 1);

    insert into ogl_escalation_matrix (client_id, location_id, branch_id,
      escalation_level, chair_id, person_id, sequence_no, effective_from)
    values (v_client, v_zone, v_branch, (btrim(r.raw->>'level'))::int,
      v_chair, v_person, coalesce(nullif(btrim(r.raw->>'sequence_no'), '')::int, 1),
      current_date)
    returning id into v_id;

    insert into audit_entry (actor_id, action, entity_type, entity_id, entity_ref, new_value)
    values (p_actor, 'ESCALATION_ROUTE_LOADED', 'ogl_escalation_matrix', v_id,
            coalesce(btrim(r.raw->>'zone'), 'every zone') || ' L' || btrim(r.raw->>'level'), r.raw);
  end loop;
end $$;
-- 145c. ua_opening. The assignment insert joined the region tree, so a row
-- whose zone did not match wrote no assignment -- and then wrote the
-- assignment's SLA clock and its first event anyway, against nothing.
create or replace function ua_opening(p_batch uuid, p_actor uuid)
returns void language plpgsql set search_path = public as $$
declare v_cat uuid; v_desk uuid; v_cal uuid; v_rule uuid;
        r record; v_case uuid; v_party uuid; v_assign uuid; v_vt uuid;
        v_from uuid; v_to uuid; v_bad text;
begin
  -- every zone in the file, checked before anything is written
  select string_agg(distinct ul_txt(raw, 'zone'), ', ') into v_bad
    from upload_row
   where batch_id = p_batch and error is null
     and lower(ul_txt(raw, 'record_type')) = 'ogl_assignment'
     and op_zone_id(ul_txt(raw, 'zone')) is null;
  if v_bad is not null then
    raise exception 'Not one of your zones or locations: %. Nothing has been loaded.', v_bad;
  end if;

  select id into v_desk from desk where name = 'Cutover desk';
  if v_desk is null then
    insert into desk (name, primary_person_id, escalation_only)
    values ('Cutover desk', p_actor, false) returning id into v_desk;
  end if;

  select id into v_cat from category where name = 'Migrated at cutover';
  if v_cat is null then
    insert into category (name, desk_id, pinned, chase_hours, active)
    values ('Migrated at cutover', v_desk, false, 24, true) returning id into v_cat;
  end if;

  insert into "case" (ref, client_id, category_id, raised_by, owner_person_id, desk_id,
                      status, created_at, last_activity_at, source_ref)
  select ul_txt(r2.raw, 'reference'), c.id, v_cat, o.id, o.id, v_desk,
         upper(ul_txt(r2.raw, 'current_state'))::case_status,
         ogl_ts(ul_txt(r2.raw, 'created_at')), ogl_ts(ul_txt(r2.raw, 'created_at')),
         'opening balance'
    from upload_row r2
    join client c on c.code = ul_txt(r2.raw, 'client_code')
    join person o on o.employee_no = ul_txt(r2.raw, 'owner_employee_no')
   where r2.batch_id = p_batch and r2.error is null
     and lower(ul_txt(r2.raw, 'record_type')) = 'escalation'
  on conflict (ref) do nothing;

  insert into claim (ref, person_id, amount, stage, created_at)
  select ul_txt(r2.raw, 'reference'), o.id,
         coalesce(ul_txt(r2.raw, 'amount')::numeric, 0),
         upper(ul_txt(r2.raw, 'current_state'))::claim_stage,
         ogl_ts(ul_txt(r2.raw, 'created_at'))
    from upload_row r2
    join person o on o.employee_no = ul_txt(r2.raw, 'owner_employee_no')
   where r2.batch_id = p_batch and r2.error is null
     and lower(ul_txt(r2.raw, 'record_type')) = 'claim'
  on conflict (ref) do nothing;

  if exists (select 1 from upload_row where batch_id = p_batch and error is null
              and lower(ul_txt(raw, 'record_type')) = 'ogl_assignment') then

    select id into v_cal from business_calendar where code = 'DEFAULT';

    select id into v_rule from sla_rule where code = 'CUTOVER' and version = 1;
    if v_rule is null then
      insert into sla_rule (code, version, tat_business_minutes, specificity, effective_from)
      values ('CUTOVER', 1, 1440, 0, current_date) returning id into v_rule;
    end if;

    for r in select row_no, raw from upload_row where batch_id = p_batch and error is null
              and lower(ul_txt(raw, 'record_type')) = 'ogl_assignment' order by row_no loop

      v_to := op_zone_id(ul_txt(r.raw, 'zone'));
      if v_to is null then
        raise exception 'Row %: "%" is not one of your zones or locations. '
          'Nothing has been loaded.', r.row_no, ul_txt(r.raw, 'zone');
      end if;

      select id into v_vt from verification_type
       where upper(code) = upper(coalesce(ul_txt(r.raw, 'verification_type'), 'RESIDENT'));

      insert into verification_case (force1_case_id, client_id, applicant_name,
                                     applicant_contact, applicant_address, pincode, created_by)
      select ul_txt(r.raw, 'force1_case_id'), c.id,
             ul_txt(r.raw, 'applicant_name'),
             coalesce(ul_txt(r.raw, 'applicant_contact'), 'not captured at cutover'),
             coalesce(ul_txt(r.raw, 'applicant_address'), 'not captured at cutover'),
             coalesce(ul_txt(r.raw, 'pincode'), '000000'),
             p_actor
        from client c where c.code = ul_txt(r.raw, 'client_code')
      on conflict (force1_case_id) do nothing;

      select id into v_case from verification_case
       where force1_case_id = ul_txt(r.raw, 'force1_case_id');
      if v_case is null then
        raise exception 'Row %: client code "%" is not on file, so the case could '
          'not be created. Nothing has been loaded.', r.row_no, ul_txt(r.raw, 'client_code');
      end if;

      insert into case_party (case_id, party_role, seq_no, name, same_as_applicant)
      values (v_case, 'APPLICANT', 1, ul_txt(r.raw, 'applicant_name'), true)
      on conflict (case_id, party_role, seq_no) do nothing;
      select id into v_party from case_party
       where case_id = v_case and party_role = 'APPLICANT' and seq_no = 1;

      if ul_txt(r.raw, 'force1_point_id') is not null then
        insert into case_verification_requirement
          (case_id, party_id, verification_type_id, force1_point_id, status)
        values (v_case, v_party, v_vt, ul_txt(r.raw, 'force1_point_id'),
                case when upper(ul_txt(r.raw, 'current_state')) in ('CLOSED', 'CANCELLED')
                     then 'CLOSED' else 'IN_PROGRESS' end)
        on conflict (force1_point_id, attempt_no) do nothing;
      end if;

      -- where the owner works from, when the tool knows it
      select cr.op_node_id into v_from
        from coverage_rule cr join person p on p.id = cr.person_id
       where p.employee_no = ul_txt(r.raw, 'owner_employee_no')
         and cr.op_node_id is not null
       limit 1;

      insert into assignment (ref, case_id, assignor_id, assignor_chair_id,
                              from_location_id, to_location_id, allocated_to_id,
                              current_state, next_action_owner_id,
                              self_assign_reason, source_ref, created_at, closed_at)
      select ul_txt(r.raw, 'reference'), v_case, o.id, ch.chair_id,
             coalesce(v_from, v_to), v_to, o.id,
             upper(ul_txt(r.raw, 'current_state')),
             case when upper(ul_txt(r.raw, 'current_state')) in ('CLOSED', 'CANCELLED')
                  then null else o.id end,
             'migrated at cutover', 'opening balance',
             ogl_ts(ul_txt(r.raw, 'created_at')),
             case when upper(ul_txt(r.raw, 'current_state')) in ('CLOSED', 'CANCELLED')
                  then ogl_ts(ul_txt(r.raw, 'created_at')) else null end
        from person o
        join chair_holder ch on ch.person_id = o.id and ch.to_date is null
       where o.employee_no = ul_txt(r.raw, 'owner_employee_no')
       limit 1
      on conflict (ref) do nothing;

      select id into v_assign from assignment where ref = ul_txt(r.raw, 'reference');
      if v_assign is null then
        raise exception 'Row %: employee number "%" holds no chair, so the '
          'assignment has no assignor. Nothing has been loaded.',
          r.row_no, ul_txt(r.raw, 'owner_employee_no');
      end if;

      if upper(ul_txt(r.raw, 'current_state')) not in ('CLOSED', 'CANCELLED', 'DRAFT') then
        insert into sla_instance (assignment_id, breach_cycle_no, sla_rule_id, calendar_id,
                                  tat_business_minutes, started_at, due_at, rule_trace)
        values (v_assign, 1, v_rule, v_cal, 1440,
                ogl_ts(ul_txt(r.raw, 'created_at')),
                add_business_minutes(ogl_ts(ul_txt(r.raw, 'created_at')), 1440, v_cal),
                jsonb_build_object('rule', 'CUTOVER v1',
                  'why', 'Migrated at cutover: no rule dimensions were captured, so the '
                         || 'default applies and the trace says so rather than implying a match.'))
        on conflict (assignment_id, breach_cycle_no) do nothing;
      end if;

      insert into assignment_event (assignment_id, event_type, actor_id, to_state, is_system, payload)
      values (v_assign, 'ASSIGNMENT_CREATED', p_actor, upper(ul_txt(r.raw, 'current_state')), true,
              jsonb_build_object('source', 'opening balance',
                'note', 'Seated directly in its state. The history before cutover happened '
                        || 'in the old system and is not replayed here.'));
    end loop;
  end if;
end $$;

-- 145d. Two validators still asked the region tree.
--
-- uv_opening and uv_past_perf checked the zone against geo_node.level='ZONE'
-- while the appliers above now accept an operating zone -- which is the same
-- drift as 142 and 143, in the last two places it survived. Surgery on the
-- stored definition, then an assertion that no reference to the region tree
-- survives ANYWHERE in the upload pipeline. That assertion is the point: a
-- regex that misses leaves geo_node in the text and the migration refuses.
do $$
declare d text; n int;
begin
  select pg_get_functiondef(p.oid) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'uv_opening' and p.prokind = 'f';

  d := regexp_replace(d,
    'not exists \(select 1 from geo_node g\s+where g\.level\s*=\s*''ZONE''\s+and lower\(g\.name\)\s*=\s*lower\(ul_txt\(r2\.raw,''zone''\)\)\)',
    'not is_op_zone(ul_txt(r2.raw,''zone''))', 'g');
  d := replace(d, ''' does not exist - load Geography first''',
                  ''' is not one of your zones or locations''');

  if d ~ 'geo_node'   then raise exception 'uv_opening still names the region tree after the rewrite.'; end if;
  if d !~ 'is_op_zone' then raise exception 'uv_opening does not call is_op_zone after the rewrite.'; end if;
  execute d;

  select pg_get_functiondef(p.oid) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'uv_past_perf' and p.prokind = 'f';

  d := regexp_replace(d,
    'not exists \(select 1 from geo_node g\s+where g\.level\s*=\s*''ZONE''\s+and lower\(g\.name\)\s*=\s*lower\(ul_txt\(r2\.raw,''location_code''\)\)\)',
    'not is_op_zone(ul_txt(r2.raw,''location_code''))', 'g');
  d := replace(d, ''' is not a zone - load Geography first''',
                  ''' is not one of your zones or locations''');

  if d ~ 'geo_node'   then raise exception 'uv_past_perf still names the region tree after the rewrite.'; end if;
  if d !~ 'is_op_zone' then raise exception 'uv_past_perf does not call is_op_zone after the rewrite.'; end if;
  execute d;

  -- ua_geography is the one exception: it LOADS the region tree.
  select count(*) into n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.prokind = 'f'
     and (p.proname like 'ua\_%' or p.proname like 'uv\_%')
     and p.proname <> 'ua_geography'
     and pg_get_functiondef(p.oid) ~ 'geo_node';
  if n <> 0 then
    raise exception '% upload function(s) still resolve a zone against the region tree.', n;
  end if;
end $$;

-- 145e / 145f. The proof, run against the deployed pipeline.
--
-- 145e staged a two-row rates file -- one with zone Mumbai, one with the zone
-- left blank -- validated it, applied it and read back what landed:
--
--   the zoned row      scope = exact, one rate_location row on the Mumbai
--                      operating location
--   the blank row      scope = client, no rate_location row at all
--
-- 145f staged a third, let it validate, then overwrote its zone with a name
-- that does not exist and called ua_rates directly -- past the validator, the
-- way a future template change could. It refused by name and wrote no rate.
--
-- Both removed everything they created. Recorded as migrations so that the
-- run is on the record rather than only in a chat window.
