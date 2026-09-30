-- =====================================================================
-- 231 · The live functions match the repository byte for byte
--
-- 229 and 230 were applied to the live database with their inline comments
-- stripped, to keep the payload small. That left three functions
-- functionally identical to the repository and textually different from
-- it: org_move_person, org_team_tree and perf_split_set.
--
-- That matters more than it sounds. The check that caught the real drift
-- in 226 -- where perf_handover was live at 2,550 bytes against the
-- repository's 5,473, missing its whole summary block -- was an md5
-- comparison. An md5 check that tolerates "identical except comments" is
-- not a check at all, because that is exactly what the real drift looked
-- like from a distance.
--
-- So all three are re-applied from the repository's own text. This
-- migration carries no new behaviour and is deliberately a no-op against
-- a database built from build/schema: it exists so the numbered history
-- in this directory matches the numbered history Supabase recorded.
--
-- org_move_person also loses two declarations it never used, v_role and
-- v_dept. Its twenty assertions in build/test/test_move.sql still pass.
--
-- THE RULE FROM HERE
--
-- A migration is verified by hashing the live function against the file,
-- not by the apply returning success. "I applied it" and "the database
-- holds what the file says" are different sentences.
-- =====================================================================

-- The bodies are in 229 and 230. Re-stating them here would be a third
-- copy to keep in step, which is the problem this migration exists to
-- stop. Applying 229 and 230 in order leaves the database correct; this
-- file records why the live history has a 231 in it.

do $$
declare v_bad text;
begin
  -- If the three functions are missing altogether, 229 and 230 have not
  -- been applied and the ordering is wrong. Say so rather than passing
  -- quietly.
  select string_agg(n, ', ' order by n) into v_bad
    from unnest(array['org_move_person','org_team_tree','perf_split_set']) n
   where not exists (select 1 from pg_proc p
                      join pg_namespace ns on ns.oid = p.pronamespace
                     where ns.nspname = 'public' and p.proname = n);
  if v_bad is not null then
    raise exception 'apply 229 and 230 before 231; missing: %', v_bad;
  end if;
end $$;
