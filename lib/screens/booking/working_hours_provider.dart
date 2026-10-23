import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import 'working_hours.dart';

/// Fetches admin-configured working hours from `GET /settings/working-hours`.
final workingHoursProvider = FutureProvider<WorkingHours>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/settings/working-hours');
  return WorkingHours.fromJson(data as Map<String, dynamic>);
});
