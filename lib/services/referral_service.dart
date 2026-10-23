import 'api_client.dart';

/// The logged-in customer's referral info (project.txt Module 14 — Invite
/// & Earn), from `GET /referral/info`. [referralCode] is null until the
/// customer's first order is delivered.
class ReferralInfo {
  const ReferralInfo({
    required this.enabled,
    this.referralCode,
    required this.referrerReward,
    required this.refereeReward,
    required this.totalReferrals,
  });

  final bool enabled;
  final String? referralCode;
  final double referrerReward;
  final double refereeReward;
  final int totalReferrals;

  factory ReferralInfo.fromJson(Map<String, dynamic> json) {
    return ReferralInfo(
      enabled: json['enabled'] as bool? ?? false,
      referralCode: json['referral_code'] as String?,
      referrerReward: (json['referrer_reward'] as num?)?.toDouble() ?? 0,
      refereeReward: (json['referee_reward'] as num?)?.toDouble() ?? 0,
      totalReferrals: json['total_referrals'] as int? ?? 0,
    );
  }
}

/// Talks to `GET /referral/info`.
class ReferralService {
  ReferralService(this._apiClient);

  final ApiClient _apiClient;

  Future<ReferralInfo> getInfo() async {
    final data = await _apiClient.get('/referral/info');
    return ReferralInfo.fromJson(data as Map<String, dynamic>);
  }
}
