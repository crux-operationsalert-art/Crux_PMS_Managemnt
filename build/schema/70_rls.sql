-- =====================================================================
-- Crux baseline | 70_rls.sql | row level security
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- Row level security is on for nearly every table, and most of them carry no policy at all. That is deliberate: the tool reaches the database through SECURITY DEFINER functions and the service role, so a table with RLS on and no policy is closed to anon and to authenticated, which is what it should be.
-- =====================================================================

alter table public."case" enable row level security;
alter table public.access_chair_level enable row level security;
alter table public.access_department_level enable row level security;
alter table public.access_level enable row level security;
alter table public.access_level_screen enable row level security;
alter table public.access_screen_parent enable row level security;
alter table public.ai_call enable row level security;
alter table public.ai_key enable row level security;
alter table public.app_page enable row level security;
alter table public.app_setting enable row level security;
alter table public.assignment enable row level security;
alter table public.assignment_completion enable row level security;
alter table public.assignment_event enable row level security;
alter table public.assignment_request enable row level security;
alter table public.assist_guide enable row level security;
alter table public.audit_entry enable row level security;
alter table public.auth_session enable row level security;
alter table public.automation enable row level security;
alter table public.automation_run enable row level security;
alter table public.branch enable row level security;
alter table public.branch_contact enable row level security;
alter table public.branch_generation_map enable row level security;
alter table public.business_calendar enable row level security;
alter table public.business_import_alias enable row level security;
alter table public.business_record enable row level security;
alter table public.capability_level enable row level security;
alter table public.capability_psychometric enable row level security;
alter table public.capability_topic enable row level security;
alter table public.capability_track enable row level security;
alter table public.case_event enable row level security;
alter table public.case_party enable row level security;
alter table public.case_verification_requirement enable row level security;
alter table public.category enable row level security;
alter table public.chair enable row level security;
alter table public.chair_accountability enable row level security;
alter table public.chair_authority enable row level security;
alter table public.chair_holder enable row level security;
alter table public.chair_measure enable row level security;
alter table public.chair_seating enable row level security;
alter table public.chair_subtask enable row level security;
alter table public.chair_task enable row level security;
alter table public.claim enable row level security;
alter table public.client enable row level security;
alter table public.client_contact enable row level security;
alter table public.client_view_policy enable row level security;
alter table public.client_zone enable row level security;
alter table public.coverage_rule enable row level security;
alter table public.cutover_check enable row level security;
alter table public.daily_count enable row level security;
alter table public.daily_note enable row level security;
alter table public.day_reopen enable row level security;
alter table public.delivery enable row level security;
alter table public.designation enable row level security;
alter table public.desk enable row level security;
alter table public.email_domain_alias enable row level security;
alter table public.escalation_action enable row level security;
alter table public.escalation_action_log enable row level security;
alter table public.escalation_instance enable row level security;
alter table public.escalation_party enable row level security;
alter table public.forecast_config enable row level security;
alter table public.geo_node enable row level security;
alter table public.holiday enable row level security;
alter table public.holiday_centre_alias enable row level security;
alter table public.idea enable row level security;
alter table public.idea_collaborator enable row level security;
alter table public.job_config enable row level security;
alter table public.job_run enable row level security;
alter table public.kpi_definition enable row level security;
alter table public.kpi_eligibility enable row level security;
alter table public.kpi_target enable row level security;
alter table public.letter enable row level security;
alter table public.login_attempt enable row level security;
alter table public.mail_alias enable row level security;
alter table public.mail_bounce enable row level security;
alter table public.mail_budget enable row level security;
alter table public.mail_config enable row level security;
alter table public.matrix_contact enable row level security;
alter table public.matrix_dispatch enable row level security;
alter table public.migration_merge enable row level security;
alter table public.migration_review enable row level security;
alter table public.mis_saved_view enable row level security;
alter table public.mis_view enable row level security;
alter table public.notification enable row level security;
alter table public.ogl_attachment enable row level security;
alter table public.ogl_escalation_matrix enable row level security;
alter table public.ogl_transition_rule enable row level security;
alter table public.onboarding enable row level security;
alter table public.op_node enable row level security;
alter table public.op_node_alias enable row level security;
alter table public.ops_alert enable row level security;
alter table public.otp_challenge enable row level security;
alter table public.outbox enable row level security;
alter table public.penalty_instance enable row level security;
alter table public.penalty_rule enable row level security;
alter table public.perf_assignment enable row level security;
alter table public.perf_collection enable row level security;
alter table public.perf_cycle enable row level security;
alter table public.perf_entry enable row level security;
alter table public.perf_month enable row level security;
alter table public.perf_revenue enable row level security;
alter table public.perf_rollup_map enable row level security;
alter table public.person enable row level security;
alter table public.person_document enable row level security;
alter table public.person_event enable row level security;
alter table public.person_request enable row level security;
alter table public.plb_correction enable row level security;
alter table public.plb_dispute enable row level security;
alter table public.plb_goal_attribute enable row level security;
alter table public.plb_goal_kpi enable row level security;
alter table public.plb_goal_sheet enable row level security;
alter table public.plb_month_score enable row level security;
alter table public.plb_result enable row level security;
alter table public.pms_adjustment enable row level security;
alter table public.pms_band_result enable row level security;
alter table public.pms_component enable row level security;
alter table public.pms_curve_band enable row level security;
alter table public.pms_cycle enable row level security;
alter table public.pms_dispute enable row level security;
alter table public.pms_exception enable row level security;
alter table public.pms_impact enable row level security;
alter table public.pms_score enable row level security;
alter table public.pms_weighting enable row level security;
alter table public.portal_link enable row level security;
alter table public.process enable row level security;
alter table public.process_input enable row level security;
alter table public.process_party enable row level security;
alter table public.process_scope enable row level security;
alter table public.pulse_response enable row level security;
alter table public.push_subscription enable row level security;
alter table public.raisable enable row level security;
alter table public.rate enable row level security;
alter table public.rate_exception enable row level security;
alter table public.rate_location enable row level security;
alter table public.reason_taxonomy enable row level security;
alter table public.ref_counter enable row level security;
alter table public.repeat_point_decision enable row level security;
alter table public.request_task enable row level security;
alter table public.role_change enable row level security;
alter table public.sample_row enable row level security;
alter table public.setting enable row level security;
alter table public.sla_clock_segment enable row level security;
alter table public.sla_instance enable row level security;
alter table public.sla_rule enable row level security;
alter table public.strike_event enable row level security;
alter table public.submission_window enable row level security;
alter table public.target enable row level security;
alter table public.task enable row level security;
alter table public.temp_participant_grant enable row level security;
alter table public.template enable row level security;
alter table public.upload_batch enable row level security;
alter table public.upload_column enable row level security;
alter table public.upload_kind enable row level security;
alter table public.upload_row enable row level security;
alter table public.value_correction enable row level security;
alter table public.verification_case enable row level security;
alter table public.verification_type enable row level security;
alter table public.visit enable row level security;
alter table public.visit_form_field enable row level security;
alter table public.wa_bridge enable row level security;
alter table public.wa_bridge_event enable row level security;
alter table public.wa_budget enable row level security;
alter table public.wa_outbox enable row level security;
create policy audit_no_delete on public.audit_entry as PERMISSIVE for DELETE to public using (false);
create policy audit_no_update on public.audit_entry as PERMISSIVE for UPDATE to public using (false);
create policy audit_read on public.audit_entry as PERMISSIVE for SELECT to public using (app_is_admin());
create policy branch_generation_map_admin on public.branch_generation_map as PERMISSIVE for ALL to public using (app_is_admin()) with check (app_is_admin());
create policy branch_read on public.branch as PERMISSIVE for SELECT to public using (((client_id IN ( SELECT app_scope_clients.client_id
   FROM app_scope_clients() app_scope_clients(client_id))) OR app_is_admin()));
create policy business_import_alias_read on public.business_import_alias as PERMISSIVE for SELECT to authenticated using (true);
create policy client_contact_read on public.client_contact as PERMISSIVE for SELECT to public using ((app_is_admin() OR ((EXISTS ( SELECT 1
   FROM (person p
     JOIN client_view_policy v ON ((v.department = p.department)))
  WHERE ((p.id = app_person_id()) AND (v.view_kind = ANY (ARRAY['matrix'::text, 'contacts'::text]))))) AND (client_id IN ( SELECT app_scope_clients.client_id
   FROM app_scope_clients() app_scope_clients(client_id))))));
create policy client_read on public.client as PERMISSIVE for SELECT to public using (((id IN ( SELECT app_scope_clients.client_id
   FROM app_scope_clients() app_scope_clients(client_id))) OR app_is_admin()));
create policy correction_no_change on public.value_correction as PERMISSIVE for UPDATE to public using (false);
create policy correction_no_delete on public.value_correction as PERMISSIVE for DELETE to public using (false);
create policy correction_read on public.value_correction as PERMISSIVE for SELECT to public using (app_is_admin());
create policy coverage_read on public.coverage_rule as PERMISSIVE for SELECT to public using (((person_id IN ( SELECT app_subtree.person_id
   FROM app_subtree() app_subtree(person_id))) OR app_is_admin()));
create policy daily_insert_own on public.daily_count as PERMISSIVE for INSERT to public with check ((person_id = app_person_id()));
create policy daily_no_delete on public.daily_count as PERMISSIVE for DELETE to public using (false);
create policy daily_read on public.daily_count as PERMISSIVE for SELECT to public using (((person_id IN ( SELECT app_subtree.person_id
   FROM app_subtree() app_subtree(person_id))) OR app_is_admin()));
create policy daily_update_own on public.daily_count as PERMISSIVE for UPDATE to public using (((person_id = app_person_id()) AND (((received_at)::date = CURRENT_DATE) OR (EXISTS ( SELECT 1
   FROM day_reopen r
  WHERE ((r.person_id = daily_count.person_id) AND (r.day = daily_count.count_date) AND (r.closed_at IS NULL) AND (now() < r.closes_at))))))) with check ((person_id = app_person_id()));
create policy holiday_centre_alias_admin_write on public.holiday_centre_alias as PERMISSIVE for ALL to public using (app_is_admin()) with check (app_is_admin());
create policy holiday_centre_alias_read on public.holiday_centre_alias as PERMISSIVE for SELECT to public using ((app_person_id() IS NOT NULL));
create policy letter_read on public.letter as PERMISSIVE for SELECT to public using (((person_id IN ( SELECT app_subtree.person_id
   FROM app_subtree() app_subtree(person_id))) OR (person_id = app_person_id()) OR app_is_admin()));
create policy mis_view_own on public.mis_view as PERMISSIVE for ALL to public using (((person_id = app_person_id()) OR app_is_admin())) with check (((person_id = app_person_id()) OR app_is_admin()));
create policy note_read on public.daily_note as PERMISSIVE for SELECT to public using (((person_id IN ( SELECT app_subtree.person_id
   FROM app_subtree() app_subtree(person_id))) OR app_is_admin()));
create policy note_write_own on public.daily_note as PERMISSIVE for INSERT to public with check ((person_id = app_person_id()));
create policy notif_own on public.notification as PERMISSIVE for SELECT to public using ((person_id = app_person_id()));
create policy notif_own_update on public.notification as PERMISSIVE for UPDATE to public using ((person_id = app_person_id())) with check ((person_id = app_person_id()));
create policy ogl_att_insert on public.ogl_attachment as PERMISSIVE for INSERT to public with check ((uploaded_by = app_person_id()));
create policy ogl_att_no_delete on public.ogl_attachment as PERMISSIVE for DELETE to public using (false);
create policy ogl_att_read on public.ogl_attachment as PERMISSIVE for SELECT to public using (((uploaded_by IN ( SELECT app_subtree.person_id
   FROM app_subtree() app_subtree(person_id))) OR app_is_admin()));
create policy op_node_alias_admin_write on public.op_node_alias as PERMISSIVE for ALL to public using (app_is_admin()) with check (app_is_admin());
create policy op_node_alias_read on public.op_node_alias as PERMISSIVE for SELECT to public using (true);
create policy penalty_no_self_waive on public.penalty_instance as PERMISSIVE for UPDATE to public using ((app_is_admin() AND (person_id <> app_person_id())));
create policy penalty_read on public.penalty_instance as PERMISSIVE for SELECT to public using (((person_id IN ( SELECT app_subtree.person_id
   FROM app_subtree() app_subtree(person_id))) OR app_is_admin()));
create policy perf_collection_admin_write on public.perf_collection as PERMISSIVE for ALL to public using (app_is_admin()) with check (app_is_admin());
create policy perf_collection_read on public.perf_collection as PERMISSIVE for SELECT to public using (((client_id IN ( SELECT app_scope_clients.client_id
   FROM app_scope_clients() app_scope_clients(client_id))) OR app_is_admin()));
create policy perf_month_admin_write on public.perf_month as PERMISSIVE for ALL to public using (app_is_admin()) with check (app_is_admin());
create policy perf_month_read on public.perf_month as PERMISSIVE for SELECT to public using (((person_id IN ( SELECT app_subtree.person_id
   FROM app_subtree() app_subtree(person_id))) OR app_is_admin()));
create policy perf_revenue_admin_write on public.perf_revenue as PERMISSIVE for ALL to public using (app_is_admin()) with check (app_is_admin());
create policy perf_revenue_read on public.perf_revenue as PERMISSIVE for SELECT to public using (((client_id IN ( SELECT app_scope_clients.client_id
   FROM app_scope_clients() app_scope_clients(client_id))) OR app_is_admin()));
create policy person_self_read on public.person as PERMISSIVE for SELECT to public using (((id = app_person_id()) OR (id IN ( SELECT app_subtree.person_id
   FROM app_subtree() app_subtree(person_id))) OR app_is_admin()));
create policy person_self_update on public.person as PERMISSIVE for UPDATE to public using ((id = app_person_id())) with check ((id = app_person_id()));
create policy pms_cycle_read on public.pms_cycle as PERMISSIVE for SELECT to public using (((person_id IN ( SELECT app_subtree.person_id
   FROM app_subtree() app_subtree(person_id))) OR app_is_admin()));
create policy pms_cycle_score_not_self on public.pms_cycle as PERMISSIVE for UPDATE to public using (((person_id IN ( SELECT app_subtree.person_id
   FROM app_subtree() app_subtree(person_id))) AND (person_id <> app_person_id()))) with check ((person_id <> app_person_id()));
create policy pms_dispute_read on public.pms_dispute as PERMISSIVE for SELECT to public using (((cycle_id IN ( SELECT pms_cycle.id
   FROM pms_cycle
  WHERE (pms_cycle.person_id IN ( SELECT app_subtree.person_id
           FROM app_subtree() app_subtree(person_id))))) OR app_is_admin()));
create policy push_own on public.push_subscription as PERMISSIVE for ALL to public using ((person_id = app_person_id())) with check ((person_id = app_person_id()));
create policy raisable_insert on public.raisable as PERMISSIVE for INSERT to public with check (((raised_by = app_person_id()) AND (about_person <> app_person_id())));
create policy raisable_read on public.raisable as PERMISSIVE for SELECT to public using (((about_person IN ( SELECT app_subtree.person_id
   FROM app_subtree() app_subtree(person_id))) OR (raised_by = app_person_id()) OR app_is_admin()));
create policy reopen_admin on public.day_reopen as PERMISSIVE for ALL to public using (app_is_admin()) with check (app_is_admin());
create policy reopen_own_read on public.day_reopen as PERMISSIVE for SELECT to public using (((person_id = app_person_id()) OR app_is_admin()));
create policy role_change_admin_write on public.role_change as PERMISSIVE for ALL to public using (app_is_admin()) with check (app_is_admin());
create policy role_change_read on public.role_change as PERMISSIVE for SELECT to public using (((person_id IN ( SELECT app_subtree.person_id
   FROM app_subtree() app_subtree(person_id))) OR app_is_admin()));
create policy session_own on public.auth_session as PERMISSIVE for SELECT to public using ((person_id = app_person_id()));
create policy target_read on public.target as PERMISSIVE for SELECT to public using (((person_id IN ( SELECT app_subtree.person_id
   FROM app_subtree() app_subtree(person_id))) OR app_is_admin()));
create policy target_write_manager on public.target as PERMISSIVE for INSERT to public with check (((person_id <> app_person_id()) AND (person_id IN ( SELECT app_subtree.person_id
   FROM app_subtree() app_subtree(person_id)))));
create policy task_read on public.task as PERMISSIVE for SELECT to public using (((person_id IN ( SELECT app_subtree.person_id
   FROM app_subtree() app_subtree(person_id))) OR app_is_admin()));

