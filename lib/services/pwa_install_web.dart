import 'dart:async';
import 'dart:js_interop';

/// `window.izmirimPwa`, defined in web/index.html.
@JS('izmirimPwa')
external _IzmirimPwa? get _pwa;

extension type _IzmirimPwa(JSObject _) implements JSObject {
  external bool isStandalone();
  external bool isIos();
  external bool canPrompt();
  external JSPromise<JSString> prompt();
}

@JS('addEventListener')
external void _addEventListener(String type, JSFunction listener);

bool isStandalone() => _pwa?.isStandalone() ?? false;

bool isIos() => _pwa?.isIos() ?? false;

bool canPrompt() => _pwa?.canPrompt() ?? false;

Future<bool> prompt() async {
  final pwa = _pwa;
  if (pwa == null) return false;
  final outcome = await pwa.prompt().toDart;
  return outcome.toDart == 'accepted';
}

final _changes = StreamController<void>.broadcast(
  onListen: _listenOnce,
);

var _listening = false;

void _listenOnce() {
  if (_listening) return;
  _listening = true;
  _addEventListener('izmirim-pwa-change', (() => _changes.add(null)).toJS);
}

Stream<void> changes() => _changes.stream;
