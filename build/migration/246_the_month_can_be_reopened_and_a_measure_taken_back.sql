-- The month can be reopened, and a measure can be taken back (246)
--
-- "PMS is not ready, set KPI is still not working and just like that most of
--  the Buttons in PMS are not working. this is P1 to finish"
--
-- MEASURED FIRST, because the sentence says "buttons" and the cause turned
-- out not to be buttons. The published page was loaded in Chromium, a
-- manager was signed in against stubbed services, and every control on
-- Performance & appraisal was pressed:
--
--     19 controls on first draw, 22 with a person open, 30 with the KPI
--     form open. Every one wired. No JavaScript error. No console error.
--
-- The front end is not dead. The writes are being refused, and there are
-- three reasons in the database. This file fixes two of them; the third is
-- the screen's and is in screen-perf.js.
--
-- ------------------------------------------------------------ the first
-- THE WINDOW FOR SETTING KPIs IS FIVE WORKING DAYS A MONTH, AND THERE IS NO
-- WAY TO EXTEND IT.
--
--     perf_cycle_open sets assign_closes = plb_wd_after(period_start, 5)
--
--     2026-10-01  closes 2026-10-08   open today (06 Oct)
--     2026-09-01  closed 2026-09-07   SHUT
--
-- perf_assign, perf_assign_edit and perf_assign_remove all answer
-- window_closed for anybody but an administrator. So from 9 October every
-- manager in the company is offered four KPI controls and every one of them
-- refuses — and the only way to reopen the month is to write SQL by hand,
-- because perf_cycle_open answers "that cycle was already open" and changes
-- nothing.
--
-- The rule itself is kept. It is the Constitution's, and a month whose
-- measures can be rewritten at the end of it is a month that measured
-- nothing. What is added is the thing that makes a rule workable instead of
-- merely strict: the people who own the scheme can move the date, with a
-- reason, recorded.
--
-- ----------------------------------------------------------- the second
-- perf_assign_remove DOES NOT EXIST IN THE LIVE DATABASE. It is the last
-- block of migration 240 and it never landed, so the Remove button comes
-- back as SQLSTATE 42883 — "no function of that name".
--
-- It lands here with one deliberate change: it WITHDRAWS and never deletes.
--
-- 240 deleted the row when nothing had been filed against it and withdrew
-- it otherwise. That looked tidy and it is wrong twice. A measure that was
-- given and taken back is a fact about that month -- it is the evidence that
-- the manager set it, which is exactly what somebody asks about afterwards.
-- And the audit row 240 writes for the delete points at a perf_assignment id
-- that no longer exists, so the record of the removal cannot be followed
-- back to what was removed.
--
-- One state, one meaning: WITHDRAWN is "no longer asked for". 240 already
-- widened the state constraint to carry it and already swept perf_tree and
-- perf_kpi_score to filter it, so everything downstream reads it correctly
-- the day this lands.
--
-- The unique index has to move with it, and that is the part worth being
-- careful about. perf_assignment_once_top says one KPI per person per cycle.
-- With a withdrawn row left in the table, giving the same measure again
-- would hit that index -- so "once per cycle" is narrowed to mean once
-- ASKED FOR per cycle, which is what it always meant.

-- ------------------------------------------- once means once asked for
do $idx$
declare v_def text;
begin
  select pg_get_indexdef(ix.indexrelid) into v_def
    from pg_index ix join pg_class i on i.oid = ix.indexrelid
    join pg_class t on t.oid = ix.indrelid
    join pg_namespace n on n.oid = t.relnamespace
   where n.nspname = 'public' and t.relname = 'perf_assignment'
     and i.relname = 'perf_assignment_once_top';

  if v_def is null then
    raise exception 'Migration 246: perf_assignment_once_top is not there, so '
                    'this file cannot tell what one-per-cycle currently means.';
  elsif position('WITHDRAWN' in v_def) > 0 then
    raise notice 'perf_assignment_once_top already ignores withdrawn measures';
  else
    -- Checked rather than assumed: if the index has gained a column since
    -- this was written, rewriting it from memory would quietly drop it.
    if position('cycle_id' in v_def) = 0 or position('person_id' in v_def) = 0
       or position('kpi_id' in v_def) = 0 or position('part_of_id' in v_def) = 0 then
      raise exception 'Migration 246: perf_assignment_once_top is %, which is '
                      'not the index this expected.', v_def;
    end if;
    drop index perf_assignment_once_top;
    create unique index perf_assignment_once_top
        on perf_assignment (cycle_id, person_id, kpi_id)
     where kpi_id is not null and part_of_id is null
       and state is distinct from 'WITHDRAWN';
    raise notice 'one KPI per person per cycle now means one ASKED FOR';
  end if;
end $idx$;

-- ------------------------------------------------- taking a measure back
create or replace function perf_assign_remove(p_actor uuid, p_assignment uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  a perf_assignment; c perf_cycle; n_filed int; n_kids int; n_split int;
begin
  select * into a from perf_assignment where id = p_assignment;
  if a.id is null then return jsonb_build_object('error','no_such_assignment'); end if;

  if not perf_may_set(p_actor, a.person_id) then
    return jsonb_build_object('error','not_permitted',
      'reason','A measure is taken back by the person''s own manager or by '
            || 'an administrator -- and never by themselves.');
  end if;

  if a.state = 'WITHDRAWN' then
    return jsonb_build_object('ok', true, 'withdrawn', true, 'changed', false,
      'note','That measure has already been taken back.');
  end if;

  select * into c from perf_cycle where id = a.cycle_id;
  if current_date > c.assign_closes
     and not exists (select 1 from person where id = p_actor and app_role = 'ADMIN') then
    return jsonb_build_object('error','window_closed',
      'reason','Measures for ' || c.period_start || ' had to be settled by '
            || c.assign_closes || '. HR or an administrator can reopen the '
            || 'month on the Performance screen, and the reopening is recorded.');
  end if;

  -- Somebody else's measure climbs into this one. Taking it back would leave
  -- their number with nowhere to go, so it is refused by name rather than
  -- cascaded into silently.
  select count(*) into n_kids from perf_assignment x
   where x.rolls_into_id = a.id and x.person_id <> a.person_id
     and x.state is distinct from 'WITHDRAWN';
  if n_kids > 0 then
    return jsonb_build_object('error','feeds_this',
      'reason', n_kids || ' measure(s) below this one climb into it. Move or '
             || 'take those back first, or their numbers have nowhere to add up to.');
  end if;

  select count(*) into n_filed from perf_entry e
   where e.assignment_id = a.id
      or e.assignment_id in (select x.id from perf_assignment x where x.part_of_id = a.id);
  select count(*) into n_split from perf_assignment where part_of_id = a.id;

  -- Withdrawn, never deleted, whether or not anything was filed. The row is
  -- the evidence that this was asked for, and the audit entry below has
  -- something to point at.
  update perf_assignment set state = 'WITHDRAWN'
   where id = a.id or part_of_id = a.id;

  insert into audit_entry (actor_id, action, entity_type, entity_ref,
                           old_value, new_value)
  values (p_actor, 'PERF_KPI_WITHDRAWN', 'perf_assignment', a.id::text,
          jsonb_build_object('name', a.name, 'unit', a.unit,
                             'target', a.target_value, 'person', a.person_id,
                             'state', a.state, 'splits', n_split),
          jsonb_build_object('state','WITHDRAWN','filings', n_filed));

  return jsonb_build_object('ok', true, 'withdrawn', true, 'changed', true,
    'filings', n_filed, 'splits', n_split,
    'note', 'Taken back. It stops being asked for and stops counting'
         || case when n_split > 0
                 then ', and its ' || n_split || ' client share(s) went with it'
                 else '' end
         || case when n_filed > 0
                 then '. The ' || n_filed || ' figure(s) already filed against it '
                   || 'still read back, because they are a record of what happened'
                 else '. Nothing had been filed against it' end
         || '.');
end $function$;

comment on function perf_assign_remove(uuid, uuid) is
  'Takes a measure back by marking it WITHDRAWN. It is never deleted: the row '
  'is the evidence the manager asked for it, and perf_tree and '
  'perf_kpi_score already read WITHDRAWN as "no longer asked for".';

-- ------------------------------------------------- reopening the month
-- The same three the scheme already belongs to, written the same way
-- perf_cycle_open writes it. Migration 242's rule: when a screen offers a
-- control, it must ask the same question the write asks, in the same words,
-- or the tool puts a button in front of somebody that always refuses.
create or replace function perf_cycle_extend(p_actor uuid, p_cycle uuid,
                                             p_until date, p_why text)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare a person%rowtype; c perf_cycle; v_was date;
begin
  select * into a from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null or (a.app_role <> 'ADMIN'
                      and coalesce(a.department,'') <> 'Human Resources'
                      and coalesce(a.department,'') <> 'Business Excellence') then
    return jsonb_build_object('error','not_permitted',
      'reason','Reopening a month for KPI setting is HR''s, Business '
            || 'Excellence''s or an administrator''s -- the same three who open it.');
  end if;

  select * into c from perf_cycle where id = p_cycle;
  if c.id is null then return jsonb_build_object('error','no_such_cycle'); end if;

  if p_why is null or btrim(p_why) = '' then
    return jsonb_build_object('error','reason_required',
      'reason','Reopening a month changes what a team can still be asked for, '
            || 'so it carries the reason it was reopened.');
  end if;

  if p_until is null then
    return jsonb_build_object('error','no_date',
      'reason','Say the date KPI setting should close instead.');
  end if;
  if p_until < current_date then
    return jsonb_build_object('error','already_past',
      'reason', p_until || ' is in the past, so it would shut the month rather '
             || 'than reopen it.');
  end if;
  -- Only ever later. Moving the date earlier would shut a window people are
  -- working inside, retrospectively, which is not something a screen should
  -- be able to do by accident.
  if p_until <= c.assign_closes then
    return jsonb_build_object('error','not_later',
      'reason','KPIs for ' || c.period_start || ' can already be set until '
            || c.assign_closes || '. This only ever moves that date later.');
  end if;
  -- And never past the day filing closes: a measure first asked for after
  -- nobody can file against it is a measure nobody can meet.
  if p_until > c.entry_closes then
    return jsonb_build_object('error','after_filing_closes',
      'reason','Filing for ' || c.period_start || ' closes on ' || c.entry_closes
            || ', so a KPI set after that could never be filed against.');
  end if;

  v_was := c.assign_closes;
  update perf_cycle set assign_closes = p_until where id = c.id;

  insert into audit_entry (actor_id, action, entity_type, entity_ref,
                           old_value, new_value)
  values (p_actor, 'PERF_CYCLE_EXTENDED', 'perf_cycle', c.id::text,
          jsonb_build_object('assignCloses', v_was),
          jsonb_build_object('assignCloses', p_until, 'why', btrim(p_why),
                             'by', a.full_name));

  return jsonb_build_object('ok', true, 'cycleId', c.id,
    'period', c.period_start, 'was', v_was, 'assignCloses', p_until,
    'note','KPIs for ' || c.period_start || ' may now be set until ' || p_until
        || '. Who reopened it and why is recorded.');
end $function$;

comment on function perf_cycle_extend(uuid, uuid, date, text) is
  'Moves a cycle''s assign_closes later, for HR, Business Excellence or an '
  'administrator, with a reason, audited. Only ever later, and never past '
  'entry_closes.';

-- ------------------------------------------------------------- the guard
do $guard$
declare
  p_boss uuid; p_rep uuid; p_adm uuid; p_hr uuid; p_plain uuid;
  v_cycle uuid; v_kpi uuid; v_a uuid; o jsonb; n int; v_was date;
begin
  -- A world of its own, rolled back at the end, so this proves the
  -- functions against real rows rather than against their own source.
  insert into person (full_name, work_email, app_role)
    values ('M246 Admin','m246.adm@example.invalid','ADMIN') returning id into p_adm;
  insert into person (full_name, work_email, app_role, department)
    values ('M246 HR','m246.hr@example.invalid','MANAGER','Human Resources')
    returning id into p_hr;
  insert into person (full_name, work_email, app_role)
    values ('M246 Boss','m246.boss@example.invalid','MANAGER') returning id into p_boss;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('M246 Rep','m246.rep@example.invalid','VIEWER', p_boss) returning id into p_rep;
  insert into person (full_name, work_email, app_role)
    values ('M246 Plain','m246.plain@example.invalid','VIEWER') returning id into p_plain;

  insert into perf_cycle (period_start, period_kind, assign_opens, assign_closes,
                          entry_closes, opened_by)
  values (date '2099-01-01','MONTH', date '2099-01-01', date '2099-01-08',
          date '2099-02-05', p_adm)
  returning id into v_cycle;

  insert into kpi_definition (name, unit, active, position)
    values ('M246 measure','COUNT', true, 1) returning id into v_kpi;

  -- ------------------------------------------------ taking one back
  o := perf_assign(p_boss, jsonb_build_object('cycleId', v_cycle,
         'personId', p_rep, 'kpiId', v_kpi, 'target', 10));
  v_a := (o->>'assignmentId')::uuid;
  if v_a is null then
    v_a := (select id from perf_assignment
             where cycle_id = v_cycle and person_id = p_rep limit 1);
  end if;
  if v_a is null then
    raise exception 'Migration 246: the guard could not give a measure to '
                    'check taking one back. perf_assign said %', o;
  end if;

  -- Nobody takes their own measure back.
  if coalesce((perf_assign_remove(p_rep, v_a)->>'ok')::boolean, false) then
    raise exception 'Migration 246: a person took their own measure back.';
  end if;

  o := perf_assign_remove(p_boss, v_a);
  if not coalesce((o->>'ok')::boolean, false) then
    raise exception 'Migration 246: the manager could not take the measure '
                    'back: %', o;
  end if;
  if (select state from perf_assignment where id = v_a) <> 'WITHDRAWN' then
    raise exception 'Migration 246: the measure was not withdrawn.';
  end if;
  if not exists (select 1 from perf_assignment where id = v_a) then
    raise exception 'Migration 246: the measure was deleted. It is meant to '
                    'stay as the evidence it was asked for.';
  end if;

  -- And the same measure can be given again, which is what narrowing the
  -- index was for.
  o := perf_assign(p_boss, jsonb_build_object('cycleId', v_cycle,
         'personId', p_rep, 'kpiId', v_kpi, 'target', 12));
  if o->>'error' is not null then
    raise exception 'Migration 246: a withdrawn measure still blocks giving '
                    'the same one again: %', o;
  end if;
  raise notice 'a measure can be taken back, stays as evidence, and can be given again';

  -- ------------------------------------------------ reopening the month
  update perf_cycle set assign_closes = current_date - 1 where id = v_cycle;

  -- Shut: the manager is refused and told why.
  o := perf_assign(p_boss, jsonb_build_object('cycleId', v_cycle,
         'personId', p_rep, 'kpiId', null, 'name','M246 late','unit','COUNT'));
  if o->>'error' is distinct from 'window_closed' then
    raise exception 'Migration 246: with the window shut, perf_assign said % '
                    'rather than window_closed.', o;
  end if;

  -- An ordinary person may not reopen it.
  if coalesce((perf_cycle_extend(p_plain, v_cycle, current_date + 7, 'because')->>'ok')::boolean, false) then
    raise exception 'Migration 246: an ordinary person reopened a month.';
  end if;
  -- Nor may anybody without a reason.
  if perf_cycle_extend(p_hr, v_cycle, current_date + 7, '  ')->>'error'
     is distinct from 'reason_required' then
    raise exception 'Migration 246: a month was reopened with no reason.';
  end if;
  -- Nor backwards, nor past the day filing closes.
  if perf_cycle_extend(p_hr, v_cycle, current_date - 2, 'x')->>'error'
     is distinct from 'already_past' then
    raise exception 'Migration 246: a month was reopened into the past.';
  end if;
  if perf_cycle_extend(p_hr, v_cycle, date '2099-03-01', 'x')->>'error'
     is distinct from 'after_filing_closes' then
    raise exception 'Migration 246: a month was reopened past filing.';
  end if;

  -- HR may, with a reason.
  v_was := (select assign_closes from perf_cycle where id = v_cycle);
  o := perf_cycle_extend(p_hr, v_cycle, current_date + 7,
         'The team were still being given managers.');
  if not coalesce((o->>'ok')::boolean, false) then
    raise exception 'Migration 246: HR could not reopen the month: %', o;
  end if;
  if (select assign_closes from perf_cycle where id = v_cycle) <> current_date + 7 then
    raise exception 'Migration 246: the month says it reopened and the date '
                    'did not move.';
  end if;
  if not exists (select 1 from audit_entry
                  where action = 'PERF_CYCLE_EXTENDED' and entity_ref = v_cycle::text) then
    raise exception 'Migration 246: reopening the month wrote no audit row.';
  end if;

  -- And now the manager can set a KPI again. This is the whole point.
  o := perf_assign(p_boss, jsonb_build_object('cycleId', v_cycle,
         'personId', p_rep, 'kpiId', null, 'name','M246 after','unit','COUNT'));
  if o->>'error' is not null then
    raise exception 'Migration 246: the month was reopened and the manager '
                    'still cannot set a KPI: %', o;
  end if;
  raise notice 'a shut month can be reopened by HR, with a reason, and the '
               'manager can set KPIs again';

  raise exception using errcode = 'P0001', message = 'M246 guard: undo';
exception
  when sqlstate 'P0001' then
    if sqlerrm <> 'M246 guard: undo' then raise; end if;
    raise notice 'migration 246 checked itself against real rows and rolled them back';
end $guard$;
