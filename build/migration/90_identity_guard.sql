-- =====================================================================
-- 90 · THE FOURTH GUARD — Defect 3 could recur.
--
-- The migration merged 583 coverage rows held by
-- aniket.chalke@cruxINIDA.co.in into the real person, but nothing stopped the
-- same thing happening on the next write: person.work_email had no unique
-- index at all, and nothing folded the misspelt domain.
--
-- IMPLEMENTATION.md section 7 names "the misspelt-domain person" as one of
-- four writes that must be refused at cut-over. Three already were:
--   branch_code_uniq            (client_id, code)
--   outbox_idempotency_uniq     (idempotency_key)
--   coverage_rule_no_overlap    trigger
-- This is the fourth.
--
-- Two parts, because neither can do both jobs:
--   * the alias table folds a known-bad domain onto the right one. It is a
--     table rather than a constant so the next typo is a row, not a deploy —
--     which is also why the fold is a trigger and not an expression index: an
--     index expression must be IMMUTABLE and may not read a table.
--   * the unique index then refuses the duplicate the fold has revealed.
-- =====================================================================
create table if not exists email_domain_alias (
  wrong      text primary key,
  correct    text not null,
  noted_by   text,
  noted_at   timestamptz not null default now(),
  constraint email_domain_alias_differs check (lower(wrong) <> lower(correct))
);
comment on table email_domain_alias is
  'Misspelt mail domains folded onto the real one before a person row is written. Defect 3: one typo domain held 583 coverage rows and a whole second identity. Adding a newly-spotted typo is an insert here, not a deploy.';

insert into email_domain_alias (wrong, correct, noted_by)
values ('cruxinida.co.in', 'cruxindia.co.in', 'migration P-01')
on conflict (wrong) do nothing;

create or replace function person_normalise_email() returns trigger
language plpgsql as $$
declare v_alias text;
begin
  if new.work_email is null or btrim(new.work_email) = '' then
    return new;
  end if;
  new.work_email := lower(btrim(new.work_email));
  select a.correct into v_alias
  from email_domain_alias a
  where lower(a.wrong) = split_part(new.work_email, '@', 2);
  if v_alias is not null then
    new.work_email := split_part(new.work_email, '@', 1) || '@' || lower(v_alias);
  end if;
  if new.personal_email is not null then
    new.personal_email := lower(btrim(new.personal_email));
  end if;
  return new;
end $$;

drop trigger if exists person_normalise_email on person;
create trigger person_normalise_email
  before insert or update of work_email, personal_email on person
  for each row execute function person_normalise_email();

-- A superseded twin keeps its address on purpose: that row is the audit trail
-- of the merge. A person who has left keeps theirs so the history reads back.
-- Only live people are constrained.
create unique index if not exists person_work_email_uniq
  on person (lower(work_email))
  where work_email is not null and superseded_by is null and left_on is null;
