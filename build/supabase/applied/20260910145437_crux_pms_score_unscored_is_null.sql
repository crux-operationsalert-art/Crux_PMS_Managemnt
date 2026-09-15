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
  has_base boolean;
begin
  select * into cy from pms_cycle c where c.id = p_cycle;
  if not found then return; end if;
  select * into st from pms_cycle_state(p_cycle);

  select exists (select 1 from pms_component where cycle_id = p_cycle
                  and kind in ('KPI','ATTRIBUTE')) into has_base;
  if not has_base then
    kpi := null; attr := null; final := null; own := null;
    cut := st.cut; held := st.held; floored := false; team_avg := null;
    return next; return;
  end if;

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