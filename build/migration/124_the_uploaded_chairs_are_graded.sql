-- Grade the uploaded chairs, and give them the detail the graded ones have.
--
-- The 124 chairs that came in on the Chairs file carried a title, a level and a
-- parent and nothing else, so the org chart showed them with no SG number and
-- an empty page underneath. This fills, for each of the 118 still ungraded:
-- the grade, the band, the function, a purpose, three accountabilities, three
-- measures, and what the chair decides for itself against what it must
-- escalate -- the same shape org_chair already renders for the chairs that came
-- from the organisation document.
--
-- WHERE THIS CONTENT COMES FROM, because it matters. The 28 chairs seeded from
-- the organisation document carry that document's own words. These do not.
-- They are derived from the job title, the chair's place in the tree and the
-- grade ladder that document establishes (SG1 executive up to SG7 enterprise),
-- and they are written to be edited. Every row inserted here is stamped
-- source_ref 'DERIVED', so the two can always be told apart and a later load of
-- the real job descriptions can replace them without touching the document's.
--
-- The statements are composed rather than listed: a chair's family supplies
-- what it is answerable for, its grade supplies the frame. That is why a Head
-- "owns" something and an Executive "does" it, and why the wording stays
-- consistent down a ladder instead of drifting chair by chair.
--
-- Function names and bands reuse the vocabulary already in the chair table --
-- Governance, Executive, Operations, Finance, Assurance & People, Business
-- Excellence, Commercial -- rather than growing a second set the chart would
-- then have to group twice.

alter table chair_accountability add column if not exists source_ref text;
alter table chair_measure        add column if not exists source_ref text;
alter table chair_authority      add column if not exists source_ref text;

-- what each family of chairs is answerable for, and the one measure that is
-- particular to it rather than true of any chair
create temporary table fam(family text primary key, scope text, deliverable text,
                           fmeas text, track text) on commit drop;
insert into fam values
  ('ADMIN','the workplace and its running','offices, assets, travel and the facilities record','Every office is compliant, insured and fit to work in.','Administration'),
  ('AUDIT','independent assurance over how the company works','the audit plan and its findings','The audit plan is delivered and findings close inside their agreed date.','Assurance & Compliance'),
  ('BD','new business and the clients it comes from','prospecting, bids and onboarding','New clients are won at the margin the plan assumed.','Business Development'),
  ('COMP','the company''s regulatory standing','the compliance calendar and its evidence','Every filing is made on time with evidence kept.','Assurance & Compliance'),
  ('CX','what the client experiences','complaints, queries and the service standard','Complaints are closed inside the standard and repeat complaints fall.',null),
  ('DATA','the numbers the company decides on','reporting, dashboards and data quality','Every published number can be traced to its source.','MIS & Analytics'),
  ('EXEC','the company''s performance against plan','the executive agenda','The company meets the plan the board approved.','Enterprise Leadership'),
  ('FIN','the company''s books and cash','the ledger, the close and the cash position','The month closes on time and the books reconcile.','Accounting & Statutory'),
  ('FINLEAD','the company''s financial position','the plan, the close and the cash position','The month closes on time and the books reconcile.','Finance Leadership'),
  ('GEN','the work allocated to this chair','the day''s allocated work','The day''s work is finished, filed and correct.',null),
  ('GOV','the board''s oversight of the company','board and committee business','Every committee meets on its calendar and its minutes are signed.','Board Governance'),
  ('HR','the people the company employs','hiring, records, payroll input and exits','Every seat has a named holder and every joiner is on record from day one.','HR Operations'),
  ('LEGAL','the company''s legal exposure','contracts, notices and disputes','No contract is signed without review and no notice misses its date.','Assurance & Compliance'),
  ('MKT','how the company is known in its market','campaigns, brand and the enquiry pipeline','Enquiries arrive at the cost per enquiry the plan assumed.','Business Development'),
  ('OPS','delivery to the client','the day''s casework and its turnaround','Turnaround is met on the cases this chair is answerable for.','Operations Leadership'),
  ('PARTNER','the partner network this chair is answerable for','partner recruitment, standards and payout','Partners meet the same standard as an owned branch, and are paid on time.','Business Development'),
  ('PMO','how the company improves itself','projects, process change and their benefit','Every project lands its stated benefit, or is stopped and said so.','Business Excellence'),
  ('PROC','what the company buys','sourcing, vendor selection and the purchase record','Nothing is bought outside an approved rate and a signed vendor.','Administration'),
  ('QUAL','the quality of what leaves the company','sampling, scoring and correction','The error rate falls quarter on quarter and no client finds a fault first.','Business Excellence'),
  ('RISK','the risks the company is carrying','the risk register and its treatment','No risk sits past its review date without a named owner.','Assurance & Compliance'),
  ('SALES','the revenue this chair is answerable for','the pipeline and its conversion','The number is met, and the pipeline covers next period before this one closes.','Business Development'),
  ('TECH','the systems the company runs on','availability, change and support','The systems are available in working hours and changes do not break them.','Technology');

-- the frame each grade puts around it
create temporary table tier(tier text, kind text, ord int, tpl text) on commit drop;
insert into tier values
  ('HEAD','ACC',1,'Owns {scope} for the whole company and answers for it to {parent}.'),
  ('HEAD','ACC',2,'Sets the standard, the plan and the budget for {deliverable}.'),
  ('HEAD','ACC',3,'Keeps a named successor ready for every chair reporting to this one.'),
  ('HEAD','MEA',1,'{fmeas}'),
  ('HEAD','MEA',2,'The function stays inside the budget it was given.'),
  ('HEAD','MEA',3,'No chair below this one is left vacant for more than a quarter.'),
  ('HEAD','DECIDE',1,'Sets the standard and the operating budget for {scope}.'),
  ('HEAD','DECIDE',2,'Appoints, moves and releases the chairs reporting to this one.'),
  ('HEAD','ESCALATE',1,'Anything that changes the company''s obligations to a client or a regulator.'),
  ('HEAD','ESCALATE',2,'Any spend or commitment beyond the delegation this chair was given.'),
  ('SENIOR','ACC',1,'Owns {scope} across the region or zone and answers for it to {parent}.'),
  ('SENIOR','ACC',2,'Runs {deliverable} to the standard the function head set.'),
  ('SENIOR','ACC',3,'Grows the managers below this chair and reports who is ready.'),
  ('SENIOR','MEA',1,'{fmeas}'),
  ('SENIOR','MEA',2,'The region meets its number without breaching the standard.'),
  ('SENIOR','MEA',3,'No unit in the region is left without a manager.'),
  ('SENIOR','DECIDE',1,'How the region is organised and who runs each unit within the standard.'),
  ('SENIOR','DECIDE',2,'Allocation of the region''s people and budget between its units.'),
  ('SENIOR','ESCALATE',1,'A standard that cannot be met in the region without changing the standard.'),
  ('SENIOR','ESCALATE',2,'Anything beyond this chair''s delegated authority to spend or commit.'),
  ('MANAGER','ACC',1,'Runs {deliverable} day to day and answers for it to {parent}.'),
  ('MANAGER','ACC',2,'Holds the team to the standard {scope} is measured on.'),
  ('MANAGER','ACC',3,'Checks the work before it leaves and corrects it where it is wrong.'),
  ('MANAGER','MEA',1,'{fmeas}'),
  ('MANAGER','MEA',2,'Nothing sits unactioned past its due date.'),
  ('MANAGER','MEA',3,'Every person in the team files their day.'),
  ('MANAGER','DECIDE',1,'How the day''s work is allocated across the team.'),
  ('MANAGER','DECIDE',2,'Whether a piece of work is fit to go out or must be redone.'),
  ('MANAGER','ESCALATE',1,'Anything that will miss its date before it misses it.'),
  ('MANAGER','ESCALATE',2,'A dispute, a complaint or a loss that is outside this chair''s authority to settle.'),
  ('SUPERVISOR','ACC',1,'Supervises the people doing {deliverable} and checks their work before it leaves.'),
  ('SUPERVISOR','ACC',2,'Keeps the day moving: allocation, chasing and hand-back.'),
  ('SUPERVISOR','ACC',3,'Trains new joiners on {scope} until they can work unsupervised.'),
  ('SUPERVISOR','MEA',1,'{fmeas}'),
  ('SUPERVISOR','MEA',2,'The day''s allocation is closed by the end of the day.'),
  ('SUPERVISOR','MEA',3,'Rework caused by the team falls month on month.'),
  ('SUPERVISOR','DECIDE',1,'Who does what within the team today.'),
  ('SUPERVISOR','DECIDE',2,'Whether a piece of work goes back for correction.'),
  ('SUPERVISOR','ESCALATE',1,'Anything that will miss its turnaround.'),
  ('SUPERVISOR','ESCALATE',2,'A person, client or case problem the team cannot settle itself.'),
  ('EXECUTIVE','ACC',1,'Does the work of {deliverable} to the standard set for {scope}.'),
  ('EXECUTIVE','ACC',2,'Files the day''s count and keeps own records current.'),
  ('EXECUTIVE','ACC',3,'Raises a problem the same day rather than carrying it.'),
  ('EXECUTIVE','MEA',1,'{fmeas}'),
  ('EXECUTIVE','MEA',2,'The day is filed, every working day.'),
  ('EXECUTIVE','MEA',3,'Work returned for correction stays inside the allowed rate.'),
  ('EXECUTIVE','DECIDE',1,'How own work is sequenced within the day.'),
  ('EXECUTIVE','DECIDE',2,'When to stop and ask rather than guess.'),
  ('EXECUTIVE','ESCALATE',1,'Anything that cannot be finished inside its turnaround.'),
  ('EXECUTIVE','ESCALATE',2,'Anything that looks wrong, missing or outside the standard.');

create temporary table sgtier(sg text primary key, tier text) on commit drop;
insert into sgtier values
  ('SG1','EXECUTIVE'),
  ('SG2','SUPERVISOR'),
  ('SG3','MANAGER'),
  ('SG4','MANAGER'),
  ('SG5','SENIOR'),
  ('SG6','HEAD'),
  ('SG7','HEAD');

create temporary table g(code text primary key, sg text, band text, fn text,
                         family text, purpose text) on commit drop;
insert into g values
  ('ACCOUNTS_MANAGER','SG3','Unit manager','Finance','FIN','Runs the accounts team: entries, reconciliations and the evidence behind both.'),
  ('ADMIN_ASSOCIATE','SG1','Executive','Operations','ADMIN','Supports administration and keeps the asset and travel record current.'),
  ('ADMIN_EXECUTIVE','SG1','Executive','Operations','ADMIN','Does the day''s administration and keeps the office record current.'),
  ('ADMIN_MANAGER','SG3','Unit manager','Operations','ADMIN','Runs administration day to day across the offices in scope.'),
  ('ASSOCIATE','SG1','Executive','Operations','GEN','Supports the team and keeps its records current.'),
  ('AUDIT_ASSOCIATE','SG1','Executive','Assurance & People','AUDIT','Supports audit fieldwork and keeps the finding record current.'),
  ('AUDIT_COMMITTEE_CHAIR','SG7','Enterprise','Governance','AUDIT','Chairs the audit committee. Owns the relationship with internal and statutory audit.'),
  ('BD_ASSOCIATE','SG1','Executive','Commercial','BD','Supports business development and keeps the prospect record current.'),
  ('BD_EXECUTIVE','SG1','Executive','Commercial','BD','Prospects, qualifies and helps close new business.'),
  ('BD_MANAGER','SG3','Unit manager','Commercial','BD','Runs a business development team against its pipeline and its wins.'),
  ('BD_TEAM_LEADER','SG2','Supervisor','Commercial','BD','Supervises the BD team''s daily activity and the quality of what they submit.'),
  ('BOARD_CHAIR','SG7','Enterprise','Governance','GOV','Chairs the board. Owns the agenda, the calendar and the quality of the board''s own decisions.'),
  ('BOARD_MEMBER','SG7','Enterprise','Governance','GOV','Governs the company as one of the directors. Does not operate it.'),
  ('BUSINESS_EXCELLENCE_ASSOCIATE','SG1','Executive','Business Excellence','PMO','Supports process and improvement work and keeps its record current.'),
  ('CEO_MD','SG7','Enterprise','Executive','EXEC','Runs the company through its function heads and answers to the board for the result.'),
  ('CFO','SG6','Function head','Finance','FINLEAD','Owns the company''s financial position: the plan, the close, the cash and the controls around them.'),
  ('CHIEF_COMPLIANCE_OFFICER','SG6','Function head','Assurance & People','COMP','Owns the company''s regulatory standing and answers for it to the board.'),
  ('CHIEF_CUSTOMER_OFFICER','SG6','Function head','Operations','CX','Owns what the client experiences, end to end, and answers for it to the chief executive.'),
  ('CHIEF_DATA_OFFICER','SG6','Function head','Business Excellence','DATA','Owns the numbers the company decides on and whether they can be trusted.'),
  ('CHIEF_OF_STAFF','SG6','Function head','Executive','EXEC','Runs the executive agenda: what gets decided, by when, and whether it then happened.'),
  ('CHIEF_PARTNERSHIP_OFFICER','SG6','Function head','Commercial','PARTNER','Owns the partner and channel network as a route to market.'),
  ('CHRO','SG6','Function head','Assurance & People','HR','Owns the people the company employs: who it hires, how they are paid and why they stay.'),
  ('CIO_CTO','SG6','Function head','Business Excellence','TECH','Owns the systems the company runs on and the plan for what they become.'),
  ('CISO','SG5','Senior / regional','Assurance & People','TECH','Owns information security. Answers for what would happen if the company were attacked.'),
  ('CMO','SG6','Function head','Commercial','MKT','Owns how the company is known and the enquiries that come from it.'),
  ('COMPANY_SECRETARY','SG6','Function head','Governance','GOV','Owns the company''s statutory record and the machinery of the board.'),
  ('COMPLIANCE_ASSOCIATE','SG1','Executive','Assurance & People','COMP','Supports compliance and keeps the calendar and evidence current.'),
  ('COMPLIANCE_EXECUTIVE','SG1','Executive','Assurance & People','COMP','Makes the filings and keeps the evidence.'),
  ('COMPLIANCE_MANAGER','SG3','Unit manager','Assurance & People','COMP','Runs the compliance calendar and the evidence behind each filing.'),
  ('COO','SG6','Function head','Operations','OPS','Owns delivery to the client across every region, and the cost of delivering it.'),
  ('CPO','SG6','Function head','Operations','PROC','Owns what the company buys and what it pays for it.'),
  ('CRO','SG6','Function head','Assurance & People','RISK','Owns the company''s risk picture and says plainly what it is carrying.'),
  ('CSO','SG6','Function head','Commercial','SALES','Owns the revenue number and the sales organisation that delivers it.'),
  ('CUSTOMER_SERVICE_ASSOCIATE','SG1','Executive','Operations','CX','Supports the service desk and keeps the complaint record current.'),
  ('CUSTOMER_SERVICE_EXECUTIVE','SG1','Executive','Operations','CX','Answers client queries and closes complaints inside the standard.'),
  ('CUSTOMER_SERVICE_MANAGER','SG3','Unit manager','Operations','CX','Runs the service desk: queries answered, complaints closed, promises kept.'),
  ('DATA_ANALYST','SG1','Executive','Business Excellence','DATA','Builds and checks the reports, and can show where every number came from.'),
  ('DATA_ASSOCIATE','SG1','Executive','Business Excellence','DATA','Prepares and checks the data the reports are built on.'),
  ('EXECUTIVE','SG1','Executive','Operations','GEN','Does the work allocated to this chair, to the standard set for it.'),
  ('EXECUTIVE_ASSISTANT','SG2','Supervisor','Executive','ADMIN','Runs the chief executive''s diary, papers and follow-ups.'),
  ('FACILITIES_EXECUTIVE','SG1','Executive','Operations','ADMIN','Does the day''s facilities work and logs what was done.'),
  ('FACILITIES_MANAGER','SG3','Unit manager','Operations','ADMIN','Runs premises and facilities for the offices in scope.'),
  ('FINANCE_ASSOCIATE','SG1','Executive','Finance','FIN','Does the daily finance work: entries, reconciliations and filing.'),
  ('FINANCIAL_CONTROLLER','SG5','Senior / regional','Finance','FIN','Owns the ledger and the close. The books are right because this chair checked them.'),
  ('GENERAL_COUNSEL','SG6','Function head','Assurance & People','LEGAL','Owns the company''s legal position and is the last word on legal risk.'),
  ('HEAD_ADMINISTRATION','SG4','Functional manager','Operations','ADMIN','Owns the offices, the assets in them and the services that keep them running.'),
  ('HEAD_APPLICATIONS','SG4','Functional manager','Business Excellence','TECH','Owns the applications the company works in and the changes made to them.'),
  ('HEAD_BI_ANALYTICS','SG4','Functional manager','Business Excellence','DATA','Owns reporting and analysis, and the data quality underneath both.'),
  ('HEAD_BRAND_MARKETING','SG4','Functional manager','Commercial','MKT','Owns the brand and the campaigns that carry it.'),
  ('HEAD_BUSINESS_DEVELOPMENT','SG4','Functional manager','Commercial','BD','Owns new business: who the company goes after and on what terms.'),
  ('HEAD_CNB','SG4','Functional manager','Assurance & People','HR','Owns pay, benefits and the payroll input that follows from them.'),
  ('HEAD_CUSTOMER_SERVICE','SG4','Functional manager','Operations','CX','Owns the service standard and the complaints that test it.'),
  ('HEAD_DIGITAL_MARKETING','SG4','Functional manager','Commercial','MKT','Owns the digital channels and what they cost per enquiry.'),
  ('HEAD_ENTERPRISE_RISK','SG4','Functional manager','Assurance & People','RISK','Owns the enterprise risk register and the treatment behind each entry.'),
  ('HEAD_FACILITIES','SG4','Functional manager','Operations','ADMIN','Owns the workplace: premises, safety, and whether the place is fit to work in.'),
  ('HEAD_FINANCE_OPERATIONS','SG4','Functional manager','Finance','FIN','Owns billing, receipts and payables as a running operation rather than a month-end scramble.'),
  ('HEAD_FP_A','SG4','Functional manager','Finance','FINLEAD','Owns the plan, the forecast and the variance story behind both.'),
  ('HEAD_HR_OPERATIONS','SG4','Functional manager','Assurance & People','HR','Owns the employee record from offer to exit, and everything filed off it.'),
  ('HEAD_INFRASTRUCTURE','SG4','Functional manager','Business Excellence','TECH','Owns the infrastructure everything else runs on.'),
  ('HEAD_INTERNAL_AUDIT','SG4','Functional manager','Assurance & People','AUDIT','Owns independent assurance. Reports to the audit committee, not to the audited.'),
  ('HEAD_IT_SERVICE','SG4','Functional manager','Business Excellence','TECH','Owns IT service: whether people can actually work, and how fast they are unblocked.'),
  ('HEAD_LD','SG4','Functional manager','Assurance & People','HR','Owns capability: what people must be able to do, and how that is proven.'),
  ('HEAD_OPERATIONAL_RISK','SG4','Functional manager','Assurance & People','RISK','Owns the risks that come out of how the work is actually done.'),
  ('HEAD_PARTNER_NETWORK','SG4','Functional manager','Commercial','PARTNER','Owns partner recruitment, standards and the payout that follows.'),
  ('HEAD_PMO','SG4','Functional manager','Business Excellence','PMO','Owns the project portfolio: what is running, what it costs, what it was for.'),
  ('HEAD_QUALITY','SG4','Functional manager','Operations','QUAL','Owns the standard the work is judged against, and the sampling that proves it is met.'),
  ('HEAD_STRATEGY_BE','SG5','Senior / regional','Business Excellence','PMO','Owns how the company improves itself, and whether the improvement actually landed.'),
  ('HEAD_TALENT_ACQUISITION','SG4','Functional manager','Assurance & People','HR','Owns hiring: the plan, the pipeline and the quality of who joins.'),
  ('HEAD_TAX','SG4','Functional manager','Finance','COMP','Owns every tax position the company takes and the filings that follow from them.'),
  ('HEAD_TREASURY','SG4','Functional manager','Finance','FINLEAD','Owns cash, banking and the company''s ability to pay what it owes when it falls due.'),
  ('HR_ASSOCIATE','SG1','Executive','Assurance & People','HR','Supports HR and keeps the employee record current.'),
  ('HR_EXECUTIVE','SG1','Executive','Assurance & People','HR','Does the day''s HR work: records, joiners, leavers and payroll input.'),
  ('HR_MANAGER','SG3','Unit manager','Assurance & People','HR','Runs HR for the unit in scope and is the first call for its managers.'),
  ('INDEPENDENT_DIRECTOR','SG7','Enterprise','Governance','GOV','Brings a view that is not management''s. Sits on the committees that need independence.'),
  ('INTERNAL_AUDITOR','SG1','Executive','Assurance & People','AUDIT','Does the fieldwork, records the finding and follows it to closure.'),
  ('INTERNAL_AUDIT_MANAGER','SG3','Unit manager','Assurance & People','AUDIT','Runs the audit plan and the fieldwork behind it.'),
  ('IT_MANAGER','SG3','Unit manager','Business Excellence','TECH','Runs IT support and the asset and access record behind it.'),
  ('IT_SUPPORT_ASSOCIATE','SG1','Executive','Business Excellence','TECH','Supports the IT desk and keeps the asset and access record current.'),
  ('IT_SUPPORT_EXECUTIVE','SG1','Executive','Business Excellence','TECH','Resolves support calls inside the standard and records what was done.'),
  ('LEGAL_ASSOCIATE','SG1','Executive','Assurance & People','LEGAL','Supports legal work and keeps the contract register current.'),
  ('LEGAL_EXECUTIVE','SG1','Executive','Assurance & People','LEGAL','Reviews and files contracts and notices, and chases what they require.'),
  ('LEGAL_HEAD','SG4','Functional manager','Assurance & People','LEGAL','Owns legal operations: contracts, notices, disputes and the record of all three.'),
  ('LEGAL_MANAGER','SG3','Unit manager','Assurance & People','LEGAL','Runs contract review and the dispute file.'),
  ('MARKETING_ASSOCIATE','SG1','Executive','Commercial','MKT','Supports campaigns and keeps the marketing record current.'),
  ('MARKETING_EXECUTIVE','SG1','Executive','Commercial','MKT','Runs the day''s marketing activity and records what it produced.'),
  ('MARKETING_MANAGER','SG3','Unit manager','Commercial','MKT','Runs campaigns to their plan, their budget and their result.'),
  ('NOM_GOV_COMMITTEE_CHAIR','SG7','Enterprise','Governance','GOV','Chairs nomination and governance. Owns succession at board and function-head level.'),
  ('PARTNER_ASSOCIATE','SG1','Executive','Operations','PARTNER','Supports the partner location and keeps its records current.'),
  ('PARTNER_EXECUTIVE','SG1','Executive','Operations','PARTNER','Does the partner location''s casework to the company''s standard.'),
  ('PARTNER_OPERATIONS_LEAD','SG3','Unit manager','Operations','PARTNER','Runs delivery at a partner location to the same standard as an owned branch.'),
  ('PARTNER_TEAM_LEADER','SG2','Supervisor','Operations','PARTNER','Supervises the partner location''s team and checks its work before it leaves.'),
  ('PROCESS_EXCELLENCE_EXECUTIVE','SG1','Executive','Business Excellence','PMO','Maps how the work is done today and proves whether a change made it better.'),
  ('PROCUREMENT_ASSOCIATE','SG1','Executive','Operations','PROC','Supports sourcing and keeps the vendor and rate record current.'),
  ('PROCUREMENT_EXECUTIVE','SG1','Executive','Operations','PROC','Raises and chases purchase orders and keeps the buying record straight.'),
  ('PROCUREMENT_MANAGER','SG3','Unit manager','Operations','PROC','Runs sourcing and purchase orders against approved rates and signed vendors.'),
  ('PROJECT_COORDINATOR','SG1','Executive','Business Excellence','PMO','Keeps the project plan, the actions and the record of both current.'),
  ('PROJECT_MANAGER','SG3','Unit manager','Business Excellence','PMO','Runs projects to their date, their cost and their stated benefit.'),
  ('QUALITY_ASSOCIATE','SG1','Executive','Operations','QUAL','Supports sampling and keeps the quality record current.'),
  ('QUALITY_EXECUTIVE','SG1','Executive','Operations','QUAL','Samples and scores completed work against the standard.'),
  ('QUALITY_MANAGER','SG3','Unit manager','Operations','QUAL','Runs sampling and scoring, and chases the corrections that come out of it.'),
  ('REGIONAL_BD_HEAD','SG5','Senior / regional','Commercial','BD','Owns new business for the region and the bids that win it.'),
  ('REGIONAL_HEAD_OPERATIONS','SG5','Senior / regional','Operations','OPS','Owns operations for the region as a business: its number, its people and its quality.'),
  ('REGIONAL_PARTNER_HEAD','SG5','Senior / regional','Commercial','PARTNER','Owns the region''s partner network and whether it meets the company''s standard.'),
  ('REGIONAL_SALES_HEAD','SG5','Senior / regional','Commercial','SALES','Owns the region''s revenue number and the pipeline behind it.'),
  ('RISK_ASSOCIATE','SG1','Executive','Assurance & People','RISK','Supports risk work and keeps the register current.'),
  ('RISK_COMMITTEE_CHAIR','SG7','Enterprise','Governance','RISK','Chairs the risk committee. Answers to the board for what the company is exposed to.'),
  ('RISK_EXECUTIVE','SG1','Executive','Assurance & People','RISK','Assesses and records risks, and chases their treatment.'),
  ('RISK_MANAGER','SG3','Unit manager','Assurance & People','RISK','Runs risk assessment and keeps the register honest and current.'),
  ('SALES_ASSOCIATE','SG1','Executive','Commercial','SALES','Supports the sales team and keeps the pipeline record current.'),
  ('SALES_EXECUTIVE','SG1','Executive','Commercial','SALES','Carries a number and works the pipeline behind it.'),
  ('SALES_MANAGER','SG3','Unit manager','Commercial','SALES','Runs a sales team against its number and its pipeline.'),
  ('SALES_TEAM_LEADER','SG2','Supervisor','Commercial','SALES','Supervises the sales team''s daily activity and the quality of what they promise.'),
  ('SENIOR_EXECUTIVE','SG1','Executive','Operations','GEN','Carries the harder work within the team and helps others do theirs.'),
  ('SENIOR_SALES_EXECUTIVE','SG1','Executive','Commercial','SALES','Carries a number and the larger or more difficult accounts within it.'),
  ('SYSTEMS_ADMINISTRATOR','SG1','Executive','Business Excellence','TECH','Keeps the systems running, patched, backed up and access-controlled.'),
  ('VENDOR_EXECUTIVE','SG1','Executive','Operations','PROC','Keeps vendor records, contracts and performance notes current.'),
  ('VENDOR_MANAGER','SG3','Unit manager','Operations','PROC','Owns the vendor list: who is approved, on what terms, performing how well.'),
  ('VP_FINANCE','SG6','Function head','Finance','FINLEAD','Deputises for the CFO across finance and carries the chairs the CFO delegates.');

do $$ begin
  if exists (select 1 from g where code not in (select code from chair)) then
    raise exception 'unknown chair code(s): %',
      (select string_agg(code, ', ') from g where code not in (select code from chair));
  end if;
  if exists (select 1 from g join chair c on c.code = g.code where c.sg_level is not null) then
    raise exception 'refusing to regrade an already graded chair: %',
      (select string_agg(g.code, ', ') from g join chair c on c.code = g.code
        where c.sg_level is not null);
  end if;
  if exists (select 1 from g where family not in (select family from fam)) then
    raise exception 'unknown family: %', (select string_agg(distinct family, ', ') from g
      where family not in (select family from fam));
  end if;
end $$;

update chair c set
    sg_level      = g.sg,
    band          = g.band,
    function_name = g.fn,
    purpose       = g.purpose,
    capability_track_id = coalesce(c.capability_track_id,
                            (select t.id from capability_track t where t.name = f.track))
  from g join fam f on f.family = g.family
 where g.code = c.code;

-- one place where the placeholders are filled, so the three inserts below
-- cannot drift apart
create temporary table said on commit drop as
select c.id as chair_id, t.kind, t.ord,
       replace(replace(replace(replace(t.tpl,
         '{scope}', f.scope), '{deliverable}', f.deliverable), '{fmeas}', f.fmeas),
         '{parent}', coalesce((select p.title from chair p where p.id = c.parent_id),
                              'the chair above this one')) as statement
  from g
  join chair  c on c.code = g.code
  join fam    f on f.family = g.family
  join sgtier s on s.sg = g.sg
  join tier   t on t.tier = s.tier;

insert into chair_accountability (chair_id, ord, statement, source_ref)
select chair_id, ord, statement, 'DERIVED' from said where kind = 'ACC'
   and not exists (select 1 from chair_accountability x where x.chair_id = said.chair_id);

insert into chair_measure (chair_id, ord, statement, source_ref)
select chair_id, ord, statement, 'DERIVED' from said where kind = 'MEA'
   and not exists (select 1 from chair_measure x where x.chair_id = said.chair_id);

insert into chair_authority (chair_id, kind, ord, statement, source_ref)
select chair_id, kind, ord, statement, 'DERIVED' from said where kind in ('DECIDE','ESCALATE')
   and not exists (select 1 from chair_authority x where x.chair_id = said.chair_id);

do $$ declare n int;
begin
  select count(*) into n from chair where sg_level is null;
  if n > 0 then raise exception '% chairs still have no grade', n; end if;
  select count(*) into n from g join chair c on c.code = g.code where not exists
    (select 1 from chair_accountability a where a.chair_id = c.id);
  if n > 0 then raise exception '% newly graded chairs have no accountabilities', n; end if;
end $$;
