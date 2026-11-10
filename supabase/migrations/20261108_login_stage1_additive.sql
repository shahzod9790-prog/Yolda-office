-- ==========================================================================
-- YO'LDA — LOGIN, 1-BOSQICH (faqat QO'SHISH, hech narsa o'chirilmaydi / buzilmaydi)
-- Mavjud jadval va funksiyalar o'zgarmaydi; eski ilovalar avvalgidek ishlaydi.
-- ==========================================================================

-- 1) haydovchilar: telefon, kirish (auth) bilan bog'lanish, faol/nofaol
alter table public.drivers add column if not exists phone text;
alter table public.drivers add column if not exists auth_user_id uuid references auth.users(id) on delete set null;
alter table public.drivers add column if not exists active boolean not null default true;
create unique index if not exists drivers_phone_uidx on public.drivers (phone) where phone is not null;
create unique index if not exists drivers_auth_user_uidx on public.drivers (auth_user_id) where auth_user_id is not null;

-- 2) rol tekshiruvlari (JWT ichidagi app_metadata.role = 'office')
create or replace function public.is_office()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'office'
$$;

create or replace function public.my_driver_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.drivers where auth_user_id = auth.uid() and active
$$;

-- 3) kirish so'rovlari (haydovchi -> ofis). Token faqat haydovchi qurilmasida; bazada faqat uning xeshi.
create table if not exists public.driver_requests (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  first_name text not null,
  last_name text not null,
  phone text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  driver_id uuid references public.drivers(id) on delete set null,
  message text,
  temp_password text,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  delivered_at timestamptz
);
create index if not exists driver_requests_status_idx on public.driver_requests (status, created_at desc);
create index if not exists driver_requests_phone_idx on public.driver_requests (phone);

alter table public.driver_requests enable row level security;
revoke all on public.driver_requests from anon, authenticated;
grant select, delete on public.driver_requests to authenticated;
drop policy if exists driver_requests_office_select on public.driver_requests;
drop policy if exists driver_requests_office_delete on public.driver_requests;
create policy driver_requests_office_select on public.driver_requests for select to authenticated using (public.is_office());
create policy driver_requests_office_delete on public.driver_requests for delete to authenticated using (public.is_office());

-- 4) haydovchi uchun (login qilmasdan) ishlaydigan 3 ta funksiya — SECURITY DEFINER, qat'iy tekshiruvlar bilan
create or replace function public.request_access(p_token text, p_first text, p_last text, p_phone text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_phone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_first text := btrim(coalesce(p_first, ''));
  v_last  text := btrim(coalesce(p_last, ''));
  v_hash  text;
begin
  if length(coalesce(p_token, '')) < 32 or length(p_token) > 200 then raise exception 'BAD_TOKEN'; end if;
  if length(v_first) < 1 or length(v_first) > 60 or length(v_last) < 1 or length(v_last) > 60 then raise exception 'BAD_NAME'; end if;
  if length(v_phone) < 10 or length(v_phone) > 15 then raise exception 'BAD_PHONE'; end if;
  v_hash := encode(sha256(convert_to(p_token, 'UTF8')), 'hex');
  delete from public.driver_requests where token_hash = v_hash and status in ('pending', 'rejected');
  if exists (select 1 from public.driver_requests where token_hash = v_hash) then raise exception 'ALREADY_USED'; end if;
  if (select count(*) from public.driver_requests where phone = v_phone and status = 'pending') >= 3 then raise exception 'TOO_MANY'; end if;
  if (select count(*) from public.driver_requests where status = 'pending') >= 300 then raise exception 'TOO_MANY'; end if;
  insert into public.driver_requests (token_hash, first_name, last_name, phone) values (v_hash, v_first, v_last, v_phone);
end $$;

create or replace function public.request_status(p_token text)
returns table (status text, first_name text, last_name text, phone text, message text, password text)
language sql stable security definer set search_path = public as $$
  select r.status, r.first_name, r.last_name, r.phone, r.message, r.temp_password
  from public.driver_requests r
  where r.token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
$$;

create or replace function public.request_ack(p_token text)
returns void language sql security definer set search_path = public as $$
  update public.driver_requests
     set temp_password = null, delivered_at = now()
   where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
     and status = 'approved'
$$;

revoke all on function public.request_access(text, text, text, text) from public;
revoke all on function public.request_status(text) from public;
revoke all on function public.request_ack(text) from public;
grant execute on function public.request_access(text, text, text, text) to anon, authenticated;
grant execute on function public.request_status(text) to anon, authenticated;
grant execute on function public.request_ack(text) to anon, authenticated;
