create table if not exists lab_state (k text primary key, v text);

-- psql does not interpolate :variables inside dollar-quoted blocks, so the mode is
-- passed through a session setting instead of pasted into the DO block.
select set_config('lab.mode', :'mode', false);

do $$
declare
  mode text := current_setting('lab.mode');
  fingerprint text;
  stored text;
  nullable text;
begin
  if mode = 'before' then
    select md5(string_agg(id::text || '|' || lower(email) || '|' || full_name, ',' order by id))
      into fingerprint from customers;
    insert into lab_state (k, v) values ('customers_fingerprint', fingerprint)
      on conflict (k) do update set v = excluded.v;
    insert into lab_state (k, v) values ('customers_rows', (select count(*)::text from customers))
      on conflict (k) do update set v = excluded.v;
  else
    select md5(string_agg(id::text || '|' || lower(email_address) || '|' || full_name, ',' order by id))
      into fingerprint from customers;

    select v into stored from lab_state where k = 'customers_fingerprint';
    if stored is distinct from fingerprint then
      raise exception 'email values changed across the rename';
    end if;

    select v into stored from lab_state where k = 'customers_rows';
    if stored is distinct from (select count(*)::text from customers) then
      raise exception 'customer row count changed';
    end if;

    if exists (select 1 from customers where email_address is null) then
      raise exception 'email_address is null on some rows';
    end if;

    select is_nullable into nullable from information_schema.columns
     where table_name = 'customers' and column_name = 'email_address';
    if nullable is distinct from 'NO' then
      raise exception 'email_address should be NOT NULL after contract';
    end if;

    if exists (select 1 from information_schema.columns
                where table_name = 'customers' and column_name = 'email') then
      raise exception 'old email column still present after contract';
    end if;
  end if;
end $$;
