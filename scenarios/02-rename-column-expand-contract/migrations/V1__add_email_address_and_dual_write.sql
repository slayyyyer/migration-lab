-- Expand: new column plus a trigger so both names stay correct while old code still runs.
-- A plain `alter table customers rename column email to email_address` breaks every
-- deployed instance at once, with no way to roll the application back independently.
alter table customers add column email_address varchar(320);

create or replace function sync_customer_email() returns trigger as $$
begin
  if tg_op = 'INSERT' then
    new.email_address := coalesce(new.email_address, new.email);
    new.email := coalesce(new.email, new.email_address);
  elsif new.email is distinct from old.email then
    new.email_address := new.email;
  else
    new.email := new.email_address;
  end if;
  return new;
end;
$$ language plpgsql;

create trigger customers_email_dual_write
  before insert or update on customers
  for each row execute function sync_customer_email();
