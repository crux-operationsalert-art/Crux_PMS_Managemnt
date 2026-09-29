-- =====================================================================
-- 222 · The quarter is not everybody's to read
--
-- Reported, after 218 went in: "Data leakage still exists, managers are
-- seeing everyone's data and not only of their team."
--
-- Correct. 218 closed the door the Performance screen's KPI half goes
-- through. The appraisal half goes through a different one and I did not
-- check it.
--
--     GET /plb/quarter  ->  plb_quarter(p_quarter date)
--
-- takes no actor at all. It returns, to anybody who can sign in:
--
--   * every goal sheet in the company -- the person's name, employee
--     number, chair, status, TARGET PLB IN RUPEES, months scored,
--     attributes pending, disputes open and overdue, whether it is
--     certified and published, and the AMOUNT PAID; and
--   * `inScheme`, which is every seated person on a chair that carries a
--     measure set, with their chair and whether they have a sheet yet.
--
-- The rupee figures are the part that matters. A goal sheet's target and a
-- published result are somebody's pay, and every manager in the company
-- could read every colleague's.
--
-- THE SAME RULE, NOT A NEW ONE
--
-- perf_rel already answers "what is this person to me" -- self, manage,
-- watch, admin, or nothing. It is what 218 put in and what the KPI half
-- already obeys. The quarter now asks the same question about each row and
-- drops the ones that come back null, so the two halves of one screen
-- cannot disagree about who somebody is allowed to see.
--
-- WHY THE OLD SIGNATURE IS NOT SIMPLY DROPPED
--
-- plb_quarter(date) is left in place and made to refuse. A drop would take
-- with it anything that still calls it, and a function that returns
-- `{"error": "no_actor"}` says what happened; a function that is missing
-- produces a 500 and sends somebody reading logs. It cannot leak either
-- way, which is the point.
-- =====================================================================

create or replace function plb_quarter(p_quarter date, p_actor uuid)
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $function$
  select jsonb_build_object(
    'quarter', date_trunc('quarter', p_quarter)::date,
    'sheets', coalesce((
      select jsonb_agg(jsonb_build_object(
               'sheetId', s.id, 'person', p.full_name, 'personId', p.id,
               'employeeNo', p.employee_no,
               'chair', ch.title, 'status', s.status, 'targetPlb', s.target_plb_inr,
               'rel', perf_rel(p_actor, p.id),
               'maySet', perf_rel(p_actor, p.id) in ('manage','admin'),
               'acknowledged', s.acknowledged_at is not null,
               'monthsScored', (select count(*) from plb_month_score ms
                                 where ms.sheet_id = s.id and ms.kpi_points is not null),
               'attrsPending', (select count(*) from plb_goal_attribute ga
                                 where ga.sheet_id = s.id and ga.state = 'PROPOSED'),
               'needsCountersign', (select count(*) from plb_month_score ms
                                     where ms.sheet_id = s.id and coalesce(ms.attr_points,0) > 7.5
                                       and ms.countersign_at is null),
               'disputesOpen', (select count(*) from plb_dispute d
                                 where d.sheet_id = s.id and d.closed_at is null),
               'disputesOverdue', (select count(*) from plb_dispute d
                                 where d.sheet_id = s.id and d.closed_at is null
                                   and ((d.stage = 'RAISED' and current_date > d.respond_due)
                                     or (d.stage = 'ESCALATED' and current_date > d.decide_due))),
               'certified', (select r.certified_at is not null from plb_result r where r.sheet_id = s.id),
               'published', (select r.published_at is not null from plb_result r where r.sheet_id = s.id),
               'amount', (select r.amount_inr from plb_result r where r.sheet_id = s.id))
               order by ch.title, p.full_name)
        from plb_goal_sheet s
        join person p on p.id = s.person_id
        join chair ch on ch.id = s.chair_id
       where s.quarter = date_trunc('quarter', p_quarter)::date
         -- the whole of the fix, twice
         and perf_rel(p_actor, p.id) is not null), '[]'::jsonb),
    'inScheme', coalesce((
      select jsonb_agg(jsonb_build_object(
               'personId', p.id, 'person', p.full_name, 'employeeNo', p.employee_no,
               'chair', ch.title, 'chairCode', ch.code,
               'rel', perf_rel(p_actor, p.id),
               'kpiCount', (select count(*) from kpi_definition k
                             where k.chair_id = ch.id and k.active and k.position < 100),
               'hasSheet', exists (select 1 from plb_goal_sheet s
                                    where s.person_id = p.id
                                      and s.quarter = date_trunc('quarter', p_quarter)::date))
               order by ch.title, p.full_name)
        from chair_holder h
        join person p on p.id = h.person_id
        join chair ch on ch.id = h.chair_id
       where h.to_date is null
         and exists (select 1 from kpi_definition k
                      where k.chair_id = ch.id and k.active and k.position < 100)
         and perf_rel(p_actor, p.id) is not null), '[]'::jsonb));
$function$;

comment on function plb_quarter(date,uuid) is
  'The quarter as one person may see it: their own sheet, their team''s, '
  'and the sheets of everyone below their team. Each row says which of '
  'those it is, so the screen can offer a button only where one will be '
  'accepted. Until migration 222 this took no actor and returned every '
  'sheet in the company, target and amount in rupees included, to anybody '
  'who could sign in.';

-- The old door, left standing and made to refuse. Dropping it would take
-- with it anything that still calls it; this way a stale caller is told
-- what to do and no row goes out either way.
create or replace function plb_quarter(p_quarter date)
returns jsonb
language sql
stable
set search_path to 'public'
as $function$
  select jsonb_build_object(
    'error', 'no_actor',
    'reason', 'The quarter is read as somebody. Call plb_quarter(quarter, actor) '
              || 'so the answer can be narrowed to the sheets that person may see.',
    'quarter', date_trunc('quarter', p_quarter)::date,
    'sheets', '[]'::jsonb, 'inScheme', '[]'::jsonb);
$function$;

comment on function plb_quarter(date) is
  'Refuses. Superseded by plb_quarter(date, uuid) in migration 222, which '
  'narrows the quarter to the reporting line. Kept rather than dropped so '
  'a stale caller is told what to do instead of producing a 500.';

revoke all on function plb_quarter(date,uuid) from public, anon, authenticated;
revoke all on function plb_quarter(date)      from public, anon, authenticated;

-- ---------------------------------------------- the sheet, asked by somebody
--
-- plb_sheet(sheet) is SECURITY DEFINER, reads the target and the amount in
-- rupees, and asks nothing. Migration 218 gated it at the route by having
-- /sheet/:id call plb_sheet_rel first -- which works, and is a gate exactly
-- one route remembers. The assertion below caught that, which is what it is
-- for, so the gate moves into the database beside the others.
create or replace function plb_sheet_for(p_actor uuid, p_sheet uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_rel text; v_out jsonb;
begin
  v_rel := plb_sheet_rel(p_actor, p_sheet);
  if v_rel is null then
    if not exists (select 1 from plb_goal_sheet where id = p_sheet) then
      return jsonb_build_object('error','no_such_sheet');
    end if;
    return jsonb_build_object('error','not_permitted',
      'reason','A goal sheet is the employee''s and the line above them.');
  end if;
  v_out := plb_sheet(p_sheet);
  if jsonb_typeof(v_out) = 'object' then
    v_out := v_out || jsonb_build_object(
      'rel', v_rel, 'mine', v_rel = 'self',
      'maySet', v_rel in ('manage','admin'));
  end if;
  return v_out;
end $function$;

comment on function plb_sheet_for(uuid,uuid) is
  'plb_sheet, asked by somebody, refusing a sheet outside the asker''s '
  'line and saying which relationship it is so the screen knows whether to '
  'draw an input or a number.';

revoke all on function plb_sheet_for(uuid,uuid) from public, anon, authenticated;

-- ------------------------------------------------------- the assertion
-- The five functions a route can reach that return somebody's numbers.
-- Each passes either by asking perf_rel itself, or by having a _for
-- wrapper that does -- which is the shape 218 and 222 both settled on. If
-- a later migration unwraps one, this fails the rebuild rather than
-- waiting for it to be reported again.
--
-- Deliberately a named list and not a search for the column. A search also
-- catches plb_sheet_issue, which WRITES a sheet and checks its own
-- permission, and plb_dispute_impact, which is arithmetic nothing calls
-- from outside -- and an assertion that cries wolf gets deleted by the
-- next person in a hurry.
do $$
declare v_bad text;
begin
  select string_agg(w.want, ', ') into v_bad
    from (values ('plb_quarter'), ('plb_sheet'), ('perf_tree'),
                 ('perf_history'), ('perf_kpi_score')) w(want)
   where exists (
     select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = w.want and p.prosecdef)
     and not exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = w.want
          and pg_get_functiondef(p.oid) ilike '%perf_rel%')
     and not exists (
       select 1 from pg_proc f join pg_namespace fn on fn.oid = f.pronamespace
        where fn.nspname = 'public' and f.proname = w.want || '_for'
          and (pg_get_functiondef(f.oid) ilike '%perf_rel%'
            or pg_get_functiondef(f.oid) ilike '%plb_sheet_rel%'));
  if v_bad is not null then
    raise exception
      'migration 222: % returns somebody''s numbers and neither asks perf_rel nor has a _for wrapper that does', v_bad;
  end if;
end $$;
