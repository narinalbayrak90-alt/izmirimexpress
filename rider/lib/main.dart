import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'providers/app_providers.dart';
import 'services/secure_storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await EasyLocalization.ensureInitialized();
  final sharedPreferences = await SharedPreferences.getInstance();

  // Read the stored token before the first frame so the router's initial
  // redirect (see buildRouter) already knows whether the rider is signed
  // in — otherwise Welcome would flash before jumping to Home.
  final secureStorageService = SecureStorageService(const FlutterSecureStorage());
  final token = await secureStorageService.readToken();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        secureStorageProvider.overrideWithValue(secureStorageService),
        isLoggedInProvider.overrideWith((ref) => token != null && token.isNotEmpty),
      ],
      child: EasyLocalization(
        supportedLocales: const [Locale('tr'), Locale('en'), Locale('es'), Locale('ar')],
        path: 'assets/l10n',
        // Turkish unless the rider picks another language from Account >
        // Language (EasyLocalization saves that choice and it wins).
        startLocale: const Locale('tr'),
        fallbackLocale: const Locale('tr'),
        child: const PickupRiderApp(),
      ),
    ),
  );
}
