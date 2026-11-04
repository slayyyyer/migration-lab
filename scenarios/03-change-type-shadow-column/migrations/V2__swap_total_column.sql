-- Contract: readers must already use total_amount before this runs.
drop trigger orders_total_dual_write on orders;
drop function sync_order_total();

-- Dropping the old column and renaming the shadow into its name is metadata-only;
-- the rewrite already happened when the values were written.
alter table orders drop column total_cents;
alter table orders rename column total_amount to total_cents;
alter table orders alter column total_cents set not null;
