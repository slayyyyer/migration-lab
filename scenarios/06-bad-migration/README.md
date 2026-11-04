# 06 — A deliberately bad migration (expected to be caught)

This directory is a **showcase of the guardrail**, not an example to copy.

`V1__bad_type_change.sql` is a real type change with a `USING` clause. Postgres rewrites every
row while holding `ACCESS EXCLUSIVE`; reads and writes both wait for the whole rewrite, and the
lock is held until the migration transaction commits.

**Why it is here:** a lab that only contains good migrations proves nothing about whether the
harness can tell the difference. This scenario is marked `EXPECTED_FAIL=true`, so it counts as a
pass only when the harness actually catches it — either the concurrent writer is blocked past the
200 ms budget, or the assertions reject the resulting schema.

**What the harness reports**

- The scenario status is `caught`, never `pass`.
- The writer's worst latency is reported next to the budget that was exceeded.
- The data checks run first, so the report can say "no rows were lost, but the table was blocked
  for N ms" rather than collapsing both facts into one word.

**The fix** is scenario 03: add a shadow column, backfill in batches, then swap the names. Same
end state, no exclusive rewrite of a hot table.
