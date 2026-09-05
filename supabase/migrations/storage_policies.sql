-- Privora Supabase Storage Policies
-- Bucket: private-photos
-- Storage is strictly private. All image files are pre-encrypted with AES-256-GCM.

-- 1. Create the private bucket if it doesn't already exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'private-photos',
    'private-photos',
    false,
    52428800, -- 50MB per file
    ARRAY['application/octet-stream', 'application/encrypted']
)
ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = 52428800;

-- 2. Storage RLS Policies
-- Users can only read objects in their own folder: {userId}/photos/* and {userId}/thumbnails/*
DROP POLICY IF EXISTS "Users can read own encrypted photos" ON storage.objects;
CREATE POLICY "Users can read own encrypted photos"
ON storage.objects FOR SELECT
USING (
    bucket_id = 'private-photos'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Users can only insert objects into their own folder: {userId}/*
DROP POLICY IF EXISTS "Users can upload own encrypted photos" ON storage.objects;
CREATE POLICY "Users can upload own encrypted photos"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'private-photos'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Users can only update objects in their own folder
DROP POLICY IF EXISTS "Users can update own encrypted photos" ON storage.objects;
CREATE POLICY "Users can update own encrypted photos"
ON storage.objects FOR UPDATE
USING (
    bucket_id = 'private-photos'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Users can only delete objects in their own folder
DROP POLICY IF EXISTS "Users can delete own encrypted photos" ON storage.objects;
CREATE POLICY "Users can delete own encrypted photos"
ON storage.objects FOR DELETE
USING (
    bucket_id = 'private-photos'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
);
