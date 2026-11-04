# 02 — Rename a column with expand/contract

**Failure mode this avoids:** `ALTER TABLE … RENAME COLUMN` is instant, and it instantly breaks
every application instance still running the old query. There is no schema version both releases
understand, so the only rollback is another deploy.

**Order of operations**

1. `V1` adds `email_address` plus a trigger that keeps the two columns in sync in both
   directions, so old writers keep working.
2. `backfill.sql` copies existing values in batches.
3. `V2` builds the unique index on the new column.
4. `V3` drops the trigger and the old column — only once every reader has moved.

**Asserted:** the email values are identical before and after (case-insensitive checksum over all
rows), no nulls, the new column is `NOT NULL`, the old column is gone after contract, and the
previous release's `select … email …` still works after the expand step (target 2).

**Note:** the trigger is the dual-write mechanism, and it is the part to be suspicious of. It
adds a function call to every write on `customers`; if that table takes heavy write traffic, the
alternative is dual-write in the application, which moves the same problem into two deployables.
