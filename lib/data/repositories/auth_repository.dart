import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sp;
import '../../core/errors/app_exception.dart';
import '../../core/security/secure_key_service.dart';
import '../../core/security/session_lock_service.dart';
import '../services/supabase_auth_service.dart';
import '../services/supabase_database_service.dart';
import '../services/supabase_storage_service.dart';

/// Repository coordinating authentication, account deletion, and session cleanup.
class AuthRepository {
  final SupabaseAuthService authService;
  final SupabaseDatabaseService databaseService;
  final SupabaseStorageService storageService;
  final SecureKeyService secureKeyService;
  final SessionLockNotifier lockService;

  AuthRepository({
    required this.authService,
    required this.databaseService,
    required this.storageService,
    required this.secureKeyService,
    required this.lockService,
  });

  sp.User? get currentUser => authService.currentUser;
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

  Future<bool> signInWithGoogle() {
    return authService.signInWithGoogle();
  }

  Future<void> sendPasswordResetEmail(String email) {
    return authService.sendPasswordResetEmail(email);
  }

  /// Signs out, locks the session, and clears decrypted memory
  Future<void> signOut() async {
    lockService.resetToLocked();
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

      // 3. Clear all local secure credentials and keys
      await secureKeyService.clearAll();

      // 4. Lock session
      lockService.resetToLocked();

      // 5. Sign out of Supabase
      await authService.signOut();
    } catch (e) {
      debugPrint('Account deletion warning: $e');
      throw AuthException('Failed to completely delete account data: $e');
    }
  }
}
