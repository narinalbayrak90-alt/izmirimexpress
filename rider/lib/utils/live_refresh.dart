import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How often on-screen data quietly re-fetches, so order statuses, rider
/// positions and balances change without the user pulling to refresh.
/// The backend runs on shared hosting with no WebSocket server, so this
/// polls (pausing in the background), and [liveSignals] from Pusher make it
/// immediate when the admin has set Pusher up.
const liveRefreshInterval = Duration(seconds: 5);

/// Fires when the backend signals a change through Pusher (see
/// LiveConnection). Everything that refreshes on a timer also refreshes on
/// this, so changes show at once when Pusher is set up and within
/// [liveRefreshInterval] when it isn't.
final liveSignals = StreamController<void>.broadcast();

bool get _appIsVisible {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == null || state == AppLifecycleState.resumed;
}

extension LiveRefreshRef on Ref {
  /// Re-runs this provider every [every] while something watches it. The
  /// old value stays on screen during the re-fetch (Riverpod keeps it on
  /// refresh), so nothing flickers.
  void refreshEvery([Duration every = liveRefreshInterval]) {
    late Timer timer;
    void schedule() {
      timer = Timer(every, () {
        if (_appIsVisible) {
          invalidateSelf();
        } else {
          schedule();
        }
      });
    }

    schedule();
    final signals = liveSignals.stream.listen((_) {
      if (!_appIsVisible) return;
      timer.cancel();
      invalidateSelf();
    });
    onDispose(() {
      timer.cancel();
      signals.cancel();
    });
  }
}

/// Calls [onTick] every [every] while the State is mounted and the app is
/// in the foreground — for screens that load with setState rather than a
/// provider.
class LiveTicker {
  LiveTicker(this.onTick, {this.every = liveRefreshInterval});

  final VoidCallback onTick;
  final Duration every;
  Timer? _timer;
  StreamSubscription<void>? _signals;

  void start() {
    stop();
    _timer = Timer.periodic(every, (_) {
      if (_appIsVisible) onTick();
    });
    _signals = liveSignals.stream.listen((_) {
      if (_appIsVisible) onTick();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _signals?.cancel();
    _signals = null;
  }
}
