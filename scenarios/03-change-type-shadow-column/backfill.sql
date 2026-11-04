with batch as (
    select id from orders where total_amount is null limit :batch
), updated as (
    update orders o
       set total_amount = round(o.total_cents / 100.0, 2)
      from batch b
     where o.id = b.id
    returning o.id
)
select count(*) from updated;
