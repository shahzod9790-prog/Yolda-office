
create index if not exists idx_trip_events_batch on trip_events (batch_id);
create index if not exists idx_trip_sends_trip_batch on trip_sends (trip_id, batch_number);
alter table trip_sends enable row level security;
drop policy if exists allow_all on trip_sends;
create policy allow_all on trip_sends for all using (true) with check (true);
