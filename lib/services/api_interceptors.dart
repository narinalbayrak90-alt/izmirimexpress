import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';

import 'api_exception.dart';
import 'secure_storage_service.dart';

/// Attaches the stored bearer token (if any) to every outgoing request.
///
/// Public endpoints simply ignore the header when there's no matching
/// `auth:sanctum` (or equivalent) middleware, so it's safe to always attach
/// it rather than tracking per-request auth requirements here.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._secureStorage);

  final SecureStorageService _secureStorage;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _secureStorage.readToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}

/// Normalizes every Dio failure into an [ApiException] so the rest of the
/// app never has to branch on Dio's exception types or guess at the shape
/// of the backend's error payload.
///
/// Handles three cases, in order:
/// 1. The backend's own envelope: `{success: false, message, errors}`.
/// 2. Laravel's default validation-failure shape (no `success` key):
///    `{message, errors}` — can leak through on requests that fail a Form
///    Request's validation before reaching a controller using ApiResponse.
/// 3. Transport-level failures with no parseable body (timeout, no
///    connection, etc.) — mapped to a generic message keyed off [DioExceptionType].
class ApiErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final data = err.response?.data;
    final statusCode = err.response?.statusCode;

    if (data is Map<String, dynamic> && data.containsKey('message')) {
      handler.next(
        err.copyWith(
          error: ApiException(
            message: data['message'] as String? ?? 'common.unexpected_error'.tr(),
            errors: data['errors'],
            statusCode: statusCode,
          ),
        ),
      );
      return;
    }

    handler.next(
      err.copyWith(error: ApiException(message: _fallbackMessage(err.type), statusCode: statusCode)),
    );
  }

  String _fallbackMessage(DioExceptionType type) {
    switch (type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return 'common.request_timeout'.tr();
      case DioExceptionType.connectionError:
        return 'common.no_internet'.tr();
      case DioExceptionType.cancel:
        return 'common.request_cancelled'.tr();
      case DioExceptionType.badCertificate:
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return 'common.unexpected_error'.tr();
    }
  }
}
