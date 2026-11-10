# Supabase (server tomoni)

Bu papka faqat hujjat/zaxira uchun — Railway uni xizmat qilmaydi (server.js faqat ro'yxatdagi fayllarni beradi).

## Hozirgi baza

- Loyiha: **Yolda**, identifikator `bcolbgjeibswpahqleds`, mintaqa eu-central-1 (2026-11-09 da yaratilgan).
- Ikkala ilova (haydovchi + ofis) shu bazaga ulangan (`SUPABASE_URL` va ochiq `anon` kalit `src/source.html` boshida).
- Oldingi loyiha (`orflkpzbmluqfrebdaho`) endi ishlatilmaydi: u boshqa hisobda qolgan, unga kirish yo'qolgan. Ichida faqat sinov ma'lumoti bor edi.

## Bazani noldan tiklash (tartib bilan)

`migrations/` ichidagi fayllarni nomi bo'yicha (tartib raqami bilan) ketma-ket SQL Editor'da yoki migratsiya orqali qo'llang:

1. `20261010_01_core_schema.sql` — asosiy jadvallar va reys funksiyalari
2. `20261011_02_trip_send_batches.sql` — jo'natish partiyalari
3. `20261011_03_trip_sends_indexes_rls.sql` — indekslar
4. `20261019_04_create_trip_photos_bucket.sql` — rasmlar uchun bucket va yuklash qoidasi
5. `20261021_05_trip_photos_select_only_during_upload.sql` — yuklash vaqtida o'qish qoidasi
6. `20261026_06_add_km_report_function.sql` — km hisobi (`km_report`)
7. `20261108_login_stage1_additive.sql` — kirish tizimi, 1-bosqich (faqat QO'SHADI)

Yangi bo'sh bazada 2- va 3-fayllardagi `drop policy if exists allow_all on trip_sends;` qatori kerak emas (u siyosat hali yo'q); 7-fayldagi `drop policy ...` qatorlari ham shunday.
`20261108_login_stage1_ROLLBACK.sql` — 1-bosqichni to'liq qaytarish (kerak bo'lsa).

Keyin:
- `functions/office-admin/index.ts` — Edge Function: ofis xodimi haydovchi so'rovini tasdiqlaydi/rad etadi, hisobni yoqadi/o'chiradi.
  Supabase'ga yuklanadi (verify_jwt = true). Maxfiy `service role` kaliti faqat serverda (Supabase o'zi beradi), ilovada emas.
- Tyagach/prisep bazasi ofis panelidagi «Asosiy baza» bo'limidan kiritiladi.

## Ofis xodimi hisobi

Supabase paneli → Authentication → Users → Add user (email + parol, «Auto Confirm User» yoqilgan). So'ng unga rol beriladi:
`update auth.users set raw_app_meta_data = raw_app_meta_data || '{"role":"office"}' where email = '<email>';`
Parolni xodim ofis ilovasidagi kalit (🔑) tugmasi bilan o'zi almashtiradi.

## Hali qilinmagan (xavfsizlik)

- 2-bosqich: `allow_all` qoidalarini haqiqiy qoidalarga almashtirish (haydovchi faqat o'z reysi, ofis hammasini ko'radi).
- Supabase paneli → Authentication → Sign In / Providers → «Allow new users to sign up» ni o'chirish.
