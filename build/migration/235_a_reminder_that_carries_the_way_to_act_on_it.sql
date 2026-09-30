-- A reminder that carries the way to act on it (235)
--
-- Applied live 2026-09-30 and verified by hashing each function against this
-- file, which is the only check worth making: an apply that returns success
-- is not evidence the database holds what the file says.
--
-- "The emails that have got triggered are good but should have hyperlinks in
-- front of the activities for them to action those."
--
-- They are right, and the fix has three parts, only one of which is the link.
--
-- ONE. There is nowhere in the database that says where the tool lives.
-- Every message ends "Open Performance in Crux" and leaves the reader to
-- find it. So this adds one setting, app_url, and one function, app_link.
--
-- The setting ships EMPTY on purpose, and app_link returns null while it is.
-- A reminder sent to a hundred people with a link that goes nowhere is worse
-- than the same reminder with no link at all: the second asks somebody to
-- open the tool, and the first tells them the tool is broken. So every
-- composer here asks for a link and writes the sentence without one when
-- there is none. The moment an administrator sets app_url every message
-- grows working links, with nothing redeployed.
--
-- TWO. The bodies leak a family code. A line in a live reminder reads
--
--     - Days filed, target 90 % of working days filed · EX2
--
-- and EX2 is not a unit. It is the code that tells the roll-up which
-- measures are the same quantity, and it belongs to the machinery, not to
-- the person reading their morning e-mail. The screen was fixed for this in
-- the same week; the e-mail was not, because it builds its own strings.
-- perf_unit_plain is the database's half of that fix, written once here so
-- there is not a third place to forget.
--
-- THREE. A URL in the text is not yet a hyperlink in the HTML twin, which
-- escapes the body and turns newlines into <br>. That half is in
-- build/supabase/functions/mail/index.ts, in the same change.
--
-- A link points at a SCREEN and never at a row. The tool is one page with
-- hash routes, and a person who followed a link to their own Performance
-- screen is where they needed to be; a deep link to one measure would be a
-- second addressing scheme to keep true.

-- ------------------------------------------------------ where the tool is
-- app_setting carries a sentence for every setting, which is the right
-- place for the one thing an administrator has to do to turn this on. It
-- ships EMPTY: nobody here can verify from inside the database which
-- address the published page actually answers on, and a guessed URL sent
-- to a hundred people every morning is worse than no URL at all.
insert into app_setting (key, value, plain_language, group_name, editable_by)
values ('app_url', '',
        'Where the published tool is served from, e.g. '
        'https://your-company.github.io/crux. Reminders put a link beside '
        'each thing a person has to do, and while this is blank they carry '
        'no links at all rather than links that go nowhere. Set it once and '
        'tomorrow morning''s reminders have working links.',
        'Mail and reminders', 'ADMIN')
on conflict (key) do nothing;

create or replace function app_link(p_path text default '')
returns text
language sql
stable security definer
set search_path to 'public'
as $function$
  -- Null, not an empty string, so a caller writing
  --   coalesce(' ' || app_link('#perf'), '')
  -- gets nothing at all rather than a trailing space and a bare hash.
  select case
    when coalesce(btrim(v.value), '') = '' then null
    else rtrim(btrim(v.value), '/') ||
         case when coalesce(p_path,'') = '' then ''
              when left(p_path, 1) in ('#','/') then p_path
              else '/' || p_path end
  end
  from (select value from app_setting where key = 'app_url') v;
$function$;

comment on function app_link(text) is
  'A link into the tool, or null when nobody has said where the tool is. '
  'Null is the whole point: a message with a link that goes nowhere is '
  'worse than the same message with no link.';

-- ------------------------------------------------- a unit a person can read
-- The mirror of pfUnit() on the screen. A unit may carry a family code after
-- a middle dot -- "% of working days filed · EX2" -- which the roll-up reads
-- and a person never should.
create or replace function perf_unit_plain(p_unit text)
returns text
language sql
immutable
as $function$
  select case
    when p_unit is null then null
    when position('·' in p_unit) = 0 then btrim(p_unit)
    else btrim(left(p_unit, length(p_unit) - position('·' in reverse(p_unit))))
  end;
$function$;

comment on function perf_unit_plain(text) is
  'A unit with its roll-up family code stripped: "cases · EX2" reads '
  '"cases". The code is machinery and belongs nowhere a person reads.';

-- =====================================================================
-- The daily reminder, with the way to act on it
-- =====================================================================
create or replace function perf_reminder_sweep(p_on date default current_date)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_run uuid; r record; due jsonb; item jsonb; lines text; body text;
  n_due int := 0; n_unset int := 0; n_skip int := 0; c perf_cycle;
  v_perf text; v_team text;
begin
  insert into job_run (job_key, started_at, state)
  values ('PERF_REMINDERS', now(), 'RUNNING') returning id into v_run;

  -- Asked once for the whole sweep rather than once per person: it is one
  -- setting and a hundred people, and it cannot change mid-sweep.
  v_perf := app_link('#perf');
  v_team := app_link('#people');

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
                           || coalesce(' ' || perf_unit_plain(item->>'unit'), '')
                      else '' end
              -- The link goes on the activity's own line, which is what
              -- "in front of the activities" asks for: a person scanning
              -- five lines can act on the third without reading the other
              -- four to find out where to go.
              || coalesce(E'\n      File it: ' || v_perf, '')
              || E'\n';
      end if;
    end loop;

    if lines = '' then n_skip := n_skip + 1; continue; end if;

    body := 'Good morning ' || split_part(r.full_name, ' ', 1) || E',\n\n'
         || 'These are due from you today, ' || to_char(p_on, 'FMDD FMMonth YYYY') || E':\n\n'
         || lines || E'\n'
         || coalesce('Open Performance: ' || v_perf || E'\n\n', '')
         || 'The number is for today -- filing it tomorrow does not make it '
         || 'tomorrow''s number.' || E'\n';

    insert into outbox (idempotency_key, template_key, recipient, subject, body,
                        entity_type, entity_id, not_before, state)
    values (md5('PERF_DUE|' || r.email || '|' || p_on), 'PERF_DUE', r.email,
            'Due today in Crux', body, 'person', r.id, now(), 'QUEUED')
    on conflict (idempotency_key) do nothing;
    n_due := n_due + 1;
  end loop;

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
           || E'\n\n'
           || coalesce('Set their targets: ' || v_team || E'\n',
                       E'Open Performance in Crux, then My team.\n');

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
                                     'cycle', c.id,
                                     -- Recorded per run, so "why did today's
                                     -- mail have no links" is answerable
                                     -- from the job row alone.
                                     'linked', v_perf is not null)
   where id = v_run;

  return jsonb_build_object('day', p_on, 'due', n_due, 'unset', n_unset,
    'linked', v_perf is not null,
    'note', case when n_due = 0 and n_unset = 0
      then 'Nothing was owed by anybody today, so nobody was written to.'
      else n_due || ' filing reminder(s) and ' || n_unset || ' setting reminder(s) queued.'
           || case when v_perf is null
                   then ' No app_url is set, so they carry no links -- set it and '
                        'tomorrow''s will.'
                   else '' end end);
exception when others then
  update job_run set finished_at = now(), state = 'FAILED', error = sqlerrm where id = v_run;
  raise;
end $function$;

comment on function perf_reminder_sweep(date) is
  'The daily filing reminder. Each activity carries the link to file it, '
  'when app_url is set; units are printed without their roll-up family code.';

-- =====================================================================
-- The matrix nudge, the same way
-- =====================================================================
create or replace function matrix_nudge_sweep(p_on date default current_date)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_run uuid; r record; m jsonb; c jsonb; late text; n_late int;
  body text; n int := 0; v_period date; v_link text;
begin
  insert into job_run (job_key, started_at, state)
  values ('MATRIX_NUDGE', now(), 'RUNNING') returning id into v_run;

  v_period := date_trunc('month', p_on)::date;
  v_link := app_link('#matrix');

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
             || coalesce(E'\n      Send it: ' || v_link, '')
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
         || coalesce('Open the escalation matrix: ' || v_link || E'\n',
                     E'Open Escalation matrix in Crux.\n');

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
         counts = jsonb_build_object('day', p_on, 'period', v_period, 'nudges', n,
                                     'linked', v_link is not null)
   where id = v_run;

  return jsonb_build_object('period', v_period, 'nudges', n,
    'linked', v_link is not null,
    'note', case when n = 0
      then 'Every client covered by somebody has had this month''s matrix, so nobody was written to.'
      else n || ' person(s) reminded.' end);
exception when others then
  update job_run set finished_at = now(), state = 'FAILED', error = sqlerrm where id = v_run;
  raise;
end $function$;

comment on function matrix_nudge_sweep(date) is
  'The monthly escalation-matrix nudge. Each client carries the link to '
  'send it, when app_url is set.';

-- ------------------------------------------------------------- the gate
revoke execute on function app_link(text) from public, anon, authenticated;
revoke execute on function perf_reminder_sweep(date) from public, anon, authenticated;
revoke execute on function matrix_nudge_sweep(date) from public, anon, authenticated;

do $guard$
declare v text; n int;
begin
  if not exists (select 1 from app_setting where key = 'app_url') then
    raise exception 'Migration 235 did not add the app_url setting';
  end if;

  -- app_link must be NULL while app_url is empty. If this ever returns a
  -- string, every reminder starts carrying a link to nowhere.
  if app_link('#perf') is not null
     and coalesce(btrim((select value from app_setting where key='app_url')),'') = '' then
    raise exception 'Migration 235: app_link returns a link with no app_url set';
  end if;

  -- The family code must not survive into anything a person reads.
  if perf_unit_plain('% of working days filed · EX2') <> '% of working days filed' then
    raise exception 'Migration 235: perf_unit_plain left the family code on, it read %',
      perf_unit_plain('% of working days filed · EX2');
  end if;
  if perf_unit_plain('cases') <> 'cases' then
    raise exception 'Migration 235: perf_unit_plain damaged a unit with no code';
  end if;

  select count(*) into n from pg_proc
   where proname in ('app_link','perf_unit_plain','perf_reminder_sweep',
                     'matrix_nudge_sweep');
  if n <> 4 then
    raise exception 'Migration 235 left % of 4 functions behind', n;
  end if;
end $guard$;
