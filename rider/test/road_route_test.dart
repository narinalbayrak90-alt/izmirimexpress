import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pickup_rider/services/road_route_service.dart';

void main() {
  test('decodes the route and caches it', () async {
    var calls = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        calls++;
        // Google's documented example polyline.
        handler.resolve(Response(requestOptions: options, data: {
          'routes': [
            {'overview_polyline': {'points': '_p~iF~ps|U_ulLnnqC_mqNvxq`@'}},
          ],
        }));
      }));
    final service = RoadRouteService(dio);
    const a = LatLng(38.5, -120.2), b = LatLng(43.252, -126.453);
    final route = await service.route(a, b);
    expect(route.length, 3);
    expect(route[1].latitude, closeTo(40.7, 1e-6));
    expect(route[2].longitude, closeTo(-126.453, 1e-6));
    await service.route(a, b);
    expect(calls, 1);
  });

  test('falls back to a straight line', () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(requestOptions: options, data: {'status': 'ZERO_RESULTS', 'routes': []}));
      }));
    const a = LatLng(1, 2), b = LatLng(3, 4);
    expect(await RoadRouteService(dio).route(a, b), [a, b]);
  });
}
