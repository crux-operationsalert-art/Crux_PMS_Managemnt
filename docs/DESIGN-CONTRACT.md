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

## Still not matching

Stated plainly rather than quietly left:

- **Automations has no tab.** The blueprint gives it one in Company; in the
  tool the seven jobs live inside Settings.
- **Moving a chair is a picker, not drag-and-drop.**
- **MIS has no saved views, period comparison or export customisation.**
- **The mobile bar** carries four short labels of its own and has not been
  measured against the blueprint.

## Re-measuring

```sh
# every colour in the blueprint, by frequency
grep -o '#[0-9a-fA-F]\{6\}' 'Crux App v2.dc.html' | tr A-F a-f | sort | uniq -c | sort -rn

# every colour in the built page, to diff against the list above
grep -o '#[0-9a-fA-F]\{6\}' index.html | tr A-F a-f | sort -u

# the blueprint's navigation, verbatim
grep -o "navGroups = \[[^]]*\]" 'Crux App v2.dc.html'

# its labels, verbatim
grep -o 'NAV_LABEL = {[^}]*}' 'Crux App v2.dc.html'
```
