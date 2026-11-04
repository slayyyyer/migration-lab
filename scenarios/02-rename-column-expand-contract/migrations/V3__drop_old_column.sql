-- Contract: only safe once every reader uses email_address and no writer posts to email.
drop trigger customers_email_dual_write on customers;
drop function sync_customer_email();
alter table customers drop column email;
