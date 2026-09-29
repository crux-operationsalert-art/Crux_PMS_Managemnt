-- =====================================================================
-- 223 · The number climbs, and the target comes down
--
-- Asked for: "the urgent flow is from the bottom of the pyramid to the top
-- at Org end, which is everydays productivity or KPI numbers updated and
-- those numbers summing up and also vice versa, but only for targets, if
-- my manager updates my target it auto distributes evenly to all in my
-- team unless I edit and change it manually."
--
-- Three things, and two of them already existed.
--
-- WHAT WAS ALREADY THERE
--
-- perf_value() walks perf_assignment.rolls_into_id and adds a measure's own
-- filings to everything climbing into it. perf_accrual_kind() already
-- decides whether that is a sum or an average, and it decides it the right
-- way round: anything counted in %, score, rate or ratio is a LEVEL and is
-- averaged; everything else is a SUM. So "the numbers summing up" is
-- arithmetic this database has had since migration 190.
--
-- WHAT WAS MISSING, AND WHY NOTHING CLIMBED
--
-- Of the 364 measures seeded in migration 221, TEN climbed. Migration 221
-- linked a measure to its manager's measure of the same NAME, and the
-- registry does not name things that way. It names them per chair and
-- codes the family in the unit, after a middle dot:
--
--     Executive        Cases completed against target      · EX1
--     Team Leader      Daily target achievement            · D3
--     Branch Manager   Cases completed within TAT          · D3
--     Zonal Manager    Branches at or above plan           · D8
--
-- Those four are one pyramid and no two of them share a name. Two of them
-- share a code. So the link is by FAMILY, and where the family changes as
-- it goes up -- EX1 becomes D3 becomes D8 -- it changes by a map somebody
-- wrote down on purpose.
--
-- THE MAP IS A TABLE, NOT A GUESS
--
-- perf_rollup_map holds child family -> parent family. It is seeded below
-- with the chains the registry's own codes support, and every row carries
-- the sentence that justifies it. Where two families are the same code at
-- two levels -- a Team Leader's D3 into a Branch Manager's D3 -- no row is
-- needed: same code climbs into same code by default.
--
-- THIS MAP IS THE BUSINESS'S TO CORRECT. It is the one part of this
-- migration that is a judgement rather than a mechanism, and it is in a
-- table with a note on every row so that correcting it is an UPDATE and
-- not a deploy.
--
-- TARGETS, THE OTHER WAY
--
-- perf_target_set() sets one target and pushes it down. How it divides
-- depends on the same SUM/LEVEL question the roll-up asks, because the two
-- have to agree or a team's targets will not add up to their manager's:
--
--   SUM    a count. 600 cases across four people is 150 each.
--   LEVEL  a percentage. 95% across four people is 95% each, not 23.75%.
--
-- A share edited by hand is pinned -- target_source = 'MANUAL' -- and the
-- rest divide what is left. Set one person to 300 of the 600 and the other
-- three get 100 each. Nothing a person typed is ever overwritten by a
-- later cascade; that is the whole of "unless I edit and change it
-- manually".
--
-- DAILY, IN EVERY DEPARTMENT
--
-- Every seeded measure becomes DAILY. perf_due() already reads the cadence
-- and already rolls a due date off a Sunday or a holiday, so a person is
-- asked for one number per measure per working day and the org total moves
-- the moment they file it. The registry's own cadence said MONTHLY for all
-- 173, which is why nothing was ever due: a monthly measure falls due once,
-- on the closing date. The cadence stays a per-measure field, so a measure
-- that genuinely is monthly can be set back without touching anything else.
-- =====================================================================

-- --------------------------------------------------------- the family
create or replace function perf_family(p_unit text)
returns text
language sql
immutable
as $function$
  select nullif(btrim(split_part(coalesce(p_unit, ''), '·', 2)), '')
$function$;

comment on function perf_family(text) is
  'The measure family coded after the middle dot in a unit -- EX1, D3, R6. '
  'The registry names a measure per chair and codes what it is a member of '
  'here, which is the only thing that links a Branch Manager''s "Cases '
  'completed within TAT" to a Team Leader''s "Daily target achievement".';

-- ------------------------------------------------------------ the map
create table if not exists perf_rollup_map (
  child_family  text primary key,
  parent_family text not null,
  note          text not null,
  set_by        uuid references person(id),
  set_at        timestamptz not null default now()
);

comment on table perf_rollup_map is
  'Which measure family a family climbs into when the code changes going '
  'up. Same code into same code needs no row and is the default. This is a '
  'judgement about the business, not a mechanism: correcting it is an '
  'UPDATE here, never a deploy, and every row says why it is what it is.';

insert into perf_rollup_map (child_family, parent_family, note) values
  ('EX1','D3',  'An executive''s cases completed against target are what a Team Leader''s daily target achievement is made of.'),
  ('EX2','D8',  'Days filed by one person are what "team days filed" counts.'),
  ('EX3','D21', 'Work returned to an executive for correction is what a quality or error-rate score measures.'),
  ('D3', 'D8',  'A branch at or above plan is a branch whose daily target achievement held. The zone counts branches; the branch counts cases.'),
  ('D1', 'D1',  'TAT and SLA adherence keeps its code all the way to the Operations head.'),
  ('F4', 'F4b', 'Collection achievement at a branch is what the zone''s DSO against the Finance target is made of.'),
  ('R6', 'R8',  'Branch revenue achievement is what zone revenue achievement is made of.'),
  ('R8', 'R1',  'Zone revenue is what revenue against plan is made of.'),
  ('R1', 'CEO1','Revenue against plan is what company revenue against the board plan is made of.'),
  ('X2', 'X1',  'A branch''s expense against budget is part of the function''s cost against budget.'),
  ('X1', 'CEO2','Function cost against budget is part of company cost against budget.'),
  ('X3', 'CEO2','Cost per case is part of company cost against budget.'),
  ('HRE1','HRO1','An HR executive''s joiners on record are what the HR Operations head is measured on.'),
  ('HRE2','HRO4','An HR executive''s days filed are part of their team''s days filed.'),
  ('HRE3','HRO3','Work returned for correction in HR is part of nothing being left unactioned.'),
  ('K4', 'K1',  'Sales against target is what mandate renewal is built on.'),
  ('K5', 'HFO3','Nothing unactioned in sales is part of nothing unactioned in finance operations.'),
  ('M1', 'HFO4','MIS submitted on time by a Team Leader is part of the team''s filing record.'),
  ('F9', 'AC4', 'Claim accuracy against computed entitlement is part of reconciliation being current.'),
  ('G4', 'G4',  'Financial close within timeline keeps its code from Finance Operations up to the VP.'),
  ('D2', 'L1',  'Four-region delivery against plan is what EBITDA against plan rests on.'),
  ('D21','D21', 'Quality keeps its code at every level that carries one.'),
  ('D8', 'L1',  'Branches at or above plan is what EBITDA against plan rests on.')
on conflict (child_family) do nothing;

alter table perf_rollup_map enable row level security;
revoke all on table perf_rollup_map from public, anon, authenticated;

-- ------------------------------------------- where a target came from
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'perf_assignment'
                    and column_name = 'target_source') then
    alter table perf_assignment add column target_source text not null default 'SEEDED';
    alter table perf_assignment add constraint perf_assignment_target_source_check
      check (target_source in ('SEEDED','SHARED','MANUAL'));
  end if;
end $$;

comment on column perf_assignment.target_source is
  'SEEDED -- came from the chair registry and nobody has looked at it. '
  'SHARED -- a share of the manager''s target, divided by the cascade, and '
  'the cascade may divide it again. MANUAL -- somebody typed this number '
  'for this person, and no cascade will ever overwrite it.';

-- ------------------------------------------------------ which way is good
-- A measure is a FLOOR when a bigger number is better -- revenue against
-- plan, cases completed, a quality score -- and a CEILING when a smaller
-- one is: work returned for correction, an error rate, expense variance,
-- attrition, escalations.
--
-- This exists because the registry codes two of them under one family. At
-- Team Leader, D21 is "Error rate" and you want it near zero. At Branch
-- Manager, D21 is "Branch quality score" and you want it near a hundred.
-- Adding the first into the second, or dividing the second's target into
-- the first, produces a number that is not wrong so much as meaningless --
-- and build/test/test_flow.sql caught exactly that, with a 5% ceiling
-- overwritten by a 90% floor coming down the cascade.
--
-- So a chain stops where the direction changes, and says it stopped. That
-- is a fact about the registry to be corrected there, not something for
-- the engine to paper over.
create or replace function perf_direction(p_unit text)
returns text
language sql
immutable
as $function$
  select case when lower(coalesce(p_unit, ''))
                   ~ 'below|variance|returned|escalat|attrition|error|vacant|dso|days to'
              then 'CEILING' else 'FLOOR' end
$function$;

comment on function perf_direction(text) is
  'FLOOR when a bigger number is better, CEILING when a smaller one is. A '
  'measure never climbs into one facing the other way, and a target never '
  'cascades across the change: work returned and a quality score are not '
  'the same quantity even where the registry gives them one family code.';

-- ----------------------------------------------------------- the climb
-- Three things have to agree before one measure climbs into another:
-- the FAMILY, the DIRECTION, and the KIND. Each of the three was added
-- after the one before it let something meaningless through, and the last
-- one was found on the live data rather than in a test: a Branch
-- Manager's "% of cases within TAT" was climbing into the Managing
-- Director's "branches operational against plan", and the count cascading
-- back down had given sixty-three executives a target of 1.61.
--
-- The nearest person above this one, in the reporting line, who carries
-- this measure family. Nearest, not the direct manager: a level that does
-- not carry a family has to be climbed past rather than stopped at, and
-- stopping at the direct manager is what left 354 of 364 measures
-- climbing nowhere.
create or replace function perf_climb(p_cycle uuid, p_person uuid, p_family text,
                                     p_direction text, p_kind text)
returns uuid
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_up uuid := p_person; v_hops int := 0; v_into uuid;
begin
  if p_family is null then return null; end if;
  loop
    select manager_id into v_up from person
     where id = v_up and manager_id is not null and manager_id <> id;
    exit when v_up is null or v_hops >= 12;
    v_hops := v_hops + 1;

    select a.id into v_into
      from perf_assignment a
     where a.cycle_id = p_cycle
       and a.person_id = v_up
       and a.part_of_id is null
       and perf_family(a.unit) = p_family
       and perf_direction(a.unit) = p_direction
       and perf_accrual_kind(a.kpi_id, a.unit) = p_kind
     order by a.id limit 1;
    if v_into is not null then return v_into; end if;
  end loop;
  return null;
end $function$;

comment on function perf_climb(uuid,uuid,text,text,text) is
  'The assignment this one should climb into: the nearest person above in '
  'the reporting line who carries the named measure family, or nothing if '
  'the chain runs out.';

-- --------------------------------------------------------- the relink
--
-- Every measure climbs into the NEAREST person above it in the reporting
-- line who carries the family it climbs into. Nearest, not the direct
-- manager: a Branch Manager's D3 has to reach the Zonal Manager's D8 even
-- though the zone does not carry D3 itself, and stopping at the direct
-- manager is what left 354 of 364 measures climbing nowhere.
create or replace function perf_relink(p_actor uuid, p_cycle uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_role role_kind; r record; v_into uuid;
  v_linked int := 0; v_cleared int := 0; v_top int := 0;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Rebuilding the roll-up is an administrator''s.');
  end if;

  -- Start from nothing, so a run after the map is corrected is a rebuild
  -- and not an accumulation of two different opinions.
  update perf_assignment set rolls_into_id = null
   where cycle_id = p_cycle and rolls_into_id is not null;
  get diagnostics v_cleared = row_count;

  for r in
    select a.id, a.person_id, perf_family(a.unit) as fam,
           perf_direction(a.unit) as dir,
           perf_accrual_kind(a.kpi_id, a.unit) as kind,
           m.parent_family as mapped
      from perf_assignment a
      left join perf_rollup_map m on m.child_family = perf_family(a.unit)
                                 and m.parent_family <> perf_family(a.unit)
     where a.cycle_id = p_cycle
       and a.part_of_id is null
       and perf_family(a.unit) is not null
  loop
    -- Two passes up the manager chain, and the order is the whole of it.
    --
    -- The SAME family first. A Team Leader's D3 climbs into a Branch
    -- Manager's D3: same code, two levels, no map row needed and none
    -- wanted. Looking at the map first sent that one past its own parent
    -- to a grandparent's D8 and left it climbing nowhere, which is what
    -- build/test/test_flow.sql caught.
    --
    -- The MAPPED family second, and only when nobody above carries the
    -- same one. A Branch Manager's D3 has no D3 above it -- the zone
    -- counts branches, not cases -- so it takes the map's D8. A family can
    -- therefore climb through several levels of itself and change code
    -- once at the top, which is how the registry is actually written.
    v_into := null;
    v_into := perf_climb(p_cycle, r.person_id, r.fam, r.dir, r.kind);
    if v_into is null and r.mapped is not null then
      v_into := perf_climb(p_cycle, r.person_id, r.mapped, r.dir, r.kind);
    end if;

    if v_into is null then
      v_top := v_top + 1;
    else
      update perf_assignment set rolls_into_id = v_into where id = r.id;
      v_linked := v_linked + 1;
    end if;
  end loop;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, new_value)
  values (p_actor, 'PERF_ROLLUP_REBUILT', 'perf_cycle', p_cycle::text,
          jsonb_build_object('linked', v_linked, 'cleared', v_cleared, 'topOfAChain', v_top));

  return jsonb_build_object('ok', true, 'linked', v_linked,
    'cleared', v_cleared, 'topOfAChain', v_top,
    'note', v_linked || ' measure(s) now climb. ' || v_top ||
            ' are the top of their own chain, which is where a number stops.');
end $function$;

comment on function perf_relink(uuid,uuid) is
  'Rebuilds perf_assignment.rolls_into_id for one cycle from the family '
  'codes and perf_rollup_map. Each measure finds the nearest person above '
  'it in the reporting line who carries the family it feeds -- nearest, '
  'not the direct manager, because a level that does not carry a family '
  'must be climbed past rather than stopped at.';

-- ------------------------------------------------- the target, downwards
--
-- Divides the way the roll-up adds, or the two would disagree and a team's
-- targets would not reconcile with their manager's.
create or replace function perf_cascade(p_assignment uuid, p_depth int default 0)
returns int
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  a perf_assignment; kind text; r record;
  v_pinned numeric := 0; v_free int := 0; v_each numeric; v_n int := 0;
begin
  if p_depth > 12 then return 0; end if;
  select * into a from perf_assignment where id = p_assignment;
  if a.id is null or a.target_value is null then return 0; end if;

  kind := perf_accrual_kind(a.kpi_id, a.unit);

  select coalesce(sum(case when c.target_source = 'MANUAL'
                           then coalesce(c.target_value, 0) else 0 end), 0),
         count(*) filter (where c.target_source <> 'MANUAL')
    into v_pinned, v_free
    from perf_assignment c where c.rolls_into_id = a.id;

  if v_free = 0 then return 0; end if;

  if kind = 'SUM' then
    -- A count divides. What somebody pinned comes off the top first, so
    -- their number is honoured and the rest share what is actually left.
    v_each := round((a.target_value - v_pinned) / v_free, 2);
    if v_each < 0 then v_each := 0; end if;
  else
    -- A percentage does not divide. Ninety-five per cent across four
    -- people is ninety-five each; dividing it would ask each of them for a
    -- quarter of the standard.
    v_each := a.target_value;
  end if;

  for r in select c.id from perf_assignment c
            where c.rolls_into_id = a.id and c.target_source <> 'MANUAL'
  loop
    update perf_assignment
       set target_value = v_each, target_source = 'SHARED'
     where id = r.id;
    v_n := v_n + 1 + perf_cascade(r.id, p_depth + 1);
  end loop;

  return v_n;
end $function$;

comment on function perf_cascade(uuid,int) is
  'Pushes one target down the measures that climb into it, dividing a '
  'count and copying a percentage, and never touching a share somebody '
  'typed by hand. Returns how many shares moved.';

create or replace function perf_target_set(p_actor uuid, p_assignment uuid,
                                           p_value numeric, p_manual boolean default true)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare a perf_assignment; v_was numeric; v_moved int; v_up uuid; v_sib int;
begin
  select * into a from perf_assignment where id = p_assignment;
  if a.id is null then return jsonb_build_object('error','no_such_assignment'); end if;

  if not perf_may_set(p_actor, a.person_id) then
    return jsonb_build_object('error','not_permitted',
      'reason','A target is set by the person''s own manager. You see the '
               'progress of everyone below them; you set only your own team''s.');
  end if;

  v_was := a.target_value;
  update perf_assignment
     set target_value  = p_value,
         target_source = case when p_manual then 'MANUAL' else 'SHARED' end
   where id = p_assignment;

  -- Down: the team divides it.
  v_moved := perf_cascade(p_assignment);

  -- Sideways: a hand-typed share changes what is left for the others, so
  -- the parent divides again around it. Not upwards -- a manager's own
  -- target is not moved by what they gave somebody.
  if p_manual and a.rolls_into_id is not null then
    v_moved := v_moved + perf_cascade(a.rolls_into_id);
    select count(*) into v_sib from perf_assignment c
     where c.rolls_into_id = a.rolls_into_id and c.id <> a.id;
  end if;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_actor, 'PERF_TARGET_SET', 'perf_assignment', p_assignment::text,
          jsonb_build_object('target', v_was, 'source', a.target_source),
          jsonb_build_object('target', p_value,
                             'source', case when p_manual then 'MANUAL' else 'SHARED' end,
                             'sharesMoved', v_moved));

  return jsonb_build_object('ok', true, 'target', p_value,
    'sharesMoved', v_moved,
    'note', case
      when v_moved = 0 then 'Set. Nobody reports into this measure, so there was nothing to divide.'
      else 'Set, and divided across ' || v_moved || ' measure(s) below it. '
           || 'Anything typed by hand was left alone.' end);
end $function$;

comment on function perf_target_set(uuid,uuid,numeric,boolean) is
  'Sets one target and pushes it down the line. p_manual true pins it, so '
  'no later cascade overwrites it and the siblings redivide around it. The '
  'gate is perf_may_set: your own team, one step, and never yourself.';

revoke all on function perf_family(text)                        from public, anon, authenticated;
revoke all on function perf_direction(text)                     from public, anon, authenticated;
drop function if exists perf_climb(uuid,uuid,text,text);
revoke all on function perf_climb(uuid,uuid,text,text,text)     from public, anon, authenticated;
revoke all on function perf_relink(uuid,uuid)                   from public, anon, authenticated;
revoke all on function perf_cascade(uuid,int)                   from public, anon, authenticated;
revoke all on function perf_target_set(uuid,uuid,numeric,boolean) from public, anon, authenticated;
