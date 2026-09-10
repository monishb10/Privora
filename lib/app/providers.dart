import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';
import '../core/security/pin_service.dart';
import '../core/security/secure_key_service.dart';
import '../core/security/session_lock_service.dart';
import '../core/security/temporary_file_cleaner.dart';
import '../core/security/vault_crypto_service.dart';
import '../data/models/vault_category.dart';
import '../data/models/vault_photo.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/photo_repository.dart';
import '../data/repositories/vault_repository.dart';
import '../data/services/cloudinary_media_service.dart';
import '../data/services/gallery_import_service.dart';
import '../data/services/photo_download_service.dart';
import '../data/services/photo_upload_service.dart';
import '../data/services/supabase_auth_service.dart';
import '../data/services/supabase_database_service.dart';
import '../data/services/supabase_storage_service.dart';

// --- CORE SECURITY PROVIDERS ---

final secureKeyServiceProvider = Provider<SecureKeyService>((ref) {
  return SecureKeyService();
});

final vaultCryptoServiceProvider = Provider<VaultCryptoService>((ref) {
  return VaultCryptoService();
});

final temporaryFileCleanerProvider = Provider<TemporaryFileCleaner>((ref) {
  return TemporaryFileCleaner();
});

final pinServiceProvider = Provider<PinService>((ref) {
  return PinService(
    secureKeyService: ref.watch(secureKeyServiceProvider),
    cryptoService: ref.watch(vaultCryptoServiceProvider),
  );
});

final sessionLockServiceProvider = NotifierProvider<SessionLockNotifier, bool>(
  SessionLockNotifier.new,
);

// --- SUPABASE SERVICES ---

final supabaseAuthServiceProvider = Provider<SupabaseAuthService>((ref) {
  return SupabaseAuthService();
});

final supabaseDatabaseServiceProvider = Provider<SupabaseDatabaseService>((
  ref,
) {
  return SupabaseDatabaseService();
});

final supabaseStorageServiceProvider = Provider<SupabaseStorageService>((ref) {
  return SupabaseStorageService();
});

final cloudinaryMediaServiceProvider = Provider<CloudinaryMediaService>((ref) {
  return CloudinaryMediaService();
});

final photoDownloadServiceProvider = Provider<PhotoDownloadService>((ref) {
  return PhotoDownloadService(
    storageService: ref.watch(supabaseStorageServiceProvider),
    cloudinaryService: ref.watch(cloudinaryMediaServiceProvider),
    cryptoService: ref.watch(vaultCryptoServiceProvider),
  );
});

final photoUploadServiceProvider = Provider<PhotoUploadService>((ref) {
  return PhotoUploadService(
    cryptoService: ref.watch(vaultCryptoServiceProvider),
    storageService: ref.watch(supabaseStorageServiceProvider),
    cloudinaryService: ref.watch(cloudinaryMediaServiceProvider),
    databaseService: ref.watch(supabaseDatabaseServiceProvider),
    cleaner: ref.watch(temporaryFileCleanerProvider),
  );
});

final galleryImportServiceProvider = Provider<GalleryImportService>((ref) {
  return GalleryImportService();
});

// --- REPOSITORIES ---

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    authService: ref.watch(supabaseAuthServiceProvider),
    databaseService: ref.watch(supabaseDatabaseServiceProvider),
    storageService: ref.watch(supabaseStorageServiceProvider),
    secureKeyService: ref.watch(secureKeyServiceProvider),
    lockService: ref.watch(sessionLockServiceProvider.notifier),
    pinService: ref.watch(pinServiceProvider),
    temporaryFileCleaner: ref.watch(temporaryFileCleanerProvider),
    categoryRepository: ref.watch(categoryRepositoryProvider),
  );
});

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository(
    databaseService: ref.watch(supabaseDatabaseServiceProvider),
  );
});

final photoRepositoryProvider = Provider<PhotoRepository>((ref) {
  return PhotoRepository(
    databaseService: ref.watch(supabaseDatabaseServiceProvider),
    storageService: ref.watch(supabaseStorageServiceProvider),
    uploadService: ref.watch(photoUploadServiceProvider),
    downloadService: ref.watch(photoDownloadServiceProvider),
    cloudinaryService: ref.watch(cloudinaryMediaServiceProvider),
  );
});

final vaultRepositoryProvider = Provider<VaultRepository>((ref) {
  return VaultRepository(
    pinService: ref.watch(pinServiceProvider),
    cryptoService: ref.watch(vaultCryptoServiceProvider),
    secureKeyService: ref.watch(secureKeyServiceProvider),
    databaseService: ref.watch(supabaseDatabaseServiceProvider),
  );
});

// --- AUTH & USER STATE ---

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).currentUser;
});

// --- DATA PROVIDERS ---

final categoriesProvider = FutureProvider.autoDispose<List<VaultCategory>>((
  ref,
) async {
  final user =
      ref.watch(currentUserProvider) ??
      (SupabaseConfig.isInitialized
          ? Supabase.instance.client.auth.currentUser
          : null);
  if (user == null || user.id.isEmpty) return [];
  return ref
      .watch(categoryRepositoryProvider)
      .getCategories(user.id)
      .timeout(const Duration(seconds: 10));
});

final recentlyDeletedPhotosProvider =
    FutureProvider.autoDispose<List<VaultPhoto>>((ref) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return [];
      return ref.watch(photoRepositoryProvider).getRecentlyDeleted(user.id);
    });

final storageUsageProvider = FutureProvider.autoDispose<int>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return 0;
  return ref.watch(photoRepositoryProvider).getTotalStorageUsage(user.id);
});
