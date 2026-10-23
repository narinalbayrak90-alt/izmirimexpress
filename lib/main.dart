import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // See Env: the web build takes its config from the page's own domain.
    dotenv.loadFromString(isOptional: true);
  } else {
    await dotenv.load(fileName: '.env');
  }
  await EasyLocalization.ensureInitialized();
  final sharedPreferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: EasyLocalization(
        supportedLocales: const [Locale('tr'), Locale('en'), Locale('es'), Locale('ar')],
        path: 'assets/l10n',
        startLocale: const Locale('tr'),
        fallbackLocale: const Locale('tr'),
        child: const PickupDropApp(),
      ),
    ),
  );
}
