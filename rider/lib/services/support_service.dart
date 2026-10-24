import 'api_client.dart';

/// Admin's support contact details, from `GET /support/contact` (App
/// Setting > App Contact Us) — the same public endpoint the User App
/// reads, since this isn't rider-specific data.
class SupportContactInfo {
  const SupportContactInfo({this.email, this.phone, this.whatsapp});

  final String? email;
  final String? phone;
  final String? whatsapp;

  factory SupportContactInfo.fromJson(Map<String, dynamic> json) {
    return SupportContactInfo(
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      whatsapp: json['whatsapp'] as String?,
    );
  }
}

/// Talks to the public `/support/contact` endpoints backing the Help &
/// Support screen — shared with the User App, since neither the contact
/// details nor the contact-form mailer care which app sent them (see
/// SupportController on the backend).
class SupportService {
  SupportService(this._apiClient);

  final ApiClient _apiClient;

  Future<SupportContactInfo> contactInfo() async {
    final data = await _apiClient.get('/support/contact');
    return SupportContactInfo.fromJson(data as Map<String, dynamic>);
  }

  /// Emails the admin's configured contact address. `source: 'rider_app'`
  /// is tagged on every submission so the admin can tell a rider's
  /// message apart from a customer's (see ContactUsRequest/
  /// SupportController::sendContactForm's doc comments on the backend).
  Future<void> sendContactForm({required String name, required String email, required String message}) {
    return _apiClient.post('/support/contact', data: {
      'name': name,
      'email': email,
      'message': message,
      'source': 'rider_app',
    });
  }
}
