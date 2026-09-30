-- =====================================================================
-- Crux baseline | 95_access_policy.sql | the access policy
--
-- GENERATED from the live project. Do not hand-edit: change the
-- database with a migration, then regenerate. build/schema/REGENERATE.md
-- says how, and build/migration/README.md says why this exists.
--
-- The ONLY rows the baseline carries. Who may open what is configuration, not data: nobody's name is in it, it is the same in every environment, and with these tables empty access_may_open() answers false for everybody and the rebuilt tool opens for nobody.
-- =====================================================================

insert into public.access_level (level, label, note) values
  ('admin', 'Administrator', 'Nothing is hidden from it and it can change everything. Not derived from a seat.'),
  ('analytics', 'MIS and analytics', 'Reporting and the data behind it. No client contact list.'),
  ('branch', 'Branch and above', 'A place and what it owes. Branch, zonal, regional and the heads carry the same list; what differs is how far they see, which is the service''s question and not this one.'),
  ('exec', 'Executive', 'Their own work: the day, the case in front of them, their own performance.'),
  ('finance', 'Finance', 'Money, penalties and the automations that raise them.'),
  ('hr', 'Human resources', 'People, joining, and the company''s messaging.'),
  ('partner', 'Location partner', 'A branch view, plus the penalty ledger they are charged against.'),
  ('staff', 'Staff function', 'Excellence, risk, legal, company secretary: read across the company, own nothing operational.'),
  ('team', 'Team leader', 'Their own work and the team under them.')
on conflict do nothing;

insert into public.access_level_screen (level, screen) values
  ('analytics', 'cases'),
  ('analytics', 'coverage'),
  ('analytics', 'data'),
  ('analytics', 'history'),
  ('analytics', 'ideas'),
  ('analytics', 'people'),
  ('analytics', 'perf'),
  ('analytics', 'profile'),
  ('analytics', 'reports'),
  ('analytics', 'today'),
  ('branch', 'cases'),
  ('branch', 'clients'),
  ('branch', 'hiring'),
  ('branch', 'history'),
  ('branch', 'ideas'),
  ('branch', 'joining'),
  ('branch', 'ogl'),
  ('branch', 'people'),
  ('branch', 'perf'),
  ('branch', 'profile'),
  ('branch', 'reports'),
  ('branch', 'today'),
  ('branch', 'visits'),
  ('exec', 'cases'),
  ('exec', 'ideas'),
  ('exec', 'ogl'),
  ('exec', 'perf'),
  ('exec', 'profile'),
  ('exec', 'today'),
  ('exec', 'visits'),
  ('finance', 'auto'),
  ('finance', 'cases'),
  ('finance', 'clients'),
  ('finance', 'config'),
  ('finance', 'hiring'),
  ('finance', 'history'),
  ('finance', 'ideas'),
  ('finance', 'penalties'),
  ('finance', 'people'),
  ('finance', 'perf'),
  ('finance', 'profile'),
  ('finance', 'reports'),
  ('finance', 'today'),
  ('finance', 'visits'),
  ('hr', 'auto'),
  ('hr', 'cases'),
  ('hr', 'config'),
  ('hr', 'hiring'),
  ('hr', 'history'),
  ('hr', 'hr'),
  ('hr', 'ideas'),
  ('hr', 'joining'),
  ('hr', 'mail'),
  ('hr', 'penalties'),
  ('hr', 'people'),
  ('hr', 'perf'),
  ('hr', 'profile'),
  ('hr', 'reports'),
  ('hr', 'today'),
  ('hr', 'visits'),
  ('partner', 'cases'),
  ('partner', 'clients'),
  ('partner', 'hiring'),
  ('partner', 'history'),
  ('partner', 'ideas'),
  ('partner', 'joining'),
  ('partner', 'ogl'),
  ('partner', 'penalties'),
  ('partner', 'people'),
  ('partner', 'perf'),
  ('partner', 'profile'),
  ('partner', 'reports'),
  ('partner', 'today'),
  ('partner', 'visits'),
  ('staff', 'cases'),
  ('staff', 'clients'),
  ('staff', 'history'),
  ('staff', 'ideas'),
  ('staff', 'people'),
  ('staff', 'perf'),
  ('staff', 'profile'),
  ('staff', 'reports'),
  ('staff', 'today'),
  ('staff', 'visits'),
  ('team', 'cases'),
  ('team', 'ideas'),
  ('team', 'ogl'),
  ('team', 'people'),
  ('team', 'perf'),
  ('team', 'profile'),
  ('team', 'today'),
  ('team', 'visits')
on conflict do nothing;

insert into public.access_screen_parent (screen, parent) values
  ('access', 'reports'),
  ('matrix', 'clients'),
  ('mis', 'reports'),
  ('org', 'people'),
  ('plb', 'perf'),
  ('pms', 'perf'),
  ('rates', 'reports'),
  ('tenday', 'reports'),
  ('whatsapp', 'mail')
on conflict do nothing;

insert into public.access_chair_level (chair_title, level) values
  ('Assistant Vice President', 'branch'),
  ('Assurance, Risk & Compliance', 'staff'),
  ('Back Office / Processing Executives', 'exec'),
  ('Branch Collection Executive', 'exec'),
  ('Branch Manager', 'branch'),
  ('Business Excellence & PMO', 'staff'),
  ('Central Collections Executives', 'exec'),
  ('Chief Executive Officer / Managing Director', 'admin'),
  ('Company Secretary', 'staff'),
  ('Field Executives / Verifiers', 'exec'),
  ('Finance Head', 'finance'),
  ('Head — Finance Operations', 'finance'),
  ('Head — HR Operations', 'hr'),
  ('Head — Human Resources', 'hr'),
  ('Head — Operations', 'branch'),
  ('HR Executive', 'hr'),
  ('HR Operations', 'hr'),
  ('Legal & Compliance', 'staff'),
  ('Location Partner / Franchisee Partner', 'partner'),
  ('Managing Director', 'admin'),
  ('MIS & Business Analytics', 'analytics'),
  ('Operations Head', 'branch'),
  ('Partner Team Leader / Supervisor', 'team'),
  ('Regional Manager', 'branch'),
  ('Sales Manager', 'branch'),
  ('Team Leader / Supervisor', 'team'),
  ('Vice President', 'finance'),
  ('Zonal Manager', 'branch'),
  ('Accounts', 'finance'),
  ('Executive', 'exec')
on conflict do nothing;

insert into public.access_department_level (department, level) values
  ('Finance & Accounts', 'finance'),
  ('Human Resources', 'hr'),
  ('Finance', 'finance'),
  ('MIS', 'analytics')
on conflict do nothing;

insert into public.pms_weighting (id, scope_all, chair_id, person_id, kpi_percent, attr_percent, effective_from, set_by) values
  ('af1e1457-6cbb-4532-bbe1-7a67ef23c467', 'true', null, null, '75', '25', '2026-10-01', null)
on conflict do nothing;

insert into public.pms_curve_band (id, effective_fy, rank, label, share_pct) values
  ('26458bcc-7819-421a-ad61-0acec664edea', '2026-27', '2', 'Exceeds', '15'),
  ('a354bd5c-029f-4cf0-9438-0e0d541d1f05', '2026-27', '3', 'Meets', '60'),
  ('ab73f187-abd3-4fee-b3eb-94b222aa45e2', '2026-27', '4', 'Below', '15'),
  ('d34b70a5-6ecb-4b84-8cd6-a77923b662ca', '2026-27', '5', 'Unsatisfactory', '5'),
  ('ff007538-af51-4277-810a-1ecdb9f85b55', '2026-27', '1', 'Outstanding', '5')
on conflict do nothing;

-- pms_impact is empty

insert into public.perf_rollup_map (child_family, parent_family, note, set_by, set_at, priority) values
  ('EX1', 'D3', 'An executive''s cases completed against target and a Team Leader''s daily target achievement are the same quantity: work finished against work asked for, one person and then their team.', null, '2026-09-30T00:38:27.222014+00:00', '1'),
  ('EX2', 'D8', 'Days filed by one person are what a Sales Manager''s "team days filed" counts.', null, '2026-09-30T00:38:27.222014+00:00', '1'),
  ('EX2', 'HFO4', 'The same, where the line runs through Finance Operations.', null, '2026-09-30T00:38:27.222014+00:00', '2'),
  ('EX2', 'HRO4', 'The same, where the line runs through HR Operations.', null, '2026-09-30T00:38:27.222014+00:00', '3'),
  ('EX3', 'D21', 'Work returned to an executive for correction is what a Team Leader''s error rate counts. Both are a proportion of work that came back, and both want to be small.', null, '2026-09-30T00:38:27.222014+00:00', '1'),
  ('HRE1', 'HRO2', 'The same measure, one level up: the HR executive and the HR Operations head are both measured on joiners being on record from day one. Migration 223 sent this to HRO1, "Chairs with a named holder", which is a different question entirely.', null, '2026-09-30T00:38:27.222014+00:00', '1'),
  ('HRE2', 'HRO4', 'An HR executive''s days filed are what the HR Operations head''s "team days filed" counts.', null, '2026-09-30T00:38:27.222014+00:00', '1'),
  ('K5', 'HFO3', 'Nothing unactioned past its due date, named identically at both levels.', null, '2026-09-30T00:38:27.222014+00:00', '1'),
  ('R1', 'CEO1', 'Revenue against plan is what company revenue against the board plan is made of.', null, '2026-09-30T00:38:27.222014+00:00', '1'),
  ('R6', 'R8', 'Branch revenue achievement is what zone revenue achievement is made of. The same rupees, counted at two scopes.', null, '2026-09-30T00:38:27.222014+00:00', '1'),
  ('R8', 'R1', 'Zone revenue is what revenue against plan is made of.', null, '2026-09-30T00:38:27.222014+00:00', '1'),
  ('X1', 'CEO2', 'Function cost against budget is part of company cost against budget.', null, '2026-09-30T00:38:27.222014+00:00', '1'),
  ('X2', 'X1', 'A branch''s expense against budget is part of the function''s cost against budget. The same variance, counted at two scopes.', null, '2026-09-30T00:38:27.222014+00:00', '1')
on conflict do nothing;



