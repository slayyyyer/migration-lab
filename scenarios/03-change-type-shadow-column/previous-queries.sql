-- The previous release reads total_cents as a bigint of cents. It still works while the
-- old column exists; the arithmetic would be wrong if it silently read dollars instead,
-- which is why the new column has a different name during the expand phase.
select count(*) as orders_over_100_dollars
  from orders
 where total_cents > 10000;
