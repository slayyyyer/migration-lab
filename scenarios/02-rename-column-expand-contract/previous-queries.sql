-- The previous release selects `email`, which still exists during the expand phase.
select id, email, full_name from customers order by id limit 5;
