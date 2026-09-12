# Privora Security Model

## Media encryption

- Every full photo and thumbnail is encrypted on the phone with AES-256-GCM
  before upload.
- Each encrypted object uses a random 12-byte nonce and 16-byte authentication
  tag.
- Cloudinary receives authenticated raw ciphertext, not a viewable photograph.
- Decrypted display bytes and the active master key are kept in memory and
  cleared when the vault locks.

## PIN protection

- The app accepts exactly six numeric digits.
- PBKDF2-HMAC-SHA256 with a random salt and 100,000 iterations derives the
  local key-encryption key and verifier.
- The PIN itself is never stored.
- Each Supabase user ID has isolated secure-storage keys and an isolated server
  PIN envelope.
- Progressive delays are applied after five incorrect attempts.

## Gmail OTP PIN reset

Privora does not ask the user to retain a separate secret. Instead:

1. During vault setup, the authenticated `vault-key-otp` Edge Function stores
   a server-encrypted copy of the random master key.
2. Forgot PIN always targets the email address from the current Google/Supabase
   user. The user cannot type a different address.
3. Supabase sends and verifies a six-digit email OTP.
4. The Edge Function independently verifies the JWT and requires a recent
   `amr=otp` claim for the same user and email.
5. The original master key is released over authenticated TLS, re-wrapped under
   the new PIN, and removed from temporary memory.

`VAULT_OTP_MASTER_SECRET` is a random 32-byte base64 secret stored only in
Supabase Edge Function secrets. Never put it, the Cloudinary API secret, or the
Supabase service-role key in Flutter.

## Honest trust boundary

Photo files remain encrypted before Cloudinary receives them. Gmail-based PIN
reset requires a server-held encryption secret, so the reset architecture is
not zero-knowledge against a fully compromised Supabase backend. This is the
tradeoff that makes a forgotten PIN reset possible without asking the user to
save another secret.

Rotating or deleting `VAULT_OTP_MASTER_SECRET` without migrating existing
envelopes will make email PIN reset unavailable. Back it up in a secure owner
password manager and restrict Supabase project access.

## Device protections

- Android `FLAG_SECURE` blocks screenshots, screen recording, and recent-app
  previews.
- Private-camera captures do not enter Android MediaStore.
- Temporary import/camera files are cleaned after use and again at startup.
- A rooted/jailbroken device or live process compromise can expose data while
  the vault is unlocked; automatic locking narrows that window.
