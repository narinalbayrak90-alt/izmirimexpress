import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../config/env.dart';
import 'web_push.dart';

/// Thin wrapper around the OneSignal SDK — the single place in the app
/// that touches `OneSignal.*` directly, so nothing else needs to know the
/// SDK's API surface.
///
/// The app's OneSignal App ID is admin-configured (App Setting > Push
/// Notification) rather than a compile-time constant, so [initialize] is
/// called once the app's settings are fetched (see `appSettingsProvider`),
/// not from `main()` — [_isInitialized] makes repeat calls (e.g. on every
/// settings refresh) harmless.
///
/// The OneSignal Flutter SDK has no web implementation, so the web build
/// goes through OneSignal's Web SDK instead (see [WebPush]); the same App
/// ID works for both once the OneSignal app has its Web platform set up.
class OneSignalService {
  bool _isInitialized = false;

  void initialize(String appId) {
    if (_isInitialized || appId.isEmpty) return;
    if (kIsWeb) {
      WebPush.init(appId);
      _isInitialized = true;
      return;
    }

    OneSignal.Debug.setLogLevel(Env.isProduction ? OSLogLevel.none : OSLogLevel.verbose);
    OneSignal.initialize(appId);
    _isInitialized = true;
  }

  /// Whether the customer still has to be asked (web: the browser can do
  /// push and they haven't answered yet; mobile: not granted yet).
  bool get needsPermission {
    if (kIsWeb) return WebPush.isSupported && WebPush.permission == 'default';
    return _isInitialized && !OneSignal.Notifications.permission;
  }

  /// Requests OS-level notification permission — a no-op if already
  /// granted/denied. Needed for push to actually arrive on iOS and on
  /// Android 13+ (POST_NOTIFICATIONS is a runtime permission there).
  Future<bool> requestPermission() async {
    if (kIsWeb) return WebPush.requestPermission();
    if (!_isInitialized) return false;
    return OneSignal.Notifications.requestPermission(true);
  }

  /// Tags this device with the logged-in customer's id (project.txt
  /// Module 14) so the backend can target personalised notifications —
  /// e.g. "send to users where user_id = 123" via OneSignal's REST API.
  void tagUserId(int customerId) {
    if (kIsWeb) return WebPush.tagUserId(customerId);
    OneSignal.User.addTagWithKey('user_id', customerId.toString());
  }

  /// Removes the `user_id` tag on logout/account deletion so a
  /// shared/reused device doesn't keep receiving the previous customer's
  /// personalised notifications after they've signed out.
  void clearUserTag() {
    if (kIsWeb) return WebPush.clearUserTag();
    OneSignal.User.removeTag('user_id');
  }
}
