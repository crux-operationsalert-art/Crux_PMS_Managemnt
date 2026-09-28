-- 210 · The three questions that are not mine
--
-- Enforcing the access policy in the services (204) turned up three places
-- where the policy itself looks wrong. Changing a policy while implementing it
-- hides the change, so none of them was touched. They were written into a
-- migration comment and a document, which is where findings go to be forgotten.
--
-- This puts them on the Alerts screen instead, where the administrator meets
-- them, each with the one line that settles it. They are INFO, not WARN: the
-- tool is not broken, somebody has to decide something.
--
-- Each check is live. Apply the fix and the alert resolves itself the next
-- time access_policy_questions() runs; decide the other way and resolve it on
-- the screen, which is the same thing said out loud. It is NOT scheduled --
-- a decision is not a sweep -- so re-running the function is how it refreshes.

create or replace function public.access_policy_questions()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_open  int := 0;
  v_shut  int := 0;
  n int;
  v_detail text;
begin
  -- ------------------------------------------------ 1. the rate master
  -- rates is a child of reports, so every level that carries Reports can read
  -- every client's commercial rate. Finance and the administrator own WRITING
  -- one; reading one is open to six of the eight levels.
  select count(*) into n
    from access_screen_parent
   where screen = 'rates' and parent = 'reports';
  if n > 0 then
    select count(*) into n from person p
     where p.employment_status = 'ACTIVE' and p.superseded_by is null
       and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
       and access_may_open(p.id, 'rates');
    perform ops_alert_raise(
      'ACCESS_POLICY',
      'The rate master is open to everyone who can open Reports',
      'access-policy-rates', 'INFO',
      n || ' people can read every client''s commercial rate, because the rate '
        || 'master is reached from inside Reports and six of the eight scope '
        || 'levels carry Reports. Finance and the administrator own changing a '
        || 'rate; this is about reading one.',
      'If that is right, resolve this. If it is not, move it under Settings, '
        || 'which only HR, Finance and the administrator carry: '
        || 'update access_screen_parent set parent = ''config'' where screen = ''rates'';');
    v_open := v_open + 1;
  else
    update ops_alert set resolved_at = now(),
           resolved_note = 'The rate master no longer follows Reports.'
     where dedupe_key = 'access-policy-rates' and resolved_at is null;
    v_shut := v_shut + (case when found then 1 else 0 end);
  end if;

  -- --------------------------------------- 2. the rule nobody ever read
  -- The published tool declares ADMIN_TABS = { data, mail, whatsapp } and
  -- never reads it. SCREENS gives mail to hr and data to analytics, and
  -- SCREENS is what runs.
  select count(*) into n from access_level_screen
   where (level = 'hr' and screen = 'mail')
      or (level = 'analytics' and screen = 'data');
  if n > 0 then
    perform ops_alert_raise(
      'ACCESS_POLICY',
      'Two screens the design marked administrator-only are not',
      'access-policy-admin-tabs', 'INFO',
      'The tool declares ADMIN_TABS = { data, mail, whatsapp } and never reads '
        || 'it, so the intention is legible and has never run. What runs gives '
        || 'Messaging to HR and Data setup to MIS. What was seeded is what runs.',
      'If the intention was the policy: '
        || 'delete from access_level_screen where (level, screen) in '
        || '((''hr'',''mail''), (''analytics'',''data'')); '
        || 'and take the dead variable out of the page.');
    v_open := v_open + 1;
  else
    update ops_alert set resolved_at = now(),
           resolved_note = 'Messaging and Data setup are the administrator''s now.'
     where dedupe_key = 'access-policy-admin-tabs' and resolved_at is null;
    v_shut := v_shut + (case when found then 1 else 0 end);
  end if;

  -- ------------------------- 3. a permission for a screen nobody can open
  -- places.ts carries mayAssign, which lets a department with a matrix or full
  -- client view assign coverage. No such person's level carries the coverage
  -- screen, so the permission is for a page they cannot open. Before the
  -- services enforced the policy they could reach it by typing the URL; they
  -- can not now, which is the policy working, and the policy may be wrong.
  select count(*), string_agg(distinct p.department, ', ')
    into n, v_detail
    from person p
    join client_view_policy v on v.department = p.department
   where p.employment_status = 'ACTIVE' and p.superseded_by is null
     and v.view_kind in ('matrix','full')
     and not access_may_open(p.id, 'coverage');
  if n > 0 then
    perform ops_alert_raise(
      'ACCESS_POLICY',
      'Operations may assign coverage and cannot open the screen that does it',
      'access-policy-coverage', 'INFO',
      n || ' people in ' || v_detail || ' hold the permission to assign '
        || 'coverage, and not one of them is at a scope level that carries the '
        || 'Places, coverage & owners screen -- which only MIS and the '
        || 'administrator do. The navigation has never offered it to them; '
        || 'until the services enforced the policy they could still reach it by '
        || 'typing the address.',
      'If Operations runs coverage, give the level the screen -- for example: '
        || 'insert into access_level_screen (level, screen) values '
        || '(''branch'',''coverage'') on conflict do nothing; -- and it appears '
        || 'in their navigation. If it does not, the mayAssign check in '
        || 'ops/routes/places.ts is vestigial and should go.');
    v_open := v_open + 1;
  else
    update ops_alert set resolved_at = now(),
           resolved_note = 'Everyone who may assign coverage can open the screen.'
     where dedupe_key = 'access-policy-coverage' and resolved_at is null;
    v_shut := v_shut + (case when found then 1 else 0 end);
  end if;

  return jsonb_build_object('open', v_open, 'resolved', v_shut);
end $fn$;

comment on function public.access_policy_questions() is
  'Three places where enforcing the access policy showed the policy itself may '
  'be wrong. Raises an INFO alert while each is true and resolves it when it '
  'is not. Not scheduled: a decision is not a sweep.';

do $do$
declare r jsonb;
begin
  r := access_policy_questions();
  raise notice '210: % open, % resolved', r->>'open', r->>'resolved';
end $do$;
