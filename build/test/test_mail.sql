-- A reminder that carries the way to act on it (235)
--
-- The assertion that matters most here is the one about ABSENCE. app_link
-- must return null while nobody has said where the tool is, because the
-- failure mode is not an error -- it is a hundred people receiving a link
-- that goes nowhere, on a schedule, every morning. Nothing would throw.
--
-- Runs inside a transaction that is rolled back.

begin;

-- Somebody who actually owes something today, because the assertions that
-- matter are about what lands in an inbox, and a test that skips those on an
-- empty database is a test that passes by not looking.
do $seed$
declare p_ex uuid; cyc uuid; k uuid; c_ex uuid;
begin
  insert into chair (code, title, level) values ('ML_E','Mail exec','executive')
    returning id into c_ex;
  insert into person (full_name, work_email)
    values ('ML Exec','ml.ex@example.invalid') returning id into p_ex;
  insert into kpi_definition (chair_id, name, unit, active, mandatory, position,
                              cadence, accrual)
    values (c_ex,'Days filed','% of working days filed · EX2', true, true, 1,
            'DAILY','REPLACES') returning id into k;

  -- A cycle that certainly contains today, whatever day this is run.
  insert into perf_cycle (period_start, assign_opens, assign_closes, entry_closes)
  values (date_trunc('month', current_date)::date,
          date_trunc('month', current_date)::date,
          date_trunc('month', current_date)::date + 9,
          (date_trunc('month', current_date) + interval '1 month - 1 day')::date)
  on conflict (period_start, period_kind) do update
     set assign_opens = excluded.assign_opens,
         assign_closes = excluded.assign_closes,
         entry_closes = excluded.entry_closes
  returning id into cyc;

  insert into perf_assignment (cycle_id, person_id, kpi_id, name, unit,
                               target_value, weight_pct, cadence, set_by,
                               state, target_source)
  values (cyc, p_ex, k, 'Days filed','% of working days filed · EX2', 90, 100,
          'DAILY', p_ex, 'ISSUED', 'SEEDED');
end $seed$;

-- The baseline carries the SCHEMA and not the data, so the app_url row that
-- migration 235 inserts is absent from a freshly rebuilt database. Every
-- `update app_setting` below would then touch nothing and app_link would read
-- null throughout. This test passed on a cluster where the migration had been
-- applied by hand and failed in the suite for exactly that reason, which is
-- the whole argument for running it against the baseline alone.
insert into app_setting (key, value, plain_language, group_name, editable_by)
values ('app_url', '', 'Where the published tool is served from.',
        'Mail and reminders', 'ADMIN')
on conflict (key) do nothing;

do $t$
declare o text; n int; v_body text; v_run jsonb; p_ex uuid;
begin
  select id into p_ex from person where work_email = 'ml.ex@example.invalid';
  -- ============================== no app_url means no link, not a bad one
  update app_setting set value = '' where key = 'app_url';

  if app_link('#perf') is null
    then raise notice 'PASS  with nowhere to point, a link is nothing rather than a bad link';
    else raise exception 'FAIL  app_link invented a link: %', app_link('#perf'); end if;

  if app_link() is null
    then raise notice 'PASS  and that is true of the bare link too';
    else raise exception 'FAIL  the bare link was invented'; end if;

  -- A composer that writes coalesce('Open: ' || app_link(...), '') must get
  -- nothing at all -- this is the idiom every one of them uses.
  if coalesce('Open Performance: ' || app_link('#perf'), '') = ''
    then raise notice 'PASS  so the sentence around it disappears with it';
    else raise exception 'FAIL  a half-written sentence survived'; end if;

  -- =========================================== once somebody says where
  update app_setting set value = 'https://example.invalid/crux/' where key = 'app_url';

  if app_link('#perf') = 'https://example.invalid/crux#perf'
    then raise notice 'PASS  a hash route joins on without a slash between';
    else raise exception 'FAIL  the hash link read %', app_link('#perf'); end if;

  if app_link() = 'https://example.invalid/crux'
    then raise notice 'PASS  and a trailing slash on the setting is not doubled';
    else raise exception 'FAIL  the bare link read %', app_link(); end if;

  if app_link('help.html') = 'https://example.invalid/crux/help.html'
    then raise notice 'PASS  a plain path gets the slash it needs';
    else raise exception 'FAIL  the path link read %', app_link('help.html'); end if;

  -- =================================== the family code a person never reads
  if perf_unit_plain('% of working days filed · EX2') = '% of working days filed'
    then raise notice 'PASS  the roll-up family code is stripped from a unit';
    else raise exception 'FAIL  the unit read %',
      perf_unit_plain('% of working days filed · EX2'); end if;

  if perf_unit_plain('cases') = 'cases'
    then raise notice 'PASS  and a unit that never had one is left alone';
    else raise exception 'FAIL  a plain unit was damaged'; end if;

  if perf_unit_plain('₹ lakh · A · D8') = '₹ lakh · A'
    then raise notice 'PASS  only the LAST code goes, as on the screen';
    else raise exception 'FAIL  two dots read %', perf_unit_plain('₹ lakh · A · D8'); end if;

  if perf_unit_plain(null) is null
    then raise notice 'PASS  and nothing in is nothing out';
    else raise exception 'FAIL  null became a string'; end if;

  -- ================================ what actually lands in somebody's inbox
  -- The sweep is run for real against a person who owes something, and the
  -- queued row is read. Asserting on the function's return would prove the
  -- function returned; asserting on the outbox proves the reminder.
  update app_setting set value = 'https://example.invalid/crux' where key = 'app_url';
  delete from outbox where template_key = 'PERF_DUE';

  v_run := perf_reminder_sweep(current_date);

  if (v_run->>'linked')::boolean
    then raise notice 'PASS  the run records that it had somewhere to point';
    else raise exception 'FAIL  the sweep did not know about app_url'; end if;

  -- The seeded person's own row, not "limit 1": an assertion about some
  -- other row is an assertion about nothing in particular.
  select body into v_body from outbox
   where template_key = 'PERF_DUE' and entity_id = p_ex;
  if v_body is null then
    raise exception 'FAIL  the person who owes something got no reminder at all';
  end if;

  if position('https://example.invalid/crux#perf' in v_body) > 0
    then raise notice 'PASS  and the reminder carries the link to act on it';
    else raise exception 'FAIL  a reminder went out with no link: %',
      left(v_body, 300); end if;

  if position(E'\n      File it: ' in v_body) > 0
    then raise notice 'PASS  on the activity''s own line, not only at the foot';
    else raise exception 'FAIL  the link is not against the activity'; end if;

  if position('Days filed' in v_body) > 0
    then raise notice 'PASS  the activity is named beside its link';
    else raise exception 'FAIL  the measure was not named'; end if;

  if position('90 % of working days filed' in v_body) > 0
    then raise notice 'PASS  the target reads in the unit a person uses';
    else raise exception 'FAIL  the target line read wrong: %', left(v_body, 300); end if;

  -- This is the defect the user actually saw, in the place they saw it.
  if position('EX2' in v_body) = 0
    then raise notice 'PASS  and the roll-up family code did NOT reach the inbox';
    else raise exception 'FAIL  "EX2" leaked into the e-mail body'; end if;

  -- ------------------------------ and with the setting cleared again
  update app_setting set value = '' where key = 'app_url';
  delete from outbox where template_key = 'PERF_DUE';
  v_run := perf_reminder_sweep(current_date);

  if not (v_run->>'linked')::boolean
    then raise notice 'PASS  clearing the setting stops the links, it does not break the mail';
    else raise exception 'FAIL  the sweep still thought it had a link'; end if;

  select count(*) into n from outbox
   where template_key = 'PERF_DUE' and body like '%File it:%';
  if n = 0
    then raise notice 'PASS  and no reminder carries the words with nothing after them';
    else raise exception 'FAIL  % reminder(s) say "File it:" and then stop', n; end if;

  raise notice '--- the reminder and its links: every assertion passed ---';
end $t$;

rollback;
