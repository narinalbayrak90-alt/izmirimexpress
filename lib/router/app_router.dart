import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/app_providers.dart';
import '../screens/account/account_screen.dart';
import '../screens/account/help_support_screen.dart';
import '../screens/account/invite_earn_screen.dart';
import '../screens/account/personal_information_screen.dart';
import '../screens/account/saved_addresses_screen.dart';
import '../screens/account/wallet_screen.dart';
import '../services/auth_service.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/otp_verification_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/booking/booking_category_screen.dart';
import '../screens/booking/dropoff_location_screen.dart';
import '../screens/booking/payment_method_screen.dart';
import '../screens/booking/pickup_location_screen.dart';
import '../screens/booking/summary_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/notifications/notification_screen.dart';
import '../screens/orders/my_orders_screen.dart';
import '../screens/orders/order_detail_screen.dart';
import '../screens/tracking/order_tracking_screen.dart';
import '../screens/welcome/welcome_screen.dart';

/// Builds the app's [GoRouter] configuration.
///
/// The welcome screen is a one-time, install-only screen: [redirect] sends
/// returning users straight to `/home` based on the persisted
/// [onboardingStorageProvider] flag, so it's never shown again once
/// "Get Started" has been tapped. Module 2 adds further routes (splash,
/// language select, auth) and folds them into this same redirect.
GoRouter buildRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final hasSeenWelcome = ref.read(onboardingStorageProvider).hasSeenWelcome;
      if (state.matchedLocation == '/' && hasSeenWelcome) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const WelcomeScreen()),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/booking', builder: (context, state) => const BookingCategoryScreen()),
      GoRoute(path: '/booking/pickup', builder: (context, state) => const PickupLocationScreen()),
      GoRoute(path: '/booking/dropoff', builder: (context, state) => const DropoffLocationScreen()),
      GoRoute(path: '/booking/summary', builder: (context, state) => const SummaryScreen()),
      GoRoute(path: '/booking/payment', builder: (context, state) => const PaymentMethodScreen()),
      GoRoute(
        path: '/orders',
        builder: (context, state) => MyOrdersScreen(
          initialFilter: (state.extra as Map<String, dynamic>?)?['filter'] as String? ?? 'all',
        ),
      ),
      GoRoute(
        path: '/orders/:orderId',
        builder: (context, state) => OrderTrackingScreen(
          orderId: int.parse(state.pathParameters['orderId']!),
          showPaymentSuccessToast: (state.extra as Map<String, dynamic>?)?['paymentSuccess'] as bool? ?? false,
        ),
      ),
      GoRoute(
        path: '/orders/:orderId/detail',
        builder: (context, state) => OrderDetailScreen(orderId: int.parse(state.pathParameters['orderId']!)),
      ),
      GoRoute(path: '/account', builder: (context, state) => const AccountScreen()),
      GoRoute(path: '/notifications', builder: (context, state) => const NotificationScreen()),
      GoRoute(
        path: '/account/personal-information',
        builder: (context, state) => PersonalInformationScreen(initialProfile: state.extra as CustomerProfile),
      ),
      GoRoute(path: '/account/saved-addresses', builder: (context, state) => const SavedAddressesScreen()),
      GoRoute(path: '/account/wallet', builder: (context, state) => const WalletScreen()),
      GoRoute(path: '/account/help-support', builder: (context, state) => const HelpSupportScreen()),
      GoRoute(path: '/account/invite-earn', builder: (context, state) => const InviteEarnScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
      GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/otp-verify',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return OtpVerificationScreen(
            customerId: extra?['customerId'] as int?,
            identifier: extra?['identifier'] as String?,
            purpose: extra?['purpose'] as String? ?? 'signup',
          );
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('common.page_not_found'.tr())),
    ),
  );
}
