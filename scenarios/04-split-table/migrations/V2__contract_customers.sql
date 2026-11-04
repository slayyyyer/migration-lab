-- Contract: only after every reader uses customer_profiles.
-- Dropping the columns also drops the old case-insensitive unique index on customers.email.
alter table customers drop column email;
alter table customers drop column full_name;
