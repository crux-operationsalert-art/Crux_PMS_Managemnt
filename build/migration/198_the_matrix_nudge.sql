-- "the escalation matrix which is to be sent to the clients everymonth"
--
-- 196 made sending possible and recorded. This is the every-month part: a
-- nudge to the person whose coverage it is, on the fifth working day, naming
-- the clients that have not had this month's pack and the branches that are
-- holding it up.
--
-- Once a month, not once a day. A matrix that goes out on the 6th instead of
-- the 5th is late; a mailbox with twenty identical nudges in it is ignored,
-- and then the matrix goes out on the 20th.
--
-- Depends on 196.

create or replace function public.matrix_nudge_sweep(p_on date default current_date)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_run uuid; r record; m jsonb; c jsonb; late text; n_late int;
  body text; n int := 0; v_period date;
begin
  insert into job_run (job_key, started_at, state)
  values ('MATRIX_NUDGE', now(), 'RUNNING') returning id into v_run;

  v_period := date_trunc('month', p_on)::date;

  for r in
    select p.id, p.full_name, lower(btrim(p.work_email)) as email
      from person p
     where p.employment_status = 'ACTIVE' and p.superseded_by is null
       and coalesce(btrim(p.work_email), '') <> ''
       and exists (select 1 from coverage_rule cr
                    where cr.person_id = p.id
                      and (cr.effective_to is null or cr.effective_to >= p_on))
  loop
    m := matrix_month(r.id, p_on);
    if not coalesce((m->>'maySend')::boolean, false) then continue; end if;

    late := ''; n_late := 0;
    for c in select jsonb_array_elements(m->'clients') loop
      if c->>'sentAt' is null then
        n_late := n_late + 1;
        late := late || '  - ' || (c->>'name')
             || ' -- ' || (c->>'ready') || ' of ' || (c->>'branches') || ' branches ready'
             || case when coalesce((c->>'incomplete')::int, 0) > 0
                     then ', ' || (c->>'incomplete') || ' still missing a level'
                     else '' end
             || case when coalesce((c->>'recipients')::int, 0) = 0
                     then ', and no contacts on file to send it to'
                     else '' end
             || E'\n';
      end if;
    end loop;

    if n_late = 0 then continue; end if;

    body := 'Good morning ' || split_part(r.full_name, ' ', 1) || E',\n\n'
         || n_late || ' client(s) have not had the escalation matrix for '
         || to_char(v_period, 'FMMonth YYYY') || E':\n\n'
         || late || E'\n'
         || 'A branch with a blank level is held back and named in the letter rather '
         || 'than sent with a gap, so a client with an incomplete branch can still be '
         || 'sent what is ready.' || E'\n\n'
         || 'Open Escalation matrix in Crux.' || E'\n';

    insert into outbox (idempotency_key, template_key, recipient, subject, body,
                        entity_type, entity_id, not_before, state)
    values (md5('MATRIX_NUDGE|' || r.email || '|' || v_period), 'MATRIX_NUDGE', r.email,
            'Escalation matrix for ' || to_char(v_period, 'FMMonth YYYY')
              || ' has not gone out',
            body, 'person', r.id, now(), 'QUEUED')
    on conflict (idempotency_key) do nothing;
    n := n + 1;
  end loop;

  update job_run set finished_at = now(), state = 'DONE',
         counts = jsonb_build_object('day', p_on, 'period', v_period, 'nudges', n)
   where id = v_run;

  return jsonb_build_object('period', v_period, 'nudges', n,
    'note', case when n = 0
      then 'Every client covered by somebody has had this month''s matrix, so nobody was written to.'
      else n || ' person(s) reminded.' end);
exception when others then
  update job_run set finished_at = now(), state = 'FAILED', error = sqlerrm where id = v_run;
  raise;
end $fn$;

insert into job_config (job_key, enabled, cron, reason)
values ('MATRIX_NUDGE', true, '30 4 * * *',
        'On the fifth working day of the month, names the clients that have not '
        || 'had this month''s escalation matrix to whoever covers them. The tick '
        || 'runs daily and the sweep decides; the idempotency key is the month, '
        || 'so nobody is nudged twice.')
on conflict (job_key) do nothing;

-- The tick runs every morning and the sweep decides whether this is the day.
-- Putting "the fifth working day" in a cron expression is not possible, and
-- putting it in a comment is how it stops being true.
create or replace function public.crux_matrix_nudge_tick()
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare d date := date_trunc('month', current_date)::date; n int := 0;
begin
  if not coalesce((select enabled from job_config where job_key='MATRIX_NUDGE'), false) then
    return jsonb_build_object('skipped', 'MATRIX_NUDGE is switched off.');
  end if;
  -- count working days from the first of the month up to today, nationally
  while d < current_date loop
    if is_working_day(d, null) then n := n + 1; end if;
    d := d + 1;
  end loop;
  if not is_working_day(current_date, null) then
    return jsonb_build_object('skipped', 'Not a working day.');
  end if;
  if n <> 4 then
    return jsonb_build_object('skipped',
      'Today is working day ' || (n + 1) || ' of the month; the nudge goes on the fifth.');
  end if;
  return matrix_nudge_sweep();
end $fn$;

select cron.schedule('crux-matrix-nudge', '30 4 * * *',
                     'select crux_matrix_nudge_tick()');

revoke all on function public.matrix_nudge_sweep(date) from public, anon, authenticated;
revoke all on function public.crux_matrix_nudge_tick() from public, anon, authenticated;
