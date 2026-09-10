import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/widgets/privora_floating_nav_bar.dart';
import '../data/models/vault_category.dart';
import '../features/account/account_screen.dart';
import '../features/account/recovery_code_screen.dart';
import '../features/account/security_settings_screen.dart';
import '../features/account/storage_usage_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/camera/private_camera_screen.dart';
import '../features/categories/categories_screen.dart';
import '../features/categories/category_detail_screen.dart';
import '../features/pin/change_pin_screen.dart';
import '../features/pin/confirm_pin_screen.dart';
import '../features/pin/create_pin_screen.dart';
import '../features/pin/recover_vault_screen.dart';
import '../features/pin/unlock_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/trash/recently_deleted_screen.dart';
import 'providers.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

class _AuthRefreshNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _subscription;

  _AuthRefreshNotifier(Stream<AuthState> stream) {
    _subscription = stream.listen((_) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final authNotifier = _AuthRefreshNotifier(authRepo.authStateChanges);
  ref.onDispose(authNotifier.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final isAuth = authRepo.isAuthenticated;
      final loc = state.matchedLocation;

      // Allow splash and login when not authenticated
      final isPublic = loc == '/login' || loc == '/splash';

      if (!isAuth && !isPublic) {
        return '/login';
      }

      // Automatically route legacy onboarding/auth routes to single Google Login
      if (loc == '/welcome' ||
          loc == '/register' ||
          loc == '/forgot-password' ||
          loc == '/email-verification') {
        return '/login';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/welcome', redirect: (context, state) => '/login'),
      GoRoute(path: '/register', redirect: (context, state) => '/login'),
      GoRoute(path: '/forgot-password', redirect: (context, state) => '/login'),
      GoRoute(
        path: '/email-verification',
        redirect: (context, state) => '/login',
      ),
      GoRoute(
        path: '/create-pin',
        builder: (context, state) => const CreatePinScreen(),
      ),
      GoRoute(
        path: '/confirm-pin',
        builder: (context, state) {
          final pin = state.extra as String? ?? '';
          return ConfirmPinScreen(originalPin: pin);
        },
      ),
      GoRoute(
        path: '/unlock',
        builder: (context, state) => const UnlockScreen(),
      ),
      GoRoute(
        path: '/change-pin',
        builder: (context, state) => const ChangePinScreen(),
      ),
      GoRoute(
        path: '/recover-vault',
        builder: (context, state) => const RecoverVaultScreen(),
      ),
      GoRoute(
        path: '/category/:id',
        builder: (context, state) {
          final category = state.extra as VaultCategory;
          return CategoryDetailScreen(category: category);
        },
      ),
      GoRoute(
        path: '/storage-usage',
        builder: (context, state) => const StorageUsageScreen(),
      ),
      GoRoute(
        path: '/security-settings',
        builder: (context, state) => const SecuritySettingsScreen(),
      ),
      GoRoute(
        path: '/recovery-code',
        builder: (context, state) => const RecoveryCodeScreen(),
      ),

      // Bottom Navigation Shell for main screens
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return _MainScaffold(navigationShell: navigationShell);
        },
        branches: [
          // Branch 0: Categories
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/categories',
                builder: (context, state) => const CategoriesScreen(),
              ),
            ],
          ),
          // Branch 1: Quick Camera Action
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/camera-tab',
                builder: (context, state) => const PrivateCameraScreen(),
              ),
            ],
          ),
          // Branch 2: Recently Deleted
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/trash',
                builder: (context, state) => const RecentlyDeletedScreen(),
              ),
            ],
          ),
          // Branch 3: Account & Settings
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/account',
                builder: (context, state) => const AccountScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _MainScaffold({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    final isCategoriesTab = navigationShell.currentIndex == 0;

    return PopScope(
      canPop: isCategoriesTab,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // When on a non-Categories root tab (Camera-tab, Trash, Account),
        // system Back switches the active tab back to Categories.
        if (navigationShell.currentIndex != 0) {
          navigationShell.goBranch(0);
        }
      },
      child: Scaffold(
        extendBody: true,
        body: navigationShell,
        bottomNavigationBar: PrivoraFloatingNavBar(
          currentIndex: navigationShell.currentIndex,
          onTap: (index) {
            if (index == 1) {
              // Central camera action: opens camera directly
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (context) => const PrivateCameraScreen(),
                ),
              );
            } else {
              navigationShell.goBranch(index);
            }
          },
        ),
      ),
    );
  }
}
