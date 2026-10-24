import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pickup_rider/app.dart';
import 'package:pickup_rider/providers/app_providers.dart';
import 'package:pickup_rider/screens/welcome/welcome_provider.dart';

void main() {
  setUpAll(() async {
    // EasyLocalization itself reads shared_preferences during init, so the
    // mock channel needs a value in place before that call.
    SharedPreferences.setMockInitialValues({});
    await dotenv.load(fileName: '.env');
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('App boots to the welcome screen with Log In / Create Account CTAs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
          // No stored token in this test, so the router's redirect (see
          // buildRouter) should send us to Welcome rather than Home.
          isLoggedInProvider.overrideWith((ref) => false),
          // Avoid a real network call in tests — exercise the same
          // fallback-illustration path the app uses when the backend is
          // unreachable.
          welcomeInfoProvider.overrideWith((ref) async => const WelcomeInfo()),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('es'), Locale('ar')],
          path: 'assets/l10n',
          fallbackLocale: const Locale('en'),
          child: const PickupRiderApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);

    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
  });
}
