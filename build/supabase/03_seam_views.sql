-- Applied to the live database 2026-09-15 as migration crux_seam_views_for_prototype.
--
-- The application reads through a generic data seam that asks for tables in
-- its own shape: string ids, its own field names, and in one case its own
-- meaning -- the seam's "assignment" is client x zone x handler coverage,
-- which this database calls coverage_rule.
--
-- These views present the live normalised data in exactly that shape, so the
-- application needs no change (Rule Zero holds: no screen, view model or
-- calculation is touched). Ids are uuid::text -- the app treats ids as opaque
-- strings and never parses a prefix, so they need only be stable and
-- consistent, which uuids are.
--
-- Reading is through the API only. anon and authenticated are revoked, so a
-- browser key cannot reach these even if RLS on a base table were wrong.

create schema if not exists seam;

create or replace view seam.geo_zone as
select g.id::text as id, g.name as name, g.group_name as "group",
       g.region as region, (g.level = 'ZONE') as is_aggregate
from public.geo_node g;

create or replace view seam.client as
select c.id::text as id, c.code as code, c.name as name from public.client c;

create or replace view seam.holiday as
select h.day as date, h.name as name, h.applies_to as scope, h.confirmed as confirmed
from public.holiday h;

create or replace view seam.person as
select p.id::text as id, p.full_name as name,
       coalesce(ch.title, d.title) as chair,
       cov.geo_node_id::text as zone_id,
       p.manager_id::text as reports_to,
       (sr.row_id is not null) as is_sample
from public.person p
left join public.designation d on d.id = p.designation_id
left join public.chair_holder chh on chh.person_id = p.id and chh.to_date is null and chh.is_primary
left join public.chair ch on ch.id = chh.chair_id
left join lateral (
  select cr.geo_node_id from public.coverage_rule cr
   where cr.person_id = p.id and cr.geo_node_id is not null
     and (cr.effective_to is null or cr.effective_to >= current_date)
   order by cr.effective_from desc nulls last limit 1) cov on true
left join public.sample_row sr on sr.table_name = 'person' and sr.row_id = p.id;

create or replace view seam.assignment as
select c.id::text as id, c.geo_node_id::text as zone_id, c.client_id::text as client_id,
       c.person_id::text as person_id, lh.person_id::text as location_head_id,
       c.effective_from as effective_from, c.effective_to as effective_to,
       (sr.row_id is not null) as is_sample
from public.coverage_rule c
left join lateral (
  select h.person_id from public.coverage_rule h
   where h.role = 'LOCATION_HEAD'
     and h.client_id is not distinct from c.client_id
     and h.geo_node_id is not distinct from c.geo_node_id
     and (h.effective_to is null or h.effective_to >= current_date)
   limit 1) lh on true
left join public.sample_row sr on sr.table_name = 'coverage_rule' and sr.row_id = c.id
where c.role <> 'LOCATION_HEAD' or c.role is null;

create or replace view seam.business_record as
select b.id::text as id, b.period as period, b.geo_node_id::text as zone_id,
       b.client_id::text as client_id, b.mtd as mtd, b.revenue as revenue,
       null::numeric as projected_expense, b.source_ref as src
from public.business_record b;

create or replace view seam.rate as
select r.id::text || coalesce('#' || rl.geo_node_id::text, '') as id,
       r.client_id::text as client_id, rl.geo_node_id::text as zone_id,
       r.scope::text as scope, r.value as value,
       r.effective_from as effective_from, r.effective_to as effective_to,
       r.status as origin, null::int as months_observed,
       null::int as months_of_history, r.reason as note
from public.rate r
left join public.rate_location rl on rl.rate_id = r.id;

-- Multipliers are a commercial choice. No rows in forecast_config means no
-- scenarios, rather than a default invented here.
create or replace view seam.forecast_scenario as
select s->>'key' as key, s->>'label' as label,
       (s->>'multiplier')::numeric as multiplier,
       s->>'stance' as stance, s->>'source' as source
from public.forecast_config f
cross join lateral jsonb_array_elements(f.scenarios) s;

-- sheet_* is day-10 revenue times each multiplier: the arithmetic the source
-- sheet did in columns M/N/O/P. live_addition has no source in this schema.
create or replace view seam.tenday_snapshot as
select b.id::text as id, b.period as period, g.name as location,
       b.day10 as day10_revenue, b.revenue as actual_revenue,
       null::numeric as live_addition,
       b.day10 * 5 as sheet_x5, b.day10 * 4 as sheet_x4,
       b.day10 * 3.5 as sheet_x35, b.day10 * 3.25 as sheet_x325,
       b.source_ref as src
from public.business_record b
left join public.geo_node g on g.id = b.geo_node_id
where b.day10 is not null;

-- Every rate here is currently derived from revenue/MTD rather than agreed, so
-- deriving anomalies from them would manufacture false confidence. Empty until
-- the owner supplies the agreed commercial card.
create or replace view seam.rate_anomaly as
select null::text as id, null::text as client_id, null::text as zone_id,
       null::text as period, null::numeric as observed, null::numeric as expected,
       null::text as kind, null::text as note
where false;

grant usage on schema seam to postgres, service_role;
grant select on all tables in schema seam to postgres, service_role;
alter default privileges in schema seam grant select on tables to postgres, service_role;
revoke all on schema seam from anon, authenticated;
