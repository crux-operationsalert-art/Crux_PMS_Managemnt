/* Deployment configuration. The ONLY file that differs between environments.
 *
 * Leave CRUX_API_BASE empty and the application runs on its built-in seed data
 * (useful for demos and for opening the file locally). Set it to the API origin
 * and every screen reads the live database instead. Nothing else changes —
 * do not edit the application to switch environments.
 *
 * Local     http://localhost:8080
 * Staging   https://crux-api-staging.onrender.com
 * Live      https://api.<your-domain>
 */
window.CRUX_API_BASE = '';
