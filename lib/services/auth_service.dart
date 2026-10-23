import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import 'api_client.dart';

/// Result of `POST /auth/register` or `POST /auth/login` — either a
/// ready-to-use [token] (no verification pending) or a [customerId] to
/// hand to `POST /auth/verify-otp` (project.txt Module 2's
/// admin-configurable None/SMS/WhatsApp/Email verification step).
class AuthResult {
  const AuthResult({
    required this.customerId,
    required this.token,
    required this.requiresVerification,
    this.verificationChannel,
  });

  final int customerId;
  final String? token;
  final bool requiresVerification;
  final String? verificationChannel;

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      customerId: (json['customer'] as Map<String, dynamic>)['id'] as int,
      token: json['token'] as String?,
      requiresVerification: json['requires_verification'] as bool? ?? false,
      verificationChannel: json['verification_channel'] as String?,
    );
  }
}

/// The logged-in customer's own profile, from `GET /me` (project.txt
/// Module 14 — Account screen).
class CustomerProfile {
  const CustomerProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.countryCode,
    required this.phone,
    this.photoUrl,
    required this.walletBalance,
    required this.isVerified,
    required this.totalDeliveries,
    required this.activeOrders,
  });

  final int id;
  final String name;
  final String email;
  final String countryCode;
  final String phone;
  final String? photoUrl;
  final double walletBalance;
  final bool isVerified;
  final int totalDeliveries;
  final int activeOrders;

  factory CustomerProfile.fromJson(Map<String, dynamic> json) {
    return CustomerProfile(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      countryCode: json['country_code'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      photoUrl: json['photo'] as String?,
      walletBalance: (json['wallet_balance'] as num?)?.toDouble() ?? 0,
      isVerified: json['is_verified'] as bool? ?? false,
      totalDeliveries: json['total_deliveries'] as int? ?? 0,
      activeOrders: json['active_orders'] as int? ?? 0,
    );
  }
}

/// Talks to the `POST /auth/*` endpoints backing signup, login, and
/// password reset (project.txt Module 2), plus the logged-in customer's
/// own profile and logout.
class AuthService {
  AuthService(this._apiClient);

  final ApiClient _apiClient;

  Future<AuthResult> register({
    required String name,
    required String email,
    required String countryCode,
    required String phone,
    required String password,
  }) async {
    final data = await _apiClient.post(
      '/auth/register',
      data: {
        'name': name,
        'email': email,
        'country_code': countryCode,
        'phone': phone,
        'password': password,
      },
    );
    return AuthResult.fromJson(data as Map<String, dynamic>);
  }

  Future<AuthResult> login({required String identifier, required String password}) async {
    final data = await _apiClient.post(
      '/auth/login',
      data: {'identifier': identifier, 'password': password},
    );
    return AuthResult.fromJson(data as Map<String, dynamic>);
  }

  /// Returns the auth token on success.
  Future<String> verifyOtp({required int customerId, required String code}) async {
    final data = await _apiClient.post(
      '/auth/verify-otp',
      data: {'customer_id': customerId, 'code': code},
    );
    return (data as Map<String, dynamic>)['token'] as String;
  }

  /// [purpose] controls which channel the backend resends over: a "reset"
  /// OTP always goes out over email (always available), a "signup" one
  /// follows the admin's `signup_verification` setting.
  Future<void> resendOtp({required int customerId, String purpose = 'signup'}) {
    return _apiClient.post('/auth/resend-otp', data: {'customer_id': customerId, 'purpose': purpose});
  }

  /// Returns the customer id to hand to [resetPassword]/[verifyOtp]'s OTP
  /// screen.
  Future<int> forgotPassword({required String identifier}) async {
    final data = await _apiClient.post('/auth/forgot-password', data: {'identifier': identifier});
    return (data as Map<String, dynamic>)['customer_id'] as int;
  }

  /// Verifies the reset OTP and sets the new password in one step. Returns
  /// the auth token — successfully resetting logs the customer in.
  Future<String> resetPassword({required int customerId, required String code, required String password}) async {
    final data = await _apiClient.post(
      '/auth/reset-password',
      data: {'customer_id': customerId, 'code': code, 'password': password},
    );
    return (data as Map<String, dynamic>)['token'] as String;
  }

  Future<CustomerProfile> getProfile() async {
    final data = await _apiClient.get('/me');
    return CustomerProfile.fromJson(data as Map<String, dynamic>);
  }

  /// Edits the logged-in customer's own profile (project.txt Module 14 —
  /// Personal Information): the same fields collected at signup, plus an
  /// optional password change ([currentPassword]/[newPassword], both or
  /// neither) and an optional new [photo] to upload.
  Future<CustomerProfile> updateProfile({
    required String name,
    required String email,
    required String countryCode,
    required String phone,
    String? currentPassword,
    String? newPassword,
    XFile? photo,
  }) async {
    final data = FormData.fromMap({
      'name': name,
      'email': email,
      'country_code': countryCode,
      'phone': phone,
      if (currentPassword != null && currentPassword.isNotEmpty) 'current_password': currentPassword,
      if (newPassword != null && newPassword.isNotEmpty) 'new_password': newPassword,
      if (photo != null) 'photo': MultipartFile.fromBytes(await photo.readAsBytes(), filename: photo.name),
    });
    final result = await _apiClient.post('/me/update', data: data);
    return CustomerProfile.fromJson(result as Map<String, dynamic>);
  }

  /// Revokes the token server-side. Callers should still clear the locally
  /// stored token afterwards regardless of whether this succeeds (a failed
  /// revoke — e.g. offline — shouldn't leave the customer stuck logged in).
  Future<void> logout() {
    return _apiClient.post('/auth/logout');
  }

  /// Deletes the account (project.txt Module 14 — required by app store
  /// policies) — requires the current password so a stolen/left-open
  /// session can't destroy the account on its own. Unlike [logout],
  /// callers should only clear the local token once this actually
  /// succeeds — on failure the account still exists server-side, so
  /// silently dropping the token would misrepresent that as done.
  Future<void> deleteAccount({required String currentPassword}) {
    return _apiClient.delete('/me', data: {'current_password': currentPassword});
  }
}
