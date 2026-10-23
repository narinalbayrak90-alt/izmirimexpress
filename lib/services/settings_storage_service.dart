import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

/// Persists the [AppSettings] fetched from `GET /home` to local storage
/// (project.txt Module 1: "save in localstorage so we can use that in
/// entire app like currency, language etc."), so the rest of the app can
/// read them synchronously without waiting on a network call.
class SettingsStorageService {
  SettingsStorageService(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'app_settings';
  static const _languageChosenKey = 'language_manually_chosen';
  static const _installCardDismissedKey = 'install_card_dismissed';

  AppSettings? read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Cached shape from a previous app version — refetch instead of crashing.
      return null;
    }
  }

  Future<void> save(AppSettings settings) => _prefs.setString(_key, jsonEncode(settings.toJson()));

  /// Whether the customer has ever explicitly picked a language (Account >
  /// Change Language) — while false, the app follows App Setting >
  /// Language's `default_language` automatically; once true, that manual
  /// choice always wins and the admin's default is never re-applied.
  bool hasManuallyChosenLanguage() => _prefs.getBool(_languageChosenKey) ?? false;

  Future<void> setManuallyChosenLanguage() => _prefs.setBool(_languageChosenKey, true);

  /// Whether the customer closed the home screen's "Install the app" card
  /// (Account > Install App still offers it).
  bool isInstallCardDismissed() => _prefs.getBool(_installCardDismissedKey) ?? false;

  Future<void> setInstallCardDismissed() => _prefs.setBool(_installCardDismissedKey, true);
}
