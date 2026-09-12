# Privora Gmail OTP Update

## Final app flow

### New user

`Google Login → Create PIN → Confirm PIN → Categories`

### Returning user

`Enter PIN → Categories`

After an intentional sign-out, the user selects the Google account again and
then enters that account's PIN.

### Forgotten PIN

`Forgot PIN → Send code to signed-in Gmail → Verify 6 digits → New PIN → Confirm PIN → Categories`

The address is read from the authenticated Google/Supabase user and cannot be
edited on the reset screen.

## Removed

- Backup-code screen and route
- Backup-code modal
- Backup-code generation/replacement controls
- Old vault-recovery screen
- Account-page backup-code option
- Security-page backup-code state and error path

Existing installed accounts receive a one-time invisible key-envelope upgrade
when possible; no old code is displayed or requested.

## Added or corrected

- `ForgotPinOtpScreen` with request, verify, new-PIN, and confirm-PIN stages
- `VaultOtpService` for the protected Supabase function
- `vault-key-otp` Edge Function with JWT, account, email, and recent-OTP checks
- `005_gmail_otp_pin_reset.sql` private envelope table
- Server PIN-envelope hydration before returning-user unlock
- Complete-key validation instead of trusting a stale local setup flag
- Server PIN-envelope update after PIN changes and successful legacy unlocks
- OTP screen preservation while the user briefly opens Gmail
- Responsive security page describing the current architecture
- Tests covering the new screen and master-key-preserving PIN reset

## Required backend actions

Follow `SUPABASE_SETUP.md` before testing. The new SQL migration, email template,
Edge secret, and `vault-key-otp` deployment are mandatory.

## Validation in this workspace

- All relative Dart imports resolve.
- Delimiter checks passed across Dart and TypeScript sources.
- No deleted screen, class, or route is referenced by active source.
- No private server credential was added to Flutter or Android files.
- Every logo, font, theme-token file, and core brand widget matches the uploaded
  project byte for byte.

The current editing environment does not contain the Flutter or Dart SDK, so
`flutter analyze` and `flutter test` must be run on the Windows development
machine using the commands in `SUPABASE_SETUP.md`.
