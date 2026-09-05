/// Core application constants.
class AppConstants {
  AppConstants._();

  static const String appName = 'Privora';
  static const String appTagline = 'Your moments. Only yours.';

  // Security & PIN constraints
  static const int pinLength = 6;
  static const int maxPinAttemptsBeforeLockout = 5;
  static const int baseLockoutSeconds = 30;

  // Key derivation parameters
  static const int pbkdf2Iterations = 100000;
  static const int keyLengthBits = 256;
  static const int saltLengthBytes = 16;
  static const int gcmNonceLengthBytes = 12;

  // Photo constraints
  static const int maxPhotoSizeBytes = 50 * 1024 * 1024; // 50MB
  static const int thumbnailSizePixels = 400;
  static const int thumbnailQuality = 75;

  // Trash retention
  static const int trashRetentionDays = 30;

  // Allowed image MIME types
  static const List<String> allowedMimeTypes = [
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
    'image/heic',
  ];
}
