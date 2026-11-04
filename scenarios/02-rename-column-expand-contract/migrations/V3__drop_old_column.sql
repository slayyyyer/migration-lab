-- Contract: only safe once every reader uses email_address and no writer posts to email.
drop trigger customers_email_dual_write on customers;
drop function sync_customer_email();

-- The backfill has already filled every row, so the NOT NULL guarantee the old column carried
-- can be kept on the new one. Skipping this quietly widens the schema: a checksum of the email
-- values cannot tell a nullable column from a required one, and the next bad insert finds out.
alter table customers alter column email_address set not null;

alter table customers drop column email;
