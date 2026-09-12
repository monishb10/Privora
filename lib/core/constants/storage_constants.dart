/// Constants for Supabase Storage and Secure Storage keys.
class StorageConstants {
  StorageConstants._();

  // Supabase Storage Bucket
  static const String privatePhotosBucket = 'private-photos';

  // Secure Storage Keys
  static const String securePinSalt = 'privora_pin_salt';
  static const String securePinVerifier = 'privora_pin_verifier';
  static const String securePinWrappedMasterKey =
      'privora_pin_wrapped_master_key';
  static const String securePinKekNonce = 'privora_pin_kek_nonce';
  static const String secureFailedPinAttempts = 'privora_failed_pin_attempts';
  static const String secureLockoutUntil = 'privora_lockout_until';
  static const String secureHasCompletedSetup = 'privora_has_completed_setup';
  static const String secureOtpBackupConfigured =
      'privora_otp_backup_configured';
  // Read only while upgrading older installations, then permanently deleted.
  static const String secureRecoveryCode = 'privora_recovery_code';

  // Supabase Database Table Names
  static const String tableProfiles = 'profiles';
  static const String tableVaultKeys = 'vault_keys';
  static const String tableCategories = 'categories';
  static const String tablePhotos = 'photos';

  /// Generates the storage path for an encrypted full photo
  static String photoPath(String userId, String photoId) {
    return '$userId/photos/$photoId.enc';
  }

  /// Generates the storage path for an encrypted thumbnail
  static String thumbnailPath(String userId, String photoId) {
    return '$userId/thumbnails/$photoId.enc';
  }
}
