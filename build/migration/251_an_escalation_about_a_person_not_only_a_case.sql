-- An escalation about a person, not only a case (251)
--
-- "Raise an escalation about a person, not only a case."
--
-- The tool has had escalations since it had cases: escalation_instance is
-- raised when a case breaches its TAT, routed by the client's matrix, and
-- closed when somebody acts. Every one of them is about a CASE. There has
-- never been a way to say "this is about a person" -- the conduct side
-- starts at a warning, which is a finding, and a finding is the end of a
-- process rather than the start of one.
--
-- So somebody who hits a problem with a colleague has had two options: issue
-- a warning they are not entitled to issue, or say nothing. This is the
-- missing first step.
--
-- WHAT IT IS, AND WHAT IT IS NOT
--
-- An escalation is a QUESTION put to the one person who can answer it. It is
-- not a finding, it carries no level, and it goes on nobody's record unless
-- and until it is closed with an outcome that says it should.
--
-- A warning is the opposite: person_warn writes a record that is never
-- edited, because "a disciplinary record that can be rewritten afterwards is
-- not evidence of anything" (233). The two are deliberately different
-- shapes, and an escalation that is upheld does not silently become a
-- warning -- somebody has to issue one, and sign it.
--
-- WHO IT GOES TO. The subject's own manager, because that is the person who
-- can do something about it. If the raiser IS that manager, it goes a step
-- further up -- a manager escalating about their own report is asking for
-- their own manager's view, not their own. If there is nobody above, it goes
-- to Human Resources, who run the people side.
--
-- WHO MAY SEE IT. The raiser, whoever it routed to, the subject's managers,
-- HR and the administrator. NOT the subject, while it is open: an
-- unexamined allegation shown to the person it is about is how a tool turns
-- a question into a grievance. Once it is closed, the subject sees it with
-- its outcome, on their own conduct panel, because a thing that was decided
-- about somebody is theirs to read.
--
-- WHO MAY RAISE IT. Anybody who works here, about anybody but themselves.
-- That is the point of it: the person who hits the problem is usually not in
-- the reporting line of the person causing it, and a form only managers can
-- reach is a form that leaves the commonest case unsaid.

create table if not exists person_escalation (
  id            uuid primary key default gen_random_uuid(),
  about_id      uuid not null references person(id),
  raised_by     uuid not null references person(id),
  raised_at     timestamptz not null default now(),
  routed_to     uuid references person(id),
  route_note    text,
  subject       text not null,
  detail        text,
  -- What kind of thing this is, so the person it routes to knows which hat
  -- to put on before reading it. Not a severity: severity is a judgement and
  -- this is raised before anybody has judged anything.
  about_kind    text not null default 'CONDUCT',
  due_on        date,
  state         text not null default 'OPEN',
  seen_at       timestamptz,
  closed_at     timestamptz,
  closed_by     uuid references person(id),
  outcome       text,
  outcome_note  text,
  constraint person_escalation_said      check (btrim(subject) <> ''),
  constraint person_escalation_not_self  check (about_id <> raised_by),
  constraint person_escalation_kind      check (about_kind in
    ('CONDUCT','PERFORMANCE','PROCESS','SAFETY','OTHER')),
  constraint person_escalation_state     check (state in
    ('OPEN','SEEN','CLOSED','WITHDRAWN')),
  -- A closed escalation says how it ended. "Closed" with no outcome is the
  -- state that lets a thing be quietly dropped and still look handled.
  constraint person_escalation_closed_says_how check (
    state <> 'CLOSED' or (outcome is not null and btrim(coalesce(outcome_note,'')) <> ''))
);

create index if not exists person_escalation_about on person_escalation (about_id, raised_at desc);
create index if not exists person_escalation_to on person_escalation (routed_to, state);

alter table person_escalation enable row level security;

comment on table person_escalation is
  'A question raised about a person and put to the one person who can answer '
  'it. Not a warning: it carries no level and goes on no record unless it is '
  'closed with an outcome that says so.';

-- =====================================================================
-- Where it goes.
-- =====================================================================
create or replace function person_escalation_route(p_raiser uuid, p_about uuid)
returns table (to_id uuid, why text)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare v_mgr uuid; v_up uuid; v_hr uuid;
begin
  select manager_id into v_mgr from person where id = p_about;

  if v_mgr is not null and v_mgr <> p_raiser then
    return query select v_mgr, 'their manager'::text;
    return;
  end if;

  -- The raiser IS the manager. Asking themselves is not an escalation, so it
  -- goes one step further up.
  if v_mgr is not null and v_mgr = p_raiser then
    select manager_id into v_up from person where id = v_mgr;
    if v_up is not null then
      return query select v_up, 'you are their manager, so this goes to yours'::text;
      return;
    end if;
  end if;

  -- Nobody above, or nobody at all. HR run the people side.
  select id into v_hr from person
   where employment_status = 'ACTIVE' and superseded_by is null
     and coalesce(department,'') = 'Human Resources'
     and coalesce(employee_type,'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
   order by case when app_role = 'ADMIN' then 1 else 0 end, full_name
   limit 1;
  if v_hr is not null then
    return query select v_hr, 'nobody is above them, so this goes to Human Resources'::text;
    return;
  end if;

  return query select null::uuid,
    'nobody is above them and there is no one in Human Resources'::text;
end
$function$;

-- =====================================================================
-- Raising one.
-- =====================================================================
create or replace function person_escalation_raise(p_actor uuid, p_in jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public'
as $function$
declare
  a person; s person;
  v_about uuid; v_subject text; v_kind text;
  v_to uuid; v_why text; v_id uuid; v_due date;
begin
  select * into a from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null then
    return jsonb_build_object('error','not_permitted','reason','Who is asking?');
  end if;

  v_about := nullif(btrim(coalesce(p_in->>'personId','')),'')::uuid;
  select * into s from person
   where id = v_about and employment_status = 'ACTIVE' and superseded_by is null;
  if s.id is null then
    return jsonb_build_object('error','no_such_person');
  end if;
  if coalesce(s.employee_type,'EMPLOYEE') in ('SERVICE_ACCOUNT','CLIENT_CONTACT') then
    return jsonb_build_object('error','not_staff',
      'reason', s.full_name || ' is not a member of staff.');
  end if;
  if v_about = p_actor then
    return jsonb_build_object('error','not_permitted',
      'reason','An escalation is raised about somebody else. If this is about '
            || 'your own work, your manager is the person to tell.');
  end if;

  v_subject := btrim(coalesce(p_in->>'subject',''));
  if v_subject = '' then
    return jsonb_build_object('error','invalid',
      'reason','Say in one line what this is about. The person it goes to has '
            || 'to be able to recognise it without opening it.');
  end if;
  if length(v_subject) > 160 then
    return jsonb_build_object('error','invalid',
      'reason','One line, not a paragraph. The detail goes underneath.');
  end if;

  v_kind := upper(coalesce(nullif(btrim(coalesce(p_in->>'kind','')),''),'CONDUCT'));
  if v_kind not in ('CONDUCT','PERFORMANCE','PROCESS','SAFETY','OTHER') then
    return jsonb_build_object('error','invalid',
      'reason','Conduct, Performance, Process, Safety or Other.');
  end if;

  select to_id, why into v_to, v_why from person_escalation_route(p_actor, v_about);
  if v_to is null then
    return jsonb_build_object('error','nowhere_to_send',
      'reason','There is nobody this can go to: ' || coalesce(v_why,'') || '. '
            || 'Ask the administrator to put somebody above them first.');
  end if;

  -- Three working days, on the same calendar the dispute window runs on. An
  -- escalation with no clock is a thing that sits.
  v_due := plb_wd_after(current_date, 3);

  insert into person_escalation (about_id, raised_by, routed_to, route_note,
                                 subject, detail, about_kind, due_on)
  values (v_about, p_actor, v_to, v_why, v_subject,
          nullif(btrim(coalesce(p_in->>'detail','')),''), v_kind, v_due)
  returning id into v_id;

  insert into audit_entry (actor_id, action, entity_type, entity_ref,
                           old_value, new_value)
  values (p_actor, 'PERSON_ESCALATION_RAISED', 'person', v_about::text, null,
          jsonb_build_object('id', v_id, 'subject', v_subject, 'kind', v_kind,
                             'routedTo', v_to));

  return jsonb_build_object('ok', true, 'id', v_id,
    'routedTo', v_to,
    'routedToName', (select full_name from person where id = v_to),
    'dueOn', v_due,
    'note', 'Raised with ' || (select full_name from person where id = v_to) ||
            ' — ' || v_why || '. They have until ' || v_due ||
            '. ' || s.full_name || ' is not shown it while it is open.');
end
$function$;

comment on function person_escalation_raise(uuid, jsonb) is
  'Raise an escalation about a person. Routes to their manager, or a step '
  'higher when the raiser is that manager, or to HR when nobody is above '
  'them. Anybody may raise one, about anybody but themselves.';

-- =====================================================================
-- Acting on one.
-- =====================================================================
create or replace function person_escalation_act(p_actor uuid, p_id uuid,
                                                 p_action text, p_in jsonb
                                                   default '{}'::jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public'
as $function$
declare
  a person; e person_escalation; v_act text; v_outcome text; v_note text;
begin
  select * into a from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null then
    return jsonb_build_object('error','not_permitted','reason','Who is asking?');
  end if;
  select * into e from person_escalation where id = p_id;
  if e.id is null then return jsonb_build_object('error','no_such_escalation'); end if;

  v_act := upper(coalesce(nullif(btrim(coalesce(p_action,'')),''),''));

  -- Withdrawing is the raiser's, and only theirs. Nobody else gets to decide
  -- that a thing was never worth raising.
  if v_act = 'WITHDRAW' then
    if p_actor <> e.raised_by then
      return jsonb_build_object('error','not_permitted',
        'reason','Only the person who raised it can withdraw it. Anybody it '
              || 'went to can close it, with an outcome.');
    end if;
    if e.state in ('CLOSED','WITHDRAWN') then
      return jsonb_build_object('ok', true, 'changed', false,
        'note','It is already ' || lower(e.state) || '.');
    end if;
    update person_escalation set state = 'WITHDRAWN', closed_at = now(),
           closed_by = p_actor,
           outcome_note = nullif(btrim(coalesce(p_in->>'note','')),'')
     where id = p_id;
    insert into audit_entry (actor_id, action, entity_type, entity_ref,
                             old_value, new_value)
    values (p_actor, 'PERSON_ESCALATION_WITHDRAWN', 'person', e.about_id::text,
            jsonb_build_object('state', e.state), jsonb_build_object('state','WITHDRAWN'));
    return jsonb_build_object('ok', true, 'changed', true,
      'note','Withdrawn. It stays on the record as having been raised and '
          || 'withdrawn, because a thing that was said was said.');
  end if;

  -- Everything else is for whoever it went to, their line, HR and the
  -- administrator. The same people who can see it.
  if not (p_actor = e.routed_to
          or a.app_role = 'ADMIN'
          or coalesce(a.department,'') = 'Human Resources'
          or perf_may_set(p_actor, e.about_id)) then
    return jsonb_build_object('error','not_permitted',
      'reason','This was put to somebody else. They, their own manager, HR and '
            || 'the administrator can act on it.');
  end if;

  if v_act = 'SEEN' then
    if e.state <> 'OPEN' then
      return jsonb_build_object('ok', true, 'changed', false,
        'note','Already ' || lower(e.state) || '.');
    end if;
    update person_escalation set state = 'SEEN', seen_at = now() where id = p_id;
    return jsonb_build_object('ok', true, 'changed', true,
      'note','Marked as read. The clock does not stop for that; closing it does.');
  end if;

  if v_act = 'CLOSE' then
    if e.state in ('CLOSED','WITHDRAWN') then
      return jsonb_build_object('ok', true, 'changed', false,
        'note','It is already ' || lower(e.state) || '.');
    end if;
    v_outcome := upper(coalesce(nullif(btrim(coalesce(p_in->>'outcome','')),''),''));
    if v_outcome not in ('UPHELD','PARTLY_UPHELD','NOT_UPHELD','RESOLVED','NO_ACTION') then
      return jsonb_build_object('error','invalid',
        'reason','Upheld, Partly upheld, Not upheld, Resolved or No action.');
    end if;
    v_note := nullif(btrim(coalesce(p_in->>'note','')),'');
    if v_note is null then
      -- The constraint refuses it anyway; saying so here costs nothing and
      -- the refusal is in words rather than a constraint name.
      return jsonb_build_object('error','invalid',
        'reason','Say what was decided and why. Both the person who raised it '
              || 'and the person it was about will read this.');
    end if;
    update person_escalation
       set state = 'CLOSED', closed_at = now(), closed_by = p_actor,
           outcome = v_outcome, outcome_note = v_note,
           seen_at = coalesce(seen_at, now())
     where id = p_id;
    insert into audit_entry (actor_id, action, entity_type, entity_ref,
                             old_value, new_value)
    values (p_actor, 'PERSON_ESCALATION_CLOSED', 'person', e.about_id::text,
            jsonb_build_object('state', e.state),
            jsonb_build_object('state','CLOSED','outcome', v_outcome));
    return jsonb_build_object('ok', true, 'changed', true, 'outcome', v_outcome,
      'note','Closed as ' || lower(replace(v_outcome,'_',' ')) ||
             '. It is now on ' ||
             (select full_name from person where id = e.about_id) ||
             '''s own panel, with what was decided. Upholding it is not a '
             'warning: if one is warranted, issue it.');
  end if;

  return jsonb_build_object('error','invalid',
    'reason','Seen, Close or Withdraw.');
end
$function$;

comment on function person_escalation_act(uuid, uuid, text, jsonb) is
  'Mark an escalation read, close it with an outcome, or withdraw it. '
  'Withdrawing is the raiser''s alone; closing is for whoever it went to, '
  'their line, HR and the administrator, and always carries a reason.';

-- =====================================================================
-- Reading them.
--
-- The one rule that is not obvious: while an escalation is OPEN or SEEN the
-- person it is about does not see it. An unexamined allegation shown to its
-- subject is how a question becomes a grievance.
-- =====================================================================
create or replace function person_escalation_list(p_actor uuid, p_person uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare a person; v_wide boolean;
begin
  select * into a from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null then return '[]'::jsonb; end if;

  v_wide := a.app_role = 'ADMIN'
         or coalesce(a.department,'') = 'Human Resources'
         or perf_may_set(p_actor, p_person);

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', e.id, 'subject', e.subject, 'detail', e.detail,
             'kind', e.about_kind, 'state', e.state,
             'raisedAt', e.raised_at, 'dueOn', e.due_on,
             'overdue', e.state in ('OPEN','SEEN') and e.due_on < current_date,
             'raisedBy', rb.full_name,
             'routedTo', rt.full_name, 'routedToId', e.routed_to,
             'routeNote', e.route_note,
             'outcome', e.outcome, 'outcomeNote', e.outcome_note,
             'closedAt', e.closed_at, 'closedBy', cb.full_name,
             'mine', e.raised_by = p_actor,
             'mayAct', e.state in ('OPEN','SEEN')
                       and (e.routed_to = p_actor or v_wide),
             'mayWithdraw', e.raised_by = p_actor and e.state in ('OPEN','SEEN'))
           order by e.raised_at desc)
      from person_escalation e
      left join person rb on rb.id = e.raised_by
      left join person rt on rt.id = e.routed_to
      left join person cb on cb.id = e.closed_by
     where e.about_id = p_person
       and (v_wide
            or e.raised_by = p_actor
            or e.routed_to = p_actor
            -- The subject, once it has been decided and not before.
            or (p_actor = p_person and e.state in ('CLOSED','WITHDRAWN')))
  ), '[]'::jsonb);
end
$function$;

comment on function person_escalation_list(uuid, uuid) is
  'The escalations about one person that this reader is entitled to. The '
  'person themselves sees only the ones that have been closed or withdrawn: '
  'an unexamined allegation shown to its subject is a grievance, not a '
  'question.';

-- =====================================================================
-- The conduct panel gains them.
--
-- By substitution over the live body rather than by pasting person_conduct
-- again, so the parts nobody is changing cannot drift while being retyped.
-- =====================================================================
do $do$
declare src text; out_src text;
  v_anchor text := '       limit 1));' || chr(10) || 'end ';
begin
  select prosrc into src from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'person_conduct';
  if src is null then
    raise exception 'Migration 251: person_conduct is not there to change.';
  end if;
  if position('escalations' in src) > 0 then
    raise notice 'Migration 251: person_conduct already carries the escalations.';
    return;
  end if;
  if position(v_anchor in src) = 0 then
    raise exception 'Migration 251: the end of person_conduct is not where this '
                    'expects it, so a blind replace would be a silent no-op.';
  end if;
  out_src := replace(src, v_anchor,
    '       limit 1),' || chr(10) ||
    '    ''escalations'', person_escalation_list(p_actor, p_person),' || chr(10) ||
    '    ''mayRaise'', p_actor <> p_person);' || chr(10) || 'end ');
  execute 'create or replace function person_conduct(p_actor uuid, p_person uuid) '
       || 'returns jsonb language plpgsql stable security definer '
       || 'set search_path to ''public'' as ' || quote_literal(out_src);
end
$do$;

-- ------------------------------------------------------------- the guard
do $guard$
declare
  v_a uuid; v_b uuid; v_boss uuid; o jsonb; v_id uuid; n int;
begin
  select id into v_a from person
   where employment_status='ACTIVE' and superseded_by is null
     and manager_id is not null
     and coalesce(employee_type,'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
   limit 1;
  if v_a is null then
    raise notice 'Migration 251: nobody with a manager to check against.';
    return;
  end if;
  select manager_id into v_boss from person where id = v_a;
  select id into v_b from person
   where employment_status='ACTIVE' and superseded_by is null
     and id not in (v_a, v_boss)
     and coalesce(employee_type,'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
   limit 1;

  -- Nobody raises one about themselves.
  if person_escalation_raise(v_a, jsonb_build_object(
       'personId', v_a, 'subject','about me'))->>'error' is distinct from 'not_permitted' then
    raise exception 'Migration 251: somebody raised an escalation about themselves.';
  end if;
  -- And it needs a line somebody can recognise it by.
  if person_escalation_raise(v_b, jsonb_build_object(
       'personId', v_a, 'subject','  '))->>'error' is distinct from 'invalid' then
    raise exception 'Migration 251: an escalation with no subject was accepted.';
  end if;
  -- It routes to the subject's manager.
  if (select to_id from person_escalation_route(v_b, v_a)) is distinct from v_boss then
    raise exception 'Migration 251: an escalation did not route to the manager.';
  end if;
  -- And a step higher when the raiser IS that manager.
  if (select to_id from person_escalation_route(v_boss, v_a)) = v_boss then
    raise exception 'Migration 251: a manager was asked to answer their own '
                    'escalation.';
  end if;
  -- The panel carries them.
  o := person_conduct(v_boss, v_a);
  if not (o ? 'escalations') then
    raise exception 'Migration 251: the conduct panel does not carry the '
                    'escalations.';
  end if;
  raise notice 'person_escalation: an escalation can be raised about a person.';
end $guard$;
