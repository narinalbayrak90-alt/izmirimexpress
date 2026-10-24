import 'web_push_stub.dart' if (dart.library.js_interop) 'web_push_web.dart' as platform;

/// Browser push for the web build, through OneSignal's Web SDK (the
/// Flutter SDK has no web side). Backed by `window.izmirimPush` in
/// web/index.html; every call is a no-op on the mobile builds.
class WebPush {
  const WebPush._();

  /// The browser can receive push at all. False on an iPhone until the
  /// site is added to the home screen (Safari only allows push there).
  static bool get isSupported => platform.isSupported();

  /// `default` (not asked yet), `granted` or `denied`.
  static String get permission => platform.permission();

  static void init(String appId) => platform.init(appId);

  /// Shows the browser's "allow notifications" prompt; true when allowed.
  /// Must run from a tap: Safari and Firefox ignore it otherwise.
  static Future<bool> requestPermission() => platform.requestPermission();

  static void tagUserId(int customerId) => platform.tagUserId(customerId);

  static void clearUserTag() => platform.clearUserTag();
}
