-- 2-bosqich xavfsizlik: "allow_all" (hamma uchun ochiq) qoidalari o'rniga haqiqiy qoidalar.
--   * Ofis xodimi (app_metadata.role = 'office')  -> hamma narsani ko'radi va boshqaradi.
--   * Haydovchi (faol, hisobi bog'langan)          -> faqat o'z reyslari, o'z yozuvlari; tyagach/prisep ro'yxatini faqat o'qiydi.
--   * Kirmagan odam (anon)                          -> hech qanday jadvalni o'qiy/yoza olmaydi
--                                                     (faqat request_access/status/ack funksiyalari ochiq qoladi).
-- Reys funksiyalari SECURITY DEFINER bo'ldi va har birida "bu reys shu haydovchinikimi?" tekshiruvi bor.
-- start_trip endi haydovchini ism bo'yicha emas, kirgan hisob bo'yicha aniqlaydi (bir xil ismli ikki haydovchi aralashmaydi).
-- Qaytarish: 20261111_security_stage2_ROLLBACK.sql

begin;

-- ---------- yordamchi: bu reysga tegish mumkinmi ----------
create or replace function public.can_touch_trip(p_trip_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_office()
      or exists (select 1 from public.trips t where t.id = p_trip_id and t.driver_id = public.my_driver_id())
$$;
revoke all on function public.can_touch_trip(uuid) from public, anon;
grant execute on function public.can_touch_trip(uuid) to authenticated;

-- ---------- eski "hamma uchun ochiq" qoidalarni olib tashlash ----------
drop policy if exists allow_all on public.drivers;
drop policy if exists allow_all on public.tractors;
drop policy if exists allow_all on public.trailers;
drop policy if exists allow_all on public.trips;
drop policy if exists allow_all on public.trip_events;
drop policy if exists allow_all on public.trip_sends;

-- kirmagan odam jadvallarga umuman tegmaydi
revoke all on public.drivers, public.tractors, public.trailers, public.trips, public.trip_events, public.trip_sends from anon;

-- ---------- drivers ----------
create policy drivers_office_all on public.drivers for all to authenticated
  using (public.is_office()) with check (public.is_office());
create policy drivers_self_select on public.drivers for select to authenticated
  using (auth_user_id = auth.uid());

-- ---------- tractors / trailers ----------
create policy tractors_office_all on public.tractors for all to authenticated
  using (public.is_office()) with check (public.is_office());
create policy tractors_driver_select on public.tractors for select to authenticated
  using (public.my_driver_id() is not null);
create policy trailers_office_all on public.trailers for all to authenticated
  using (public.is_office()) with check (public.is_office());
create policy trailers_driver_select on public.trailers for select to authenticated
  using (public.my_driver_id() is not null);

-- ---------- trips (haydovchi faqat o'qiydi; o'zgartirish faqat funksiyalar orqali) ----------
create policy trips_office_all on public.trips for all to authenticated
  using (public.is_office()) with check (public.is_office());
create policy trips_driver_select on public.trips for select to authenticated
  using (driver_id = public.my_driver_id());

-- ---------- trip_events (haydovchi o'z reysiga yozadi, o'chira olmaydi) ----------
create policy trip_events_office_all on public.trip_events for all to authenticated
  using (public.is_office()) with check (public.is_office());
create policy trip_events_driver_select on public.trip_events for select to authenticated
  using (public.can_touch_trip(trip_id));
create policy trip_events_driver_insert on public.trip_events for insert to authenticated
  with check (public.can_touch_trip(trip_id));
create policy trip_events_driver_update on public.trip_events for update to authenticated
  using (public.can_touch_trip(trip_id)) with check (public.can_touch_trip(trip_id));

-- ---------- trip_sends ----------
create policy trip_sends_office_all on public.trip_sends for all to authenticated
  using (public.is_office()) with check (public.is_office());
create policy trip_sends_driver_select on public.trip_sends for select to authenticated
  using (public.can_touch_trip(trip_id));
create policy trip_sends_driver_insert on public.trip_sends for insert to authenticated
  with check (public.can_touch_trip(trip_id));

-- ---------- reys funksiyalari: SECURITY DEFINER + egalik tekshiruvi ----------
create or replace function public.start_trip(p_driver_first text, p_driver_last text, p_tractor_number text, p_trailer_number text, p_start_km numeric, p_start_moto_chas numeric, p_moto_chas_photo jsonb)
returns uuid language plpgsql security definer set search_path = public
as $function$
declare
  v_driver_id uuid;
  v_tractor_id uuid;
  v_tractor_status text;
  v_trailer_id uuid;
  v_trailer_status text;
  v_trip_id uuid;
begin
  -- p_driver_first / p_driver_last eski ilova bilan moslik uchun qoldirilgan, ishlatilmaydi
  v_driver_id := public.my_driver_id();
  if v_driver_id is null then raise exception 'NOT_DRIVER'; end if;

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
$function$;

create or replace function public.accept_tractor(p_trip_id uuid, p_new_tractor_number text, p_new_km numeric, p_address text)
returns void language plpgsql security definer set search_path = public
as $function$
declare
  v_new_id uuid;
  v_status text;
begin
  if not public.can_touch_trip(p_trip_id) then raise exception 'FORBIDDEN'; end if;
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
$function$;

create or replace function public.accept_trailer(p_trip_id uuid, p_new_trailer_number text, p_new_km numeric, p_address text, p_moto_chas numeric, p_moto_chas_photo jsonb, p_load_status text, p_photos jsonb)
returns void language plpgsql security definer set search_path = public
as $function$
declare
  v_new_id uuid;
  v_status text;
begin
  if not public.can_touch_trip(p_trip_id) then raise exception 'FORBIDDEN'; end if;
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
$function$;

create or replace function public.confirm_tractor(p_trip_id uuid, p_new_tractor_number text, p_new_km numeric)
returns void language plpgsql security definer set search_path = public
as $function$
declare
  v_new_tractor_id uuid;
begin
  if not public.can_touch_trip(p_trip_id) then raise exception 'FORBIDDEN'; end if;
  select id into v_new_tractor_id from tractors where number = p_new_tractor_number;
  update trips set tractor_id = v_new_tractor_id, tractor_number = p_new_tractor_number where id = p_trip_id;
  insert into trip_events (trip_id, type, data)
  values (p_trip_id, 'tractor_confirmed', jsonb_build_object('newTractorNumber', p_new_tractor_number, 'newKm', p_new_km));
end;
$function$;

create or replace function public.confirm_trailer(p_trip_id uuid, p_new_trailer_number text, p_moto_chas numeric)
returns void language plpgsql security definer set search_path = public
as $function$
declare
  v_new_trailer_id uuid;
begin
  if not public.can_touch_trip(p_trip_id) then raise exception 'FORBIDDEN'; end if;
  select id into v_new_trailer_id from trailers where number = p_new_trailer_number;
  update trips set trailer_id = v_new_trailer_id, trailer_number = p_new_trailer_number where id = p_trip_id;
  insert into trip_events (trip_id, type, data)
  values (p_trip_id, 'trailer_confirmed', jsonb_build_object('newTrailerNumber', p_new_trailer_number, 'motoChas', p_moto_chas));
end;
$function$;

create or replace function public.end_trip(p_trip_id uuid)
returns void language plpgsql security definer set search_path = public
as $function$
declare
  v_tractor_id uuid;
  v_trailer_id uuid;
begin
  if not public.can_touch_trip(p_trip_id) then raise exception 'FORBIDDEN'; end if;
  select tractor_id, trailer_id into v_tractor_id, v_trailer_id from trips where id = p_trip_id;
  update tractors set status = 'free' where id = v_tractor_id;
  if v_trailer_id is not null then
    update trailers set status = 'free' where id = v_trailer_id;
  end if;
  update trips set completed = true where id = p_trip_id;
end;
$function$;

create or replace function public.finish_tractor(p_trip_id uuid, p_km numeric, p_address text)
returns void language plpgsql security definer set search_path = public
as $function$
declare
  v_tractor_id uuid;
begin
  if not public.can_touch_trip(p_trip_id) then raise exception 'FORBIDDEN'; end if;
  select tractor_id into v_tractor_id from trips where id = p_trip_id;
  update tractors set status = 'free' where id = v_tractor_id;
  insert into trip_events (trip_id, type, data)
  values (p_trip_id, 'tractor_end', jsonb_build_object('km', p_km, 'address', p_address));
end;
$function$;

create or replace function public.finish_trailer(p_trip_id uuid, p_km numeric, p_address text, p_moto_chas numeric, p_moto_chas_photo jsonb, p_load_status text, p_photos jsonb)
returns void language plpgsql security definer set search_path = public
as $function$
declare
  v_trailer_id uuid;
begin
  if not public.can_touch_trip(p_trip_id) then raise exception 'FORBIDDEN'; end if;
  select trailer_id into v_trailer_id from trips where id = p_trip_id;
  if v_trailer_id is not null then
    update trailers set status = 'free' where id = v_trailer_id;
  end if;
  update trips set trailer_id = null, trailer_number = null where id = p_trip_id;
  insert into trip_events (trip_id, type, data)
  values (p_trip_id, 'trailer_end', jsonb_build_object('km', p_km, 'address', p_address, 'motoChas', p_moto_chas, 'motoChasPhoto', p_moto_chas_photo, 'loadStatus', p_load_status, 'photos', p_photos));
end;
$function$;

-- send_batch va km_report (invoker) RLS ostida ishlaydi: haydovchi faqat o'z ma'lumotini ko'radi; anon'dan yopiladi
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
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- ---------- rasm yuklash: faqat kirgan foydalanuvchi ----------
alter policy trip_photos_insert_only on storage.objects to authenticated;
alter policy trip_photos_select_only_during_upload on storage.objects to authenticated;

commit;
