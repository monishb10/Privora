# Privora Supabase Setup

Project reference used by this build: `crpglfjxrxnmfgssijcq`.

## 1. Database migration

For the existing Privora project, open Supabase Dashboard → SQL Editor, copy
all of `supabase/migrations/005_gmail_otp_pin_reset.sql`, and run it once.

For a completely fresh Supabase project, run migrations `001` through `005` in
numeric order. Keep the old nullable columns during this release because they
are used only for a one-time safe upgrade of existing installed vaults.

## 2. Configure the six-digit email

Open Supabase Dashboard → Authentication → Email Templates → Magic Link.

Use a subject such as:

```text
Your Privora PIN reset code
```

Use this body (the `Token` placeholder is required):

```html
<h2>Reset your Privora PIN</h2>
<p>Your one-time verification code is:</p>
<h1 style="letter-spacing: 6px">{{ .Token }}</h1>
<p>If you did not request this, you can ignore this email.</p>
```

Save the template. The Email provider must remain enabled. Privora calls email
OTP with account creation disabled, so this cannot create a second account.

## 3. Create the Edge Function encryption secret

Run these commands in PowerShell. Do not print or share the generated value.

```powershell
cd D:\Privora
$VaultOtpSecret = node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
npx.cmd supabase secrets set "VAULT_OTP_MASTER_SECRET=$VaultOtpSecret" --project-ref crpglfjxrxnmfgssijcq
Remove-Variable VaultOtpSecret
```

Keep a private owner backup of this secret. It is not a Flutter credential and
must never be placed in `--dart-define`, source code, the APK, or Git.

## 4. Deploy the Gmail OTP key function

```powershell
cd D:\Privora
npx.cmd supabase functions deploy vault-key-otp --project-ref crpglfjxrxnmfgssijcq
```

Docker is not required for this remote deployment. A Docker warning can be
ignored if the command ends with `Deployed Functions`.

## 5. Existing Google and Cloudinary configuration

- Google Web client ID is public and already configured in
  `lib/core/config/environment.dart`.
- Android OAuth package: `com.monish.privora`.
- Debug SHA-1:
  `07:30:40:FB:67:AD:72:4F:B5:FF:A4:D4:04:BE:C7:9C:3F:AA:A0:E2`.
- Supabase Google provider must remain enabled with the Web and Android client
  IDs and the Web client secret.
- Keep the existing `cloudinary-media` function and Cloudinary Edge secrets.

## 6. Run and verify

```powershell
cd D:\Privora
flutter pub get
flutter analyze
flutter test
flutter run -d ZA223FCV3D
```

Test both flows:

1. New Google account → Create PIN → Confirm PIN → Categories.
2. Reopen app → Enter PIN → Categories.
3. Forgot PIN → Send Gmail code → enter six digits → new PIN → confirm →
   Categories with the same photos.

Supabase normally enforces a resend delay. Do not repeatedly request codes
during testing; wait for the on-screen countdown.
