import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/data/models/vault_category.dart';
import 'package:privora/data/models/vault_photo.dart';

void main() {
  group('VaultCategory Model Tests', () {
    test('serializes and deserializes correctly', () {
      final now = DateTime.now();
      final category = VaultCategory(
        id: 'cat-123',
        userId: 'user-456',
        name: 'Private Travel',
        colorValue: const Color(0xFFE6B566).toARGB32(),
        coverPhotoId: 'photo-789',
        createdAt: now,
        updatedAt: now,
        photoCount: 5,
        latestPhotoDate: now,
      );

      final json = category.toJson();
      expect(json['id'], 'cat-123');
      expect(json['name'], 'Private Travel');
      expect(json['color_value'], const Color(0xFFE6B566).toARGB32());

      final fromJson = VaultCategory.fromJson(
        json,
        photoCount: 5,
        latestPhotoDate: now,
      );
      expect(fromJson.id, 'cat-123');
      expect(fromJson.name, 'Private Travel');
      expect(fromJson.color.toARGB32(), const Color(0xFFE6B566).toARGB32());
      expect(fromJson.photoCount, 5);
      expect(fromJson.coverPhotoId, 'photo-789');
    });

    test('copyWith updates specified attributes', () {
      final now = DateTime.now();
      final category = VaultCategory(
        id: 'cat-1',
        userId: 'user-1',
        name: 'Old Name',
        colorValue: 0xFF112233,
        createdAt: now,
        updatedAt: now,
      );

      final updated = category.copyWith(name: 'New Name', photoCount: 10);
      expect(updated.name, 'New Name');
      expect(updated.photoCount, 10);
      expect(updated.id, 'cat-1');
    });
  });

  group('VaultPhoto & Recently Deleted Calculation Tests', () {
    test('calculates remaining days accurately for 30-day trash retention', () {
      final now = DateTime.now();
      final deleteAfter25Days = now.add(const Duration(days: 25));
      final photo1 = VaultPhoto(
        id: 'photo-1',
        userId: 'user-1',
        categoryId: 'cat-1',
        storagePath: 'user-1/photos/p1.enc',
        thumbnailPath: 'user-1/thumbnails/p1.enc',
        displayName: 'Vacation.jpg',
        mimeType: 'image/jpeg',
        encryptedSize: 1024 * 1024,
        createdAt: now,
        updatedAt: now,
        deletedAt: now,
        deleteAfter: deleteAfter25Days,
      );

      expect(photo1.isDeleted, isTrue);
      expect(photo1.remainingDays, inInclusiveRange(24, 25));

      // Expired photo
      final expiredDeleteAfter = now.subtract(const Duration(days: 1));
      final expiredPhoto = photo1.copyWith(deleteAfter: expiredDeleteAfter);
      expect(expiredPhoto.remainingDays, 0);
    });
  });
}
