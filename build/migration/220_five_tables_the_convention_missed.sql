-- =====================================================================
-- 220 · Five tables the convention missed
--
-- Found by the project's own security advisor while working on the third
-- reported defect, not by looking for it.
--
--     perf_cycle, perf_assignment, perf_entry,
--     matrix_dispatch, person_document
--
-- have row level security OFF. Every other table in this database — 156 of
-- them — has it ON, and build/schema/70_rls.sql states why in its own
-- header:
--
--     "Row level security is on for nearly every table, and most of them
--      carry no policy at all. That is deliberate: the tool reaches the
--      database through SECURITY DEFINER functions and the service role,
--      so a table with RLS on and no policy is closed to anon and to
--      authenticated, which is what it should be."
--
-- These five were created after that convention settled and did not get
-- it. Nothing chose to exempt them.
--
-- WHY THIS IS THE SAME DEFECT AS 218, THROUGH A DIFFERENT DOOR
--
-- The publishable key is in the public repository on purpose — it names
-- the project and grants nothing on its own. It grants nothing because
-- every table is closed to it. These five were open to it, which means
-- perf_assignment and perf_entry — every person's KPIs, their targets,
-- and every number they have filed — could be read straight off
-- /rest/v1/perf_assignment by anybody at all, with no sign-in, bypassing
-- perf_line, perf_rel and every gate migration 218 put in.
--
-- Two things kept it from being a live breach: perf_assignment and
-- perf_entry are empty today, and the application never speaks to
-- PostgREST — index.html contains no /rest/v1 call at all; everything
-- goes through the Edge Functions, which connect with SUPABASE_DB_URL and
-- are unaffected by RLS.
--
-- The first of those two stops being true the moment the KPIs are
-- pre-uploaded, which is the very next thing being asked for. So this goes
-- first.
--
-- NO POLICIES, ON PURPOSE
--
-- The advisor's own note says enabling RLS without policies blocks all
-- access, and warns against applying it blind. Here that IS the intent and
-- it is checked, not assumed: the application makes no PostgREST call, and
-- the six Edge Functions hold a direct connection which RLS does not
-- apply to. Closed to anon and to authenticated is the correct state and
-- the state every neighbouring table is already in.
-- =====================================================================

alter table public.perf_cycle      enable row level security;
alter table public.perf_assignment enable row level security;
alter table public.perf_entry      enable row level security;
alter table public.matrix_dispatch enable row level security;
alter table public.person_document enable row level security;

-- Say it out loud on the two that would have carried real harm, so the
-- next person to look does not read the absence of a policy as an
-- oversight of the same kind this migration is fixing.
comment on table public.perf_assignment is
  'One KPI given to one person for one cycle: the target, when they file, '
  'which of their own measures it is a part of, and which of their '
  'manager''s measures it climbs into. RLS is on and carries no policy, '
  'which closes it to anon and to authenticated. That is deliberate and is '
  'what every other table here does: the tool reaches this row through '
  'SECURITY DEFINER functions that ask perf_rel who is allowed to see it.';

comment on table public.perf_entry is
  'One filing against one assignment for one day. as_of is the day the '
  'number is for; filed_at is when somebody typed it. RLS is on and '
  'carries no policy, which closes it to anon and to authenticated -- see '
  'perf_assignment.';

-- The check the advisory would have made. If a later migration turns one
-- of these back off, this fails the rebuild rather than waiting for the
-- advisor to notice again.
do $$
declare v_open text;
begin
  select string_agg(c.relname, ', ' order by c.relname) into v_open
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind = 'r'
     and not c.relrowsecurity
     and c.relname in ('perf_cycle','perf_assignment','perf_entry',
                       'matrix_dispatch','person_document');
  if v_open is not null then
    raise exception 'migration 220: % still open to the publishable key', v_open;
  end if;
end $$;
