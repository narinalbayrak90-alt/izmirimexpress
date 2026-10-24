import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_rider/services/live_connection.dart';
import 'package:pickup_rider/utils/live_refresh.dart';

void main() {
  test('subscribes after the handshake, answers pings and relays changes', () async {
    final received = <Map<String, dynamic>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((data) {
        final message = jsonDecode(data as String) as Map<String, dynamic>;
        received.add(message);
        if (message['event'] == 'pusher:subscribe') {
          socket.add(jsonEncode({'event': 'pusher:ping', 'data': '{}'}));
          socket.add(jsonEncode({'event': 'changed', 'channel': 'riders', 'data': '{}'}));
        }
      });
      socket.add(jsonEncode({'event': 'pusher:connection_established', 'data': '{"socket_id":"1.2"}'}));
    });

    final signal = liveSignals.stream.first;
    LiveConnection()
      ..subscribe('riders')
      ..connectUrl('ws://127.0.0.1:${server.port}/app/key');

    await signal.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(received.map((m) => m['event']), containsAllInOrder(['pusher:subscribe', 'pusher:pong']));
    expect(received.first['data'], {'channel': 'riders'});
    await server.close(force: true);
  });
}
