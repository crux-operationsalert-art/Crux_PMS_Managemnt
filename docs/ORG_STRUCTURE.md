# The operating structure

The owner's *Crux — Operating Structure* document is the source of truth for
chairs, processes, RACI, information flow and the L1–L5 clearance ladders.
This note records what was taken from it, what was changed on the way in, and
how to check the result.

## A chair is a seat; the place is a property of the seating

The document draws **70 chairs** because it draws one per region — "Branch
Manager — Pune", "Branch Managers — North", "Branch Managers — South" and so
on. Those are not seventy different jobs. They are **34 seats**, several of
them held in more than one place at once.

The structure is stored that way:

| table | what it holds |
|---|---|
| `chair` | the 34 seats. **No location appears in a chair title.** |
| `chair_seating` | the 70 rows the document draws: this seat, held for this place, reporting to that seating |
| `chair_holder` | a person on a chair — many people may hold one chair |
| `coverage_rule` | that person's scope: client × zone × geography × branch × **product** |

So one Branch Manager chair can be held by many people, each covering one or
more locations, and two holders can share a location when they carry different
clients or products. That last case is what `coverage_rule.product` and
`coverage_rule.client_id` exist for; nothing in the chair needs to change.

The 70 document rows are kept whole in `chair_seating`, so the collapse to 34
seats can always be shown and undone. `chair_seating.source_ref` is
`ORGDOC!<the document's chair code>`.

The same multiplication runs one level deeper: **188 process rows are 150
processes**, ten of them drawn once per region. Those regional refs live in
`process_scope`, so `L6`, `L7` and `L9NO` all still resolve to the one
"Branch P&L".

## What was loaded

| | count | checked against |
|---|---|---|
| seats (`chair`) | 34 | 70 document chairs, grouped by the document's own code prefix |
| seatings (`chair_seating`) | 70 | every document chair kept |
| processes (`process`) | 150 | 188 document rows |
| process scope instances (`process_scope`) | 48 | the regional refs |
| RACI parties (`process_party`) | 896 | R, C and I; A is `process.owner_chair_id`, so accountability is single by construction |
| input links (`process_input`) | 374 | 441 in the document, 395 distinct, 374 after suppliers collapse onto seats |
| capability tracks | 21 | document states 21 |
| clearance levels | 105 | 21 tracks × 5, **not** 350 — the ladder was verified identical across every chair sharing a track before being stored once |
| dossier statements | 803 | accountabilities, measures, authority, tasks, sub-tasks |

Every headline count the document states about itself — 70 chairs, 188
processes, 441 input links, 21 tracks — was reproduced by the extractor before
anything was loaded. The dossier text was additionally verified by md5 against
the source after loading; the first attempt failed that check (`''` inside a
dollar-quoted string is two apostrophes, not an escape) and was corrected.

## Decisions taken on the way in

- **Seats are grouped by the document's code prefix** (`BM_P`, `BM_NO` → `BM`),
  not by title. Grouping on the title would have missed that the Pune back
  office is titled "Back Office / Processing Executives" while the northern one
  is "Back Office Executives — North". They are the same seat.
- **An em-dash suffix is a place only when it names one.** "— South Zone" is a
  place; "— Risk Operations", "— project based" and "— P&L, balance sheet and
  cash flow" are part of the name. The places are listed explicitly rather than
  guessed from the shape of the string.
- **Branch Manager reports to two different seats.** Five of its six seatings
  report to a Regional Manager; the South one reports to the Business Manager —
  South Zone, which sits between the Regional Manager and the branches while
  the South regional chair is vacant. The seat's default parent is Regional
  Manager; the real line is on each seating.
- **The Regional Manager purpose was rewritten.** The document's text for the
  richest seating named West's states; a seat cannot carry one region's
  geography, so that detail stays on the seating.
- **The 17 demo chairs were deleted.** They were seed data with
  `@example.invalid` holders and were never Crux's structure.

## Reading it back

- `org_chart()` — the whole tree, with each seat's places, holders and process
  counts.
- `org_chair('BM')` — one chair's full file: purpose, accountabilities,
  measures, authority, tasks, owned processes, what it needs and who supplies
  it, what it supplies, and the L1–L5 ladder with its knowledge test and
  psychometric gates.

Both are served by the `org` edge function at `/functions/v1/org` and
`/functions/v1/org/chair?code=…`, and drawn by the **Org chart** tab.

That tab is deliberately **not chair-gated**. The structure is who the company
is, not anyone's caseload — which is why it renders for an administrator who
has not been seated yet.

## Rebuilding the extract

```
python3 build/migration/org_extract.py   # document -> org_structure.json
python3 build/migration/org_model.py     # -> org_model.json, 34 seats
```

Both print their counts and assert the ones the document states.
