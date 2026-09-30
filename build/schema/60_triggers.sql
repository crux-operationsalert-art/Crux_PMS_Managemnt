-- =====================================================================
-- Crux baseline | 60_triggers.sql | triggers
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- The functions they call are in the 40 files.
-- =====================================================================

CREATE TRIGGER pms_cap_shadow AFTER UPDATE ON public.app_setting FOR EACH ROW EXECUTE FUNCTION pms_cap_shadow();
CREATE TRIGGER assignment_state_guard_trg BEFORE UPDATE ON public.assignment FOR EACH ROW EXECUTE FUNCTION assignment_state_guard();
CREATE TRIGGER case_auto_close_window BEFORE UPDATE ON public."case" FOR EACH ROW EXECUTE FUNCTION case_auto_close_window();
CREATE TRIGGER case_parties_sync AFTER INSERT OR UPDATE OF raised_by, against_person_id, desk_id ON public."case" FOR EACH ROW EXECUTE FUNCTION case_parties_trigger();
CREATE TRIGGER case_status_guard BEFORE UPDATE ON public."case" FOR EACH ROW EXECUTE FUNCTION case_status_guard();
CREATE TRIGGER coverage_rule_no_overlap BEFORE INSERT OR UPDATE ON public.coverage_rule FOR EACH ROW EXECUTE FUNCTION coverage_no_overlap();
CREATE TRIGGER daily_count_unwrap BEFORE INSERT OR UPDATE OF "values" ON public.daily_count FOR EACH ROW EXECUTE FUNCTION daily_count_unwrap_values();
CREATE TRIGGER outbox_whatsapp_mirror AFTER INSERT ON public.outbox FOR EACH ROW EXECUTE FUNCTION outbox_mirror_to_whatsapp();
CREATE TRIGGER perf_assignment_edges_t BEFORE INSERT OR UPDATE ON public.perf_assignment FOR EACH ROW EXECUTE FUNCTION perf_assignment_edges();
CREATE TRIGGER perf_entry_not_on_a_parent_t BEFORE INSERT OR UPDATE ON public.perf_entry FOR EACH ROW EXECUTE FUNCTION perf_entry_not_on_a_parent();
CREATE TRIGGER person_normalise_email BEFORE INSERT OR UPDATE OF work_email, personal_email ON public.person FOR EACH ROW EXECUTE FUNCTION person_normalise_email();
CREATE TRIGGER person_welcome_after_insert AFTER INSERT ON public.person FOR EACH ROW EXECUTE FUNCTION person_welcome_on_create();

