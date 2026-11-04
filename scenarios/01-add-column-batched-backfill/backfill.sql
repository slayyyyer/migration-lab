-- One batch per transaction. Each batch takes row locks only, so writers keep going.
-- Run by the harness in a loop until it returns 0; deliberately NOT a Flyway migration,
-- because a data backfill is an operational step, not a schema version.
with batch as (
    select id from orders where channel is null limit :batch
), updated as (
    update orders o
       set channel = 'web'
      from batch b
     where o.id = b.id
    returning o.id
)
select count(*) from updated;
