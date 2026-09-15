# What actually stands between the app and live data

> **Status 2026-09-15 — items 1 and 2 are now resolved.** The generic
> `/api/:table` endpoint exists (`build/api/routes/table.js`) and the
> translation layer is applied (`build/supabase/03_seam_views.sql`, live as
> migration `crux_seam_views_for_prototype`). Item 3 stands: the database
> still holds only sample data until the masters are loaded. The analysis
> below is kept because it explains why the seam layer exists.

Written 2026-09-15, from the live database (`oxpwqfbtbxlvuqpztbwg`) and the
shipped application, not from the design documents.

`GO_LIVE_GITHUB_SUPABASE.md` Step 4 says pointing the app at the API is one
line in `config.js`, because "the application already speaks the shape these
endpoints return". **Against this database that is not true.** This file
records exactly why, so the decision is made on evidence.

---

## 1. The API does not expose what the app calls

`crux-data.js` swaps in an HTTP adapter that speaks four generic operations
against any table:

```
GET    /api/<table>?col=v&col=v     POST   /api/<table>
PATCH  /api/<table>/<id>            DELETE /api/<table>/<id>
```

`build/api/server.js` mounts named routers — `/api/cases`, `/api/matrix`,
`/api/pms`, `/api/people`, `/api/penalties`, and now `/api/upload` and
`/api/sample`. There is **no generic `/api/:table` handler**, so almost every
read the app issues would 404. Step 3 of the go-live document specifies this
endpoint; it was never written.

## 2. The two data models are different models

Not different names for the same thing — different shapes, different key
types, and in one case the same name for a different concept.

| The app asks for | The database has | Gap |
|---|---|---|
| `person{id, name, chair, zone_id, reports_to, is_sample}`, id `PS-0084` | `person{id uuid, full_name, work_email, designation_id, manager_id, …}` | field names, and **string id vs uuid** |
| `client{id, code, name}`, id `CL-034` | `client{id uuid, code, name, status, …}` | string id vs uuid |
| `holiday{date, name, scope, confirmed}` | `holiday{day, name, applies_to, source, confirmed, batch_id}` | `date`→`day`, `scope`→`applies_to` |
| `business_record{period, zone_id, client_id, mtd, revenue, projected_expense, src}` | `business_record{period, business_date, client_id, geo_node_id, owner_id, mtd, day10, target, revenue, source_ref}` | `zone_id`→`geo_node_id`, no `projected_expense`, `src`→`source_ref` |
| `rate{client_id, zone_id, scope, value, effective_from, effective_to, origin, months_observed, months_of_history, note}` | `rate{code, client_id, scope, value, currency, …}` + `rate_location(rate_id, geo_node_id)` | zone moved to a join table; `origin`, `months_observed`, `note` absent |
| `geo_zone{id, name, group, region, is_aggregate}` | `geo_node{id, parent_id, level, name, group_name, region}` | mappable: `group_name`→`group`, `is_aggregate` from `level` |
| `forecast_scenario{key, label, multiplier, stance, source}`, 4 rows | `forecast_config{id, scenarios jsonb}` | unroll the jsonb |
| `assignment{id, zone_id, client_id, person_id, location_head_id, effective_from, effective_to, is_sample}` | `assignment{id, ref, case_id, assignor_id, from_location_id, allocated_to_id, current_state, breach_cycle_no, …}` | **same name, different concept.** The app means client×zone×handler coverage — that is `coverage_rule` here. The live `assignment` is an OGL work item. |
| `tenday_snapshot{id, period, location, day10_revenue, actual_revenue, live_addition, sheet_x5, …}` | — | **does not exist** |
| `rate_anomaly{id, client_id, zone_id, period, observed, expected, kind, note}` | — | **does not exist** |

The id-format difference is the awkward one. The app's rows reference each
other by string key (`assignment.zone_id = 'ZN-BHUVANESHVAR_ODISHA_ZO'`), so
any translation layer must mint **stable** string ids from uuids, not
ad-hoc ones, or cross-references break between requests.

## 3. The database holds no real data yet

Everything currently in it is `sample_seed()` placeholder data — 23 people, 7
clients, 19 branches — all tagged in `sample_row` and removable with
`select * from sample_purge();`.

Meanwhile the application's seed carries the **real audited figures**: 471
people, 1,373 business records, 159 rates, 46 clients, 47 zones. So today the
app on seed data shows *more* real business content than the database would.
Wiring it up before the masters are loaded would make the tool look emptier,
not better.

---

## Consequences for sequencing

This changes the order of the remaining work:

1. **Host the frontend now.** It is complete and it works — verified booting
   with zero page errors and zero failed requests. Leave `CRUX_API_BASE`
   empty; the go-live document explicitly keeps seed mode as the demo path.
2. **Deploy the API** for `/api/upload` — that is what makes master loading
   possible through the product rather than by SQL.
3. **Load the masters** in the `DEPLOY.md` §5 order. Holidays are a blocker:
   an empty holiday table is why every TAT was silently wrong before.
   `is_assigned_handler` must be set on exactly one row per client × location
   or every MIS total reads zero, correctly and confusingly.
4. **Then** build the translation layer — the generic `/api/:table` endpoint
   plus roughly ten views presenting live data in the seam's shape, with
   stable synthesised ids. Each view validated against the seed shape before
   it is trusted.
5. **Then** flip the one line in `config.js`, and run the five audits in
   `APPLICATION_AUDIT_LOG.md` §E that a prototype cannot.

Step 4 is the real work, and it is the step no document currently accounts
for. It is not a rebuild of the application — Rule Zero holds, no screen
changes — but it is not one line either.

## What must not happen

`pg_cron` runs `crux-tick` (15 min) and `crux-mail` (every minute) in this
database today. `build/api/worker.js` does the same work. **Never run both** —
that is the 1,892-send storm's exact shape. `render.yaml` therefore has no
worker service, and the reason is written at the bottom of that file.
