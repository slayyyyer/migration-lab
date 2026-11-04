-- Deliberately bad. Included to prove the harness catches it, not as a recommendation.
--
-- This is a real type change with a USING clause, so Postgres rewrites all 200k rows while
-- holding ACCESS EXCLUSIVE. Every read and every write waits for the whole rewrite, and the
-- lock is held until the migration's transaction commits.
--
-- The safe version is scenario 03: shadow column, batched backfill, then swap.
alter table orders
  alter column total_cents type numeric(14,2)
  using total_cents::numeric(14,2);
