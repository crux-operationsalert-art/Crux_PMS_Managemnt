# Holidays and the strike clock

Loaded 2026-09-15 as migration `crux_holidays_2026_rbi`: the RBI banking-centre
holiday list for 2026, supplied by the owner. 43 dates. All 43 date/day-of-week
pairs were checked and are internally consistent.

## Why only six are confirmed

`working_hours_after()` decides when a strike clock has run out. Its holiday
test is, in full:

```sql
exists (select 1 from holiday h where h.day = cur::date and h.confirmed)
```

**There is no location term.** Any confirmed holiday stops the clock for
everyone, everywhere. And `holiday` has `PRIMARY KEY (day)`, so the table
cannot hold one row per centre even if the function wanted it to.

The RBI list is overwhelmingly centre-specific — Thiruvalluvar Day is Chennai
only, Chapchar Kut is Aizawl only, Losar is Gangtok only. Confirming all 43
would pause the Mumbai strike clock 43 times a year instead of the handful that
actually apply there, and every TAT would be too generous. That is the same
class of defect as the empty holiday table it replaces, pointing the other way.

So `confirmed = true` is set on the six dates that genuinely apply everywhere:

| date | holiday |
|---|---|
| 2026-01-26 | Republic Day |
| 2026-04-01 | Annual Closing of Bank Accounts |
| 2026-04-03 | Good Friday |
| 2026-08-15 | Independence Day |
| 2026-10-02 | Gandhi Jayanti |
| 2026-12-25 | Christmas Day |

The other 37 are loaded with `confirmed = false`: recorded, visible, and
carrying their centre list in `applies_to`, but inert. Any 2026 row from
earlier seeding that was still confirmed has been unconfirmed, because an
unverified date that stops the clock nationwide is exactly what this table
exists to prevent.

## What is still owed, and it is a decision not a task

Making centre-specific holidays count needs three things, and the third is the
owner's:

1. `working_hours_after(p_from, p_hours)` gains a place argument and filters
   `applies_to`. Backwards compatible if it defaults to null meaning "All
   India only". Call sites are `cases.js:69` and `worker.js:63`, both of which
   have a case, hence a branch, hence a place.
2. `holiday` loses `PRIMARY KEY (day)` in favour of a key on (day, centre), so
   one date can apply to several centres independently.
3. **A mapping from branch location to RBI banking centre.** RBI publishes ~30
   centres; the branch master has hundreds of towns. A branch in a small town
   follows some centre, and only Crux can say which. Without that mapping the
   first two changes have nothing to join on.

Until then the clock honours national holidays only. That is conservative — it
runs during a local holiday rather than pausing wrongly for the whole country —
and it is a documented position rather than an accident.

## Also worth a decision

Banks close on the **2nd and 4th Saturday** of each month. The working week
here is Mon–Sat with Saturday a half day (`sat`, `sat_hours`). A TAT clock that
counts those Saturdays as working time will run while the client's branch is
shut. Not currently modelled anywhere.
