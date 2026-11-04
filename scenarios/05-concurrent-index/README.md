# 05 — Build an index without blocking writes

**Failure mode this avoids:** `CREATE INDEX` on a hot table. It takes a `SHARE` lock, so reads
continue while **every write queues** behind the build. It also runs inside the migration
transaction, so the lock is held for the whole migration, not just the build.

**What runs**

1. `V1` builds `orders_status_naive_idx` the naive way — deliberately blocking, measured.
2. `V2` drops it again.
3. `extra/concurrent-index.sql` builds `orders_status_idx` with `CONCURRENTLY`, also measured.

The report shows both durations and the worst writer latency for each. The concurrent build is
usually **slower in wall-clock time** and still the correct choice: it holds no lock that stops
writers.

**Why it is not a Flyway migration:** `CREATE INDEX CONCURRENTLY` cannot run inside a transaction
block. Flyway wraps SQL migrations in one by default, so this statement is executed directly by
the harness. Hiding that exception in a migration configuration flag would hide the single most
important property of the statement.

**Asserted:** the index exists **and is valid**, no invalid indexes are left behind (a failed
concurrent build leaves one, and it silently does nothing), and the naive index is gone.
