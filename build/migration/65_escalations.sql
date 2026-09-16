-- =====================================================================
-- 65 · ESCALATIONS — the three live cases from the ESCALATIONS tab.
-- No migration script covered this tab, so the "open escalation cases" gate
-- read 0 against an expected 3. Rules:
--   E-01 the sheet's Category is a short label, not a category name; it is
--        mapped explicitly and anything unmapped is refused, never guessed
--   E-02 owner is the desk primary at migration time; a vacant desk leaves the
--        owner null and the desk carries the case, which case_has_owner allows
--   E-03 Status maps straight onto case_status; RESOLVED with no resolution
--        timestamp in the sheet is asked about rather than invented
--
-- Runs after 62_config_desks_categories.sql: a case cannot exist before the
-- category and desk it routes to.
-- =====================================================================
create temp table esc_map (sheet text primary key, category text);
insert into esc_map values ('Billing','Billing'), ('Service','Service Delivery');

insert into "case" (ref, client_id, branch_id, category_id, raised_by, against_person_id,
                    against_text, description, owner_person_id, desk_id, status,
                    resolved_at, strike_count, last_activity_at, created_at, source_ref)
select btrim(e.ref), cl.id, b.id, cat.id,
       coalesce(rp.superseded_by, rp.id),
       coalesce(ap.superseded_by, ap.id),
       stg.norm_email(e.against),
       nullif(btrim(e.description),''),
       d.primary_person_id, d.id,
       upper(btrim(e.status))::case_status,
       stg.ts(e.resolved_at),
       coalesce(nullif(regexp_replace(coalesce(e.strike_count,''),'[^0-9]','','g'),'')::int, 0),
       coalesce(stg.ts(e.created_at), now()),
       coalesce(stg.ts(e.created_at), now()),
       'ESCALATIONS!' || e.row_no
from stg.escalations e
join client cl on cl.code = btrim(e.client_code)
join esc_map m on m.sheet = btrim(e.category)
join category cat on cat.name = m.category
join desk d on d.id = cat.desk_id
join person rp on rp.work_email = stg.norm_email(e.raised_by)
join person ap on ap.work_email = stg.norm_email(e.against)
left join branch b on b.client_id = cl.id and b.code = btrim(e.branch_code)
where upper(btrim(e.status)) in ('OPEN','IN_PROGRESS','RESOLVED','CLOSED','BLOCKED')
on conflict (ref) do nothing;

-- E-01 receipt · any row the explicit map does not cover stays visible
insert into migration_review (entity_type, entity_ref, question, context)
select 'case', 'ESCALATIONS!' || e.row_no,
       'Escalation category "' || coalesce(btrim(e.category),'(blank)') || '" has no mapping to one of the 22 categories — which one?',
       concat_ws(' | ', e.ref, e.client_code, left(coalesce(e.description,''), 120))
from stg.escalations e
where not exists (select 1 from esc_map m where m.sheet = btrim(e.category))
  and not exists (select 1 from migration_review r where r.entity_ref = 'ESCALATIONS!' || e.row_no);

-- E-03 receipt · RESOLVED without a resolution timestamp cannot start the
-- 7-day auto-close clock, so the date is asked for rather than guessed.
insert into migration_review (entity_type, entity_ref, question, context)
select 'case', 'ESCALATIONS!' || e.row_no,
       'Escalation ' || btrim(e.ref) || ' is RESOLVED but the sheet carries no resolution date, so the 7-day auto-close window cannot start. What date was it resolved?',
       concat_ws(' | ', e.raised_by, e.against, left(coalesce(e.description,''), 120))
from stg.escalations e
where upper(btrim(coalesce(e.status,''))) = 'RESOLVED' and not stg.present(e.resolved_at)
  and not exists (select 1 from migration_review r where r.entity_ref = 'ESCALATIONS!' || e.row_no);
