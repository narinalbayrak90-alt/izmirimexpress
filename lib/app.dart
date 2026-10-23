import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/app_providers.dart';
import 'screens/home/home_provider.dart';
import 'theme/app_theme.dart';
import 'widgets/responsive_shell.dart';

/// Root app widget: wires the router, theme and localization together.
class PickupDropApp extends ConsumerWidget {
  const PickupDropApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    // The OneSignal App ID is admin-configured (App Setting > Push
    // Notification), not a compile-time constant, so initialization waits
    // until it's actually known rather than happening in main() —
    // OneSignalService.initialize is idempotent, so this firing again on
    // a later settings refresh is harmless.
    ref.listen(appSettingsProvider, (previous, next) {
      final settings = next.valueOrNull;
      if (settings == null) return;

      final appId = settings.onesignalAppId;
      if (appId != null && appId.isNotEmpty) {
        ref.read(oneSignalServiceProvider).initialize(appId);
      }

      // İzmirim Express is a Turkish service: the app always opens in
      // Turkish until the customer explicitly picks another language
      // (Account > Change Language). The admin's `default_language` isn't
      // applied — it was set to English on the live panel and kept
      // switching every new visitor to English.
      final storage = ref.read(settingsStorageProvider);
      if (!storage.hasManuallyChosenLanguage() && context.locale.languageCode != 'tr') {
        context.setLocale(const Locale('tr'));
      }
    });

    return MaterialApp.router(
      title: 'app_name'.tr(),
      // On the web this becomes the page's theme-color (browser and
      // installed-app status/navigation bars); the default, the yellow
      // primary color, showed as stripes above and below the app.
      color: Colors.white,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) => ResponsiveShell(child: child ?? const SizedBox.shrink()),
    );
  }
}
