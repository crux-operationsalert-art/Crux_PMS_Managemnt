# What is actually enforced, and where

Written 27 Sep after the owner, using act-as, found a Field Executive being
shown Penalty ledger, Data setup and Settings.

## A correction first

The commit that fixed the navigation (2d3a6f1) says the real check "belongs
in the services, per endpoint, and most of them do not have it yet."

**That is wrong.** I wrote it before reading `api/scope.ts`. The services do
enforce scope, and have all along. The gap was the navigation only. The
correction matters because an overstated security gap sends people looking
for a hole that is not there, and because the fix I shipped is smaller than
that sentence implies.

## What the services do

`api/scope.ts` — copied verbatim into `ops` — builds a scope for every
authenticated request, from the person, not from anything the browser sends:

| Piece | Built from |
|---|---|
| `chairs` | `chair_holder` rows that are still open |
| `subtreeIds` | recursive walk down from the primary chair |
| `branches()` | `coverage_rule` resolved through `coverage_resolve` |
| `clientView` | `client_view_policy` keyed on the person's department |
| `isAdmin` | `app_role = 'ADMIN'` — every chair, every branch, deliberately |

`api/index.ts:102` and `ops/index.ts:88` call `buildScope` on every request
and hand it to the route. Routes then filter on it, and refuse with
`out_of_scope` rather than returning somebody else's rows — `matrix.ts` is
the clearest example, checking both the branch and the `clientView` kind
before it answers.

`emptyReason()` exists so an empty page says *which* empty it is: no chair
yet, or a chair with no coverage. That is the D8 rule — an empty list and no
reason is the one thing that must never happen.

## What each service enforces

| Service | Scope | How |
|---|---|---|
| `api` | full | `buildScope` per request; routes filter on `subtreeIds`, `branches()`, `clientView` |
| `ops` | full | same file, same rules |
| `plb` | own model | "your own sheet, or you run the scheme", checked inside each `SECURITY DEFINER` function so a caller that skips the service is refused too |
| `hr` | ADMIN or HR | checked in the route *and* again in `person_add` / `auth_act_as` |
| `crux` | ADMIN for uploads, mail, reset | checked before the route runs |

`plb` and `hr` carry `scope: null` on purpose — "your own sheet" and "HR, or
an administrator" are not coverage questions, and carrying a scope nothing
reads would invite somebody to start reading it.

## What was actually broken, and is now fixed

The **navigation**. `allowed()` asked two questions — is this one of three
admin tabs, and is Settings allowed — so every other screen appeared for
anyone who could sign in. Measured across six chairs:

| | before | after | design |
|---|---:|---:|---:|
| Field Executive | 18 | 8 | 7 + bonus |
| Team Leader | 18 | 9 | 8 + bonus |
| Branch Manager | 18 | 14 | 13 + bonus |
| Location Partner | 18 | 15 | 14 + bonus |
| HR | 19 | 17 | 16 + bonus |
| Administrator | 21 | 21 | 20 + bonus |

Typing a URL for a screen you are not given lands on Today.

## What is still open

1. **The scope level is carried but unused.** `CHAIR_LEVEL` gives every chair
   one of eight levels from the design — exec, team, branch, region,
   national, function, partner, admin. The services scope by *coverage and
   chair subtree*, which is a different axis. Where the design says a
   regional manager sees three locations and a branch manager one, the tool
   says "whatever coverage_rule gives you". Those usually agree. They are not
   the same rule, and nothing currently checks that they agree.

2. **Nothing reconciles nav against service.** A chair could be given a
   screen whose endpoints will refuse it, or denied a screen it can still
   call. A test that walks every chair against every endpoint would catch
   both; there isn't one.

3. **`ops/routes/mis.ts` and `ops/routes/auto.ts`** have no scope references
   at all. They may not need any — MIS is a reporting surface and Automations
   is administrator work — but neither has been checked, and "probably fine"
   is not a finding.
