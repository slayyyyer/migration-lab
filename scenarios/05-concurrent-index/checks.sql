create table if not exists lab_state (k text primary key, v text);

-- psql does not interpolate :variables inside dollar-quoted blocks, so the mode is
-- passed through a session setting instead of pasted into the DO block.
select set_config('lab.mode', :'mode', false);

do $$
declare
  mode text := current_setting('lab.mode');
  is_valid boolean;
  invalid_count integer;
  stored text;
begin
  if mode = 'before' then
    -- The index this scenario is about does not exist yet, so there is nothing to assert.
    -- Recording the row count lets the after-check prove the builds moved no data.
    insert into lab_state (k, v) values ('orders_rows', (select count(*)::text from orders))
      on conflict (k) do update set v = excluded.v;
  else
    if exists (select 1 from pg_class where relname = 'orders_status_naive_idx') then
      raise exception 'the naive index should have been dropped before the concurrent build';
    end if;

    select i.indisvalid into is_valid
      from pg_index i
      join pg_class c on c.oid = i.indexrelid
     where c.relname = 'orders_status_idx';

    if is_valid is null then
      raise exception 'orders_status_idx was not created';
    end if;

    if not is_valid then
      raise exception 'orders_status_idx exists but is INVALID — a concurrent build failed and left the index behind';
    end if;

    select count(*) into invalid_count
      from pg_index i
      join pg_class c on c.oid = i.indexrelid
     where c.relnamespace = 'public'::regnamespace and not i.indisvalid;

    if invalid_count > 0 then
      raise exception '% invalid index(es) left behind', invalid_count;
    end if;

    select v into stored from lab_state where k = 'orders_rows';
    if stored is distinct from (select count(*)::text from orders) then
      raise exception 'order row count changed across the index builds';
    end if;
  end if;
end $$;
