-- Privora Database Migration
-- Migration: 003_cloudinary_storage_migration.sql
-- Description: Adds Cloudinary storage provider columns, pending uploads tracking,
-- trash retention protections, and strict per-user ownership enforcement.
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
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS delete_after TIMESTAMPTZ;

-- 3. Make legacy Supabase storage paths and category_id nullable for records
-- Category deletion must NOT cascade-delete trash records needed to restore files!
ALTER TABLE public.photos 
    ALTER COLUMN storage_path DROP NOT NULL,
    ALTER COLUMN thumbnail_path DROP NOT NULL,
    ALTER COLUMN category_id DROP NOT NULL;

-- 4. Update foreign key on photos.category_id to ON DELETE SET NULL
-- Prevents category deletion from destroying photos in Recently Deleted
DO $$
BEGIN
    -- Find and drop existing foreign key on photos(category_id)
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_type = 'FOREIGN KEY' 
          AND table_name = 'photos' 
          AND constraint_name = 'photos_category_id_fkey'
    ) THEN
        ALTER TABLE public.photos DROP CONSTRAINT photos_category_id_fkey;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_type = 'FOREIGN KEY' 
          AND table_name = 'photos' 
          AND constraint_name = 'fk_photos_category_id'
    ) THEN
        ALTER TABLE public.photos 
            ADD CONSTRAINT fk_photos_category_id 
            FOREIGN KEY (category_id) 
            REFERENCES public.categories(id) 
            ON DELETE SET NULL;
    END IF;
END $$;

-- 5. Index for efficient querying by user, category, and storage provider
CREATE INDEX IF NOT EXISTS idx_photos_storage_provider ON public.photos(user_id, storage_provider);
CREATE INDEX IF NOT EXISTS idx_photos_cloudinary_public_id ON public.photos(cloudinary_public_id);
CREATE INDEX IF NOT EXISTS idx_photos_deleted_at ON public.photos(deleted_at);
CREATE INDEX IF NOT EXISTS idx_photos_delete_after ON public.photos(delete_after);

-- 6. Ensure existing records without explicit provider are tagged as 'supabase'
UPDATE public.photos 
SET storage_provider = 'supabase' 
WHERE storage_provider IS NULL;

-- 7. PENDING UPLOADS TABLE (Server-controlled pending upload tracking)
CREATE TABLE IF NOT EXISTS public.pending_uploads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES public.categories(id) ON DELETE CASCADE,
    photo_id UUID NOT NULL,
    full_public_id TEXT NOT NULL,
    thumbnail_public_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'committed', 'abandoned'
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_pending_uploads_user_id ON public.pending_uploads(user_id);
CREATE INDEX IF NOT EXISTS idx_pending_uploads_status ON public.pending_uploads(status);
CREATE INDEX IF NOT EXISTS idx_pending_uploads_photo_id ON public.pending_uploads(photo_id);

ALTER TABLE public.pending_uploads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pending_uploads_select_own" ON public.pending_uploads;
CREATE POLICY "pending_uploads_select_own" ON public.pending_uploads
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "pending_uploads_insert_own" ON public.pending_uploads;
CREATE POLICY "pending_uploads_insert_own" ON public.pending_uploads
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "pending_uploads_update_own" ON public.pending_uploads;
CREATE POLICY "pending_uploads_update_own" ON public.pending_uploads
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "pending_uploads_delete_own" ON public.pending_uploads;
CREATE POLICY "pending_uploads_delete_own" ON public.pending_uploads
    FOR DELETE USING (auth.uid() = user_id);

-- 8. Re-assert and strengthen Row Level Security policies for Photos
-- Enforces that photos cannot reference another user's category!
ALTER TABLE public.photos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "photos_select_own" ON public.photos;
CREATE POLICY "photos_select_own" ON public.photos
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "photos_insert_own" ON public.photos;
CREATE POLICY "photos_insert_own" ON public.photos
    FOR INSERT WITH CHECK (
        auth.uid() = user_id AND (
            category_id IS NULL OR 
            EXISTS (SELECT 1 FROM public.categories c WHERE c.id = category_id AND c.user_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS "photos_update_own" ON public.photos;
CREATE POLICY "photos_update_own" ON public.photos
    FOR UPDATE USING (auth.uid() = user_id)
    WITH CHECK (
        auth.uid() = user_id AND (
            category_id IS NULL OR 
            EXISTS (SELECT 1 FROM public.categories c WHERE c.id = category_id AND c.user_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS "photos_delete_own" ON public.photos;
CREATE POLICY "photos_delete_own" ON public.photos
    FOR DELETE USING (auth.uid() = user_id);

-- 9. AUTOMATED TRASH EXPIRY AND ABANDONED UPLOAD CLEANUP FUNCTION
-- Runs on schedule or via Edge Function backend worker
CREATE OR REPLACE FUNCTION public.clean_expired_trash()
RETURNS jsonb AS $$
DECLARE
    cleaned_count INT := 0;
    abandoned_count INT := 0;
BEGIN
    -- 1. Clean expired photos that have exceeded their 30-day delete_after retention window
    WITH expired_photos AS (
        SELECT id, storage_path, thumbnail_path, storage_provider 
        FROM public.photos
        WHERE deleted_at IS NOT NULL 
          AND delete_after IS NOT NULL 
          AND delete_after <= timezone('utc'::text, now())
    ),
    -- For legacy supabase files, clean up storage.objects
    deleted_storage AS (
        DELETE FROM storage.objects 
        WHERE name IN (SELECT storage_path FROM expired_photos WHERE storage_provider = 'supabase')
           OR name IN (SELECT thumbnail_path FROM expired_photos WHERE storage_provider = 'supabase')
    ),
    -- Delete the photo metadata rows
    deleted_rows AS (
        DELETE FROM public.photos
        WHERE id IN (SELECT id FROM expired_photos)
        RETURNING id
    )
    SELECT count(*) INTO cleaned_count FROM deleted_rows;

    -- 2. Mark pending uploads older than 2 hours as abandoned
    WITH abandoned_uploads AS (
        UPDATE public.pending_uploads 
        SET status = 'abandoned', updated_at = timezone('utc'::text, now())
        WHERE status = 'pending' 
          AND created_at < timezone('utc'::text, now()) - INTERVAL '2 hours'
        RETURNING id
    )
    SELECT count(*) INTO abandoned_count FROM abandoned_uploads;

    RETURN jsonb_build_object(
        'expired_photos_cleaned', cleaned_count,
        'abandoned_uploads_marked', abandoned_count,
        'timestamp', timezone('utc'::text, now())
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 10. Schedule automatic daily cleanup using pg_cron if available
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Run daily at 02:00 UTC
        PERFORM cron.schedule(
            'privora_daily_trash_cleanup',
            '0 2 * * *',
            'SELECT public.clean_expired_trash();'
        );
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        -- pg_cron might not be configured; backend worker or Edge function handles cleanup
        RAISE NOTICE 'pg_cron scheduling skipped: %', SQLERRM;
END $$;

-- 11. Add comments documenting the storage and trash architecture
COMMENT ON TABLE public.pending_uploads IS 'Tracks pending photo uploads bound to verified user and category before metadata commit.';
COMMENT ON COLUMN public.photos.storage_provider IS 'Defines whether encrypted bytes are stored in Supabase Storage (supabase) or Cloudinary raw authenticated assets (cloudinary).';
COMMENT ON COLUMN public.photos.cloudinary_public_id IS 'Cloudinary public ID for full encrypted photo asset (privora/{userId}/{categoryId}/{photoId}).';
COMMENT ON COLUMN public.photos.cloudinary_thumbnail_public_id IS 'Cloudinary public ID for encrypted thumbnail asset (privora/{userId}/{categoryId}/{photoId}_thumb).';
