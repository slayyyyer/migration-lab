create table if not exists lab_state (k text primary key, v text);

-- psql does not interpolate :variables inside dollar-quoted blocks, so the mode is
-- passed through a session setting instead of pasted into the DO block.
select set_config('lab.mode', :'mode', false);

do $$
declare
  mode text := current_setting('lab.mode');
  total_before text;
  total_after text;
  stored text;
  data_type text;
begin
  if mode = 'before' then
    select (coalesce(sum(total_cents), 0)::numeric / 100)::text into total_before from orders;
    insert into lab_state (k, v) values ('orders_total_dollars', total_before)
      on conflict (k) do update set v = excluded.v;
    insert into lab_state (k, v) values ('orders_rows', (select count(*)::text from orders))
      on conflict (k) do update set v = excluded.v;
  else
    select coalesce(sum(total_cents), 0)::text into total_after from orders;
    select v into stored from lab_state where k = 'orders_total_dollars';

    if stored::numeric is distinct from total_after::numeric then
      raise exception 'order value changed across the type change: % -> %', stored, total_after;
    end if;

    select v into stored from lab_state where k = 'orders_rows';
    if stored is distinct from (select count(*)::text from orders) then
      raise exception 'order row count changed';
    end if;

    if exists (select 1 from orders where total_cents is null) then
      raise exception 'total_cents is null after the swap';
    end if;

    select data_type into data_type from information_schema.columns
     where table_name = 'orders' and column_name = 'total_cents';
    if data_type is distinct from 'numeric' then
      raise exception 'total_cents should be numeric, found %', data_type;
    end if;

    if exists (select 1 from information_schema.columns
                where table_name = 'orders' and column_name = 'total_amount') then
      raise exception 'shadow column total_amount should be renamed away';
    end if;
  end if;
end $$;
