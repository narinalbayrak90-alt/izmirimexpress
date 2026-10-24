import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/app_providers.dart';
import 'screens/home/home_provider.dart';
import 'screens/order/order_detail_provider.dart';
import 'services/app_update_service.dart';
import 'theme/app_theme.dart';

/// Root app widget: wires the router, theme and localization together —
/// same shape as the User App's `PickupDropApp`.
class PickupRiderApp extends ConsumerStatefulWidget {
  const PickupRiderApp({super.key});

  @override
  ConsumerState<PickupRiderApp> createState() => _PickupRiderAppState();
}

class _PickupRiderAppState extends ConsumerState<PickupRiderApp> with WidgetsBindingObserver {
  final _updates = AppUpdateService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the background counts as "opening the app" too — riders
  // rarely fully close it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForUpdate();
      // Settings that failed to load at launch (no signal) or had no
      // OneSignal App ID yet would otherwise leave push off until the
      // app is killed; fetch them again so push starts as soon as it can.
      final settings = ref.read(riderSettingsProvider);
      final appId = settings.valueOrNull?.onesignalAppId;
      if (settings.hasError || (settings.hasValue && (appId == null || appId.isEmpty))) {
        ref.invalidate(riderSettingsProvider);
      }
    }
  }

  /// Offers a newer APK if CI has published one.
  void _checkForUpdate() {
    final router = ref.read(routerProvider);
    _updates.promptIfOutdated(() => router.routerDelegate.navigatorKey.currentContext ?? context);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // The OneSignal App ID is admin-configured (App Setting > Push
    // Notification > Driver App), not a compile-time constant, so
    // initialization waits until it's actually known rather than
    // happening in main() — OneSignalService.initialize is idempotent, so
    // this firing again on a later rebuild is harmless.
    ref.listen(riderSettingsProvider, (previous, next) {
      final appId = next.valueOrNull?.onesignalAppId;
      if (appId == null || appId.isEmpty) return;

      ref.read(oneSignalServiceProvider).initialize(appId);

      // Tapping a "new order available" push (see
      // OneSignalService::notifyOrderAvailable on the backend) brings the
      // rider to Home, where the Available Orders section shows it —
      // there's no dedicated order-detail screen to deep-link into yet.
      ref.read(oneSignalServiceProvider).listenForOrderAvailableClicks((orderId) {
        router.go('/home');
      });

      // Tapping a "this order was cancelled" push (see
      // OneSignalService::notifyRiderOrderCancelled on the backend) takes
      // the rider straight to that order's detail so they see the
      // cancelled state immediately, and refreshes the Active Orders list
      // for whenever they land back on Home.
      ref.read(oneSignalServiceProvider).listenForOrderCancelledClicks((orderId) {
        ref.invalidate(activeOrdersProvider);
        ref.invalidate(orderDetailProvider(orderId));
        router.go('/orders/$orderId');
      });
    });

    return MaterialApp.router(
      title: 'app_name'.tr(),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
    );
  }
}
