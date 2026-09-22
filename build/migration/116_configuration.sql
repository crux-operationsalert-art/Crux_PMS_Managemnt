-- =====================================================================
-- 116 · Configuration — every setting, job and penalty rule, on a screen
--
-- Applied as migrations settings_tell_the_truth,
-- the_auto_close_window_is_a_setting_again, configuration_has_a_back_end,
-- config_read_grouping_fix, crux_app_page_configuration_styles_and_door and
-- crux_app_page_configuration_view, 2026-09-22.
--
-- Seventy-one settings, seven jobs and seven penalty rules had been
-- reachable only by somebody with database access. Before building a screen
-- onto them, every one was read against every function and every edge route
-- to find out what actually reads it. That found three kinds of lie, and
-- they are fixed first, because a Configuration screen built on settings
-- that do nothing is worse than no screen: it tells a person they are in
-- control when they are not.
-- =====================================================================

-- ------------------------------------------------- a setting that is not one
-- A setting nothing reads yet is not a bug - the decision is recorded - but
-- it must not look like a control.
alter table app_setting
  add column if not exists in_force boolean not null default true;

comment on column app_setting.in_force is
  'False when the value is recorded but no code reads it yet. The screen '
  'shows these apart, so nobody changes a number expecting an effect.';

-- 1 · dead duplicates. Each read by nothing, anywhere, and each duplicating
--     a source that is live. Keeping them means two places to change one
--     thing, which is the defect this rebuild exists to remove.
delete from app_setting where key in (
  'curve_band_1','curve_band_2','curve_band_3','curve_band_4','curve_band_5',
                                   -- the bands live in pms_curve_band, with labels
  'pms_curve',                     -- the same bands again, as one string
  'day_open_hour','day_close_hour',-- day_start and day_end are what the clock reads
  'pms_probation_floor'            -- pms_probation is what pms_cycle_score reads
);

-- 2 · recorded, not yet in force
update app_setting set in_force = false where key in (
  'pms_window_open','pms_window_close','pms_self_by','pms_review_hrs','pms_exc_open',
  'mail_spread_above'
);

-- 3 · plumbing, not a setting: how the system talks to itself
update app_setting set editable_by = 'SYSTEM' where key in (
  'anon_key','function_base_url','mail_cron_secret','mail_oauth_state',
  'mail_oauth_refresh_token','whatsapp'
);

-- Eighteen rows said "Migrated from the API settings table" in the field the
-- screen shows a person verbatim. They now say what the setting does. The
-- full text is in the migration ledger under settings_tell_the_truth; the
-- grouping was fixed in the same place, because "clocks" had become the
-- drawer that appraisal numbers, a mail cap and a connection status went into.

-- ------------------------------------------- the auto-close window, honestly
-- auto_close_days sat in app_setting, editable, described, and read by
-- nothing: the window was a literal seven days in the escalation route. The
-- rule belongs next to the data, so every writer gets it - including a
-- correction made by hand - and so this needed no redeployment.
create or replace function case_auto_close_window()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare v_days int;
begin
  if new.status = 'RESOLVED' and old.status is distinct from 'RESOLVED' then
    v_days := coalesce(nullif((select value from app_setting
                                where key = 'auto_close_days'), ''), '7')::int;
    -- scheduled at resolution, so changing the setting later never moves a
    -- window somebody is already inside
    new.auto_close_at := now() + make_interval(days => v_days);
  end if;
  return new;
end $function$;

drop trigger if exists case_auto_close_window on "case";
create trigger case_auto_close_window
  before update on "case"
  for each row execute function case_auto_close_window();

-- ------------------------------------------------------- one number, one key
-- pms_monthly_cap and pms_cut_cap were two keys for the same two-point shared
-- monthly cap, read from two places in the same file. pms_cut_cap wins.
--
-- The other survives as a shadow kept in step by a trigger, marked SYSTEM so
-- it is never offered as a control, because the DEPLOYED api function still
-- asks for it by name. build/supabase/functions/api/routes/pms.ts in this
-- repository already reads pms_cut_cap; deploying api removes the need for
-- the shadow, and the shadow and this trigger go with it.
insert into app_setting (key, value, plain_language, group_name, secret, editable_by, in_force)
values ('pms_monthly_cap',
        (select value from app_setting where key = 'pms_cut_cap'),
        'A shadow of pms_cut_cap, kept in step automatically. It exists only '
        'because a deployed edge function still asks for the old key by name, '
        'and it is removed when that function is next deployed. Never edit it: '
        'edit pms_cut_cap.',
        'Performance and appraisal', false, 'SYSTEM', true)
on conflict (key) do update set value = excluded.value, editable_by = 'SYSTEM';

create or replace function pms_cap_shadow()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  if new.key = 'pms_cut_cap' and new.value is distinct from old.value then
    update app_setting set value = new.value where key = 'pms_monthly_cap';
  end if;
  return new;
end $function$;

drop trigger if exists pms_cap_shadow on app_setting;
create trigger pms_cap_shadow
  after update on app_setting
  for each row execute function pms_cap_shadow();

-- ============================================================ the back end
-- Three rules run through all of it:
--   · A secret goes in and never comes back out. The screen is told whether
--     one is set, never what it is.
--   · Nothing marked SYSTEM is offered as a control.
--   · Every change is audited with the actor, the old value and the new.
--
-- config_read, config_set, config_job_set and config_penalty_save are in the
-- migration ledger under configuration_has_a_back_end and
-- config_read_grouping_fix. The guards each one carries, proven by test:
--
--   config_set          · refuses a SYSTEM value, refuses an unknown key
--   config_job_set      · refuses to stop a job without a reason, and records
--                         who stopped it (job_config refuses it otherwise)
--   config_penalty_save · refuses to switch a rule on while its amount is
--                         zero, because a rule at zero records a charge of
--                         nothing against somebody's name
--
-- The screen is served by a new edge function, cfg, for the same reason org
-- and wa have their own: changing a settings screen must never mean
-- redeploying the escalation engine.

revoke all on function case_auto_close_window() from public, anon, authenticated;
revoke all on function pms_cap_shadow() from public, anon, authenticated;
