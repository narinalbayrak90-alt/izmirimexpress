import 'page_zoom_stub.dart' if (dart.library.js_interop) 'page_zoom_web.dart' as platform;

/// How much the browser has zoomed the page on its own (1 when it hasn't).
///
/// Chrome on Android zooms every page to follow the phone's font size
/// setting, which blows up the whole app — buttons, cards and icons, not
/// just the text — compared to the same screens in a native app.
double pageZoom() => platform.pageZoom();
