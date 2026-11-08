-- Storage API runs "INSERT ... RETURNING" on upload; without a SELECT policy the insert-only policy gives 403.
-- This SELECT policy applies ONLY while the current Storage operation is an upload, so objects still cannot be listed
-- (public bucket => images are served by URL without any policy; no list/update/delete for anon).
create policy "trip_photos_select_only_during_upload"
on storage.objects
for select
to anon, authenticated
using (
  bucket_id = 'trip-photos'
  and storage.allow_only_operation('storage.object.upload')
);
