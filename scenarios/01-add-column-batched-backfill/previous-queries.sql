-- The query set the previous release runs. It must keep working during the expand phase.
select id, status, currency, total_cents, created_at
  from orders
 where customer_id = (select id from customers order by id limit 1)
 order by created_at desc
 limit 5;
