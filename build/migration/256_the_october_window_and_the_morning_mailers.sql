-- Two operational changes the owner asked for on 7 October
--
-- Both were applied live before this file existed, which is the wrong way
-- round. They are written down here so that the live project can be rebuilt
-- from this repository and arrive at the same state -- an operational change
-- that exists only in somebody's memory of having made it is a change that
-- the next rebuild quietly undoes.
--
-- =====================================================================
-- 1. The October assign window runs to the 15th.
--
-- perf_cycle_open sets assign_closes five working days after the first, so
-- October's closed on the 8th. The owner asked for the 15th: the KPI and
-- target work for this month is still in hand, and a window that shuts
-- while the work is half done turns every control on the Performance
-- screen into one that is offered and refused.
--
-- Through perf_cycle_extend rather than an UPDATE, because that function is
-- the one that records who reopened it and why. A date changed behind its
-- back is a date nobody can account for.
-- =====================================================================
do $do$
declare v_admin uuid; v_cycle uuid; o jsonb;
begin
  select id into v_admin from person
   where employment_status = 'ACTIVE' and superseded_by is null
     and app_role = 'ADMIN'
     and coalesce(employee_type,'EMPLOYEE') not in ('SERVICE_ACCOUNT','CLIENT_CONTACT')
   limit 1;
  select id into v_cycle from perf_cycle
   where period_start = date '2026-10-01' and period_kind = 'MONTH';

  if v_admin is null or v_cycle is null then
    raise notice 'Migration 256: no October cycle or no staff administrator '
                 'here, so the window is left as it is.';
  elsif (select assign_closes from perf_cycle where id = v_cycle) >= date '2026-10-15' then
    raise notice 'Migration 256: the October window already runs to the 15th '
                 'or later.';
  else
    o := perf_cycle_extend(v_admin, v_cycle, date '2026-10-15',
           'The owner asked for the window to stay open to 15 October: the '
        || 'KPI and target work for this month is still in hand.');
    if o->>'error' is not null then
      raise exception 'Migration 256: the October window could not be '
                      'extended: %', o;
    end if;
    raise notice 'Migration 256: KPIs for October may be set until the 15th.';
  end if;
end
$do$;

-- =====================================================================
-- 2. The daily morning mailers are paused.
--
-- "pause the daily morning mailers as of now".
--
-- Two jobs generate them, and they are the two that put a row in the outbox
-- every morning without anybody asking:
--
--   crux-perf-reminders  04:00 UTC  PERF_DUE      606 since 30 September
--   crux-matrix-nudge    04:30 UTC  MATRIX_NUDGE
--
-- crux-mail is deliberately LEFT RUNNING. It is the sender, not a mailer:
-- pausing it would also stop activation codes, welcome messages and every
-- other piece of mail somebody is waiting on because they asked for it. The
-- instruction was to stop the daily morning post, not the post.
--
-- Paused rather than unscheduled, so turning them back on is one line and
-- the schedule they ran on is still written down.
-- =====================================================================
do $do$
declare n int := 0; r record;
begin
  if to_regclass('cron.job') is null then
    raise notice 'Migration 256: no pg_cron here, so there is nothing to pause.';
    return;
  end if;
  for r in select jobid, jobname from cron.job
            where jobname in ('crux-perf-reminders','crux-matrix-nudge')
              and active
  loop
    perform cron.alter_job(r.jobid, active := false);
    n := n + 1;
    raise notice 'Migration 256: % is paused.', r.jobname;
  end loop;
  if n = 0 then
    raise notice 'Migration 256: the morning mailers were already paused.';
  end if;

  -- The sender must still be running, and saying so here is cheaper than
  -- finding out from somebody who never got their activation code.
  if exists (select 1 from cron.job where jobname = 'crux-mail' and not active) then
    raise warning 'Migration 256: crux-mail is NOT running, so nothing is '
                  'being sent at all -- including activation codes. That is '
                  'not what pausing the morning mailers was meant to do.';
  end if;
end
$do$;

-- ------------------------------------------------------------- the guard
do $guard$
declare v_close date; v_on int;
begin
  select assign_closes into v_close from perf_cycle
   where period_start = date '2026-10-01' and period_kind = 'MONTH';
  if v_close is not null and v_close < date '2026-10-15' then
    raise exception 'Migration 256: the October window still shuts on %.', v_close;
  end if;

  if to_regclass('cron.job') is not null then
    select count(*) into v_on from cron.job
     where jobname in ('crux-perf-reminders','crux-matrix-nudge') and active;
    if v_on > 0 then
      raise exception 'Migration 256: % morning mailer(s) are still running.', v_on;
    end if;
  end if;

  raise notice 'October runs to the 15th, and the morning post is paused.';
end $guard$;
