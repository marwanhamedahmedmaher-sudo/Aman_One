-- ============================================================================
-- 025_task_visit_photos_storage.sql — Private bucket for visit photos
--
-- Each field visit requires a photo of the place. Photos are uploaded directly
-- from the app to a PRIVATE bucket, then the object path is passed to
-- record_task_visit() (024). Path convention:  {rep_id}/{task_id}/{uuid}.jpg
--
-- RLS on storage.objects isolates reps by the first path segment (their uid),
-- mirroring the rep_id := auth.uid() write rule on task_visits. Supervisors and
-- admins can read every rep's photos for oversight. Photos are immutable to
-- reps (insert + read only) so a visit's proof can't be swapped after the fact.
-- ============================================================================

-- 1. Private bucket (idempotent).
INSERT INTO storage.buckets (id, name, public)
VALUES ('task-visit-photos', 'task-visit-photos', false)
ON CONFLICT (id) DO NOTHING;

-- 2. Policies on storage.objects, scoped to this bucket.

-- Rep uploads only into their own {uid}/... prefix.
DROP POLICY IF EXISTS task_visit_photos_rep_insert ON storage.objects;
CREATE POLICY task_visit_photos_rep_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'task-visit-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Rep reads their own photos.
DROP POLICY IF EXISTS task_visit_photos_rep_select ON storage.objects;
CREATE POLICY task_visit_photos_rep_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'task-visit-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Supervisor / admin read every rep's photos (oversight).
DROP POLICY IF EXISTS task_visit_photos_oversight_select ON storage.objects;
CREATE POLICY task_visit_photos_oversight_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'task-visit-photos'
    AND (public.is_supervisor() OR public.is_admin())
  );

-- No UPDATE/DELETE policy for authenticated users — visit photos are immutable
-- proof. Service role (Dashboard) bypasses RLS for cleanup if ever needed.

-- ============================================================================
-- End of 025_task_visit_photos_storage.sql
-- ============================================================================
