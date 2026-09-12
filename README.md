# Privora

> Your moments. Only yours.

Privora is a Flutter private-gallery application. Full photos and thumbnails
are encrypted on the device with AES-256-GCM before they are uploaded to
Cloudinary. Supabase provides Google authentication, private metadata, and
protected Edge Functions.

## Authentication flow

### New Google account

1. Continue with Google.
2. Create a six-digit PIN.
3. Confirm the PIN.
4. Open Categories.

### Returning Google account

1. A retained Google/Supabase session opens directly at Enter PIN.
2. After an intentional sign-out, Continue with Google is required again.
3. Enter the account's existing PIN.
4. If the PIN is forgotten, request a six-digit code at the Gmail address
   already attached to that Google account, verify it, and create a new PIN.

There is no user-managed backup-code screen or onboarding gate.

## Data placement

| Data | Location |
|---|---|
| Encrypted full photos and thumbnails | Cloudinary authenticated raw assets |
| Categories and photo metadata | Supabase PostgreSQL with RLS |
| Google identity and sessions | Supabase Auth |
| PIN-wrapped vault key | Per-user device secure storage and `vault_keys` |
| Gmail-OTP reset envelope | Private `vault_otp_envelopes` table, Edge Function only |

Raw PINs, Cloudinary API secrets, the Supabase service-role key, and the OTP
envelope secret must never be included in Flutter source or an APK.

## Design

The supplied Privora branding is unchanged:

- Logos and launcher/splash assets remain in `assets/branding/`.
- Manrope, Inter, and Playfair Display remain in `assets/fonts/`.
- Colors, typography, motion, cards, and navigation remain in `lib/core/theme/`
  and `lib/core/widgets/`.

## Setup

Complete [SUPABASE_SETUP.md](SUPABASE_SETUP.md) before testing a new account.
The Google Web client ID, Supabase URL, and publishable key already have public
defaults in `lib/core/config/environment.dart`, so they do not need to be typed
on every run.

```powershell
cd D:\Privora
flutter pub get
flutter analyze
flutter test
flutter run -d ZA223FCV3D
```

To build an installable APK:

```powershell
flutter build apk --release
```

The APK is created at `build\app\outputs\flutter-apk\app-release.apk`.
