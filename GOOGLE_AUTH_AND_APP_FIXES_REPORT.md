# Privora Google Authentication & App Fixes Report

## 1. Package Versions Inspection

From [pubspec.yaml](file:///d:/Privora/pubspec.yaml) and [pubspec.lock](file:///d:/Privora/pubspec.lock):
- **`google_sign_in`**: **`6.3.0`** (declared as `^6.2.2`, resolved to `6.3.0`)
  - Supported API: Version 6 constructor `GoogleSignIn(serverClientId: ..., scopes: ...)`, `signIn()`, and `GoogleSignInAccount.authentication`.
  - Deprecated / Removed in v7: Version 6 does not use `GoogleSignIn.instance` or `initialize()`. In strict accordance with the instructions, version 6 APIs are exclusively used without mixing version 7 APIs.
- **`supabase_flutter`**: **`2.17.2`** (declared as `^2.17.2`, resolved to `2.17.2`)
  - Uses `client.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken, accessToken: accessToken)`.

---

## 2. Root Cause Analysis: "Failed to retrieve the Google authentication token"

### The Immediate Blocker
When signing in with Google on Android using `google_sign_in: 6.3.0`, Google Play Services requires `serverClientId` to be set to the **Google Web Application Client ID** (`.apps.googleusercontent.com`).
1. **Missing or Invalid `serverClientId`**: If the app is launched without `--dart-define=GOOGLE_WEB_CLIENT_ID=...`, `Environment.googleWebClientId` defaults to `''`. When `serverClientId` is null or empty, Google Play Services authenticates the local user but **does not issue an OpenID Connect `idToken`**.
2. **Generic Error Masking**: `SupabaseAuthService` previously caught `idToken == null || idToken.isEmpty` and threw a hardcoded generic string:
   `"Failed to retrieve Google authentication token. Please ensure Google Play Services is available."`
   This masked the real root cause (missing Web Client ID audience or Google Cloud Console SHA-1/package registration mismatch) and suppressed underlying `PlatformException` codes.

---

## 3. Real Android Keystore Fingerprints & Configuration

Inspected directly from `$HOME/.android/debug.keystore` using `keytool`:

```
Keystore: C:\Users\Monish\.android\debug.keystore
Alias: androiddebugkey
Package Name: com.monish.privora
SHA-1 Fingerprint:   07:30:40:FB:67:AD:72:4F:B5:FF:A4:D4:04:BE:C7:9C:3F:AA:A0:E2
SHA-256 Fingerprint: FC:FD:AB:46:24:10:87:E8:3C:92:CE:EB:9E:87:04:DF:50:ED:5A:AB:33:0C:52:93:31:87:55:6C:7D:AE:3E:86
```
*(Note: The actual keystore SHA-1 is `07:30:40:FB:67:AD:72:4F:B5:FF:A4:D4:04:BE:C7:9C:3F:AA:A0:E2`; please ensure this exact value is registered in Google Cloud Console).*

---

## 4. Google Authentication Repairs Implemented

### A. Strict Pre-Login Validation of `GOOGLE_WEB_CLIENT_ID`
In [environment.dart](file:///d:/Privora/lib/core/config/environment.dart):
- Rejects empty values with actionable development guidance.
- Rejects placeholder values (`WEB_CLIENT_ID`, `<YOUR_GOOGLE_WEB_CLIENT_ID>`, etc.).
- Trims accidental leading/trailing whitespace and line breaks.
- Strictly enforces `.apps.googleusercontent.com` suffix.
- Guarantees no Google Client Secret is embedded anywhere in Flutter code.

### B. Robust Exception Capture & Diagnosis in `SupabaseAuthService`
In [supabase_auth_service.dart](file:///d:/Privora/lib/data/services/supabase_auth_service.dart):
- **User Cancellation Handling**: Captures `PlatformException` with cancellation codes (`sign_in_canceled`, `12501`) and returns `null` silently without showing a false failure banner.
- **Developer Error Capture (`ApiException 10: DEVELOPER_ERROR`)**: Captures SHA-1 or package mismatch and maps directly to:
  `Google Sign-In configuration error (ApiException 10: DEVELOPER_ERROR). Ensure package name "com.monish.privora" and debug SHA-1 07:30:40:FB:67:AD:72:4F:B5:FF:A4:D4:04:BE:C7:9C:3F:AA:A0:E2 are registered in Google Cloud Console under an Android OAuth 2.0 Client.`
- **Configuration Error Capture (`ApiException 12500: SIGN_IN_FAILED`)**: Provides explicit instructions to verify the Google Cloud OAuth consent screen and Google Play Services.
- **Network Error Capture (`ApiException 7 / network_error`)**: Maps cleanly to a retryable connection message.
- **Missing ID Token Diagnosis**: If `idToken` is null, logs safe diagnostics in debug mode (serverClientId presence, accessToken presence, serverAuthCode presence without leaking token data) and guides the developer to verify client IDs.
- **Supabase ID Token Exchange Errors**: Catches Supabase `AuthException` and reports if Google provider is disabled or if the token audience is unauthorized.
- **Debouncing & Timeouts**: Enforces `_isGoogleSignInRunning` guard against repeated button taps and bounded 45s / 30s timeouts.
- **Sign Out**: `signOut()` independently signs out and disconnects Google (`_googleSignIn.disconnect()`), enabling the account picker to select another Google account on subsequent login.

---

## 5. Dashboard Configuration Checklist

For Google authentication to succeed end-to-end between Google Play Services, your app, and Supabase:

### 1. Google Cloud Console (APIs & Services -> Credentials)
- **Web Application OAuth Client**:
  - Name: `Privora Web Client`
  - Client ID: `<WEB_CLIENT_ID>.apps.googleusercontent.com` (pass this to `--dart-define=GOOGLE_WEB_CLIENT_ID=...`)
- **Android OAuth Client**:
  - Name: `Privora Android Debug Client`
  - Package name: `com.monish.privora`
  - SHA-1 certificate fingerprint: `07:30:40:FB:67:AD:72:4F:B5:FF:A4:D4:04:BE:C7:9C:3F:AA:A0:E2`

### 2. Supabase Dashboard (Authentication -> Providers -> Google)
- **Enable Google provider**: Toggle ON
- **Client ID**: Enter the **Web Application Client ID** (`<WEB_CLIENT_ID>.apps.googleusercontent.com`)
- **Authorized Client IDs**: Enter both Client IDs separated by comma:
  `[Web Client ID], [Android Client ID]`
  *(Supabase receives the Web Client ID first and Android Client ID second)*

---

## 6. Status of the Four Core App Requirements

1. **Categories Single Create Action**:
   - 0 categories: Exactly 1 centered button `Create your first category`; no FABs, no header actions.
   - 1+ categories: Category grid and exactly 1 header action `New category`.
   - Debounce guard `_isOpeningCreateSheet` prevents double-taps and duplicate database rows.
2. **Optional Recovery Code System**:
   - Additive migration `004_recovery_and_vault_envelopes.sql` with nullable recovery columns.
   - 128-bit cryptographically secure code generated in `Account → Security & Privacy → Recovery Code`.
   - Requires re-entering 6-digit PIN before generating/replacing.
   - Readable code shown once in secure dialog with copy/confirm, wiped from memory on dismiss.
   - `Forgot PIN? Use recovery code` flow recovers original master vault key and sets new PIN without re-encrypting photos.
3. **Security Page Layout (Zero Overflows)**:
   - Fixed 42×42 icon container, responsive `LayoutBuilder` wrapping badges below titles on narrow screens/large font scales.
   - Verified across 320px, 360px, 412px widths and 1.0x, 1.3x, 2.0x text scalers.
4. **Reliable 6-Digit PIN Login & Isolation**:
   - `currentUser?.id` fallback and explicit `userId` parameter eliminate `PIN has not been set yet`.
   - Server PIN envelope backup syncs to fresh devices automatically.
   - State machine guarantees authenticated session before PIN lookup; failed login never creates a vault.

---

## 7. Verification & Build Results

| Verification Step | Command | Status |
|-------------------|---------|--------|
| Dependencies | `flutter pub get` | PASSED |
| Code Formatting | `dart format .` | PASSED (0 unformatted files) |
| Static Analysis | `flutter analyze` | **PASSED (0 issues found)** |
| Unit & Widget Test Suite | `flutter test` | **PASSED (90 / 90 tests, 100%)** |
| Android Build | `flutter build apk --debug` | **PASSED (`app-debug.apk` built)** |

---

## 8. Device Check & Exact Run Command

### Device Status
`adb devices -l` was executed:
```
List of devices attached
```
Device `ZA223FCV3D` is currently not detected over USB ADB on this host machine.

### Exact PowerShell Run Command
Once `ZA223FCV3D` is connected over USB (with USB Debugging enabled in Android Developer Options):

```powershell
# In PowerShell from D:\Privora:
flutter run -d ZA223FCV3D --dart-define=GOOGLE_WEB_CLIENT_ID=<YOUR_WEB_CLIENT_ID>.apps.googleusercontent.com
```

If testing on Google Chrome / Web:
```powershell
flutter run -d chrome --dart-define=GOOGLE_WEB_CLIENT_ID=<YOUR_WEB_CLIENT_ID>.apps.googleusercontent.com
```
