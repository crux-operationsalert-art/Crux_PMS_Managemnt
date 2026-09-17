-- =====================================================================
-- 105 · A holder knows which of the chair's places it holds
--
-- A holder was linked to the chair but not to the place. With one Branch
-- Manager chair held in six places, that meant all sixteen branch
-- managers appeared against Pune, and against Thane, and against every
-- other place.
--
-- The chair is still what decides what a person may see; the seating
-- simply records which of the chair's places they hold. It is nullable
-- because most people were seated from the USERS sheet, which names no
-- place — their location comes from coverage_rule, as it always did.
-- =====================================================================
alter table chair_holder add column if not exists seating_id uuid references chair_seating(id);
create index if not exists chair_holder_seating_idx on chair_holder (seating_id);

update chair_holder ch set seating_id = cs.id
from chair_seating cs, person p
where cs.chair_id = ch.chair_id
  and p.id = ch.person_id
  and ch.to_date is null
  and ch.seating_id is null
  and cs.holder_text is not null
  and lower(regexp_replace(p.full_name, '\s+', ' ', 'g'))
    = lower(regexp_replace(regexp_replace(cs.holder_text, '\s*—.*$', '', 'g'), '\s+', ' ', 'g'));
