-- October 2026 branch targets, from the business sheet
--
-- The owner, 14 Oct: "Update the attached target for the month of October
-- + 10% to all the branch managers for their KPI of revenue, collection
-- would be revenue*2, TAT 2 days or 48 hours, quality 95%. Once this is
-- done follow the remaining climb up and down flow, do the division and
-- addition." Decisions taken with the owner the same day: rupee measures
-- replace the "% of target" ones; the seat-to-sheet mapping below; the
-- escalation-matrix mailer is held.
--
-- SOURCE. Business_Targets_Oct_2026.xlsx, sheet "Main Tracker": one row per
-- location and client, with zone subtotals and four regional totals over
-- them (each checked to add up exactly). Only the 36 leaf locations are
-- read, never a subtotal, or a branch is counted three times. Sheet total
-- Rs 3,35,89,000; with 10% Rs 3,69,47,900.
--
-- WHAT A BRANCH MANAGER NOW CARRIES (weights 30/25/15/15/15):
--   Branch revenue      rupees, the sheet x 1.1         (new, adds up)
--   Branch collection   rupees, revenue x 2             (new, adds up)
--   Turnaround time     hours, 48, lower is better      (new, a level)
--   Branch quality      % score, 95                     (new, a level)
--   and a fifth already there: "Branch expense against budget" -- or, for
--   the four with a team (Aniket Chalke, Avinash Chaskar, Shivakumar V, Sadu
--   Ambedkar), "Cases completed within TAT", which their team's 65 measures
--   roll into and which perf_assign_remove rightly refuses to withdraw
--   ("feeds_this"). A scorecard holds five.
--   "Branch revenue achievement" and "Branch collection achievement" (% of
--   target, 90) are withdrawn -- never deleted. Nothing had been filed on any.
--
-- DIVISION. The sheet says how each branch's revenue divides: by client.
-- Each becomes a CLIENT split under the branch's revenue (107 lines), so
-- the branch's number is the sum of its banks and nothing is filed twice.
-- Pune is split evenly between Avinash Chaskar and Parag Mayekar, client by
-- client. Manoj Batham carries the MP zone (Indore, Bhopal, Bilaspur,
-- Raipur, Gwalior); Firoz Islam Guwahati, Kolkata and Jharkhand.
--
-- ADDITION. Every branch's revenue and collection roll into Manish Shukla's
-- (Head of Operations), so what is filed in a branch climbs to him. His
-- targets are the whole sheet, not only the twelve seated branches: Rs
-- 3,69,47,900 and Rs 7,38,95,800. His "Revenue" was unit "% · X3" -- a
-- level, which would have AVERAGED the branches rather than adding them --
-- and is now rupees. Avinash's and Parag's halves both climb straight to
-- Manish rather than through Avinash, or Pune would be counted twice.
-- Every target is pinned (MANUAL), so no later cascade overwrites one.
--
-- NOT DONE, and why: Vinayak Jondale is seated "West", a zone, with no
-- branch of his own on the sheet -- his scorecard is untouched. 23 sheet
-- locations (Rs 1,53,29,820) have nobody in a Branch Manager chair; their
-- money is in Manish's target and on nobody's below it. Nitish Bhope
-- (Zonal) has no rupee measure, so the climb passes him.
--
-- Every write goes through the tool's own functions as the administrator
-- (perf_kpis_set, perf_assign, perf_assign_edit, perf_target_set), so every
-- rule they enforce -- three to five measures, weights to a hundred, a
-- target on everything, nothing removed that is filed against or fed -- is
-- enforced here too. Any refusal aborts the whole file.
do $do$
declare
  v_admin uuid := (select id from person where work_email = 'operations.alert@cruxindia.co.in');
  v_cycle uuid := (select id from perf_cycle where period_start = date '2026-10-01');
  v_chair uuid := (select id from chair where title = 'Branch Manager' order by id limit 1);
  v_rev_k uuid; v_col_k uuid; v_tat_k uuid; v_q_k uuid;
  v_m_rev uuid; v_m_col uuid; v_parag_exp uuid;
  d jsonb := $j$[{"name":"Parag Mayekar","revenue":"1683000.00","collection":"3366000.00","parts":[["LIC HFL","115500.00"],["SBI","594000.00"],["BOM","618750.00"],["BOM MSME PRE","110000.00"],["BOM MSME POST","13750.00"],["BOI","16500.00"],["BRT","59400.00"],["KARNATAKA BANK","4125.00"],["SVC","6600.00"],["IDBI Bank","144375.00"]]},
{"name":"Piyush Parmar","revenue":"740300.00","collection":"1480600.00","parts":[["SBI","514800.00"],["BOM","165000.00"],["BOM MSME PRE","27500.00"],["IDBI Bank","33000.00"]]},
{"name":"Shivakumar V","revenue":"2218150.00","collection":"4436300.00","parts":[["SBI","844800.00"],["LIC HFL","6600.00"],["BOI","134750.00"],["SVC","115500.00"],["CAN FIN HOMES","38500.00"],["IDBI Bank","594000.00"],["BOM","288750.00"],["BOM MSME PRE","82500.00"],["BOM MSME POST","13750.00"],["KARNATAKA BANK","55000.00"],["CANARA","44000.00"]]},
{"name":"Kapil Harwara","revenue":"528605.00","collection":"1057210.00","parts":[["SBI","480480.00"],["BOM","20625.00"],["BOM MSME PRE","27500.00"]]},
{"name":"Manoj Batham","revenue":"2111175.00","collection":"4222350.00","parts":[["BOM · Indore","123750.00"],["BOM MSME PRE · Indore","110000.00"],["IDBI Bank · Indore","49500.00"],["TOYOTA · Indore","3300.00"],["BOM · Bhopal","264000.00"],["BOM MSME PRE · Bhopal","82500.00"],["SBI · Bilaspur","440000.00"],["BOM · Bilaspur","16500.00"],["BOM MSME PRE · Bilaspur","55000.00"],["IDBI Bank · Bilaspur","61875.00"],["BOI · Bilaspur","8250.00"],["SBI · Raipur","660000.00"],["BOM · Raipur","99000.00"],["BOM MSME PRE · Raipur","55000.00"],["IDBI Bank · Raipur","16500.00"],["BOI · Raipur","16500.00"],["IDBI Bank · Gwalior","49500.00"]]},
{"name":"Shyam Sundar Kalta","revenue":"284625.00","collection":"569250.00","parts":[["BOM","185625.00"],["BOM MSME PRE","82500.00"],["IDBI Bank","16500.00"]]},
{"name":"Anish Bazmee","revenue":"3715800.00","collection":"7431600.00","parts":[["SBI","1848000.00"],["SBI Car Loan+","1320000.00"],["BOM","371250.00"],["BOM MSME PRE","137500.00"],["BOM MSME POST","13750.00"],["BOI","7700.00"],["SVC","13200.00"],["CAN FIN HOMES","4400.00"]]},
{"name":"Sadu Ambedkar","revenue":"1044450.00","collection":"2088900.00","parts":[["LIC HFL","290400.00"],["SVC","6600.00"],["CAN FIN HOMES","2200.00"],["BOI","16500.00"],["IDBI Bank","165000.00"],["BOM","412500.00"],["BOM MSME PRE","137500.00"],["BOM MSME POST","13750.00"]]},
{"name":"Aniket Chalke","revenue":"3697650.00","collection":"7395300.00","parts":[["LIC HFL","547800.00"],["SBI","1336500.00"],["AXIS BANK","27500.00"],["Axis Finace","5500.00"],["SVC","99000.00"],["DNSB","4400.00"],["Tezzract","16500.00"],["BOM","412500.00"],["BOM MSME PRE","220000.00"],["BOM MSME POST","27500.00"],["IDBI Bank","990000.00"],["CAN FIN HOMES","2200.00"],["KARNATAKA BANK","8250.00"]]},
{"name":"Firoz Islam","revenue":"3387175.00","collection":"6774350.00","parts":[["SBI · Guwahati Assam","1540000.00"],["BOM · Guwahati Assam","61875.00"],["BOM MSME PRE · Guwahati Assam","27500.00"],["BOM MSME POST · Guwahati Assam","6875.00"],["IDBI Bank · Guwahati Assam","16500.00"],["TOYOTA · Guwahati Assam","3300.00"],["SBI · Kolkata","561000.00"],["UNION · Kolkata","275000.00"],["BOI · Kolkata","220000.00"],["BOM · Kolkata","66000.00"],["BOM MSME PRE · Kolkata","27500.00"],["IDBI Bank · Kolkata","66000.00"],["SBI · Jharkhand","288750.00"],["BOM · Jharkhand","82500.00"],["BOM MSME PRE · Jharkhand","82500.00"],["IDBI Bank · Jharkhand","61875.00"]]},
{"name":"Avinash Chaskar","revenue":"1683000.00","collection":"3366000.00","parts":[["LIC HFL","115500.00"],["SBI","594000.00"],["BOM","618750.00"],["BOM MSME PRE","110000.00"],["BOM MSME POST","13750.00"],["BOI","16500.00"],["BRT","59400.00"],["KARNATAKA BANK","4125.00"],["SVC","6600.00"],["IDBI Bank","144375.00"]]},
{"name":"Dheeraj Khandelwal","revenue":"524150.00","collection":"1048300.00","parts":[["SBI","471900.00"],["BOM","16500.00"],["BOM MSME PRE","27500.00"],["IDBI Bank","8250.00"]]}]$j$;
  b jsonb; part jsonb; p uuid; o jsonb; lst jsonb; keep record; rr record; v_rev uuid;
  n_people int := 0; n_parts int := 0;
begin
  if v_admin is null or v_cycle is null or v_chair is null then
    raise exception 'Migration 264: administrator, October cycle or the Branch Manager chair is missing.';
  end if;

  -- 1. The registry
  insert into kpi_definition (chair_id, name, unit, direction, accrual, cadence, position, active, mandatory)
  select v_chair, x.name, x.unit, x.dir, x.acc::kpi_accrual, 'DAILY'::kpi_cadence, x.pos, true, true
    from (values ('Branch revenue',    'rupees · R6',                 'HIGHER', 'ADDS',     11),
                 ('Branch collection', 'rupees · F4',                 'HIGHER', 'ADDS',     12),
                 ('Turnaround time',   'hours, average per case · D3', 'LOWER', 'REPLACES', 13),
                 ('Branch quality',    '% score · D21',               'HIGHER', 'REPLACES', 14)) x(name, unit, dir, acc, pos)
   where not exists (select 1 from kpi_definition k where k.chair_id = v_chair and k.name = x.name);
  select id into v_rev_k from kpi_definition where chair_id = v_chair and name = 'Branch revenue';
  select id into v_col_k from kpi_definition where chair_id = v_chair and name = 'Branch collection';
  select id into v_tat_k from kpi_definition where chair_id = v_chair and name = 'Turnaround time';
  select id into v_q_k   from kpi_definition where chair_id = v_chair and name = 'Branch quality';

  -- 2. The top of the line: Manish Shukla, in rupees, the whole sheet
  select a.id into v_m_rev from perf_assignment a join person m on m.id = a.person_id
   where m.full_name = 'Manish Shukla' and a.cycle_id = v_cycle and a.name = 'Revenue'
     and a.part_of_id is null and a.state <> 'WITHDRAWN';
  select a.id into v_m_col from perf_assignment a join person m on m.id = a.person_id
   where m.full_name = 'Manish Shukla' and a.cycle_id = v_cycle and a.name = 'Collection'
     and a.part_of_id is null and a.state <> 'WITHDRAWN';
  if v_m_rev is null or v_m_col is null then
    raise exception 'Migration 264: Manish Shukla''s October Revenue and Collection are not there.';
  end if;
  o := perf_assign_edit(v_admin, jsonb_build_object('assignmentId', v_m_rev, 'unit', 'rupees · R6'));
  if o->>'error' is not null then raise exception 'Migration 264: Manish revenue unit: %', o; end if;
  o := perf_target_set(v_admin, v_m_rev, 36947900, true);
  if o->>'error' is not null then raise exception 'Migration 264: Manish revenue target: %', o; end if;
  o := perf_target_set(v_admin, v_m_col, 73895800, true);
  if o->>'error' is not null then raise exception 'Migration 264: Manish collection target: %', o; end if;

  -- 3. Parag's expense fed Avinash's; Pune is two halves side by side now
  select a.id into v_parag_exp from perf_assignment a join person x on x.id = a.person_id
   where x.full_name = 'Parag Mayekar' and a.cycle_id = v_cycle
     and a.name = 'Branch expense against budget' and a.state <> 'WITHDRAWN' and a.rolls_into_id is not null;
  if v_parag_exp is not null then
    o := perf_assign_edit(v_admin, jsonb_build_object('assignmentId', v_parag_exp, 'rollsInto', ''));
    if o->>'error' is not null then raise exception 'Migration 264: detaching Parag''s expense: %', o; end if;
  end if;

  -- 4. Each branch manager's scorecard, whole, through perf_kpis_set
  for b in select * from jsonb_array_elements(d) loop
    select id into p from person where full_name = b->>'name' and superseded_by is null;
    if p is null then raise exception 'Migration 264: % is not in person.', b->>'name'; end if;
    if exists (select 1 from perf_assignment where person_id = p and cycle_id = v_cycle
                and kpi_id = v_rev_k and state <> 'WITHDRAWN') then
      raise notice 'Migration 264: % already carries Branch revenue; left as it is.', b->>'name';
      continue;
    end if;
    lst := jsonb_build_array(
      jsonb_build_object('kpiId', v_rev_k, 'name', 'Branch revenue', 'unit', 'rupees · R6',
        'weight', 30, 'target', (b->>'revenue')::numeric, 'cadence', 'DAILY',
        'direction', 'HIGHER', 'rollsInto', v_m_rev),
      jsonb_build_object('kpiId', v_col_k, 'name', 'Branch collection', 'unit', 'rupees · F4',
        'weight', 25, 'target', (b->>'collection')::numeric, 'cadence', 'DAILY',
        'direction', 'HIGHER', 'rollsInto', v_m_col),
      jsonb_build_object('kpiId', v_tat_k, 'name', 'Turnaround time', 'unit', 'hours, average per case · D3',
        'weight', 15, 'target', 48, 'cadence', 'DAILY', 'direction', 'LOWER'),
      jsonb_build_object('kpiId', v_q_k, 'name', 'Branch quality', 'unit', '% score · D21',
        'weight', 15, 'target', 95, 'cadence', 'DAILY', 'direction', 'HIGHER'));
    -- the fifth: whatever the team feeds, else the expense measure
    select a.id, a.target_value, a.name into keep from perf_assignment a
     where a.person_id = p and a.cycle_id = v_cycle and a.part_of_id is null and a.state <> 'WITHDRAWN'
       and a.name = 'Cases completed within TAT'
       and exists (select 1 from perf_assignment x where x.rolls_into_id = a.id
                    and x.state <> 'WITHDRAWN' and x.person_id <> p);
    if keep.id is null then
      select a.id, a.target_value, a.name into keep from perf_assignment a
       where a.person_id = p and a.cycle_id = v_cycle and a.part_of_id is null and a.state <> 'WITHDRAWN'
         and a.name = 'Branch expense against budget';
    end if;
    if keep.id is not null then
      lst := lst || jsonb_build_array(jsonb_build_object('assignmentId', keep.id,
                       'weight', 15, 'target', coalesce(keep.target_value, 5)));
    else
      lst := lst || jsonb_build_array(jsonb_build_object('kpiId',
                       (select id from kpi_definition where name = 'Branch expense against budget' limit 1),
                       'name', 'Branch expense against budget', 'unit', '% variance · X2',
                       'weight', 15, 'target', 5, 'cadence', 'DAILY', 'direction', 'LOWER'));
    end if;
    -- A sub-KPI under a measure being replaced goes first: the tool will not
    -- take a measure off while it has parts. (Aniket Chalke's "SBI", typed by
    -- hand on 13 Oct under the % measure at Rs 12,15,000, is the sheet's
    -- September SBI; it is re-made below as October's, Rs 13,36,500.)
    -- perf_assign_remove refuses anything filed against.
    for rr in select x.id from perf_assignment x join perf_assignment pa on pa.id = x.part_of_id
               where pa.person_id = p and pa.cycle_id = v_cycle and pa.state <> 'WITHDRAWN'
                 and x.state <> 'WITHDRAWN'
                 and pa.name in ('Branch revenue achievement', 'Branch collection achievement') loop
      o := perf_assign_remove(v_admin, rr.id);
      if o->>'error' is not null then
        raise exception 'Migration 264: % sub-KPI could not be withdrawn: %', b->>'name', o;
      end if;
    end loop;
    o := perf_kpis_set(v_admin, v_cycle, p, lst);
    if o->>'error' is not null then
      raise exception 'Migration 264: % scorecard refused: %', b->>'name', o;
    end if;
    n_people := n_people + 1;

    -- A new row is SEEDED, and a seeded target is one the next cascade of
    -- Manish's figure would overwrite with an even share. These were typed
    -- from the sheet: pin them, before any client line goes under them.
    for rr in select a.id, a.target_value from perf_assignment a
               where a.person_id = p and a.cycle_id = v_cycle and a.part_of_id is null
                 and a.state <> 'WITHDRAWN' and a.kpi_id in (v_rev_k, v_col_k, v_tat_k, v_q_k) loop
      o := perf_target_set(v_admin, rr.id, rr.target_value, true);
      if o->>'error' is not null then
        raise exception 'Migration 264: % could not be pinned: %', b->>'name', o;
      end if;
    end loop;

    -- 5. Division: the branch's revenue, client by client
    select id into v_rev from perf_assignment where person_id = p and cycle_id = v_cycle
       and kpi_id = v_rev_k and part_of_id is null and state <> 'WITHDRAWN';
    for part in select * from jsonb_array_elements(b->'parts') loop
      o := perf_assign(v_admin, jsonb_build_object('cycleId', v_cycle, 'personId', p,
             'name', part->>0, 'unit', 'rupees · R6', 'target', (part->>1)::numeric,
             'cadence', 'DAILY', 'partOf', v_rev, 'splitKind', 'CLIENT', 'splitLabel', part->>0));
      if o->>'error' is not null then
        raise exception 'Migration 264: % / % refused: %', b->>'name', part->>0, o;
      end if;
      n_parts := n_parts + 1;
    end loop;
  end loop;
  raise notice 'Migration 264: % scorecard(s) set, % client line(s) under them.', n_people, n_parts;
end
$do$;

-- --------------------------------------------------------------- the proof
do $guard$
declare v_cycle uuid := (select id from perf_cycle where period_start = date '2026-10-01');
  n_bad int; v_sum numeric; v_n int;
begin
  -- every one of the twelve: five measures, weights 100, revenue = its parts,
  -- collection = twice revenue, both climbing to Manish
  with bm as (select id, full_name from person where full_name in ('Piyush Parmar','Shivakumar V',
         'Kapil Harwara','Manoj Batham','Shyam Sundar Kalta','Anish Bazmee','Sadu Ambedkar',
         'Aniket Chalke','Firoz Islam','Avinash Chaskar','Parag Mayekar','Dheeraj Khandelwal')),
  m as (select bm.full_name,
          (select count(*) from perf_assignment a where a.person_id = bm.id and a.cycle_id = v_cycle
             and a.part_of_id is null and a.state <> 'WITHDRAWN') n,
          (select round(sum(a.weight_pct), 2) from perf_assignment a where a.person_id = bm.id
             and a.cycle_id = v_cycle and a.part_of_id is null and a.state <> 'WITHDRAWN') w,
          r.target_value rev, r.rolls_into_id rev_up,
          (select sum(x.target_value) from perf_assignment x where x.part_of_id = r.id
             and x.state <> 'WITHDRAWN') parts,
          c.target_value col, c.rolls_into_id col_up,
          (r.target_source = 'MANUAL' and c.target_source = 'MANUAL') pinned
        from bm
        join perf_assignment r on r.person_id = bm.id and r.cycle_id = v_cycle and r.name = 'Branch revenue'
             and r.part_of_id is null and r.state <> 'WITHDRAWN'
        join perf_assignment c on c.person_id = bm.id and c.cycle_id = v_cycle and c.name = 'Branch collection'
             and c.part_of_id is null and c.state <> 'WITHDRAWN')
  select count(*) filter (where n <> 5 or w <> 100 or rev <> parts or col <> rev * 2
                            or rev_up is null or col_up is null or not pinned), count(*), sum(rev)
    into n_bad, v_n, v_sum from m;
  if v_n <> 12 then raise exception 'Migration 264: % of 12 scorecards carry the new measures.', v_n; end if;
  if n_bad > 0 then raise exception 'Migration 264: % scorecard(s) do not hold together.', n_bad; end if;
  if v_sum <> 21618080 then raise exception 'Migration 264: the twelve come to %, not 21618080.', v_sum; end if;
  if (select target_value from perf_assignment a join person p on p.id = a.person_id
       where p.full_name = 'Manish Shukla' and a.cycle_id = v_cycle and a.name = 'Revenue'
         and a.state <> 'WITHDRAWN') <> 36947900 then
    raise exception 'Migration 264: Manish''s revenue is not the sheet plus ten per cent.';
  end if;
  raise notice 'Migration 264: twelve branch scorecards hold together and add to Rs %; Manish carries the sheet.', v_sum;
end $guard$;
