# Privora Security & Cryptographic Architecture

Privora is architected under zero-knowledge and zero-device-persistence security models. This document details the cryptographic algorithms, key lifecycle, threat mitigations, and known limitations.

---

## 1. Cryptographic Primitives

Privora employs standard, audited cryptographic algorithms provided by the `cryptography` package in Dart:

- **Symmetric Cipher**: AES-256 in Galois/Counter Mode (**AES-256-GCM**)
  - Key size: 256 bits (32 bytes)
  - Nonce size: 96 bits (12 bytes), cryptographically random and unique for every single encrypted object
  - Authentication tag (MAC): 128 bits (16 bytes) providing integrity and confidentiality
- **Key Derivation Function (KDF)**: **PBKDF2** with HMAC-SHA256
  - Iterations: 100,000 iterations
  - Key length: 256 bits
  - Salt: 128 bits (16 bytes) cryptographically random

---

## 2. Key Hierarchy & Lifecycle

```
[User 6-Digit PIN] + [Random PIN Salt (16 bytes)]
        │
        ▼ (PBKDF2, 100k iterations)
[PIN Key-Encryption Key (KEK)] ───► AES-256-GCM Wrap ───► [PIN-Wrapped Master Key]
                                            ▲               (Stored in FlutterSecureStorage)
                                            │
                               [256-bit Random Master Key]
                                            │
                                            ▼
[Recovery Code (Base32)] + [Random Recovery Salt (16 bytes)]
        │                                   │
        ▼ (PBKDF2, 100k iterations)         │
[Recovery KEK] ──────────────────► AES-256-GCM Wrap ───► [Recovery-Wrapped Master Key]
                                                            (Stored in Supabase vault_keys table)
```

1. **Master Vault Key Generation**:
   A random 256-bit key (`Uint8List` of 32 secure random bytes) is generated on the client device during initial setup.
2. **Local Key Wrapping**:
   The user chooses a 6-digit PIN. A 256-bit PIN KEK is derived using PBKDF2 (100k iterations, 16-byte salt). The master key is encrypted with this KEK using AES-256-GCM. The ciphertext, salt, and nonce are saved to the device's hardware-backed secure storage (`EncryptedSharedPreferences` on Android, `Keychain` on iOS).
3. **Cloud Recovery Key Wrapping**:
   A 24-character high-entropy recovery code (`PRIV-XXXX-XXXX-XXXX-XXXX`) is generated. A recovery KEK is derived from this code and a random salt using PBKDF2. The master key is wrapped with this recovery KEK. Only the ciphertext, recovery salt, and recovery nonce are uploaded to Supabase `vault_keys`. **The plain recovery code is never uploaded to the cloud or saved to disk.**
4. **Session Key Invalidation**:
   When the user unlocks the app with their 6-digit PIN, the Master Vault Key is unwrapped and held in volatile memory (RAM). When the app is minimized, screen-locked, or manually locked, this in-memory key is overwritten with zeros and garbage-collected.

---

## 3. Encrypted Object Format

Every photo and thumbnail uploaded to Supabase Storage follows this binary envelope:

```
┌───────────────┬──────────────────┬─────────────────┬─────────────────────────┐
│ Version (1B)  │  Nonce (12 Bytes)│  MAC (16 Bytes) │   AES-256-GCM Ciphertext│
│     0x01      │  Random Nonce    │  Integrity Tag  │   Encrypted Image Bytes │
└───────────────┴──────────────────┴─────────────────┴─────────────────────────┘
```

- Total header length: 29 bytes.
- Tamper-proof: Any alteration to the ciphertext or header results in immediate decryption failure.
- Zero metadata leakage: File names in Supabase Storage are random UUIDs (`{userId}/photos/{uuid}.enc`).

---

## 4. Operating System Protections

### Android
- **`FLAG_SECURE`**:
  `WindowManager.LayoutParams.FLAG_SECURE` is applied in `MainActivity.kt`. This blocks OS-level screenshots, screen mirroring, screen recording, and blacks out application snapshots in the Recent Apps switcher.
- **MediaStore Isolation**:
  Photos captured using Privora’s private camera are written to private application cache paths and never registered with `MediaStore`. They never appear in Google Photos or system gallery apps.
- **Temporary File Purging**:
  Any intermediate files used during upload, camera capture, or external sharing are deleted immediately upon completion and swept during application startup.

### iOS
- Screen masking on backgrounding and memory purge are enforced. (Hardware screenshot blocking on iOS is limited by the operating system; Privora blurs/masks contents upon app state transition).

---

## 5. Brute-Force & PIN Lockout

- Raw PINs are never stored; only a salted PBKDF2 verifier is stored.
- Failed PIN attempts are recorded. After 5 consecutive failed attempts, progressive lockouts are enforced (30 seconds, doubling up to multiple minutes).
- The keypad is disabled during the lockout duration.

---

## 6. Honest Security Disclosures & Limitations

1. **No Master Backdoor**:
   Because Privora does not hold the user's PIN or plaintext recovery code, **if a user forgets their PIN and loses their recovery code, their photos cannot be recovered by anyone, including Privora developers or Supabase administrators**.
2. **Device Compromise (Root/Jailbreak)**:
   If an adversary gains root access or code execution within the process memory while the vault is actively unlocked, they could read the Master Vault Key in RAM. Auto-locking upon minimize significantly narrows this window.
3. **Export / Share Exposure**:
   When a user explicitly chooses to export or share a photo via the OS share sheet, a decrypted file must be temporarily handed to the system share dialog. Privora displays a clear confirmation dialog explaining this temporary departure and deletes the file immediately.
