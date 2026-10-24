import 'dart:js_interop';

/// `window.izmirimZoom`, defined in web/index.html.
@JS('izmirimZoom')
external JSFunction? get _zoom;

double pageZoom() {
  final zoom = _zoom;
  if (zoom == null) return 1;
  final value = (zoom.callAsFunction() as JSNumber?)?.toDartDouble ?? 1;
  return value.isFinite && value > 1 ? value : 1;
}
