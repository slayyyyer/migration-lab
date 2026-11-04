# 04 — Split a table into two with a foreign key

**Failure mode this avoids:** moving columns to a new table and dropping the originals in one
deploy. Every instance of the old release starts failing at the same second, and there is no
schema version where both work.

**Order of operations**

1. `V1` creates `customer_profiles` with a foreign key to `customers` and its own unique index.
   The old columns stay.
2. `backfill.sql` copies rows in batches, skipping any customer that already has a profile, so
   the step is safe to re-run.
3. `V2` drops `customers.email` and `customers.full_name`.

**Asserted:** the profile data matches the original customer data row for row
(case-insensitive checksum), every customer has exactly one profile, there are no orphans, the
foreign key exists, the old columns are gone after contract, and the previous release's
`select id, email, full_name from customers` still works after the expand step.

**Note:** the split is a normalisation, so the read path changes shape: the new release joins
`customers` to `customer_profiles`. That join is the price of the split and belongs in the
review, not in a surprise after the deploy.
