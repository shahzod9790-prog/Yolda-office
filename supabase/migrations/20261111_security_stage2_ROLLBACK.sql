-- 2-bosqich xavfsizlikni TO'LIQ qaytarish (20261111_security_stage2_rls.sql dan oldingi holat).
-- Faqat kerak bo'lsa ishlating: baza yana "hamma uchun ochiq" holatga qaytadi.
begin;

drop policy if exists drivers_office_all on public.drivers;
drop policy if exists drivers_self_select on public.drivers;
drop policy if exists tractors_office_all on public.tractors;
drop policy if exists tractors_driver_select on public.tractors;
drop policy if exists trailers_office_all on public.trailers;
drop policy if exists trailers_driver_select on public.trailers;
drop policy if exists trips_office_all on public.trips;
drop policy if exists trips_driver_select on public.trips;
drop policy if exists trip_events_office_all on public.trip_events;
drop policy if exists trip_events_driver_select on public.trip_events;
drop policy if exists trip_events_driver_insert on public.trip_events;
drop policy if exists trip_events_driver_update on public.trip_events;
drop policy if exists trip_sends_office_all on public.trip_sends;
drop policy if exists trip_sends_driver_select on public.trip_sends;
drop policy if exists trip_sends_driver_insert on public.trip_sends;

create policy allow_all on public.drivers for all using (true) with check (true);
create policy allow_all on public.tractors for all using (true) with check (true);
create policy allow_all on public.trailers for all using (true) with check (true);
create policy allow_all on public.trips for all using (true) with check (true);
create policy allow_all on public.trip_events for all using (true) with check (true);
create policy allow_all on public.trip_sends for all using (true) with check (true);

grant all on public.drivers, public.tractors, public.trailers, public.trips, public.trip_events, public.trip_sends to anon;

-- asl (oldingi) reys funksiyalari — 20261010_01_core_schema.sql dan
create or replace function start_trip(
  p_driver_first text, p_driver_last text,
  p_tractor_number text, p_trailer_number text,
  p_start_km numeric, p_start_moto_chas numeric, p_moto_chas_photo jsonb
) returns uuid
language plpgsql
as $$
declare
  v_driver_id uuid;
  v_tractor_id uuid;
  v_tractor_status text;
  v_trailer_id uuid;
  v_trailer_status text;
  v_trip_id uuid;
begin
  select id into v_driver_id from drivers where first_name = p_driver_first and last_name = p_driver_last limit 1;
  if v_driver_id is null then
    insert into drivers (first_name, last_name) values (p_driver_first, p_driver_last) returning id into v_driver_id;
  end if;

  select id, status into v_tractor_id, v_tractor_status from tractors where number = p_tractor_number for update;
  if v_tractor_id is null then
    insert into tractors (number, status) values (p_tractor_number, 'active') returning id into v_tractor_id;
  elsif v_tractor_status = 'active' then
    raise exception 'TRACTOR_BUSY';
  else
    update tractors set status = 'active' where id = v_tractor_id;
  end if;

  select id, status into v_trailer_id, v_trailer_status from trailers where number = p_trailer_number for update;
  if v_trailer_id is null then
    insert into trailers (number, status) values (p_trailer_number, 'active') returning id into v_trailer_id;
  elsif v_trailer_status = 'active' then
    raise exception 'TRAILER_BUSY';
  else
    update trailers set status = 'active' where id = v_trailer_id;
  end if;

  insert into trips (driver_id, tractor_id, trailer_id, tractor_number, trailer_number, start_km, start_moto_chas, moto_chas_photo)
  values (v_driver_id, v_tractor_id, v_trailer_id, p_tractor_number, p_trailer_number, p_start_km, p_start_moto_chas, p_moto_chas_photo)
  returning id into v_trip_id;

  return v_trip_id;
end;
$$;

-- Tyagachni yakunlash: eski tyagach darhol FREE bo'ladi (spec talabiga ko'ra)
create or replace function finish_tractor(p_trip_id uuid, p_km numeric, p_address text)
returns void
language plpgsql
as $$
declare
  v_tractor_id uuid;
begin
  select tractor_id into v_tractor_id from trips where id = p_trip_id;
  update tractors set status = 'free' where id = v_tractor_id;
  insert into trip_events (trip_id, type, data)
  values (p_trip_id, 'tractor_end', jsonb_build_object('km', p_km, 'address', p_address));
end;
$$;

-- Yangi tyagachni qabul qilish: band qiladi (hali tasdiqlanmagan, lekin rezerv qilinadi)
create or replace function accept_tractor(p_trip_id uuid, p_new_tractor_number text, p_new_km numeric, p_address text)
returns void
language plpgsql
as $$
declare
  v_new_id uuid;
  v_status text;
begin
  select id, status into v_new_id, v_status from tractors where number = p_new_tractor_number for update;
  if v_new_id is null then
    insert into tractors (number, status) values (p_new_tractor_number, 'active') returning id into v_new_id;
  elsif v_status = 'active' then
    raise exception 'TRACTOR_BUSY';
  else
    update tractors set status = 'active' where id = v_new_id;
  end if;

  insert into trip_events (trip_id, type, data)
  values (p_trip_id, 'tractor_accepted', jsonb_build_object('newTractorNumber', p_new_tractor_number, 'newKm', p_new_km, 'address', p_address));
end;
$$;

-- Tyagach almashinuvini yakuniy tasdiqlash
create or replace function confirm_tractor(p_trip_id uuid, p_new_tractor_number text, p_new_km numeric)
returns void
language plpgsql
as $$
declare
  v_new_tractor_id uuid;
begin
  select id into v_new_tractor_id from tractors where number = p_new_tractor_number;
  update trips set tractor_id = v_new_tractor_id, tractor_number = p_new_tractor_number where id = p_trip_id;
  insert into trip_events (trip_id, type, data)
  values (p_trip_id, 'tractor_confirmed', jsonb_build_object('newTractorNumber', p_new_tractor_number, 'newKm', p_new_km));
end;
$$;

-- Prisepni yakunlash: darhol PRISEPSIZ holatga o'tadi, eski prisep FREE bo'ladi
create or replace function finish_trailer(p_trip_id uuid, p_km numeric, p_address text, p_moto_chas numeric, p_moto_chas_photo jsonb, p_load_status text, p_photos jsonb)
returns void
language plpgsql
as $$
declare
  v_trailer_id uuid;
begin
  select trailer_id into v_trailer_id from trips where id = p_trip_id;
  if v_trailer_id is not null then
    update trailers set status = 'free' where id = v_trailer_id;
  end if;
  update trips set trailer_id = null, trailer_number = null where id = p_trip_id;
  insert into trip_events (trip_id, type, data)
  values (p_trip_id, 'trailer_end', jsonb_build_object('km', p_km, 'address', p_address, 'motoChas', p_moto_chas, 'motoChasPhoto', p_moto_chas_photo, 'loadStatus', p_load_status, 'photos', p_photos));
end;
$$;

-- Yangi prisepni qabul qilish: band qiladi (rezerv)
create or replace function accept_trailer(p_trip_id uuid, p_new_trailer_number text, p_new_km numeric, p_address text, p_moto_chas numeric, p_moto_chas_photo jsonb, p_load_status text, p_photos jsonb)
returns void
language plpgsql
as $$
declare
  v_new_id uuid;
  v_status text;
begin
  select id, status into v_new_id, v_status from trailers where number = p_new_trailer_number for update;
  if v_new_id is null then
    insert into trailers (number, status) values (p_new_trailer_number, 'active') returning id into v_new_id;
  elsif v_status = 'active' then
    raise exception 'TRAILER_BUSY';
  else
    update trailers set status = 'active' where id = v_new_id;
  end if;

  insert into trip_events (trip_id, type, data)
  values (p_trip_id, 'trailer_accepted', jsonb_build_object('newTrailerNumber', p_new_trailer_number, 'newKm', p_new_km, 'address', p_address, 'motoChas', p_moto_chas, 'motoChasPhoto', p_moto_chas_photo, 'loadStatus', p_load_status, 'photos', p_photos));
end;
$$;

-- Prisep almashinuvini yakuniy tasdiqlash
create or replace function confirm_trailer(p_trip_id uuid, p_new_trailer_number text, p_moto_chas numeric)
returns void
language plpgsql
as $$
declare
  v_new_trailer_id uuid;
begin
  select id into v_new_trailer_id from trailers where number = p_new_trailer_number;
  update trips set trailer_id = v_new_trailer_id, trailer_number = p_new_trailer_number where id = p_trip_id;
  insert into trip_events (trip_id, type, data)
  values (p_trip_id, 'trailer_confirmed', jsonb_build_object('newTrailerNumber', p_new_trailer_number, 'motoChas', p_moto_chas));
end;
$$;

-- Reysni butunlay yakunlash: tyagach va prisep ikkalasi ham FREE bo'ladi
create or replace function end_trip(p_trip_id uuid)
returns void
language plpgsql
as $$
declare
  v_tractor_id uuid;
  v_trailer_id uuid;
begin
  select tractor_id, trailer_id into v_tractor_id, v_trailer_id from trips where id = p_trip_id;
  update tractors set status = 'free' where id = v_tractor_id;
  if v_trailer_id is not null then
    update trailers set status = 'free' where id = v_trailer_id;
  end if;
  update trips set completed = true where id = p_trip_id;
end;
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.start_trip(text,text,text,text,numeric,numeric,jsonb)',
    'public.accept_tractor(uuid,text,numeric,text)',
    'public.accept_trailer(uuid,text,numeric,text,numeric,jsonb,text,jsonb)',
    'public.confirm_tractor(uuid,text,numeric)',
    'public.confirm_trailer(uuid,text,numeric)',
    'public.end_trip(uuid)',
    'public.finish_tractor(uuid,numeric,text)',
    'public.finish_trailer(uuid,numeric,text,numeric,jsonb,text,jsonb)',
    'public.send_batch(uuid)',
    'public.km_report(timestamptz,timestamptz)'
  ] loop
    execute format('grant execute on function %s to public', f);
  end loop;
end $$;

drop function if exists public.can_touch_trip(uuid);

alter policy trip_photos_insert_only on storage.objects to anon, authenticated;
alter policy trip_photos_select_only_during_upload on storage.objects to anon, authenticated;

commit;
