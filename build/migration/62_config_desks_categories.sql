-- =====================================================================
-- 62 · DESKS AND CATEGORIES — the routing configuration R-06 depends on.
-- It was never seeded. The only desks that ever existed were two sample desks
-- and a "Cutover" scaffolding desk, all now deleted, which left the database
-- with zero desks and zero categories and no way to route a case.
--
-- Desk heads come from the USERS sheet by department + designation, not from
-- invention. Three functions have a head in the data (Operations, Finance,
-- HR); IT, Compliance, MIS and the MD office have nobody, so they fall back to
-- the Administrator desk exactly as the vacancy rule says, and each vacancy is
-- written to migration_review for an admin to fill.
--
-- Note on counts: build/IMPLEMENTATION.md says Operations receives 14 of the
-- 22 categories. The prototype's own list gives it 12, and the per-desk text
-- on the configuration screen agrees with 12 (Finance 2, HR 2, IT 2,
-- Compliance 3, MIS 1). 12 is used; the "14" is a stale count from before two
-- orphan groups were given their own names.
--
-- Runs before 65_escalations.sql.
-- =====================================================================
insert into desk (name, primary_person_id, escalation_only)
select 'Administrator', p.id, false
from person p
where p.work_email = 'shantanu.suravase@cruxindia.co.in' and p.superseded_by is null
on conflict (name) do nothing;

insert into desk (name, primary_person_id, escalation_only)
select v.desk_name, p.id, false
from (values ('Operations','manish.s@cruxindia.co.in'),
             ('Finance','sneha.radhe@cruxindia.co.in'),
             ('HR','valsan.p@cruxindia.co.in')) v(desk_name, head_email)
join person p on p.work_email = v.head_email and p.superseded_by is null
on conflict (name) do nothing;

insert into desk (name, primary_person_id, escalation_only, fallback_desk_id)
select v.desk_name, null, v.esc_only, a.id
from (values ('IT', false), ('Compliance', false), ('MIS', false),
             ('MD office', true)) v(desk_name, esc_only)
cross join desk a
where a.name = 'Administrator'
on conflict (name) do nothing;

-- every vacancy is a question, not a silence
insert into migration_review (entity_type, entity_ref, question, context)
select 'desk', d.name,
       case when d.name = 'MD office'
            then 'MD office has no primary. Two people hold the MD designation (Virendra Pal, Arun Bodupali) and the sheet marks neither primary — which one holds the desk?'
            else 'Desk "' || d.name || '" has no head: nobody in the USERS sheet belongs to this function. Escalations for it fall back to the Administrator desk until someone is named.' end,
       'Vacancy rule: fall back to the admin group and flag it loudly.'
from desk d
where d.primary_person_id is null
  and not exists (select 1 from migration_review r where r.entity_type = 'desk' and r.entity_ref = d.name);

-- the 22 categories, exactly the list the prototype offers on the raise form.
-- Audit/Quality routes to Operations (decision of 3 Sep); Fraud/Integrity and
-- Data Privacy are pinned to Compliance and cannot be moved by anyone.
insert into category (name, desk_id, pinned)
select v.cat, d.id, v.pinned
from (values
  ('Service Delivery','Operations',false),
  ('Delay/TAT','Operations',false),
  ('Report Quality','Operations',false),
  ('Data Accuracy','Operations',false),
  ('Customer Handling','Operations',false),
  ('Communication','Operations',false),
  ('Assignment/Allocation','Operations',false),
  ('Client/Branch Mapping','Operations',false),
  ('Client Requirements','Operations',false),
  ('Audit/Quality','Operations',false),
  ('Escalation/Complaint Handling','Operations',false),
  ('Vendor/Partner','Operations',false),
  ('Billing','Finance',false),
  ('Payment','Finance',false),
  ('Staff Behaviour','HR',false),
  ('Performance/KPI','HR',false),
  ('Technology','IT',false),
  ('Access/Permissions','IT',false),
  ('Compliance','Compliance',false),
  ('Fraud/Integrity','Compliance',true),
  ('Data Privacy','Compliance',true),
  ('MIS/Reporting','MIS',false)
) v(cat, desk_name, pinned)
join desk d on d.name = v.desk_name
on conflict do nothing;
