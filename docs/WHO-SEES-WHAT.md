# Who sees what, measured

"Data leakage, on few tabs people are able to see the data of others, or
full list of data creating confusion."

Measured against the live database on 2026-10-06, after migrations 239-242.
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
```
