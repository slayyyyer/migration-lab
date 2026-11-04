-- Deterministic seed data. The same scale always produces the same distribution,
-- because every random draw comes from a seeded PRNG.
--
-- Run as: psql -v scale=200000 -v ON_ERROR_STOP=1 -f shared/seed.sql
--
-- 200k orders keeps a full scenario sweep inside a few minutes on CI hardware while
-- still being large enough that a table rewrite is visible in lock timings.

\if :{?scale}
\else
  \set scale 200000
\endif

select setseed(0.42);

insert into customers (id, email, full_name)
select gen_random_uuid(),
       'customer-' || i || '@example.com',
       'Customer ' || i
  from generate_series(1, 500) as i;

insert into products (id, sku, name, unit_price_cents)
select gen_random_uuid(),
       'SKU-' || lpad(i::text, 4, '0'),
       'Product ' || i,
       (500 + (i * 37) % 20000)::bigint
  from generate_series(1, 200) as i;

-- Order status distribution: mostly PAID, with a long tail of the other states.
insert into orders (id, customer_id, status, currency, total_cents, created_at)
select gen_random_uuid(),
       c.id,
       case
         when random() < 0.70 then 'PAID'
         when random() < 0.90 then 'PENDING'
         when random() < 0.97 then 'SHIPPED'
         else 'CANCELLED'
       end,
       'USD',
       0,
       timestamptz '2026-01-01 00:00:00+00' + (random() * interval '300 days')
  from generate_series(1, :scale) as i
  join lateral (select id from customers order by random() limit 1) as c on true;

-- One to three lines per order.
insert into order_items (id, order_id, product_id, quantity, unit_price_cents)
select gen_random_uuid(),
       o.id,
       p.id,
       qty,
       p.unit_price_cents
  from orders o
  join lateral generate_series(1, 1 + (abs(hashtext(o.id::text)) % 3)) as qty on true
  join lateral (select id, unit_price_cents from products order by random() limit 1) as p on true;

-- Totals are derived from the lines, so the baseline is internally consistent
-- before any scenario touches it.
update orders o
   set total_cents = coalesce(
       (select sum(i.line_total_cents) from order_items i where i.order_id = o.id), 0);

analyze customers;
analyze products;
analyze orders;
analyze order_items;

select 'seeded ' || (select count(*) from orders) || ' orders, ' ||
       (select count(*) from order_items) || ' items' as seed_summary;
