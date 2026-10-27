-- A rate is a level, fewer days are better, and the stale WhatsApp copies
-- are retired
--
-- Three of the owner's answers of 27 Oct, applied.
--
-- 1. Q6, "Are cost per case, days to close and DSO levels rather than
--    counts?" -- answered by pointing at the BI dashboard: "This dashboard
--    will give you full understanding". It does. Its Revenue & collections
--    page defines "Months outstanding" as open invoice value divided by the
--    average monthly expected revenue, and "Average days to collect" as the
--    days from the end of the invoice month to the receipt, weighted by
--    amount; its TAT page reports median, average and P90 hours and the
--    share inside the SLA. Every one is a level -- a ratio, an average, a
--    duration per item -- and every one is better LOWER.
--
--    The registry had them as counts. perf_accrual_kind reads ADDS unless
--    the unit says %, score, rate or ratio, so "INR per case", "days",
--    "working days to close" and "cases per day" were summed across a
--    quarter: three months of a 45-day DSO read as 135 days. They are now
--    REPLACES, which is what the registry calls a level: the quarter reads
--    the value, it does not add the months.
--
--    "Output per executive" stays a count. It is a month's cases divided by
--    the people doing them -- a volume -- and its quarter target is the sum
--    of three monthly targets, so the quarter adds up.
--
-- 2. The same measures, and four more, were registered HIGHER is better: a
--    DSO of 90 scored above a DSO of 30, and more statutory penalties scored
--    above fewer. The registry's direction is the default every assignment
--    reads unless its manager overrode it (perf_direction_of), so the default
--    is corrected and every override is left exactly as the manager set it.
--    October is not scored until the month is over (269), so no score that
--    has been given moves.
--
-- 3. Q8, the WhatsApp backlog -- "You decide." Decided: retired. 723 copies
--    sat in wa_outbox (534 daily-count reminders of 30 Sep to 7 Oct, 91 of
--    the 14 Oct welcome letter, 89 activation notices of 30 Sep, 6 matrix
--    nudges, a PERF_UNSET and two tests). Every one is the WhatsApp twin of
--    an e-mail that was delivered at the time; no phone was ever linked.
--    Sent now, the day a phone is linked, each would arrive weeks late and
--    out of date -- "file today's count" for a day long gone. They are
--    marked ABANDONED with the reason, not removed, so the record of what
--    was meant to go stays.
--
-- 0. Found on the way, and this session's own: 264 moved Manish Shukla's
--    October measures to rupees by renaming the assignments in place --
--    "Revenue, rupees · R6" and "Collection, rupees · D1" -- and never
--    re-pointed them at the registry. Revenue still pointed at "Cost per
--    case" and Collection at "Escalation ratio", both registered LOWER, and
--    Escalation ratio a level. So his Revenue scored better the less there
--    was, and his Collection neither added up his twelve branch managers'
--    figures nor counted more as better. The twelve beneath him were set
--    against the registry's own "Branch revenue" and "Branch collection"
--    (264), which are HIGHER and add up; his two now point there too. The
--    rename-in-place is the only kind of this in the database: no other live
--    measure's name differs from the registry entry it points at.
do $do$
declare n_level int; n_dir int; n_live int; n_wa int; n_moved int := 0; n int;
  v_rev uuid; v_col uuid;
begin
  -- ---------------------------------------------------------------- 0
  select id into v_rev from kpi_definition where name = 'Branch revenue' and unit = 'rupees · R6';
  select id into v_col from kpi_definition where name = 'Branch collection' and unit = 'rupees · F4';
  if v_rev is null or v_col is null then
    raise exception 'Migration 273: the registry''s Branch revenue / Branch collection are not there to point at.';
  end if;
  update perf_assignment a set kpi_id = v_rev
   where a.state <> 'WITHDRAWN' and a.part_of_id is null
     and a.name = 'Revenue' and a.unit like 'rupees%' and a.kpi_id <> v_rev;
  get diagnostics n = row_count; n_moved := n_moved + n;
  update perf_assignment a set kpi_id = v_col
   where a.state <> 'WITHDRAWN' and a.part_of_id is null
     and a.name = 'Collection' and a.unit like 'rupees%' and a.kpi_id <> v_col;
  get diagnostics n = row_count; n_moved := n_moved + n;
  raise notice 'Migration 273: % renamed measure(s) now point at the registry entry they are.', n_moved;

  -- ---------------------------------------------------------------- 1
  update kpi_definition set accrual = 'REPLACES'
   where accrual = 'ADDS'
     and name in ('Cost per case', 'Company cost per case against budget',
                  'Field and agency cost per case',
                  'DSO against target', 'Zone DSO against the Finance target',
                  'Financial close within timeline', 'Month-end close within timeline',
                  'Days from case completion to local certification',
                  'Days from certification to receipt',
                  'Contract turnaround time', 'Launch time, approval to go-live',
                  'Release cycle time', 'Time to productivity for a new joiner',
                  'Vacancy closure TAT',
                  'Cases processed per day', 'Cases per day vs product benchmark');
  get diagnostics n_level = row_count;

  -- ---------------------------------------------------------------- 2
  select count(*) into n_live
    from perf_assignment a join kpi_definition k on k.id = a.kpi_id
   where a.state <> 'WITHDRAWN' and nullif(btrim(coalesce(a.direction,'')),'') is null
     and k.direction = 'HIGHER'
     and k.name in ('DSO against target', 'Zone DSO against the Finance target',
                    'Contract turnaround time',
                    'Days from case completion to local certification',
                    'Days from certification to receipt',
                    'Launch time, approval to go-live', 'Release cycle time',
                    'Time to productivity for a new joiner', 'Office downtime',
                    'Clean statutory audit', 'Zero statutory penalty',
                    'Statutory dues paid on time');
  update kpi_definition set direction = 'LOWER'
   where direction = 'HIGHER'
     and name in ('DSO against target', 'Zone DSO against the Finance target',
                  'Contract turnaround time',
                  'Days from case completion to local certification',
                  'Days from certification to receipt',
                  'Launch time, approval to go-live', 'Release cycle time',
                  'Time to productivity for a new joiner', 'Office downtime',
                  'Clean statutory audit', 'Zero statutory penalty',
                  'Statutory dues paid on time');
  get diagnostics n_dir = row_count;

  -- ---------------------------------------------------------------- 3
  update wa_outbox
     set state = 'ABANDONED',
         last_error = 'Retired 27 Oct 2026: the WhatsApp copy of an e-mail delivered at the time, '
                      'held while the tool was not live and stale by the time it could go '
                      '(owner, Q8: "You decide").'
   where state = 'QUEUED' and created_at < '2026-10-27';
  get diagnostics n_wa = row_count;

  raise notice 'Migration 273: % registry measure(s) now levels; % now lower-is-better (% live assignment(s) with no override follow); % stale WhatsApp copies retired.',
    n_level, n_dir, n_live, n_wa;
end
$do$;

-- --------------------------------------------------------------- the proof
do $guard$
declare v_bad text;
begin
  select string_agg(k.name, ', ') into v_bad from kpi_definition k
   where k.name in ('Cost per case', 'Zone DSO against the Finance target',
                    'Financial close within timeline', 'Cases processed per day')
     and perf_accrual_kind(k.id, k.unit) <> 'LEVEL';
  if v_bad is not null then
    raise exception 'Migration 273: still read as counts: %', v_bad;
  end if;
  if exists (select 1 from kpi_definition where name = 'Output per executive against benchmark'
                                            and perf_accrual_kind(id, unit) <> 'SUM') then
    raise exception 'Migration 273: a volume was turned into a level.';
  end if;
  select string_agg(k.name, ', ') into v_bad from kpi_definition k
   where k.name in ('Zone DSO against the Finance target', 'Zero statutory penalty')
     and perf_direction_of(k.id, k.unit, null) <> 'LOWER';
  if v_bad is not null then
    raise exception 'Migration 273: still higher-is-better: %', v_bad;
  end if;
  select string_agg(p.full_name || ' ' || a.name, ', ') into v_bad
    from perf_assignment a join person p on p.id = a.person_id
   where a.state <> 'WITHDRAWN' and a.part_of_id is null
     and a.name in ('Revenue', 'Collection') and a.unit like 'rupees%'
     and (perf_direction_of(a.kpi_id, a.unit, a.direction) <> 'HIGHER'
          or perf_accrual_kind(a.kpi_id, a.unit) <> 'SUM');
  if v_bad is not null then
    raise exception 'Migration 273: rupees still scored as lower-is-better or as a level: %', v_bad;
  end if;
  if exists (select 1 from perf_assignment a join kpi_definition k on k.id = a.kpi_id
              where a.state <> 'WITHDRAWN' and a.part_of_id is null
                and a.unit like 'rupees%' and k.unit not like 'rupees%') then
    raise exception 'Migration 273: a live rupee measure still points at a registry entry that is not one.';
  end if;
  if exists (select 1 from wa_outbox where state = 'QUEUED' and created_at < '2026-10-27') then
    raise exception 'Migration 273: a stale WhatsApp copy is still waiting to go.';
  end if;
  raise notice 'Migration 273: levels read as levels, days and defects as lower-is-better, and nothing stale is queued.';
end
$guard$;
