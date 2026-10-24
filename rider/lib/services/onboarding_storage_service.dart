import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the user has already dismissed the one-time welcome
/// screen, so it only ever shows on a fresh install (not plain
/// auth/session state, so [SecureStorageService] isn't the right fit here).
class OnboardingStorageService {
  OnboardingStorageService(this._prefs);

  final SharedPreferences _prefs;

  static const _hasSeenWelcomeKey = 'has_seen_welcome';

  bool get hasSeenWelcome => _prefs.getBool(_hasSeenWelcomeKey) ?? false;

  Future<void> markWelcomeSeen() => _prefs.setBool(_hasSeenWelcomeKey, true);
}
