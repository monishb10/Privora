import 'package:intl/intl.dart';

/// Formatting utilities for sizes, dates, and sensitive labels.
class Formatters {
  Formatters._();

  /// Formats byte size into human readable string (KB, MB, GB)
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Formats a DateTime into a friendly date string
  static String formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0 && now.day == dateTime.day) {
      return 'Today at ${DateFormat('h:mm a').format(dateTime)}';
    }
    if (difference.inDays <= 1 && now.day - dateTime.day == 1) {
      return 'Yesterday at ${DateFormat('h:mm a').format(dateTime)}';
    }
    if (difference.inDays < 7) {
      return DateFormat('EEEE, h:mm a').format(dateTime);
    }
    return DateFormat('MMM d, yyyy').format(dateTime);
  }

  /// Formats remaining days for Recently Deleted photos
  static String formatRemainingDays(DateTime? deleteAfter) {
    if (deleteAfter == null) return '30 days left';
    final now = DateTime.now();
    final remainingDays = deleteAfter.difference(now).inDays;
    if (remainingDays <= 0) return 'Expires today';
    if (remainingDays == 1) return '1 day left';
    return '$remainingDays days left';
  }

  /// Masks email address for display (e.g., m***h@example.com)
  static String maskEmail(String email) {
    if (!email.contains('@')) return email;
    final parts = email.split('@');
    final username = parts[0];
    final domain = parts[1];

    if (username.length <= 2) {
      return '${username[0]}***@$domain';
    }
    return '${username[0]}***${username[username.length - 1]}@$domain';
  }
}
