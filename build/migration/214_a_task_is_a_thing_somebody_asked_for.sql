-- 214 · A task is a thing somebody asked for
--
-- The blueprint's Performance screen has three buttons over the team list:
-- Set targets, Assign a task, Eligibility matrix. Only the first has ever
-- meant anything here. This makes the second real.
--
-- A task is one person asking another to do a specific thing by a date --
-- "visit the SBI branches this month" -- to one manager or to all of them at
-- once. It is not an escalation and not a KPI. It matters to the score in one
-- place: A-3, contribution beyond your chair, which the PLB Scorecard Guide
-- says must cite "a named artefact ID -- a ticket, a sign-off, a document
-- reference" and never "a generic description". A task closed on time IS that
-- record. A task missed is the other kind of record.
--
-- The table was already here -- task(person_id, assigned_by, title, detail,
-- due_on, period, status, outcome, attribute_weight, closed_at) -- with the
-- right shape and not one row in it. Nothing read it, nothing wrote it, and no
-- function mentioned it. This gives it a verb.
--
-- What a missed task does NOT do, and why: it does not open a case. A case in
-- this tool belongs to a client and a branch and carries an SLA clock; a task
-- has none of those, and forcing one into that shape would put rows in the OGL
-- register that no client ever asked for. Instead a missed task raises an
-- alert to whoever set it, and stands in the month's evidence as a nil for
-- A-3. If a missed task should also open a formal case, that is a policy
-- decision with a client attached to it, and it is recorded as a question
-- rather than assumed here.

-- ------------------------------------------------------------- the states

do $$ begin
  alter table public.task add constraint task_status_check
    check (status in ('OPEN','DONE','LATE','MISSED','CANCELLED'));
exception when duplicate_object then null; end $$;

create index if not exists task_person_period_idx on public.task (person_id, period);
create index if not exists task_open_due_idx     on public.task (due_on) where status = 'OPEN';
create index if not exists task_assigner_idx     on public.task (assigned_by, period);

comment on table public.task is
  'One person asking another for a specific thing by a date. Not an escalation '
  'and not a KPI: it is the record A-3 (contribution beyond your chair) is '
  'scored from, which the Constitution requires to be a named artefact rather '
  'than a manager''s assertion.';
comment on column public.task.attribute_weight is
  'How much this task is worth when A-3 is scored, in the same 0-2 scale as an '
  'Attribute. Null means it is a request, not something scored.';
comment on column public.task.period is
  'The month it counts in, YYYY-MM. Taken from the due date, because a task due '
  'in October is October''s evidence whoever set it in September.';

-- ------------------------------------------------------------- assigning

create or replace function public.task_assign(p_actor uuid, p_in jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_title   text := nullif(btrim(p_in->>'title'), '');
  v_detail  text := nullif(btrim(p_in->>'detail'), '');
  v_due     date := nullif(p_in->>'dueOn','')::date;
  v_weight  numeric := nullif(p_in->>'attributeWeight','')::numeric;
  v_period  text := coalesce(nullif(p_in->>'period',''), to_char(coalesce(v_due, current_date), 'YYYY-MM'));
  v_admin   boolean;
  v_made    int := 0;
  v_refused text[] := '{}';
  r record;
begin
  if p_actor is null then return jsonb_build_object('error','no_actor'); end if;
  if v_title is null then return jsonb_build_object('error','no_title',
      'reason','A task needs a sentence saying what is being asked for.'); end if;
  if v_weight is not null and (v_weight < 0 or v_weight > 2) then
    return jsonb_build_object('error','bad_weight',
      'reason','An attribute is worth 0 to 2 points. A task cannot be worth more than the attribute it feeds.');
  end if;

  select coalesce(p.app_role = 'ADMIN', false) into v_admin from person p where p.id = p_actor;

  -- Who is being asked. Named people, everybody in a chair, everybody in a
  -- department, or the actor's whole subtree -- the four ways the blueprint's
  -- "all the managers" actually gets written down. The subtree is read once:
  -- it is a recursive walk and the audience can be a hundred people.
  create temp table if not exists _mine (person_id uuid primary key) on commit drop;
  delete from _mine;
  insert into _mine select person_id from kpi_subtree_people(p_actor) on conflict do nothing;

  for r in
    select distinct pe.id as person_id, pe.full_name
      from person pe
     where pe.employment_status = 'ACTIVE' and pe.superseded_by is null
       and coalesce(pe.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
       and (
            (p_in ? 'people'
               and pe.id in (select (jsonb_array_elements_text(p_in->'people'))::uuid))
         or (nullif(p_in->>'chair','') is not null and exists (
               select 1 from chair_holder h
                where h.person_id = pe.id and h.chair_id = (p_in->>'chair')::uuid
                  and (h.to_date is null or h.to_date >= current_date)))
         or (nullif(p_in->>'department','') is not null and pe.department = p_in->>'department')
         or (coalesce((p_in->>'allReports')::boolean, false)
               and pe.id in (select person_id from _mine))
       )
     order by pe.full_name
  loop
    -- You may ask somebody for something if they are under you, or if you are
    -- the administrator. Anything else is a request, and requests have their
    -- own door.
    if not v_admin
       and r.person_id <> p_actor
       and r.person_id not in (select person_id from _mine) then
      v_refused := v_refused || r.full_name;
      continue;
    end if;
    insert into task (person_id, assigned_by, title, detail, due_on, period,
                      status, attribute_weight)
    values (r.person_id, p_actor, v_title, v_detail, v_due, v_period, 'OPEN', v_weight);
    v_made := v_made + 1;
  end loop;

  if v_made = 0 and array_length(v_refused,1) is null then
    return jsonb_build_object('error','nobody',
      'reason','That names nobody who is still here.');
  end if;

  return jsonb_build_object('created', v_made, 'period', v_period,
    'refused', to_jsonb(v_refused),
    'note', case when array_length(v_refused,1) is null then null
                 else 'A task can only be set for somebody who reports to you.' end);
end $fn$;

comment on function public.task_assign(uuid, jsonb) is
  'Sets one task for named people, for a chair, for a department, or for the '
  'actor''s whole subtree. Refuses anybody outside it by name rather than '
  'silently dropping them.';

-- -------------------------------------------------------------- closing it

create or replace function public.task_close(p_actor uuid, p_task uuid, p_outcome text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare t task; v_state text;
begin
  select * into t from task where id = p_task;
  if t.id is null then return jsonb_build_object('error','no_such_task'); end if;
  if t.status <> 'OPEN' then
    return jsonb_build_object('error','already_closed', 'status', t.status);
  end if;
  if p_actor <> t.person_id and p_actor <> t.assigned_by
     and not exists (select 1 from person p where p.id = p_actor and p.app_role = 'ADMIN') then
    return jsonb_build_object('error','not_yours',
      'reason','A task is closed by the person it was set for, or by whoever set it.');
  end if;

  -- On time or late is a fact about the clock, not something either party types in.
  v_state := case when t.due_on is null or current_date <= t.due_on then 'DONE' else 'LATE' end;

  update task set status = v_state, outcome = nullif(btrim(p_outcome),''), closed_at = now()
   where id = p_task;

  return jsonb_build_object('status', v_state, 'dueOn', t.due_on, 'closedOn', current_date);
end $fn$;

comment on function public.task_close(uuid, uuid, text) is
  'Closes a task. Whether it reads DONE or LATE is decided by the due date '
  'against today, not by whoever closes it.';

create or replace function public.task_cancel(p_actor uuid, p_task uuid, p_why text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare t task;
begin
  select * into t from task where id = p_task;
  if t.id is null then return jsonb_build_object('error','no_such_task'); end if;
  if p_actor <> t.assigned_by
     and not exists (select 1 from person p where p.id = p_actor and p.app_role = 'ADMIN') then
    return jsonb_build_object('error','not_yours',
      'reason','Only whoever set a task can call it off.');
  end if;
  update task set status = 'CANCELLED', outcome = nullif(btrim(p_why),''), closed_at = now()
   where id = p_task and status = 'OPEN';
  return jsonb_build_object('cancelled', found);
end $fn$;

-- ---------------------------------------------------------------- the sweep

create or replace function public.task_sweep()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare v_missed int := 0; v_told int := 0; v_more int := 0;
begin
  create temp table if not exists _missed (id uuid primary key, person_id uuid,
                                           assigned_by uuid, title text) on commit drop;
  delete from _missed;

  with gone as (
    update task set status = 'MISSED'
     where status = 'OPEN' and due_on is not null and due_on < current_date
    returning id, person_id, assigned_by, title)
  insert into _missed select id, person_id, assigned_by, title from gone;
  get diagnostics v_missed = row_count;

  if v_missed = 0 then
    return jsonb_build_object('tasks_missed', 0, 'people_told', 0);
  end if;

  -- This goes to the two people it is about, and to nobody else. The Alerts
  -- screen is the administrator's, filtered by role and not by person, so a
  -- missed task has no business on it: ops_alert_open() would show one
  -- manager's forgotten instruction to whoever holds ADMIN. A notification is
  -- addressed to a person, which is what this is.
  --
  -- One line each, however many tasks. Eleven separate notices about the same
  -- forgotten instruction is how a bell stops being read.

  -- the person who missed it: it is their month's evidence
  insert into notification (person_id, kind, text, entity_type, entity_id, push, at)
  select m.person_id, 'TASK_MISSED',
         count(*) || ' task' || case when count(*) = 1 then '' else 's' end
           || ' you were given went past its date'
           || case when count(*) = 1 then ' — ' || min(m.title) else '' end
           || '. A missed task stands as a nil for A-3 this month.',
         'person', m.person_id, true, now()
    from _missed m group by m.person_id;
  get diagnostics v_told = row_count;

  -- whoever asked for it: they are the only one who can call it off
  insert into notification (person_id, kind, text, entity_type, entity_id, push, at)
  select m.assigned_by, 'TASK_MISSED',
         count(*) || ' task' || case when count(*) = 1 then '' else 's' end
           || ' you set went past the date you gave'
           || case when count(*) = 1 then ' — ' || min(m.title) else '' end
           || '. Close the ones that were done, and call off the ones that should not have been asked for.',
         'person', m.assigned_by, false, now()
    from _missed m where m.assigned_by <> m.person_id group by m.assigned_by;
  get diagnostics v_more = row_count;
  v_told := v_told + v_more;

  return jsonb_build_object('tasks_missed', v_missed, 'people_told', v_told);
end $fn$;

comment on function public.task_sweep() is
  'Turns an open task whose date has passed into a missed one, and tells the two '
  'people it concerns -- the one who was asked and the one who asked -- once '
  'each, however many tasks there are. It raises no ops_alert: that screen is '
  'filtered by role, not by person, so it would show one manager''s forgotten '
  'instruction to the administrator. It opens no case either: a case belongs to '
  'a client and a branch, and a task has neither.';

-- Every other sweep in this database is a job_config row, a crux_*_tick that
-- reads it, and a cron line that calls the tick. This is the same, at 07:15
-- India time -- after the penalty sweep, before anybody opens the tool, so a
-- task that went past its date is already known when the day starts.

create or replace function public.crux_task_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  if not coalesce((select enabled from job_config where job_key='TASK_SWEEP'), false) then
    return jsonb_build_object('skipped', 'TASK_SWEEP is switched off.');
  end if;
  return task_sweep();
end $fn$;

insert into public.job_config (job_key, enabled, cron)
select 'TASK_SWEEP', true, '45 1 * * *'
 where not exists (select 1 from job_config where job_key = 'TASK_SWEEP');

do $$ begin
  perform cron.schedule('crux-task-sweep', '45 1 * * *', 'select crux_task_tick()');
exception when undefined_table then
  raise notice '214: no pg_cron here, so the sweep is not scheduled -- the function is still callable';
when others then
  raise notice '214: could not schedule the task sweep (%), the function is still callable', sqlerrm;
end $$;

-- ------------------------------------------------------- what it is worth

create or replace function public.task_evidence(p_person uuid, p_period text)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select jsonb_build_object(
    'period',   p_period,
    'assigned', count(*),
    'onTime',   count(*) filter (where status = 'DONE'),
    'late',     count(*) filter (where status = 'LATE'),
    'missed',   count(*) filter (where status = 'MISSED'),
    'open',     count(*) filter (where status = 'OPEN'),
    'cancelled',count(*) filter (where status = 'CANCELLED'),
    -- A-3 runs 0 to 2. Full marks means everything asked for landed when it was
    -- asked for. Late is half. Missed is nothing. Nobody is scored on a month
    -- they were asked for nothing in -- that returns null, not zero.
    'a3Suggested', case
      when count(*) filter (where status in ('DONE','LATE','MISSED')) = 0 then null
      else round( 2.0 * (
             count(*) filter (where status = 'DONE')
             + 0.5 * count(*) filter (where status = 'LATE')
           )::numeric
           / nullif(count(*) filter (where status in ('DONE','LATE','MISSED')), 0), 2)
      end,
    'items', coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'title', title, 'dueOn', due_on, 'status', status,
        'outcome', outcome, 'weight', attribute_weight,
        'setBy', (select pp.full_name from person pp where pp.id = assigned_by))
      order by due_on nulls last, created_at), '[]'::jsonb))
  from task where person_id = p_person and period = p_period;
$fn$;

comment on function public.task_evidence(uuid, text) is
  'A month''s tasks for one person, and what A-3 would be if it were scored from '
  'them alone. A suggestion with its working shown -- the manager still scores. '
  'Returns null rather than zero for a month nobody asked for anything.';

create or replace function public.task_mine(p_person uuid, p_period text)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select jsonb_build_object(
    'period', p_period,
    'owed', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id, 'title', t.title, 'detail', t.detail, 'dueOn', t.due_on,
               'status', t.status, 'weight', t.attribute_weight,
               'overdue', (t.status = 'OPEN' and t.due_on is not null and t.due_on < current_date),
               'setBy', b.full_name)
             order by t.due_on nulls last, t.created_at)
        from task t join person b on b.id = t.assigned_by
       where t.person_id = p_person and t.period = p_period), '[]'::jsonb),
    'set', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id, 'title', t.title, 'dueOn', t.due_on, 'status', t.status,
               'forWhom', w.full_name)
             order by t.due_on nulls last, t.created_at)
        from task t join person w on w.id = t.person_id
       where t.assigned_by = p_person and t.period = p_period), '[]'::jsonb));
$fn$;

comment on function public.task_mine(uuid, text) is
  'A month of tasks from both sides: what I owe and what I asked of other people.';

grant execute on function public.task_assign(uuid, jsonb)   to authenticated;
grant execute on function public.task_close(uuid, uuid, text) to authenticated;
grant execute on function public.task_cancel(uuid, uuid, text) to authenticated;
grant execute on function public.task_evidence(uuid, text)  to authenticated;
grant execute on function public.task_mine(uuid, text)      to authenticated;

-- ------------------------------------------- the split the Constitution sets

-- "Monthly Score = (0.75 x KPI score) + (0.25 x Attribute score)" -- PLB
-- Scorecard Guide §2, and the same figures in Annexure F. pms_weighting is the
-- table the blueprint's "PMS weighting - Admin and HR" panel writes to, and it
-- had no rows, so the split existed only as two numbers typed into a heading in
-- the page. This puts it where it can be read and changed.
--
-- Effective 1 October 2026, which is the Constitution's own date and the start
-- of the first quarter the scheme runs in. Nothing before that is scored under
-- V2.0, and this deliberately does not pretend otherwise.

insert into public.pms_weighting (scope_all, chair_id, person_id, kpi_percent, attr_percent, effective_from, set_by)
select true, null, null, 75, 25, date '2026-10-01',
       (select id from person where lower(work_email) = 'operations.alert@cruxindia.co.in' limit 1)
 where not exists (select 1 from pms_weighting where scope_all and effective_from = date '2026-10-01');

-- ------------------------------------------------------------------ checks

do $do$
declare v_w int; v_fn int; v_ev jsonb;
begin
  select count(*) into v_w from pms_weighting where scope_all;
  if v_w = 0 then raise exception '214: the company-wide weighting did not land'; end if;

  if (select kpi_percent + attr_percent from pms_weighting
       where scope_all order by effective_from desc limit 1) <> 100 then
    raise exception '214: a weighting that does not add to 100 is not a weighting';
  end if;

  select count(*) into v_fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('task_assign','task_close','task_cancel','task_sweep','task_evidence','task_mine');
  if v_fn <> 6 then raise exception '214: expected 6 task functions, found %', v_fn; end if;

  -- a month nobody was asked for anything in is not a zero
  v_ev := task_evidence('00000000-0000-0000-0000-000000000000'::uuid, '2026-10');
  if (v_ev->>'a3Suggested') is not null then
    raise exception '214: an empty month suggested an A-3 score of %', v_ev->>'a3Suggested';
  end if;

  raise notice '214: task engine in place, weighting 75/25 from 2026-10-01';
end $do$;
