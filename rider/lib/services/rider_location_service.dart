import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Thin wrapper around [Geolocator] — the single place in the app that
/// touches location permissions/position directly.
///
/// [positionStream] is what keeps a rider's live position flowing to the
/// backend even while the app is backgrounded (e.g. minimized behind a
/// maps app while driving) — plain `Timer`-based polling of
/// [getCurrentPosition] can't do that, since Dart timers freeze once the
/// OS suspends the app. Android gets there via a foreground service (see
/// [_platformSettings]'s [ForegroundNotificationConfig] — this is exactly
/// what `ACCESS_BACKGROUND_LOCATION`/`FOREGROUND_SERVICE_LOCATION` in
/// AndroidManifest.xml exist for); iOS via `UIBackgroundModes: location`
/// in Info.plist plus [AppleSettings.allowBackgroundLocationUpdates].
/// Neither survives the OS fully killing the app process — that needs a
/// separate native background-service architecture, out of scope here
/// and unnecessary for the "minimized, not force-quit" case this covers.
class RiderLocationService {
  /// Requests location permission if not already decided, escalating to
  /// "always" rather than settling for "while in use" once granted —
  /// needed for [positionStream] to keep delivering updates once the app
  /// is backgrounded. Returns false for denied/deniedForever, or if
  /// location services are off at the OS level — callers should explain
  /// that going online requires location rather than silently failing to
  /// report a position.
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse) {
      // Android requires foreground and background location be requested
      // in two separate prompts — this second call is what actually
      // shows the "Allow all the time" dialog (see PermissionManager's
      // own requestPermission logic in geolocator_android). iOS ignores
      // repeat calls once a decision is already made; there, "always" is
      // instead earned automatically over time once the OS observes the
      // app actually using background location, which starting
      // [positionStream] with `allowBackgroundLocationUpdates: true` does.
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }

  /// Null when permission isn't granted, location services are off, or
  /// the platform fails to produce a fix — callers should treat this as
  /// "skip this update" rather than an error worth surfacing every time.
  Future<Position?> getCurrentPosition() async {
    if (!await ensurePermission()) return null;

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (_) {
      return null;
    }
  }

  /// Continuous position updates, configured per-platform to keep
  /// flowing while the app is backgrounded — see this class's own doc
  /// comment. Callers (RiderLocationTracker) throttle how often they
  /// actually push a position to the backend; this stream is just the
  /// freshest-known-fix source, not the push cadence itself.
  Stream<Position> positionStream() {
    return Geolocator.getPositionStream(locationSettings: _platformSettings());
  }

  LocationSettings _platformSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'location.notification_title'.tr(),
          notificationText: 'location.notification_text'.tr(),
          enableWakeLock: true,
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }

    return const LocationSettings(accuracy: LocationAccuracy.high);
  }
}
