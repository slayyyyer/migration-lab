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
  select md5(string_agg(id::text || '|' || total_cents::text, ',' order by id))
    into fingerprint from orders;

  if mode = 'before' then
    insert into lab_state (k, v) values ('orders_fingerprint', fingerprint)
      on conflict (k) do update set v = excluded.v;
    insert into lab_state (k, v) values ('orders_rows', (select count(*)::text from orders))
      on conflict (k) do update set v = excluded.v;
  else
    select v into stored from lab_state where k = 'orders_fingerprint';
    if stored is distinct from fingerprint then
      raise exception 'preserved columns changed: % -> %', stored, fingerprint;
    end if;

    select v into stored from lab_state where k = 'orders_rows';
    if stored is distinct from (select count(*)::text from orders) then
      raise exception 'order row count changed';
    end if;

    if exists (select 1 from orders where channel is null) then
      raise exception 'channel is still null on some rows';
    end if;

    if exists (select 1 from information_schema.columns
                where table_name = 'orders' and column_name = 'channel' and is_nullable = 'YES') then
      raise exception 'channel column is still nullable';
    end if;
  end if;
end $$;
