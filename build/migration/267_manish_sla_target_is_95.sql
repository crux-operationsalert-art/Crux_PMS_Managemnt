-- Manish Shukla's "SLA and TAT adherence" target is 95, not 5
--
-- The unit says it: "% of cases inside TAT, target 95%". The target said 5,
-- and because a percentage is copied down, not divided, nine Team Leaders'
-- "Cases within TAT" had inherited the same 5 -- each of them was being
-- asked to get five per cent of cases inside TAT. Owner, 16 Oct: "fix
-- Manish's target to 95". Through perf_target_set, so the copy runs down the
-- line the way the tool says it does; measured first in a rolled-back
-- transaction: exactly those ten measures move, 5 -> 95, and nothing else.
do $do$
declare o jsonb; n int;
  v_admin uuid := (select id from person where work_email = 'operations.alert@cruxindia.co.in');
  v_cycle uuid := (select id from perf_cycle where period_start = date '2026-10-01');
  v_sla uuid;
begin
  select a.id into v_sla from perf_assignment a join person p on p.id = a.person_id
   where p.full_name = 'Manish Shukla' and a.cycle_id = v_cycle
     and a.name = 'SLA and TAT adherence' and a.state <> 'WITHDRAWN';
  if v_sla is null then raise exception 'Migration 267: Manish''s SLA measure is not there.'; end if;
  o := perf_target_set(v_admin, v_sla, 95, true);
  if o->>'error' is not null then raise exception 'Migration 267: %', o; end if;
  select count(*) into n from perf_assignment where cycle_id = v_cycle and state <> 'WITHDRAWN'
     and rolls_into_id = v_sla and target_value = 5;
  if n > 0 then raise exception 'Migration 267: % measure(s) under it still read 5.', n; end if;
  raise notice 'Migration 267: Manish''s SLA target is 95, and the line below him with it.';
end
$do$;
