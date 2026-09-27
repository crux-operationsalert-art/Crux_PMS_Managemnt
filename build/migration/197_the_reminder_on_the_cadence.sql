-- "I get reminder based on when I should be updating it."
--
-- The model already knew what was owed from whom and on which day --
-- perf_due() reads the cadence off the assignment. What nothing did was tell
-- anybody. A cadence that only the database can see is a rule the person it
-- applies to has never been told.
--
-- Two reminders, both swept once a morning:
--
--   PERF_DUE    to the person, listing what they owe today and nothing else.
--   PERF_UNSET  to the manager, while the setting window is still open,
--               naming the people who have been given nothing for the month.
--
-- The second one exists because the first is useless without it. A person
-- with no KPI gets no reminder, files nothing, and scores nothing, and the
-- first anybody hears of it is at the end of the month.

-- -------------------------------------------------- the clock, applied
--
-- perf_due() as first written treated DAILY as "every day" and a day of the
-- month as that date whatever it fell on. The tool has one clock -- Sunday
-- off, Saturday as the working week says, and a confirmed holiday where the
-- person actually is -- and this is it, applied to the cadence.
--
-- A nominal day that is not a working day ROLLS FORWARD rather than being
-- skipped. The 10th falling on a Sunday does not mean that month's number is
-- not owed; it means it is owed on the Monday.
create or replace function public.perf_roll_forward(p_day date, p_centre text)
returns date language plpgsql stable security definer
set search_path to 'public' as $fn$
declare d date := p_day; n int := 0;
begin
  while n < 10 and not is_working_day(d, p_centre) loop
    d := d + 1; n := n + 1;
  end loop;
  return d;
end $fn$;

create or replace function public.perf_due(p_person uuid, p_on date default current_date)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare
  out jsonb := '[]'::jsonb; r record; cad text; due boolean;
  centre text; nominal date; eff date;
begin
  centre := person_centre(p_person);
  -- Nothing is owed on a day nobody is working. A reminder on a holiday is
  -- not diligence; it is noise that teaches people to ignore the next one.
  if not is_working_day(p_on, centre) then return out; end if;

  -- A split is filed against, so a split needs a rhythm, and it is the
  -- rhythm of the measure it splits unless somebody gave it its own. Without
  -- this a measure split by client -- which is the ordinary case, and the
  -- one the owner asked for by name -- falls to the default of month end and
  -- nobody is reminded of it for four weeks.
  for r in
    select a.id, a.name, a.unit, a.target_value,
           coalesce(a.cadence, par.cadence)::text as cadence,
           coalesce(a.cadence_day, par.cadence_day) as cadence_day,
           a.split_label, c.period_start, c.entry_closes,
           (select max(e.as_of) from perf_entry e where e.assignment_id = a.id) as last_filed
      from perf_assignment a
      join perf_cycle c on c.id = a.cycle_id
      left join perf_assignment par on par.id = a.part_of_id
     where a.person_id = p_person
       and a.state in ('ISSUED','ACKNOWLEDGED')
       and p_on between c.period_start and c.entry_closes
       and not exists (select 1 from perf_assignment x where x.part_of_id = a.id)
  loop
    cad := upper(coalesce(r.cadence, 'MONTH_END'));

    if cad like 'DAIL%' then
      due := true;                                  -- every working day
    elsif cad like 'WEEK%' then
      -- the named weekday of the week p_on is in, rolled forward
      nominal := p_on - (extract(isodow from p_on)::int - coalesce(r.cadence_day, 5));
      eff := perf_roll_forward(nominal, centre);
      due := p_on = eff;
    elsif cad like '%DAY%' or cad like '%DATE%' then
      nominal := least(
        date_trunc('month', p_on)::date + (coalesce(r.cadence_day, 10) - 1),
        (date_trunc('month', p_on) + interval '1 month')::date - 1);
      eff := perf_roll_forward(nominal, centre);
      due := p_on = eff;
    else
      due := p_on = r.entry_closes;                 -- month end
    end if;

    if due then
      out := out || jsonb_build_object(
        'assignmentId', r.id, 'name', r.name,
        'split', r.split_label, 'unit', r.unit, 'target', r.target_value,
        'cadence', r.cadence, 'lastFiled', r.last_filed,
        'alreadyFiled', exists (select 1 from perf_entry e
                                 where e.assignment_id = r.id and e.as_of = p_on));
    end if;
  end loop;
  return out;
end $fn$;

-- ------------------------------------------------------------- the sweep
create or replace function public.perf_reminder_sweep(p_on date default current_date)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_run uuid; r record; due jsonb; item jsonb; lines text; body text;
  n_due int := 0; n_unset int := 0; n_skip int := 0; c perf_cycle;
begin
  insert into job_run (job_key, started_at, state)
  values ('PERF_REMINDERS', now(), 'RUNNING') returning id into v_run;

  -- what is owed today, to the person it is owed by
  for r in
    select p.id, p.full_name, lower(btrim(p.work_email)) as email
      from person p
     where p.employment_status = 'ACTIVE' and p.superseded_by is null
       and coalesce(btrim(p.work_email), '') <> ''
  loop
    due := perf_due(r.id, p_on);
    lines := '';
    for item in select jsonb_array_elements(due) loop
      if not coalesce((item->>'alreadyFiled')::boolean, false) then
        lines := lines || '  - ' || (item->>'name')
              || case when coalesce(item->>'split','') <> ''
                      then ' (' || (item->>'split') || ')' else '' end
              || case when coalesce(item->>'target','') <> ''
                      then ', target ' || (item->>'target')
                           || coalesce(' ' || (item->>'unit'), '') else '' end
              || E'\n';
      end if;
    end loop;

    if lines = '' then n_skip := n_skip + 1; continue; end if;

    body := 'Good morning ' || split_part(r.full_name, ' ', 1) || E',\n\n'
         || 'These are due from you today, ' || to_char(p_on, 'FMDD FMMonth YYYY') || E':\n\n'
         || lines || E'\n'
         || 'Open Performance in Crux and file them. The number is for today -- '
         || 'filing it tomorrow does not make it tomorrow''s number.' || E'\n';

    insert into outbox (idempotency_key, template_key, recipient, subject, body,
                        entity_type, entity_id, not_before, state)
    values (md5('PERF_DUE|' || r.email || '|' || p_on), 'PERF_DUE', r.email,
            'Due today in Crux', body, 'person', r.id, now(), 'QUEUED')
    on conflict (idempotency_key) do nothing;
    n_due := n_due + 1;
  end loop;

  -- and, while the window is open, the people nobody has set anything for
  select * into c from perf_cycle
   where period_kind = 'MONTH' and period_start = date_trunc('month', p_on)::date;

  if c.id is not null and p_on <= c.assign_closes then
    for r in
      select m.id, m.full_name, lower(btrim(m.work_email)) as email,
             string_agg('  - ' || t.full_name, E'\n' order by t.full_name) as who,
             count(*) as n
        from person m
        join person t on t.manager_id = m.id
       where m.employment_status = 'ACTIVE' and m.superseded_by is null
         and coalesce(btrim(m.work_email), '') <> ''
         and t.employment_status = 'ACTIVE' and t.superseded_by is null
         and not exists (select 1 from perf_assignment a
                          where a.person_id = t.id and a.cycle_id = c.id)
       group by m.id, m.full_name, m.work_email
    loop
      body := 'Good morning ' || split_part(r.full_name, ' ', 1) || E',\n\n'
           || r.n || ' of your team have no KPI for '
           || to_char(c.period_start, 'FMMonth YYYY') || E' yet:\n\n'
           || r.who || E'\n\n'
           || 'The window closes on ' || to_char(c.assign_closes, 'FMDD FMMonth')
           || '. After that an administrator can still change them, and it is recorded.'
           || E'\n\nOpen Performance in Crux, then My team.\n';

      insert into outbox (idempotency_key, template_key, recipient, subject, body,
                          entity_type, entity_id, not_before, state)
      values (md5('PERF_UNSET|' || r.email || '|' || c.period_start), 'PERF_UNSET', r.email,
              'KPIs not set for ' || to_char(c.period_start, 'FMMonth YYYY'),
              body, 'person', r.id, now(), 'QUEUED')
      on conflict (idempotency_key) do nothing;
      n_unset := n_unset + 1;
    end loop;
  end if;

  update job_run set finished_at = now(), state = 'DONE',
         counts = jsonb_build_object('day', p_on, 'due_reminders', n_due,
                                     'unset_reminders', n_unset,
                                     'nothing_owed', n_skip,
                                     'cycle', c.id)
   where id = v_run;

  return jsonb_build_object('day', p_on, 'due', n_due, 'unset', n_unset,
    'note', case when n_due = 0 and n_unset = 0
      then 'Nothing was owed by anybody today, so nobody was written to.'
      else n_due || ' filing reminder(s) and ' || n_unset || ' setting reminder(s) queued.' end);
exception when others then
  update job_run set finished_at = now(), state = 'FAILED', error = sqlerrm where id = v_run;
  raise;
end $fn$;

insert into job_config (job_key, enabled, cron, reason)
values ('PERF_REMINDERS', true, '0 4 * * *',
        'Queues what is due today to the person who owes it, and -- while the '
        || 'setting window is open -- the unset team to their manager.')
on conflict (job_key) do nothing;

create or replace function public.crux_perf_reminder_tick()
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
begin
  if not coalesce((select enabled from job_config where job_key='PERF_REMINDERS'), false) then
    return jsonb_build_object('skipped', 'PERF_REMINDERS is switched off.');
  end if;
  return perf_reminder_sweep();
end $fn$;

-- 04:00 UTC is 09:30 in India: before the working day rather than during it.
select cron.schedule('crux-perf-reminders', '0 4 * * *',
                     'select crux_perf_reminder_tick()');

revoke all on function public.perf_roll_forward(date, text) from public, anon, authenticated;
revoke all on function public.perf_due(uuid, date) from public, anon, authenticated;
revoke all on function public.perf_reminder_sweep(date) from public, anon, authenticated;
revoke all on function public.crux_perf_reminder_tick() from public, anon, authenticated;
