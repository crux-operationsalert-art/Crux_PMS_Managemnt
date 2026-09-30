-- =====================================================================
-- 226 · A family maps only to the same quantity, and a chain that stops
--       hands over rather than disappearing
--
-- I over-mapped. Migration 223's perf_rollup_map has twenty rows and I
-- wrote them from the family codes and the levels they sit at, which is
-- not the same question as "do these two measure the same thing". Read
-- back against the registry's own names, more than half do not:
--
--   D3  -> D8    "Cases completed within TAT" into "Branches at or above
--                 plan". A percentage of CASES into a percentage of
--                 BRANCHES. Not the same quantity.
--   K4  -> K1    "Sales against target" into "Mandate renewal rate".
--                 Selling and renewing are different acts.
--   M1  -> HFO4  "MIS submitted on time" into "Team days filed".
--                 Filing a report and filing a number are not one thing.
--   D2  -> L1    "Four-region delivery against plan" into "EBITDA against
--                 plan". Delivery is not profit.
--   D8  -> L1    "Branches at or above plan" into EBITDA. The same error.
--   F4  -> F4b   "Branch collection achievement" (% of target) into "Zone
--                 DSO against the Finance target" (days). Collection and
--                 days-sales-outstanding are related and are not equal.
--   F9  -> AC4   "Claim accuracy" into "Bank reconciliation current".
--   X3  -> CEO2  "Cost per case" into "Company cost against budget", one
--                 a rupee figure and the other a variance.
--   HRE1-> HRO1  "Joiners on record from day one" into "Chairs with a
--                 named holder" -- when HRO2 IS "Joiners on record from
--                 day one", the very same measure, one level up. A plain
--                 mistake and the clearest one.
--   HRE3-> HRO3  "Work returned for correction" into "Nothing unactioned
--                 past its due date".
--
-- The direction and kind rules from 223 already made most of those inert:
-- a percentage never climbed into a count, a ceiling never into a floor.
-- Inert is not the same as right. A map row is a written claim about the
-- business and a wrong one left lying there will be believed by somebody.
--
-- THE RULE THE MAP NOW FOLLOWS
--
-- A family maps to another family when the two are THE SAME QUANTITY
-- MEASURED AT TWO SCOPES. Cases done by one person and cases done by a
-- team. Revenue at a branch and revenue in a zone. Days filed by a person
-- and days filed by their team. Not "related", not "contributes to", not
-- "sits above it in the chart": the same quantity.
--
-- Thirteen rows survive that test. The rest are deleted rather than
-- corrected, because there is nothing to correct them to.
--
-- A CHILD MAY NOW HAVE MORE THAN ONE PARENT
--
-- "Days filed" is the case that forced it. An executive's days filed roll
-- into their team's days filed -- which the registry gives THREE codes,
-- one per function: D8 for sales, HFO4 for finance operations, HRO4 for
-- HR operations. One row per child cannot say that. The key is now the
-- pair, with a priority, and perf_relink tries each in turn until one is
-- actually above the person. Nothing is guessed: whichever parent is in
-- their real reporting line is the one that takes it.
--
-- WHERE A CHAIN STOPS, THE CHAIR SEES WHAT STOPPED
--
-- Asked for: "if the managers or a layer or chair where the KPI changes
-- there the chair must see the roll up and then update his own."
--
-- That is exactly right, and it is better than any map I could write. A
-- Branch Manager's cases genuinely do not add into a Zonal Manager's count
-- of branches -- but the Zonal Manager absolutely should see every
-- branch's number before filing theirs, and then file theirs knowing it.
--
-- perf_handover() is that. For one person it returns, per direct report,
-- every measure of theirs that climbs nowhere: the name, the target, where
-- it has got to, and how far through it is. It is a briefing, not an
-- input. The chair reads it and files their own number, and the record
-- shows they had the numbers in front of them when they did.
--
-- This turns the registry's type changes from a defect into a step. A
-- number is carried up by arithmetic where the quantity is the same, and
-- by a person where it is not -- which is what actually happens in a
-- company, and what the old silent nulls were hiding.
-- =====================================================================

-- ------------------------------------------------ one child, several parents
do $$
begin
  if exists (select 1 from pg_constraint
              where conname = 'perf_rollup_map_pkey'
                and conrelid = 'perf_rollup_map'::regclass) then
    alter table perf_rollup_map drop constraint perf_rollup_map_pkey;
  end if;
end $$;

alter table perf_rollup_map
  add column if not exists priority int not null default 1;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'perf_rollup_map_pair'
                    and conrelid = 'perf_rollup_map'::regclass) then
    alter table perf_rollup_map
      add constraint perf_rollup_map_pair primary key (child_family, parent_family);
  end if;
end $$;

comment on column perf_rollup_map.priority is
  'Which parent to try first when a family has more than one. "Days filed" '
  'rolls into "team days filed", and the registry codes that three times -- '
  'D8 in sales, HFO4 in finance operations, HRO4 in HR. Whichever is '
  'actually above the person is the one that takes it; the priority only '
  'settles the order of asking.';

-- ------------------------------------------------------ start from nothing
-- Every row is re-stated below, so a corrected map is the whole map and
-- not the old one with patches on it.
delete from perf_rollup_map;

insert into perf_rollup_map (child_family, parent_family, priority, note) values
  -- ---------------------------------------------------------- work done
  ('EX1','D3',   1, 'An executive''s cases completed against target and a Team Leader''s daily target achievement are the same quantity: work finished against work asked for, one person and then their team.'),

  -- ------------------------------------------------------- days on record
  -- One child, three parents. The registry codes "team days filed" once
  -- per function and a person belongs to exactly one of them, so the
  -- reporting line picks rather than this table.
  ('EX2','D8',   1, 'Days filed by one person are what a Sales Manager''s "team days filed" counts.'),
  ('EX2','HFO4', 2, 'The same, where the line runs through Finance Operations.'),
  ('EX2','HRO4', 3, 'The same, where the line runs through HR Operations.'),
  ('HRE2','HRO4',1, 'An HR executive''s days filed are what the HR Operations head''s "team days filed" counts.'),

  -- -------------------------------------------------------------- quality
  ('EX3','D21',  1, 'Work returned to an executive for correction is what a Team Leader''s error rate counts. Both are a proportion of work that came back, and both want to be small.'),

  -- --------------------------------------------------------------- people
  ('HRE1','HRO2',1, 'The same measure, one level up: the HR executive and the HR Operations head are both measured on joiners being on record from day one. Migration 223 sent this to HRO1, "Chairs with a named holder", which is a different question entirely.'),

  -- -------------------------------------------------------------- backlog
  ('K5','HFO3',  1, 'Nothing unactioned past its due date, named identically at both levels.'),

  -- -------------------------------------------------------------- revenue
  ('R6','R8',    1, 'Branch revenue achievement is what zone revenue achievement is made of. The same rupees, counted at two scopes.'),
  ('R8','R1',    1, 'Zone revenue is what revenue against plan is made of.'),
  ('R1','CEO1',  1, 'Revenue against plan is what company revenue against the board plan is made of.'),

  -- ----------------------------------------------------------------- cost
  ('X2','X1',    1, 'A branch''s expense against budget is part of the function''s cost against budget. The same variance, counted at two scopes.'),
  ('X1','CEO2',  1, 'Function cost against budget is part of company cost against budget.');

-- A family whose code does not change on the way up needs no row at all:
-- perf_relink tries the same family first and always has. D1, D21, G4 and
-- D3 each appear at more than one level under their own code, and 223
-- carried rows saying so, which did nothing but suggest the default was
-- not the default.

comment on table perf_rollup_map is
  'Which measure family a family climbs into when the code changes going '
  'up. A row means the two are THE SAME QUANTITY AT TWO SCOPES -- not '
  '"related", not "contributes to", not "sits above it in the chart". '
  'Same code into same code needs no row and is the default. Where no row '
  'is right, the chain stops and perf_handover shows the chair what '
  'stopped below them, so the number is carried up by a person instead of '
  'by arithmetic. This is a judgement about the business: correcting it is '
  'an UPDATE here, never a deploy, and every row says why it is what it is.';

-- ----------------------------------------------- a rupee figure is a ceiling
-- "Cost per case", in INR against budget, wants to be small and read as a
-- floor because the words the pattern looks for were not in its unit.
create or replace function perf_direction(p_unit text)
returns text
language sql
immutable
as $function$
  select case when lower(coalesce(p_unit, ''))
                   ~ 'below|variance|returned|escalat|attrition|error|vacant|dso|days to|cost per|per case'
              then 'CEILING' else 'FLOOR' end
$function$;

comment on function perf_direction(text) is
  'FLOOR when a bigger number is better, CEILING when a smaller one is. A '
  'measure never climbs into one facing the other way, and a target never '
  'cascades across the change: work returned and a quality score are not '
  'the same quantity even where the registry gives them one family code.';

-- --------------------------------------------- perf_relink tries each parent
create or replace function perf_relink(p_actor uuid, p_cycle uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_role role_kind; r record; m record; v_into uuid;
  v_linked int := 0; v_cleared int := 0; v_top int := 0;
begin
  select app_role into v_role from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if v_role is distinct from 'ADMIN' then
    return jsonb_build_object('error','not_admin',
      'reason','Rebuilding the roll-up is an administrator''s.');
  end if;

  update perf_assignment set rolls_into_id = null
   where cycle_id = p_cycle and rolls_into_id is not null;
  get diagnostics v_cleared = row_count;

  for r in
    select a.id, a.person_id, perf_family(a.unit) as fam,
           perf_direction(a.unit) as dir,
           perf_accrual_kind(a.kpi_id, a.unit) as kind
      from perf_assignment a
     where a.cycle_id = p_cycle and a.part_of_id is null
       and perf_family(a.unit) is not null
  loop
    -- The same family first, always: a code that does not change on the
    -- way up needs no row and must not be sent past its own parent.
    v_into := perf_climb(p_cycle, r.person_id, r.fam, r.dir, r.kind);

    -- Then each mapped parent in turn, until one of them is actually
    -- above this person. A family with three parents is not three
    -- guesses: the reporting line picks, and at most one can be in it.
    if v_into is null then
      for m in select parent_family from perf_rollup_map
                where child_family = r.fam and parent_family <> r.fam
                order by priority, parent_family
      loop
        v_into := perf_climb(p_cycle, r.person_id, m.parent_family, r.dir, r.kind);
        exit when v_into is not null;
      end loop;
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
          jsonb_build_object('linked', v_linked, 'cleared', v_cleared,
                             'handedOver', v_top));

  return jsonb_build_object('ok', true, 'linked', v_linked, 'cleared', v_cleared,
    'handedOver', v_top,
    'note', v_linked || ' measure(s) climb by arithmetic. ' || v_top ||
            ' stop, and are handed to the chair above to read and answer in '
            'their own number.');
end $function$;

comment on function perf_relink(uuid,uuid) is
  'Rebuilds perf_assignment.rolls_into_id for one cycle: the same family '
  'first, then each mapped parent in priority order until one is actually '
  'in the person''s reporting line. What does not link is not lost -- '
  'perf_handover shows it to the chair above.';

-- ------------------------------------------------------------ the handover
--
-- What stopped below me. Per direct report, every measure of theirs that
-- climbs nowhere: what it is, what they were asked for, where they have
-- got to, and how far through that is.
--
-- A briefing, not an input. Nothing here writes anything. The chair reads
-- it and files their own number, and because they were shown it, the
-- number they file is an answer rather than a guess.
create or replace function perf_handover(p_actor uuid, p_cycle uuid,
                                         p_person uuid default null)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_who uuid; v_rel text;
begin
  v_who := coalesce(p_person, p_actor);
  v_rel := perf_rel(p_actor, v_who);
  if v_rel is null then
    return jsonb_build_object('error','not_permitted',
      'reason','That person is not in your line.');
  end if;

  return jsonb_build_object(
    'rel', v_rel,

    -- The summary first, and it is not a nicety. A Branch Manager with
    -- forty-two executives gets eighty-six numbers handed to them; a list
    -- of eighty-six is not a briefing, it is a wall. Grouped by measure
    -- there are three lines, each saying how the team stands and who is
    -- furthest from the mark -- which is what the person filing their own
    -- number actually needs to know.
    'summary', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', q.name, 'unit', q.unit, 'family', q.family,
               'direction', q.direction, 'kind', q.kind,
               'people', q.people, 'filed', q.filed,
               'target', q.target,
               'team', case when q.kind = 'SUM' then q.total else q.mean end,
               'best', case when q.direction = 'CEILING' then q.lo else q.hi end,
               'worst', case when q.direction = 'CEILING' then q.hi else q.lo end,
               'atOrAbove', q.made,
               'pct', case when coalesce(q.target,0) = 0 then null
                           else round(100.0
                                * (case when q.kind = 'SUM' then q.total else q.mean end)
                                / q.target, 1) end)
             order by q.name)
        from (
          select a.name, a.unit,
                 perf_family(a.unit) as family,
                 perf_direction(a.unit) as direction,
                 perf_accrual_kind(a.kpi_id, a.unit) as kind,
                 count(*) as people,
                 count(perf_value(a.id)) as filed,
                 avg(a.target_value) as target,
                 sum(perf_value(a.id)) as total,
                 avg(perf_value(a.id)) as mean,
                 min(perf_value(a.id)) as lo,
                 max(perf_value(a.id)) as hi,
                 count(*) filter (
                   where perf_value(a.id) is not null and a.target_value is not null
                     and ((perf_direction(a.unit) = 'CEILING'
                           and perf_value(a.id) <= a.target_value)
                       or (perf_direction(a.unit) = 'FLOOR'
                           and perf_value(a.id) >= a.target_value))) as made
            from perf_line(v_who) l
            join perf_assignment a on a.person_id = l.person_id
           where l.depth = 1
             and a.cycle_id = p_cycle
             and a.part_of_id is null
             and a.rolls_into_id is null
           group by a.name, a.unit, perf_family(a.unit),
                    perf_direction(a.unit), perf_accrual_kind(a.kpi_id, a.unit)
        ) q), '[]'::jsonb),

    'from', coalesce((
      select jsonb_agg(x order by x->>'name')
        from (
          select jsonb_build_object(
                   'personId', p.id,
                   'name', p.full_name,
                   'employeeNo', p.employee_no,
                   'chair', (select ch.title from chair_holder h
                              join chair ch on ch.id = h.chair_id
                             where h.person_id = p.id and h.to_date is null
                             order by h.is_primary desc limit 1),
                   'measures', coalesce((
                     select jsonb_agg(jsonb_build_object(
                              'assignmentId', a.id, 'name', a.name,
                              'unit', a.unit, 'family', perf_family(a.unit),
                              'direction', perf_direction(a.unit),
                              'kind', perf_accrual_kind(a.kpi_id, a.unit),
                              'target', a.target_value,
                              'value', perf_value(a.id),
                              'pct', case when coalesce(a.target_value,0) = 0 then null
                                          else round(100.0 * perf_value(a.id)
                                                     / a.target_value, 1) end,
                              'filings', (select count(*) from perf_entry e
                                           where e.assignment_id = a.id),
                              'lastFiled', (select max(e.as_of) from perf_entry e
                                             where e.assignment_id = a.id),
                              'feeders', (select count(*) from perf_assignment g
                                           where g.rolls_into_id = a.id))
                            order by a.name)
                       from perf_assignment a
                      where a.person_id = p.id
                        and a.cycle_id = p_cycle
                        and a.part_of_id is null
                        and a.rolls_into_id is null), '[]'::jsonb)) as x
            from perf_line(v_who) l
            join person p on p.id = l.person_id
           where l.depth = 1
             and exists (select 1 from perf_assignment a
                          where a.person_id = p.id and a.cycle_id = p_cycle
                            and a.part_of_id is null and a.rolls_into_id is null)
        ) q), '[]'::jsonb),
    'note', 'These numbers stop with the person who filed them, because what '
            'they measure is not what you are measured on. Read them, then '
            'file your own.');
end $function$;

comment on function perf_handover(uuid,uuid,uuid) is
  'What stopped below this person: per direct report, every measure of '
  'theirs that climbs nowhere, with where it has got to. A briefing before '
  'they file their own number, so a chain that the registry breaks is '
  'carried across by a person who was shown it rather than lost in a null.';

revoke all on function perf_direction(text)            from public, anon, authenticated;
revoke all on function perf_relink(uuid,uuid)          from public, anon, authenticated;
revoke all on function perf_handover(uuid,uuid,uuid)   from public, anon, authenticated;
