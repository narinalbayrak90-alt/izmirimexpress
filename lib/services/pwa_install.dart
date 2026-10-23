import 'pwa_install_stub.dart' if (dart.library.js_interop) 'pwa_install_web.dart' as platform;

/// "Install the app" support for the web build (PWA).
///
/// Android and desktop Chrome/Edge show their own install dialog
/// ([canPrompt] / [prompt]); iOS Safari has none, so the app explains
/// "Share > Add to Home Screen" instead ([isIos]). Everything reports
/// false on the mobile builds, which are already installed apps. Backed by
/// `window.izmirimPwa` in web/index.html.
class PwaInstall {
  const PwaInstall._();

  /// Already running as an installed app (home screen / app window).
  static bool get isStandalone => platform.isStandalone();

  static bool get isIos => platform.isIos();

  /// The browser's install dialog is ready to show.
  static bool get canPrompt => platform.canPrompt();

  /// Whether there's anything to offer: a dialog, or the iOS steps.
  static bool get isAvailable => !isStandalone && (canPrompt || isIos);

  /// Shows the browser's install dialog; true when the customer accepted.
  static Future<bool> prompt() => platform.prompt();

  /// Fires when [canPrompt] or [isStandalone] may have changed (the
  /// dialog became available, or the app got installed).
  static Stream<void> get changes => platform.changes();
}
