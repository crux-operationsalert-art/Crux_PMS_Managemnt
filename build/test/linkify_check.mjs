// A URL in an e-mail body becomes a real link in the HTML twin.
//
// The plain-text half of every message needs nothing -- mail clients make a
// bare URL clickable on their own. The HTML twin escapes the body and turns
// newlines into <br>, so before this the URL sat there as dead text: the
// half that exists to look better was the half where the link did not work.
//
// What is checked here is the joins, because that is where this kind of
// function goes wrong: a full stop swallowed into the href, an escaped
// ampersand torn in half, and a javascript: URL treated as a link. The last
// one is the only one that matters much, and it matters a lot -- a body is
// composed by this system's own functions, but "it is our own data" is what
// every injection was called first.
//
// The code under test is read out of the mail function at run time, for the
// same reason the scorecard check does it: a copy here could pass while the
// real one was wrong.
//
//   /opt/node22/bin/node build/test/linkify_check.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(
  join(here, "..", "supabase", "functions", "mail", "index.ts"), "utf8");

const a = src.indexOf("function linkify(");
const b = src.indexOf("function html(", a);
if (a < 0 || b < 0) {
  console.log("FAIL  linkify is gone from the mail function");
  process.exit(1);
}
// Strip the TypeScript annotation; the body is plain JavaScript.
const body = src.slice(a, b).replace(/\(escaped: string\)/, "(escaped)");

const escSrc = `function esc(s){ return s.replace(/&/g,"&amp;")
  .replace(/</g,"&lt;").replace(/>/g,"&gt;"); }`;
const { linkify, esc } = new Function(
  escSrc + body + "\n return { linkify: linkify, esc: esc };")();

let fails = 0;
const run = (name, input, check) => {
  const got = linkify(esc(input));
  if (check(got)) console.log("PASS  " + name);
  else {
    console.log("FAIL  " + name + "\n      in   " + JSON.stringify(input) +
                "\n      got  " + JSON.stringify(got));
    fails++;
  }
};

run("a bare URL becomes an anchor",
    "File it: https://crux.example/#perf",
    (g) => g.includes('<a href="https://crux.example/#perf"'));

run("and the anchor's text is the URL, not 'click here'",
    "https://crux.example/#perf",
    (g) => g.includes(">https://crux.example/#perf</a>"));

run("a full stop after a URL stays in the sentence",
    "Open https://crux.example/. Then file.",
    (g) => g.includes('href="https://crux.example/"') && g.includes("</a>. Then"));

run("so does a closing bracket",
    "(see https://crux.example/#perf)",
    (g) => g.includes('href="https://crux.example/#perf"') && g.includes("</a>)"));

run("a query string survives escaping intact",
    "https://crux.example/?a=1&b=2",
    (g) => g.includes('href="https://crux.example/?a=1&amp;b=2"'));

run("two URLs on two lines both link",
    "File: https://crux.example/#perf\nTeam: https://crux.example/#people",
    (g) => (g.match(/<a href=/g) || []).length === 2);

run("http is linked as well as https",
    "http://crux.example/x",
    (g) => g.includes('<a href="http://crux.example/x"'));

// The one that is not cosmetic.
run("javascript: is NOT made into a link",
    "javascript:alert(1)",
    (g) => !g.includes("<a "));

run("nor is data:",
    "data:text/html,<script>alert(1)</script>",
    (g) => !g.includes("<a "));

run("a body with no URL is left exactly as it was",
    "These are due from you today:\n  - Cases completed, target 300 cases",
    (g) => g === esc("These are due from you today:\n  - Cases completed, target 300 cases"));

// An injected tag must stay escaped: linkify runs AFTER esc and must not
// undo it.
run("an angle bracket in the body stays escaped",
    '<img src=x onerror=alert(1)> https://crux.example/',
    (g) => g.includes("&lt;img") && !g.includes("<img"));

// A quote ends the URL match, so the href closes cleanly and the rest is
// left as inert text after the </a>. What must be true is not that the
// characters vanish -- they are somebody's typing and belong in the body --
// but that no tag this function emits carries an event handler.
run("a quote cannot break out of the href",
    'https://crux.example/"onmouseover="alert(1)',
    (g) => {
      const tags = g.match(/<[^>]*>/g) || [];
      return tags.every((t) => !/\son\w+\s*=/i.test(t)) &&
             g.includes('href="https://crux.example/"');
    });

run("and neither can an apostrophe",
    "https://crux.example/'onclick='alert(1)",
    (g) => (g.match(/<[^>]*>/g) || []).every((t) => !/\son\w+\s*=/i.test(t)));

run("a URL alone on a line, which is what the composers write",
    "  - Days filed, target 90 % of working days filed\n" +
    "      File it: https://crux.example/#perf",
    (g) => g.includes('<a href="https://crux.example/#perf"') &&
           g.includes("Days filed"));

console.log(fails ? "\n" + fails + " FAILED"
                  : "\nthe links in the mail: every assertion passed");
process.exit(fails ? 1 : 0);
