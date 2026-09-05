# Privora

> **"Your moments. Only yours."**

Privora is a mobile-only, private, zero-knowledge cloud photo gallery built with Flutter. Photos taken within Privora or imported from your device gallery are encrypted client-side using **AES-256-GCM** before being uploaded to Supabase Storage. Unencrypted photos never touch your device's permanent storage.

---

## Key Principles & Security Architecture

1. **Zero Device Footprint**
   - Photos taken with Privora’s private camera never appear in the device gallery (`MediaStore`).
   - Photos are decrypted strictly in RAM using `Image.memory`. No disk caching or unencrypted local databases (no SQLite/Hive/Isar).
   - In-memory decrypted photo caches and the master vault key are purged immediately when the application is minimized, screen-locked, or locked manually.

2. **Hardware-Isolated 6-Digit PIN**
   - Everyday application access uses exclusively a 6-digit numeric PIN with a custom keypad.
   - **No biometrics**: Fingerprint and face authentication are deliberately omitted to eliminate biometric coercion vectors.
   - Raw PINs are never persisted; only a salted verifier derived via PBKDF2-HMAC-SHA256 (100,000 iterations) is stored in hardware-backed secure storage.
   - Progressive exponential lockouts protect against brute-force attacks after 5 incorrect attempts.

3. **Client-Side AES-256-GCM Encryption**
   - Every photo and thumbnail is encrypted with a randomly generated 256-bit Master Vault Key.
   - Each encrypted object uses a unique 12-byte random nonce and authenticated 16-byte MAC tag.
   - The master key is wrapped locally using a Key-Encryption Key (KEK) derived from the user's PIN.
   - The master key is also backed up to Supabase wrapped with a 24-character single-use recovery code. The plain recovery code is never transmitted to any server.

4. **Zero-Demo Policy**
   - No pre-seeded demo users, categories, or photos.
   - Every collection is created manually by the authenticated user.

5. **Screen & App Switcher Masking**
   - Android `FLAG_SECURE` blocks screenshots, screen recording, and blacks out recent app switcher previews.

---

## Project Structure

```
lib/
├── app/
│   ├── app.dart                   # Root MaterialApp with lifecycle listeners
│   ├── router.dart                # GoRouter routing with mobile navigation
│   ├── app_lifecycle_observer.dart # Auto-lock on background/inactive
│   └── providers.dart             # Riverpod dependency injection
├── core/
│   ├── config/                    # Environment & Supabase config
│   ├── constants/                 # Timing, security, & storage constants
│   ├── errors/                    # Typed exceptions & safe user error mapper
│   ├── security/                  # PinService, VaultCryptoService, SecureKeyService, Cleaner
│   ├── theme/                     # Design system colors, typography, theme
│   ├── utils/                     # Validators, Formatters, FileUtils
│   └── widgets/                   # PrivoraButton, EmptyState, ErrorView, ConfirmationDialog
├── data/
│   ├── models/                    # UserProfile, VaultCategory, VaultPhoto, UploadState
│   ├── repositories/              # Auth, Category, Photo, and Vault repositories
│   └── services/                  # Supabase Auth, Database, Storage, Upload, & Download
└── features/
    ├── splash/                    # Splash screen with startup cleanup & routing
    ├── onboarding/                # Welcome screen
    ├── auth/                      # Login, Register, Forgot Password, Verification
    ├── pin/                       # Create, Confirm, Unlock, Change PIN, Recover Vault
    ├── categories/                # Category 2-column grid, detail, create, & edit
    ├── camera/                    # Private in-app camera & preview
    ├── gallery/                   # Photo grid, viewer, details, move, & upload progress
    ├── trash/                     # Recently Deleted system screen with 30-day retention
    └── account/                   # Profile, storage usage, security settings, & deletion
```

---

## Configuration & Environment Flags

Privora uses `--dart-define` to inject configuration without hardcoding secrets:

| Variable | Description | Default |
| :--- | :--- | :--- |
| `SUPABASE_URL` | Your Supabase project URL | Placeholder |
| `SUPABASE_ANON_KEY` | Supabase publishable/anon public key | Placeholder |
| `ENABLE_GOOGLE_LOGIN` | Enable Google OAuth button | `false` |

*(Never embed your Supabase `service-role` secret in the application!)*

---

## Running the Application

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Run Analysis and Tests
```bash
flutter analyze
flutter test
```

### 3. Launch on Connected Android Device
```bash
flutter run -d ZA223FCV3D \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=ENABLE_GOOGLE_LOGIN=false
```

---

## Supabase Setup

Refer to [SUPABASE_SETUP.md](SUPABASE_SETUP.md) for complete SQL migration and Storage policy configuration instructions.
