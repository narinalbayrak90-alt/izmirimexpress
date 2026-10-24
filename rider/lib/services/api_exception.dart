/// Uniform error type surfaced to callers of [ApiClient] regardless of
/// whether the failure came from the backend's `{success:false, ...}`
/// envelope, Laravel's default validation-error shape, or a transport-level
/// problem (timeout, no connection).
class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.errors,
    this.statusCode,
  });

  final String message;

  /// Field-level validation errors, if any (Laravel's `errors` map shape).
  final dynamic errors;

  final int? statusCode;

  @override
  String toString() => message;
}
