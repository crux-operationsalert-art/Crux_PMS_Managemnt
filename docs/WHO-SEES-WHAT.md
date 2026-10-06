# Who sees what, measured

"Data leakage, on few tabs people are able to see the data of others, or
full list of data creating confusion."

Measured against the live database on 2026-10-06, after migrations 239-245.
The short answer is that there is no permission leak, and that the two
things which looked like one are a data problem and a screen problem.

Re-measure with the queries at the foot of this page.

---

## The rule, as the database actually applies it

`perf_rel(actor, person)` is the whole of it, and it answers in this order:

| | |
|---|---|
| `self` | the same person |
| `admin` | the actor holds ADMIN — for everybody |
| `manage` | the person is one step below the actor |
| `watch` | the person is further below the actor |
| null | anybody else — and `perf_may_see` is false |

`perf_may_see` is "the relation is not null". `perf_may_set` is "the
relation is manage or admin". Human Resources is deliberately not on either
list: migration 218 removed it, 239 briefly put it back, and 241 took it
out again. Running the scheme — issuing sheets, certifying, publishing — is
`maySetUp` in the service and is a different question.

## What that comes to, over 104 people

| Can see | People |
|---:|---|
| nobody but themselves | **89** |
| 1 to 9 others | 6 |
| 10 to 49 | 5 |
| 50 or more | 4 |

Eighty-nine of a hundred and four see only their own numbers. That is the
shape it should be.

The fifteen who see more:

| Person | Chair | Sees | May set |
|---|---|---:|---:|
| Shantanu Suravase | Assistant Vice President (ADMIN) | 103 | 103 |
| Operations Alert | — (ADMIN) | 103 | 103 |
| Arun Bodupali | Managing Director | 101 | 2 |
| Manish Shukla | Head — Operations | 88 | 5 |
| Aniket Chalke | Branch Manager | 42 | **42** |
| Nitish Bhope | Zonal Manager | 25 | 8 |
| Avinash Chaskar | Branch Manager | 17 | **17** |
| Parag Mayekar | Branch Manager | 16 | **16** |
| Virendra Pal | Chief Executive Officer / Managing Director | 11 | 3 |

Every one of those numbers is the reporting line doing exactly what it
says. None of it is a leak. But three rows in that table are worth the
owner's attention, and they are not about permissions.

## Three things the measurement found, none of them a leak

### 1. A Branch Manager with forty-two direct reports

Aniket Chalke's "My team" is forty-two rows because forty-two people have
his id in `person.manager_id`. He may set all forty-two, because they are
all one step below him.

That is almost certainly the org chart being flat rather than the
organisation being flat — a branch with forty-two people in it usually has
supervisors in between. Until somebody says otherwise the tool is right to
show forty-two, and the fix is in the chart, not the code. The same applies
to Avinash Chaskar (17) and Parag Mayekar (16).

**This is the likeliest thing behind "a full list of data creating
confusion" for anybody who is not an administrator.**

### 2. The chief executive sees eleven people

Virendra Pal holds "Chief Executive Officer / Managing Director" and reaches
eleven people. Arun Bodupali holds "Managing Director", reports to nobody,
and reaches a hundred and one.

So the company has two roots, and the one the title says is the top is not
the one the reporting line says is the top. Nothing is leaking either way —
but if the chief executive opens Performance and sees eleven people, the
answer is the chart, not the screen.

### 3. Two people nobody can set measures for

Manoj Batham and Shyam Sundar Kalta have no manager and hold no chair.
`perf_rel` returns null for everybody except an administrator, so no manager
can give them a KPI and they appear on no team. They are not invisible —
they can sign in and file — but nobody owns their numbers.

## What was actually fixed

Two things did produce "a full list", and both are closed:

- **531 of 639 active people were client-bank contacts**, not staff, so
  every people picker and every headcount was mostly bank managers.
  Migration 238 set them inactive; the staff list went 639 → 104.
- **An administrator's "My team" listed all 103 other people.** The service
  still returns them — an administrator has to be able to reach anyone — but
  the screen now holds that list behind a search box and draws only the
  reporting line, so the heading and the contents agree.

## The sweep

Every route handler in every edge function that touches `person` or
`chair_holder` was checked for a gate. Seven came back ungated on a first
pass and all seven were false positives: six carry `requireChair` or
`requireScreen`, and `hr/options` checks `mayAdd` inside the handler. No
route returns a list of people without a gate in front of it.

---

## All people, and why it is not a leak (migration 244)

There is now one screen that deliberately shows every member of staff:
**All people**, the second tab on My team & structure. It is the
administrator's and Human Resources', on the same test the rest of the tool
already applies to those two — `/access` uses `isAdmin or level = 'hr'`,
`person_add` is HR's, and `org_move_person`'s own first question is
`app_role = 'ADMIN' or department = 'Human Resources'`. Everybody else gets
`{mayUse:false}` and a sentence saying their team is the chart.

It exists because a chart cannot draw an absence. Measured the day it was
built: of 103 staff, 3 have no manager, 2 hold no chair, 49 have no
designation and 13 have no location — and not one of those facts is visible
in a drawing of who reports to whom.

**It widens nothing about performance.** `org_people_table` returns a name,
an employee number, a designation, a chair, a place and a manager. It does
not touch `perf_rel`, `perf_may_set` or `perf_line`, and 241 still stands:
HR may not set a named person's KPIs or targets. `test_people.sql` asserts
that as its last pair of checks, by asking `perf_may_set` for every person
outside HR's own line.

## Who is not in any of these lists (migrations 243 and 245)

Two kinds of row in `person` are not somebody who works here:

| | |
|---|---|
| `CLIENT_CONTACT` | the 531 bank contacts migration 238 took out |
| `SERVICE_ACCOUNT` | operations.alert@cruxindia.co.in, which administers the tool |

The service account keeps ADMIN and keeps signing in — `auth_login`,
`auth_whoami` and `perf_rel`'s administrator branch read `app_role` and
never `employee_type`. What it loses is being a person: the headcount, the
org chart, the people pickers, the measure-setting lists and the People
upload template.

243 widened the thirteen functions that already carried the contact
predicate. 245 closed the two it could not reach:

- `is_staff` is a **second** staff test — employee number, OR our own
  e-mail domain, OR a chair — and the domain arm said yes, so the People
  upload template carried the service account and the next upload would have
  put it back.
- `org_subtree`, `app_subtree`, `org_team_tree`'s report count and
  `perf_reminder_sweep` have **no** `employee_type` test at all. Rather than
  write the predicate a fifth time, the rule is kept by the table: the check
  constraint `person_service_account_reports_to_nobody` and the trigger
  `person_manager_is_not_a_service_account` make the reporting line
  structurally free of service accounts in both directions, so a walker
  written next year is covered without being told.

---

## Re-measuring

```sql
-- the distribution: how many people each person can see
with staff as (
  select p.id, p.app_role::text as role from person p
   where p.employment_status='ACTIVE' and p.superseded_by is null
     and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'),
n as (select count(*)::int as total from staff)
select case when s.role='ADMIN' then (select total from n)-1
            else (select count(*) from perf_line(s.id)) end as can_see,
       count(*) as people
  from staff s group by 1 order by 1;

-- anybody with an unusually wide team
select m.full_name, count(*) as direct_reports
  from person r join person m on m.id = r.manager_id
 where r.employment_status='ACTIVE' and r.superseded_by is null
   and coalesce(r.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
 group by m.id, m.full_name having count(*) >= 8 order by 2 desc;

-- anybody outside the reporting line altogether
select p.full_name from person p
 where p.employment_status='ACTIVE' and p.superseded_by is null
   and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
   and p.manager_id is null;

-- the gaps All people exists to find, as one row
select (o->'summary') as gaps
  from (select org_people_table(
          (select id from person
            where app_role='ADMIN' and employment_status='ACTIVE'
              and superseded_by is null limit 1)) as o) t;

-- the service account is out of the staff list by BOTH staff tests,
-- out of the upload template, and still an administrator over everybody
with a as (select id, full_name from person
            where lower(work_email)='operations.alert@cruxindia.co.in')
select (select full_name from a) as who,
       is_staff((select id from a))        as is_staff_says,
       person_is_staff((select id from a)) as person_is_staff_says,
       (select count(*) from upload_seed('People') t
         where t::text ilike '%operations.alert%') as rows_in_template,
       (select count(*) from person p
         where p.employment_status='ACTIVE' and p.superseded_by is null
           and p.id <> (select id from a)
           and perf_rel((select id from a), p.id) is distinct from 'admin')
         as people_it_is_not_admin_over;
```
