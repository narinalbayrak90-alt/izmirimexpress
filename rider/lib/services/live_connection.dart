import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/live_refresh.dart';

/// Pusher Channels connection that turns the backend's "something changed"
/// signals (LiveSignal on the backend) into [liveSignals], so screens
/// refresh the moment an order changes instead of on their next poll.
///
/// Speaks Pusher's WebSocket protocol directly: the channels are public and
/// a signal carries no data (the app re-fetches through the normal API), so
/// subscribing, answering pings and reconnecting is all it takes. Without a
/// key from the admin panel nothing connects and polling carries on alone.
class LiveConnection {
  String? _url;
  final Set<String> _channels = {};
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  bool _established = false;
  bool _wasConnected = false;
  Duration _delay = const Duration(seconds: 1);

  void connect({required String key, required String cluster}) {
    connectUrl('wss://ws-$cluster.pusher.com/app/${Uri.encodeComponent(key)}?protocol=7&client=izmirim&version=1.0');
  }

  @visibleForTesting
  void connectUrl(String url) {
    if (url == _url) return;
    _url = url;
    _close();
    _open();
  }

  void subscribe(String channel) {
    if (_channels.add(channel) && _established) {
      _send('pusher:subscribe', {'channel': channel});
    }
  }

  void unsubscribe(String channel) {
    if (_channels.remove(channel) && _established) {
      _send('pusher:unsubscribe', {'channel': channel});
    }
  }

  void _open() {
    final url = _url;
    if (url == null) return;
    try {
      final socket = WebSocketChannel.connect(Uri.parse(url));
      _socket = socket;
      _subscription = socket.stream.listen(
        _onMessage,
        onDone: _reconnectLater,
        onError: (Object _) => _reconnectLater(),
        cancelOnError: true,
      );
    } catch (_) {
      _reconnectLater();
    }
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> message;
    try {
      message = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (message['event']) {
      case 'pusher:connection_established':
        _established = true;
        _delay = const Duration(seconds: 1);
        for (final channel in _channels) {
          _send('pusher:subscribe', {'channel': channel});
        }
        // Signals sent while the connection was down were missed; catch up.
        if (_wasConnected) liveSignals.add(null);
        _wasConnected = true;
      case 'pusher:ping':
        _send('pusher:pong', const {});
      case 'changed':
        liveSignals.add(null);
    }
  }

  void _send(String event, Map<String, dynamic> data) {
    try {
      _socket?.sink.add(jsonEncode({'event': event, 'data': data}));
    } catch (_) {
      // The socket is closing; the reconnect subscribes again.
    }
  }

  void _reconnectLater() {
    _subscription?.cancel();
    _subscription = null;
    _socket = null;
    _established = false;
    _retry?.cancel();
    _retry = Timer(_delay, _open);
    _delay = Duration(seconds: min(_delay.inSeconds * 2, 30));
  }

  void _close() {
    _retry?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _socket?.sink.close();
    _socket = null;
    _established = false;
  }
}
