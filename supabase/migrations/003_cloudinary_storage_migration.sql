-- Privora Database Migration
-- Migration: 003_cloudinary_storage_migration.sql
-- Description: Adds Cloudinary storage provider columns and metadata to the photos table.
-- Preserves backward compatibility for existing Supabase Storage records.

-- 1. Add storage_provider column defaulting to 'supabase' for all existing records
ALTER TABLE public.photos 
    ADD COLUMN IF NOT EXISTS storage_provider TEXT NOT NULL DEFAULT 'supabase';

-- 2. Add Cloudinary asset identifier and tracking columns, plus ensure metadata fields exist
ALTER TABLE public.photos 
    ADD COLUMN IF NOT EXISTS cloudinary_public_id TEXT,
    ADD COLUMN IF NOT EXISTS cloudinary_thumbnail_public_id TEXT,
    ADD COLUMN IF NOT EXISTS cloudinary_asset_id TEXT,
    ADD COLUMN IF NOT EXISTS cloudinary_version TEXT,
    ADD COLUMN IF NOT EXISTS encrypted_bytes BIGINT,
    ADD COLUMN IF NOT EXISTS original_filename TEXT,
    ADD COLUMN IF NOT EXISTS mime_type TEXT,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- 3. Make legacy Supabase storage paths nullable for records uploaded via Cloudinary
ALTER TABLE public.photos 
    ALTER COLUMN storage_path DROP NOT NULL,
    ALTER COLUMN thumbnail_path DROP NOT NULL;

-- 4. Index for efficient querying by user, category, and storage provider
CREATE INDEX IF NOT EXISTS idx_photos_storage_provider ON public.photos(user_id, storage_provider);
CREATE INDEX IF NOT EXISTS idx_photos_cloudinary_public_id ON public.photos(cloudinary_public_id);
CREATE INDEX IF NOT EXISTS idx_photos_deleted_at ON public.photos(deleted_at);

-- 5. Ensure existing records without explicit provider are tagged as 'supabase'
UPDATE public.photos 
SET storage_provider = 'supabase' 
WHERE storage_provider IS NULL;

-- 6. Re-assert and strengthen Row Level Security policies
ALTER TABLE public.photos ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'photos' AND policyname = 'photos_select_own'
    ) THEN
        CREATE POLICY "photos_select_own" ON public.photos
            FOR SELECT USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'photos' AND policyname = 'photos_insert_own'
    ) THEN
        CREATE POLICY "photos_insert_own" ON public.photos
            FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'photos' AND policyname = 'photos_update_own'
    ) THEN
        CREATE POLICY "photos_update_own" ON public.photos
            FOR UPDATE USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'photos' AND policyname = 'photos_delete_own'
    ) THEN
        CREATE POLICY "photos_delete_own" ON public.photos
            FOR DELETE USING (auth.uid() = user_id);
    END IF;
END $$;

-- 7. Add comment documenting the storage architecture
COMMENT ON COLUMN public.photos.storage_provider IS 'Defines whether encrypted bytes are stored in Supabase Storage (supabase) or Cloudinary raw authenticated assets (cloudinary).';
COMMENT ON COLUMN public.photos.cloudinary_public_id IS 'Cloudinary public ID for full encrypted photo asset (privora/{userId}/{categoryId}/{photoId}).';
COMMENT ON COLUMN public.photos.cloudinary_thumbnail_public_id IS 'Cloudinary public ID for encrypted thumbnail asset (privora/{userId}/{categoryId}/{photoId}_thumb).';
