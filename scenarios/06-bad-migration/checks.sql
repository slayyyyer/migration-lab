create table if not exists lab_state (k text primary key, v text);

-- psql does not interpolate :variables inside dollar-quoted blocks, so the mode is
-- passed through a session setting instead of pasted into the DO block.
select set_config('lab.mode', :'mode', false);

do $$
declare
  mode text := current_setting('lab.mode');
  fingerprint text;
  stored text;
  data_type text;
begin
  if mode = 'before' then
    insert into lab_state (k, v)
    values ('orders_ids', (select md5(string_agg(id::text, ',' order by id)) from orders))
      on conflict (k) do update set v = excluded.v;
    insert into lab_state (k, v) values ('orders_rows', (select count(*)::text from orders))
      on conflict (k) do update set v = excluded.v;
  else
    -- Data survival is checked first: the bad migration does not lose rows, it blocks the
    -- table. Reporting both facts is more honest than one "failed" flag.
    select md5(string_agg(id::text, ',' order by id)) into fingerprint from orders;
    select v into stored from lab_state where k = 'orders_ids';
    if stored is distinct from fingerprint then
      raise exception 'rows were lost or replaced by the rewrite';
    end if;

    select v into stored from lab_state where k = 'orders_rows';
    if stored is distinct from (select count(*)::text from orders) then
      raise exception 'order row count changed';
    end if;

    select c.data_type into data_type from information_schema.columns c
     where c.table_name = 'orders' and c.column_name = 'total_cents';
    if data_type = 'numeric' then
      raise exception 'REJECTED: total_cents was rewritten in place to numeric while holding ACCESS EXCLUSIVE; use the shadow-column pattern from scenario 03';
    end if;
  end if;
end $$;
