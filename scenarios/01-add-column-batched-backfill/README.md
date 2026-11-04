# 01 — Add a column, backfill in batches, enforce NOT NULL

**Failure mode this avoids:** `alter table … add column … not null default …` on a hot table,
or `set not null` while 200k rows are being written. Both take `ACCESS EXCLUSIVE` for the whole
scan and every write queues behind it.

**Order of operations**

1. `V1` adds a *nullable* column with no default. Metadata-only, milliseconds.
2. `backfill.sql` fills it in batches of 5,000, each batch its own transaction, so writers only
   ever contend with row locks.
3. `V2` adds a `CHECK … NOT VALID` (brief lock, no scan), `VALIDATE CONSTRAINT` (scans under
   `SHARE UPDATE EXCLUSIVE`, writers unaffected), then `SET NOT NULL` (no scan needed because
   the constraint is already proven).

**Asserted:** row count and a checksum over the untouched columns are identical before and
after; no row is left with a null `channel`; the column is `NOT NULL`; the previous release's
query still runs after the expand step.
