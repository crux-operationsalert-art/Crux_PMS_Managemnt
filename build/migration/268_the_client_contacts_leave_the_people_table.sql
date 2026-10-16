-- The 531 client-bank contacts leave the people table
--
-- Owner, 16 Oct: "Remove the client contacts." 531 of the rows in person
-- were contacts at client banks (Bank of Maharashtra 208, IDBI 120, SBI
-- 106, ...): typed CLIENT_CONTACT, no employee number, never signed in, and
-- each already DEACTIVATED. They made every company-wide list of people
-- mostly bankers.
--
-- Measured before this file, across all 160 foreign keys onto person: only
-- two tables point at them. branch_contact.person_id (750 rows) -- a link,
-- since branch_contact keeps its own name, mobile and e-mail; 55 of those
-- rows had no name of their own, so it is copied from the person first and
-- nothing is lost. And person_event (531 rows), each one the record of the
-- deactivation.
--
-- Reversible: every removed row -- the person and its events -- is kept,
-- whole, as jsonb in person_removed, with when and why.
create table if not exists person_removed (
  id uuid primary key,
  removed_at timestamptz not null default now(),
  why text not null,
  person jsonb not null,
  events jsonb not null default '[]'::jsonb
);
comment on table person_removed is
  'Rows taken out of person, kept whole so the removal can be undone. 268: the 531 client-bank contacts.';

do $do$
declare n_p int; n_e int; n_bc int; n_left int;
begin
  insert into person_removed (id, why, person, events)
  select p.id, '268: a client-bank contact, not a member of staff (owner, 16 Oct)',
         to_jsonb(p),
         coalesce((select jsonb_agg(to_jsonb(e)) from person_event e where e.person_id = p.id), '[]'::jsonb)
    from person p where p.employee_type = 'CLIENT_CONTACT'
  on conflict (id) do nothing;

  update branch_contact bc
     set name = coalesce(nullif(btrim(bc.name), ''), p.full_name),
         email = coalesce(nullif(btrim(bc.email), ''), p.work_email),
         mobile = coalesce(nullif(btrim(bc.mobile), ''), p.mobile),
         person_id = null
    from person p
   where p.id = bc.person_id and p.employee_type = 'CLIENT_CONTACT';
  get diagnostics n_bc = row_count;

  delete from person_event e using person p
   where p.id = e.person_id and p.employee_type = 'CLIENT_CONTACT';
  get diagnostics n_e = row_count;

  delete from person where employee_type = 'CLIENT_CONTACT';
  get diagnostics n_p = row_count;

  select count(*) into n_left from person where employee_type = 'CLIENT_CONTACT';
  if n_left > 0 then raise exception 'Migration 268: % client contact(s) are still in person.', n_left; end if;
  if n_p <> (select count(*) from person_removed where why like '268:%') then
    raise exception 'Migration 268: removed % but kept % -- not reversible, stopping.', n_p,
      (select count(*) from person_removed where why like '268:%');
  end if;
  raise notice 'Migration 268: % client contacts removed (% events, % branch contacts kept with their details); all kept in person_removed.',
    n_p, n_e, n_bc;
end
$do$;
