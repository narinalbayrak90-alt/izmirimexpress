import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How often on-screen data quietly re-fetches, so order statuses, rider
/// positions and balances change without the user pulling to refresh.
/// The backend runs on shared hosting with no WebSocket server, so this is
/// polling; it pauses while the app is in the background.
const liveRefreshInterval = Duration(seconds: 10);

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
    onDispose(() => timer.cancel());
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

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) {
      if (_appIsVisible) onTick();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
