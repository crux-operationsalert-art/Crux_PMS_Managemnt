insert into app_setting (key, value, plain_language, group_name)
select s.key, s.value, 'Migrated from the API settings table.', 'clocks'
from setting s
where not exists (select 1 from app_setting a where a.key = s.key)
on conflict (key) do nothing;

insert into app_setting (key, value, plain_language, group_name) values
  ('pms_wkpi','70','How much of the final score comes from KPIs?','Performance and appraisal'),
  ('pms_window_open','1st 10:00','When does the appraisal window open?','Performance and appraisal'),
  ('pms_window_close','7th 19:00','When does the appraisal window close?','Performance and appraisal'),
  ('pms_self_by','2nd 18:00','By when must a person self-evaluate?','Performance and appraisal'),
  ('pms_review_hrs','48','Working hours a manager gets to review and score','Performance and appraisal'),
  ('pms_dispute_hrs','48','Working hours HR gets to close a disputed score','Performance and appraisal'),
  ('pms_exc_hrs','24','Working hours HR gets to answer a window exception','Performance and appraisal'),
  ('pms_exc_open','48','How long an exception keeps a window open','Performance and appraisal'),
  ('pms_esc_attr','1','Attribute points an escalation removes','Performance and appraisal'),
  ('pms_warn_attr','2','Attribute points a warning removes','Performance and appraisal'),
  ('pms_appr_attr','1','Attribute points an appreciation adds','Performance and appraisal'),
  ('pms_idea_attr','2','Attribute points an approved idea adds','Performance and appraisal'),
  ('pms_esc_kpi','0.5','KPI points an escalation removes once Attributes hit zero','Performance and appraisal'),
  ('pms_warn_kpi','1','KPI points a warning removes once Attributes hit zero','Performance and appraisal'),
  ('pms_cut_cap','2','Most KPI points the cascade may remove in a month','Performance and appraisal'),
  ('pms_team_share','50','Share of a manager''s Attributes that comes from their team','Performance and appraisal'),
  ('pms_probation','5','Floor score for anybody on probation','Performance and appraisal'),
  ('pms_curve','5 / 15 / 60 / 15 / 5','Bell curve bands, best band first','Performance and appraisal'),
  ('pms_bottom_up','Yes','Must a manager close their team before their own window opens?','Performance and appraisal')
on conflict (key) do update set value = excluded.value;

comment on table app_setting is
  'Every tunable number, and the only copy. pms_* keys are read by the appraisal engine; a value that appears in application code instead of here is a defect.';

create or replace function pms_cfg(p_key text, p_default numeric)
returns numeric language sql stable set search_path = public as $$
  select coalesce(
    (select nullif(regexp_replace(value, '[^0-9.]', '', 'g'), '')::numeric
       from app_setting where key = p_key),
    p_default)
$$;

create or replace function working_hours_after(p_from timestamptz, p_hours numeric)
returns timestamptz language plpgsql stable set search_path = public as $$
declare
  cur   timestamptz := p_from;
  left_ numeric     := p_hours;
  open_h  int := coalesce((select split_part(value, ':', 1)::int from app_setting where key = 'day_start'), 10);
  close_h int := coalesce((select split_part(value, ':', 1)::int from app_setting where key = 'day_end'), 19);
  sat_h   numeric := pms_cfg('sat_hours', 4);
  sat_on  boolean := coalesce((select value ilike 'y%' from app_setting where key = 'sat'), true);
  day_cap numeric;
  avail   numeric;
begin
  while left_ > 0 loop
    if extract(dow from cur) = 0
       or (extract(dow from cur) = 6 and not sat_on)
       or exists (select 1 from holiday h where h.day = cur::date) then
      cur := date_trunc('day', cur) + interval '1 day' + (open_h || ' hours')::interval;
      continue;
    end if;
    day_cap := case when extract(dow from cur) = 6 then sat_h else close_h - open_h end;
    if cur::time < (open_h || ':00')::time then
      cur := date_trunc('day', cur) + (open_h || ' hours')::interval;
    end if;
    avail := least(day_cap, extract(epoch from ((date_trunc('day', cur) + ((open_h + day_cap) || ' hours')::interval) - cur)) / 3600.0);
    if avail <= 0 then
      cur := date_trunc('day', cur) + interval '1 day' + (open_h || ' hours')::interval;
      continue;
    end if;
    if left_ <= avail then
      return cur + (left_ || ' hours')::interval;
    end if;
    left_ := left_ - avail;
    cur := date_trunc('day', cur) + interval '1 day' + (open_h || ' hours')::interval;
  end loop;
  return cur;
end $$;

create or replace function pms_cycle_state(p_cycle uuid)
returns table (attr numeric, kpi numeric, cut numeric, held numeric)
language plpgsql stable set search_path = public as $$
declare rec record;
begin
  attr := coalesce((select raw from pms_component where cycle_id = p_cycle and kind = 'ATTRIBUTE'), 0);
  kpi  := coalesce((select raw from pms_component where cycle_id = p_cycle and kind = 'KPI'), 0);
  cut  := 0;
  held := coalesce((select sum(abs(a.points)) from pms_adjustment a
                     where a.cycle_id = p_cycle and not a.applied), 0);

  for rec in select a.points as pts, a.half as hf from pms_adjustment a
              where a.cycle_id = p_cycle and a.applied
              order by a.at, a.id loop
    if rec.hf = 'ATTRIBUTE' then
      attr := greatest(0, least(10, attr + rec.pts));
    else
      if rec.pts < 0 then cut := cut - rec.pts; end if;
      kpi := greatest(0, least(10, kpi + rec.pts));
    end if;
  end loop;
  return next;
end $$;

create or replace function pms_cascade_apply(
  p_cycle uuid, p_kind raisable_kind, p_source uuid, p_actor uuid, p_reason text)
returns table (half text, points numeric, applied boolean)
language plpgsql set search_path = public as $$
declare
  st record;
  v_down boolean := p_kind in ('ESCALATION','WARNING');
  v_size numeric;
  v_used numeric; v_over numeric; v_want numeric; v_room numeric;
  v_kc numeric := 0; v_blocked numeric := 0; v_kb numeric := 0;
  c_cap numeric := pms_cfg('pms_cut_cap', 2);
begin
  select * into st from pms_cycle_state(p_cycle);

  v_size := case p_kind
              when 'ESCALATION'   then pms_cfg('pms_esc_attr', 1)
              when 'WARNING'      then pms_cfg('pms_warn_attr', 2)
              when 'APPRECIATION' then pms_cfg('pms_appr_attr', 1)
              else                     pms_cfg('pms_idea_attr', 2)
            end;

  if v_down then
    v_used := least(st.attr, v_size);
    v_over := v_size - v_used;
    if v_over > 0 then
      v_want := (v_over / v_size) * case p_kind when 'ESCALATION'
                                      then pms_cfg('pms_esc_kpi', 0.5)
                                      else pms_cfg('pms_warn_kpi', 1) end;
      v_room := greatest(0, c_cap - st.cut);
      v_kc := least(v_want, v_room);
      v_blocked := v_want - v_kc;
    end if;

    if v_used > 0 then
      insert into pms_adjustment (cycle_id, source_kind, source_id, half, points, reason, actor_id, applied)
      values (p_cycle, p_kind, p_source, 'ATTRIBUTE', -v_used, p_reason, p_actor, true);
      half := 'ATTRIBUTE'; points := -v_used; applied := true; return next;
    end if;
    if v_kc > 0 then
      insert into pms_adjustment (cycle_id, source_kind, source_id, half, points, reason, actor_id, applied)
      values (p_cycle, p_kind, p_source, 'KPI', -v_kc,
              p_reason || ' - Attributes were already at zero', p_actor, true);
      half := 'KPI'; points := -v_kc; applied := true; return next;
    end if;
    if v_blocked > 0.001 then
      insert into pms_adjustment (cycle_id, source_kind, source_id, half, points, reason,
                                  actor_id, applied, capped, over_cap)
      values (p_cycle, p_kind, p_source, 'KPI', -v_blocked,
              p_reason || ' - beyond the ' || c_cap || '-point monthly cap; recorded and flagged to HR rather than taken off the score',
              p_actor, false, true, true);
      half := 'KPI'; points := -v_blocked; applied := false; return next;
    end if;
  else
    v_used := least(10 - st.attr, v_size);
    v_over := v_size - v_used;
    if v_over > 0 then v_kb := least(10 - st.kpi, v_over); end if;

    if v_used > 0 then
      insert into pms_adjustment (cycle_id, source_kind, source_id, half, points, reason, actor_id, applied)
      values (p_cycle, p_kind, p_source, 'ATTRIBUTE', v_used, p_reason, p_actor, true);
      half := 'ATTRIBUTE'; points := v_used; applied := true; return next;
    end if;
    if v_kb > 0 then
      insert into pms_adjustment (cycle_id, source_kind, source_id, half, points, reason, actor_id, applied)
      values (p_cycle, p_kind, p_source, 'KPI', v_kb,
              p_reason || ' - Attributes were already at ten', p_actor, true);
      half := 'KPI'; points := v_kb; applied := true; return next;
    end if;
  end if;
  return;
end $$;

create or replace function pms_cycle_score(p_cycle uuid, p_include_team boolean default true)
returns table (kpi numeric, attr numeric, final numeric, own numeric,
               cut numeric, held numeric, floored boolean, team_avg numeric)
language plpgsql stable set search_path = public as $$
declare
  st record;
  cy record;
  w_kpi numeric := pms_cfg('pms_wkpi', 70);
  share numeric := pms_cfg('pms_team_share', 50) / 100.0;
  floor_score numeric := pms_cfg('pms_probation', 5);
begin
  select * into cy from pms_cycle c where c.id = p_cycle;
  if not found then return; end if;
  select * into st from pms_cycle_state(p_cycle);

  kpi := st.kpi; own := st.attr; cut := st.cut; held := st.held;
  team_avg := null;

  if p_include_team then
    team_avg := pms_team_average(cy.person_id, cy.period);
    if team_avg is not null then
      attr := own * (1 - share) + team_avg * share;
    else
      attr := own;
    end if;
  else
    attr := own;
  end if;

  attr := greatest(0, least(10, attr));
  final := (kpi * w_kpi + attr * (100 - w_kpi)) / 100.0;

  floored := cy.on_probation and final < floor_score;
  if floored then final := floor_score; end if;
  return next;
end $$;

create or replace function pms_team_average(p_person uuid, p_period date)
returns numeric language sql stable set search_path = public as $$
  with recursive my_chair as (
    select ch.chair_id from chair_holder ch
     where ch.person_id = p_person and ch.to_date is null
  ), below as (
    select c.id from chair c join my_chair m on c.parent_id = m.chair_id
    union all
    select c.id from chair c join below b on c.parent_id = b.id
  ), ppl as (
    select distinct h.person_id from chair_holder h
      join below b on b.id = h.chair_id
     where h.to_date is null
  )
  select avg(s.final)
    from ppl p
    join pms_cycle cy on cy.person_id = p.person_id and cy.period = p_period
    cross join lateral pms_cycle_score(cy.id, false) s
$$;

comment on function pms_cascade_apply is
  'The cascade: Attributes absorb first and floor at zero, the remainder spills into KPI at that kind''s rate, and the month''s spill is capped. What the cap refuses is written with applied = false, never dropped.';