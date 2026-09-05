# Supabase Setup Guide for Privora

Follow these exact steps to prepare your Supabase backend for Privora.

---

## 1. Create a Supabase Project

1. Log into your [Supabase Dashboard](https://supabase.com/dashboard).
2. Click **New project**, select an organization, enter a project name (e.g., `Privora Vault`), choose a secure database password, and choose your preferred geographic region.
3. Wait for the project initialization to complete.

---

## 2. Execute Database Schema Migration

1. In your Supabase project dashboard, navigate to the **SQL Editor** (terminal icon in left sidebar).
2. Click **New query**.
3. Open the file [`supabase/migrations/001_privora_schema.sql`](supabase/migrations/001_privora_schema.sql) in this repository, copy its entire contents, and paste it into the query editor.
4. Click **Run** (or `Ctrl+Enter`).
5. Verify that the query executes successfully. This creates:
   - `public.profiles` table and trigger on `auth.users`.
   - `public.vault_keys` table for recovery-wrapped master keys.
   - `public.categories` table for user-created categories.
   - `public.photos` table for encrypted metadata.
   - Strict Row Level Security (RLS) policies ensuring users can only read and write their own data (`auth.uid() = user_id`).

---

## 3. Configure Supabase Storage

1. Open [`supabase/migrations/storage_policies.sql`](supabase/migrations/storage_policies.sql) in this repository.
2. In the **SQL Editor**, paste and run the contents of `storage_policies.sql`.
3. This creates:
   - Private bucket named `private-photos` (`public = false`, 50MB file limit).
   - Storage RLS policies restricting SELECT, INSERT, UPDATE, and DELETE operations exclusively to paths where the root folder matches `auth.uid()`.
4. To verify:
   - In the left sidebar, navigate to **Storage** -> **Buckets**.
   - Confirm that the `private-photos` bucket is visible and that the **Public** badge is **OFF**.

---

## 4. Run Seed Verification

1. In the **SQL Editor**, run the contents of [`supabase/migrations/seed.sql`](supabase/migrations/seed.sql).
2. Confirm the status message: `"Privora database schema ready. Zero demo data seeded."`.

---

## 5. Configure Authentication

### Email / Password Auth (Default)
1. Go to **Authentication** -> **Providers** -> **Email**.
2. Ensure **Enable Email provider** is enabled.
3. (Optional for testing) You can toggle **Confirm email** off if you wish to bypass email confirmation links during development.

### Google OAuth (Optional)
If you wish to enable Google sign-in:
1. In the Google Cloud Console, create OAuth 2.0 Client Credentials (Android & Web).
2. In Supabase Dashboard, navigate to **Authentication** -> **Providers** -> **Google**.
3. Enable Google and paste your Client ID and Client Secret.
4. Add the redirect URL: `com.monish.privora://login-callback`.
5. In your flutter launch command, pass `--dart-define=ENABLE_GOOGLE_LOGIN=true`.

---

## 6. Retrieve API Credentials

1. Navigate to **Project Settings** (gear icon in sidebar) -> **API**.
2. Copy the following values:
   - **Project URL** (e.g. `https://xyzcompany.supabase.co`)
   - **Project API Keys** -> `anon` / `public` key

> ⚠️ **CRITICAL SECURITY WARNING**:
> NEVER copy or place the `service_role` key in the mobile application. The `service_role` key bypasses Row Level Security and must remain private on trusted backend infrastructure.

---

## 7. Run Privora with Configured Credentials

Run the application on your connected Android device with `--dart-define` parameters:

```bash
flutter run -d ZA223FCV3D \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-publishable-key \
  --dart-define=ENABLE_GOOGLE_LOGIN=false
```
