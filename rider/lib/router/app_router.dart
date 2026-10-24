import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/app_providers.dart';
import '../screens/account/account_settings_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/reset_password_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/auth/verification_status_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/order/order_detail_screen.dart';
import '../screens/support/support_screen.dart';
import '../screens/welcome/welcome_screen.dart';

/// Routes reachable without a stored token — everything else is
/// considered behind the auth gate (see [buildRouter]'s redirect).
const _publicPaths = {'/', '/login', '/signup', '/forgot-password', '/reset-password', '/verification-status'};

/// Builds the app's [GoRouter] configuration.
///
/// Grows as each screen is built (see the app's own README/TODO for
/// progress). [isLoggedInProvider] is read fresh (not watched) on every
/// navigation attempt — the app doesn't need the router to react to it
/// changing mid-session, since every place that flips it (login,
/// reset-password with a token, logout) already calls `context.go(...)`
/// itself right after.
GoRouter buildRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = ref.read(isLoggedInProvider);
      final isPublicRoute = _publicPaths.contains(state.matchedLocation);

      if (!isLoggedIn && !isPublicRoute) return '/';
      if (isLoggedIn && (state.matchedLocation == '/' || state.matchedLocation == '/login' || state.matchedLocation == '/signup')) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
      GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ResetPasswordScreen(
            riderId: extra?['riderId'] as int? ?? 0,
            identifier: extra?['identifier'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/verification-status',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return VerificationStatusScreen(
            identifier: extra?['identifier'] as String? ?? '',
            password: extra?['password'] as String? ?? '',
          );
        },
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/account/settings', builder: (context, state) => const AccountSettingsScreen()),
      GoRoute(path: '/support', builder: (context, state) => const SupportScreen()),
      GoRoute(
        path: '/orders/:orderId',
        builder: (context, state) => OrderDetailScreen(orderId: int.parse(state.pathParameters['orderId']!)),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('common.page_not_found'.tr())),
    ),
  );
}
