-- =====================================================================
-- Crux baseline | 50_views.sql | views
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- public and seam. The seam views are the prototype's read-only window on the real tables.
-- =====================================================================

create or replace view public.branch_effective_matrix as
 SELECT b.id AS branch_id,
    m.level,
    m.level_name,
    m.name,
    m.mobile,
    m.email,
    false AS inherited
   FROM branch b
     JOIN matrix_contact m ON m.branch_id = b.id
UNION ALL
 SELECT b.id AS branch_id,
    m.level,
    m.level_name,
    m.name,
    m.mobile,
    m.email,
    true AS inherited
   FROM branch b
     JOIN matrix_contact m ON m.client_id = b.client_id AND m.branch_id IS NULL
  WHERE NOT (EXISTS ( SELECT 1
           FROM matrix_contact x
          WHERE x.branch_id = b.id));

create or replace view public.branch_matrix_state as
 SELECT b.id AS branch_id,
    b.client_id,
    count(*) FILTER (WHERE m.name IS NOT NULL AND btrim(m.name) <> ''::text AND (COALESCE(btrim(m.mobile), ''::text) <> ''::text OR COALESCE(btrim(m.email), ''::text) <> ''::text)) AS complete_levels
   FROM branch b
     LEFT JOIN matrix_contact m ON m.branch_id = b.id
  GROUP BY b.id, b.client_id;

create or replace view public.branch_without_place as
 SELECT b.id,
    b.code,
    b.name,
    b.address,
    c.code AS client_code,
    c.name AS client_name
   FROM branch b
     JOIN client c ON c.id = b.client_id
  WHERE b.geo_node_id IS NULL AND b.status = 'ACTIVE'::entity_status;

create or replace view public.chair_status as
 SELECT c.id AS chair_id,
    c.id,
    c.code,
    c.title,
    h.person_id,
        CASE
            WHEN h.person_id IS NOT NULL THEN 'FILLED'::text
            WHEN r.id IS NOT NULL AND r.due_at < now() THEN 'OVERDUE'::text
            WHEN r.id IS NOT NULL THEN 'REQUESTED'::text
            ELSE 'DORMANT'::text
        END AS state,
    r.due_at,
    h.person_id IS NULL AS vacant,
        CASE
            WHEN r.id IS NOT NULL AND r.due_at < now() THEN GREATEST(0, EXTRACT(day FROM now() - r.due_at)::integer)
            ELSE 0
        END AS overdue_days
   FROM chair c
     LEFT JOIN chair_holder h ON h.chair_id = c.id AND h.to_date IS NULL AND h.is_primary
     LEFT JOIN person_request r ON r.chair_id = c.id AND (r.state = ANY (ARRAY['DRAFT'::approval_state, 'AWAITING_HR'::approval_state, 'AWAITING_ADMIN'::approval_state]));

create or replace view public.dispatch_eligible_branch as
 SELECT b.id AS branch_id,
    b.client_id
   FROM branch b
     JOIN branch_matrix_state s ON s.branch_id = b.id
     JOIN client c ON c.id = b.client_id
  WHERE b.status = 'ACTIVE'::entity_status AND c.status = 'ACTIVE'::entity_status AND s.complete_levels = 5;

create or replace view public.dispatch_eligible_branch_v2 as
 SELECT b.id AS branch_id,
    b.client_id,
    bool_or(e.inherited) AS using_client_default
   FROM branch b
     JOIN client c ON c.id = b.client_id
     JOIN branch_effective_matrix e ON e.branch_id = b.id
  WHERE b.status = 'ACTIVE'::entity_status AND c.status = 'ACTIVE'::entity_status
  GROUP BY b.id, b.client_id
 HAVING count(*) FILTER (WHERE e.name IS NOT NULL AND btrim(e.name) <> ''::text AND (COALESCE(btrim(e.mobile), ''::text) <> ''::text OR COALESCE(btrim(e.email), ''::text) <> ''::text)) = 5;

create or replace view public.kpi_registry_gap as
 SELECT id AS chair_id,
    code,
    title,
    (( SELECT count(*) AS count
           FROM chair_holder h
          WHERE h.chair_id = ch.id AND h.to_date IS NULL))::integer AS seated,
    (( SELECT count(*) AS count
           FROM kpi_definition k
          WHERE k.chair_id = ch.id AND k.active))::integer AS measures,
    (( SELECT count(*) AS count
           FROM chair_measure m
          WHERE m.chair_id = ch.id))::integer AS statements
   FROM chair ch
  WHERE (EXISTS ( SELECT 1
           FROM chair_holder h
          WHERE h.chair_id = ch.id AND h.to_date IS NULL)) AND NOT (EXISTS ( SELECT 1
           FROM kpi_definition k
          WHERE k.chair_id = ch.id AND k.active));

create or replace view public.migration_coverage_shape as
 SELECT scope_type,
    count(*) AS rules,
    sum(( SELECT count(*) AS count
           FROM coverage_resolve(r.*) coverage_resolve(coverage_resolve))) AS branches_covered
   FROM coverage_rule r
  GROUP BY scope_type
  ORDER BY scope_type;

create or replace view public.migration_gate as
 WITH g AS (
         SELECT 'clients'::text AS gate,
            (( SELECT count(*) AS count
                   FROM client))::integer AS actual,
            28 AS expected,
            'CLIENTS tab'::text AS basis
        UNION ALL
         SELECT 'branches'::text,
            ( SELECT count(*) AS count
                   FROM branch) AS count,
            1413,
            'BRANCHES tab, B-01 real rows after B-03 collapse'::text
        UNION ALL
         SELECT 'branches ACTIVE'::text,
            ( SELECT count(*) AS count
                   FROM branch
                  WHERE branch.status = 'ACTIVE'::entity_status) AS count,
            722,
            'B-04'::text
        UNION ALL
         SELECT 'branches INACTIVE'::text,
            ( SELECT count(*) AS count
                   FROM branch
                  WHERE branch.status = 'INACTIVE'::entity_status) AS count,
            691,
            'B-04'::text
        UNION ALL
         SELECT 'matrix rows loaded'::text,
            ( SELECT count(*) AS count
                   FROM matrix_contact) AS count,
            3525,
            'one contact per (client, branch, level) after M-02'::text
        UNION ALL
         SELECT 'matrix rows accounted'::text,
            (( SELECT count(*) AS count
                   FROM matrix_contact)) + (( SELECT count(*) AS count
                   FROM migration_merge
                  WHERE migration_merge.entity_type = 'matrix_contact'::text)) + (( SELECT count(*) AS count
                   FROM stg.matrix m
                  WHERE NOT (stg.present(m.name) OR stg.present(m.email) OR stg.present(m.mobile)))),
            3783,
            'loaded + collapsed + blank = every row on the tab'::text
        UNION ALL
         SELECT 'branches complete at 5 levels'::text,
            ( SELECT count(*) AS count
                   FROM branch_matrix_state
                  WHERE branch_matrix_state.complete_levels = 5) AS count,
            692,
            'R-01 recomputed from staging: 692, all present as branches'::text
        UNION ALL
         SELECT 'people from USERS sheet'::text,
            ( SELECT count(*) AS count
                   FROM person
                  WHERE person.superseded_by IS NULL AND person.source_ref ~~ 'USERS!%'::text) AS count,
            55,
            'P-02 creates a further 551 from branch and matrix e-mails'::text
        UNION ALL
         SELECT 'open escalation cases'::text,
            ( SELECT count(*) AS count
                   FROM "case"
                  WHERE "case".status <> 'CLOSED'::case_status) AS count,
            3,
            'ESCALATIONS tab, E-01/E-03'::text
        UNION ALL
         SELECT 'rescued notes'::text,
            ( SELECT count(*) AS count
                   FROM person_event
                  WHERE person_event.source_ref ~~ 'Copy of%'::text AND person_event.kind = 'NOTE'::text) AS count,
            449,
            'Copy of PEOPLE_EVENTS is a primary source'::text
        UNION ALL
         SELECT 'desks configured'::text,
            ( SELECT count(*) AS count
                   FROM desk) AS count,
            8,
            'Ops, Finance, HR, IT, Compliance, MIS, MD office, Administrator fallback'::text
        UNION ALL
         SELECT 'categories configured'::text,
            ( SELECT count(*) AS count
                   FROM category) AS count,
            22,
            'R-06 routing; Fraud/Integrity and Data Privacy pinned to Compliance'::text
        UNION ALL
         SELECT 'administrators'::text,
            ( SELECT count(*) AS count
                   FROM person
                  WHERE person.superseded_by IS NULL AND person.app_role = 'ADMIN'::role_kind) AS count,
            2,
            'USERS.Role, applied by P-05'::text
        UNION ALL
         SELECT 'staged rows unaccounted'::text,
            ( SELECT count(*) AS count
                   FROM migration_unaccounted) AS count,
            0,
            'a row in no table, no merge log and no review queue'::text
        UNION ALL
         SELECT 'queued mail'::text,
            ( SELECT count(*) AS count
                   FROM outbox
                  WHERE outbox.state = 'QUEUED'::outbox_state) AS count,
            0,
            'nothing may send at cut-over'::text
        UNION ALL
         SELECT 'standing tokens'::text,
            ( SELECT count(*) AS count
                   FROM auth_session
                  WHERE auth_session.revoked_at IS NULL) AS count,
            0,
            'no session survives cut-over'::text
        )
 SELECT gate,
    actual,
    expected,
    actual - expected AS delta,
        CASE
            WHEN actual = expected THEN 'PASS'::text
            ELSE 'FAIL'::text
        END AS result,
    basis
   FROM g;

create or replace view public.migration_merge_log as
 SELECT at,
    entity_type,
    rule,
    COALESCE(merged_key, merged_id::text) AS merged,
    kept_id,
    rows_moved,
        CASE
            WHEN reviewed_at IS NULL THEN 'UNREVIEWED'::text
            ELSE 'REVIEWED'::text
        END AS state
   FROM migration_merge m
  ORDER BY entity_type, at;

create or replace view public.migration_open_questions as
 SELECT entity_type,
    count(*) AS open
   FROM migration_review
  WHERE resolved_at IS NULL
  GROUP BY entity_type
  ORDER BY (count(*)) DESC;

create or replace view public.migration_unaccounted as
 SELECT 'BRANCHES'::text AS tab,
    b.row_no,
    COALESCE(b.code, b.name) AS key
   FROM stg.branches b
  WHERE (stg.present(b.code) OR stg.present(b.name)) AND NOT (EXISTS ( SELECT 1
           FROM branch x
          WHERE x.source_ref = ('BRANCHES!'::text || b.row_no))) AND NOT (EXISTS ( SELECT 1
           FROM migration_merge x
          WHERE x.merged_key = ('BRANCHES!'::text || b.row_no))) AND NOT (EXISTS ( SELECT 1
           FROM migration_review x
          WHERE x.entity_ref = ('BRANCHES!'::text || b.row_no)))
UNION ALL
 SELECT 'MATRIX'::text AS tab,
    m.row_no,
    m.branch_code AS key
   FROM stg.matrix m
  WHERE (stg.present(m.name) OR stg.present(m.email) OR stg.present(m.mobile)) AND NOT (EXISTS ( SELECT 1
           FROM matrix_contact x
          WHERE x.source_ref = ('MATRIX!'::text || m.row_no))) AND NOT (EXISTS ( SELECT 1
           FROM migration_merge x
          WHERE x.merged_key = ('MATRIX!'::text || m.row_no))) AND NOT (EXISTS ( SELECT 1
           FROM migration_review x
          WHERE x.entity_ref = ('MATRIX!'::text || m.row_no)))
UNION ALL
 SELECT 'ESCALATIONS'::text AS tab,
    e.row_no,
    e.ref AS key
   FROM stg.escalations e
  WHERE NOT (EXISTS ( SELECT 1
           FROM "case" x
          WHERE x.source_ref = ('ESCALATIONS!'::text || e.row_no))) AND NOT (EXISTS ( SELECT 1
           FROM migration_review x
          WHERE x.entity_ref = ('ESCALATIONS!'::text || e.row_no)));

create or replace view public.plb_goal_kpi as
 SELECT id,
    sheet_id,
    kpi_id,
    weight_pct,
    target_value,
    basis_level,
    basis_note,
    m1_share,
    m2_share,
    m3_share,
    actual_value,
    direction,
    removed_at
   FROM plb_goal_kpi_all
  WHERE removed_at IS NULL;

create or replace view seam.assignment as
 SELECT c.id::text AS id,
    c.geo_node_id::text AS zone_id,
    c.client_id::text AS client_id,
    c.person_id::text AS person_id,
    lh.person_id::text AS location_head_id,
    c.effective_from,
    c.effective_to,
    sr.row_id IS NOT NULL AS is_sample
   FROM coverage_rule c
     LEFT JOIN LATERAL ( SELECT h.person_id
           FROM coverage_rule h
          WHERE h.role = 'LOCATION_HEAD'::text AND NOT h.client_id IS DISTINCT FROM c.client_id AND NOT h.geo_node_id IS DISTINCT FROM c.geo_node_id AND (h.effective_to IS NULL OR h.effective_to >= CURRENT_DATE)
         LIMIT 1) lh ON true
     LEFT JOIN sample_row sr ON sr.table_name = 'coverage_rule'::text AND sr.row_id = c.id
  WHERE c.role <> 'LOCATION_HEAD'::text OR c.role IS NULL;

create or replace view seam.business_record as
 SELECT id::text AS id,
    period,
    geo_node_id::text AS zone_id,
    client_id::text AS client_id,
    mtd,
    revenue,
    NULL::numeric AS projected_expense,
    source_ref AS src
   FROM business_record b;

create or replace view seam.client as
 SELECT id::text AS id,
    code,
    name
   FROM client c;

create or replace view seam.forecast_scenario as
 SELECT s.value ->> 'key'::text AS key,
    s.value ->> 'label'::text AS label,
    (s.value ->> 'multiplier'::text)::numeric AS multiplier,
    s.value ->> 'stance'::text AS stance,
    s.value ->> 'source'::text AS source
   FROM forecast_config f
     CROSS JOIN LATERAL jsonb_array_elements(f.scenarios) s(value);

create or replace view seam.geo_zone as
 SELECT id::text AS id,
    name,
    group_name AS "group",
    region,
    level = 'ZONE'::geo_level AS is_aggregate
   FROM geo_node g;

create or replace view seam.holiday as
 SELECT day AS date,
    name,
    applies_to AS scope,
    confirmed
   FROM holiday h;

create or replace view seam.person as
 SELECT p.id::text AS id,
    p.full_name AS name,
    COALESCE(ch.title, d.title) AS chair,
    cov.geo_node_id::text AS zone_id,
    p.manager_id::text AS reports_to,
    sr.row_id IS NOT NULL AS is_sample
   FROM person p
     LEFT JOIN designation d ON d.id = p.designation_id
     LEFT JOIN chair_holder chh ON chh.person_id = p.id AND chh.to_date IS NULL AND chh.is_primary
     LEFT JOIN chair ch ON ch.id = chh.chair_id
     LEFT JOIN LATERAL ( SELECT cr.geo_node_id
           FROM coverage_rule cr
          WHERE cr.person_id = p.id AND cr.geo_node_id IS NOT NULL AND (cr.effective_to IS NULL OR cr.effective_to >= CURRENT_DATE)
          ORDER BY cr.effective_from DESC NULLS LAST
         LIMIT 1) cov ON true
     LEFT JOIN sample_row sr ON sr.table_name = 'person'::text AND sr.row_id = p.id;

create or replace view seam.rate as
 SELECT r.id::text || COALESCE('#'::text || rl.op_node_id::text, ''::text) AS id,
    r.client_id::text AS client_id,
    rl.op_node_id::text AS zone_id,
    r.scope::text AS scope,
    r.value,
    r.effective_from,
    r.effective_to,
    r.status AS origin,
    NULL::integer AS months_observed,
    NULL::integer AS months_of_history,
    r.reason AS note
   FROM rate r
     LEFT JOIN rate_location rl ON rl.rate_id = r.id;

create or replace view seam.rate_anomaly as
 SELECT NULL::text AS id,
    NULL::text AS client_id,
    NULL::text AS zone_id,
    NULL::text AS period,
    NULL::numeric AS observed,
    NULL::numeric AS expected,
    NULL::text AS kind,
    NULL::text AS note
  WHERE false;

create or replace view seam.tenday_snapshot as
 SELECT b.id::text AS id,
    b.period,
    g.name AS location,
    b.day10 AS day10_revenue,
    b.revenue AS actual_revenue,
    NULL::numeric AS live_addition,
    b.day10 * 5 AS sheet_x5,
    b.day10 * 4 AS sheet_x4,
    b.day10::numeric * 3.5 AS sheet_x35,
    b.day10::numeric * 3.25 AS sheet_x325,
    b.source_ref AS src,
    b.client_id,
    b.geo_node_id
   FROM business_record b
     LEFT JOIN geo_node g ON g.id = b.geo_node_id
  WHERE b.day10 IS NOT NULL;

