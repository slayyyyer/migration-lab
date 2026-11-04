-- Baseline for every scenario: the starting schema of the orders domain.
-- Deliberately identical to orders-service V1__schema.sql, so a migration proven here
-- is a migration that applies to the service.
--
-- Applied to an empty database, then Flyway baselines at version 0 and each scenario's
-- migrations run on top.

create table customers (
    id         uuid         primary key,
    email      varchar(320) not null,
    full_name  varchar(200) not null,
    created_at timestamptz  not null default now()
);

create unique index customers_email_lower_key on customers (lower(email));

create table products (
    id               uuid        primary key,
    sku              varchar(64) not null unique,
    name             varchar(200) not null,
    unit_price_cents bigint      not null check (unit_price_cents >= 0),
    created_at       timestamptz not null default now()
);

create table orders (
    id              uuid        primary key,
    customer_id     uuid        not null references customers (id),
    status          varchar(32) not null
                    check (status in ('PENDING', 'PAID', 'SHIPPED', 'CANCELLED')),
    currency        char(3)     not null,
    total_cents     bigint      not null check (total_cents >= 0),
    idempotency_key varchar(128),
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);

create unique index orders_idempotency_key_key
    on orders (idempotency_key)
    where idempotency_key is not null;

create index orders_customer_created_idx on orders (customer_id, created_at desc);

create table order_items (
    id               uuid    primary key,
    order_id         uuid    not null references orders (id) on delete cascade,
    product_id       uuid    not null references products (id),
    quantity         integer not null check (quantity > 0),
    unit_price_cents bigint  not null check (unit_price_cents >= 0),
    line_total_cents bigint  generated always as (quantity::bigint * unit_price_cents) stored
);

create index order_items_order_idx on order_items (order_id);

create table outbox_events (
    id           bigserial   primary key,
    aggregate_id uuid        not null,
    event_type   varchar(64) not null,
    payload      jsonb       not null,
    created_at   timestamptz not null default now(),
    published_at timestamptz
);

create index outbox_events_unpublished_idx on outbox_events (created_at) where published_at is null;
