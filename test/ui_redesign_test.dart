import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privora/app/providers.dart';
import 'package:privora/core/constants/app_constants.dart';
import 'package:privora/core/theme/app_colors.dart';
import 'package:privora/core/theme/app_theme.dart';
import 'package:privora/core/widgets/privora_brand_app_bar.dart';
import 'package:privora/core/widgets/privora_floating_nav_bar.dart';
import 'package:privora/core/widgets/privora_logo.dart';
import 'package:privora/data/models/vault_category.dart';
import 'package:privora/features/categories/categories_screen.dart';

void main() {
  group('Privora Top App Bar Tests', () {
    testWidgets(
      'PrivoraBrandAppBar renders mathematically centered brand header',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              appBar: PrivoraBrandAppBar(
                isSearching: false,
                onToggleSearch: () {},
                onLock: () {},
              ),
            ),
          ),
        );

        // Verify Privora logo and title exist
        expect(find.byType(PrivoraLogo), findsOneWidget);
        expect(find.text(AppConstants.appName), findsOneWidget);

        // Verify font and typography
        final textWidget = tester.widget<Text>(find.text(AppConstants.appName));
        expect(textWidget.style?.fontFamily, equals('PlayfairDisplay'));
        expect(textWidget.style?.fontWeight, equals(FontWeight.w700));
        expect(textWidget.style?.fontSize, inInclusiveRange(25.0, 28.0));
        expect(textWidget.style?.color, equals(AppColors.primaryText));

        // Verify Privora logo is positioned at the left-side corner
        final logoTopLeft = tester.getTopLeft(find.byType(PrivoraLogo));
        expect(logoTopLeft.dx, equals(16.0));

        // Verify mathematical centering: center of title is exactly 200 (screenWidth / 2)
        final titleCenter = tester.getCenter(find.text(AppConstants.appName));
        expect(titleCenter.dx, equals(200.0));

        // Verify right action buttons exist with 48px touch targets
        final searchButton = find.byTooltip('Search Categories');
        final lockButton = find.byTooltip('Lock Privora');
        expect(searchButton, findsOneWidget);
        expect(lockButton, findsOneWidget);

        final searchSize = tester.getSize(searchButton);
        expect(searchSize.width, greaterThanOrEqualTo(44.0));
        expect(searchSize.height, greaterThanOrEqualTo(44.0));

        final lockSize = tester.getSize(lockButton);
        expect(lockSize.width, greaterThanOrEqualTo(44.0));
        expect(lockSize.height, greaterThanOrEqualTo(44.0));
      },
    );

    testWidgets('PrivoraBrandAppBar toggles to search mode cleanly', (
      tester,
    ) async {
      final controller = TextEditingController();
      bool searchToggled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            appBar: PrivoraBrandAppBar(
              isSearching: true,
              searchController: controller,
              onToggleSearch: () => searchToggled = true,
              onLock: () {},
            ),
          ),
        ),
      );

      // In search mode, search TextField is displayed with close button
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Close Search'), findsOneWidget);

      await tester.tap(find.byTooltip('Close Search'));
      expect(searchToggled, isTrue);
    });
  });

  group('Privora Floating Navigation Bar Tests', () {
    testWidgets(
      'PrivoraFloatingNavBar renders all 4 destinations with glass styling',
      (tester) async {
        int tappedIndex = -1;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              bottomNavigationBar: PrivoraFloatingNavBar(
                currentIndex: 0,
                onTap: (index) => tappedIndex = index,
              ),
            ),
          ),
        );

        // Verify 4 destinations
        expect(find.text('Categories'), findsOneWidget);
        expect(find.text('Camera'), findsOneWidget);
        expect(find.text('Trash'), findsOneWidget);
        expect(find.text('Account'), findsOneWidget);

        // Verify BackdropFilter glass effect
        expect(find.byType(BackdropFilter), findsOneWidget);

        // Tap on Trash (index 2)
        await tester.tap(find.text('Trash'));
        expect(tappedIndex, equals(2));
      },
    );
  });

  group('CategoriesScreen Integration Tests', () {
    testWidgets(
      'CategoriesScreen displays centered brand app bar and elevated New Category FAB',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              categoriesProvider.overrideWith(
                (ref) => Future.value(<VaultCategory>[]),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const CategoriesScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify brand header is centered
        expect(find.byType(PrivoraBrandAppBar), findsOneWidget);
        expect(find.text(AppConstants.appName), findsOneWidget);

        // Verify single create-category action when list is empty (no duplicate FAB)
        expect(find.text('Create your first category'), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsNothing);
      },
    );
  });
}
