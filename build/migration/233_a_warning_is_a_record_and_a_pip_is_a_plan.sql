-- =====================================================================
-- 233 · A warning is a record; a PIP is a plan with dates
--
-- Asked for, on the team screen: "raise escalation, warning, put on PIP
-- and update the PIP form and those PIP planned reviews".
--
-- None of it existed. strike_event is the nearest thing and it is about a
-- CASE going wrong, not about a person. escalation_instance is the client
-- escalation matrix. So these are new, and they are deliberately two
-- different shapes because they are two different acts:
--
--   A WARNING IS A RECORD. It happened, it is dated, somebody issued it,
--   and it does not change again. Editing a warning after the fact is how
--   a disciplinary record stops being evidence of anything.
--
--   A PIP IS A PLAN. It has a start and an end, what "improved" means in
--   numbers, review dates set in advance, and an outcome written at the
--   end. It is edited constantly -- that is the point of it.
--
-- WHY THE REVIEWS ARE ROWS AND NOT A DATE FIELD
--
-- "Those PIP planned reviews" is the part people skip. A plan with a
-- review date is a plan with one review that gets missed; a plan whose
-- reviews are rows is a plan that can be asked "which of these has not
-- happened yet". So opening a PIP writes its review rows up front, and
-- each is completed with a note and a judgement of its own.
--
-- WHO MAY DO EITHER
--
-- The person they report to, or HR. Not the person themselves, and not a
-- manager two steps up reaching past somebody -- the same perf_may_set
-- rule the rest of the scheme uses, widened to HR because a disciplinary
-- record with no HR involvement is a liability rather than a process.
--
-- NOTHING HERE DECIDES ANYTHING ABOUT PAY
--
-- A PIP does not touch plb_result and a warning does not change a score.
-- Whether either should is a decision for the business, and wiring it in
-- silently would be making that decision on their behalf.
-- =====================================================================

create table if not exists person_warning (
  id            uuid primary key default gen_random_uuid(),
  person_id     uuid not null references person(id),
  issued_by     uuid not null references person(id),
  issued_at     timestamptz not null default now(),
  level         text not null check (level in ('VERBAL','WRITTEN','FINAL')),
  subject       text not null,
  detail        text,
  -- What it is about, when it is about something the tool already knows:
  -- a measure that was missed, a task not done. Free where it is not.
  about_kind    text check (about_kind in ('KPI','TASK','CONDUCT','ATTENDANCE','OTHER')),
  about_ref     uuid,
  acknowledged_at timestamptz,
  acknowledged_note text
);

comment on table person_warning is
  'A disciplinary warning about a person. A record, not a plan: it is '
  'issued once and never edited, because a warning that can be rewritten '
  'afterwards is not evidence of anything. The person may acknowledge it, '
  'and that acknowledgement is the only field they can touch.';

create index if not exists person_warning_person on person_warning(person_id, issued_at desc);

create table if not exists pip_plan (
  id            uuid primary key default gen_random_uuid(),
  person_id     uuid not null references person(id),
  opened_by     uuid not null references person(id),
  opened_at     timestamptz not null default now(),
  starts_on     date not null,
  ends_on       date not null,
  concern       text not null,
  expectation   text not null,
  support       text,
  state         text not null default 'OPEN'
                check (state in ('OPEN','EXTENDED','MET','NOT_MET','WITHDRAWN')),
  closed_at     timestamptz,
  closed_by     uuid references person(id),
  outcome_note  text,
  constraint pip_plan_dates check (ends_on > starts_on)
);

comment on table pip_plan is
  'A performance improvement plan: what the concern is, what improvement '
  'looks like, what support is offered, and the window it runs for. Edited '
  'throughout, unlike a warning, and closed with an outcome written by a '
  'person rather than computed.';

-- Only one plan may be running for a person at a time. Two overlapping
-- PIPs is not a stricter process, it is an unanswerable question about
-- which one they are on.
create unique index if not exists pip_plan_one_open
  on pip_plan(person_id) where state in ('OPEN','EXTENDED');

create table if not exists pip_review (
  id            uuid primary key default gen_random_uuid(),
  plan_id       uuid not null references pip_plan(id) on delete cascade,
  due_on        date not null,
  seq           int not null,
  held_at       timestamptz,
  held_by       uuid references person(id),
  note          text,
  judgement     text check (judgement in ('ON_TRACK','AT_RISK','OFF_TRACK')),
  unique (plan_id, seq)
);

comment on table pip_review is
  'One planned review inside a PIP, written when the plan opens rather '
  'than remembered later. A plan with a review DATE has one review that '
  'gets missed; a plan whose reviews are rows can be asked which of them '
  'has not happened.';

create index if not exists pip_review_due on pip_review(due_on) where held_at is null;

alter table person_warning enable row level security;
alter table pip_plan       enable row level security;
alter table pip_review     enable row level security;

-- ------------------------------------------------------ may I do this
create or replace function hr_may_discipline(p_actor uuid, p_person uuid)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $function$
  select p_actor <> p_person
     and (perf_may_set(p_actor, p_person)
          or exists (select 1 from person a
                      where a.id = p_actor
                        and a.employment_status = 'ACTIVE' and a.superseded_by is null
                        and (a.app_role = 'ADMIN'
                             or coalesce(a.department,'') = 'Human Resources')));
$function$;

comment on function hr_may_discipline(uuid,uuid) is
  'Whether this person may issue a warning to, or open a PIP on, that one: '
  'their reporting manager, HR, or an administrator, and never themselves.';

-- --------------------------------------------------------- the warning
create or replace function person_warn(p_actor uuid, p_in jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_person uuid; v_id uuid; v_level text;
begin
  v_person := nullif(p_in->>'personId','')::uuid;
  if v_person is null then return jsonb_build_object('error','missing_person'); end if;
  if not hr_may_discipline(p_actor, v_person) then
    return jsonb_build_object('error','not_permitted',
      'reason','A warning is issued by the person they report to, or by HR.');
  end if;
  v_level := upper(coalesce(p_in->>'level','WRITTEN'));
  if v_level not in ('VERBAL','WRITTEN','FINAL') then
    return jsonb_build_object('error','unknown_level',
      'reason','A warning is verbal, written or final.');
  end if;
  if coalesce(trim(p_in->>'subject'),'') = '' then
    return jsonb_build_object('error','missing_subject',
      'reason','A warning has to say what it is about.');
  end if;

  insert into person_warning (person_id, issued_by, level, subject, detail,
                              about_kind, about_ref)
  values (v_person, p_actor, v_level, trim(p_in->>'subject'), p_in->>'detail',
          nullif(upper(coalesce(p_in->>'aboutKind','OTHER')),''),
          nullif(p_in->>'aboutRef','')::uuid)
  returning id into v_id;

  insert into person_event (person_id, kind, note, at)
  values (v_person, 'WARNING_ISSUED', v_level || ': ' || trim(p_in->>'subject'), now());
  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor,'WARNING_ISSUED','person', v_person::text,
          jsonb_build_object('warningId', v_id, 'level', v_level));

  return jsonb_build_object('ok', true, 'warningId', v_id, 'level', v_level,
    'note','Issued and on the record. A warning is not edited afterwards; '
           'if it was wrong, issue the correction as its own record.');
end $function$;

comment on function person_warn(uuid,jsonb) is
  'Issues a warning. There is deliberately no function to edit one.';

-- ------------------------------------------------------------- the PIP
create or replace function pip_open(p_actor uuid, p_in jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_person uuid; v_id uuid; v_start date; v_end date;
  v_every int; v_n int := 0; d date; i int := 0;
begin
  v_person := nullif(p_in->>'personId','')::uuid;
  if v_person is null then return jsonb_build_object('error','missing_person'); end if;
  if not hr_may_discipline(p_actor, v_person) then
    return jsonb_build_object('error','not_permitted',
      'reason','A PIP is opened by the person they report to, or by HR.');
  end if;
  if coalesce(trim(p_in->>'concern'),'') = ''
     or coalesce(trim(p_in->>'expectation'),'') = '' then
    return jsonb_build_object('error','missing_detail',
      'reason','A PIP has to say what the concern is and what improvement '
               'would look like. A plan without both is not a plan.');
  end if;

  v_start := coalesce(nullif(p_in->>'startsOn','')::date, current_date);
  v_end   := coalesce(nullif(p_in->>'endsOn','')::date, v_start + 60);
  if v_end <= v_start then
    return jsonb_build_object('error','bad_dates',
      'reason','A PIP has to end after it starts.');
  end if;

  if exists (select 1 from pip_plan
              where person_id = v_person and state in ('OPEN','EXTENDED')) then
    return jsonb_build_object('error','already_on_one',
      'reason','That person is already on a plan. Close it before opening '
               'another, or extend the one they are on.');
  end if;

  insert into pip_plan (person_id, opened_by, starts_on, ends_on,
                        concern, expectation, support)
  values (v_person, p_actor, v_start, v_end,
          trim(p_in->>'concern'), trim(p_in->>'expectation'), p_in->>'support')
  returning id into v_id;

  -- The reviews are written now, not remembered later.
  v_every := greatest(7, coalesce(nullif(p_in->>'reviewEveryDays','')::int, 14));
  d := v_start + v_every;
  while d < v_end loop
    i := i + 1;
    insert into pip_review (plan_id, due_on, seq) values (v_id, d, i);
    v_n := v_n + 1;
    d := d + v_every;
  end loop;
  -- Always one on the last day, whatever the spacing worked out to.
  i := i + 1;
  insert into pip_review (plan_id, due_on, seq) values (v_id, v_end, i);
  v_n := v_n + 1;

  insert into person_event (person_id, kind, note, at)
  values (v_person, 'PIP_OPENED',
          'PIP ' || v_start || ' to ' || v_end || ', ' || v_n || ' reviews', now());
  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor,'PIP_OPENED','person', v_person::text,
          jsonb_build_object('planId', v_id, 'reviews', v_n,
                             'startsOn', v_start, 'endsOn', v_end));

  return jsonb_build_object('ok', true, 'planId', v_id, 'reviews', v_n,
    'startsOn', v_start, 'endsOn', v_end,
    'note', v_n || ' review(s) are already booked, the last on the day the '
            'plan ends. None of them is a reminder -- each is a row that '
            'stays unanswered until somebody holds it.');
end $function$;

comment on function pip_open(uuid,jsonb) is
  'Opens a performance improvement plan and books its reviews up front. '
  'One open plan per person, because two is an unanswerable question '
  'about which one they are on.';

create or replace function pip_review_hold(p_actor uuid, p_review uuid,
                                           p_judgement text, p_note text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_plan pip_plan; v_j text;
begin
  select pl.* into v_plan from pip_review r join pip_plan pl on pl.id = r.plan_id
   where r.id = p_review;
  if v_plan.id is null then return jsonb_build_object('error','no_such_review'); end if;
  if not hr_may_discipline(p_actor, v_plan.person_id) then
    return jsonb_build_object('error','not_permitted',
      'reason','That plan is not yours to review.');
  end if;
  v_j := upper(coalesce(p_judgement,''));
  if v_j not in ('ON_TRACK','AT_RISK','OFF_TRACK') then
    return jsonb_build_object('error','missing_judgement',
      'reason','A review says on track, at risk, or off track.');
  end if;

  update pip_review
     set held_at = now(), held_by = p_actor, judgement = v_j, note = p_note
   where id = p_review;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor,'PIP_REVIEW_HELD','pip_plan', v_plan.id::text,
          jsonb_build_object('reviewId', p_review, 'judgement', v_j));

  return jsonb_build_object('ok', true, 'judgement', v_j,
    'remaining', (select count(*) from pip_review
                   where plan_id = v_plan.id and held_at is null));
end $function$;

create or replace function pip_close(p_actor uuid, p_plan uuid,
                                     p_state text, p_note text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_plan pip_plan; v_s text; v_open int;
begin
  select * into v_plan from pip_plan where id = p_plan;
  if v_plan.id is null then return jsonb_build_object('error','no_such_plan'); end if;
  if not hr_may_discipline(p_actor, v_plan.person_id) then
    return jsonb_build_object('error','not_permitted',
      'reason','That plan is not yours to close.');
  end if;
  v_s := upper(coalesce(p_state,''));
  if v_s not in ('MET','NOT_MET','WITHDRAWN','EXTENDED') then
    return jsonb_build_object('error','unknown_outcome',
      'reason','A plan is met, not met, withdrawn, or extended.');
  end if;
  if v_s in ('MET','NOT_MET') and coalesce(trim(p_note),'') = '' then
    return jsonb_build_object('error','missing_note',
      'reason','Say why. "Not met" with no reason is not a decision '
               'anybody can stand behind later.');
  end if;

  select count(*) into v_open from pip_review
   where plan_id = p_plan and held_at is null;

  update pip_plan
     set state = v_s, outcome_note = p_note,
         closed_at = case when v_s = 'EXTENDED' then null else now() end,
         closed_by = case when v_s = 'EXTENDED' then null else p_actor end
   where id = p_plan;

  insert into person_event (person_id, kind, note, at)
  values (v_plan.person_id, 'PIP_' || v_s, coalesce(p_note,''), now());
  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor,'PIP_CLOSED','pip_plan', p_plan::text,
          jsonb_build_object('state', v_s, 'reviewsUnheld', v_open));

  return jsonb_build_object('ok', true, 'state', v_s, 'reviewsUnheld', v_open,
    'note', case when v_open > 0
      then 'Closed with ' || v_open || ' review(s) never held. That is on the '
           'record too.'
      else 'Closed, every review held.' end);
end $function$;

-- ------------------------------------------------- what a tile shows
create or replace function person_conduct(p_actor uuid, p_person uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
begin
  if perf_rel(p_actor, p_person) is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That person is not in your line.');
  end if;
  -- A person's own warnings and plan are theirs to see. A colleague's are
  -- not, and perf_rel has already decided that.
  return jsonb_build_object(
    'personId', p_person,
    'mayAct', hr_may_discipline(p_actor, p_person),
    'warnings', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', w.id, 'level', w.level, 'subject', w.subject,
               'detail', w.detail, 'issuedAt', w.issued_at,
               'issuedBy', (select full_name from person x where x.id = w.issued_by),
               'acknowledgedAt', w.acknowledged_at)
             order by w.issued_at desc)
        from person_warning w where w.person_id = p_person), '[]'::jsonb),
    'plan', (
      select jsonb_build_object(
               'id', pl.id, 'state', pl.state,
               'startsOn', pl.starts_on, 'endsOn', pl.ends_on,
               'concern', pl.concern, 'expectation', pl.expectation,
               'support', pl.support, 'outcome', pl.outcome_note,
               'reviews', coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'id', rv.id, 'seq', rv.seq, 'dueOn', rv.due_on,
                          'heldAt', rv.held_at, 'judgement', rv.judgement,
                          'note', rv.note,
                          'overdue', rv.held_at is null and rv.due_on < current_date)
                        order by rv.seq)
                   from pip_review rv where rv.plan_id = pl.id), '[]'::jsonb))
        from pip_plan pl
       where pl.person_id = p_person
       order by case when pl.state in ('OPEN','EXTENDED') then 0 else 1 end,
                pl.opened_at desc
       limit 1));
end $function$;

comment on function person_conduct(uuid,uuid) is
  'One person''s warnings and their current or most recent PIP, with each '
  'review and whether it is overdue. What the team tile opens.';

revoke all on function hr_may_discipline(uuid,uuid)                from public, anon, authenticated;
revoke all on function person_warn(uuid,jsonb)                     from public, anon, authenticated;
revoke all on function pip_open(uuid,jsonb)                        from public, anon, authenticated;
revoke all on function pip_review_hold(uuid,uuid,text,text)        from public, anon, authenticated;
revoke all on function pip_close(uuid,uuid,text,text)              from public, anon, authenticated;
revoke all on function person_conduct(uuid,uuid)                   from public, anon, authenticated;
