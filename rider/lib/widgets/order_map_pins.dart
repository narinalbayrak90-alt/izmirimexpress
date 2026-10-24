import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/rider_order_service.dart';

/// Shared pin colours, so the Map tab, the order detail map and the legend
/// all agree: yellow-orange = pick up here, green = deliver here, blue = a
/// new order still waiting for a rider.
class OrderMapPins {
  OrderMapPins._();

  static final pickup = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
  static final dropoff = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
  static final available = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);

  /// İzmir city centre — where the map starts before any order is loaded.
  static const izmir = LatLng(38.4237, 27.1428);

  static LatLng latLng(RiderLatLng p) => LatLng(p.lat, p.lng);

  /// Smallest box around [points], padded a little so a single stop or two
  /// stops on the same street still give a sensible zoom.
  static LatLngBounds bounds(List<LatLng> points) {
    var south = points.first.latitude, north = south;
    var west = points.first.longitude, east = west;
    for (final p in points) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    const pad = 0.004;
    return LatLngBounds(
      southwest: LatLng(south - pad, west - pad),
      northeast: LatLng(north + pad, east + pad),
    );
  }

  static final _numbered = <String, Future<BitmapDescriptor>>{};

  /// A round pin with the stop's place in the tour on it, orange for a
  /// pickup and green for a drop-off. Drawn once per number and colour.
  static Future<BitmapDescriptor> numbered(int number, {required bool pickup}) {
    return _numbered['$number-$pickup'] ??= _drawNumbered(number, pickup ? const Color(0xFFFF8F00) : const Color(0xFF2FAE60));
  }

  static Future<BitmapDescriptor> _drawNumbered(int number, Color color) async {
    const size = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(size / 2, size / 2);
    canvas.drawCircle(center, size / 2, Paint()..color = Colors.white);
    canvas.drawCircle(center, size / 2 - 7, Paint()..color = color);
    final text = TextPainter(
      text: TextSpan(
        text: '$number',
        style: const TextStyle(color: Colors.white, fontSize: 46, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(png!.buffer.asUint8List(), width: 34, height: 34);
  }
}
