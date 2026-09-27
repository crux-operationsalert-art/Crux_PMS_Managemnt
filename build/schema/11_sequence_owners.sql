-- =====================================================================
-- Crux baseline | 11_sequence_owners.sql | sequence ownership
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- The three sequences that column defaults call. They are generated before the tables because a default that calls nextval on a sequence that does not exist is a table that will not load.
-- =====================================================================

alter sequence public.assignment_event_id_seq owned by public.assignment_event.id;
alter sequence public.cutover_check_id_seq owned by public.cutover_check.id;
alter sequence public.login_attempt_id_seq owned by public.login_attempt.id;
