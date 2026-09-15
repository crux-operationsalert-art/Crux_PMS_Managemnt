alter table daily_count add column if not exists values jsonb;
comment on column daily_count.values is
  'The day''s figures, keyed by KPI. Sub-categories hang off their parent key. One row per person per day: the filing is a single act with a single cutoff.';

alter table daily_count alter column kpi_id drop not null;
alter table daily_count alter column value  drop not null;

alter table daily_count drop constraint if exists daily_count_uniq;

alter table daily_count drop constraint if exists daily_count_has_figures;
alter table daily_count add constraint daily_count_has_figures
  check (values is not null or (kpi_id is not null and value is not null));

alter table person drop constraint if exists person_employee_type_check;
alter table person add constraint person_employee_type_check
  check (employee_type in ('EMPLOYEE','PARTNER','INTERN','CONTRACT'));

alter table person_request add column if not exists employee_type text not null default 'EMPLOYEE';
alter table person_request drop constraint if exists person_request_employee_type_check;
alter table person_request add constraint person_request_employee_type_check
  check (employee_type in ('EMPLOYEE','PARTNER','INTERN','CONTRACT'));
comment on column person_request.employee_type is
  'Captured when the request is raised, because HR approves the terms as well as the chair. Carried onto the person at account creation.';

insert into setting (key, value) values
  ('pms_dispute_hrs','48'),
  ('pms_exc_hrs','48'),
  ('pms_exc_open','48')
on conflict (key) do nothing;