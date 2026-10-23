import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed accessors over the values loaded from `.env` by [dotenv].
///
/// Keeps `dotenv.env[...]` string lookups out of the rest of the app so
/// callers get sane defaults instead of null-checking everywhere, and so
/// there's a single place to update if a key is renamed.
///
/// The web build doesn't read `.env` (it would be a publicly served file,
/// and the server blocks dotfiles anyway): there the API lives on the same
/// domain as the app, under `/admin/api`, unless overridden at build time
/// with `--dart-define=API_BASE_URL=...`.
class Env {
  Env._();

  static const _webApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (kIsWeb) {
      return _webApiBaseUrl.isNotEmpty ? _webApiBaseUrl : '${Uri.base.origin}/admin/api';
    }
    return dotenv.env['API_BASE_URL'] ?? '';
  }

  /// Unused on web: Google calls go through the backend's `/maps` proxy,
  /// which adds the admin-configured key server-side.
  static String get googleMapsApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  static bool get isProduction => kIsWeb ? kReleaseMode : dotenv.env['APP_ENV'] == 'production';
}
