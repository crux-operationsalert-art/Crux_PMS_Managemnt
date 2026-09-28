-- =====================================================================
-- Crux baseline | 21_checks.sql | check constraints
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- These come after the functions: person_mobile_shape calls person_mobile(), and a CHECK is resolved when the ALTER TABLE runs.
-- =====================================================================

alter table public.ai_key add constraint ai_key_scope_check CHECK ((scope = ANY (ARRAY['everything'::text, 'short'::text, 'long'::text, 'fallback'::text])));
alter table public.ai_key add constraint ai_key_state_check CHECK ((state = ANY (ARRAY['healthy'::text, 'untested'::text, 'erroring'::text, 'no_key'::text])));
alter table public.assignment add constraint assignment_check CHECK (((to_location_id <> from_location_id) OR (self_assign_reason IS NOT NULL)));
alter table public.assignment add constraint assignment_delay_count_check CHECK ((delay_count <= 3));
alter table public.assignment add constraint assignment_dispute_count_check CHECK ((dispute_count <= 2));
alter table public.automation add constraint automation_pause_reason CHECK ((enabled OR (disabled_reason IS NOT NULL)));
alter table public.automation_run add constraint automation_run_outcome_check CHECK ((outcome = ANY (ARRAY['OK'::text, 'NOOP'::text, 'ERROR'::text])));
alter table public.branch_contact add constraint branch_contact_identified CHECK (((person_id IS NOT NULL) OR (name IS NOT NULL)));
alter table public.business_calendar add constraint business_calendar_check CHECK ((window_end > window_start));
alter table public.business_import_alias add constraint business_import_alias_kind_check CHECK ((kind = ANY (ARRAY['location'::text, 'client'::text, 'person'::text])));
alter table public.business_record add constraint business_record_day10_check CHECK ((day10 >= 0));
alter table public.business_record add constraint business_record_mtd_check CHECK ((mtd >= 0));
alter table public.business_record add constraint business_record_target_check CHECK ((target >= 0));
alter table public.capability_level add constraint capability_level_level_check CHECK ((level = ANY (ARRAY['L1'::text, 'L2'::text, 'L3'::text, 'L4'::text, 'L5'::text])));
alter table public."case" add constraint case_has_owner CHECK (((owner_person_id IS NOT NULL) OR (desk_id IS NOT NULL) OR (status = 'BLOCKED'::case_status)));
alter table public.case_verification_requirement add constraint case_verification_requirement_outcome_check CHECK (((outcome IS NULL) OR (outcome = ANY (ARRAY['POSITIVE'::text, 'NEGATIVE'::text, 'REFER'::text, 'UNTRACEABLE'::text, 'PARTIAL'::text]))));
alter table public.chair_authority add constraint chair_authority_kind_check CHECK ((kind = ANY (ARRAY['DECIDE'::text, 'ESCALATE'::text])));
alter table public.claim add constraint claim_dispute_reason CHECK (((stage <> 'DISPUTED'::claim_stage) OR (dispute_reason IS NOT NULL)));
alter table public.claim add constraint claim_paid_ref CHECK (((stage <> 'PAID'::claim_stage) OR (paid_ref IS NOT NULL)));
alter table public.client_view_policy add constraint client_view_policy_view_kind_check CHECK ((view_kind = ANY (ARRAY['matrix'::text, 'contacts'::text, 'none'::text])));
alter table public.coverage_rule add constraint coverage_scope_shape CHECK ((((scope_type = 'CLIENT'::scope_kind) AND (client_id IS NOT NULL) AND (client_zone_id IS NULL) AND (geo_node_id IS NULL) AND (branch_id IS NULL)) OR ((scope_type = 'CLIENT_ZONE'::scope_kind) AND (client_zone_id IS NOT NULL) AND (branch_id IS NULL)) OR ((scope_type = 'STATE'::scope_kind) AND (client_id IS NOT NULL) AND (geo_node_id IS NOT NULL) AND (branch_id IS NULL)) OR ((scope_type = 'BRANCH'::scope_kind) AND (branch_id IS NOT NULL)) OR ((scope_type = 'LOCATION'::scope_kind) AND (op_node_id IS NOT NULL) AND (branch_id IS NULL) AND (client_zone_id IS NULL) AND (geo_node_id IS NULL))));
alter table public.cutover_check add constraint cutover_check_result_check CHECK ((result = ANY (ARRAY['PASS'::text, 'FAIL'::text])));
alter table public.daily_count add constraint daily_count_has_figures CHECK ((("values" IS NOT NULL) OR ((kpi_id IS NOT NULL) AND (value IS NOT NULL))));
alter table public.daily_count add constraint daily_count_sync_window CHECK ((received_at <= (entered_at + '24:00:00'::interval)));
alter table public.daily_count add constraint daily_reopen_needs_reason CHECK (((reopened_by IS NULL) OR (reopen_reason IS NOT NULL)));
alter table public.day_reopen add constraint day_reopen_window CHECK ((closes_at > opened_at));
alter table public.desk add constraint desk_primary_or_fallback CHECK (((primary_person_id IS NOT NULL) OR (fallback_desk_id IS NOT NULL)));
alter table public.email_domain_alias add constraint email_domain_alias_differs CHECK ((lower(wrong) <> lower(correct)));
alter table public.escalation_instance add constraint escalation_instance_escalation_level_check CHECK (((escalation_level >= 1) AND (escalation_level <= 4)));
alter table public.escalation_instance add constraint escalation_instance_trigger_code_check CHECK ((trigger_code = ANY (ARRAY['BREACH'::text, 'SUB_TAT_BREACH'::text, 'MANUAL'::text, 'REPEAT_BREACH'::text])));
alter table public.forecast_config add constraint forecast_config_id_check CHECK ((id = 1));
alter table public.idea add constraint idea_decision_reason CHECK (((stage <> ALL (ARRAY['REJECTED'::idea_stage, 'ON_HOLD'::idea_stage])) OR (decision_reason IS NOT NULL)));
alter table public.job_config add constraint job_disable_needs_reason CHECK ((enabled OR ((reason IS NOT NULL) AND (disabled_by IS NOT NULL))));
alter table public.kpi_definition add constraint kpi_scope CHECK ((NOT ((chair_id IS NOT NULL) AND (person_id IS NOT NULL))));
alter table public.kpi_eligibility add constraint kpi_elig_effect CHECK ((((on_miss = 'DEDUCT'::text) AND (deduct_points IS NOT NULL)) OR ((on_miss = 'DEFAULT_SCORE'::text) AND (default_score IS NOT NULL))));
alter table public.kpi_eligibility add constraint kpi_eligibility_on_miss_check CHECK ((on_miss = ANY (ARRAY['DEDUCT'::text, 'DEFAULT_SCORE'::text])));
alter table public.kpi_target add constraint kpi_target_not_self CHECK ((set_by <> person_id));
alter table public.mail_config add constraint mail_config_auth_mode_check CHECK ((auth_mode = ANY (ARRAY['service_account'::text, 'oauth'::text, 'smtp'::text])));
alter table public.mail_config add constraint mail_config_check CHECK (((test_mode = false) OR (test_address IS NOT NULL)));
alter table public.mail_config add constraint mail_config_id_check CHECK ((id = 1));
alter table public.matrix_contact add constraint matrix_contact_level_check CHECK (((level >= 1) AND (level <= 5)));
alter table public.mis_view add constraint mis_view_config_is_object CHECK ((jsonb_typeof(config) = 'object'::text));
alter table public.mis_view add constraint mis_view_name_not_blank CHECK ((btrim(name) <> ''::text));
alter table public.ogl_escalation_matrix add constraint ogl_escalation_matrix_escalation_level_check CHECK (((escalation_level >= 1) AND (escalation_level <= 4)));
alter table public.op_node add constraint op_node_level_check CHECK ((level = ANY (ARRAY['GROUP'::text, 'ZONE'::text, 'LOCATION'::text])));
alter table public.ops_alert add constraint ops_alert_severity_check CHECK ((severity = ANY (ARRAY['INFO'::text, 'WARN'::text, 'URGENT'::text])));
alter table public.otp_challenge add constraint otp_challenge_purpose_check CHECK ((purpose = ANY (ARRAY['activate'::text, 'reset'::text])));
alter table public.penalty_instance add constraint penalty_amount_frozen CHECK ((amount >= (0)::numeric));
alter table public.penalty_instance add constraint penalty_waiver_needs_reason CHECK (((state <> 'WAIVED'::penalty_state) OR ((waived_by IS NOT NULL) AND (waive_reason IS NOT NULL))));
alter table public.perf_assignment add constraint perf_assignment_cadence_day_check CHECK (((cadence_day IS NULL) OR ((cadence_day >= 1) AND (cadence_day <= 28))));
alter table public.perf_assignment add constraint perf_assignment_not_its_own_parent CHECK ((rolls_into_id IS DISTINCT FROM id));
alter table public.perf_assignment add constraint perf_assignment_not_its_own_part CHECK ((part_of_id IS DISTINCT FROM id));
alter table public.perf_assignment add constraint perf_assignment_split_is_complete CHECK ((((split_kind IS NULL) AND (split_ref IS NULL) AND (part_of_id IS NULL)) OR ((split_kind IS NOT NULL) AND (part_of_id IS NOT NULL))));
alter table public.perf_assignment add constraint perf_assignment_split_is_named CHECK (((part_of_id IS NULL) OR (split_ref IS NOT NULL) OR (COALESCE(btrim(split_label), ''::text) <> ''::text)));
alter table public.perf_assignment add constraint perf_assignment_split_kind_check CHECK ((split_kind = ANY (ARRAY['CLIENT'::text, 'BRANCH'::text, 'PLACE'::text, 'OTHER'::text])));
alter table public.perf_assignment add constraint perf_assignment_state_check CHECK ((state = ANY (ARRAY['DRAFT'::text, 'ISSUED'::text, 'ACKNOWLEDGED'::text, 'LOCKED'::text])));
alter table public.perf_assignment add constraint perf_assignment_weight_pct_check CHECK (((weight_pct IS NULL) OR ((weight_pct > (0)::numeric) AND (weight_pct <= (100)::numeric))));
alter table public.perf_collection add constraint perf_collection_balances CHECK (((opening_outstanding_inr - collected_inr) = closing_outstanding_inr));
alter table public.perf_cycle add constraint perf_cycle_period_kind_check CHECK ((period_kind = ANY (ARRAY['MONTH'::text, 'QUARTER'::text])));
alter table public.perf_cycle add constraint perf_cycle_state_check CHECK ((state = ANY (ARRAY['OPEN'::text, 'ASSIGNED'::text, 'ENTRY'::text, 'SCORING'::text, 'CLOSED'::text])));
alter table public.person add constraint person_email_shape CHECK (((work_email IS NULL) OR (work_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-zA-Z]{2,}$'::text)));
alter table public.person add constraint person_employee_no_shape CHECK (((employee_no IS NULL) OR (btrim(employee_no) ~ '^[A-Za-z0-9][A-Za-z0-9/_-]{0,19}$'::text)));
alter table public.person add constraint person_employee_type_check CHECK ((employee_type = ANY (ARRAY['EMPLOYEE'::text, 'PARTNER'::text, 'INTERN'::text, 'CONTRACT'::text, 'CLIENT_CONTACT'::text])));
alter table public.person add constraint person_mobile_shape CHECK (((mobile IS NULL) OR (person_mobile(mobile) ~ '^[6-9][0-9]{9}$'::text)));
alter table public.person add constraint person_not_own_manager CHECK (((manager_id IS NULL) OR (manager_id <> id)));
alter table public.person_document add constraint person_document_kind_check CHECK ((kind = ANY (ARRAY['ID_PROOF'::text, 'ADDRESS_PROOF'::text, 'QUALIFICATION'::text, 'BANK_DETAILS'::text])));
alter table public.person_document add constraint person_document_state_check CHECK ((state = ANY (ARRAY['WITH_HR'::text, 'VERIFIED'::text, 'REVISION_REQUESTED'::text, 'WITH_ACCOUNTS'::text])));
alter table public.person_request add constraint person_request_employee_type_check CHECK ((employee_type = ANY (ARRAY['EMPLOYEE'::text, 'PARTNER'::text, 'INTERN'::text, 'CONTRACT'::text])));
alter table public.person_request add constraint person_request_finance_state_check CHECK ((finance_state = ANY (ARRAY['NOT_REQUIRED'::text, 'AWAITING'::text, 'APPROVED'::text, 'REFUSED'::text])));
alter table public.person_request add constraint person_request_reject_reason CHECK (((state <> 'REJECTED'::approval_state) OR (reject_reason IS NOT NULL)));
alter table public.plb_dispute add constraint plb_dispute_element CHECK ((element = ANY (ARRAY['TARGET'::text, 'ACTUAL'::text, 'WEIGHT'::text, 'MONTH_SCORE'::text, 'ACHIEVEMENT'::text, 'PAYOUT_FACTOR'::text, 'MONTHLY_MEAN'::text, 'CONSISTENCY'::text, 'GATE'::text, 'TARGET_PLB'::text, 'AMOUNT'::text, 'ARITHMETIC'::text])));
alter table public.plb_dispute add constraint plb_dispute_outcome CHECK (((outcome IS NULL) OR (outcome = ANY (ARRAY['UPHELD'::text, 'PARTLY_UPHELD'::text, 'REJECTED'::text]))));
alter table public.plb_dispute add constraint plb_dispute_points_at_something CHECK ((((element = ANY (ARRAY['TARGET'::text, 'ACTUAL'::text, 'WEIGHT'::text])) = (kpi_id IS NOT NULL)) AND ((element = 'MONTH_SCORE'::text) = (month IS NOT NULL))));
alter table public.plb_dispute add constraint plb_dispute_stage CHECK ((stage = ANY (ARRAY['RAISED'::text, 'RESPONDED'::text, 'ESCALATED'::text, 'DECIDED'::text, 'WITHDRAWN'::text])));
alter table public.plb_goal_attribute add constraint plb_goal_attribute_state CHECK ((state = ANY (ARRAY['EMPTY'::text, 'PROPOSED'::text, 'APPROVED'::text, 'RETURNED'::text])));
alter table public.plb_goal_kpi add constraint plb_goal_kpi_basis_level_check CHECK (((basis_level >= 1) AND (basis_level <= 4)));
alter table public.plb_goal_kpi add constraint plb_goal_kpi_weight_pct_check CHECK (((weight_pct > (0)::numeric) AND (weight_pct <= (100)::numeric)));
alter table public.plb_goal_sheet add constraint plb_goal_sheet_status_check CHECK ((status = ANY (ARRAY['DRAFT'::text, 'ISSUED'::text, 'ACKNOWLEDGED'::text, 'LOCKED'::text])));
alter table public.plb_goal_sheet add constraint plb_goal_sheet_target_plb_inr_check CHECK ((target_plb_inr >= (0)::numeric));
alter table public.plb_month_score add constraint plb_month_score_attr_points_check CHECK (((attr_points >= (0)::numeric) AND (attr_points <= (10)::numeric)));
alter table public.plb_month_score add constraint plb_month_score_kpi_points_check CHECK (((kpi_points >= (0)::numeric) AND (kpi_points <= (10)::numeric)));
alter table public.plb_month_score add constraint plb_month_score_self_attr_check CHECK (((self_attr >= (0)::numeric) AND (self_attr <= (10)::numeric)));
alter table public.plb_month_score add constraint plb_month_score_self_kpi_check CHECK (((self_kpi >= (0)::numeric) AND (self_kpi <= (10)::numeric)));
alter table public.pms_adjustment add constraint pms_adjustment_half_check CHECK ((half = ANY (ARRAY['ATTRIBUTE'::text, 'KPI'::text])));
alter table public.pms_component add constraint pms_component_kind_check CHECK ((kind = ANY (ARRAY['KPI'::text, 'ATTRIBUTE'::text, 'TEAM'::text])));
alter table public.pms_curve_band add constraint pms_curve_band_rank_check CHECK (((rank >= 1) AND (rank <= 5)));
alter table public.pms_dispute add constraint pms_dispute_outcome CHECK (((decided_at IS NULL) OR (outcome IS NOT NULL)));
alter table public.pms_dispute add constraint pms_dispute_outcome_check CHECK ((outcome = ANY (ARRAY['SCORE_STANDS'::text, 'RESCORE'::text, 'WITHDRAWN'::text])));
alter table public.pms_exception add constraint pms_exception_state_check CHECK ((state = ANY (ARRAY['PENDING'::text, 'GRANTED'::text, 'REFUSED'::text, 'EXPIRED'::text])));
alter table public.pms_score add constraint pms_score_manager_score_check CHECK (((manager_score >= (1)::numeric) AND (manager_score <= (10)::numeric)));
alter table public.pms_weighting add constraint pms_weight_sums CHECK (((kpi_percent + attr_percent) = (100)::numeric));
alter table public.portal_link add constraint portal_link_target CHECK (((client_id IS NOT NULL) OR (branch_id IS NOT NULL)));
alter table public.pulse_response add constraint pulse_response_score_check CHECK (((score >= (1)::numeric) AND (score <= (10)::numeric)));
alter table public.rate add constraint rate_check CHECK (((effective_to IS NULL) OR (effective_to > effective_from)));
alter table public.rate add constraint rate_value_check CHECK ((value >= (0)::numeric));
alter table public.role_change add constraint role_change_kind_check CHECK ((kind = ANY (ARRAY['JOIN'::text, 'MOVE'::text, 'PROMOTION'::text, 'LATERAL'::text, 'EXIT'::text])));
alter table public.strike_event add constraint strike_event_status_check CHECK ((status = ANY (ARRAY['ACTIVE'::text, 'WAIVED'::text, 'EXPIRED'::text])));
alter table public.strike_event add constraint strike_event_trigger_code_check CHECK ((trigger_code = ANY (ARRAY['SLA_BREACH'::text, 'SUB_TAT_BREACH'::text, 'DISPUTE_UPHELD'::text, 'MIGRATED'::text])));
alter table public.task add constraint task_status_check CHECK ((status = ANY (ARRAY['OPEN'::text, 'DONE'::text, 'LATE'::text, 'MISSED'::text, 'CANCELLED'::text])));
alter table public.upload_batch add constraint upload_batch_state_check CHECK ((state = ANY (ARRAY['PREVIEW'::text, 'APPLIED'::text, 'REJECTED'::text, 'CANCELLED'::text])));
alter table public.value_correction add constraint value_correction_reason_real CHECK ((length(btrim(reason)) >= 8));
alter table public.wa_bridge add constraint wa_bridge_device_kind_check CHECK ((device_kind = ANY (ARRAY['laptop'::text, 'phone'::text, 'server'::text])));
alter table public.wa_bridge add constraint wa_bridge_state_check CHECK ((state = ANY (ARRAY['NEW'::text, 'NEEDS_QR'::text, 'READY'::text, 'STALE'::text, 'DISABLED'::text])));

