-- =====================================================================
-- Crux baseline | 08_sequences.sql | sequences
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- Created before the tables, because a column default that calls nextval on a sequence that does not exist is a table that will not load. Which column owns which sequence is in 11_sequence_owners.sql, because that cannot be said until the tables are there.
-- =====================================================================

create sequence if not exists public.assignment_event_id_seq;
create sequence if not exists public.cutover_check_id_seq;
create sequence if not exists public.login_attempt_id_seq;

