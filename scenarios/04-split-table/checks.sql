create table if not exists lab_state (k text primary key, v text);

-- psql does not interpolate :variables inside dollar-quoted blocks, so the mode is
-- passed through a session setting instead of pasted into the DO block.
select set_config('lab.mode', :'mode', false);

do $$
declare
  mode text := current_setting('lab.mode');
  fingerprint text;
  stored text;
begin
  if mode = 'before' then
    select md5(string_agg(id::text || '|' || lower(email) || '|' || full_name, ',' order by id))
      into fingerprint from customers;
    insert into lab_state (k, v) values ('profiles_fingerprint', fingerprint)
      on conflict (k) do update set v = excluded.v;
    insert into lab_state (k, v) values ('customers_rows', (select count(*)::text from customers))
      on conflict (k) do update set v = excluded.v;
  else
    select md5(string_agg(c.id::text || '|' || lower(p.email) || '|' || p.full_name, ',' order by c.id))
      into fingerprint
      from customers c
      join customer_profiles p on p.customer_id = c.id;

    select v into stored from lab_state where k = 'profiles_fingerprint';
    if stored is distinct from fingerprint then
      raise exception 'profile data does not match the original customer rows';
    end if;

    select v into stored from lab_state where k = 'customers_rows';
    if stored is distinct from (select count(*)::text from customers) then
      raise exception 'customer row count changed';
    end if;

    if (select count(*) from customer_profiles) <> (select count(*) from customers) then
      raise exception 'every customer must have exactly one profile';
    end if;

    if exists (select 1 from customer_profiles p
                where not exists (select 1 from customers c where c.id = p.customer_id)) then
      raise exception 'orphaned profile rows';
    end if;

    if not exists (select 1 from pg_constraint
                    where conrelid = 'customer_profiles'::regclass and contype = 'f') then
      raise exception 'customer_profiles must have a foreign key to customers';
    end if;

    if exists (select 1 from information_schema.columns
                where table_name = 'customers' and column_name in ('email', 'full_name')) then
      raise exception 'old columns still present after contract';
    end if;
  end if;
end $$;
