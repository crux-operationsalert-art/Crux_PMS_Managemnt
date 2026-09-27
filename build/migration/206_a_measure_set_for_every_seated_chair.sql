-- 206 · A measure set for every seated chair
--
-- The KPI registry holds 65 measures across 17 chairs. One hundred and one
-- people hold a chair. Only twelve of them sit in a chair that has any
-- measures at all:
--
--   seated AND measured   BRANCH_MANAGER (11 people, 4 measures)
--                         AVP            (1 person,  3 measures)
--   seated, no measures   EXECUTIVE (63), TEAM_LEADER (9),
--                         LOCATION_PARTNER (7), ZONAL_MANAGER (2),
--                         CEO_MD, MD, HEAD_OPERATIONS, HEAD_HR_OPERATIONS,
--                         HEAD_FINANCE_OPERATIONS, HR_EXECUTIVE,
--                         SALES_MANAGER, VP_FINANCE (1 each)
--   measured, nobody in   OPS, FIN, RM, BZ, ACC, BD, BEX, BID, CCM, CS, ENG,
--                         GRC, MIS, TEC  (15 chairs, 58 measures)
--
-- Eighty-nine of the hundred and one sit in a chair with nothing to be
-- measured on. That is not an authoring gap alone -- it is two parallel sets
-- of chairs. The registry was written against the FUNCTION chairs and the
-- people were seated in a different set, which is why Head — Operations has
-- no measures while Operations Head has four and nobody in it.
--
-- Merging those pairs would change the org chart and the reporting lines, and
-- that is the owner's decision, not this migration's. What this does instead
-- is give each seated chair its own set, written from what that chair already
-- says it is answerable for -- chair_measure holds 501 such statements across
-- 152 chairs, three to six for each of these twelve. Nothing here is invented;
-- where a counterpart chair already words the same measure, its wording is
-- reused rather than a second name for one number being coined.
--
-- Two choices worth stating:
--
--   Cadence is MONTHLY throughout, including for the statements that say
--   "every working day". A DAILY measure is a daily reminder, and turning one
--   on for sixty-three people is an operational change nobody asked for. The
--   daily discipline is measured as the month's compliance with it -- "% of
--   working days filed" -- which is the same fact without the siren.
--
--   Accrual is COMPUTED, not typed. Migration 200 found forty-six percentage
--   measures marked ADDS because ADDS was the column default, and a month
--   that accumulates percentages reaches 181%. So every row below takes its
--   accrual from perf_accrual_kind(), the function that decides it at scoring
--   time. The stored value and the computed one cannot disagree because they
--   are the same answer.

-- ---------------------------------------------- first, stop it happening twice
-- kpi_definition has no uniqueness at all: the same measure can be authored
-- against the same chair any number of times, and a registry with two rows
-- called "Branch revenue achievement" scores one of them and silently ignores
-- the other. Check before adding the index, so a pre-existing duplicate is
-- named rather than crashing an index build with a message about a relation.
do $do$
declare v text;
begin
  select string_agg(ch.title || ' :: ' || k.name, ', ') into v
    from kpi_definition k join chair ch on ch.id = k.chair_id
   where k.active and k.chair_id is not null
   group by k.chair_id, lower(btrim(k.name)), ch.title, k.name
  having count(*) > 1;
  if v is not null then
    raise exception 'the registry already holds duplicate measures and they must be '
                    'retired before the index goes on: %', v;
  end if;
end $do$;

create unique index if not exists kpi_definition_one_name_per_chair
  on public.kpi_definition (chair_id, lower(btrim(name)))
  where chair_id is not null and active;

comment on index public.kpi_definition_one_name_per_chair is
  'One live measure of a given name per chair. Retired measures are exempt, so '
  'a measure can be replaced by retiring it and authoring the next one.';

-- ------------------------------------------------------------- the measures
-- Every row is traceable to a statement on its own chair. The unit carries the
-- reference the existing registry uses, so a reader can find the source.
insert into public.kpi_definition
  (chair_id, name, unit, "position", cadence, accrual, active, mandatory)
select ch.id, w.name, w.unit, w.ord,
       'MONTHLY'::kpi_cadence,
       (case when perf_accrual_kind(null, w.unit) = 'LEVEL'
             then 'REPLACES' else 'ADDS' end)::kpi_accrual,
       true, true
  from (values
    -- Chief Executive Officer / Managing Director ------------------------
    ('CEO_MD', 1, 'Company revenue against the board plan', '% of plan · CEO1'),
    ('CEO_MD', 2, 'Company cost against budget',            '% variance · CEO2'),
    ('CEO_MD', 3, 'Chairs left vacant beyond a quarter',    'count, target zero · CEO3'),

    -- Managing Director ---------------------------------------------------
    ('MD', 1, 'Revenue against plan',                   '% of plan · R1'),
    ('MD', 2, 'EBITDA against plan',                    '% of plan · L1'),
    ('MD', 3, 'Branches operational against plan',      'count against plan · D8'),
    ('MD', 4, 'Issues resolved below this chair',       '% of escalations · E1'),

    -- Head — Operations ---------------------------------------------------
    -- Its own statements, which are already measure-shaped, and closer to the
    -- work than the generic set on the Operations Head chair nobody sits in.
    ('HEAD_OPERATIONS', 1, 'SLA and TAT adherence',  '% of cases inside TAT, target 95% · D1'),
    ('HEAD_OPERATIONS', 2, 'Escalation ratio',       '% of cases escalated, target below 2% · D1'),
    ('HEAD_OPERATIONS', 3, 'Cost per case',          'INR per case against budget · X3'),
    ('HEAD_OPERATIONS', 4, 'Audit score',            '% score, target 95% · D21'),

    -- Head — Finance Operations -------------------------------------------
    -- Rows 1 and 2 reuse the Finance Head and Accounts wording verbatim.
    ('HEAD_FINANCE_OPERATIONS', 1, 'Financial close within timeline',     'working days to close · G4'),
    ('HEAD_FINANCE_OPERATIONS', 2, 'Bank reconciliation current',         '% of accounts reconciled · AC4'),
    ('HEAD_FINANCE_OPERATIONS', 3, 'Nothing unactioned past its due date','% actioned inside the window · HFO3'),
    ('HEAD_FINANCE_OPERATIONS', 4, 'Team days filed',                     '% of the team''s working days filed · HFO4'),

    -- Vice President (Finance) --------------------------------------------
    ('VP_FINANCE', 1, 'Financial close within timeline',      'working days to close · G4'),
    ('VP_FINANCE', 2, 'Function cost against budget',         '% variance · X1'),
    ('VP_FINANCE', 3, 'Chairs below this one left vacant beyond a quarter', 'count, target zero · VP3'),

    -- Head — HR Operations ------------------------------------------------
    ('HEAD_HR_OPERATIONS', 1, 'Chairs with a named holder',          '% of chairs seated · HRO1'),
    ('HEAD_HR_OPERATIONS', 2, 'Joiners on record from day one',      '% of joiners on the master on their start date · HRO2'),
    ('HEAD_HR_OPERATIONS', 3, 'Nothing unactioned past its due date','% actioned inside the window · HRO3'),
    ('HEAD_HR_OPERATIONS', 4, 'Team days filed',                     '% of the team''s working days filed · HRO4'),

    -- HR Executive ---------------------------------------------------------
    ('HR_EXECUTIVE', 1, 'Joiners on record from day one', '% of joiners on the master on their start date · HRE1'),
    ('HR_EXECUTIVE', 2, 'Days filed',                     '% of working days filed · HRE2'),
    ('HR_EXECUTIVE', 3, 'Work returned for correction',   '% of work returned · HRE3'),

    -- Sales Manager --------------------------------------------------------
    ('SALES_MANAGER', 1, 'Sales against target',                 '% of target · K4'),
    ('SALES_MANAGER', 2, 'Pipeline cover for next period',       '% of next period''s target covered · K4'),
    ('SALES_MANAGER', 3, 'Nothing unactioned past its due date', '% actioned inside the window · K5'),
    ('SALES_MANAGER', 4, 'Team days filed',                      '% of the team''s working days filed · D8'),

    -- Zonal Manager --------------------------------------------------------
    ('ZONAL_MANAGER', 1, 'Zone revenue achievement',             '% of target · R8'),
    ('ZONAL_MANAGER', 2, 'Branches at or above plan',            '% of branches · D8'),
    ('ZONAL_MANAGER', 3, 'Mandate renewal rate',                 '% of mandates renewed · K1'),
    ('ZONAL_MANAGER', 4, 'Zone DSO against the Finance target',  'days · F4b'),
    ('ZONAL_MANAGER', 5, 'Branch quality score',                 '% score · D21'),
    ('ZONAL_MANAGER', 6, 'Regrettable attrition',                '% of the team · H1'),

    -- Location Partner / Franchisee Partner --------------------------------
    ('LOCATION_PARTNER', 1, 'Franchise revenue against agreed plan',        '% of plan · R6'),
    ('LOCATION_PARTNER', 2, 'File TAT against branch SLA',                  '% of files inside SLA · D3'),
    ('LOCATION_PARTNER', 3, 'Quality score on franchise files',             '% score · D21'),
    ('LOCATION_PARTNER', 4, 'Collection on sourced accounts',               '% of target · F4'),
    ('LOCATION_PARTNER', 5, 'Brand and SOP audit score',                    '% score · X2'),
    ('LOCATION_PARTNER', 6, 'Claim accuracy against computed entitlement',  '% accurate · F9'),

    -- Team Leader / Supervisor ---------------------------------------------
    ('TEAM_LEADER', 1, 'Daily target achievement',                 '% of target, target 95% · D3'),
    ('TEAM_LEADER', 2, 'Output per executive against benchmark',   'cases per executive · D3'),
    ('TEAM_LEADER', 3, 'Cases within TAT',                         '% of cases inside TAT · D1'),
    ('TEAM_LEADER', 4, 'Error rate',                               '% of work returned, target below 3% · D21'),
    ('TEAM_LEADER', 5, 'MIS submitted on time',                    '% submitted inside the window · M1'),

    -- Executive -------------------------------------------------------------
    -- Sixty-three people. See the note on cadence at the top of this file.
    ('EXECUTIVE', 1, 'Cases completed against target', '% of target · EX1'),
    ('EXECUTIVE', 2, 'Days filed',                     '% of working days filed · EX2'),
    ('EXECUTIVE', 3, 'Work returned for correction',   '% of work returned · EX3')
  ) as w(code, ord, name, unit)
  join public.chair ch on ch.code = w.code
 where not exists (
   select 1 from public.kpi_definition k
    where k.chair_id = ch.id and k.active
      and lower(btrim(k.name)) = lower(btrim(w.name)));

-- --------------------------------------------------- so it cannot go quiet again
-- A seated chair with no measures is invisible: the person opens Performance,
-- sees nothing, and there is no screen anywhere that says which chairs are in
-- that state. This is that screen's answer.
create or replace view public.kpi_registry_gap as
  select ch.id as chair_id, ch.code, ch.title,
         (select count(*) from chair_holder h
           where h.chair_id = ch.id and h.to_date is null)::int as seated,
         (select count(*) from kpi_definition k
           where k.chair_id = ch.id and k.active)::int as measures,
         (select count(*) from chair_measure m where m.chair_id = ch.id)::int as statements
    from chair ch
   where exists (select 1 from chair_holder h
                  where h.chair_id = ch.id and h.to_date is null)
     and not exists (select 1 from kpi_definition k
                      where k.chair_id = ch.id and k.active);

comment on view public.kpi_registry_gap is
  'Seated chairs with no measure set. Empty is the only acceptable state: a '
  'person in a chair with nothing to be measured on opens Performance and sees '
  'nothing, with no screen anywhere saying why.';

create or replace function public.kpi_registry_completeness()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select jsonb_build_object(
    'seatedChairs', (select count(*) from chair ch
                      where exists (select 1 from chair_holder h
                                     where h.chair_id = ch.id and h.to_date is null)),
    'withMeasures', (select count(*) from chair ch
                      where exists (select 1 from chair_holder h
                                     where h.chair_id = ch.id and h.to_date is null)
                        and exists (select 1 from kpi_definition k
                                     where k.chair_id = ch.id and k.active)),
    'peopleWithout', (select count(*) from chair_holder h
                       join kpi_registry_gap g on g.chair_id = h.chair_id
                      where h.to_date is null),
    'gaps', coalesce((select jsonb_agg(jsonb_build_object(
                        'code', g.code, 'chair', g.title,
                        'seated', g.seated, 'statements', g.statements)
                      order by g.seated desc, g.title)
                       from kpi_registry_gap g), '[]'::jsonb))
$fn$;

comment on function public.kpi_registry_completeness() is
  'What the MIS chair''s own measure -- "KPI registry completeness" -- is asking '
  'for: how many seated chairs have a measure set, and which do not.';

-- --------------------------------------------------------------- the check
do $do$
declare v_gaps text; v_thin text; n int;
begin
  select string_agg(code || ' (' || seated || ' seated)', ', ' order by code)
    into v_gaps from kpi_registry_gap;
  if v_gaps is not null then
    raise exception 'still seated with no measure set: %', v_gaps;
  end if;

  select string_agg(ch.code || ' (' || c || ')', ', ' order by ch.code) into v_thin
    from (select k.chair_id, count(*) as c from kpi_definition k
           where k.active group by k.chair_id) q
    join chair ch on ch.id = q.chair_id
   where q.c < 3
     and exists (select 1 from chair_holder h
                  where h.chair_id = ch.id and h.to_date is null);
  if v_thin is not null then
    raise exception 'a seated chair with fewer than three measures is not a set: %', v_thin;
  end if;

  -- and the stored accrual must be the one perf_accrual_kind would compute,
  -- which is the whole lesson of migration 200
  select count(*) into n from kpi_definition k
   where k.active
     and (case when perf_accrual_kind(null, k.unit) = 'LEVEL' then 'REPLACES' else 'ADDS' end)
         <> k.accrual::text;
  if n > 0 then
    raise exception '% measures carry an accrual the scorer would not agree with', n;
  end if;

  raise notice '206: % seated chairs, all with a measure set; % measures in the registry',
    (select count(*) from chair ch
      where exists (select 1 from chair_holder h where h.chair_id = ch.id and h.to_date is null)),
    (select count(*) from kpi_definition where active);
end $do$;
