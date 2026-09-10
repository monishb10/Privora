import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sp;
import '../../core/errors/app_exception.dart';
import '../../core/security/pin_service.dart';
import '../../core/security/secure_key_service.dart';
import '../../core/security/session_lock_service.dart';
import '../../core/security/temporary_file_cleaner.dart';
import '../services/supabase_auth_service.dart';
import '../services/supabase_database_service.dart';
import '../services/supabase_storage_service.dart';
import 'category_repository.dart';

/// Repository coordinating authentication, account deletion, and session cleanup.
class AuthRepository {
  final SupabaseAuthService authService;
  final SupabaseDatabaseService databaseService;
  final SupabaseStorageService storageService;
  final SecureKeyService secureKeyService;
  final SessionLockNotifier lockService;
  final PinService pinService;
  final TemporaryFileCleaner temporaryFileCleaner;
  final CategoryRepository? categoryRepository;

  AuthRepository({
    required this.authService,
    required this.databaseService,
    required this.storageService,
    required this.secureKeyService,
    required this.lockService,
    required this.pinService,
    required this.temporaryFileCleaner,
    this.categoryRepository,
  });

  sp.User? get currentUser => authService.currentUser;
  sp.Session? get currentSession => authService.currentSession;
  bool get isAuthenticated => authService.isAuthenticated;
  Stream<sp.AuthState> get authStateChanges => authService.authStateChanges;

  Future<sp.AuthResponse> signUp({
    required String email,
    required String password,
    String? displayName,
  }) {
    return authService.signUp(
      email: email,
      password: password,
      displayName: displayName,
    );
  }

  Future<sp.AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return authService.signIn(email: email, password: password);
  }

  Future<sp.AuthResponse?> signInWithGoogle() {
    return authService.signInWithGoogle();
  }

  Future<void> sendPasswordResetEmail(String email) {
    return authService.sendPasswordResetEmail(email);
  }

  /// Full clean sign out protocol:
  /// 1. Immediately locks the vault.
  /// 2. Clears the decrypted vault key from memory.
  /// 3. Deletes temporary decrypted image files and temporary thumbnails.
  /// 4. Signs out of Google and Supabase.
  /// 5. Leaves encrypted per-user keys intact for returning user.
  Future<void> signOut() async {
    // 1. Lock vault
    lockService.resetToLocked();

    // 2. Clear master key from memory
    pinService.lockSession();

    // 3. Delete temporary decrypted files and thumbnails
    try {
      await temporaryFileCleaner.cleanTemporaryFiles();
    } catch (e) {
      debugPrint('Error cleaning temporary files on signOut: $e');
    }

    // 4. Clear cached categories to prevent cross-account leakage
    categoryRepository?.clearCache();

    // 5. Sign out of Google and Supabase
    await authService.signOut();
  }

  /// Permanently deletes user account, cloud storage objects, database rows, and local secrets
  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException('No active user session found.');
    }

    final userId = user.id;

    try {
      // 1. Delete all encrypted photos and thumbnails in storage
      await storageService.deleteAllUserStorage(userId);

      // 2. Delete database rows (photos, categories, vault keys, profile)
      await databaseService.deleteUserDatabaseRecords(userId);

      // 3. Clear all local secure credentials and keys for this user
      await secureKeyService.clearUserKeys(userId);

      // 4. Clean temporary files
      await temporaryFileCleaner.cleanTemporaryFiles();

      // 5. Clear memory key and lock session
      pinService.lockSession();
      lockService.resetToLocked();

      // 6. Clear category cache
      categoryRepository?.clearCache();

      // 7. Sign out of Google and Supabase
      await authService.signOut();
    } catch (e) {
      debugPrint('Account deletion warning: $e');
      throw AuthException('Failed to completely delete account data: $e');
    }
  }
}
