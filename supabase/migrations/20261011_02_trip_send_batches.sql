
create table if not exists trip_sends (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references trips(id) on delete cascade,
  batch_number int not null,
  sent_at timestamptz not null default now()
);

alter table trip_events add column if not exists batch_id uuid references trip_sends(id);

create index if not exists idx_trip_sends_trip on trip_sends (trip_id, batch_number);
create index if not exists idx_trip_events_batch on trip_events (batch_id);

alter table trip_sends enable row level security;
drop policy if exists allow_all on trip_sends;
create policy allow_all on trip_sends for all using (true) with check (true);

-- Haydovchi "Jo'natish"ni tasdiqlaganda: yangi partiya ochiladi, hali jo'natilmagan
-- barcha eventlar shu partiyaga biriktiriladi (atomik, bitta tranzaksiyada)
create or replace function send_batch(p_trip_id uuid)
returns uuid
language plpgsql
as $$
declare
  v_batch_id uuid;
  v_next_number int;
begin
  select coalesce(max(batch_number), 0) + 1 into v_next_number from trip_sends where trip_id = p_trip_id;
  insert into trip_sends (trip_id, batch_number) values (p_trip_id, v_next_number) returning id into v_batch_id;
  update trip_events set batch_id = v_batch_id where trip_id = p_trip_id and batch_id is null;
  return v_batch_id;
end;
$$;
