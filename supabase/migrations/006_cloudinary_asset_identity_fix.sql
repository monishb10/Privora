-- ==============================================================================
-- PRIVORA MIGRATION 006: CLOUDINARY ASSET IDENTITY FIX
-- Adds dedicated column and index for Cloudinary thumbnail asset UUID
-- Strictly additive: preserves all existing columns, rows, and policies
-- ==============================================================================

ALTER TABLE public.photos
ADD COLUMN IF NOT EXISTS cloudinary_thumbnail_asset_id TEXT;

CREATE INDEX IF NOT EXISTS idx_photos_cloudinary_thumbnail_asset_id
ON public.photos(cloudinary_thumbnail_asset_id);
