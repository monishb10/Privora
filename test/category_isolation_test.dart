import 'package:flutter_test/flutter_test.dart';
import 'package:privora/data/models/vault_category.dart';
import 'package:privora/data/repositories/category_repository.dart';
import 'package:privora/data/services/supabase_database_service.dart';

class FakeDatabaseServiceForIsolation extends Fake
    implements SupabaseDatabaseService {
  final Map<String, List<VaultCategory>> userCategories = {};

  @override
  Future<List<VaultCategory>> getCategories(String userId) async {
    return List.from(userCategories[userId] ?? []);
  }

  @override
  Future<VaultCategory> createCategory(VaultCategory category) async {
    final list = userCategories[category.userId] ?? [];
    list.add(category);
    userCategories[category.userId] = list;
    return category;
  }
}

void main() {
  test(
    'CategoryRepository strictly isolates category caches across different accounts',
    () async {
      final fakeDb = FakeDatabaseServiceForIsolation();
      final categoryRepo = CategoryRepository(databaseService: fakeDb);

      const userA = 'user-account-A';
      const userB = 'user-account-B';

      // 1. User A creates a category
      await categoryRepo.createCategory(
        userId: userA,
        name: 'Account A Category',
        colorValue: 0xFF2196F3,
      );

      // Fetch User A's categories
      final catsA = await categoryRepo.getCategories(userA);
      expect(catsA.length, equals(1));
      expect(catsA.first.name, equals('Account A Category'));

      // 2. User B logs in and fetches categories
      // Must return empty list for fresh User B, NEVER User A's categories!
      final catsB = await categoryRepo.getCategories(userB);
      expect(catsB, isEmpty);

      // 3. User B creates their own category
      await categoryRepo.createCategory(
        userId: userB,
        name: 'Account B Category',
        colorValue: 0xFF4CAF50,
      );

      // Fetch User B's categories again
      final catsBUpdated = await categoryRepo.getCategories(userB);
      expect(catsBUpdated.length, equals(1));
      expect(catsBUpdated.first.name, equals('Account B Category'));

      // 4. Switch back to User A
      final catsASwitched = await categoryRepo.getCategories(userA);
      expect(catsASwitched.length, equals(1));
      expect(catsASwitched.first.name, equals('Account A Category'));

      // 5. Test clearCache
      categoryRepo.clearCache();
      expect(categoryRepo.cachedCategories, isNull);

      final catsAfterClear = await categoryRepo.getCategories(userA);
      expect(catsAfterClear.length, equals(1));
      expect(catsAfterClear.first.name, equals('Account A Category'));
    },
  );
}
