-- =====================================================================
-- Crux baseline | 05_types.sql | types
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- Every enum the schema uses. Nothing here has a table behind it, so this file loads first and alone.
-- =====================================================================

create type public.approval_state as enum ('DRAFT', 'AWAITING_HR', 'AWAITING_ADMIN', 'ACTIVE', 'REJECTED');
create type public.case_status as enum ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED', 'BLOCKED');
create type public.claim_stage as enum ('DRAFT', 'OPS_APPROVAL', 'HR_APPROVAL', 'ACCOUNTS', 'DISPUTED', 'PAID', 'REJECTED');
create type public.entity_status as enum ('ACTIVE', 'INACTIVE');
create type public.esc_party as enum ('RAISER', 'RESPONDENT', 'MANAGER', 'DESK', 'HR', 'ADMIN', 'INFORMED');
create type public.geo_level as enum ('ZONE', 'STATE', 'CITY');
create type public.idea_stage as enum ('SUBMITTED', 'IN_REVIEW', 'ACCEPTED', 'INITIATED', 'ON_HOLD', 'REJECTED', 'DELIVERED');
create type public.job_result as enum ('OK', 'NOOP', 'FAILED');
create type public.kpi_accrual as enum ('ADDS', 'REPLACES');
create type public.kpi_cadence as enum ('DAILY', 'WEEKLY', 'DAY_OF_MONTH', 'MONTHLY', 'MONTH_END', 'QUARTERLY');
create type public.note_class as enum ('UNCLASSIFIED', 'ATTRIBUTE', 'FYI');
create type public.ogl_party_kind as enum ('CASE', 'APPLICANT', 'CO_APPLICANT', 'GUARANTOR');
create type public.outbox_state as enum ('QUEUED', 'SENT', 'DEFERRED', 'ABANDONED');
create type public.penalty_state as enum ('PENDING', 'APPLIED', 'WAIVED', 'DISPUTED', 'REVERSED');
create type public.person_event_kind as enum ('NOTE', 'APPRECIATION', 'WARNING', 'PIP', 'ACTIVATION');
create type public.pms_cycle_state as enum ('PENDING', 'SELF_DONE', 'AWAITING_REVIEW', 'SCORED', 'DISPUTED', 'CLOSED');
create type public.raisable_kind as enum ('ESCALATION', 'WARNING', 'APPRECIATION', 'ASSISTANCE');
create type public.rate_scope as enum ('exact', 'group', 'client');
create type public.role_kind as enum ('ADMIN', 'MANAGER', 'LOCATION_HEAD', 'VIEWER');
create type public.scope_kind as enum ('CLIENT', 'CLIENT_ZONE', 'STATE', 'BRANCH', 'LOCATION');

