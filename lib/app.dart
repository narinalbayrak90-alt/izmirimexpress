import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/app_providers.dart';
import 'screens/home/home_provider.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

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

      // App Setting > Language's `default_language` drives the app's
      // locale until the customer explicitly picks one themselves
      // (Account > Change Language) — a manual choice always wins from
      // then on, so this never overrides it.
      final storage = ref.read(settingsStorageProvider);
      if (!storage.hasManuallyChosenLanguage() &&
          context.supportedLocales.any((locale) => locale.languageCode == settings.defaultLanguage) &&
          context.locale.languageCode != settings.defaultLanguage) {
        context.setLocale(Locale(settings.defaultLanguage));
      }
    });

    return MaterialApp.router(
      title: 'app_name'.tr(),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) => _MobileWidthFrame(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Keeps the app at phone width on wide screens (the web build on a
/// desktop browser): screens are laid out for a phone — full-width buttons,
/// edge-to-edge cards — and stretched across a monitor they turn into huge
/// bars. On a phone-sized screen this is a no-op.
///
/// [MediaQuery] is narrowed too, so widgets that size themselves from the
/// screen width (sheets, carousels, dialogs) see the frame, not the window.
class _MobileWidthFrame extends StatelessWidget {
  const _MobileWidthFrame({required this.child});

  final Widget child;

  static const double maxWidth = 480;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    if (mediaQuery.size.width <= maxWidth) return child;

    return ColoredBox(
      color: AppColors.frameBackdrop,
      child: Center(
        child: SizedBox(
          width: maxWidth,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: [BoxShadow(color: Color(0x1F000000), blurRadius: 24)],
            ),
            child: ClipRect(
              child: MediaQuery(
                data: mediaQuery.copyWith(size: Size(maxWidth, mediaQuery.size.height)),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
