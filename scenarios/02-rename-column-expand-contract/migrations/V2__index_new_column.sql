-- New reads can move over now. The unique index is built on the new column only;
-- building it CONCURRENTLY in production would avoid even the SHARE lock taken here.
create unique index customers_email_address_lower_key on customers (lower(email_address));
