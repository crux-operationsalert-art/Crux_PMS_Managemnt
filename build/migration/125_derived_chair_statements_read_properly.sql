-- Three of the composed statements read badly wherever the family's scope is a
-- phrase rather than a noun -- "Holds the team to the standard the revenue this
-- chair is answerable for is measured on." The fix is to stop substituting the
-- scope into sentences that do not need it. Only DERIVED rows are touched, so
-- the organisation document's own wording is untouched.

update chair_accountability
   set statement = 'Holds the team to the standard this work is measured on.'
 where source_ref = 'DERIVED' and statement like 'Holds the team to the standard %';

update chair_accountability
   set statement = 'Trains new joiners until they can work unsupervised.'
 where source_ref = 'DERIVED' and statement like 'Trains new joiners on %';

update chair_accountability
   set statement = regexp_replace(statement, ' to the standard set for .*\.$', ' to the standard set for it.')
 where source_ref = 'DERIVED' and statement like 'Does the work of % to the standard set for %';

-- and the two scopes that read as clauses become plain nouns everywhere else
update chair_accountability
   set statement = replace(replace(statement,
         'the revenue this chair is answerable for', 'the sales number'),
         'the partner network this chair is answerable for', 'the partner network')
 where source_ref = 'DERIVED' and statement like '%this chair is answerable for%';

update chair_measure
   set statement = replace(replace(statement,
         'the revenue this chair is answerable for', 'the sales number'),
         'the partner network this chair is answerable for', 'the partner network')
 where source_ref = 'DERIVED' and statement like '%this chair is answerable for%';

update chair_authority
   set statement = replace(replace(statement,
         'the revenue this chair is answerable for', 'the sales number'),
         'the partner network this chair is answerable for', 'the partner network')
 where source_ref = 'DERIVED' and statement like '%this chair is answerable for%';
