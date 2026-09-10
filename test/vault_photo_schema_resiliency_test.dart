import 'package:flutter_test/flutter_test.dart';
import 'package:privora/data/models/vault_photo.dart';

void main() {
  group('VaultPhoto Schema Resiliency Tests', () {
    final now = DateTime(2026, 9, 10, 12, 0, 0);

    test('toBaseJson contains only 001_privora_schema.sql columns', () {
      final photo = VaultPhoto(
        id: '550e8400-e29b-41d4-a716-446655440000',
        userId: '11111111-2222-3333-4444-555555555555',
        categoryId: '66666666-7777-8888-9999-000000000000',
        storagePath:
            'privora/11111111-2222-3333-4444-555555555555/photos/photo1',
        thumbnailPath:
            'privora/11111111-2222-3333-4444-555555555555/thumbnails/photo1',
        displayName: 'test_photo.jpg',
        mimeType: 'image/jpeg',
        encryptedSize: 102400,
        width: 1920,
        height: 1080,
        createdAt: now,
        updatedAt: now,
        storageProvider: 'cloudinary',
        cloudinaryPublicId:
            'privora/11111111-2222-3333-4444-555555555555/photos/photo1',
        cloudinaryThumbnailPublicId:
            'privora/11111111-2222-3333-4444-555555555555/thumbnails/photo1',
        cloudinaryAssetId: 'cld_asset_123',
        cloudinaryVersion: '1725900000',
        encryptedBytes: 102400,
        originalFilename: 'test_photo.jpg',
      );

      final baseJson = photo.toBaseJson();

      // Verify guaranteed base columns exist
      expect(baseJson['id'], equals('550e8400-e29b-41d4-a716-446655440000'));
      expect(
        baseJson['user_id'],
        equals('11111111-2222-3333-4444-555555555555'),
      );
      expect(
        baseJson['category_id'],
        equals('66666666-7777-8888-9999-000000000000'),
      );
      expect(
        baseJson['storage_path'],
        equals('privora/11111111-2222-3333-4444-555555555555/photos/photo1'),
      );
      expect(
        baseJson['thumbnail_path'],
        equals(
          'privora/11111111-2222-3333-4444-555555555555/thumbnails/photo1',
        ),
      );
      expect(baseJson['display_name'], equals('test_photo.jpg'));
      expect(baseJson['mime_type'], equals('image/jpeg'));
      expect(baseJson['encrypted_size'], equals(102400));
      expect(baseJson['width'], equals(1920));
      expect(baseJson['height'], equals(1080));
      expect(baseJson['created_at'], equals(now.toIso8601String()));
      expect(baseJson['updated_at'], equals(now.toIso8601String()));

      // Strictly verify extended migration 003 columns are NOT present
      expect(baseJson.containsKey('storage_provider'), isFalse);
      expect(baseJson.containsKey('cloudinary_public_id'), isFalse);
      expect(baseJson.containsKey('cloudinary_thumbnail_public_id'), isFalse);
      expect(baseJson.containsKey('cloudinary_asset_id'), isFalse);
      expect(baseJson.containsKey('cloudinary_version'), isFalse);
      expect(baseJson.containsKey('encrypted_bytes'), isFalse);
      expect(baseJson.containsKey('original_filename'), isFalse);
    });

    test(
      'fromJson auto-detects Cloudinary when storage_provider is null in DB row',
      () {
        // Simulates row returned from a Supabase instance running 001_privora_schema.sql
        final dbRowFromBaseSchema = <String, dynamic>{
          'id': 'photo-uuid-1',
          'user_id': 'user-uuid-1',
          'category_id': 'cat-uuid-1',
          'storage_path': 'privora/user-uuid-1/photos/photo-uuid-1',
          'thumbnail_path': 'privora/user-uuid-1/thumbnails/photo-uuid-1',
          'display_name': 'vacation.jpg',
          'mime_type': 'image/jpeg',
          'encrypted_size': 54321,
          'width': 800,
          'height': 600,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'deleted_at': null,
          'delete_after': null,
          // Notice: storage_provider and cloudinary_* keys are absent
        };

        final parsed = VaultPhoto.fromJson(dbRowFromBaseSchema);

        expect(parsed.isCloudinary, isTrue);
        expect(parsed.storageProvider, equals('cloudinary'));
        expect(
          parsed.cloudinaryPublicId,
          equals('privora/user-uuid-1/photos/photo-uuid-1'),
        );
        expect(
          parsed.cloudinaryThumbnailPublicId,
          equals('privora/user-uuid-1/thumbnails/photo-uuid-1'),
        );
        expect(
          parsed.storagePath,
          equals('privora/user-uuid-1/photos/photo-uuid-1'),
        );
        expect(
          parsed.thumbnailPath,
          equals('privora/user-uuid-1/thumbnails/photo-uuid-1'),
        );
      },
    );

    test(
      'fromJson preserves Supabase storage when path does not start with privora/',
      () {
        final legacySupabaseRow = <String, dynamic>{
          'id': 'photo-uuid-2',
          'user_id': 'user-uuid-2',
          'category_id': 'cat-uuid-2',
          'storage_path': 'user-uuid-2/photos/photo-uuid-2.enc',
          'thumbnail_path': 'user-uuid-2/thumbnails/photo-uuid-2.enc',
          'display_name': 'legacy.png',
          'mime_type': 'image/png',
          'encrypted_size': 12345,
          'width': 400,
          'height': 400,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        };

        final parsed = VaultPhoto.fromJson(legacySupabaseRow);

        expect(parsed.isCloudinary, isFalse);
        expect(parsed.storageProvider, equals('supabase'));
        expect(
          parsed.storagePath,
          equals('user-uuid-2/photos/photo-uuid-2.enc'),
        );
        expect(
          parsed.thumbnailPath,
          equals('user-uuid-2/thumbnails/photo-uuid-2.enc'),
        );
      },
    );

    test('toExtendedJson contains all migration 003 fields', () {
      final photo = VaultPhoto(
        id: 'photo-uuid-3',
        userId: 'user-uuid-3',
        categoryId: 'cat-uuid-3',
        storagePath: 'privora/user-uuid-3/photos/photo-uuid-3',
        thumbnailPath: 'privora/user-uuid-3/thumbnails/photo-uuid-3',
        displayName: 'extended.jpg',
        mimeType: 'image/jpeg',
        encryptedSize: 99999,
        createdAt: now,
        updatedAt: now,
        storageProvider: 'cloudinary',
        cloudinaryPublicId: 'privora/user-uuid-3/photos/photo-uuid-3',
        cloudinaryThumbnailPublicId:
            'privora/user-uuid-3/thumbnails/photo-uuid-3',
        cloudinaryAssetId: 'cld_12345',
        cloudinaryVersion: '2',
        encryptedBytes: 99999,
        originalFilename: 'extended.jpg',
      );

      final extJson = photo.toExtendedJson();

      expect(extJson['storage_provider'], equals('cloudinary'));
      expect(
        extJson['cloudinary_public_id'],
        equals('privora/user-uuid-3/photos/photo-uuid-3'),
      );
      expect(
        extJson['cloudinary_thumbnail_public_id'],
        equals('privora/user-uuid-3/thumbnails/photo-uuid-3'),
      );
      expect(extJson['cloudinary_asset_id'], equals('cld_12345'));
      expect(extJson['cloudinary_version'], equals('2'));
      expect(extJson['encrypted_bytes'], equals(99999));
      expect(extJson['original_filename'], equals('extended.jpg'));
    });
  });
}
