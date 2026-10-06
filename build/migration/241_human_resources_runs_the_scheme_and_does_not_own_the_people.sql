-- Human Resources runs the scheme and does not own the people (241)
--
-- This takes migration 239's HR half back out. The administrator half of
-- 239 was a bug fix and stays; the HR half was a decision I had no business
-- making, and it was wrong in a way I did not notice until the test suite
-- said so.
--
-- WHAT 239 DID. It taught perf_rel a fourth relation, 'hr', so that anybody
-- in the Human Resources department stood in a setting relationship to
-- every person in the company.
--
-- WHY THAT WAS WRONG. Migration 218 had already removed exactly this, on
-- purpose, and said why: "a department was a licence over every person in
-- the company. The rule now is the reporting line and nothing else --
-- running the scheme is a different act from setting one named person's
-- numbers." Three assertions guard it, in test_190_198 and test_line. 239
-- made all three fail, and the right reading of a failing test that was
-- written deliberately is that the change is wrong, not the test.
--
-- AND IT DID MORE THAN IT CLAIMED. 239's own header says it does not widen
-- anybody's VIEW, on the reasoning that HR already had 'watch' over
-- everybody. That reasoning is false. perf_rel's last branch reads from
-- perf_line, which holds only people BELOW the actor, so for a stranger it
-- returned null and perf_may_see was false. Giving HR a non-null relation
-- to everybody therefore made perf_may_see true for everybody -- a hundred
-- people's performance, newly readable, in a change whose header promised
-- the opposite. test_line caught it in one line: "HR reached a stranger:
-- see=t set=t".
--
-- WHAT REMAINS OF 239. Nothing in the database. The real fix for "team
-- member assignments is still not working for Admin or HR" is elsewhere and
-- is kept: an administrator with direct reports used to be shown only those
-- reports, because the route fell back to the whole company only when the
-- reports numbered zero. That is in the plb function, is about ADMIN alone,
-- and changes nobody's permissions -- perf_rel has always returned 'admin'
-- for an administrator over everybody.
--
-- WHAT IS LEFT OPEN. Whether HR should be able to set a named person's
-- KPIs and targets is a policy question, not a bug, and it is the owner's
-- to answer. Until it is answered the rule is 218's.

-- -------------------------------------------------------------- perf_rel
-- Byte for byte what it was before 239, so a diff against the migration
-- that last touched it is empty.
create or replace function perf_rel(p_actor uuid, p_person uuid)
returns text language sql stable security definer set search_path to 'public'
as $function$
  select case
    when p_actor is null or p_person is null then null
    when p_actor = p_person then 'self'
    when exists (select 1 from person a
                  where a.id = p_actor and a.app_role = 'ADMIN'
                    and a.employment_status = 'ACTIVE' and a.superseded_by is null) then 'admin'
    else (select case when l.depth = 1 then 'manage' else 'watch' end
            from perf_line(p_actor) l where l.person_id = p_person)
  end
$function$;

create or replace function perf_may_set(p_actor uuid, p_person uuid)
returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(perf_rel(p_actor, p_person) in ('manage','admin'), false)
$function$;

create or replace function kpi_subtree_people(p_actor uuid)
returns table(person_id uuid) language sql stable security definer set search_path to 'public'
as $function$
  select p.id
    from person p
   where p.employment_status = 'ACTIVE'
     and p.superseded_by is null
     and coalesce(p.employee_type, 'EMPLOYEE') <> 'CLIENT_CONTACT'
     and p.id <> p_actor
     and (exists (select 1 from person a
                   where a.id = p_actor and a.app_role = 'ADMIN'
                     and a.employment_status = 'ACTIVE'
                     and a.superseded_by is null)
          or p.id in (select l.person_id from perf_line(p_actor) l
                       where l.depth = 1))
$function$;

-- ------------------------------------------- and the five that 239 widened
-- 'hr' is now a relation perf_rel never returns, so leaving it in these
-- lists would be inert. Inert is not the same as absent: the next person to
-- read plb_quarter would find a relation named in the code and nowhere
-- else, and would reasonably conclude it means something. One rule, said
-- once.
do $narrow$
declare
  r record; v_src text; v_n int := 0;
  v_old constant text := $q$'manage','admin','hr')$q$;
  v_new constant text := $q$'manage','admin')$q$;
begin
  for r in
    select p.proname,
           pg_get_function_identity_arguments(p.oid) as args,
           pg_get_function_result(p.oid) as ret,
           p.prosrc, p.provolatile, p.prosecdef, l.lanname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      join pg_language l on l.oid = p.prolang
     where n.nspname = 'public'
       and l.lanname in ('sql','plpgsql')
       and position(v_old in p.prosrc) > 0
  loop
    v_src := replace(r.prosrc, v_old, v_new);
    execute format(
      'create or replace function %I(%s) returns %s language %s %s %s '
      'set search_path to ''public'' as %L',
      r.proname, r.args, r.ret, r.lanname,
      case r.provolatile when 's' then 'stable'
                         when 'i' then 'immutable'
                         else '' end,
      case when r.prosecdef then 'security definer' else 'security invoker' end,
      v_src);
    v_n := v_n + 1;
    raise notice '  relation list narrowed in %(%)', r.proname, r.args;
  end loop;
  raise notice 'relation list narrowed in % function(s)', v_n;
end $narrow$;

-- The wording 239 changed on plb_actual_from_perf, put back.
do $wording$
declare v_src text; v_old text; v_new text;
begin
  v_old := 'is the reporting manager''''s, or Human Resources, or ';
  v_new := 'is the reporting manager''''s, or ';
  select prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'plb_actual_from_perf';
  if position(v_old in v_src) > 0 then
    execute 'create or replace function plb_actual_from_perf(p_actor uuid, p_sheet uuid) '
         || 'returns jsonb language plpgsql security definer '
         || 'set search_path to ''public'' as '
         || quote_literal(replace(v_src, v_old, v_new));
  end if;
end $wording$;

-- ------------------------------------------------------------- the guard
-- The three assertions 239 broke, said here as well as in the test files,
-- so a re-run of this migration alone proves the revert landed.
do $guard$
declare v_hr uuid; v_far uuid; v_adm uuid; n int;
begin
  select id into v_hr from person
   where coalesce(department,'') = 'Human Resources'
     and employment_status = 'ACTIVE' and superseded_by is null
     and app_role is distinct from 'ADMIN'
   limit 1;
  select id into v_adm from person
   where app_role = 'ADMIN' and employment_status = 'ACTIVE' and superseded_by is null
   limit 1;

  if v_hr is not null then
    -- Somebody HR neither manages nor reports to.
    select p.id into v_far from person p
     where p.employment_status = 'ACTIVE' and p.superseded_by is null
       and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
       and p.id <> v_hr
       and perf_rel(v_hr, p.id) is null
     limit 1;

    if v_far is null then
      raise notice 'Migration 241: every person is in HR''s line, so there is '
                   'no stranger to test against.';
    else
      if perf_may_set(v_hr, v_far) then
        raise exception 'Migration 241: being in Human Resources is still a '
                        'licence to set over a stranger';
      end if;
      if perf_may_see(v_hr, v_far) then
        raise exception 'Migration 241: being in Human Resources is still a '
                        'reason to see a stranger';
      end if;
      if exists (select 1 from kpi_subtree_people(v_hr) s where s.person_id = v_far) then
        raise exception 'Migration 241: a stranger is still in HR''s KPI subtree';
      end if;
    end if;
  end if;

  -- The administrator is untouched, which is the half of 239 that was right.
  if v_adm is not null then
    select count(*) into n
      from person p
     where p.employment_status = 'ACTIVE' and p.superseded_by is null
       and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'
       and p.id <> v_adm
       and not perf_may_set(v_adm, p.id);
    if n > 0 then
      raise exception 'Migration 241: an administrator may no longer set for '
                      '% person/people', n;
    end if;
    if perf_may_set(v_adm, v_adm) then
      raise exception 'Migration 241: an administrator may set their own';
    end if;
  end if;

  -- And no function names a relation perf_rel cannot return. Matched on the
  -- two shapes the relation is actually written in -- the tail of a relation
  -- list, and the branch that returned it -- rather than on the bare string
  -- 'hr', which also appears in dept_canon, person_welcome_body and
  -- access_policy_questions for reasons that have nothing to do with this.
  select count(*) into n from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and (p.prosrc like '%''manage'',''admin'',''hr''%'
       or p.prosrc like '%then ''hr''%');
  if n > 0 then
    raise exception 'Migration 241: % function(s) still name the hr relation', n;
  end if;

  raise notice 'the rule is the reporting line and nothing else; '
               'the administrator is unchanged';
end $guard$;
