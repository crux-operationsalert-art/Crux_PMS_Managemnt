-- =====================================================================
-- 103 · The People upload: mobile optional, and Excel floats
--
-- Both asked for by the owner.
--
-- 1. A missing mobile no longer fails the row. It was required, and only
--    22 of the 55 people on the USERS sheet have one anywhere in the
--    workbook — so "a file with any error applies zero rows" meant the
--    upload could never run. A blank mobile now loads and is recorded as
--    a question for HR instead of blocking everyone else.
--
-- 2. Excel writes a phone number pulled from a numeric cell as
--    "8104660689.0". Stripping non-digits turned that into 81046606890 —
--    eleven digits, and the wrong number. The trailing decimal is now
--    removed before the digits are read.
--
-- The full uv_people and ua_people bodies are applied in the database;
-- this file records the helper and the intent. See migration history
-- `people_upload_mobile_optional_and_excel_floats`.
-- =====================================================================
create or replace function ul_mobile(p text)
returns text
language sql
immutable
set search_path to 'public'
as $$
  -- drop a trailing Excel decimal, then keep the digits
  select nullif(regexp_replace(regexp_replace(coalesce(p,''), '\.0+$', ''), '[^0-9]', '', 'g'), '')
$$;

update upload_column set rule = 'Optional for now. 10 to 13 digits. Used for sign-in by OTP where there is no Google account; a person loaded without one is listed for HR to complete.'
where kind = 'People' and name = 'mobile';

-- the USERS sheet carries no mobile column, but the escalation matrix does,
-- against the same addresses. Used as they are, per the owner.
update person p set mobile = m.num, updated_at = now()
from (
  select lower(trim(x.email)) as email, min(ul_mobile(x.mobile)) as num
  from stg.matrix x
  where stg.present(x.email) and ul_mobile(x.mobile) ~ '^[0-9]{10,13}$'
  group by 1
) m
where p.superseded_by is null and p.mobile is null and lower(p.work_email) = m.email;
