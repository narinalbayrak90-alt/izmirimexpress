import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'rider_auth_service.dart';
import 'rider_location_service.dart';

/// Keeps `current_lat`/`current_lng` fresh on the backend while the rider
/// is online — reports a position immediately on [start], then every
/// [_pushInterval] until [stop], including while the app is backgrounded
/// (see [RiderLocationService.positionStream]'s own doc comment for how).
/// Lives in a provider (not a widget's state) so it keeps running across
/// navigation and only stops on an explicit go-offline or logout, not on
/// leaving whatever screen started it.
///
/// Two moving pieces, deliberately decoupled: [_positionSubscription]
/// keeps [_lastPosition] as fresh as the OS is willing to deliver fixes
/// (which varies — Android's `intervalDuration` targets 5s, iOS is
/// distance-filter-driven so its cadence isn't fixed), while
/// [_pushTimer] pushes whatever's cached on its own exact 5-second beat.
/// That way the push cadence the backend sees is always exactly 5
/// seconds regardless of GPS fix jitter.
class RiderLocationTracker {
  RiderLocationTracker(this._locationService, this._authService);

  static const _pushInterval = Duration(seconds: 5);

  final RiderLocationService _locationService;
  final RiderAuthService _authService;

  StreamSubscription<Position>? _positionSubscription;
  Timer? _pushTimer;
  Position? _lastPosition;

  /// The latest fix while online, for requests that plan from where the
  /// rider is right now (the tour).
  Position? get lastPosition => _lastPosition;

  void start() {
    stop();

    _positionSubscription = _locationService.positionStream().listen(
      (position) => _lastPosition = position,
      onError: (_) {
        // A dropped fix just means [_pushOnce] skips this tick — the
        // stream itself keeps running and recovers on its own.
      },
    );

    _pushFreshFixThenStartTimer();
  }

  void stop() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _pushTimer?.cancel();
    _pushTimer = null;
    _lastPosition = null;
  }

  /// The very first push can't wait on [_positionSubscription] to
  /// deliver its first event — that could take a moment — so it fetches
  /// one fix directly, same as the old poll-based tracker did.
  Future<void> _pushFreshFixThenStartTimer() async {
    _lastPosition = await _locationService.getCurrentPosition();
    await _pushOnce();
    // [stop] may have run while the above was in flight (e.g. a rapid
    // online/offline toggle) — [_positionSubscription] is null in that
    // case, and starting the timer now would leave it running with
    // nothing to cancel it until the next [start].
    if (_positionSubscription == null) return;
    _pushTimer = Timer.periodic(_pushInterval, (_) => _pushOnce());
  }

  Future<void> _pushOnce() async {
    final position = _lastPosition;
    if (position == null) return;

    try {
      await _authService.updateLocation(lat: position.latitude, lng: position.longitude);
    } catch (_) {
      // Best-effort heartbeat — a dropped update just means the next
      // timer tick (or the customer's own stale-ETA tolerance) catches up.
    }
  }
}
