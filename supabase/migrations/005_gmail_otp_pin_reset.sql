-- Privora Gmail OTP PIN Reset
-- Run this migration after 004_recovery_and_vault_envelopes.sql.

-- PIN-only vault rows no longer require a user-managed recovery code.
ALTER TABLE public.vault_keys
    ALTER COLUMN recovery_wrapped_key DROP NOT NULL,
    ALTER COLUMN recovery_salt DROP NOT NULL,
    ALTER COLUMN recovery_nonce DROP NOT NULL;

ALTER TABLE public.vault_keys
    ADD COLUMN IF NOT EXISTS pin_wrapped_key TEXT,
    ADD COLUMN IF NOT EXISTS pin_salt TEXT,
    ADD COLUMN IF NOT EXISTS pin_nonce TEXT,
    ADD COLUMN IF NOT EXISTS pin_verifier TEXT;

-- This table is intentionally inaccessible to anon/authenticated database
-- clients. Only the service-role client inside vault-key-otp may use it.
CREATE TABLE IF NOT EXISTS public.vault_otp_envelopes (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    encrypted_master_key TEXT NOT NULL,
    nonce TEXT NOT NULL,
    crypto_version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.vault_otp_envelopes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.vault_otp_envelopes FROM anon, authenticated;
GRANT ALL ON TABLE public.vault_otp_envelopes TO service_role;

DROP TRIGGER IF EXISTS set_vault_otp_envelopes_updated_at
    ON public.vault_otp_envelopes;
CREATE TRIGGER set_vault_otp_envelopes_updated_at
    BEFORE UPDATE ON public.vault_otp_envelopes
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

COMMENT ON TABLE public.vault_otp_envelopes IS
    'Server-encrypted vault keys. Released only after recent verified email OTP authentication.';
