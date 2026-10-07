-- An escalation about a person (migration 251)
--
-- "Raise an escalation about a person, not only a case."
--
-- The assertions are the design, said in SQL:
--
--   anybody may raise    -> not only managers; the person who hits the
--                           problem is usually outside the line
--   never about yourself -> that is a conversation with your manager
--   it routes up         -> to their manager, and a step higher when the
--                           raiser IS that manager
--   the subject waits    -> an open allegation is not shown to its subject
--   closing says how     -> an outcome and a reason, both
--   withdrawing is the raiser's, and only theirs
--
-- Everything is rolled back.

begin;

do $t$
declare
  p_top uuid; p_boss uuid; p_rep uuid; p_other uuid; p_hr uuid;
  o jsonb; v_id uuid; n int;
begin
  insert into person (full_name, work_email, app_role)
    values ('ES Top','es.top@example.invalid','MANAGER') returning id into p_top;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('ES Boss','es.boss@example.invalid','MANAGER', p_top) returning id into p_boss;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('ES Rep','es.rep@example.invalid','VIEWER', p_boss) returning id into p_rep;
  insert into person (full_name, work_email, app_role)
    values ('ES Other','es.other@example.invalid','VIEWER') returning id into p_other;
  insert into person (full_name, work_email, app_role, department)
    values ('ES HR','es.hr@example.invalid','MANAGER','Human Resources') returning id into p_hr;

  -- ------------------------------------------------------ never about yourself
  if person_escalation_raise(p_rep, jsonb_build_object(
       'personId', p_rep, 'subject','me'))->>'error' is distinct from 'not_permitted' then
    raise exception 'FAIL  somebody raised an escalation about themselves';
  end if;
  raise notice 'PASS  an escalation is about somebody else';

  -- --------------------------------------------------------- anybody may raise
  -- ES Other is in nobody's line and manages nobody. That is exactly the
  -- person this is for: a form only managers can reach leaves the commonest
  -- case unsaid.
  o := person_escalation_raise(p_other, jsonb_build_object(
         'personId', p_rep, 'subject','Did not hand over the file',
         'detail','Asked twice on the 3rd and the 5th.', 'kind','PROCESS'));
  if o->>'error' is not null then
    raise exception 'FAIL  somebody outside the line could not raise one: %', o;
  end if;
  v_id := (o->>'id')::uuid;
  raise notice 'PASS  anybody may raise one, in the line or out of it';

  -- ------------------------------------------------------------- it routes up
  if (o->>'routedTo')::uuid is distinct from p_boss then
    raise exception 'FAIL  it did not go to the manager of the person it is about';
  end if;
  if (select to_id from person_escalation_route(p_boss, p_rep)) is distinct from p_top then
    raise exception 'FAIL  a manager was asked to answer their own escalation '
                    'about their own report';
  end if;
  raise notice 'PASS  it goes to their manager, and a step higher when the '
               'raiser is that manager';

  if o->>'dueOn' is null then
    raise exception 'FAIL  an escalation with no clock is a thing that sits';
  end if;
  raise notice 'PASS  and it carries a date by which it is answered';

  -- -------------------------------------------------------- the subject waits
  if jsonb_array_length(person_escalation_list(p_rep, p_rep)) <> 0 then
    raise exception 'FAIL  an open escalation was shown to the person it is '
                    'about. That turns a question into a grievance.';
  end if;
  if jsonb_array_length(person_escalation_list(p_boss, p_rep)) <> 1 then
    raise exception 'FAIL  the manager it went to cannot see it';
  end if;
  if jsonb_array_length(person_escalation_list(p_other, p_rep)) <> 1 then
    raise exception 'FAIL  the person who raised it cannot see it';
  end if;
  if jsonb_array_length(person_escalation_list(p_hr, p_rep)) <> 1 then
    raise exception 'FAIL  Human Resources cannot see it';
  end if;
  raise notice 'PASS  the raiser, the manager and HR see it; the subject does not';

  -- ------------------------------------------------------------ closing it
  if person_escalation_act(p_other, v_id, 'CLOSE',
       jsonb_build_object('outcome','UPHELD','note','x'))->>'error'
     is distinct from 'not_permitted' then
    raise exception 'FAIL  the person who raised it closed it themselves';
  end if;
  if person_escalation_act(p_boss, v_id, 'CLOSE',
       jsonb_build_object('outcome','UPHELD'))->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  an escalation was closed with no reason given';
  end if;
  if person_escalation_act(p_boss, v_id, 'CLOSE',
       jsonb_build_object('outcome','SORTED','note','x'))->>'error'
     is distinct from 'invalid' then
    raise exception 'FAIL  an outcome nobody defined was accepted';
  end if;
  o := person_escalation_act(p_boss, v_id, 'CLOSE', jsonb_build_object(
         'outcome','PARTLY_UPHELD','note','The file was late; the two asks '
         || 'were on one day, not two.'));
  if o->>'error' is not null then
    raise exception 'FAIL  the manager it went to could not close it: %', o;
  end if;
  raise notice 'PASS  closing it is for whoever it went to, with an outcome '
               'and a reason';

  -- Upholding it is not a warning. Nothing on the record but the escalation.
  select count(*) into n from person_warning where person_id = p_rep;
  if n <> 0 then
    raise exception 'FAIL  closing an escalation as upheld issued a warning by '
                    'itself. A finding somebody has to sign is not a side '
                    'effect of a form.';
  end if;
  raise notice 'PASS  and upholding one is not, by itself, a warning';

  -- ----------------------------------------------- and now the subject reads it
  if jsonb_array_length(person_escalation_list(p_rep, p_rep)) <> 1 then
    raise exception 'FAIL  a decided escalation is still hidden from the person '
                    'it was about';
  end if;
  if (person_escalation_list(p_rep, p_rep)->0->>'outcomeNote') is null then
    raise exception 'FAIL  they are shown that it happened and not what was decided';
  end if;
  raise notice 'PASS  once it is decided, the person it was about reads it';

  -- ------------------------------------------------------------ withdrawing
  o := person_escalation_raise(p_other, jsonb_build_object(
         'personId', p_rep, 'subject','Raised in haste'));
  v_id := (o->>'id')::uuid;
  if person_escalation_act(p_boss, v_id, 'WITHDRAW')->>'error'
     is distinct from 'not_permitted' then
    raise exception 'FAIL  somebody else decided a thing was never worth raising';
  end if;
  if person_escalation_act(p_other, v_id, 'WITHDRAW')->>'error' is not null then
    raise exception 'FAIL  the person who raised it could not withdraw it';
  end if;
  if (select state from person_escalation where id = v_id) <> 'WITHDRAWN' then
    raise exception 'FAIL  withdrawing it did not take';
  end if;
  select count(*) into n from person_escalation where id = v_id;
  if n <> 1 then
    raise exception 'FAIL  withdrawing it erased it. A thing that was said was said.';
  end if;
  raise notice 'PASS  withdrawing is the raiser''s alone, and withdraws rather '
               'than erases';

  -- ----------------------------------------------- the panel carries them
  if not (person_conduct(p_boss, p_rep) ? 'escalations') then
    raise exception 'FAIL  the conduct panel does not carry the escalations';
  end if;
  raise notice 'PASS  and the conduct panel is where they are read';

  raise notice '--- escalating about a person: every assertion passed ---';
end $t$;

rollback;
