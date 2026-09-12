/// Base application exception hierarchy for Privora.
sealed class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic details;

  const AppException(this.message, {this.code, this.details});

  @override
  String toString() => message;
}

class NetworkException extends AppException {
  const NetworkException([
    super.message =
        'No internet connection. Please check your network and try again.',
  ]);
}

class AuthException extends AppException {
  const AuthException(super.message, {super.code});
}

class SessionExpiredException extends AppException {
  const SessionExpiredException([
    super.message = 'Your session has expired. Please log in again.',
  ]);
}

class PinException extends AppException {
  const PinException(super.message, {super.code});
}

class PinLockoutException extends AppException {
  final int remainingSeconds;
  const PinLockoutException(this.remainingSeconds, [String? message])
    : super(
        message ??
            'Too many incorrect attempts. Please try again in $remainingSeconds seconds.',
      );
}

class CryptoException extends AppException {
  const CryptoException(super.message, {super.code});
}

class StorageException extends AppException {
  final int? statusCode;

  const StorageException(
    super.message, {
    super.code,
    super.details,
    this.statusCode,
  });
}

class PermissionException extends AppException {
  const PermissionException(super.message, {super.code});
}

class CameraUnavailableException extends AppException {
  const CameraUnavailableException([
    super.message = 'Camera is not available on this device.',
  ]);
}

class UserCancelledException extends AppException {
  const UserCancelledException([super.message = 'Action was cancelled.']);
}

class QuotaExceededException extends AppException {
  const QuotaExceededException([
    super.message = 'Cloud storage limit exceeded.',
  ]);
}

class PinResetException extends AppException {
  const PinResetException(super.message, {super.code});
}

class ValidationException extends AppException {
  const ValidationException(super.message, {super.code});
}
