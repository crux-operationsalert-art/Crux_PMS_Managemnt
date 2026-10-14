-- A quarterly save keeps the direction it was not sent, and the months view
-- says what the direction is
--
-- plb_sheet_measures_set (255) wrote direction = whatever the caller sent,
-- with absent read as "none". The quarterly editor builds its draft from
-- plb_kpi_months, which never returned a direction at all -- so every
-- "Save the measures" posted direction: null for every row and silently
-- wiped each one-up manager's choice of which way a measure points (253:
-- "the one up manager decides"), putting the registry's guess back. Change a
-- weight, lose a ceiling, and the bonus pays more for a worse number.
--
-- 255 already knew the rule for the month split -- "a form that carries no
-- split must not wipe a phasing somebody has already run" -- and coalesced
-- m1..m3 with the row's own value. Direction was the one field on that row
-- without the same care. Measured before this file: 0 of 724 live rows
-- carried an override, so nothing has been lost yet.
--
-- Two changes, both by substitution over the live body:
--   * plb_sheet_measures_set: a row that does not mention 'direction' keeps
--     its own. A row that sends it -- empty included -- sets it, so a manager
--     can still hand a measure back to the registry's suggestion.
--   * plb_kpi_months: returns 'direction' (the row's own, null when it
--     follows the registry) and 'suggests' (the registry's), so a screen can
--     show what is actually set rather than guess.
do $do$
declare src text; out_src text;
  v_old text := $a$             direction    = nullif(upper(btrim(coalesce(x->>'direction',''))),''),$a$;
  v_new text := $b$             -- 261: absent means keep, as m1..m3 below already do.
             direction    = case when x ? 'direction'
                                 then nullif(upper(btrim(coalesce(x->>'direction',''))),'')
                                 else g.direction end,$b$;
  v_m_old text := $c$'weight', r.weight, 'quarterly', r.quarterly,$c$;
  v_m_new text := $d$'weight', r.weight,
      -- 261: what is set on the row, and what the registry suggests.
      'direction', (select g.direction from plb_goal_kpi g where g.id = r.goal_kpi_id),
      'suggests', (select k.direction from kpi_definition k where k.id = r.kpi_id),
      'quarterly', r.quarterly,$d$;
  v_args text;
begin
  select prosrc, pg_get_function_identity_arguments(p.oid) into src, v_args
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'plb_sheet_measures_set';
  if src is null then raise exception 'Migration 261: plb_sheet_measures_set is not there.'; end if;
  if position('261: absent means keep' in src) > 0 then
    raise notice 'Migration 261: plb_sheet_measures_set already keeps the direction.';
  elsif position(v_old in src) = 0 then
    raise exception 'Migration 261: the direction line in plb_sheet_measures_set is '
                    'not where this expects it.';
  else
    out_src := replace(src, v_old, v_new);
    execute format('create or replace function public.plb_sheet_measures_set(%s) '
      'returns jsonb language plpgsql security definer set search_path to ''public'' as %L',
      v_args, out_src);
  end if;

  select prosrc, pg_get_function_identity_arguments(p.oid) into src, v_args
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'plb_kpi_months';
  if src is null then raise exception 'Migration 261: plb_kpi_months is not there.'; end if;
  if position('261: what is set on the row' in src) > 0 then
    raise notice 'Migration 261: plb_kpi_months already returns the direction.';
  elsif position(v_m_old in src) = 0 then
    raise exception 'Migration 261: the measure object in plb_kpi_months is not '
                    'where this expects it.';
  else
    out_src := replace(src, v_m_old, v_m_new);
    execute format('create or replace function public.plb_kpi_months(%s) '
      'returns jsonb language plpgsql stable security definer set search_path to ''public'' as %L',
      v_args, out_src);
  end if;
end
$do$;
