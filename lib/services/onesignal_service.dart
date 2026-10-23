import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../config/env.dart';

/// Thin wrapper around the OneSignal SDK — the single place in the app
/// that touches `OneSignal.*` directly, so nothing else needs to know the
/// SDK's API surface.
///
/// The app's OneSignal App ID is admin-configured (App Setting > Push
/// Notification) rather than a compile-time constant, so [initialize] is
/// called once the app's settings are fetched (see `appSettingsProvider`),
/// not from `main()` — [_isInitialized] makes repeat calls (e.g. on every
/// settings refresh) harmless.
class OneSignalService {
  bool _isInitialized = false;

  void initialize(String appId) {
    if (_isInitialized || appId.isEmpty) return;

    OneSignal.Debug.setLogLevel(Env.isProduction ? OSLogLevel.none : OSLogLevel.verbose);
    OneSignal.initialize(appId);
    _isInitialized = true;
  }

  /// Requests OS-level notification permission — a no-op if already
  /// granted/denied. Needed for push to actually arrive on iOS and on
  /// Android 13+ (POST_NOTIFICATIONS is a runtime permission there).
  Future<bool> requestPermission() {
    return OneSignal.Notifications.requestPermission(true);
  }

  /// Tags this device with the logged-in customer's id (project.txt
  /// Module 14) so the backend can target personalised notifications —
  /// e.g. "send to users where user_id = 123" via OneSignal's REST API.
  void tagUserId(int customerId) {
    OneSignal.User.addTagWithKey('user_id', customerId.toString());
  }

  /// Removes the `user_id` tag on logout/account deletion so a
  /// shared/reused device doesn't keep receiving the previous customer's
  /// personalised notifications after they've signed out.
  void clearUserTag() {
    OneSignal.User.removeTag('user_id');
  }
}
