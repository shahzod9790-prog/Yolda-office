-- Km hisobi: har bir haydovchi uchun berilgan oraliqda yuk bilan va pustoy (yuksiz) kilometr.
-- Faqat o'qiydi (jadvallarni o'zgartirmaydi). Qoida ofis panelidagi hisob bilan bir xil:
--   reys boshida pustoy; ZAGRUZKA'dan keyin yuk bilan; VIGRUZKA'dan keyin yana pustoy.
--   Har bir yozuvdagi masofa (oldingi spidometr nuqtasidan) o'sha paytdagi holatga qo'shiladi,
--   va yozuv qaysi oyda (p_from..p_to) kiritilgan bo'lsa, o'sha oyga yoziladi.
--   Tyagach almashganda yangi tyagach spidometri (tractor_confirmed.newKm) yangi nuqta bo'ladi.
create or replace function public.km_report(p_from timestamptz, p_to timestamptz)
returns table (
  driver_id uuid,
  first_name text,
  last_name text,
  loaded_km numeric,
  empty_km numeric,
  trips_count integer,
  unsent_count integer,
  active_trips integer
)
language sql
stable
security invoker
set search_path = public
as $fn$
  with scope as (
    select t.id as trip_id, t.driver_id, t.start_km, t.completed
    from trips t
    where exists (select 1 from trip_events e where e.trip_id = t.id and e.at >= p_from and e.at < p_to)
  ),
  ev as (
    select e.trip_id, e.id, e.at, e.type, e.batch_id,
           case when (e.data->>'km') ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then (e.data->>'km')::numeric end as km,
           case when (e.data->>'newKm') ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then (e.data->>'newKm')::numeric end as new_km
    from trip_events e
    where e.trip_id in (select trip_id from scope)
  ),
  pts as (
    select ev.*,
           (ev.type in ('zagruzka','zapravka','vigruzka','tractor_end','trailer_end','trip_end') and ev.km is not null) as bears,
           case when ev.type in ('zagruzka','zapravka','vigruzka','tractor_end','trailer_end','trip_end') then ev.km
                when ev.type = 'tractor_confirmed' then ev.new_km end as pt,
           case when ev.type in ('zagruzka','vigruzka') then ev.type end as ms
    from ev
  ),
  cnt as (
    select pts.*,
           count(pts.pt) over w as pt_n,
           count(pts.ms) over w as ms_n
    from pts
    window w as (partition by pts.trip_id order by pts.at, pts.id rows between unbounded preceding and current row)
  ),
  dist as (
    select c.trip_id, c.at,
           greatest(c.km - coalesce(p.pt, s.start_km), 0) as d,
           coalesce(m.ms = 'zagruzka', false) as loaded
    from cnt c
    join scope s on s.trip_id = c.trip_id
    left join cnt p on p.trip_id = c.trip_id and p.pt is not null and p.pt_n = c.pt_n - 1
    left join cnt m on m.trip_id = c.trip_id and m.ms is not null
                   and m.ms_n = c.ms_n - (case when c.ms is not null then 1 else 0 end)
    where c.bears and c.at >= p_from and c.at < p_to
  ),
  km_by_driver as (
    select s.driver_id,
           coalesce(sum(case when dd.loaded then dd.d end), 0) as loaded_km,
           coalesce(sum(case when not dd.loaded then dd.d end), 0) as empty_km
    from dist dd join scope s on s.trip_id = dd.trip_id
    group by s.driver_id
  ),
  trips_by_driver as (
    select s.driver_id, count(*)::int as trips_count, (count(*) filter (where not s.completed))::int as active_trips
    from scope s
    group by s.driver_id
  ),
  unsent_by_driver as (
    select s.driver_id, count(*)::int as unsent_count
    from ev join scope s on s.trip_id = ev.trip_id
    where ev.batch_id is null and ev.type in ('zagruzka','zapravka','vigruzka')
      and ev.at >= p_from and ev.at < p_to
    group by s.driver_id
  )
  select dr.id, dr.first_name, dr.last_name,
         coalesce(k.loaded_km, 0), coalesce(k.empty_km, 0),
         tb.trips_count, coalesce(u.unsent_count, 0), tb.active_trips
  from trips_by_driver tb
  join drivers dr on dr.id = tb.driver_id
  left join km_by_driver k on k.driver_id = tb.driver_id
  left join unsent_by_driver u on u.driver_id = tb.driver_id
  order by dr.last_name, dr.first_name;
$fn$;
