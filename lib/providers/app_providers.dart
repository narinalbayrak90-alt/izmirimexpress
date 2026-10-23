import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';
import '../router/app_router.dart';
import '../services/address_service.dart';
import '../services/api_client.dart';
import '../services/api_interceptors.dart';
import '../services/auth_service.dart';
import '../services/fare_service.dart';
import '../services/google_places_service.dart';
import '../services/notification_service.dart';
import '../services/onboarding_storage_service.dart';
import '../services/onesignal_service.dart';
import '../services/order_service.dart';
import '../services/payment_service.dart';
import '../services/referral_service.dart';
import '../services/secure_storage_service.dart';
import '../services/settings_storage_service.dart';
import '../services/support_service.dart';
import '../services/wallet_service.dart';

/// App-wide providers. Kept as plain [Provider]s (no code generation) so the
/// wiring stays readable for buyers extending this codebase.
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService(const FlutterSecureStorage());
});

/// Overridden in `main()` with the awaited [SharedPreferences] instance
/// (must be ready before [runApp] since the router's redirect logic needs
/// it synchronously).
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in main()');
});

final onboardingStorageProvider = Provider<OnboardingStorageService>((ref) {
  return OnboardingStorageService(ref.watch(sharedPreferencesProvider));
});

final settingsStorageProvider = Provider<SettingsStorageService>((ref) {
  return SettingsStorageService(ref.watch(sharedPreferencesProvider));
});

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(AuthInterceptor(ref.watch(secureStorageProvider)));
  dio.interceptors.add(ApiErrorInterceptor());

  if (!Env.isProduction) {
    dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
  }

  return dio;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(dioProvider));
});

final fareServiceProvider = Provider<FareService>((ref) {
  return FareService(ref.watch(apiClientProvider));
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(apiClientProvider));
});

final orderServiceProvider = Provider<OrderService>((ref) {
  return OrderService(ref.watch(apiClientProvider));
});

final addressServiceProvider = Provider<AddressService>((ref) {
  return AddressService(ref.watch(apiClientProvider));
});

final supportServiceProvider = Provider<SupportService>((ref) {
  return SupportService(ref.watch(apiClientProvider));
});

final referralServiceProvider = Provider<ReferralService>((ref) {
  return ReferralService(ref.watch(apiClientProvider));
});

final oneSignalServiceProvider = Provider<OneSignalService>((ref) {
  return OneSignalService();
});

final walletServiceProvider = Provider<WalletService>((ref) {
  return WalletService(ref.watch(apiClientProvider));
});

final paymentServiceProvider = Provider<PaymentService>((ref) {
  return PaymentService(ref.watch(apiClientProvider));
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref.watch(apiClientProvider));
});

/// Separate from [dioProvider] — these calls go straight to Google's APIs,
/// not our backend, so they must not carry the backend auth interceptor.
///
/// Browsers block direct calls to Google's web services (no CORS), so the
/// web build goes through the backend's `/maps` proxy instead, which mirrors
/// Google's paths and responses and adds the API key server-side.
final googlePlacesServiceProvider = Provider<GooglePlacesService>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: kIsWeb ? '${Env.apiBaseUrl}/maps' : 'https://maps.googleapis.com/maps/api',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
  return GooglePlacesService(dio);
});

final routerProvider = Provider<GoRouter>((ref) => buildRouter(ref));
