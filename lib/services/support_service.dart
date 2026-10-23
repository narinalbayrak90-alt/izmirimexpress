import 'api_client.dart';

/// The admin's support contact details (App Setting > App Contact Us),
/// from the public `GET /support/contact` — any field may be null if the
/// admin hasn't filled it in yet.
class SupportContactInfo {
  const SupportContactInfo({this.email, this.phone, this.whatsapp});

  final String? email;
  final String? phone;
  final String? whatsapp;

  bool get hasAnyContact =>
      (email != null && email!.isNotEmpty) || (phone != null && phone!.isNotEmpty) || (whatsapp != null && whatsapp!.isNotEmpty);

  factory SupportContactInfo.fromJson(Map<String, dynamic> json) {
    return SupportContactInfo(
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      whatsapp: json['whatsapp'] as String?,
    );
  }
}

/// Talks to the public `GET`/`POST /support/contact` endpoints
/// (project.txt Module 14 — Help & Support): the admin's contact details,
/// and the screen's own contact form, which the backend emails to the
/// admin's configured contact address.
class SupportService {
  SupportService(this._apiClient);

  final ApiClient _apiClient;

  Future<SupportContactInfo> getContactInfo() async {
    final data = await _apiClient.get('/support/contact');
    return SupportContactInfo.fromJson(data as Map<String, dynamic>);
  }

  Future<void> sendContactForm({required String name, required String email, required String message}) {
    return _apiClient.post('/support/contact', data: {'name': name, 'email': email, 'message': message});
  }
}
