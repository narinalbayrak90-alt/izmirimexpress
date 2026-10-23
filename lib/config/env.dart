import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed accessors over the values loaded from `.env` by [dotenv].
///
/// Keeps `dotenv.env[...]` string lookups out of the rest of the app so
/// callers get sane defaults instead of null-checking everywhere, and so
/// there's a single place to update if a key is renamed.
class Env {
  Env._();

  static String get apiBaseUrl => dotenv.env['API_BASE_URL'] ?? '';

  static String get googleMapsApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  static bool get isProduction => dotenv.env['APP_ENV'] == 'production';
}
