-- Contract. The naive version is `alter table orders alter column channel set not null`,
-- which scans the whole table while holding ACCESS EXCLUSIVE and blocks every writer.
-- These three statements do the same job with a much shorter exclusive window.
alter table orders add constraint orders_channel_present check (channel is not null) not valid;

-- Scans the table under SHARE UPDATE EXCLUSIVE: writers are not blocked.
alter table orders validate constraint orders_channel_present;

-- With the validated constraint, Postgres can skip the scan entirely.
alter table orders alter column channel set not null;

alter table orders drop constraint orders_channel_present;
