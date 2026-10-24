import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';

/// `GET /welcome`'s response — sourced from the same App Setting >
/// Welcome Page (Legal section) the User App reads, since none of this
/// is Rider-App-specific data. [image] is the only field the Welcome
/// screen itself uses (title/description are always static Rider-App
/// copy, see [WelcomeScreen]); [privacyPolicyUrl]/[termsUrl] are what the
/// signup screen's agree-to-terms checkbox links to.
class WelcomeInfo {
  const WelcomeInfo({this.image, this.privacyPolicyUrl, this.termsUrl});

  final String? image;
  final String? privacyPolicyUrl;
  final String? termsUrl;

  factory WelcomeInfo.fromJson(Map<String, dynamic> json) {
    String? nonEmpty(String? value) => (value == null || value.isEmpty) ? null : value;

    return WelcomeInfo(
      image: nonEmpty(json['image'] as String?),
      privacyPolicyUrl: nonEmpty(json['privacy_policy_url'] as String?),
      termsUrl: nonEmpty(json['terms_url'] as String?),
    );
  }
}

/// Fetched once and shared by [WelcomeScreen] and the signup screen —
/// both need the same `GET /welcome` response, so this avoids fetching
/// it twice back-to-back during the welcome-then-signup flow.
final welcomeInfoProvider = FutureProvider<WelcomeInfo>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/welcome');
  return WelcomeInfo.fromJson(data as Map<String, dynamic>);
});
