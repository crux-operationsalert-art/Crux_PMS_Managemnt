-- =====================================================================
-- Crux baseline | 90_cron.sql | scheduled jobs
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- Requires pg_cron. Each line is the schedule as it stands in the live project.
-- =====================================================================

select cron.schedule('crux-mail', '* * * * *', 'select crux_mail_tick()');
select cron.schedule('crux-matrix-nudge', '30 4 * * *', 'select crux_matrix_nudge_tick()');
select cron.schedule('crux-penalty', '30 1 * * *', 'select crux_penalty_tick()');
select cron.schedule('crux-perf-reminders', '0 4 * * *', 'select crux_perf_reminder_tick()');
select cron.schedule('crux-request-strikes', '0 5 * * *', 'select crux_request_strike_tick()');
select cron.schedule('crux-tick', '*/15 * * * *', 'select crux_tick()');
select cron.schedule('crux-wa-bridge', '* * * * *', 'select crux_wa_bridge_tick()');
select cron.schedule('crux-whatsapp', '* * * * *', 'select crux_wa_tick()');

