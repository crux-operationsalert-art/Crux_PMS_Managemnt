# Data the database loads over HTTP

`automations.json` is `automations.js` from the repo root, as JSON: the 49
automations the design defines, each as the four-stage chain the Automations
screen draws — trigger, conditions, actions, notifies — with its guard beside
it and, where it is blocked, why.

It lives here because the application is a row in the database, not a file, so
the page cannot `<script src>` its way to this data. Migration 141 has the
database fetch this file through pg_net and load it into `automation`. That is
cheaper and far less error-prone than carrying 20KB of literal through a tool
call, and it means the file in git and the rows in the table came from the same
bytes.

Regenerate after editing `automations.js`:

```sh
node -e "global.window={};require('./automations.js');
  const a=window.CRUX_AUTO.map(x=>({key:x.id,title:x.n,grp:x.d,owner:x.own,state:x.s,
    trigger_on:x.t||[],conditions:x.c||[],actions:x.a||[],notifies:x.nt||[],
    guard:x.g||null,blocked_why:x.w||null}));
  require('fs').writeFileSync('build/data/automations.json',JSON.stringify(a,null,0))"
```
