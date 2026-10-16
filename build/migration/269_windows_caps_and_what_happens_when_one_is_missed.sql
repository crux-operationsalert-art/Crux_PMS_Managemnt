-- Windows, caps, and an escalation by e-mail when a window is missed
--
-- The owner, 16 Oct: "Wait for the month to end before scoring. Set windows
-- and caps. If missed should raise escalations with emails." The day's audit
-- had found plb_score_month taking a manager's October score on the 16th,
-- half the month unfiled. It also found nothing fencing the numbers: the
-- screen's min="0" max="10" was the only thing keeping a score out of ten,
-- the self-evaluation checked nothing at all (not even that the sheet
-- exists), and neither asked whether the month belonged to the sheet's own
-- quarter.
--
-- 1. A MONTH IS SCORED ONCE IT IS OVER -- from the 1st of the next month, by
--    the manager and in the self-evaluation alike. Refused in words before.
-- 2. CAPS. KPIs and attributes are each 0 to 10, in half steps (the steps
--    were already checked), and the month must be one of the sheet's three.
-- 3. THE REVIEW WINDOW. A month's review is due on the 5th working day after
--    it ends (plb_review_due; app_setting plb_review_days, so the owner can
--    move it). Scoring later is still allowed -- a late score is better than
--    none, and it is what clears the miss -- but the miss is raised.
--    The KPI-setting window is the cycle's own assign_closes, unchanged.
-- 4. A MISSED WINDOW IS ESCALATED AND E-MAILED. perf_window_sweep, daily at
--    05:15 UTC (10:45 IST), finds:
--      KPI_NOT_SET     a month's KPI window has closed and someone in the
--                      scheme (they hold a goal sheet for that quarter) has
--                      fewer than three measures, weights not making 100, or
--                      a measure with no target;
--      REVIEW_NOT_DONE a month's review is past due and their manager has
--                      not scored it.
--    One escalation per manager per window -- naming everybody it covers,
--    never one per report, or a manager with forty-two people receives
--    forty-two. It is raised ABOUT the manager who owed the work, through
--    person_escalation_raise, so it routes to their own manager with a
--    three-working-day clock, exactly as a person would raise it. The
--    manager is e-mailed, their manager copied, through the outbox; once
--    per window, whatever the sweep is run how many times (window_miss is
--    the record, unique on the window and the manager).
--    It starts from October 2026 (app_setting window_escalations_from):
--    September's reviews were seeded for the demo with one left unscored on
--    purpose, and the owner did not ask for a retrospective.
do $do$
declare src text; out_src text; v_args text;
  v_a text := $a$  if p_kpi * 2 <> floor(p_kpi * 2) or p_attr * 2 <> floor(p_attr * 2) then$a$;
  v_b text := $b$  -- 269: the caps, and the month must be over and the sheet's own.
  if p_kpi < 0 or p_kpi > 10 or p_attr < 0 or p_attr > 10 then
    return jsonb_build_object('error','out_of_range',
      'reason','KPIs and attributes are each scored from 0 to 10.');
  end if;
  if v_month < s.quarter or v_month >= (s.quarter + interval '3 months')::date then
    return jsonb_build_object('error','not_this_quarter',
      'reason', to_char(v_month, 'FMMonth YYYY') || ' is not one of this goal sheet''s months.');
  end if;
  if current_date < (v_month + interval '1 month')::date then
    return jsonb_build_object('error','month_not_over',
      'reason', to_char(v_month, 'FMMonth YYYY') || ' can be scored from '
             || to_char((v_month + interval '1 month')::date, 'FMDD FMMonth')
             || ', once it is over. Its review is due by '
             || to_char(plb_review_due(v_month), 'FMDD FMMonth') || '.');
  end if;
$b$;
  v_c text := $c$  insert into plb_month_score (sheet_id, month, self_kpi, self_attr, self_at)$c$;
  v_d text := $d$  -- 269: the same fences as the manager's score.
  if s.id is null then return jsonb_build_object('error','no_such_sheet'); end if;
  if p_kpi is null or p_attr is null or p_kpi < 0 or p_kpi > 10 or p_attr < 0 or p_attr > 10
     or p_kpi * 2 <> floor(p_kpi * 2) or p_attr * 2 <> floor(p_attr * 2) then
    return jsonb_build_object('error','out_of_range',
      'reason','Both halves, each from 0 to 10 in half steps.');
  end if;
  if date_trunc('month', p_month)::date < s.quarter
     or date_trunc('month', p_month)::date >= (s.quarter + interval '3 months')::date then
    return jsonb_build_object('error','not_this_quarter',
      'reason','That month is not one of this goal sheet''s.');
  end if;
  if current_date < (date_trunc('month', p_month) + interval '1 month')::date then
    return jsonb_build_object('error','month_not_over',
      'reason','A month is evaluated once it is over -- from '
             || to_char((date_trunc('month', p_month) + interval '1 month')::date, 'FMDD FMMonth') || '.');
  end if;
$d$;
begin
  -- the review window, first: plb_score_month's refusal names its date
  insert into app_setting (key, value, plain_language, group_name, editable_by)
  values ('plb_review_days', '5',
          'Working days after a month ends by which each manager scores it. A month not '
          || 'scored by then is escalated to their manager, with an e-mail.', 'Performance', 'ADMIN'),
         ('window_escalations_from', '2026-10-01',
          'The first month whose missed KPI or review windows are escalated.', 'Performance', 'ADMIN')
  on conflict (key) do nothing;
  execute $f$
    create or replace function public.plb_review_due(p_month date) returns date
    language sql stable set search_path to 'public' as $q$
      select plb_wd_after((date_trunc('month', p_month) + interval '1 month - 1 day')::date,
               coalesce(nullif(btrim((select value from app_setting where key = 'plb_review_days')), '')::int, 5))
    $q$ $f$;

  select prosrc, pg_get_function_arguments(p.oid) into src, v_args
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'plb_score_month';
  if position('269: the caps' in src) > 0 then
    raise notice 'Migration 269: plb_score_month already fenced.';
  elsif position(v_a in src) = 0 then
    raise exception 'Migration 269: plb_score_month''s half-step check is not where this expects it.';
  else
    execute format('create or replace function public.plb_score_month(%s) returns jsonb '
      'language plpgsql security definer set search_path to ''public'' as %L',
      v_args, replace(src, v_a, v_b || v_a));
  end if;

  select prosrc, pg_get_function_arguments(p.oid) into src, v_args
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'plb_self_eval';
  if position('269: the same fences' in src) > 0 then
    raise notice 'Migration 269: plb_self_eval already fenced.';
  elsif position(v_c in src) = 0 then
    raise exception 'Migration 269: plb_self_eval''s insert is not where this expects it.';
  else
    execute format('create or replace function public.plb_self_eval(%s) returns jsonb '
      'language plpgsql security definer set search_path to ''public'' as %L',
      v_args, replace(src, v_c, v_d || v_c));
  end if;
end
$do$;

create table if not exists window_miss (
  kind          text not null check (kind in ('KPI_NOT_SET','REVIEW_NOT_DONE')),
  period        date not null,
  manager_id    uuid not null references person(id),
  people        jsonb not null,
  escalation_id uuid references person_escalation(id),
  outbox_key    text,
  raised_at     timestamptz not null default now(),
  primary key (kind, period, manager_id)
);
comment on table window_miss is
  'One row per manager per missed window (269): who it covered, the escalation raised and the e-mail sent. The sweep raises nothing twice.';

create or replace function perf_window_sweep(p_on date default current_date)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_sys uuid := (select id from person where work_email = 'operations.alert@cruxindia.co.in');
  v_from date := coalesce(nullif(btrim((select value from app_setting where key = 'window_escalations_from')), '')::date,
                          date '2026-10-01');
  v_url text := (select value from app_setting where key = 'app_url');
  r record; o jsonb; v_key text; v_cc text; v_subj text; v_body text; v_mgr person; n int := 0;
begin
  for r in
    -- KPI_NOT_SET: the month's window has closed, and someone in the scheme
    -- (a goal sheet for that quarter) does not hold a complete scorecard.
    with gap as (
      select 'KPI_NOT_SET'::text kind, c.period_start period, c.assign_closes closed,
             p.manager_id, p.id person_id, p.full_name,
             case when x.n is null or x.n = 0 then 'no KPIs set'
                  when x.n < 3 then x.n || ' KPI(s), three are needed'
                  when abs(x.w - 100) > 0.1 then 'weights come to ' || round(x.w, 2) || '%'
                  else 'a KPI with no target' end why
        from perf_cycle c
        join plb_goal_sheet s on s.quarter = date_trunc('quarter', c.period_start)::date
        join person p on p.id = s.person_id
        left join lateral (select count(*) n, sum(coalesce(a.weight_pct, 0)) w,
                                  count(*) filter (where a.target_value is null) blank
                             from perf_assignment a
                            where a.cycle_id = c.id and a.person_id = p.id
                              and a.part_of_id is null and a.state <> 'WITHDRAWN') x on true
       where c.period_kind = 'MONTH' and c.period_start >= v_from and c.assign_closes < p_on
         and p.manager_id is not null and p.employment_status = 'ACTIVE' and p.superseded_by is null
         and (coalesce(x.n, 0) < 3 or abs(coalesce(x.w, 0) - 100) > 0.1 or coalesce(x.blank, 0) > 0)
      union all
      -- REVIEW_NOT_DONE: the month's review is past due and not scored.
      select 'REVIEW_NOT_DONE', mo.m, plb_review_due(mo.m), p.manager_id, p.id, p.full_name,
             'not scored' why
        from plb_goal_sheet s
        join person p on p.id = s.person_id
        cross join lateral (select (s.quarter + (k || ' months')::interval)::date m
                              from generate_series(0, 2) k) mo
       where mo.m >= v_from and plb_review_due(mo.m) < p_on and s.status <> 'DRAFT'
         and p.manager_id is not null and p.employment_status = 'ACTIVE' and p.superseded_by is null
         and not exists (select 1 from plb_month_score ms where ms.sheet_id = s.id
                          and ms.month = mo.m and ms.kpi_points is not null))
    select g.kind, g.period, min(g.closed) closed, g.manager_id,
           jsonb_agg(jsonb_build_object('id', g.person_id, 'name', g.full_name, 'why', g.why)
                     order by g.full_name) people
      from gap g
      join person m on m.id = g.manager_id
     where coalesce(m.employee_type, 'EMPLOYEE') not in ('SERVICE_ACCOUNT', 'CLIENT_CONTACT')
       and not exists (select 1 from window_miss w where w.kind = g.kind and w.period = g.period
                        and w.manager_id = g.manager_id)
     group by g.kind, g.period, g.manager_id
  loop
    select * into v_mgr from person where id = r.manager_id;
    v_subj := case r.kind
      when 'KPI_NOT_SET' then to_char(r.period, 'FMMonth YYYY') || ' KPIs not set for '
      else to_char(r.period, 'FMMonth YYYY') || ' monthly review not done for ' end
      || jsonb_array_length(r.people) || ' of your team';
    v_body := (select string_agg('  - ' || (x->>'name') || ': ' || (x->>'why'), E'\n')
                 from jsonb_array_elements(r.people) x);
    o := person_escalation_raise(v_sys, jsonb_build_object('personId', r.manager_id,
           'subject', v_subj, 'kind', 'PROCESS',
           'detail', case r.kind when 'KPI_NOT_SET'
                       then 'The window to set ' || to_char(r.period, 'FMMonth YYYY') || '''s KPIs closed on '
                            || to_char(r.closed, 'FMDD FMMonth') || '. Still not complete:'
                       else 'The review of ' || to_char(r.period, 'FMMonth YYYY') || ' was due by '
                            || to_char(r.closed, 'FMDD FMMonth') || '. Not yet scored:' end
                     || E'\n' || v_body));
    v_cc := (select work_email from person where id = nullif(o->>'routedTo', '')::uuid);
    v_key := 'WINDOW_MISS:' || r.kind || ':' || r.period || ':' || r.manager_id;
    if v_mgr.work_email is not null then
      insert into outbox (idempotency_key, template_key, entity_type, entity_id, recipient, cc_addr, subject, body)
      values (v_key, 'WINDOW_MISS', 'person', r.manager_id, v_mgr.work_email, v_cc,
        'Overdue: ' || v_subj,
        'Dear ' || initcap(split_part(regexp_replace(btrim(v_mgr.full_name), '[._]', ' ', 'g'), ' ', 1)) || ',' || E'\n\n' ||
        case r.kind when 'KPI_NOT_SET'
          then 'The window to set ' || to_char(r.period, 'FMMonth YYYY') || '''s KPIs for your team closed on '
               || to_char(r.closed, 'FMDD FMMonth') || ', and these scorecards are still not complete:'
          else 'The monthly review of ' || to_char(r.period, 'FMMonth YYYY') || ' was due by '
               || to_char(r.closed, 'FMDD FMMonth') || ', and these have not been scored yet:' end
        || E'\n' || v_body || E'\n\n' ||
        case when o->>'error' is null
          then 'This has been raised as an escalation with ' || coalesce(o->>'routedToName', 'your manager')
               || ', who has until ' || to_char((o->>'dueOn')::date, 'FMDD FMMonth') || ' to see it closed. '
          else '' end ||
        case r.kind when 'KPI_NOT_SET'
          then 'Set them under My team > Performance mapping; HR can reopen the month if it is shut.'
          else 'Score them under My team > the person > Monthly review and score. A late score still counts.' end
        || E'\n\n' || 'Open Crux: ' || coalesce(v_url, '') || E'\n\n' ||
        'Regards,' || E'\n' || 'Operations, Crux Risk Management Pvt Ltd')
      on conflict (idempotency_key) do nothing;
    end if;
    insert into window_miss (kind, period, manager_id, people, escalation_id, outbox_key)
    values (r.kind, r.period, r.manager_id, r.people, nullif(o->>'id', '')::uuid, v_key)
    on conflict do nothing;
    n := n + 1;
  end loop;
  return jsonb_build_object('raised', n, 'on', p_on);
end
$function$;

comment on function perf_window_sweep(date) is
  'Daily (269): every missed KPI-setting or monthly-review window since window_escalations_from becomes one escalation about the manager who owed it, routed to their manager, and one e-mail to them with their manager copied. Never twice.';

-- Daily at 05:15 UTC. Where pg_cron is not installed (the local proving
-- ground) the function is still there to be run by hand.
do $cron$
begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    perform cron.schedule('crux-window-escalations', '15 5 * * *', 'select perf_window_sweep(current_date)');
  end if;
end $cron$;
