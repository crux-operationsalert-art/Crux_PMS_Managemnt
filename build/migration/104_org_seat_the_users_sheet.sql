-- =====================================================================
-- 104 · Seat everyone on the USERS sheet
--
-- The owner confirmed four names are one person each:
--   Viren Pal = Virendra Pal, PP Valsan = P P Valsan,
--   Vrunda Potadar = Vrunda Potdar, Shivkumar = Shivakumar V
-- and asked for the rest to be decided rather than left open, on the
-- understanding that an administrator can move anyone in one row.
--
-- Two sources, document first where it is more specific than the sheet:
--   · the structure document, where it names a holder;
--   · otherwise the sheet's own designation and department.
--
-- The one rule that needed evidence rather than a guess is "Executive",
-- which the sheet does not qualify. The document is explicit that field
-- executives report to the Branch Manager and back-office executives to
-- the Team Leader, so each Executive is placed by who their manager is.
--
-- operations.alert@ is deliberately NOT seated. It is a shared alert
-- mailbox, not a person; seating it would give an inbox one chair's
-- scoped view of client data. It is an administrator, so Data setup,
-- Mail and the Org chart are open to it either way. Recorded as a
-- question so the decision is visible.
-- =====================================================================
with u as (
  select lower(trim(email)) as email, designation, department,
         lower(nullif(trim(manager_email),'')) as mgr
  from stg.users
),
withmgr as (
  select u.*, m.designation as mgr_designation from u left join u m on m.email = u.mgr
),
by_rule as (
  select email,
    case
      when designation = 'MD'                                          then 'MD'
      when designation = 'AVP'                                         then 'AVP'
      when designation = 'Operations Head' and department='Operations' then 'OPS'
      when designation = 'Operations Head' and department='Finance'    then 'FIN'
      when designation = 'Operations Head' and department='HR'         then 'GRC'
      when designation = 'Zonal Manager'                               then 'RM'
      when designation = 'Branch Manager'                              then 'BM'
      when designation = 'Team Leader'                                 then 'TL'
      when designation = 'Manager' and department='Operations'         then 'TL'
      when designation = 'Manager'                                     then 'BD'
      when designation = 'Executive' and department='HR'               then 'HRE'
      when designation = 'Executive' and mgr_designation='Team Leader' then 'BO'
      when designation = 'Executive'                                   then 'FE'
    end as seat_code
  from withmgr
  where email <> 'operations.alert@cruxindia.co.in'
),
by_document (email, seat_code) as (values
  ('vrunda.potdar@cruxindia.co.in','CCM'),   -- Credit & Collections, interim
  ('vrunda.potdar@cruxindia.co.in','BID'),   -- and Bids, Tenders & Contracts
  ('shivakumar.v@cruxindia.co.in','BZ'),     -- Business Manager, South Zone
  ('vicky.salvi@cruxindia.co.in','MIS'),     -- MIS & Business Analytics
  ('valsan.p@cruxindia.co.in','HRH')         -- interim cover of Head, HR
),
overridden as (select distinct email from by_document),
assign as (
  select email, seat_code from by_document
  union
  select r.email, r.seat_code from by_rule r
  where r.seat_code is not null
    and not exists (select 1 from overridden o where o.email = r.email)
)
insert into chair_holder (chair_id, person_id, is_primary, from_date)
select c.id, p.id,
       row_number() over (partition by p.id order by c.code) = 1
         and not exists (select 1 from chair_holder x
                          where x.person_id = p.id and x.is_primary and x.to_date is null),
       current_date
from assign a
join chair c on c.code = a.seat_code
join person p on p.superseded_by is null and lower(p.work_email) = a.email
where not exists (select 1 from chair_holder x
                   where x.chair_id = c.id and x.person_id = p.id and x.to_date is null);

-- The USERS sheet is the people master, so its spelling stands and the
-- document's variant is replaced wherever it was drawn.
update chair_seating set
  holder_text = replace(replace(replace(replace(holder_text,
    'Viren Pal','Virendra Pal'),'PP Valsan','P P Valsan'),
    'Vrunda Potadar','Vrunda Potdar'),'Shivkumar','Shivakumar V')
where holder_text ~ 'Viren Pal|PP Valsan|Vrunda Potadar|Shivkumar';

update chair_seating set
  note = replace(replace(replace(replace(note,
    'Viren Pal','Virendra Pal'),'PP Valsan','P P Valsan'),
    'Vrunda Potadar','Vrunda Potdar'),'Shivkumar','Shivakumar V')
where note ~ 'Viren Pal|PP Valsan|Vrunda Potadar|Shivkumar';

do $$
declare bad int;
begin
  select count(*) into bad from chair_seating
   where coalesce(holder_text,'') || coalesce(note,'') ~ 'Virendrada|Shivakumar V V|P  P Valsan';
  if bad > 0 then
    raise exception 'name normalisation doubled a substitution on % rows', bad;
  end if;
end $$;
