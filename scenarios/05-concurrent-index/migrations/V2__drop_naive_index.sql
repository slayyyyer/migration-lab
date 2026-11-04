-- Remove the blocking index so the concurrent build below starts from the same place.
drop index orders_status_naive_idx;
