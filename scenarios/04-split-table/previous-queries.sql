-- The previous release reads the columns that are about to move. It must still work
-- during the expand phase, which is the entire reason the split is staged.
select id, email, full_name from customers order by id limit 5;
