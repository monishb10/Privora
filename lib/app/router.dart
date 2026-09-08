import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/widgets/privora_floating_nav_bar.dart';
import '../data/models/vault_category.dart';
import '../features/account/account_screen.dart';
import '../features/account/security_settings_screen.dart';
import '../features/account/storage_usage_screen.dart';
import '../features/auth/email_verification_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/camera/private_camera_screen.dart';
import '../features/categories/categories_screen.dart';
import '../features/categories/category_detail_screen.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/pin/change_pin_screen.dart';
import '../features/pin/confirm_pin_screen.dart';
import '../features/pin/create_pin_screen.dart';
import '../features/pin/recover_vault_screen.dart';
import '../features/pin/unlock_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/trash/recently_deleted_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/email-verification',
        builder: (context, state) {
          final email = state.extra as String? ?? '';
          return EmailVerificationScreen(email: email);
        },
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
    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: PrivoraFloatingNavBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) {
          if (index == 1) {
            // Central camera action: opens camera directly
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const PrivateCameraScreen(),
              ),
            );
          } else {
            navigationShell.goBranch(index);
          }
        },
      ),
    );
  }
}
