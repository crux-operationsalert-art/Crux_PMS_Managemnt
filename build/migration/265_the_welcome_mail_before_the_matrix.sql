-- The welcome e-mail, to everyone carrying October measures, before any
-- escalation matrix goes to a client
--
-- The owner, 14 Oct: "Before starting the mailer, send a customised and
-- personalized email to all welcoming them and tell them what's pending.
-- Mark it important. CC to the managers above till Manish Shukla, not
-- above him." Recipients decided with the owner: all staff carrying
-- October measures (103), not only branch managers.
--
-- Personal to each: their own October scorecard with targets, and what is
-- pending from THEM -- the October numbers not yet filed (nobody had filed
-- any on the 14th), the escalation-matrix branches they cover that are
-- missing a contact (14 people; the administrator's all-branch view is not
-- coverage and is left out), and, for anyone with a team, that October's
-- KPIs shut on the 15th.
--
-- CC: every manager above the person, up to and including Manish Shukla,
-- and nobody above him. A line that never reaches him stops below his own
-- managers, and the Managing Directors -- beside him in the data, above
-- him in fact -- are never copied. Nor are the service account and client
-- contacts.
--
-- "Important": neither sender can set a priority header (the Apps Script
-- relay passes to/cc/subject/text/html only), so it is in the subject line.
--
-- Queued through the tool's own outbox, which crux-mail drains, so the send
-- is on the record. idempotency_key is unique: running this twice sends
-- nothing twice. A test copy of one message went to operations.alert first.
with recursive
cyc as (select id from perf_cycle where period_start = date '2026-10-01'),
manish as (select id from person where full_name = 'Manish Shukla'),
above_m(id, d) as (select manager_id, 1 from person where id = (select id from manish) and manager_id is not null
   union all select p.manager_id, d + 1 from above_m join person p on p.id = above_m.id
    where p.manager_id is not null and d < 10),
-- Nobody above Manish is copied: his own managers, and the Managing
-- Directors, who sit beside him in the data but above him in fact.
not_cc as (select id from above_m where id is not null
   union select p.id from person p join designation d on d.id = p.designation_id
          where d.title ilike '%managing director%' or d.title ilike '%chief executive%'),
staff as (select p.* from person p where p.work_email is not null and p.superseded_by is null
     and coalesce(p.employee_type::text, '') not in ('CLIENT_CONTACT', 'SERVICE_ACCOUNT')
     and exists (select 1 from perf_assignment a join cyc on cyc.id = a.cycle_id
                  where a.person_id = p.id and a.state <> 'WITHDRAWN')),
up(person_id, id, d) as (
   select s.id, s.manager_id, 1 from staff s where s.manager_id is not null
   union all
   select up.person_id, p.manager_id, up.d + 1 from up join person p on p.id = up.id
    where p.manager_id is not null and up.d < 10 and up.id <> (select id from manish)
      and up.id not in (select id from not_cc)),
cc as (select up.person_id, string_agg(distinct m.work_email, ', ') cc
         from up join person m on m.id = up.id
        where up.id not in (select id from not_cc) and m.work_email is not null
          and coalesce(m.employee_type::text, '') not in ('CLIENT_CONTACT', 'SERVICE_ACCOUNT')
          and m.id <> up.person_id
        group by 1),
meas as (select a.person_id,
   string_agg('  - ' || a.name || ': ' ||
     case when coalesce(a.unit, '') ilike '%rupee%' then '₹' ||
            (case when a.target_value < 1000 then trunc(a.target_value)::text
             else regexp_replace(left(trunc(a.target_value)::bigint::text, length(trunc(a.target_value)::bigint::text) - 3),
                                 '(\d)(?=(\d\d)+$)', '\1,', 'g') || ',' || right(trunc(a.target_value)::bigint::text, 3) end)
          else trim(to_char(a.target_value, 'FM999999990.##')) || ' ' ||
               coalesce(perf_unit_plain(coalesce(a.unit, (select k.unit from kpi_definition k where k.id = a.kpi_id))), '') end
     || ' (weight ' || trim(to_char(a.weight_pct, 'FM990.##')) || '%)'
     || case when (select count(*) from perf_assignment x where x.part_of_id = a.id and x.state <> 'WITHDRAWN') > 0
             then ', split across ' || (select count(*) from perf_assignment x where x.part_of_id = a.id
                                         and x.state <> 'WITHDRAWN') || ' client lines' else '' end,
     E'\n' order by a.weight_pct desc, a.name) lines,
   count(*) filter (where not exists (select 1 from perf_entry e where e.assignment_id = a.id
        or e.assignment_id in (select x.id from perf_assignment x where x.part_of_id = a.id))) unfiled,
   count(*) n,
   bool_or(a.name = 'Branch revenue') is_bm
  from perf_assignment a join cyc on cyc.id = a.cycle_id
 where a.state <> 'WITHDRAWN' and a.part_of_id is null group by 1),
st as materialized (select branch_id, complete_levels from branch_matrix_state),
mx as (select s.id, count(*) scope, count(*) filter (where coalesce(st.complete_levels, 0) < 5) pending
         from staff s cross join lateral matrix_scope_branches(s.id) b left join st on st.branch_id = b.branch_id
        where s.app_role::text <> 'ADMIN' group by s.id),
msg as (
  select s.id, s.work_email, cc.cc,
    initcap(split_part(regexp_replace(btrim(s.full_name), '[._]', ' ', 'g'), ' ', 1)) first,
    (select d.title from designation d where d.id = s.designation_id) desig,
    (select m.full_name from person m where m.id = s.manager_id) mgr,
    meas.lines, meas.unfiled, meas.n, meas.is_bm,
    coalesce(mx.pending, 0) mx_pending, coalesce(mx.scope, 0) mx_scope,
    (select count(*) from staff r where r.manager_id = s.id) reports
  from staff s join meas on meas.person_id = s.id left join cc on cc.person_id = s.id left join mx on mx.id = s.id),
items as (
  select msg.id, array_remove(array[
    case when unfiled > 0 then 'October numbers: nothing has been filed yet on ' || unfiled || ' of your ' || n ||
      ' measures. File each one under Performance & appraisal > Daily update, on its own cadence' ||
      case when is_bm then ' - your revenue against each client line, so the branch total adds itself up.' else '.' end end,
    case when mx_pending > 0 then 'Escalation matrix: ' || mx_pending || ' of the ' || mx_scope ||
      ' client branches you cover are missing a contact at one or more of the five levels. The matrix goes to ' ||
      'the banks only once a branch is complete, so please fill these in under Clients this week.' end,
    case when reports > 0 then 'Your team: ' || reports || case when reports = 1 then ' person reports' else ' people report' end ||
      ' to you. Check their October measures under My team > Performance mapping. October''s KPIs can be ' ||
      'changed until 15 October; after that the month is shut.' end], null) list
  from msg),
mail as (
  select msg.id, msg.work_email, msg.cc,
    'Important: Welcome to Crux, ' || msg.first || ' - your October scorecard and what is pending' subject,
    'Dear ' || msg.first || ',' || E'\n\n' ||
    'Welcome to Crux - the tool Crux Risk Management now runs its operations and performance on. ' ||
    'This note is written for you: your scorecard for October 2026, and what is still pending from you.' || E'\n\n' ||
    'YOUR OCTOBER SCORECARD' || coalesce(' (' || msg.desig || ')', '') || E'\n' || msg.lines || E'\n\n' ||
    case when msg.is_bm then 'Your revenue target is this October''s business plan for your branch plus 10%, split ' ||
      'by client as the plan has it. Collection is twice revenue, turnaround is 48 hours a case, and quality is 95%. ' ||
      'Your branch figures add up into the company''s.' || E'\n\n' else '' end ||
    case when cardinality(items.list) > 0 then 'WHAT IS PENDING FROM YOU' || E'\n' ||
      (select string_agg(o.n || '. ' || o.t, E'\n' order by o.n) from unnest(items.list) with ordinality o(t, n)) || E'\n\n'
      else '' end ||
    'Open Crux: ' || (select value from app_setting where key = 'app_url') || E'\n' ||
    'Sign in with your Google work account (' || msg.work_email || ').' || E'\n\n' ||
    'If anything above looks wrong, reply to this e-mail' || coalesce(' or speak to ' || msg.mgr, '') || '.' || E'\n\n' ||
    'Regards,' || E'\n' || 'Operations, Crux Risk Management Pvt Ltd' body
  from msg join items on items.id = msg.id)
insert into outbox (idempotency_key, template_key, entity_type, entity_id, recipient, cc_addr, subject, body)
select 'WELCOME_2026_10:' || mail.id, 'WELCOME_2026_10', 'person', mail.id, mail.work_email, mail.cc,
       mail.subject, mail.body
  from mail
on conflict (idempotency_key) do nothing;
