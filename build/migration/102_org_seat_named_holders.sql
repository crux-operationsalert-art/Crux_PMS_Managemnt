-- =====================================================================
-- 102 · Seat the holders the structure document names
--
-- Only where the name matches a person on the USERS sheet exactly.
-- "Viren Pal" and "Virendra Pal" are probably one person, and "PP Valsan"
-- and "P P Valsan" almost certainly are — but a chair decides what its
-- holder can see, so a near-match is a question for the owner, not a
-- guess. The 12 that do not match exactly are filed in migration_review
-- with the nearest names on the sheet.
-- =====================================================================
insert into chair_holder (chair_id, person_id, is_primary, from_date)
select c.id, p.id,
       row_number() over (partition by p.id order by c.code) = 1,
       current_date
from chair_seating cs
join chair c on c.id = cs.chair_id
join person p on p.superseded_by is null
  and lower(regexp_replace(p.full_name, '\s+', ' ', 'g'))
    = lower(regexp_replace(regexp_replace(cs.holder_text, '\s*—.*$', '', 'g'), '\s+', ' ', 'g'))
where cs.holder_text is not null
  and not exists (select 1 from chair_holder x
                   where x.chair_id = c.id and x.person_id = p.id and x.to_date is null);

insert into migration_review (entity_type, entity_ref, question, context)
select 'chair_holder', cs.source_ref,
       'Who holds this chair? The structure document names "' || cs.holder_text ||
       '", which is not an exact match for anyone on the USERS sheet.',
       c.title || coalesce(' — ' || cs.scope_label, '') ||
       '. Nearest names on the sheet: ' ||
       coalesce((select string_agg(p.full_name || ' <' || p.work_email || '>', ', ')
                 from person p
                 where p.superseded_by is null and p.source_ref like 'USERS!%'
                   and extensions.levenshtein(
                         lower(regexp_replace(p.full_name,'\s+','','g')),
                         lower(regexp_replace(regexp_replace(cs.holder_text,'\s*—.*$','','g'),'\s+','','g'))
                       ) <= 4), 'none within edit distance 4')
from chair_seating cs
join chair c on c.id = cs.chair_id
where cs.holder_text is not null
  and cs.holder_text !~* 'VACANT|TO BE HIRED|UNKNOWN|Incumbents|Partner firms|Cohort|Retained|Directors|and others'
  and not exists (
    select 1 from person p where p.superseded_by is null
      and lower(regexp_replace(p.full_name, '\s+', ' ', 'g'))
        = lower(regexp_replace(regexp_replace(cs.holder_text, '\s*—.*$', '', 'g'), '\s+', ' ', 'g')))
  and not exists (select 1 from migration_review r
                   where r.entity_type = 'chair_holder' and r.entity_ref = cs.source_ref);
