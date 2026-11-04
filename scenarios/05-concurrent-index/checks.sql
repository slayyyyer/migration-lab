do $$
declare
  is_valid boolean;
  invalid_count integer;
begin
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

  if exists (select 1 from pg_class where relname = 'orders_status_naive_idx') then
    raise exception 'the naive index should have been dropped before the concurrent build';
  end if;
end $$;
