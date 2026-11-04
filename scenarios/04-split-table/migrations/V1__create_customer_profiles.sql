-- Expand: create the new table and keep the old columns in place.
-- Both shapes are valid at once, so the old release keeps reading `customers` while the
-- new release can start reading `customer_profiles`.
create table customer_profiles (
    customer_id uuid         primary key references customers (id) on delete cascade,
    email       varchar(320) not null,
    full_name   varchar(200) not null
);

create unique index customer_profiles_email_lower_key on customer_profiles (lower(email));
