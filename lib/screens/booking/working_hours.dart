/// Admin-configured open/close window for a single weekday.
class DayHours {
  const DayHours({required this.closed, required this.open, required this.close});

  final bool closed;
  final String open; // "HH:mm"
  final String close; // "HH:mm"

  factory DayHours.fromJson(Map<String, dynamic> json) {
    return DayHours(
      closed: json['closed'] as bool? ?? false,
      open: json['open'] as String? ?? '00:00',
      close: json['close'] as String? ?? '23:59',
    );
  }

  int get openMinutes => _toMinutes(open);
  int get closeMinutes => _toMinutes(close);

  static int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}

/// Admin-configured working hours (`GET /settings/working-hours`), used to
/// constrain the "Schedule for Later" date/time pickers on the Pickup step
/// (project.txt Module 5: "scheduled time must be within admin-configured
/// allowed window").
class WorkingHours {
  const WorkingHours({required this.days, required this.operationsSuspended});

  final Map<String, DayHours> days;
  final bool operationsSuspended;

  static const _weekdayNames = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  factory WorkingHours.fromJson(Map<String, dynamic> json) {
    final daysJson = json['days'] as Map<String, dynamic>? ?? {};
    return WorkingHours(
      days: daysJson.map((key, value) => MapEntry(key, DayHours.fromJson(value as Map<String, dynamic>))),
      operationsSuspended: json['operations_suspended'] as bool? ?? false,
    );
  }

  /// Hours for the given date's weekday, or null if unknown (treat as
  /// unrestricted rather than blocking scheduling).
  DayHours? forDate(DateTime date) => days[_weekdayNames[date.weekday - 1]];
}
