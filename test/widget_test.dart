import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pickup_drop/app.dart';
import 'package:pickup_drop/providers/app_providers.dart';
import 'package:pickup_drop/screens/home/home_category.dart';
import 'package:pickup_drop/screens/home/home_provider.dart';
import 'package:pickup_drop/screens/welcome/welcome_content.dart';
import 'package:pickup_drop/screens/welcome/welcome_provider.dart';

void main() {
  setUpAll(() async {
    // EasyLocalization itself reads shared_preferences during init, so the
    // mock channel needs a value in place before that call.
    SharedPreferences.setMockInitialValues({});
    await dotenv.load(fileName: '.env');
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('App boots to the welcome screen and Get Started persists the seen flag',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
          // Avoid a real network call in tests — exercise the same
          // fallback-content path the app uses when the backend is
          // unreachable.
          welcomeContentProvider.overrideWith((ref) async => WelcomeContent.fallback()),
          homeCategoriesProvider.overrideWith((ref) async => const <HomeCategory>[]),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('es'), Locale('ar')],
          path: 'assets/l10n',
          fallbackLocale: const Locale('en'),
          child: const PickupDropApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Get Started'), findsOneWidget);
    expect(sharedPreferences.getBool('has_seen_welcome'), isNot(true));

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(sharedPreferences.getBool('has_seen_welcome'), isTrue);
  });

  testWidgets('Router redirects straight to /home once welcome has already been seen',
      (tester) async {
    SharedPreferences.setMockInitialValues({'has_seen_welcome': true});
    final sharedPreferences = await SharedPreferences.getInstance();

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        welcomeContentProvider.overrideWith((ref) async => WelcomeContent.fallback()),
        homeCategoriesProvider.overrideWith((ref) async => const <HomeCategory>[]),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(routerProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/home');
  });
}
