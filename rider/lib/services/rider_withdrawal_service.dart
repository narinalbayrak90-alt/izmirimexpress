import 'api_client.dart';

/// One payout request — from `GET /rider/withdrawals`'s `requests` list.
/// [status] is `pending`/`approved`/`declined`; [note] is the admin's
/// reason, set when the request is reviewed (always present on a decline,
/// optional on an approval — see RiderWithdrawalStatusRequest on the
/// backend).
class RiderWithdrawal {
  const RiderWithdrawal({
    required this.id,
    required this.amount,
    required this.status,
    this.note,
    required this.createdAt,
  });

  final int id;
  final double amount;
  final String status;
  final String? note;
  final DateTime createdAt;

  factory RiderWithdrawal.fromJson(Map<String, dynamic> json) {
    return RiderWithdrawal(
      id: json['id'] as int,
      amount: (json['amount'] as num).toDouble(),
      status: json['status'] as String,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// `GET /rider/withdrawals`'s full response — what the Earning tab needs
/// to show the Withdraw button's limit and a status history in one call.
class RiderWithdrawalSummary {
  const RiderWithdrawalSummary({required this.availableBalance, required this.requests, this.cashInHand = 0});

  final double availableBalance;
  final List<RiderWithdrawal> requests;

  /// COD cash not yet handed over at the office; withdrawals stay closed
  /// while it's above zero (enforced by the backend too).
  final double cashInHand;

  factory RiderWithdrawalSummary.fromJson(Map<String, dynamic> json) {
    final rows = (json['requests'] as Map<String, dynamic>)['data'] as List;

    return RiderWithdrawalSummary(
      availableBalance: (json['available_balance'] as num).toDouble(),
      cashInHand: (json['cash_in_hand'] as num?)?.toDouble() ?? 0,
      requests: rows.map((row) => RiderWithdrawal.fromJson(row as Map<String, dynamic>)).toList(),
    );
  }
}

/// Talks to the `/rider/withdrawals` endpoints backing the Earning tab's
/// Withdraw action.
class RiderWithdrawalService {
  RiderWithdrawalService(this._apiClient);

  final ApiClient _apiClient;

  Future<RiderWithdrawalSummary> summary() async {
    final data = await _apiClient.get('/rider/withdrawals');
    return RiderWithdrawalSummary.fromJson(data as Map<String, dynamic>);
  }

  /// Submits a new payout request. The backend is the source of truth on
  /// whether [amount] fits the rider's current available balance —
  /// rejects (via [ApiException], see ApiErrorInterceptor) if it doesn't,
  /// even if the caller already did its own balance check against a
  /// possibly-stale [RiderWithdrawalSummary.availableBalance].
  Future<void> request(double amount) {
    return _apiClient.post('/rider/withdrawals', data: {'amount': amount});
  }
}
