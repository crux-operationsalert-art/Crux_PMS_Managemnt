revoke insert, update, delete, truncate on all tables in schema public from authenticated;
revoke insert, update, delete, truncate on all tables in schema public from anon;
alter default privileges in schema public
  revoke insert, update, delete, truncate on tables from authenticated;

do $$
declare t text;
begin
  foreach t in array array[
    'ai_key','ai_call','mail_config','mail_alias','mail_bounce',
    'otp_challenge','portal_link',
    'app_setting','setting','assist_guide',
    'penalty_rule','rate','rate_location','rate_exception',
    'business_record','forecast_config','mis_saved_view',
    'person_request','onboarding','pulse_response',
    'migration_review','migration_merge',
    'kpi_definition','kpi_target','kpi_eligibility',
    'pms_weighting','pms_impact','pms_exception','pms_curve_band','pms_band_result',
    'automation','automation_run','job_config','job_run',
    'outbox','delivery','template','mail_budget',
    'escalation_action','escalation_action_log','escalation_party',
    'submission_window','process','process_party','process_input'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force row level security', t);
  end loop;
end $$;

drop policy if exists reopen_own_read on day_reopen;
create policy reopen_own_read on day_reopen for select
  using (person_id = app_person_id() or app_is_admin());

alter function coverage_resolve(coverage_rule)            set search_path = public;
alter function coverage_no_overlap()                      set search_path = public;
alter function may_edit_penalty_rule(uuid)                set search_path = public;
alter function penalty_recovery_for(uuid, uuid)           set search_path = public;
alter function pms_window_may_open(uuid, date)            set search_path = public;
alter function pms_attribute_balance(uuid)                set search_path = public;
alter function stg.present(text)                          set search_path = stg, public;
alter function stg.norm_email(text)                       set search_path = stg, public;
alter function stg.norm_name(text)                        set search_path = stg, public;
alter function stg.norm_mobile(text)                      set search_path = stg, public;
alter function stg.ts(text)                               set search_path = stg, public;