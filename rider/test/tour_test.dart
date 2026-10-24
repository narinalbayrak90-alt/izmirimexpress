import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_rider/services/tour_service.dart';

void main() {
  test('parses the planned tour', () {
    final tour = RiderTour.fromJson({
      'stops': [
        {'key': '7-dropoff', 'order_id': 7, 'kind': 'dropoff', 'position': 1, 'lat': 38.4, 'lng': 27.1, 'address': 'A', 'eta': '2026-10-24T15:40:00+03:00', 'leg_meters': 900},
        {'key': '9-pickup', 'order_id': 9, 'kind': 'pickup', 'position': 2, 'lat': 38.41, 'lng': 27.12, 'address': 'B', 'eta': '2026-10-24T15:50:00+03:00', 'ready_at': '2026-10-24T15:55:00+03:00'},
        {'key': '9-dropoff', 'order_id': 9, 'kind': 'dropoff', 'position': 3, 'lat': 38.42, 'lng': 27.13, 'address': 'C', 'eta': '2026-10-24T16:05:00+03:00'},
      ],
      'total_seconds': 1500,
      'total_meters': 5200,
      'polyline': '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
      'delay_warning': false,
    });

    expect(tour.isMultiOrder, isTrue);
    expect(tour.stops.map((s) => s.isPickup), [false, true, false]);
    expect(tour.stops[1].readyAt, isNotNull);
    expect(tour.line, hasLength(3));
    expect(RiderTour.fromJson({'stops': [], 'polyline': null}).line, isNull);
  });
}
