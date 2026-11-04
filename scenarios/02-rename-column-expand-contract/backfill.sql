with batch as (
    select id from customers where email_address is null limit :batch
), updated as (
    update customers c
       set email_address = c.email
      from batch b
     where c.id = b.id
    returning c.id
)
select count(*) from updated;
