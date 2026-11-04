-- The naive version, kept so the report can show what it costs.
-- CREATE INDEX takes a SHARE lock: readers keep working, every writer queues until the
-- build finishes. On 200k rows that is visible; on 200M it is an outage.
create index orders_status_naive_idx on orders (status);
