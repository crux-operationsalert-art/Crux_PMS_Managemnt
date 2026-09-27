-- 205 · The ten-day view carries its keys
--
-- seam.tenday_snapshot reads business_record and hands back the location name
-- and the figures. It drops the two columns the row is keyed on — client_id
-- and geo_node_id — which is fine for drawing a table and useless for deciding
-- who may see the row.
--
-- The MIS screen is being scoped to the caller's coverage, and coverage
-- resolves to (client, geography) pairs. Without those two columns the ten-day
-- view could only be filtered on the location NAME, which would show one
-- client's position to a person who covers a different client in the same
-- city. So the view carries its keys.
--
-- Additive: the existing columns keep their names, their types and their
-- order, and the two new ones go on the end. Anything already reading this
-- view is unaffected.

create or replace view seam.tenday_snapshot as
 SELECT b.id::text AS id,
    b.period,
    g.name AS location,
    b.day10 AS day10_revenue,
    b.revenue AS actual_revenue,
    NULL::numeric AS live_addition,
    b.day10 * 5 AS sheet_x5,
    b.day10 * 4 AS sheet_x4,
    b.day10::numeric * 3.5 AS sheet_x35,
    b.day10::numeric * 3.25 AS sheet_x325,
    b.source_ref AS src,
    b.client_id,
    b.geo_node_id
   FROM business_record b
     LEFT JOIN geo_node g ON g.id = b.geo_node_id
  WHERE b.day10 IS NOT NULL;

comment on view seam.tenday_snapshot is
  'The month''s position as at the 10th, read from business_record. client_id '
  'and geo_node_id are carried so the row can be matched against a person''s '
  'coverage; without them it could only be filtered on the location name, '
  'which is not the same question.';
