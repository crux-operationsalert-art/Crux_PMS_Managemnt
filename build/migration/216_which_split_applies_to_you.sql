-- 216 · Which split applies to you
--
-- pms_weighting can be set for everybody, for a chair, or for one person, and
-- each row carries the date it takes effect from. The blueprint's "PMS
-- weighting · Admin and HR" panel writes to it; the Performance screen's three
-- score chips read it. Nothing yet answers the only question either of them
-- actually asks: what is MY split, today.
--
-- The order of precedence is the ordinary one -- a rule about you beats a rule
-- about your chair, which beats a rule about everybody -- and within each, the
-- most recent row that has already taken effect.
--
-- It can also answer "none yet", and that matters today. The Constitution V2.0
-- is effective 1 October 2026, and the only row in the table says so. Asked on
-- 29 September it returns applies=false with the date it starts, so the screen
-- can say "the scheme starts on 1 October" instead of inventing a split or
-- showing a blank chip. A tool that silently applies a rule that has not
-- started is worse than one that says it has not started.

create or replace function public.pms_weighting_for(p_person uuid, p_on date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $fn$
declare w pms_weighting; v_next date; v_scope text;
begin
  -- A rule about you.
  select * into w from pms_weighting
   where person_id = p_person and effective_from <= p_on
   order by effective_from desc limit 1;
  if w.id is not null then v_scope := 'you'; end if;

  -- Failing that, a rule about a chair you sit in. Somebody holding two
  -- chairs takes the later rule, which is the same tie-break as everywhere
  -- else here rather than a new one invented for this case.
  if w.id is null then
    select pw.* into w from pms_weighting pw
     where pw.chair_id is not null and pw.effective_from <= p_on
       and exists (select 1 from chair_holder h
                    where h.person_id = p_person and h.chair_id = pw.chair_id
                      and (h.to_date is null or h.to_date >= p_on))
     order by pw.effective_from desc limit 1;
    if w.id is not null then v_scope := 'your chair'; end if;
  end if;

  -- Failing that, the company.
  if w.id is null then
    select * into w from pms_weighting
     where scope_all and effective_from <= p_on
     order by effective_from desc limit 1;
    if w.id is not null then v_scope := 'everybody'; end if;
  end if;

  if w.id is not null then
    return jsonb_build_object(
      'applies', true, 'scope', v_scope,
      'kpiPercent', w.kpi_percent, 'attrPercent', w.attr_percent,
      'effectiveFrom', w.effective_from,
      'note', 'A monthly score is ' || w.kpi_percent || '% of the KPI score and '
              || w.attr_percent || '% of the Attribute score, both out of ten.');
  end if;

  -- Nothing has taken effect. Say when one does, if one is waiting.
  select min(pw2.effective_from) into v_next from pms_weighting pw2
   where pw2.effective_from > p_on
     and (pw2.scope_all or pw2.person_id = p_person
          or exists (select 1 from chair_holder h
                      where h.person_id = p_person and h.chair_id = pw2.chair_id));

  return jsonb_build_object(
    'applies', false, 'scope', null,
    'kpiPercent', null, 'attrPercent', null,
    'startsOn', v_next,
    'note', case when v_next is null
                 then 'No KPI/Attribute split has been set, so no monthly score can be worked out. '
                      || 'Admin or HR sets one on the Performance screen.'
                 else 'The scheme starts on ' || to_char(v_next, 'FMDD Month YYYY')
                      || '. Nothing is scored before then.' end);
end $fn$;

comment on function public.pms_weighting_for(uuid, date) is
  'The KPI/Attribute split that applies to one person on one day: a rule about '
  'them beats a rule about their chair, which beats a rule about everybody, and '
  'within each the most recent that has already taken effect. Answers '
  'applies=false with the date the scheme starts rather than inventing a split.';

grant execute on function public.pms_weighting_for(uuid, date) to authenticated;

-- ------------------------------------------------------------------ checks

do $do$
declare a jsonb; b jsonb; v_any uuid;
begin
  select id into v_any from person where employment_status = 'ACTIVE' and superseded_by is null limit 1;

  -- before the Constitution takes effect
  a := pms_weighting_for(v_any, date '2026-09-29');
  if (a->>'applies')::boolean then
    raise exception '216: a split applied before its own effective date';
  end if;
  if (a->>'startsOn') <> '2026-10-01' then
    raise exception '216: expected the scheme to start 2026-10-01, got %', a->>'startsOn';
  end if;

  -- after
  b := pms_weighting_for(v_any, date '2026-10-01');
  if not (b->>'applies')::boolean then
    raise exception '216: the company-wide split did not apply on the day it starts';
  end if;
  if (b->>'kpiPercent')::numeric <> 75 or (b->>'attrPercent')::numeric <> 25 then
    raise exception '216: the split resolved to %/%', b->>'kpiPercent', b->>'attrPercent';
  end if;
  if b->>'scope' <> 'everybody' then
    raise exception '216: expected the company-wide rule, got %', b->>'scope';
  end if;

  raise notice '216: the split resolves -- % before it starts, % after', a->>'note', b->>'scope';
end $do$;
