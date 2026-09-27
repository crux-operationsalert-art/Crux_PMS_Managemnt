-- READY TO APPLY. Not yet applied: the MCP approval gate refused every
-- Supabase call, including a bare `select 1`, so nothing in this file has
-- run against the database. Apply it as migration
-- 187_act_as_a_person_or_a_chair.
--
-- ---------------------------------------------------------------- why
-- An administrator needs to see what a person sees, not a description of
-- it. The honest way is to hand them a real session for that person, so
-- every screen, every permission and every refusal is the real one -- and
-- to write on the session row who is really behind it.
--
-- This was in the design and was never built. Crux App v2.dc.html carries
-- a PERSONAS model giving every chair its own nav, and a seats() switcher
-- whose own confirmation message reads:
--
--     "You are now acting as {chair}. Your tasks, escalations, reports
--      and rights all follow the chair, not the person."
--
-- That is the behaviour being put back. See build/AUDIT_design_vs_built.md.
--
-- acting_actor_id is what keeps it honest. The session belongs to the
-- target, which is what makes the view truthful; the column says who
-- opened it, which is what makes it accountable. Two hours, not seven
-- days: this is for looking, and a borrowed seat should not outlive the
-- reason somebody sat in it.

alter table auth_session
  add column if not exists acting_actor_id uuid references person(id);

comment on column auth_session.acting_actor_id is
  'Set when an administrator opened this session to act as person_id. The session behaves exactly as that person''s, and this says who is behind it.';

-- auth_whoami has always returned four fields, and the page has always read
-- person.chair_title and person.department off it. It never got them, which
-- is why the header shows ADMIN or VIEWER where a chair should be. That is
-- a bug in its own right and is fixed here because act-as makes it glaring:
-- the whole point is to see yourself as that person, and the header was
-- showing a role instead of a seat.
create or replace function public.auth_whoami(p_token_hash text)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_person uuid; v_actor uuid; p person%rowtype; a person%rowtype;
begin
  update auth_session s set last_seen_at = now()
   where s.token_hash = p_token_hash
     and s.revoked_at is null
     and s.expires_at > now()
   returning s.person_id, s.acting_actor_id into v_person, v_actor;
  if v_person is null then return null; end if;

  select * into p from person
   where id = v_person and employment_status = 'ACTIVE' and superseded_by is null;
  if not found then return null; end if;

  if v_actor is not null then
    select * into a from person where id = v_actor;
  end if;

  return jsonb_build_object(
    'id', p.id, 'full_name', p.full_name,
    'work_email', p.work_email, 'app_role', p.app_role,
    'department', p.department,
    'designation', (select d.title from designation d where d.id = p.designation_id),
    'chair_title', (select ch.title from chair_holder h join chair ch on ch.id = h.chair_id
                     where h.person_id = p.id and h.to_date is null
                     order by h.is_primary desc, ch.title limit 1),
    'employee_no', p.employee_no,
    'acting', case when v_actor is null then null else jsonb_build_object(
        'by', a.full_name, 'byId', a.id, 'byEmail', a.work_email) end);
end $fn$;

-- Who can be looked at. People and chairs in one read, because the picker
-- offers both and a second round trip would only let the two disagree.
create or replace function public.auth_act_targets(p_actor uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare a person%rowtype;
begin
  select * into a from person where id = p_actor;
  if a.id is null or a.app_role <> 'ADMIN' then
    return jsonb_build_object('error','not_permitted',
      'reason','Only an administrator can look at the tool as somebody else.');
  end if;

  return jsonb_build_object(
    'people', coalesce((
      select jsonb_agg(jsonb_build_object(
               'personId', p.id, 'name', p.full_name, 'employeeNo', p.employee_no,
               'email', p.work_email, 'role', p.app_role, 'department', p.department,
               'chair', (select ch.title from chair_holder h join chair ch on ch.id = h.chair_id
                          where h.person_id = p.id and h.to_date is null
                          order by h.is_primary desc, ch.title limit 1))
             order by p.full_name)
        from person p
       where p.superseded_by is null and p.employment_status = 'ACTIVE'
         and coalesce(p.employee_type,'EMPLOYEE') <> 'CLIENT_CONTACT'), '[]'::jsonb),
    'chairs', coalesce((
      select jsonb_agg(jsonb_build_object(
               'chairId', ch.id, 'chair', ch.title, 'code', ch.code,
               'seated', (select count(*) from chair_holder h
                           where h.chair_id = ch.id and h.to_date is null),
               'inScheme', exists (select 1 from kpi_definition k
                                    where k.chair_id = ch.id and k.active and k.position < 100),
               'holders', (select coalesce(jsonb_agg(jsonb_build_object(
                     'personId', p2.id, 'name', p2.full_name) order by p2.full_name), '[]'::jsonb)
                   from chair_holder h2 join person p2 on p2.id = h2.person_id
                  where h2.chair_id = ch.id and h2.to_date is null
                    and p2.superseded_by is null and p2.employment_status = 'ACTIVE'))
             order by ch.title)
        from chair ch
       where exists (select 1 from chair_holder h where h.chair_id = ch.id
                       and h.to_date is null)), '[]'::jsonb));
end $fn$;

create or replace function public.auth_act_as(
  p_actor uuid, p_person uuid, p_chair uuid, p_token_hash text, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare a person%rowtype; t person%rowtype; n int; v_chair text;
begin
  -- ADMIN is checked here and not only in the service, so a caller that
  -- skips the service is refused the same way. The hr route this is called
  -- through admits HR as well as administrators, and that is fine: this
  -- refuses HR, and this is the gate that counts.
  select * into a from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null or a.app_role <> 'ADMIN' then
    return jsonb_build_object('error','not_permitted',
      'reason','Only an administrator can look at the tool as somebody else.');
  end if;

  -- a chair resolves to whoever is sitting in it, and says so when that is
  -- not one person: an empty chair and a shared one are different answers
  -- and collapsing them into "cannot" would hide which one it is
  if p_person is null and p_chair is not null then
    select count(*) into n from chair_holder h join person p2 on p2.id = h.person_id
     where h.chair_id = p_chair and h.to_date is null
       and p2.superseded_by is null and p2.employment_status = 'ACTIVE';
    select ch.title into v_chair from chair ch where ch.id = p_chair;
    if n = 0 then
      return jsonb_build_object('error','chair_is_empty',
        'reason', coalesce(v_chair,'That chair') || ' has nobody in it, so there is nobody to look at the tool as. Seat somebody first.');
    end if;
    if n > 1 then
      return jsonb_build_object('error','chair_is_shared',
        'reason', v_chair || ' is held by ' || n || ' people. Pick which of them.',
        'holders', (select jsonb_agg(jsonb_build_object('personId', p2.id, 'name', p2.full_name)
                      order by p2.full_name)
                      from chair_holder h join person p2 on p2.id = h.person_id
                     where h.chair_id = p_chair and h.to_date is null
                       and p2.superseded_by is null and p2.employment_status = 'ACTIVE'));
    end if;
    select p2.id into p_person from chair_holder h join person p2 on p2.id = h.person_id
     where h.chair_id = p_chair and h.to_date is null
       and p2.superseded_by is null and p2.employment_status = 'ACTIVE' limit 1;
  end if;

  if p_person is null then
    return jsonb_build_object('error','nobody_named',
      'reason','Name a person, or a chair somebody is sitting in.');
  end if;

  select * into t from person
   where id = p_person and employment_status = 'ACTIVE' and superseded_by is null;
  if t.id is null then
    return jsonb_build_object('error','no_such_person',
      'reason','That person is not active on the people master.');
  end if;
  if t.id = a.id then
    return jsonb_build_object('error','that_is_you',
      'reason','You are already signed in as yourself.');
  end if;

  insert into auth_session (person_id, expires_at, source, token_hash, acting_actor_id)
  values (t.id, now() + interval '2 hours', 'ACT_AS', p_token_hash, a.id);

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (a.id, 'ACTED_AS', 'person', t.id::text,
          jsonb_build_object('actor', a.full_name, 'actorEmail', a.work_email, 'ip', p_ip),
          jsonb_build_object('as', t.full_name, 'asEmail', t.work_email,
                             'asRole', t.app_role, 'viaChair', v_chair,
                             'expires', (now() + interval '2 hours')));

  return jsonb_build_object('id', t.id, 'full_name', t.full_name,
    'work_email', t.work_email, 'app_role', t.app_role,
    'department', t.department,
    'chair_title', (select ch.title from chair_holder h join chair ch on ch.id = h.chair_id
                     where h.person_id = t.id and h.to_date is null
                     order by h.is_primary desc, ch.title limit 1),
    'employee_no', t.employee_no,
    'acting', jsonb_build_object('by', a.full_name, 'byId', a.id, 'byEmail', a.work_email),
    'note', 'You are looking at Crux as ' || t.full_name || '. Everything you do here is recorded as ' || t.full_name || ', with your name against it in the audit trail.');
end $fn$;

revoke all on function public.auth_act_targets(uuid) from public, anon, authenticated;
revoke all on function public.auth_act_as(uuid, uuid, uuid, text, text) from public, anon, authenticated;
