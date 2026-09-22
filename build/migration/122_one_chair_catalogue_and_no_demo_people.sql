-- Three things, all consequences of building the tool on a seeded org document
-- and then loading the real chair file on top of it.
--
-- 1 · The uploaded titles arrived truncated: "Head _ Administrati",
--     "Chair _ Audit Committ". The CSV parser in the upload service walks
--     characters, not bytes, so it did not do this -- the damage is in the
--     file, where every en-dash cost the title its last two letters (the dash
--     is three bytes and was counted against a character budget). Repaired
--     here so the catalogue reads properly; the file itself still wants fixing
--     before it is loaded again.
--
-- 2 · The duplication. There were two chair catalogues: 34 chairs seeded from
--     the organisation document, and the 124 the owner uploaded. Six of the
--     seeded ones are the same job as an uploaded one. The uploaded chair wins
--     -- the People file names it, and it is the owner's own catalogue -- and
--     absorbs the seeded chair's grade, band, purpose, capability track,
--     holders, seatings, processes and accountabilities. The other 28 seeded
--     chairs are jobs the generic catalogue has no equivalent for (Field
--     Executives / Verifiers, Back Office, Bids Tenders & Contracts) and stay.
--     Every fold is recorded in audit_entry as CHAIR_FOLDED, old and new.
--
-- 3 · The 17 people invented while building the tool, all on @example.invalid,
--     plus the "Sample Manager" placeholder that came in on the branches sheet,
--     and the demo targets, months, strikes and claims hanging off them.

-- ---------------------------------------------------------------- 1 · titles
update chair c set title = v.good
  from (values
    ('AUDIT_COMMITTEE_CHAIR','Chair — Audit Committee'),
    ('BOARD_CHAIR','Chairperson — Board of Directors'),
    ('CSO','Chief Sales Officer / Head — Sales'),
    ('GENERAL_COUNSEL','General Counsel / Head — Legal'),
    ('HEAD_ADMINISTRATION','Head — Administration'),
    ('HEAD_APPLICATIONS','Head — Applications / Engineering'),
    ('HEAD_BI_ANALYTICS','Head — Business Intelligence & Analytics'),
    ('HEAD_BRAND_MARKETING','Head — Brand & Marketing'),
    ('HEAD_BUSINESS_DEVELOPMENT','Head — Business Development'),
    ('HEAD_CNB','Head — Compensation & Benefits / Payroll'),
    ('HEAD_CUSTOMER_SERVICE','Head — Customer Service'),
    ('HEAD_DIGITAL_MARKETING','Head — Digital Marketing'),
    ('HEAD_ENTERPRISE_RISK','Head — Enterprise Risk'),
    ('HEAD_FACILITIES','Head — Facilities & Workplace'),
    ('HEAD_FINANCE_OPERATIONS','Head — Finance Operations'),
    ('HEAD_FP_A','Head — FP&A / Management Accounting'),
    ('HEAD_HR_OPERATIONS','Head — HR Operations'),
    ('HEAD_INFRASTRUCTURE','Head — Infrastructure & Systems'),
    ('HEAD_INTERNAL_AUDIT','Head — Internal Audit'),
    ('HEAD_IT_SERVICE','Head — IT Service Management'),
    ('HEAD_LD','Head — Learning & Development'),
    ('HEAD_OPERATIONAL_RISK','Head — Operational Risk'),
    ('HEAD_OPERATIONS','Head — Operations'),
    ('HEAD_PARTNER_NETWORK','Head — Partner Network'),
    ('HEAD_PMO','Head — PMO / Transformation'),
    ('HEAD_QUALITY','Head — Quality Assurance'),
    ('HEAD_STRATEGY_BE','Head — Strategy & Business Excellence'),
    ('HEAD_TALENT_ACQUISITION','Head — Talent Acquisition'),
    ('HEAD_TAX','Head — Taxation'),
    ('HEAD_TREASURY','Head — Treasury'),
    ('LEGAL_HEAD','Head — Legal Operations'),
    ('NOM_GOV_COMMITTEE_CHAIR','Chair — Nomination & Governance Committee'),
    ('REGIONAL_HEAD_OPERATIONS','Regional / Zonal Head — Operations'),
    ('RISK_COMMITTEE_CHAIR','Chair — Risk Committee')
  ) as v(code, good)
 where c.code = v.code and c.source_ref is null;

-- ------------------------------------------------------------- 2 · the folds
create temporary table fold on commit drop as
select o.id as old_id, o.code as old_code, o.title as old_title,
       o.source_ref as old_src, u.id as new_id, u.code as new_code
  from (values
    ('BM','BRANCH_MANAGER'), ('TL','TEAM_LEADER'), ('ACE','ACCOUNTS_EXECUTIVE'),
    ('RM','ZONAL_MANAGER'),  ('PA','LOCATION_PARTNER'), ('OPS','HEAD_OPERATIONS')
  ) as p(oc, uc)
  join chair o on o.code = p.oc and o.source_ref is not null
  join chair u on u.code = p.uc and u.source_ref is null;

do $$ begin
  if (select count(*) from fold) <> 6 then
    raise exception 'expected 6 chair pairs to fold, found %', (select count(*) from fold);
  end if;
end $$;

-- the survivor takes on the grade and meaning the organisation document holds,
-- and keeps its own place in the uploaded tree
update chair u set
    sg_level            = coalesce(u.sg_level, o.sg_level),
    function_name       = coalesce(u.function_name, o.function_name),
    band                = coalesce(u.band, o.band),
    purpose             = coalesce(u.purpose, o.purpose),
    capability_track_id = coalesce(u.capability_track_id, o.capability_track_id),
    source_ref          = coalesce(u.source_ref, o.source_ref)
  from fold f join chair o on o.id = f.old_id
 where u.id = f.new_id;

update chair_holder         t set chair_id = f.new_id from fold f where t.chair_id = f.old_id;
update chair_seating        t set chair_id = f.new_id from fold f where t.chair_id = f.old_id;
update chair_seating        t set reports_to_chair_id = f.new_id from fold f where t.reports_to_chair_id = f.old_id;
update chair_accountability t set chair_id = f.new_id from fold f where t.chair_id = f.old_id;
update chair_measure        t set chair_id = f.new_id from fold f where t.chair_id = f.old_id;
update chair_authority      t set chair_id = f.new_id from fold f where t.chair_id = f.old_id;
update chair_task           t set chair_id = f.new_id from fold f where t.chair_id = f.old_id;
update process              t set owner_chair_id = f.new_id from fold f where t.owner_chair_id = f.old_id;
update process_input        t set from_chair_id = f.new_id from fold f where t.from_chair_id = f.old_id;
update kpi_definition       t set chair_id = f.new_id from fold f where t.chair_id = f.old_id;
update kpi_eligibility      t set chair_id = f.new_id from fold f where t.chair_id = f.old_id;
update person_request       t set chair_id = f.new_id from fold f where t.chair_id = f.old_id;
update pms_weighting        t set chair_id = f.new_id from fold f where t.chair_id = f.old_id;
update pms_cycle            t set chair_id = f.new_id from fold f where t.chair_id = f.old_id;
update audit_entry          t set chair_id = f.new_id from fold f where t.chair_id = f.old_id;
update audit_entry          t set scope_chair_id = f.new_id from fold f where t.scope_chair_id = f.old_id;
update role_change          t set from_chair_id = f.new_id from fold f where t.from_chair_id = f.old_id;
update role_change          t set to_chair_id = f.new_id from fold f where t.to_chair_id = f.old_id;
update assignment           t set assignor_chair_id = f.new_id from fold f where t.assignor_chair_id = f.old_id;
update assignment_event     t set actor_chair_id = f.new_id from fold f where t.actor_chair_id = f.old_id;
update ogl_escalation_matrix t set chair_id = f.new_id from fold f where t.chair_id = f.old_id;
update escalation_instance  t set resolved_chair_id = f.new_id from fold f where t.resolved_chair_id = f.old_id;

-- process_party carries a composite key, so a row that would collide with one
-- the survivor already has is dropped rather than moved
delete from process_party t using fold f
 where t.chair_id = f.old_id
   and exists (select 1 from process_party x
                where x.process_id = t.process_id and x.chair_id = f.new_id and x.part = t.part);
update process_party t set chair_id = f.new_id from fold f where t.chair_id = f.old_id;

-- children of a folded chair now hang off the survivor, and nothing may end up
-- as its own parent
update chair t set parent_id = f.new_id from fold f
 where t.parent_id = f.old_id and t.id <> f.new_id;
update chair t set parent_id = null from fold f
 where t.parent_id = f.old_id and t.id = f.new_id;

insert into audit_entry (action, entity_type, entity_ref, old_value, new_value)
select 'CHAIR_FOLDED', 'chair', f.old_code,
       jsonb_build_object('code', f.old_code, 'title', f.old_title, 'source_ref', f.old_src),
       jsonb_build_object('code', f.new_code, 'chair_id', f.new_id,
         'why', 'same job as the uploaded chair the People file names')
  from fold f;

delete from chair c using fold f where c.id = f.old_id;

-- ------------------------------------------------------- 3 · the demo people
create temporary table demo on commit drop as
select id, employee_no, full_name, work_email from person
 where work_email like '%@example.invalid'
    or work_email = 'sample.manager@cruxindia.co.in';

do $$ begin
  if (select count(*) from demo) <> 18 then
    raise exception 'expected 18 demo people, found %', (select count(*) from demo);
  end if;
end $$;

insert into audit_entry (action, entity_type, entity_ref, old_value, new_value)
select 'DEMO_PERSON_REMOVED', 'person', coalesce(d.employee_no, d.id::text),
       jsonb_build_object('full_name', d.full_name, 'work_email', d.work_email),
       jsonb_build_object('why', 'invented while building the tool')
  from demo d;

-- everything that hangs off them is demo data too
delete from target         where person_id in (select id from demo) or updated_by in (select id from demo);
delete from perf_month     where person_id in (select id from demo) or loaded_by  in (select id from demo);
delete from strike_event   where person_id in (select id from demo) or waived_by  in (select id from demo);
delete from claim          where person_id in (select id from demo);
delete from branch_contact where person_id in (select id from demo);

update person set manager_id = null where manager_id in (select id from demo);
delete from person where id in (select id from demo);
