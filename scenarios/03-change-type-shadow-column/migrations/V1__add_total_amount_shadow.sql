-- Expand: a second representation of the same fact.
-- `total_cents bigint` becomes `total_amount numeric(14,2)` in dollars. The change is a real
-- rewrite: every row gets a new value with a different type, so `alter column … type` holds
-- ACCESS EXCLUSIVE for the whole table while it runs.
alter table orders add column total_amount numeric(14,2);

create or replace function sync_order_total() returns trigger as $$
begin
  if tg_op = 'INSERT' then
    new.total_amount := coalesce(new.total_amount, round(new.total_cents / 100.0, 2));
    new.total_cents := coalesce(new.total_cents, round(new.total_amount * 100)::bigint);
  elsif new.total_cents is distinct from old.total_cents then
    new.total_amount := round(new.total_cents / 100.0, 2);
  else
    new.total_cents := round(new.total_amount * 100)::bigint;
  end if;
  return new;
end;
$$ language plpgsql;

create trigger orders_total_dual_write
  before insert or update on orders
  for each row execute function sync_order_total();
