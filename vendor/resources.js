/* Serves React from this directory instead of unpkg.com.
 *
 * support.js reads window.__resources before it builds each CDN script tag, so
 * the runtime is untouched — this only redirects where the files come from.
 * Without it, an unreachable unpkg (outage, firewall, offline branch) leaves
 * the whole application on a blank screen with no error state.
 *
 * Each file is byte-identical to the CDN copy: the sha384 of every one matches
 * the SRI constant support.js pins for that URL.
 *
 * Must load BEFORE support.js.
 */
window.__resources = Object.assign(window.__resources || {}, {
  'https://unpkg.com/react@18.3.1/umd/react.production.min.js':
    'vendor/react.production.min.js',
  'https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js':
    'vendor/react-dom.production.min.js',
  'https://unpkg.com/@babel/standalone@7.29.0/babel.min.js':
    'vendor/babel.standalone.min.js',
});
