import 'dart:js_interop';

/// `window.izmirimPush`, defined in web/index.html.
@JS('izmirimPush')
external _IzmirimPush? get _push;

extension type _IzmirimPush(JSObject _) implements JSObject {
  external bool isSupported();
  external JSString permission();
  external void init(JSString appId);
  external JSPromise<JSBoolean> requestPermission();
  external void tag(JSString customerId);
  external void untag();
}

bool isSupported() => _push?.isSupported() ?? false;

String permission() => _push?.permission().toDart ?? 'denied';

void init(String appId) => _push?.init(appId.toJS);

Future<bool> requestPermission() async {
  final push = _push;
  if (push == null) return false;
  return (await push.requestPermission().toDart).toDart;
}

void tagUserId(int customerId) => _push?.tag(customerId.toString().toJS);

void clearUserTag() => _push?.untag();
