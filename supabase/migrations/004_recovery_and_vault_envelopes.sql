-- Privora Database Schema Migration
-- Migration: 004_recovery_and_vault_envelopes.sql
-- Description: Makes recovery code envelope optional, adds server-side PIN envelope persistence,
-- and tracks has_recovery_code status for account security.

-- 1. Make recovery columns in vault_keys nullable (Recovery code is strictly optional)
ALTER TABLE public.vault_keys 
    ALTER COLUMN recovery_wrapped_key DROP NOT NULL,
    ALTER COLUMN recovery_salt DROP NOT NULL,
    ALTER COLUMN recovery_nonce DROP NOT NULL;

-- 2. Add columns for PIN envelope and recovery tracking
ALTER TABLE public.vault_keys
    ADD COLUMN IF NOT EXISTS pin_wrapped_key TEXT,
    ADD COLUMN IF NOT EXISTS pin_salt TEXT,
    ADD COLUMN IF NOT EXISTS pin_nonce TEXT,
    ADD COLUMN IF NOT EXISTS pin_verifier TEXT,
    ADD COLUMN IF NOT EXISTS has_recovery_code BOOLEAN DEFAULT FALSE;

-- 3. Mark existing rows with recovery codes as true
UPDATE public.vault_keys
SET has_recovery_code = TRUE
WHERE recovery_wrapped_key IS NOT NULL;
