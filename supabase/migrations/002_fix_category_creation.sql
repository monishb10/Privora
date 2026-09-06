-- Privora Database Idempotent Fix / Migration
-- Migration: 002_fix_category_creation.sql
-- Description: Ensures the categories table, uuid default generation, and RLS policies are properly set up.

-- 1. Ensure required cryptographic extension is available
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Ensure categories table exists with exact column names and types
CREATE TABLE IF NOT EXISTS public.categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color_value BIGINT NOT NULL,
    cover_photo_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 3. Ensure defaults are explicitly enforced even if table was created previously without defaults
ALTER TABLE public.categories ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE public.categories ALTER COLUMN created_at SET DEFAULT timezone('utc'::text, now());
ALTER TABLE public.categories ALTER COLUMN updated_at SET DEFAULT timezone('utc'::text, now());

-- 4. Safe foreign key constraint for cover_photo_id in categories (if photos table exists)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'photos') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint WHERE conname = 'fk_categories_cover_photo'
        ) THEN
            ALTER TABLE public.categories
            ADD CONSTRAINT fk_categories_cover_photo
            FOREIGN KEY (cover_photo_id)
            REFERENCES public.photos(id)
            ON DELETE SET NULL;
        END IF;
    END IF;
END $$;

-- 5. Index for fast querying by user_id
CREATE INDEX IF NOT EXISTS idx_categories_user_id ON public.categories(user_id);

-- 6. Ensure updated_at trigger function exists
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Ensure updated_at trigger is active on categories
DROP TRIGGER IF EXISTS set_categories_updated_at ON public.categories;
CREATE TRIGGER set_categories_updated_at
    BEFORE UPDATE ON public.categories
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 8. Enforce Row Level Security (RLS) - never disable RLS
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

-- 9. Strict RLS Policies for Categories (Permits only auth.uid() = user_id)
DROP POLICY IF EXISTS "categories_select_own" ON public.categories;
CREATE POLICY "categories_select_own" ON public.categories
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "categories_insert_own" ON public.categories;
CREATE POLICY "categories_insert_own" ON public.categories
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "categories_update_own" ON public.categories;
CREATE POLICY "categories_update_own" ON public.categories
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "categories_delete_own" ON public.categories;
CREATE POLICY "categories_delete_own" ON public.categories
    FOR DELETE USING (auth.uid() = user_id);
