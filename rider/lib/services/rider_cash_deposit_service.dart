import 'api_client.dart';
import 'rider_order_service.dart';

/// The company account riders can send COD cash to — admin-configured
/// (App Setting > Order Setting). Null from the backend when no IBAN is
/// set, which hides the IBAN option.
class DepositIban {
  const DepositIban({required this.iban, this.accountHolder, this.bankName});

  final String iban;
  final String? accountHolder;
  final String? bankName;

  factory DepositIban.fromJson(Map<String, dynamic> json) {
    return DepositIban(
      iban: json['iban'] as String,
      accountHolder: json['account_holder'] as String?,
      bankName: json['bank_name'] as String?,
    );
  }
}

/// `GET /rider/cash-deposits` — what the IBAN payment dialog needs.
class CashDepositInfo {
  const CashDepositInfo({
    required this.cashInHand,
    required this.pendingDeposits,
    required this.iban,
    required this.deposits,
  });

  final double cashInHand;

  /// IBAN transfers reported but not yet approved by the office.
  final double pendingDeposits;
  final DepositIban? iban;
  final List<RiderCashDeposit> deposits;

  /// What can still be reported without double-counting pending ones.
  double get reportable => (cashInHand - pendingDeposits).clamp(0, double.infinity).toDouble();

  factory CashDepositInfo.fromJson(Map<String, dynamic> json) {
    final iban = json['iban'];
    return CashDepositInfo(
      cashInHand: (json['cash_in_hand'] as num).toDouble(),
      pendingDeposits: (json['pending_deposits'] as num?)?.toDouble() ?? 0,
      iban: iban is Map<String, dynamic> ? DepositIban.fromJson(iban) : null,
      deposits: ((json['deposits'] as List?) ?? const [])
          .map((row) => RiderCashDeposit.fromJson(row as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Talks to the `/rider/cash-deposits` endpoints: the company IBAN and the
/// rider's "I sent the cash" report, which the office then approves.
class RiderCashDepositService {
  RiderCashDepositService(this._apiClient);

  final ApiClient _apiClient;

  Future<CashDepositInfo> info() async {
    final data = await _apiClient.get('/rider/cash-deposits');
    return CashDepositInfo.fromJson(data as Map<String, dynamic>);
  }

  /// Reports an IBAN transfer of [amount]. The backend caps it at the cash
  /// still in hand minus pending reports and rejects via [ApiException]
  /// otherwise.
  Future<void> reportIbanTransfer(double amount, {String? note}) {
    return _apiClient.post('/rider/cash-deposits', data: {
      'amount': amount,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }
}
