-- Privora Database Schema Migration
-- Migration: 001_privora_schema.sql
-- Description: Creates core schema, triggers, and Row Level Security (RLS) policies for Privora.

-- 1. PROFILES TABLE
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2. VAULT_KEYS TABLE (Encrypted master key backup using recovery code)
CREATE TABLE IF NOT EXISTS public.vault_keys (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    recovery_wrapped_key TEXT NOT NULL,
    recovery_salt TEXT NOT NULL,
    recovery_nonce TEXT NOT NULL,
    crypto_version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 3. CATEGORIES TABLE
CREATE TABLE IF NOT EXISTS public.categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color_value BIGINT NOT NULL,
    cover_photo_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 4. PHOTOS TABLE
CREATE TABLE IF NOT EXISTS public.photos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES public.categories(id) ON DELETE CASCADE,
    storage_path TEXT NOT NULL,
    thumbnail_path TEXT NOT NULL,
    display_name TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    encrypted_size BIGINT NOT NULL,
    width INT,
    height INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ,
    delete_after TIMESTAMPTZ
);

-- Safe foreign key constraint for cover_photo_id in categories
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_categories_cover_photo'
    ) THEN
        ALTER TABLE public.categories
        ADD CONSTRAINT fk_categories_cover_photo
        FOREIGN KEY (cover_photo_id)
        REFERENCES public.photos(id)
        ON DELETE SET NULL;
    END IF;
END $$;

-- INDEXES
CREATE INDEX IF NOT EXISTS idx_categories_user_id ON public.categories(user_id);
CREATE INDEX IF NOT EXISTS idx_photos_user_id ON public.photos(user_id);
CREATE INDEX IF NOT EXISTS idx_photos_category_id ON public.photos(category_id);
CREATE INDEX IF NOT EXISTS idx_photos_created_at ON public.photos(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_photos_deleted_at ON public.photos(deleted_at);
CREATE INDEX IF NOT EXISTS idx_photos_delete_after ON public.photos(delete_after);

-- UPDATED_AT TRIGGER FUNCTION
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- TRIGGERS FOR UPDATED_AT
DROP TRIGGER IF EXISTS set_profiles_updated_at ON public.profiles;
CREATE TRIGGER set_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS set_vault_keys_updated_at ON public.vault_keys;
CREATE TRIGGER set_vault_keys_updated_at
    BEFORE UPDATE ON public.vault_keys
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS set_categories_updated_at ON public.categories;
CREATE TRIGGER set_categories_updated_at
    BEFORE UPDATE ON public.categories
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS set_photos_updated_at ON public.photos;
CREATE TRIGGER set_photos_updated_at
    BEFORE UPDATE ON public.photos
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- AUTH TRIGGER: Automatically create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, display_name)
    VALUES (
        NEW.id,
        COALESCE(
            NEW.raw_user_meta_data->>'full_name',
            NEW.raw_user_meta_data->>'name',
            split_part(NEW.email, '@', 1)
        )
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ENABLE ROW LEVEL SECURITY
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vault_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.photos ENABLE ROW LEVEL SECURITY;

-- 1. PROFILES RLS POLICIES
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
CREATE POLICY "profiles_select_own" ON public.profiles
    FOR SELECT USING (auth.uid() = id);

DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
CREATE POLICY "profiles_insert_own" ON public.profiles
    FOR INSERT WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own" ON public.profiles
    FOR UPDATE USING (auth.uid() = id);

DROP POLICY IF EXISTS "profiles_delete_own" ON public.profiles;
CREATE POLICY "profiles_delete_own" ON public.profiles
    FOR DELETE USING (auth.uid() = id);

-- 2. VAULT_KEYS RLS POLICIES
DROP POLICY IF EXISTS "vault_keys_select_own" ON public.vault_keys;
CREATE POLICY "vault_keys_select_own" ON public.vault_keys
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "vault_keys_insert_own" ON public.vault_keys;
CREATE POLICY "vault_keys_insert_own" ON public.vault_keys
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "vault_keys_update_own" ON public.vault_keys;
CREATE POLICY "vault_keys_update_own" ON public.vault_keys
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "vault_keys_delete_own" ON public.vault_keys;
CREATE POLICY "vault_keys_delete_own" ON public.vault_keys
    FOR DELETE USING (auth.uid() = user_id);

-- 3. CATEGORIES RLS POLICIES
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

-- 4. PHOTOS RLS POLICIES
DROP POLICY IF EXISTS "photos_select_own" ON public.photos;
CREATE POLICY "photos_select_own" ON public.photos
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "photos_insert_own" ON public.photos;
CREATE POLICY "photos_insert_own" ON public.photos
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "photos_update_own" ON public.photos;
CREATE POLICY "photos_update_own" ON public.photos
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "photos_delete_own" ON public.photos;
CREATE POLICY "photos_delete_own" ON public.photos
    FOR DELETE USING (auth.uid() = user_id);
