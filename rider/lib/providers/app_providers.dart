import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../services/api_interceptors.dart';
import '../services/onboarding_storage_service.dart';
import '../services/onesignal_service.dart';
import '../services/road_route_service.dart';
import '../services/rider_auth_service.dart';
import '../services/rider_cash_deposit_service.dart';
import '../services/rider_location_service.dart';
import '../services/rider_location_tracker.dart';
import '../services/rider_order_service.dart';
import '../services/rider_withdrawal_service.dart';
import '../services/secure_storage_service.dart';
import '../services/support_service.dart';
import '../services/live_connection.dart';
import '../services/tour_service.dart';

/// App-wide providers. Kept as plain [Provider]s (no code generation) so the
/// wiring stays readable for buyers extending this codebase — same
/// convention as the User App's own `app_providers.dart`. Grows as each
/// screen/service is built.
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService(const FlutterSecureStorage());
});

/// Whether a token is currently stored — read once in `main()` (before
/// [runApp], so the very first frame already knows the answer) and kept in
/// sync by every place that saves/clears the token (login, reset-password
/// with a token, logout). Drives [buildRouter]'s redirect so a rider who's
/// already signed in lands straight on `/home` on cold start instead of
/// seeing the Welcome/Login screen again.
final isLoggedInProvider = StateProvider<bool>((ref) {
  throw UnimplementedError('isLoggedInProvider must be overridden in main()');
});

/// Overridden in `main()` with the awaited [SharedPreferences] instance
/// (must be ready before [runApp] since routing/onboarding state needs it
/// synchronously).
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in main()');
});

final onboardingStorageProvider = Provider<OnboardingStorageService>((ref) {
  return OnboardingStorageService(ref.watch(sharedPreferencesProvider));
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

final riderAuthServiceProvider = Provider<RiderAuthService>((ref) {
  return RiderAuthService(ref.watch(apiClientProvider));
});

final riderOrderServiceProvider = Provider<RiderOrderService>((ref) {
  return RiderOrderService(ref.watch(apiClientProvider));
});

final riderWithdrawalServiceProvider = Provider<RiderWithdrawalService>((ref) {
  return RiderWithdrawalService(ref.watch(apiClientProvider));
});

final riderCashDepositServiceProvider = Provider<RiderCashDepositService>((ref) {
  return RiderCashDepositService(ref.watch(apiClientProvider));
});

final supportServiceProvider = Provider<SupportService>((ref) {
  return SupportService(ref.watch(apiClientProvider));
});

final oneSignalServiceProvider = Provider<OneSignalService>((ref) {
  return OneSignalService();
});

final riderLocationServiceProvider = Provider<RiderLocationService>((ref) {
  return RiderLocationService();
});

/// Not autoDispose — this holds the location-heartbeat [Timer] and must
/// survive navigation (see RiderLocationTracker's own doc comment), only
/// stopping on an explicit go-offline or logout.
final riderLocationTrackerProvider = Provider<RiderLocationTracker>((ref) {
  return RiderLocationTracker(ref.watch(riderLocationServiceProvider), ref.watch(riderAuthServiceProvider));
});

final routerProvider = Provider<GoRouter>((ref) => buildRouter(ref));

/// Kept for the app's lifetime so its route cache is too.
final roadRouteServiceProvider = Provider<RoadRouteService>((ref) {
  return RoadRouteService(ref.watch(dioProvider));
});

/// The road between two points, for drawing on a map (a straight line
/// until it loads, or if no route is found).
final roadRouteProvider = FutureProvider.autoDispose.family<List<LatLng>, (LatLng, LatLng)>((ref, ends) {
  return ref.watch(roadRouteServiceProvider).route(ends.$1, ends.$2);
});

/// The app's one Pusher connection (see LiveConnection), connected once the
/// settings carry a Pusher key.
final liveConnectionProvider = Provider<LiveConnection>((ref) => LiveConnection());

final tourServiceProvider = Provider<TourService>((ref) => TourService(ref.watch(apiClientProvider)));
