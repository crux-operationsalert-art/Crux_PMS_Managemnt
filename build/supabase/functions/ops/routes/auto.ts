// Automations — the wireframe the design asks for, and the truth beside it.
//
// The design's screen draws every automation as a chain of four stages:
// trigger → conditions → actions → notifies, with the guard stated beside it.
// That is what `automation` holds — 49 of them, loaded from
// build/data/automations.json by migration 141.
//
// But a documented automation and a running one are different things, and a
// screen that showed only the first would be a brochure. So the second half of
// this is job_config and job_run: what is scheduled, and what has actually
// run. They do not agree, and the screen says so rather than smoothing it
// over — six of the seven configured jobs have never run under their own name,
// and one key that is in no configuration at all has run over a thousand
// times.
import { Router, many, one } from "../shim.ts";
import { requireChair } from "../scope.ts";
const r = Router();

r.get("/", requireChair, async (_req: any, res: any) => {
  const [designed, jobs, recent, orphans, tally] = await Promise.all([
    many(
      `select key, title, grp, owner, state, fires_on,
              trigger_on, conditions, actions, notifies, guard,
              enabled, disabled_reason
         from automation
        order by grp, key`),

    // What is configured to run, with whatever history carries its own key.
    many(
      `select c.job_key, c.enabled, c.cron, c.reason,
              (select count(*)::int from job_run r where r.job_key = c.job_key) as runs,
              (select max(r.started_at) from job_run r where r.job_key = c.job_key) as last_run,
              (select r.state from job_run r where r.job_key = c.job_key
                order by r.started_at desc limit 1) as last_state,
              (select r.error from job_run r where r.job_key = c.job_key
                order by r.started_at desc limit 1) as last_error
         from job_config c
        order by c.job_key`),

    // The last day of runs, whatever the key, with the counts each one wrote.
    many(
      `select job_key, started_at, finished_at, state, counts, error
         from job_run
        where started_at > now() - interval '24 hours'
        order by started_at desc limit 40`),

    // A key with history and no configuration. This is not an error — it is
    // how the tool actually runs — but nothing named it until now.
    many(
      `select r.job_key, count(*)::int as runs, max(r.started_at) as last_run,
              (array_agg(r.state order by r.started_at desc))[1] as last_state
         from job_run r
        where not exists (select 1 from job_config c where c.job_key = r.job_key)
        group by r.job_key order by 2 desc`),

    one(
      `select (select count(*)::int from automation) as designed,
              (select count(*)::int from automation where enabled) as designed_live,
              (select count(*)::int from job_config) as configured,
              (select count(*)::int from job_config where enabled) as configured_on,
              (select count(*)::int from job_run) as runs_all,
              (select count(*)::int from job_config c
                where exists (select 1 from job_run r where r.job_key = c.job_key)) as configured_with_history,
              (select max(started_at) from job_run) as last_run_any`),
  ]);

  res.json({ designed, jobs, recent, orphans, tally });
});

export default r;
