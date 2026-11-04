with batch as (
    select c.id
      from customers c
     where not exists (select 1 from customer_profiles p where p.customer_id = c.id)
     limit :batch
), inserted as (
    insert into customer_profiles (customer_id, email, full_name)
    select c.id, c.email, c.full_name
      from customers c
      join batch b on b.id = c.id
    on conflict (customer_id) do nothing
    returning customer_id
)
select count(*) from inserted;
