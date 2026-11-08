-- Hujjat/chek rasmlari uchun Storage bucket (faqat qo'shiladi; mavjud jadvallarga tegmaydi)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('trip-photos', 'trip-photos', true, 4194304, array['image/jpeg'])
on conflict (id) do nothing;

-- Yuklash: faqat shu bucket'ga va faqat YYYY/MM/<uuid>.jpg ko'rinishidagi nom bilan.
-- O'qish public URL orqali (taxmin qilib bo'lmaydigan uuid nomlar). Ro'yxatlash, almashtirish va o'chirish ruxsat etilmaydi.
create policy "trip_photos_insert_only"
on storage.objects for insert to anon, authenticated
with check (
  bucket_id = 'trip-photos'
  and name ~ '^[0-9]{4}/(0[1-9]|1[0-2])/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'
);
