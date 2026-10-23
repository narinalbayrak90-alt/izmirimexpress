import 'api_client.dart';

/// A single in-app notification (project.txt Module 13) — every push
/// `OneSignalService::notifyCustomer` sent this customer, persisted
/// server-side so it still shows up here even if the push itself never
/// landed on the device (no OneSignal configured, notification permission
/// denied, etc.).
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    this.orderId,
    required this.createdAt,
  });

  final int id;
  final String title;
  final String body;
  final int? orderId;
  final DateTime createdAt;

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>?;
    return NotificationItem(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      orderId: data?['order_id'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// One page of `GET /notifications`, as Laravel's paginator serializes it —
/// mirrors `WalletHistoryPage`'s shape for the same infinite-scroll pattern.
class NotificationPage {
  const NotificationPage({required this.items, required this.currentPage, required this.lastPage});

  final List<NotificationItem> items;
  final int currentPage;
  final int lastPage;

  bool get hasMore => currentPage < lastPage;

  factory NotificationPage.fromJson(Map<String, dynamic> json) {
    return NotificationPage(
      items: (json['data'] as List).map((e) => NotificationItem.fromJson(e as Map<String, dynamic>)).toList(),
      currentPage: json['current_page'] as int,
      lastPage: json['last_page'] as int,
    );
  }
}

/// Talks to the customer's `GET /notifications` (project.txt Module 13).
/// Requires auth — only ever called once the customer is logged in.
class NotificationService {
  NotificationService(this._apiClient);

  final ApiClient _apiClient;

  /// Notification history, 10 per page — the backend keeps only the
  /// customer's most recent 50 rows, so this never goes past page 5.
  Future<NotificationPage> getNotifications({required int page}) async {
    final data = await _apiClient.get('/notifications', queryParameters: {'page': page});
    return NotificationPage.fromJson(data as Map<String, dynamic>);
  }
}
