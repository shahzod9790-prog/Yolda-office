-- 1-bosqichni to'liq qaytarish (faqat shu bosqich qo'shgan narsalarni olib tashlaydi)
drop function if exists public.request_ack(text);
drop function if exists public.request_status(text);
drop function if exists public.request_access(text, text, text, text);
drop table if exists public.driver_requests;
drop function if exists public.my_driver_id();
drop function if exists public.is_office();
drop index if exists public.drivers_auth_user_uidx;
drop index if exists public.drivers_phone_uidx;
alter table public.drivers drop column if exists active;
alter table public.drivers drop column if exists auth_user_id;
alter table public.drivers drop column if exists phone;
