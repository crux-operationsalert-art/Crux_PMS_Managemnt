-- =====================================================================
-- 101 · chair_one_primary said the wrong thing
--
-- The index read "one primary holder per chair", which only makes sense
-- while a chair belongs to one person. A chair is a seat: Branch Manager
-- is held in Pune, Thane, North, South and the rest at the same time, so
-- that index refused the second holder.
--
-- The code already meant the other thing. scope.ts picks a person's
-- primary chair with chairs.find(c => c.is_primary), so is_primary is a
-- property of the person's seat list, not of the chair's holder list.
-- =====================================================================
drop index if exists chair_one_primary;
create unique index if not exists person_one_primary_chair
  on chair_holder (person_id) where (is_primary and to_date is null);
