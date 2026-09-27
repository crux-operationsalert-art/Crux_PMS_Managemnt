# The v2 design against what is live

Measured 27 Sep 2026 against `Crux App v2.dc.html` (the file the handoff
README names as the primary design) and the published `index.html`.

Method: the design's own user-visible strings were extracted by kind —
things you click (`label:`), table column headers (`<th>`), section titles
(`title:`) — the design's fixture data (staff names, rupee amounts,
addresses) was excluded, and each remaining string was looked for in the
built page. It is a proxy, not a pixel diff, and it undercounts anything I
implemented under different wording. Treat the numbers as the shape of the
gap rather than as a score.

---

## Headline

**The skeleton is complete and the data surfaces are mostly there. About a
quarter of the actions are.**

| What | In design | Built | |
|---|---:|---:|---|
| Screens (routes) | 26 | 26 | **100%** |
| Navigation groups and membership | 4 | 4 | **100%** |
| Table column headers | 80 | 60 | **75%** |
| Things you can click to do your job | 221 | 56 | **25%** |
| Section titles within screens | 106 | 11 | **10%** |

Every screen the design specifies exists and is reachable, with the same
four nav groups in the same order. What is thin is the inside of them: the
design is largely a set of **actions** — accept, answer, reassign, waive,
apply, escalate — and those are the part that is least built. 56
action-shaped controls from the design have no counterpart in the page, led
by *edit* (8), *accept* (5), *add* (5), *answer* (3), *export* (3),
*reassign* (3) and *waive* (3).

The engines underneath are in better shape than that number suggests: the
PLB curve, the dispute clock, the attribute gates, the merge, the coverage
resolver and the upload validators are all real and tested. The gap is
almost entirely between a correct engine and a control that lets somebody
reach it.

---

## The seat switcher was in the design and was never built

This is the most important finding, because it is the thing that was asked
for again today as if it were new scope.

The design carries a persona model: `PERSONAS` gives every chair its own
`nav` list, so a Branch Manager, an HR Head and an MIS analyst each see a
different set of screens. And it carries a switcher — `seats()`, commented
in the design as *"The seat switcher: which chairs this person holds, and
how to move between them"* — whose confirmation message reads:

> You are now acting as {chair}. Your tasks, escalations, reports and
> rights all follow the chair, not the person.

None of that is built. The live page has one flat `NAV` shown to everybody
and filters only by `allowed()`. So:

- there is no per-chair navigation, which is a design behaviour, not a
  nice-to-have — it is how the design keeps a Field Executive out of the
  Penalty ledger;
- there is no way to look at the tool as somebody else, which is what makes
  the above testable at all.

## Duplication

**Confirmed, and worse than cosmetic.** `vPeople` is declared **twice** —
at line 3490 (1,518 characters) and line 4638 (7,711). JavaScript takes the
later one, so the first is dead code that ships on every page load and can
never run. Nothing warned about it; a duplicate function declaration is
legal.

Every other screen is rendered by exactly one function — that one was
checked across all 29 screen functions, not assumed.

**Two Performance entries.** The nav shows *Performance & appraisal* and
*Performance & bonus* side by side under "Mine". The design has one
Performance entry and no concept of a bonus at all — the PLB scheme is
later scope from the PLB documents, not from the design. Folding bonus into
the one Performance screen as a section would match the design and remove
the choice nobody should have to make.

**Three stacked cards on HR.** Loose ends, Add a person and Two records one
person were each added on their own merits and all three live at the top of
the HR screen, which the design does not lay out that way.

---

## Where the labels diverge

A sample of design wording that the build renames rather than implements —
worth aligning because the design's wording is the one people were shown:

21 of the design's 24 `NAV_LABEL` entries are rendered with the identical
label. Three are renamed:

| Design | Built |
|---|---|
| Coverage & handlers | Places, coverage & owners |
| Messaging | E-mail |
| My team & structure | My team |

The last two matter slightly: *Messaging* in the design covers e-mail and
WhatsApp together, and the build splits them, so the top-level entry names
only half of itself. *My team & structure* names the structure the build
moved to a separate `org` sub-entry.

---

## What this does not measure

- Visual fidelity. No pixel comparison was done, and the handoff README
  explicitly says not to screenshot the design.
- The eight chat transcripts in `design-handoff/chats/`, which the README
  says are where the intent lives. They have not been read. Anything in
  them that never made it into `Crux App v2.dc.html` is invisible to this
  audit.
- Correctness of what *is* built. That is covered by the migration notes.

## The honest summary

Routes and data: near complete. Actions: about a quarter. Role-aware
navigation and the seat switcher: not started, and both are design
behaviour rather than additions. One real duplicate function, one
duplicated concept in the nav.
