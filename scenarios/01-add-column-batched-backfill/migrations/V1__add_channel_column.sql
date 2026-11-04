-- Expand: adding a nullable column with no default is metadata-only in Postgres.
-- The brief moment of ACCESS EXCLUSIVE is enough to queue, not enough to hurt.
alter table orders add column channel varchar(32);
