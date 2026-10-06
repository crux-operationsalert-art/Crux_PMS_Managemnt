-- A person is told what the tool is for (236)
--
-- This one writes to real people's inboxes, so the assertions are mostly
-- about REFUSING. The three that matter:
--
--   nothing is composed while app_url is unset, so nobody is ever sent a
--   link to nowhere;
--   the standing trigger never carries a password, whatever the one-off does;
--   the blast reaches people with a chair and not the five hundred client
--   contacts sitting in the same table.
--
-- Runs inside a transaction that is rolled back.

begin;

insert into app_setting (key, value, plain_language, group_name, editable_by)
values ('app_url', '', 'Where the published tool is served from.',
        'Mail and reminders', 'ADMIN')
on conflict (key) do nothing;

do $seed$
declare c_ex uuid; p_hr uuid; p_bm uuid; p_ex uuid; p_bank uuid; k uuid; cyc uuid;
begin
  insert into chair (code, title, level) values ('WC_E','Welcome exec','executive')
    returning id into c_ex;
  insert into kpi_definition (chair_id, name, unit, active, mandatory, position,
                              cadence, accrual)
    values (c_ex,'Cases completed','cases · WC1', true, true, 1,'DAILY','ADDS')
    returning id into k;

  insert into person (full_name, work_email, department, app_role)
    values ('WC HR','wc.hr@example.invalid','Human Resources','MANAGER')
    returning id into p_hr;
  insert into person (full_name, work_email) values ('WC Branch','wc.bm@example.invalid')
    returning id into p_bm;
  insert into person (full_name, work_email, manager_id)
    values ('WC Exec','wc.ex@example.invalid', p_bm) returning id into p_ex;
  -- Somebody in the person table who does NOT work here: no chair. This is
  -- what 531 of the rows in the live table actually are.
  insert into person (full_name, work_email)
    values ('WC Bank Contact','brmgr999@somebank.invalid') returning id into p_bank;

  insert into chair_holder (chair_id, person_id, is_primary)
    values (c_ex, p_ex, true);

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
  values (cyc, p_ex, k, 'Cases completed','cases · WC1', 300, 100,'DAILY',
          p_bm,'ISSUED','SEEDED');
end $seed$;

do $t$
declare
  p_hr uuid; p_bm uuid; p_ex uuid; p_bank uuid; p_new uuid;
  o jsonb; b text; n int;
begin
  select id into p_hr   from person where work_email='wc.hr@example.invalid';
  select id into p_bm   from person where work_email='wc.bm@example.invalid';
  select id into p_ex   from person where work_email='wc.ex@example.invalid';
  select id into p_bank from person where work_email='brmgr999@somebank.invalid';

  -- ================================ nothing at all while nobody said where
  update app_setting set value = '' where key = 'app_url';

  if person_welcome_body(p_ex) is null
    then raise notice 'PASS  with no app_url, no welcome is composed at all';
    else raise exception 'FAIL  a welcome was written with nowhere to point'; end if;

  o := person_welcome_send(p_hr, p_ex);
  if o->>'error' = 'no_app_url'
    then raise notice 'PASS  and sending one is refused, with the reason said plainly';
    else raise exception 'FAIL  a welcome was queued with no link: %',
      left(o::text,200); end if;

  o := person_welcome_all(p_hr);
  if o->>'error' = 'no_app_url'
    then raise notice 'PASS  so a blast to everybody cannot go out by accident';
    else raise exception 'FAIL  the blast ran with no link'; end if;

  -- ---- the trigger must be silent too, not raise: a welcome that cannot be
  -- ---- written is not a reason to refuse somebody a job
  insert into person (full_name, work_email)
  values ('WC Quiet','wc.quiet@example.invalid') returning id into p_new;
  if p_new is not null
    then raise notice 'PASS  and a person can still be created while it is unset';
    else raise exception 'FAIL  creating a person failed'; end if;

  select count(*) into n from outbox where recipient = 'wc.quiet@example.invalid';
  if n = 0
    then raise notice 'PASS  with nothing queued for them';
    else raise exception 'FAIL  % message(s) queued with no app_url', n; end if;

  -- ==================================== now somebody says where the tool is
  update app_setting set value = 'https://crux.example/app' where key = 'app_url';

  b := person_welcome_body(p_ex);
  if position('https://crux.example/app' in b) > 0
    then raise notice 'PASS  the link is in the message';
    else raise exception 'FAIL  no link in the body'; end if;

  if position('wc.ex@example.invalid' in b) > 0
    then raise notice 'PASS  and their user name is their work address, said as much';
    else raise exception 'FAIL  the address is not in the body'; end if;

  if position('Cases completed, target 300 cases' in b) > 0
    then raise notice 'PASS  what they file is named, with its target';
    else raise exception 'FAIL  the measure is missing: %', left(b, 400); end if;

  if position('every working day' in b) > 0
    then raise notice 'PASS  and how often it is owed';
    else raise exception 'FAIL  the cadence is missing'; end if;

  if position('WC1' in b) = 0
    then raise notice 'PASS  without the roll-up family code leaking into it';
    else raise exception 'FAIL  "WC1" reached a person''s inbox'; end if;

  if position('WC Branch' in b) > 0
    then raise notice 'PASS  it says who they report to';
    else raise exception 'FAIL  the manager is not named'; end if;

  -- ============================ the password is opt-in, every single time
  -- The rule is not "never says the word". The default copy says there is no
  -- separate password to remember, which is the right thing to tell somebody.
  -- The rule is that no credential is ever handed over.
  if position('Google button' in b) > 0 and position('Your password is' in b) = 0
    then raise notice 'PASS  by default it points at Google and hands over no credential';
    else raise exception 'FAIL  the default body hands over a password'; end if;

  b := person_welcome_body(p_ex, 'Your password is Crux@EXEC-2026.');
  if position('Crux@EXEC-2026' in b) > 0
    then raise notice 'PASS  and a caller who asks for one by name gets it';
    else raise exception 'FAIL  the supplied sign-in line was dropped'; end if;

  -- The standing trigger is the one that runs unattended for years.
  insert into person (full_name, work_email)
  values ('WC Joiner','wc.joiner@example.invalid') returning id into p_new;

  select body into b from outbox where recipient = 'wc.joiner@example.invalid';
  if b is not null
    then raise notice 'PASS  a new joiner is welcomed the moment they are created';
    else raise exception 'FAIL  no welcome was queued on insert'; end if;

  if position('Your password is' in b) = 0 and position('Crux@' in b) = 0
    then raise notice 'PASS  and the standing welcome hands over no credential, ever';
    else raise exception 'FAIL  the trigger put a password in an inbox'; end if;

  -- ================================== who the blast actually reaches
  delete from outbox where template_key = 'ACTIVATION';
  o := person_welcome_all(p_hr);

  select count(*) into n from outbox o2
   where o2.template_key = 'ACTIVATION' and o2.recipient = 'brmgr999@somebank.invalid';
  if n = 0
    then raise notice 'PASS  a client contact with no chair is not written to';
    else raise exception 'FAIL  the blast reached a bank contact'; end if;

  select count(*) into n from outbox o2
   where o2.template_key = 'ACTIVATION' and o2.recipient = 'wc.ex@example.invalid';
  if n = 1
    then raise notice 'PASS  and somebody holding a chair is';
    else raise exception 'FAIL  the seated person got % message(s)', n; end if;

  -- ------------------------------------------------- sending twice is once
  o := person_welcome_all(p_hr);
  select count(*) into n from outbox o2
   where o2.template_key = 'ACTIVATION' and o2.recipient = 'wc.ex@example.invalid';
  if n = 1
    then raise notice 'PASS  running the blast again does not send a second copy';
    else raise exception 'FAIL  a second copy went out'; end if;

  -- ======================================================== who may send
  o := person_welcome_send(p_ex, p_bm);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  a person does not welcome their own manager';
    else raise exception 'FAIL  anybody could send a welcome'; end if;

  o := person_welcome_all(p_bm);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  and writing to everybody is not a manager''s to do';
    else raise exception 'FAIL  a manager blasted the whole company'; end if;

  raise notice '--- the welcome: every assertion passed ---';
end $t$;

rollback;
