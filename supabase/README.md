# Supabase (server tomoni)

Bu papka faqat hujjat/zaxira uchun — Railway uni xizmat qilmaydi (server.js faqat ro'yxatdagi fayllarni beradi).

- `migrations/20261108_login_stage1_additive.sql` — kirish tizimi, 1-bosqich (faqat QO'SHADI). Bazaga 2026-11-08 da qo'llangan.
- `migrations/20261108_login_stage1_ROLLBACK.sql` — 1-bosqichni to'liq qaytarish (kerak bo'lsa).
- `functions/office-admin/index.ts` — Edge Function: ofis xodimi haydovchi so'rovini tasdiqlaydi/rad etadi, hisobni yoqadi/o'chiradi.
  Supabase'ga yuklangan (verify_jwt = true). Maxfiy `service role` kaliti faqat serverda (Supabase o'zi beradi), ilovada emas.

Ofis xodimi hisobi: Supabase paneli → Authentication → Users → Add user (email + parol). So'ng unga rol beriladi:
`update auth.users set raw_app_meta_data = raw_app_meta_data || '{"role":"office"}' where email = '<email>';`
