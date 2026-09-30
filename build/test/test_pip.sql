-- A warning is a record; a PIP is a plan with dates (233)
--
-- These two are deliberately different shapes and the assertions hold
-- them apart: a warning is issued once and never edited, and a plan is
-- edited constantly but can only be closed with a reason.
--
-- The one that matters most is the reviews. "PIP planned reviews" is the
-- part that gets skipped, and a plan with a review DATE has one review
-- that gets missed. These prove the reviews are rows, booked when the
-- plan opens, and that closing with some unheld says so.
--
-- Runs inside a transaction that is rolled back.

begin;

do $seed$
declare p_bm uuid; p_ex uuid; p_hr uuid; p_other uuid;
begin
  insert into person (full_name, work_email, department, app_role)
    values ('PP HR','pp.hr@example.invalid','Human Resources','MANAGER')
    returning id into p_hr;
  insert into person (full_name, work_email) values ('PP Branch','pp.bm@example.invalid')
    returning id into p_bm;
  insert into person (full_name, work_email, manager_id)
    values ('PP Exec','pp.ex@example.invalid', p_bm) returning id into p_ex;
  insert into person (full_name, work_email) values ('PP Other','pp.other@example.invalid')
    returning id into p_other;
end $seed$;

do $t$
declare
  p_bm uuid; p_ex uuid; p_hr uuid; p_other uuid;
  o jsonb; n int; v_plan uuid; v_rev uuid; v_w uuid;
begin
  select id into p_bm from person where work_email='pp.bm@example.invalid';
  select id into p_ex from person where work_email='pp.ex@example.invalid';
  select id into p_hr from person where work_email='pp.hr@example.invalid';
  select id into p_other from person where work_email='pp.other@example.invalid';

  -- ==================================================== who may act
  if hr_may_discipline(p_bm, p_ex) and hr_may_discipline(p_hr, p_ex)
    then raise notice 'PASS  a manager and HR may both discipline';
    else raise exception 'FAIL  the manager or HR was refused'; end if;

  if not hr_may_discipline(p_ex, p_ex)
    then raise notice 'PASS  and nobody warns themselves';
    else raise exception 'FAIL  a person could warn themselves'; end if;

  if not hr_may_discipline(p_other, p_ex)
    then raise notice 'PASS  nor does a stranger reach into somebody else''s team';
    else raise exception 'FAIL  a stranger could issue a warning'; end if;

  -- ======================================================= the warning
  o := person_warn(p_bm, jsonb_build_object('personId', p_ex,
        'level','WRITTEN','subject','Numbers not filed for six working days',
        'detail','Agreed to file daily by 6pm from Monday.','aboutKind','KPI'));
  if (o->>'ok')::boolean
    then raise notice 'PASS  a written warning is issued and recorded';
    else raise exception 'FAIL  the warning was refused: %', left(o::text,160); end if;
  v_w := (o->>'warningId')::uuid;

  o := person_warn(p_bm, jsonb_build_object('personId', p_ex, 'level','WRITTEN'));
  if o->>'error' = 'missing_subject'
    then raise notice 'PASS  a warning with nothing written on it is refused';
    else raise exception 'FAIL  an empty warning was accepted'; end if;

  o := person_warn(p_bm, jsonb_build_object('personId', p_ex,
        'level','SEVERE','subject','x'));
  if o->>'error' = 'unknown_level'
    then raise notice 'PASS  and only verbal, written or final are warnings';
    else raise exception 'FAIL  an invented level was accepted'; end if;

  if exists (select 1 from person_event
              where person_id = p_ex and kind = 'WARNING_ISSUED')
    then raise notice 'PASS  it lands on the person''s own record, not only in an audit log';
    else raise exception 'FAIL  no person_event was written'; end if;

  -- ============================================================ the PIP
  o := pip_open(p_bm, jsonb_build_object('personId', p_ex,
        'concern','Cases completed has been under half of target for two months',
        'expectation','At or above 90% of the monthly target for two consecutive months',
        'support','Weekly sit-down with the team leader, and the backlog re-queued',
        'startsOn', (current_date)::text,
        'endsOn', (current_date + 60)::text,
        'reviewEveryDays', 14));
  if (o->>'ok')::boolean and (o->>'reviews')::int = 5
    then raise notice 'PASS  a sixty-day plan books five reviews up front, not a reminder';
    else raise exception 'FAIL  the plan booked % reviews: %',
      coalesce(o->>'reviews','none'), left(o::text,200); end if;
  v_plan := (o->>'planId')::uuid;

  if (select due_on from pip_review where plan_id = v_plan
       order by seq desc limit 1) = current_date + 60
    then raise notice 'PASS  and the last one falls on the day the plan ends';
    else raise exception 'FAIL  the final review is not on the closing date'; end if;

  -- ---------------------------------------------- a plan needs both halves
  -- Against somebody IN the team: using p_other would have been refused by
  -- the permission gate first, which tests the gate and not this rule.
  o := pip_open(p_bm, jsonb_build_object('personId', p_ex, 'concern','x'));
  if o->>'error' = 'missing_detail'
    then raise notice 'PASS  a plan with a concern and no expectation is not a plan';
    else raise exception 'FAIL  a half-written plan was accepted'; end if;

  -- ------------------------------------------------- one plan at a time
  o := pip_open(p_hr, jsonb_build_object('personId', p_ex,
        'concern','something else','expectation','something else'));
  if o->>'error' = 'already_on_one'
    then raise notice 'PASS  nobody is on two plans at once';
    else raise exception 'FAIL  a second plan was opened'; end if;

  -- ========================================================= a review
  select id into v_rev from pip_review where plan_id = v_plan order by seq limit 1;
  o := pip_review_hold(p_bm, v_rev, 'AT_RISK', 'Filed on four of ten days.');
  if (o->>'ok')::boolean and (o->>'remaining')::int = 4
    then raise notice 'PASS  holding a review leaves four still unanswered';
    else raise exception 'FAIL  the review did not record: %', left(o::text,160); end if;

  o := pip_review_hold(p_bm, v_rev, 'FINE', 'x');
  if o->>'error' = 'missing_judgement'
    then raise notice 'PASS  a review says on track, at risk or off track -- not "fine"';
    else raise exception 'FAIL  an invented judgement was accepted'; end if;

  -- ------------------------------------------ what a tile would show
  o := person_conduct(p_bm, p_ex);
  if jsonb_array_length(o->'warnings') = 1
     and jsonb_array_length(o->'plan'->'reviews') = 5
     and (o->>'mayAct')::boolean
    then raise notice 'PASS  the tile reads one warning, a plan and its five reviews';
    else raise exception 'FAIL  the conduct read %', left(o::text,220); end if;

  o := person_conduct(p_ex, p_ex);
  if jsonb_array_length(o->'warnings') = 1 and not (o->>'mayAct')::boolean
    then raise notice 'PASS  the person sees their own warning and cannot issue one';
    else raise exception 'FAIL  the person''s own read was wrong'; end if;

  o := person_conduct(p_other, p_ex);
  if o->>'error' = 'not_permitted'
    then raise notice 'PASS  and somebody outside the line reads nothing at all';
    else raise exception 'FAIL  conduct leaked outside the reporting line'; end if;

  -- ========================================================= closing it
  o := pip_close(p_bm, v_plan, 'NOT_MET', null);
  if o->>'error' = 'missing_note'
    then raise notice 'PASS  "not met" with no reason is refused';
    else raise exception 'FAIL  a plan was failed without a reason'; end if;

  o := pip_close(p_bm, v_plan, 'NOT_MET', 'Filed on nine of forty working days.');
  if (o->>'ok')::boolean and (o->>'reviewsUnheld')::int = 4
    then raise notice 'PASS  closing early says how many reviews were never held';
    else raise exception 'FAIL  the close did not count unheld reviews: %',
      left(o::text,200); end if;

  if (select state from pip_plan where id = v_plan) = 'NOT_MET'
    then raise notice 'PASS  and the plan carries the outcome a person wrote';
    else raise exception 'FAIL  the state did not change'; end if;

  -- ---------------------------- and a closed plan frees the person
  o := pip_open(p_bm, jsonb_build_object('personId', p_ex,
        'concern','again','expectation','again'));
  if (o->>'ok')::boolean
    then raise notice 'PASS  once closed, a new plan may be opened';
    else raise exception 'FAIL  a closed plan still blocked a new one'; end if;

  raise notice '--- warnings and plans: every assertion passed ---';
end $t$;

rollback;
