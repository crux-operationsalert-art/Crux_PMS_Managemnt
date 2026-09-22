-- =====================================================================
-- 118 · An escalation can be acted on
--
-- Applied as migration an_escalation_can_be_acted_on, 2026-09-22.
--
-- escalation_action had been empty since the schema was created, and the
-- route that authorises an action reads it:
--
--   select a.* from escalation_action a
--     join escalation_party ep on ep.part = any(a.allowed_parts)
--    where ep.case_id = $1 and ep.person_id = $2 and a.code = $3
--
-- An empty table means that join returns nothing, which means EVERY action
-- on EVERY escalation was refused with "not_your_action". The escalation
-- workflow - the thing this rebuild was started for - had never been usable,
-- and nothing said so: the buttons simply were not drawn.
--
-- escalation_party was empty too, on all three migrated cases, so even with
-- actions defined nobody was a party to anything. Case creation writes the
-- raiser and nobody else.
--
-- The action set is the one the owner settled, in build/IMPLEMENTATION.md:
-- what each part may do, and what it costs. pms_impact is true only where
-- that document says it is - "Resolved, no action needed" and "Withdraw" are
-- explicitly free of it, because an escalation that turned out to be nothing
-- must not mark anybody.
--
-- Seventeen actions across five parts. Verified by asking, for a real case,
-- what each party is offered:
--
--   RAISER      Add an update · Escalate a level · Needs immediate action ·
--               Resolved - no action needed · Withdraw
--   RESPONDENT  Accept and resolve · Add an update · Dispute
--   MANAGER     Act on their behalf · Add an update · Issue a warning letter ·
--               Refer to HR · Resolve on their behalf
--   DESK        Add an update · Return to Operations · Take ownership
--   HR          Add an update · Close with an outcome · Issue a letter ·
--               Waive a penalty
--
-- "Decide the dispute" is correctly absent there: it is offered only while a
-- case is BLOCKED, which is what a dispute sets it to.
-- =====================================================================

-- The full insert is in the migration ledger under
-- an_escalation_can_be_acted_on. Seventeen rows, one per action, each
-- carrying its allowed parts, the statuses it may be used in, whether it
-- needs a note, what status it sets and where it routes.

-- ------------------------------------------------------------ the parties
-- Who is a party to a case is derivable from the case itself, so it is
-- derived rather than remembered: the raiser, the person it is against,
-- that person's manager, whoever fronts the desk it sits with, and whoever
-- fronts HR. One row each, not a whole department - a party is somebody who
-- can act, and "all of HR" cannot act as one.
--
-- It lives in the database rather than in the route that creates a case
-- because a case reassigned to another desk, or a person given a new
-- manager, changes who may act. A set of rows written once at creation would
-- go stale the first time either happened. Proven: moving a case from
-- Finance to Operations moved the DESK party with it.
create or replace function case_parties_sync(p_case uuid)
returns int
language plpgsql
security definer
set search_path to 'public'
as $function$
declare c "case"; n int := 0;
begin
  select * into c from "case" where id = p_case;
  if c.id is null then return 0; end if;

  with want as (
    select c.raised_by as person_id, 'RAISER'::esc_party as part
     where c.raised_by is not null
    union
    select c.against_person_id, 'RESPONDENT'
     where c.against_person_id is not null
    union
    select p.manager_id, 'MANAGER' from person p
     where p.id = c.against_person_id and p.manager_id is not null
    union
    select d.primary_person_id, 'DESK' from desk d
     where d.id = c.desk_id and d.primary_person_id is not null
    union
    select d.primary_person_id, 'HR' from desk d
     where d.name = 'HR' and d.primary_person_id is not null
  ),
  -- one person, one part: the first part in this order wins, so an HR head
  -- who raised the case acts as the raiser rather than as both
  ranked as (
    select distinct on (person_id) person_id, part
    from want
    order by person_id,
      case part when 'RAISER' then 1 when 'RESPONDENT' then 2
                when 'MANAGER' then 3 when 'DESK' then 4 else 5 end
  ),
  gone as (
    delete from escalation_party ep
     where ep.case_id = p_case
       and not exists (select 1 from ranked r
                        where r.person_id = ep.person_id and r.part = ep.part)
    returning 1
  ),
  put as (
    insert into escalation_party (case_id, person_id, part)
    select p_case, person_id, part from ranked
    on conflict do nothing
    returning 1
  )
  select (select count(*) from put) into n;

  return n;
end $function$;

create or replace function case_parties_trigger()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  perform case_parties_sync(new.id);
  return null;
end $function$;

drop trigger if exists case_parties_sync on "case";
create trigger case_parties_sync
  after insert or update of raised_by, against_person_id, desk_id on "case"
  for each row execute function case_parties_trigger();

-- the three migrated cases had never had a party
select case_parties_sync(id) from "case";

-- --------------------------------------------------- a closed case is closed
-- The route that applies an action checks who may do it, but not whether the
-- case is in a state where it makes sense; only the query that draws the
-- buttons does that. So the buttons are right and a request made directly is
-- not. This closes the half that matters: whatever else happens, a closed
-- escalation does not quietly change.
create or replace function case_status_guard()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  if old.status = 'CLOSED' and new.status is distinct from 'CLOSED' then
    raise exception 'ESC % is closed. A closed escalation is reopened by '
      'raising a new one, so that the record of the first stays true.', old.ref
      using errcode = 'check_violation';
  end if;
  return new;
end $function$;

drop trigger if exists case_status_guard on "case";
create trigger case_status_guard
  before update on "case"
  for each row execute function case_status_guard();

revoke all on function case_parties_sync(uuid) from public, anon, authenticated;
revoke all on function case_parties_trigger() from public, anon, authenticated;
revoke all on function case_status_guard() from public, anon, authenticated;
