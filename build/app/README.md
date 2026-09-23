# The screens, as source

The application is one row of `app_page`, so a screen change is an UPDATE and
never a deploy. That makes the live page the only copy, which is fine for
shipping and poor for reading. The files here are the source of the screens
added after the cut-over, kept so a change can be reviewed as a diff.

- `screen-coverage.js` — Coverage & handlers. The design's screen, and the
  owner's instruction that assigning people belongs in the tool rather than in
  a spreadsheet. Talks to `/api/coverage` in the `api` Edge Function.
- `screen-people.js` — People, with a Move on every chair for an
  administrator. Talks to `/api/people/chair/:id/move`.

Both are appended to the page by a migration rather than spliced into it: a
later function declaration wins in JavaScript, so `vPeople` here overrides the
one the cut-over shipped without having to match its old text exactly.
