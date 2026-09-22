-- =====================================================================
-- 115 · The penalty engine: the seven rules, and the sweep that fires them
--
-- Applied as migrations penalty_rules_and_the_sweep_that_fires_them,
-- a_branch_can_carry_the_day_it_opened, ul_date_reads_a_date_or_says_it_cannot
-- and ul_date_also_reads_a_month_spelt_out, 2026-09-18.
--
-- "Consequence is data" is one of the three things this rebuild is for, and
-- penalty_rule had been empty since it was created. The seven rules the
-- owner settled are seeded here.
--
-- Every one of them ships INACTIVE. A penalty engine switched on against a
-- half-loaded database would charge six hundred people for not filing a
-- daily count that the tool has never asked them for. Switching them on is
-- the owner's decision, made when the masters are in - which is also when
-- the amounts are known.
--
-- The nightly job itself ships ON, which is not a contradiction: the rule
-- carries the decision, not the schedule. A sweep with no active rule runs
-- every night and charges nothing, and it is visible in the jobs list from
-- the start rather than appearing out of nowhere the day someone needs it.
-- =====================================================================

-- --------------------------------------------------- a real duplicate guard
-- penalty_no_duplicate was a unique constraint on
-- (rule_id, person_id, occurred_on, entity_id). entity_id is null for any
-- rule that is not about a particular thing - P-01 among them - and in
-- Postgres two nulls are distinct by default, so it did not stop a second
-- charge for the same miss. It was a guarantee on paper only. Proven: with
-- the index as it was, two sweeps over one day charged the same person
-- twice; with it as it is, the second sweep charges nothing.
alter table penalty_instance drop constraint if exists penalty_no_duplicate;
create unique index if not exists penalty_no_duplicate
  on penalty_instance (rule_id, person_id, occurred_on, entity_id)
  nulls not distinct;

-- --------------------------------------------------------- the seven rules
-- Only P-01 has a published amount (₹200). The rest are seeded at zero
-- rather than invented, and the line the screen shows says so.
insert into penalty_rule
  (code, what, plain_language, applies_to, applies_to_list, frequency,
   cutoff_spec, amount, recovered_by, active)
values
  ('P-01', 'Daily business count not filed',
   'Everyone files a daily count. Miss the 23:59 cutoff on a working day and '
   'this is charged once for that day. Weekly offs and confirmed holidays are '
   'not working days and are never charged.',
   'Everybody', '{Everybody}', 'DAILY', '23:59 on the day itself',
   200, 'HR', false),

  ('P-02', 'Escalation not acted on within its TAT',
   'An escalation that passes its turnaround time without an action from the '
   'person concerned. Withdrawing the escalation reverses it; a dispute holds '
   'it while HR decides. The amount has not been set, so it does not fire.',
   'Everybody', '{Everybody}', 'PER_EVENT', 'the TAT on the escalation itself',
   0, 'HR', false),

  ('P-03', 'KPI targets not set for the team',
   'A manager whose reportees start a month with no target set. Nobody sets '
   'their own target, so this is the manager''s. The amount has not been set, '
   'so it does not fire.',
   'Managers with reportees', '{Managers with reportees}', 'MONTHLY',
   'the first working day of the month', 0, 'HR', false),

  ('P-04', 'Appraisal not closed by the cutoff',
   'A manager whose appraisal window closes with someone below still unclosed. '
   'The amount has not been set, so it does not fire.',
   'Managers with reportees', '{Managers with reportees}', 'CYCLE',
   'the close of the appraisal window', 0, 'HR', false),

  ('P-05', 'Team details not kept current',
   'A manager whose team records are stale past the monthly cutoff. The amount '
   'has not been set, so it does not fire.',
   'Managers with reportees', '{Managers with reportees}', 'MONTHLY',
   'the last working day of the month', 0, 'HR', false),

  ('P-06', 'Escalation matrix incomplete after fourteen days',
   'A branch whose matrix is still short of five levels, each with a name and '
   'at least one way to reach them, fourteen days after the branch was opened. '
   'Charged once, on the day the fourteen days run out, to whoever covers that '
   'branch. Finance recovers this one by billing rather than payroll.',
   'Branch Managers', '{Branch Managers,Franchise Partners}', 'DAILY',
   'fourteen days after the branch opens', 0, 'FINANCE', false),

  ('P-07', 'Warning letter not acknowledged',
   'A letter that has been issued and not acknowledged by its deadline. The '
   'amount has not been set, so it does not fire.',
   'Everybody', '{Everybody}', 'PER_EVENT', 'the deadline on the letter',
   0, 'HR', false)
on conflict (code) do nothing;

-- ------------------------------------------------------------- the helpers
-- A matrix is complete when all five levels are there, each with a name and
-- at least one way to reach the person. That is the owner's definition, and
-- it is computed rather than stored so it can never go stale.
create or replace function matrix_complete(p_branch uuid)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $$
  select count(distinct level) = 5 from matrix_contact
   where branch_id = p_branch
     and level between 1 and 5
     and coalesce(btrim(name), '') <> ''
     and (coalesce(btrim(mobile), '') <> '' or coalesce(btrim(email), '') <> '')
$$;

-- Where a person is, for the purpose of a regional holiday. Their coverage
-- says it when it says it plainly - one city and no other. Anything less and
-- the answer is null, which means only national holidays count for them.
create or replace function person_centre(p_person uuid)
returns text
language sql
stable security definer
set search_path to 'public'
as $$
  select case when count(*) = 1 then min(city) end
  from (select distinct g.name as city
          from coverage_rule cr
          join branch b on b.id = cr.branch_id
          join geo_node g on g.id = b.geo_node_id
         where cr.person_id = p_person and g.level = 'CITY') q
$$;

-- A working day: not a Sunday, not a confirmed holiday where they are, and
-- Saturday only while the working week says so.
create or replace function is_working_day(p_day date, p_centre text default null)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $$
  select case
    when extract(isodow from p_day) = 7 then false
    when extract(isodow from p_day) = 6
      and lower(coalesce((select value from app_setting where key='sat'),'')) like 'no%'
      then false
    else not holiday_applies(p_day, p_centre)
  end
$$;

-- A date out of a spreadsheet, in the forms a spreadsheet actually produces.
-- The shape of the string decides which format it is, because to_date is
-- lenient and will read 01-04-2024 as YYYY-MM-DD without complaint, giving
-- year 1. Anything unreadable comes back null rather than throwing, so one
-- bad cell does not fail a file - the validator names it instead.
create or replace function ul_date(p text)
returns date
language plpgsql
immutable
as $function$
declare s text; d date;
begin
  s := btrim(coalesce(p, ''));
  if s = '' then return null; end if;
  -- a spreadsheet writes the separator three different ways
  s := replace(replace(s, '.', '-'), '/', '-');

  begin
    if s ~ '^\d{4}-\d{1,2}-\d{1,2}$' then
      d := to_date(s, 'YYYY-MM-DD');
    elsif s ~ '^\d{1,2}-\d{1,2}-\d{4}$' then
      -- day first: the form every Indian sheet writes
      d := to_date(s, 'DD-MM-YYYY');
    elsif s ~ '^\d{1,2}-[A-Za-z]{3,}-\d{4}$' then
      begin
        d := to_date(s, 'DD-Mon-YYYY');            -- 01-Apr-2024
      exception when others then
        d := to_date(s, 'DD-Month-YYYY');          -- 01-April-2024
      end;
    else
      return null;
    end if;
  exception when others then
    return null;
  end;

  -- to_date will invent a date out of nonsense rather than refuse it
  if d < date '1900-01-01' or d > current_date + 365 then return null; end if;
  return d;
end $function$;

comment on function ul_date(text) is
  'A spreadsheet date as YYYY-MM-DD, DD-MM-YYYY or DD-Mon-YYYY; null if it '
  'cannot be read, so the validator reports it rather than the load failing.';

-- ------------------------------------------ a branch can say when it opened
-- P-06 charges a branch whose matrix is still incomplete fourteen days after
-- it opened. Every one of the 1,413 branches had effective_from null, the
-- branch upload had no column for it, and the applier never set one - so the
-- rule could not have fired, before or after the load. The clock had nothing
-- to start from.
--
-- created_at was the tempting shortcut and is the wrong answer: it is when
-- the row was migrated, not when the branch opened, and charging somebody
-- fourteen days after a migration is charging them for our import.
insert into upload_column (kind, ord, name, example, rule) values
  ('Clients and branches', 8, 'opened_on', '01-04-2024',
   'Optional. The day the branch opened. Leave it blank if you do not know; '
   'the only thing that needs it is the fourteen-day matrix clock, which '
   'simply does not start for a branch with no opening date.')
on conflict do nothing;

-- uv_clients and ua_clients gained the opened_on column: the validator
-- refuses a date it cannot read or one in the future, and the applier writes
-- it to branch.effective_from, never overwriting a date already recorded
-- with a blank cell. Full definitions in the migration ledger under
-- a_branch_can_carry_the_day_it_opened.

-- -------------------------------------------------------------- the sweep
-- Nightly, for one day at a time, and safe to run again: every row it writes
-- is held by penalty_no_duplicate, so a second run over the same day adds
-- nothing. An inactive rule fires nothing at all. A rule that is on but
-- cannot fire for want of data says so, rather than reporting a clean zero
-- that reads like "nothing was wrong".
--
-- P-02 to P-05 and P-07 have no logic here yet. They are seeded so the rules
-- exist, are visible and can be edited; the sweep will grow to cover them
-- when their amounts and cutoffs are settled. It names the rules it actually
-- ran rather than implying it ran all seven.
create or replace function penalty_sweep(p_for_day date default (current_date - 1))
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_run uuid;
  r_daily penalty_rule;
  r_matrix penalty_rule;
  v_p01 int := 0; v_p06 int := 0;
  v_ran text[] := '{}';
  v_notes text[] := '{}';
begin
  insert into job_run (job_key, started_at, state)
  values ('PENALTY_SWEEP', now(), 'RUNNING') returning id into v_run;

  select * into r_daily  from penalty_rule where code = 'P-01' and active;
  select * into r_matrix from penalty_rule where code = 'P-06' and active;

  -- P-01 - no daily count on a working day
  if r_daily.id is not null then
    v_ran := array_append(v_ran, 'P-01');
    if not exists (select 1 from kpi_definition where active) then
      v_notes := array_append(v_notes,
        'P-01 is on, but no KPI is defined for anybody, so nobody is expected '
        'to file a daily count yet and nobody was charged.');
    end if;
    insert into penalty_instance
      (rule_id, person_id, period, occurred_on, cutoff_missed, evidence,
       amount, recovered_by)
    select r_daily.id, p.id, to_char(p_for_day, 'YYYY-MM'), p_for_day,
           '23:59 on ' || to_char(p_for_day, 'DD Mon YYYY'),
           'No daily count filed for ' || to_char(p_for_day, 'DD Mon YYYY') || '.',
           r_daily.amount, penalty_recovery_for(p.id, r_daily.id)
      from person p
     where p.superseded_by is null
       and p.employment_status = 'ACTIVE'
       and exists (select 1 from chair_holder h
                    where h.person_id = p.id and h.to_date is null)
       and exists (select 1 from kpi_definition k
                    where k.person_id = p.id and k.active)
       and is_working_day(p_for_day, person_centre(p.id))
       and not exists (select 1 from daily_count d
                        where d.person_id = p.id and d.count_date = p_for_day)
    on conflict do nothing;
    get diagnostics v_p01 = row_count;
  end if;

  -- P-06 - the matrix clock runs out.
  -- Charged on the day it runs out, not every day after, so the branch is
  -- charged once and re-running the sweep changes nothing.
  if r_matrix.id is not null then
    v_ran := array_append(v_ran, 'P-06');
    if not exists (select 1 from branch where effective_from is not null) then
      v_notes := array_append(v_notes,
        'P-06 is on, but no branch carries an opening date, so the fourteen-day '
        'clock has nothing to start from. Fill opened_on in the Clients and '
        'branches upload for the rule to do anything.');
    end if;
    insert into penalty_instance
      (rule_id, person_id, period, occurred_on, cutoff_missed, evidence,
       entity_type, entity_id, amount, recovered_by)
    select distinct on (b.id)
           r_matrix.id, cr.person_id, to_char(p_for_day, 'YYYY-MM'), p_for_day,
           'Fourteen days from ' || to_char(b.effective_from, 'DD Mon YYYY'),
           'Branch ' || coalesce(b.code, b.name) || ' still has fewer than five '
             || 'complete matrix levels fourteen days after opening.',
           'branch', b.id, r_matrix.amount,
           penalty_recovery_for(cr.person_id, r_matrix.id)
      from branch b
      join coverage_rule cr on cr.branch_id = b.id
     where b.status = 'ACTIVE'
       and b.effective_from = p_for_day - 14
       and not matrix_complete(b.id)
       and (cr.effective_to is null or cr.effective_to >= p_for_day)
     order by b.id, cr.is_assigned_handler desc nulls last, cr.effective_from desc
    on conflict do nothing;
    get diagnostics v_p06 = row_count;
  end if;

  if v_ran = '{}' then
    v_notes := array_append(v_notes, 'No penalty rule is active, so nothing was charged.');
  end if;

  update job_run set finished_at = now(), state = 'DONE',
         counts = jsonb_build_object('day', p_for_day, 'P-01', v_p01, 'P-06', v_p06,
                                     'rules_run', to_jsonb(v_ran),
                                     'notes', to_jsonb(v_notes))
   where id = v_run;

  return jsonb_build_object('day', p_for_day, 'P-01', v_p01, 'P-06', v_p06,
    'rules_run', to_jsonb(v_ran), 'notes', to_jsonb(v_notes));
exception when others then
  update job_run set finished_at = now(), state = 'FAILED', error = sqlerrm where id = v_run;
  raise;
end $function$;

insert into job_config (job_key, enabled, cron)
values ('PENALTY_SWEEP', true, '30 1 * * *')
on conflict (job_key) do nothing;

create or replace function crux_penalty_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not coalesce((select enabled from job_config where job_key='PENALTY_SWEEP'), false) then
    return jsonb_build_object('skipped', 'PENALTY_SWEEP is switched off.');
  end if;
  return penalty_sweep();
end $function$;

select cron.schedule('crux-penalty', '30 1 * * *', 'select crux_penalty_tick()');

revoke all on function matrix_complete(uuid) from public, anon, authenticated;
revoke all on function person_centre(uuid) from public, anon, authenticated;
revoke all on function is_working_day(date,text) from public, anon, authenticated;
revoke all on function ul_date(text) from public, anon, authenticated;
revoke all on function penalty_sweep(date) from public, anon, authenticated;
revoke all on function crux_penalty_tick() from public, anon, authenticated;
