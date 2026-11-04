-- CREATE INDEX CONCURRENTLY cannot run inside a transaction block, which is why this is
-- executed directly by the harness rather than as a Flyway migration. Flyway would have to
-- be configured not to wrap the script, and that exception belongs in the open.
--
-- It takes longer in wall-clock terms than the naive build — it scans the table twice and
-- waits for in-flight transactions — but it never holds a lock that blocks writers.
create index concurrently orders_status_idx on orders (status);
