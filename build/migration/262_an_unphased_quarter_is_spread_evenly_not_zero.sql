-- An unphased quarter is spread evenly, not read as nought a month
--
-- plb_kpi_months says what each month of a quarterly measure "should" be:
-- the quarter times that month's share, or -- "no split means the quarter is
-- spread evenly, which is what plb_phase_targets does" -- a third of it. It
-- tested for "no split" with v_share IS NULL. But m1_share..m3_share are
-- numeric(6,3) NOT NULL DEFAULT 0: an unphased measure carries 0/0/0, never
-- null, so the even branch could not run. Every unphased count measure was
-- told its month should be 0, and the screen marked the real monthly target
-- "doesn't match the quarter" -- measured live: 11 of 13 count measures on
-- a sample of October sheets, and all 724 quarterly rows are unphased.
--
-- "Not phased" is now what the schema says it is: the three shares adding to
-- nothing. A phased month with a share of 0 (a deliberately empty month) is
-- still 0, because then the three add to a hundred.
do $do$
declare src text; out_src text; v_args text;
  v_old text := $a$        when v_share is not null then round(r.quarterly * v_share / 100.0, 2)$a$;
  v_new text := $b$        -- 262: 0/0/0 is "not phased" (the column cannot be null).
        when coalesce(r.m1_share,0) + coalesce(r.m2_share,0) + coalesce(r.m3_share,0) > 0
          then round(r.quarterly * coalesce(v_share,0) / 100.0, 2)$b$;
begin
  select prosrc, pg_get_function_identity_arguments(p.oid) into src, v_args
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'plb_kpi_months';
  if src is null then raise exception 'Migration 262: plb_kpi_months is not there.'; end if;
  if position('262: 0/0/0 is' in src) > 0 then
    raise notice 'Migration 262: plb_kpi_months already spreads an unphased quarter.';
    return;
  end if;
  if position(v_old in src) = 0 then
    raise exception 'Migration 262: the implied-month line is not where this expects it.';
  end if;
  out_src := replace(src, v_old, v_new);
  execute format('create or replace function public.plb_kpi_months(%s) '
    'returns jsonb language plpgsql stable security definer set search_path to ''public'' as %L',
    v_args, out_src);
end
$do$;

do $guard$
declare n_zero int; n_sum int;
begin
  with s as (select s.id, p.manager_id b from plb_goal_sheet s join person p on p.id = s.person_id
              where p.manager_id is not null order by s.quarter desc limit 60),
       m as (select jsonb_array_elements(plb_kpi_months(s.b, s.id)->'measures') x from s)
  select count(*) filter (where x->>'kind' = 'SUM'),
         count(*) filter (where x->>'kind' = 'SUM' and (x->>'quarterly')::numeric > 0
                            and (x->'months'->0->>'implied')::numeric = 0
                            and coalesce((x->'months'->0->>'share')::numeric,0)
                              + coalesce((x->'months'->1->>'share')::numeric,0)
                              + coalesce((x->'months'->2->>'share')::numeric,0) = 0)
    into n_sum, n_zero from m;
  if n_zero > 0 then
    raise exception 'Migration 262: % unphased count measure(s) still read as 0 a month.', n_zero;
  end if;
  raise notice 'plb_kpi_months: % count measure(s) checked; none unphased reads as nought.', n_sum;
end $guard$;
