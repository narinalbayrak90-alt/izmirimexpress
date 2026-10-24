import 'package:dio/dio.dart';

import 'api_client.dart';

/// The rider's own profile, returned by `POST /rider/auth/register`,
/// `POST /rider/auth/login`, and `GET /rider/me`.
///
/// `status` is one of pending/approved/rejected/blocked — a freshly
/// registered rider is always `pending` and can't sign in yet (see
/// [RiderAuthService.register]'s doc comment).
class RiderProfile {
  const RiderProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.status,
    required this.isOnline,
    required this.vehicleType,
    this.vehicleNumber,
    this.iban,
    this.ibanHolder,
    required this.ratingAvg,
    this.photoUrl,
    this.drivingLicenseUrl,
    this.idProofUrl,
    required this.totalDeliveries,
  });

  final int id;
  final String name;
  final String email;
  final String phone;
  final String status;
  final bool isOnline;
  final String vehicleType;
  final String? vehicleNumber;

  /// Payout account for withdrawals (TR IBAN, no spaces) and its holder.
  final String? iban;
  final String? ibanHolder;
  final double ratingAvg;
  final String? photoUrl;
  final String? drivingLicenseUrl;
  final String? idProofUrl;
  final int totalDeliveries;

  /// [status] as a typed value — see [RiderVerificationStatus]. A rider
  /// the app has a token for is always [RiderVerificationStatus.approved]
  /// (the backend's `rider` middleware blocks the rest on every request),
  /// but this stays honest to whatever the server last reported.
  RiderVerificationStatus get verificationStatus => RiderVerificationStatus.parse(status);

  factory RiderProfile.fromJson(Map<String, dynamic> json) {
    return RiderProfile(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      isOnline: json['is_online'] as bool? ?? false,
      vehicleType: json['vehicle_type'] as String? ?? '',
      vehicleNumber: json['vehicle_number'] as String?,
      iban: json['iban'] as String?,
      ibanHolder: json['iban_holder'] as String?,
      ratingAvg: (json['rating_avg'] as num?)?.toDouble() ?? 0,
      photoUrl: json['photo'] as String?,
      drivingLicenseUrl: json['driving_license'] as String?,
      idProofUrl: json['id_proof'] as String?,
      totalDeliveries: json['total_deliveries'] as int? ?? 0,
    );
  }
}

/// The four values `riders.status` can hold on the backend. A rider can
/// only sign in once they're [approved]; the other three are what
/// [RiderAuthService.checkStatus] exists to surface.
enum RiderVerificationStatus {
  pending,
  approved,
  rejected,
  blocked;

  static RiderVerificationStatus parse(String? raw) {
    return RiderVerificationStatus.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => RiderVerificationStatus.pending,
    );
  }

  bool get isApproved => this == RiderVerificationStatus.approved;
}

/// Result of `POST /rider/auth/status` — the rider's current verification
/// standing, without a token (see RiderAuthController::status). Lets a
/// rider who can't sign in yet still see whether their application is
/// under review, approved, rejected, or blocked.
class RiderStatusResult {
  const RiderStatusResult({required this.status, required this.name});

  final RiderVerificationStatus status;
  final String name;

  factory RiderStatusResult.fromJson(Map<String, dynamic> json) {
    return RiderStatusResult(
      status: RiderVerificationStatus.parse(json['status'] as String?),
      name: json['name'] as String? ?? '',
    );
  }
}

/// Result of `POST /rider/auth/login` or `POST /rider/auth/reset-password`
/// — [token] is null whenever the account isn't `approved` (see
/// [RiderProfile.status]): a reset can succeed and still not be enough to
/// sign in with, if the account is still pending/rejected/blocked.
class RiderAuthResult {
  const RiderAuthResult({required this.rider, required this.token});

  final RiderProfile rider;
  final String? token;

  factory RiderAuthResult.fromJson(Map<String, dynamic> json) {
    return RiderAuthResult(
      rider: RiderProfile.fromJson(json['rider'] as Map<String, dynamic>),
      token: json['token'] as String?,
    );
  }
}

/// Talks to the `POST /rider/auth/*` endpoints backing signup, login, and
/// password reset. Unlike the User App there's no OTP step at signup — the
/// gate between signup and being able to sign in is admin approval (see
/// [register]'s doc comment); OTP only shows up here for [forgotPassword]/
/// [resetPassword].
class RiderAuthService {
  RiderAuthService(this._apiClient);

  final ApiClient _apiClient;

  /// Rider App signup. Returns the created (still-pending) profile — never
  /// a token, since a brand-new rider can't sign in until an admin
  /// approves their account from the Delivery Staff list (see
  /// RiderAuthController::register on the backend). The caller should show
  /// a "submitted, wait for approval" state rather than treating this like
  /// a login.
  Future<RiderProfile> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String vehicleType,
    String? vehicleNumber,
    String? iban,
    String? ibanHolder,
    String? photoPath,
    String? drivingLicensePath,
    String? idProofPath,
  }) async {
    final data = FormData.fromMap({
      'name': name,
      'email': email,
      'phone': phone,
      'password': password,
      if (iban != null && iban.isNotEmpty) 'iban': iban,
      if (ibanHolder != null && ibanHolder.isNotEmpty) 'iban_holder': ibanHolder,
      'vehicle_type': vehicleType,
      if (vehicleNumber != null && vehicleNumber.isNotEmpty) 'vehicle_number': vehicleNumber,
      if (photoPath != null) 'photo': await MultipartFile.fromFile(photoPath),
      if (drivingLicensePath != null) 'driving_license': await MultipartFile.fromFile(drivingLicensePath),
      if (idProofPath != null) 'id_proof': await MultipartFile.fromFile(idProofPath),
    });

    final result = await _apiClient.post('/rider/auth/register', data: data);
    return RiderProfile.fromJson(result as Map<String, dynamic>);
  }

  /// Rejects (via [ApiException], see ApiErrorInterceptor) with the
  /// backend's specific pending/rejected/blocked message for anything
  /// other than an approved rider — never returns a null [token].
  Future<RiderAuthResult> login({required String identifier, required String password}) async {
    final data = await _apiClient.post(
      '/rider/auth/login',
      data: {'identifier': identifier, 'password': password},
    );
    return RiderAuthResult.fromJson(data as Map<String, dynamic>);
  }

  /// Checks the rider's verification status by the same email/phone +
  /// password [login] takes — but returns the pending/approved/rejected/
  /// blocked status instead of a token, so a rider whose account isn't
  /// approved yet can still see where their application stands. A wrong
  /// credential rejects (via [ApiException]) exactly like [login].
  Future<RiderStatusResult> checkStatus({required String identifier, required String password}) async {
    final data = await _apiClient.post(
      '/rider/auth/status',
      data: {'identifier': identifier, 'password': password},
    );
    return RiderStatusResult.fromJson(data as Map<String, dynamic>);
  }

  /// Always delivers the OTP over email, regardless of what [identifier]
  /// was (see RiderAuthController::forgotPassword on the backend). Returns
  /// the rider id to hand to [resetPassword].
  Future<int> forgotPassword({required String identifier}) async {
    final data = await _apiClient.post('/rider/auth/forgot-password', data: {'identifier': identifier});
    return (data as Map<String, dynamic>)['rider_id'] as int;
  }

  /// Verifies the reset OTP and sets the new password in one step. Unlike
  /// the User App's equivalent, this can succeed with a null [RiderAuthResult.token]
  /// — see that class's doc comment.
  Future<RiderAuthResult> resetPassword({required int riderId, required String code, required String password}) async {
    final data = await _apiClient.post(
      '/rider/auth/reset-password',
      data: {'rider_id': riderId, 'code': code, 'password': password},
    );
    return RiderAuthResult.fromJson(data as Map<String, dynamic>);
  }

  Future<RiderProfile> me() async {
    final data = await _apiClient.get('/rider/me');
    return RiderProfile.fromJson(data as Map<String, dynamic>);
  }

  /// Flips the rider's availability for new order offers — going online is
  /// also what makes [OneSignalService.notifyOrderAvailable] (backend)
  /// include this device in the push broadcast for a matching order, so
  /// callers should pair this with starting/stopping the location
  /// heartbeat (see RiderLocationTracker).
  Future<RiderProfile> updateAvailability(bool isOnline) async {
    final data = await _apiClient.post('/rider/me/availability', data: {'is_online': isOnline});
    return RiderProfile.fromJson(data as Map<String, dynamic>);
  }

  /// Reports the rider's live position — read back by the User App's own
  /// order-tracking screen, and what keeps `GET /rider/orders/available`'s
  /// distance sort accurate.
  Future<void> updateLocation({required double lat, required double lng}) {
    return _apiClient.post('/rider/me/location', data: {'lat': lat, 'lng': lng});
  }

  /// Revokes the token server-side. Callers should still clear the locally
  /// stored token afterwards regardless of whether this succeeds (a failed
  /// revoke — e.g. offline — shouldn't leave the rider stuck logged in).
  Future<void> logout() {
    return _apiClient.post('/rider/auth/logout');
  }

  /// Edits the logged-in rider's own profile — name/contact/vehicle,
  /// always required, plus an optional password change ([currentPassword]/
  /// [newPassword], both needed together or not at all) and optional
  /// re-upload of the photo or either verification document. See
  /// RiderAuthController::update on the backend for the full field list.
  Future<RiderProfile> update({
    required String name,
    required String email,
    required String phone,
    required String vehicleType,
    String? vehicleNumber,
    String? currentPassword,
    String? newPassword,
    String? photoPath,
    String? drivingLicensePath,
    String? idProofPath,
  }) async {
    final data = FormData.fromMap({
      'name': name,
      'email': email,
      'phone': phone,
      'vehicle_type': vehicleType,
      if (vehicleNumber != null && vehicleNumber.isNotEmpty) 'vehicle_number': vehicleNumber,
      if (currentPassword != null && currentPassword.isNotEmpty) 'current_password': currentPassword,
      if (newPassword != null && newPassword.isNotEmpty) 'new_password': newPassword,
      if (photoPath != null) 'photo': await MultipartFile.fromFile(photoPath),
      if (drivingLicensePath != null) 'driving_license': await MultipartFile.fromFile(drivingLicensePath),
      if (idProofPath != null) 'id_proof': await MultipartFile.fromFile(idProofPath),
    });

    final result = await _apiClient.post('/rider/me/update', data: data);
    return RiderProfile.fromJson(result as Map<String, dynamic>);
  }

  /// Saves the payout IBAN (POST /rider/me/iban); returns the updated profile.
  Future<RiderProfile> updateIban({required String iban, required String holder}) async {
    final result = await _apiClient.post('/rider/me/iban', data: {'iban': iban, 'iban_holder': holder});
    return RiderProfile.fromJson(result as Map<String, dynamic>);
  }

  /// Permanently disables the account — see RiderAuthController::
  /// deleteAccount on the backend for the anonymize-then-soft-delete
  /// behavior. Rejects (via [ApiException]) with "The password you
  /// entered is incorrect." if [currentPassword] doesn't match; callers
  /// still need to clear the local token/session themselves afterwards,
  /// same as [logout].
  Future<void> deleteAccount({required String currentPassword}) {
    return _apiClient.delete('/rider/me', data: {'current_password': currentPassword});
  }
}
