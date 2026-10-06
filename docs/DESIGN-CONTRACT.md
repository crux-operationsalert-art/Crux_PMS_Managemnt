# The design contract

Everything here was measured out of **`Crux App v2.dc.html`**, the design
blueprint in this repo — not decided here. Where the tool and that file
disagree, the file is right. The counts are there so a claim can be checked
rather than argued about.

Re-measure with the commands at the foot of this page.

---

## Colour

Eighteen of the tool's tokens come straight from the blueprint. These are the
whole palette — a colour not on this list does not belong in the tool.

| Token | Value | What it is |
|---|---|---|
| `--paper` | `#f4f2ee` | the page |
| `--white` | `#fff` | cards, buttons |
| `--panel` | `#faf9f6` | hover, quiet fill |
| `--panel2` | `#fdfdfb` | quieter still |
| `--ink` | `#14161a` | headings |
| `--body` | `#3d434d` | body text |
| `--mute` | `#5c6470` | secondary text — **the most used colour in the design, 790 times** |
| `--line` | `#d8d5cd` | the default border |
| `--line2` | `#eeece6` | group divider |
| `--line3` | `#f0eee9` | the lightest rule |
| `--field` | `#cfcbc1` | input borders |
| `--blue` | `#3a5a80` | **the primary action, 483 uses** |
| `--blue-dark` | `#243b55` | link hover |
| `--blue-press` | `#2c4665` | pressed |
| `--terra` | `#b4562f` | accent: the rule under the header, the badge on a tab |
| `--terra-ink` | `#a03f18` | destructive text |
| `--terra-bg` | `#fdf6f3` | destructive tint |
| `--green` | `#2f7355` | agreed, accepted, complete |
| `--green-press` | `#255c44` | pressed |
| `--green-bg` | `#f4faf6` | success tint |
| `--gold` | `#8a6d1f` | waiting, needs attention |
| `--gold-ink` | `#7a5f18` | its text |
| `--gold-bg` | `#fdfaf2` | its tint |

**A status panel borders with its own colour, never a lightened one.** Green
on `#f4faf6` bordered `#2f7355`; amber on `#fdfaf2` bordered `#8a6d1f`;
terracotta on `#fdf6f3` bordered `#a03f18`. The tool had invented five pale
borders and three off-shade fills; all nine are gone.

## Buttons

Counted across every `<button>` in the blueprint:

| Count | Style | Meaning |
|---:|---|---|
| 65 | white, `#d8d5cd` border, default ink | the ordinary button |
| 54 | white, `#3a5a80` border and text | a secondary action |
| 43 | filled `#3a5a80`, white text | **the primary action** |
| 25 | white, `#a03f18` text, terracotta or grey border | destructive |
| 4 | filled `#2f7355` | agreeing to something |

**Filled terracotta does not appear once.** It was the tool's default button
on every screen until this was corrected. Terracotta is an accent, not a
surface.

In the tool: bare `button` is the filled blue primary; `.btn` and `.ghost` are
the white outline; `.danger` is the destructive outline; `.go` is an alias of
the primary.

## Type

- Headings: `Georgia, serif`, weight 400. Page title
  `clamp(21px,3.4vw,30px)`, letter-spacing `-0.01em`. Card titles 16–22px,
  most often **17px**.
- Everything else: `"Helvetica Neue", Helvetica, Arial, sans-serif`.
- The scale, by frequency in the blueprint: **11px** (491), 12.5px (270),
  12px (259), 11.5px (156), 13.5px (134), 13px (128). It is a small,
  dense, document-like scale. Anything above 14px outside a heading is drift.

## Navigation

The blueprint's own definition, and its own reason:

> Grouped navigation — ten flat tabs was too many to scan. Ideathon sits first
> and apart, because it is an invitation rather than a duty.

| Group | Screens |
|---|---|
| *(no label)* | Ideathon — a gradient pill, not a plain tab |
| **Mine** | Dashboard · My profile · Performance & appraisal · Visits & claims |
| **Work** | OGL Assignment · Escalations · Clients · My team & structure |
| **Company** | HR · Hiring & pending chairs · Joining · Penalty ledger · Coverage & handlers · Reports · History & audit trail · Messaging · Automations · Data setup · Settings |

Measurements: row `max-width:1280px`; tab `13.5px`, padding `10px 12px 8px`,
`min-height:44px`, hover `#faf9f6`; current tab marked by a `2px #3a5a80` bar
underneath, `margin-top:7px`; group label `11px`, `letter-spacing:.12em`,
uppercase, `#5c6470`, `border-left:1px solid #eeece6`; badge `11px` on
`#b4562f`, white, `radius 9px`.

**Use the blueprint's label, in full.** "Penalties" is a subject; "Penalty
ledger" is a thing you can open. Ten labels had been trimmed and all ten are
restored.

Seven screens are not in the blueprint's top row — Escalation matrix, Org
chart, MIS dashboard, 10-day view, Rate master, Report access, WhatsApp. They
are reached from inside a parent, which is how Company stays at eleven. In the
tool they keep their routes and appear in a strip under the header.

## Automations

The blueprint calls its Automations screen "the wireframe": every automation
drawn as a chain of four stages — **trigger → conditions → actions → notifies**
— with the guard beside it, "generated from the same data the engine reads, so
it cannot drift from the behaviour."

That data is `automations.js` at the repo root: **49 automations across eight
groups, 46 live and 3 blocked**. `build/data/automations.json` is the same
thing as JSON, which migration 141 has the database fetch over pg_net into the
`automation` table.

The tool's screen shows that chain **and what actually runs beside it**,
because they are not the same: seven jobs are configured, one has ever run
under its own name, and `CRUX_TICK` — in no configuration at all — has run
over 1,300 times and is what the other sweeps are folded into.

## Export

The blueprint offers one in 35 places. In the tool it is one control on every
card that has a table, reading the rendered table rather than the server, so
what you export is what you were looking at.

## Measured again, 2026-10-06

The commands at the foot of this page, run against the page as published.
Three divergences, all real, none of them accidental — and none of them
previously written down, which is the part that was wrong.

### Six colours in the page are not in the blueprint

```
#b9c2d4  #8c99b4  #5f7095  #34497a  #14203a      the team-tree depth ramp
#d6b24a                                          "part of the way" on the dashboard
```

**The depth ramp** paints the top border of a card in My team &amp; structure,
one step darker per level down. The blueprint has no people tree, so it has
no ramp to copy; this is one hue stepped light to dark, which is the right
shape for an ordered quantity and is not a fifth and sixth accent.

**`#d6b24a`** is the middle of the three states on the dashboard — on
target, part of the way, behind. The obvious choice was `--gold #8a6d1f`,
and it was tried first and failed: `--gold` and `--terra #b4562f` are 9.6
apart to a reader with full colour vision and **1.8 apart under
deuteranopia**, so on a doughnut the middle arc and the behind arc are one
arc. The tool's palette is deliberately muted and no three steps of it
separate. The replacement scale clears both tests — 30.3 and 24.7 on the
worst adjacent pair — at the cost of a lighter step that sits below 3:1
against the panel, which is why it is never the only thing carrying a
meaning: the legend has the words and the counts, every bar has its
percentage in ink beside it, and the table names every measure.

These are the only six. Everything else in the page is on the list above.

### One navigation label is not the blueprint's

| Blueprint | In the tool |
|---|---|
| Coverage &amp; handlers | Places, coverage &amp; owners |

The rule on this page is "use the blueprint's label, in full", and this
breaks it. It breaks it because migration 150c merged three screens —
places, coverage rules and owners — into one, and the blueprint's label
describes the narrower screen that no longer exists. Renaming it back would
make the label wrong about the screen. **The other twenty-three labels are
the blueprint's, verbatim.**

### The figures are larger than the type scale

The scale is 11–13.5px and the contract says anything above 14px outside a
heading is drift. Twenty rules now exceed it, and every one of them is a
FIGURE rather than prose: a counter, the number in the middle of a ring, a
stat tile's value, a count on a waiting list.

The blueprint has no stat tiles, so it has nothing to measure these
against — the same situation the mobile bar is in, lower down this page. The
owner asked for the dashboard to follow `cruxindia/crux-console`, where the
whole method is one large tabular number per tile over a small uppercase
label. A 25px figure above an 10.5px label is that method; it is not 25px
body text, and the prose on those screens is still 11–13.5px.

## Still not matching

Stated plainly rather than quietly left:

- **`api/routes/pms.ts` line 306 has a latent jsonb bug.** `JSON.stringify()`
  on a value bound to a jsonb parameter is encoded a second time by
  postgres.js and lands as a jsonb *string*, not an object. The same defect in
  `ops` was caught by a check constraint and fixed in both places there. `api`
  cannot be redeployed through this tool — it outgrew what one call carries —
  so the daily-count `values` column will be wrong the first time somebody
  files a count. Moving that route into `ops` would fix it.
- **MIS saved views and comparison are built but unexercised.**
  `business_record` is empty until the Collections and Past performance
  uploads land, so both were proven against a fixture and the live endpoints,
  not against real months.

## Corrected in this document

- The blueprint has **no media queries at all** and no mobile bar. The tool's
  mobile bar is an addition, not drift; there is nothing to measure it
  against. It carries its own four short labels, because the nav labels are
  now the blueprint's full ones and four of those do not fit across a phone.

## Re-measuring

```sh
# every colour in the blueprint, by frequency
grep -o '#[0-9a-fA-F]\{6\}' 'Crux App v2.dc.html' | tr A-F a-f | sort | uniq -c | sort -rn

# every colour in the built page, to diff against the list above
grep -o '#[0-9a-fA-F]\{6\}' index.html | tr A-F a-f | sort -u

# only the ones that are NOT in the blueprint -- the whole of the first
# finding above, as one line
comm -23 <(grep -o '#[0-9a-fA-F]\{6\}' index.html | tr A-F a-f | sort -u) \
         <(grep -o '#[0-9a-fA-F]\{6\}' 'Crux App v2.dc.html' | tr A-F a-f | sort -u)

# the type scale as built, by frequency
grep -o 'font-size:[0-9.]*px' index.html | sed 's/font-size://' | sort | uniq -c | sort -rn

# what wears anything above 14px
grep -o '[.#][a-zA-Z0-9_ ->.]\{0,30\}{[^}]\{0,80\}font-size:\(1[5-9]\|[2-9][0-9]\)[0-9.]*px' \
  index.html | sed 's/{.*font-size:/  -> /' | sort -u

# the blueprint's navigation, verbatim
grep -o "navGroups = \[[^]]*\]" 'Crux App v2.dc.html'

# its labels, verbatim
grep -o 'NAV_LABEL = {[^}]*}' 'Crux App v2.dc.html'
```
