# 03 — Change a column type with a shadow column

**Failure mode this avoids:** `ALTER TABLE … ALTER COLUMN … TYPE numeric` rewrites every row
while holding `ACCESS EXCLUSIVE`. On a hot table that is an outage measured in write timeouts,
and it is not cancellable once it starts without losing the work.

**Order of operations**

1. `V1` adds `total_amount numeric(14,2)` and a trigger that keeps cents and dollars in sync.
2. `backfill.sql` converts existing rows in batches.
3. `V2` drops the trigger, drops the old column, renames the shadow into the old name and
   reapplies `NOT NULL`.

**Asserted:** the money total is identical before and after (compared as numerics, not text,
so `123` and `123.00` are the same amount), the row count is unchanged, no nulls remain, the
column type is `numeric`, and the shadow name is gone.

**Why a trigger:** it is the smallest thing that keeps both representations correct for writes
from the still-deployed release. The cost is a PL/pgSQL call per write; the alternative is
dual-writing in the application, which is the same problem with two deployables to coordinate.
