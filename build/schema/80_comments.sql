-- =====================================================================
-- Crux baseline | 80_comments.sql | comments
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- What the database says about itself.
-- =====================================================================

comment on column public.app_setting.in_force is 'False when the value is recorded but no code reads it yet. The screen shows these apart, so nobody changes a number expecting an effect.';
comment on column public.assignment.current_state is 'The operational position and nothing else. sla_status, escalation level, priority bucket and open_request_type are orthogonal attributes, not states: a breached assignment is still IN_PROGRESS and still shows its operator the correct next action. Written only by ogl_transition().';
comment on column public.audit_entry.scope_chair_id is 'Null means company-wide. Set means the entry is visible to that chair and its ancestors.';
comment on column public.automation.actions is 'Stage 3: what it does, in order.';
comment on column public.automation.conditions is 'Stage 2: every condition that must hold, all of them.';
comment on column public.automation.grp is 'Which group of the design it belongs to -- Scheduled jobs, OGL workflow, Penalty, and so on.';
comment on column public.automation.guard is 'What stops it doing the wrong thing twice. Stated beside the chain, never inferred.';
comment on column public.automation.notifies is 'Stage 4: who hears about it.';
comment on column public.automation.trigger_on is 'Stage 1 of the chain: what starts it.';
comment on column public.branch.op_node_id is 'The operating zone that runs this branch, from op_node. geo_node_id says where the branch is; this says who runs it.';
comment on column public.case_verification_requirement.outcome is 'What was found. POSITIVE, NEGATIVE, REFER, UNTRACEABLE or PARTIAL - the five answers a field verification actually comes back with. Null until the point is reported.';
comment on column public.coverage_rule.op_node_id is 'The operating location this coverage is for. geo_node_id still says where the branches physically are; this says which operating unit runs them.';
comment on column public.coverage_rule.product is 'Optional product the rule is limited to. Blank means every product for that client at that location.';
comment on column public.daily_count."values" is 'The day''s figures, keyed by KPI. Sub-categories hang off their parent key. One row per person per day: the filing is a single act with a single cutoff.';
comment on column public.geo_node.group_name is 'Optional grouping above region, as loaded. Free text; no routing depends on it.';
comment on column public.geo_node.op_zone is 'The operating zone this place is served from, as named in the Geography file. The authoritative operating grouping is op_node; this is a label.';
comment on column public.holiday.confirmed is 'False for a moon-sighting date that is not fixed yet. An unconfirmed day is shown on the calendar but is NOT skipped by the clock, because shortening a deadline on a date that may move is the error that cannot be undone.';
comment on column public.kpi_definition.accrual is 'ADDS: today''s figure is added to the period total (counts, rupees). REPLACES: today''s figure replaces the period-to-date level (percentages, scores). Derived at seed time from unit, then owned by the administrator.';
comment on column public.mis_view.config is 'What was selected, nothing that could go stale. No figures are stored here.';
comment on column public.penalty_rule.applies_to_list is 'Multi-select: Everybody | a department | a named chair | Managers with reportees | Executives | Team Leaders | Branch Managers | Regional Managers | Franchise Partners | Interns';
comment on column public.perf_collection.op_node_id is 'The operating zone the collection belongs to.';
comment on column public.perf_revenue.op_node_id is 'The operating zone the revenue was earned in. op_node, not geo_node: the business reports by Mumbai and Patna, not by West and East.';
comment on column public.person.address is 'Changed through the profile change-request path, never typed straight in: HR approves and then the record moves.';
comment on column public.person.employee_type is 'PARTNER = franchise partner: in scope for PMS/penalties but billed by Finance, not payroll.';
comment on column public.person.mobile is 'Required and unique. The identity for sign-in, OTP activation and password reset.';
comment on column public.person.password_hash is 'scrypt. Null for Workspace SSO accounts, which must not be able to fall back to a password.';
comment on column public.person.user_id is 'Chosen at activation, unique, what the person types to sign in.';
comment on column public.person.work_email is 'Optional. Often a shared branch inbox, so NOT unique and NOT a credential.';
comment on column public.person_request.employee_type is 'Captured when the request is raised, because HR approves the terms as well as the chair. Carried onto the person at account creation.';
comment on column public.pms_adjustment.over_cap is 'True when this movement exceeded the 2-point shared monthly cap. The movement still stands; HR is notified.';
comment on column public.pms_exception.due_at is 'created_at + 48 hours. The clock the requester sees.';
comment on column public.rate_location.op_node_id is 'The operating zone or location a rate is priced for. No row here means the rate applies to every branch of the client, which is only ever true when the file left the zone blank -- ua_rates refuses a zone it cannot place.';
comment on column public.reason_taxonomy.pause_eligible is 'Whether an RFI citing this reason may stop the clock. It is a column, not an inference from implied_attribution, because the two are allowed to disagree: a reason can be somebody else''s fault and still not earn a pause.';
comment on column public.sla_instance.tat_business_minutes is 'A snapshot. A later rule change never moves a live clock.';
comment on column public.sla_rule.op_node_id is 'The operating zone this rule is narrowed to, or null for every zone.';
comment on column public.strike_event.location_id is 'The location as at the breach, not as at now. A person who moves branch does not move their history with them.';
comment on function public.access_level_of(p_person uuid) is 'The scope level this person is at. Administrator, then primary chair, then department, then exec.';
comment on function public.access_may_open(p_person uuid, p_screen text) is 'May this person open this screen. The one question the navigation and every service both ask, so that they cannot answer it differently.';
comment on function public.access_screens(p_person uuid) is 'Every screen key this person may open, children included. What auth_whoami hands the browser and what the ops service gates on.';
comment on function public.auth_gate() is 'Refuses any sign-in that is not a Crux Workspace address already present and active on the people master. The three refusal messages are different on purpose: the person needs to know which one applies to them.';
comment on function public.automation_load(p_rows jsonb) is 'Loads build/data/automations.json into automation. Takes the rows as jsonb so it does not care how they arrived.';
comment on function public.case_auto_close_window() is 'Sets auto_close_at from the auto_close_days setting when an escalation is resolved, so the number an administrator sees is the number in force.';
comment on function public.chair_reports_to_someone(p_chair uuid) is 'True when some chair above this one is held by somebody today -- i.e. this is not the top of the reporting line. The chair tree''s own roots are not held by anyone, so parent_id is null is the wrong test.';
comment on function public.crux_mail_tick() is 'The scheduler''s hand on the sender. It carries the shared secret out of app_setting rather than having it written into a cron command, where anybody who can list jobs would read it. Returns nothing when the outbox is empty: the common case must not wake the sender.';
comment on function public.crux_tick() is 'Everything that happens because time passed: auto-close, the SLA sweep, sub-TATs and the delay auto-accept, escalation, strikes. One function, one job_run row, one place to look when somebody asks what the tool did overnight.';
comment on function public.daily_count_unwrap_values() is 'Undoes the double JSON encoding api/routes/pms.ts performs on daily_count.values. Remove it once that line passes the object instead of JSON.stringify(object) -- until then it is the only thing standing between a filed daily count and an unreadable one.';
comment on function public.dept_canon(p_text text) is 'The one canonical department name for whatever was typed, or null if it is not a department. Reads client_view_policy, so the allowed set is whatever Configuration says it is.';
comment on function public.geo_seat_scope(p_geo uuid) is 'The org chart place bucket a geography belongs to, or null when the chart has no seat for it.';
comment on function public.is_op_zone(p_name text) is 'True when this names an operating zone or location -- what every upload means by "zone". NOT geo_node.level=ZONE, which holds the six regions.';
comment on function public.kpi_registry_completeness() is 'What the MIS chair''s own measure -- "KPI registry completeness" -- is asking for: how many seated chairs have a measure set, and which do not.';
comment on function public.mail_enqueue(p_template text, p_recipient text, p_subject text, p_body text, p_entity_type text, p_entity_id uuid, p_cc text, p_not_before timestamp with time zone, p_scope text) is 'The only way into the outbox. The idempotency key is computed from the event, the recipient and the day and cannot be supplied by the caller, so the same notification asked for twice is one message.';
comment on function public.ogl_addr_match(a text, b text) is 'EXACT, NORMALISED, FUZZY with a score, or DIFFERENT. What it returns decides what the system proposes; it never decides anything itself.';
comment on function public.ogl_pause_preview(p_assignment uuid, p_reason uuid) is 'The conditional-pause arithmetic, run before submission and shown to the person submitting. Three conditions, each with its number. This is what stops a request for information being a free extension while still protecting a genuine one.';
comment on function public.ogl_ts(p timestamp with time zone) is 'An instant as the wall clock in the Pune office reads it. Every deadline printed in a message goes through this: a time typed in Pune is a Pune time, and a time shown in Pune is a Pune time.';
comment on function public.op_location_for(p_name text) is 'The operating LOCATION a branch belongs to. Exact name first, then the name as a whole word when exactly one active location carries it -- "Patna" is BIHAR/PATNA and "Kolkata" is Kolkata Zone. Used by uv_clients AND ua_clients, so the preview and the apply cannot disagree.';
comment on function public.op_zone_id(p_name text) is 'The operating zone or location a written name refers to, or null. Reads "Zone / Location" right-hand side first, accepts a retired zone because a historic rate refers to the zone as it was, matches a whole word only when exactly one NAME carries it, and falls back to a single matching ZONE when the word is ambiguous across locations.';
comment on function public.person_is_staff(p_person uuid) is 'True for a Crux person. False for a client-side contact that the branch master put in the people table.';
comment on function public.plb_consistency(p_mean numeric) is 'C = average monthly score / 10, floored at 0.30. A bad quarter still pays 30% of what was earned. There is no gate on C and no forced distribution.';
comment on function public.plb_payout_factor(p_achievement numeric) is 'Schedule 1. Continuous at every breakpoint: 0 below 50, linear to 100 at 85, half a point per point to 105 at 95, one for one to the 125 ceiling at 115.';
comment on function public.pms_cascade_apply(p_cycle uuid, p_kind raisable_kind, p_source uuid, p_actor uuid, p_reason text) is 'The cascade: Attributes absorb first and floor at zero, the remainder spills into KPI at that kind''s rate, and the month''s spill is capped. What the cap refuses is written with applied = false, never dropped.';
comment on function public.raise_escalation(p_assignment uuid, p_level integer, p_trigger text, p_actor uuid) is 'The one door escalation goes through. It computes its own idempotency key, so a sweep that runs twice raises one escalation; it never drops a delivery because the matrix is incomplete, and it never lets the gap stay quiet.';
comment on function public.recipient_reconciliation() is 'Cut-over check 1. Compares every recipient the old EMAIL_LOG reached against every address the new system can reach. Needs stg.email_log loaded; reports "not attempted" rather than a false PASS when it is empty.';
comment on function public.sample_purge() is 'Removes every tagged placeholder and whatever cannot exist without it, reading foreign keys from the catalogue rather than a hard-coded order. A nullable reference is released and its row kept, so real rows that merely record a sample actor survive. A row the seed did not create is not in sample_row, so the purge still cannot reach real data.';
comment on function public.ul_code(p text) is 'A code out of a spreadsheet. Strips the .0 a number column picks up, so branch 108 does not arrive as 108.0 and fail to match anything.';
comment on function public.ul_date(p text) is 'Reads a date the way a person writes one. The ONE definition every upload uses, for both validating and applying -- a validator that asked a different question refused 850 rows the applier could read.';
comment on function public.ul_date_ok(p text) is 'Can this be read as a date? The boolean form of ul_date, so a validator and an applier can never disagree about what counts as a date.';
comment on table public.access_chair_level is 'The chair decides the level, because the chair is what the design says drives everything. A title that is not here falls through to the department, and then to the smallest list there is.';
comment on table public.access_department_level is 'Used only when the person holds no chair, or holds one nobody has classified. A person the tool cannot place should see less, not more.';
comment on table public.access_level is 'The eight scope levels the design gives every chair, plus admin. Read by the ops service and by the navigation, through access_screens().';
comment on table public.access_level_screen is 'One row per screen a level may open. admin holds no rows and needs none: access_may_open() answers true for it before it reads this table.';
comment on table public.access_screen_parent is 'A screen the design reaches from inside a parent rather than from the top row follows its parent. The rate master is under Reports, which is why every level that carries Reports can read it.';
comment on table public.app_page is 'The front end, served from here rather than baked into the edge function. A change to a screen is an UPDATE, not a redeploy.';
comment on table public.app_setting is 'Every tunable number, and the only copy. pms_* keys are read by the appraisal engine; a value that appears in application code instead of here is a defect.';
comment on table public.assignment_completion is 'Insert only. A dispute creates the next cycle''s row; the disputed one stays exactly as submitted.';
comment on table public.assignment_event is 'Append only. The spec partitions this monthly; unpartitioned here until the volume justifies the job that creates partitions ahead of time.';
comment on table public.branch_generation_map is 'The cut-over branch master mapped onto the master the owner uploaded. Kept so the fold in migration 132 can be read back or reversed.';
comment on table public.business_calendar is 'Working window and working days. Holidays are not duplicated here - they come from holiday where confirmed, so there is one calendar to load and one to keep right.';
comment on table public.cutover_check is 'Evidence for the pre-cut-over checks: each known-bad write was attempted and the database refused it. A row here is what happened, not what was believed.';
comment on table public.email_domain_alias is 'Misspelt mail domains folded onto the real one before a person row is written. Defect 3: one typo domain held 583 coverage rows and a whole second identity. Adding a newly-spotted typo is an insert here, not a deploy.';
comment on table public.escalation_instance is 'One row per escalation actually raised. The idempotency key is the hash of assignment, cycle, level and trigger, so a sweep that runs twice raises one escalation - the property the old engine could not have, which is how it produced 1,892 sends from 77 keys.';
comment on table public.holiday_centre_alias is 'Maps a branch city onto the RBI banking centre whose holiday list it follows. Only exact name matches are seeded; the rest are asked about, because whether a non-centre city observes a nearby centre''s holidays is the owner''s call.';
comment on table public.login_attempt is 'Every sign-in attempt against the hosted shell. Five failures from one address or one IP in fifteen minutes stops the sixth being tried at all — the endpoint is public, so the lock has to live here, not in the caller.';
comment on table public.matrix_dispatch is 'One month''s escalation matrix for one client: what was sent, to whom, when, and what it said at the moment it left.';
comment on table public.mis_view is 'A saved MIS view. Configuration only -- grouping, period, comparison -- so a saved view always reflects current records rather than a copy of them.';
comment on table public.ogl_escalation_matrix is 'The INTERNAL matrix. The client contact directory is a different table and is reused as exactly that.';
comment on table public.op_node is 'How the business groups itself: compass group, operating zone, location. Taken from the Zonal Tracker and editable by an administrator. Separate from geo_node, which is where a branch physically is.';
comment on table public.op_node_alias is 'What a name written in a file means, when it is not what the operating tree calls the place. written_as is compared lower-cased and trimmed; means is resolved by op_place as though the file had said it. A row here, never a deploy.';
comment on table public.perf_assignment is 'One KPI given to one person for one cycle: the target, when they file, which of their own measures it is a part of, and which of their manager''s measures it climbs into.';
comment on table public.perf_entry is 'One filing against one assignment for one day. as_of is the day the number is for; filed_at is when somebody typed it.';
comment on table public.person_document is 'One row per document a person has actually produced. No row means it has not been asked for -- which the screen says, rather than showing a blank that reads as missing.';
comment on table public.ref_counter is 'One row per reference prefix. next_ref() increments under a row lock, so two people raising at the same moment cannot be handed the same reference, and a differently-shaped ref elsewhere in the table cannot break the sequence.';
comment on table public.repeat_point_decision is 'A Point ID keyed twice is not a duplicate to refuse - it is a decision to route, and the decision belongs to the assignor. Until they make it the point waits here, the assignment sits in DRAFT and no clock starts. Undecided rows are a queue with an owner, not a silent backlog.';
comment on table public.sample_row is 'One row per seeded placeholder. The purge deletes exactly these and nothing else, so it cannot reach real data even by accident.';
comment on table public.setting is 'Every tunable number. If a value appears in application code instead of here, that is a defect.';
comment on table public.strike_event is 'A strike is generated, never deleted. A dispute found NOT_UPHELD sets status = WAIVED with a reason and the row stays visible as waived; the ninety-day rolling window counts only ACTIVE ones.';
comment on table public.temp_participant_grant is 'Read access to one assignment for one person for a stated while. It exists so that helping with a case is a recorded act with an end date, rather than a permanent widening of somebody''s scope that nobody remembers granting.';
comment on table public.upload_column is 'The columns each loader reads, with the rule for every one. Lives here rather than in the hosted shell so a new kind needs no redeploy.';

