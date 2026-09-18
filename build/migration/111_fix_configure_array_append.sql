-- =====================================================================
-- 111 · Saving mail or WhatsApp settings always failed
--
--   v_changed := v_changed || 'provider';
--
-- With an untyped literal on the right, Postgres resolves || as
-- anyarray || anyarray and tries to read 'provider' as an array literal:
--
--   ERROR: malformed array literal: "provider"
--   DETAIL: Array value must start with "{" or dimension information.
--
-- It is array_append that was meant, and it says so.
--
-- Both mail_configure and wa_configure had it, so neither Save button had
-- ever worked. That is the whole reason mail was never configured: the
-- administrator would paste a key, press Save, get an error, and the
-- "Connect Gmail" step would then correctly report that no client secret
-- was stored — one failure reported as another.
--
-- The full replacement bodies are in the Supabase migration history under
-- fix_configure_array_append. The guard against it recurring is
-- cutover_check 'C-05 settings can actually be saved', which calls both
-- functions and asserts each returns the field it says it changed.
-- =====================================================================

-- the shape of the fix, in both functions:
--   -  v_changed := v_changed || 'provider';
--   +  v_changed := array_append(v_changed, 'provider');

do $$
declare v_bad text;
begin
  select string_agg(p.proname, ', ')
    into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prokind = 'f'
     and pg_get_functiondef(p.oid) ~ 'text\[\]'
     and pg_get_functiondef(p.oid) ~ '\|\|\s*''[a-z_]+''\s*;';
  if v_bad is not null then
    raise exception 'array append by || with an untyped literal is still present in: %', v_bad;
  end if;
end $$;
