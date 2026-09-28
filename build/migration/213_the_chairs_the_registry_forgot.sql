-- 213 · The chairs the registry forgot
--
-- Migration 206 gave a measure set to every SEATED chair, which is what the
-- Performance screen needs to work today. The operating structure document
-- gives one to all 70 chairs, seated or not, under "Measured on" -- 326 lines
-- in total, most of them repeated across the regional copies of the same
-- chair (Branch Managers -- North, -- South, -- Thane and so on all reduce to
-- BRANCH_MANAGER here).
--
-- Reducing the 70 dossier chairs onto the chairs this database has leaves 15
-- with no measures at all: the Board, the four field-facing executive chairs
-- (Back Office, Collections, Business Development, Field Verification),
-- Administration, Central Collections, Accounts Executive, Legal, Risk, the
-- three HR chairs and Learning & Development, and Interns. Every one of them
-- is a chair somebody will eventually sit in, and a chair with no measures
-- cannot be appraised -- it is the registry gap kpi_registry_gap exists to
-- show, and this closes 15 rows of it.
--
-- The names are the document's own words. The units are not: "Measured on"
-- says what is measured and not in what, so each unit here is the plain
-- reading of the line -- a percentage where the line is a rate, a count where
-- it is a count, days where it is a duration. None of them carries an
-- accountability code, because the document does not give one for a measure
-- and inventing one would make this file look more sourced than it is.
--
-- ADDS for the things that accumulate over a month (counts, days, cases);
-- REPLACES for the things that are a level at the end of it (rates, scores).
--
-- One chair is deliberately left empty. The document's own entry for Finance
-- Executive reads "To be defined" under a capability track called
-- "Undefined -- scope pending". Copying that in as a measure would put a
-- placeholder where a target belongs, so it goes to migration_review instead.

do $do$
declare
  v_added int := 0;
  v_chair uuid;
  r record;
begin
  for r in
    with m(chair_code, pos, nm, un, ac) as (values
      -- ------------------------------------------------------------- Board
      ('BRD', 1, 'Revenue against plan',                       '% of plan',                        'REPLACES'),
      ('BRD', 2, 'Clean statutory audit',                      'qualifications, target zero',      'ADDS'),
      ('BRD', 3, 'Zero material compliance breach',            'count, target zero',               'ADDS'),
      -- ----------------------------------------- Back office / processing
      ('BO',  1, 'Cases processed per day',                    'cases per day',                    'ADDS'),
      ('BO',  2, 'Share within TAT',                           '% of cases inside TAT',            'REPLACES'),
      ('BO',  3, 'Error rate below 3%',                        '% of work returned, target below 3%', 'REPLACES'),
      ('BO',  4, 'Rejection or rework count',                  'count, target zero',               'ADDS'),
      -- ------------------------------------- Branch collection executives
      ('CE',  1, 'Days from case completion to local certification', 'days',                       'ADDS'),
      ('CE',  2, 'Certification rate against cases billed',    '% of cases billed',                'REPLACES'),
      ('CE',  3, 'Accounts handed to central with complete evidence', '% of accounts',             'REPLACES'),
      ('CE',  4, 'Local queries resolved within SLA',          '% resolved in window',             'REPLACES'),
      -- ---------------------------------- Business development executives
      ('BDE', 1, 'New business from the territory',            '% of target',                      'REPLACES'),
      ('BDE', 2, 'Account activation rate',                    '% of new mandates',                'REPLACES'),
      ('BDE', 3, 'Revenue per client growth',                  '% growth',                         'REPLACES'),
      ('BDE', 4, 'Leads passed and converted',                 'count against plan',               'ADDS'),
      -- ------------------------------------------- Field executives
      ('FE',  1, 'Cases per day vs product benchmark',         'cases per day against benchmark',  'ADDS'),
      ('FE',  2, 'Share of cases within TAT',                  '% of cases inside TAT',            'REPLACES'),
      ('FE',  3, 'Error rate',                                 '% of work returned',               'REPLACES'),
      ('FE',  4, 'Fraud indicators correctly escalated',       '% of escalations',                 'REPLACES'),
      ('FE',  5, 'Zero SOP deviation',                         'count, target zero',               'ADDS'),
      -- ------------------------------------ Administration & facilities
      ('ADM', 1, 'Asset reconciliation status',                '% of assets reconciled',           'REPLACES'),
      ('ADM', 2, 'Office downtime',                            'hours, target zero',               'ADDS'),
      ('ADM', 3, 'Vendor SLA compliance',                      '% compliant, target 95%',          'REPLACES'),
      ('ADM', 4, 'Expense policy deviations',                  'count, target zero',               'ADDS'),
      -- ------------------------------------- Central collections
      ('CCE', 1, 'Portfolio collection against target',        '% of target',                      'REPLACES'),
      ('CCE', 2, 'Days from certification to receipt',         'days',                             'ADDS'),
      ('CCE', 3, 'Deduction reconciliation completeness',      '% of ledger',                      'REPLACES'),
      ('CCE', 4, 'Dispute logging completeness',               '% of cases tracked',               'REPLACES'),
      -- ------------------------------------------- Accounts executives
      ('ACCOUNTS_EXECUTIVE', 1, 'Processing accuracy',         '% accurate, target 99%',           'REPLACES'),
      ('ACCOUNTS_EXECUTIVE', 2, 'Reconciliation on schedule',  '% of accounts reconciled',         'REPLACES'),
      ('ACCOUNTS_EXECUTIVE', 3, 'Settlement accuracy',         '% accurate',                       'REPLACES'),
      ('ACCOUNTS_EXECUTIVE', 4, 'Rework count',                'count, target zero',               'ADDS'),
      -- ------------------------------------------------ Legal & compliance
      ('LEG', 1, 'Contract turnaround time',                   'days',                             'ADDS'),
      ('LEG', 2, 'Pending case count',                         'count',                            'ADDS'),
      ('LEG', 3, 'Zero penalties or adverse remarks',          'count, target zero',               'ADDS'),
      -- ------------------------------------- Risk & business continuity
      ('RISK',1, 'Risk register current and reviewed quarterly','% of quarters reviewed on time',  'REPLACES'),
      ('RISK',2, 'Issues closed within agreed dates',          '% closed in window',               'REPLACES'),
      ('RISK',3, 'Continuity plan tested annually',            'tests completed against plan',     'ADDS'),
      ('RISK',4, 'Insurance cover adequate to exposure',       '% covered and in date',            'REPLACES'),
      ('RISK',5, 'Zero uninsured material loss',               'count, target zero',               'ADDS'),
      -- --------------------------------------------- Head — Human Resources
      ('HRH', 1, 'Vacancy closure TAT',                        'days to fill',                     'ADDS'),
      ('HRH', 2, 'Payroll accuracy',                           '% of people paid correctly',       'REPLACES'),
      ('HRH', 3, 'Appraisal completion',                       '% of the team',                    'REPLACES'),
      ('HRH', 4, 'Employee satisfaction score',                'score',                            'REPLACES'),
      ('HRH', 5, 'Regrettable attrition',                      '% of the team',                    'REPLACES'),
      ('HRH', 6, 'Zero statutory penalty',                     'count, target zero',               'ADDS'),
      -- --------------------------------------------- Learning & development
      ('LND', 1, 'Time to productivity for a new joiner',      'days',                             'ADDS'),
      ('LND', 2, 'Training coverage against calendar',         '% of the calendar delivered',      'REPLACES'),
      ('LND', 3, 'Defect reduction after training',            '% change in error rate',           'REPLACES'),
      ('LND', 4, 'Intern project completion rate',             '% of projects delivered',          'REPLACES'),
      ('LND', 5, 'Intern to full-time conversion rate',        '% of interns converted',           'REPLACES'),
      -- ------------------------------------------------------------ Interns
      ('INT', 1, 'Project delivered to brief',                 '% of the brief delivered',         'REPLACES'),
      ('INT', 2, 'Sponsor rating',                             'score from the sponsoring chair',  'REPLACES'),
      ('INT', 3, 'Conversion recommendation',                  'recommendation recorded',          'ADDS'),
      -- ------------------------------------------------------ HR operations
      ('HRE', 1, 'Files audit-ready',                          '% of files complete',              'REPLACES'),
      ('HRE', 2, 'Attendance finalised before cut-off',        '% of working days filed',          'REPLACES'),
      ('HRE', 3, 'Payroll input accuracy at or above 99%',     '% accurate, target 99%',           'REPLACES'),
      ('HRE', 4, 'Filings within due dates',                   '% filed on time',                  'REPLACES'))
    select * from m
  loop
    select id into v_chair from chair where code = r.chair_code;
    if v_chair is null then
      raise notice '213: no chair %, skipped', r.chair_code;
      continue;
    end if;
    insert into kpi_definition (chair_id, person_id, name, unit, active, mandatory, position, cadence, accrual)
    values (v_chair, null, r.nm, r.un, true, true, r.pos, 'MONTHLY', r.ac::kpi_accrual)
       on conflict do nothing;
    if found then v_added := v_added + 1; end if;
  end loop;

  raise notice '213: % measures added', v_added;
end $do$;

-- The one the document does not answer either.
insert into public.migration_review (entity_type, entity_ref, question, context)
select 'chair', 'kpi:FEX',
       'What is the Finance Executive chair measured on?',
       'The operating structure document lists this chair under the capability '
       || 'track "Undefined -- scope pending" and gives its only measure as "To be '
       || 'defined". Migration 213 left it empty rather than seeding a placeholder '
       || 'somebody would later be appraised against. It shows in kpi_registry_gap '
       || 'until it is answered.'
 where exists (select 1 from chair where code = 'FEX')
   and not exists (select 1 from migration_review where entity_ref = 'kpi:FEX');

do $do$
declare v_defs int; v_chairs int; v_gap int;
begin
  select count(*), count(distinct chair_id) into v_defs, v_chairs from kpi_definition;
  select count(*) into v_gap from kpi_registry_gap;
  raise notice '213: % measures across % chairs; registry gap now % rows', v_defs, v_chairs, v_gap;

  if v_defs < 170 then
    raise exception '213: expected at least 170 measures, found %', v_defs;
  end if;
end $do$;
