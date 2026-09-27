-- The registry says every measure ADDS, and forty-six of them are
-- percentages.
--
-- Found by running the monthly cycle against the live project: a KPI was
-- assigned, 40 was filed on one day and 35 on the next, and the month stood
-- at 35 rather than 75. That is the RIGHT answer -- the measure is "% of
-- target" and a percentage is a level, not a quantity -- but it is right for
-- the wrong reason, and the wrong reason is one edit away from being a
-- disaster.
--
--   kpi_accrual is (ADDS, REPLACES).
--   61 active measures. All 61 say ADDS. None has ever said REPLACES.
--   46 of the 61 have a unit that is a percentage or a score.
--
-- perf_accrual_kind asked the accrual enum first and only fell back on the
-- unit when the enum said nothing it recognised. 'adds' happens to match
-- none of its SUM patterns -- sum, total, cumul, count -- so all 61 fell
-- through to the unit test and all 61 came out right. Had that list
-- contained 'add', every one of those forty-six percentages would have been
-- summed across the month, and 93% and 88% would have become 181% again,
-- which is the exact failure the v2 design names and this model was built to
-- prevent.
--
-- So two changes, and the second is the one that matters:
--
-- 1. The precedence is now deliberate and written down. REPLACES is an
--    explicit statement by a person and wins. A unit that reads as a rate,
--    a percentage or a score wins over ADDS, because a percentage marked
--    ADDS is a field nobody filled in rather than a claim anybody made.
--    ADDS decides only when the unit is silent.
--
-- 2. The registry is corrected, so the data says what it means and the
--    fallback stops being load-bearing. 46 rows.

create or replace function public.perf_accrual_kind(p_kpi uuid, p_unit text)
returns text language plpgsql stable as $fn$
declare a text; u text;
begin
  if p_kpi is not null then
    select lower(k.accrual::text) into a from kpi_definition k where k.id = p_kpi;
  end if;

  -- An explicit REPLACES is somebody saying so. Nothing overrides it.
  if a is not null and (a like '%replace%' or a like '%level%' or a like '%latest%'
                        or a like '%last%' or a like '%avg%' or a like '%aver%') then
    return 'LEVEL';
  end if;

  -- The design's own test, and it beats ADDS on purpose: /%|score/i is a
  -- level. A measure counted in per cent that claims to accumulate is a
  -- default nobody changed, and believing it is how a month reaches 181%.
  u := coalesce(p_unit, '');
  if u ~* '%|score|rate|ratio|pct|percent|per cent' then return 'LEVEL'; end if;

  -- Only now does ADDS get to speak, and it agrees with the fallback anyway.
  return 'SUM';
end $fn$;

-- The registry, corrected. Only where the unit plainly says so, and only
-- where nobody has already said otherwise.
update kpi_definition
   set accrual = 'REPLACES'
 where active
   and accrual = 'ADDS'
   and coalesce(unit,'') ~* '%|score|rate|ratio|pct|percent|per cent';

revoke all on function public.perf_accrual_kind(uuid, text) from public, anon, authenticated;
