import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';

import 'api_exception.dart';

/// Thin wrapper around [Dio] that unwraps the backend's `{success, message,
/// data}` envelope and rethrows failures as [ApiException].
///
/// Deliberately returns `dynamic` rather than typed models — parsing a
/// specific endpoint's `data` shape (Category, User, Order, ...) is the
/// responsibility of that feature's own repository, not this shared client.
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) {
    return _request(() => _dio.get(path, queryParameters: queryParameters));
  }

  Future<dynamic> post(String path, {dynamic data}) {
    return _request(() => _dio.post(path, data: data));
  }

  Future<dynamic> put(String path, {dynamic data}) {
    return _request(() => _dio.put(path, data: data));
  }

  Future<dynamic> delete(String path, {dynamic data}) {
    return _request(() => _dio.delete(path, data: data));
  }

  Future<dynamic> _request(Future<Response> Function() call) async {
    try {
      final response = await call();
      final body = response.data;
      // Every endpoint answers with the JSON envelope; anything else (an
      // HTML error or maintenance page from the host) is a failed request,
      // not data for the caller to choke on.
      if (body is! Map<String, dynamic>) {
        throw ApiException(message: 'common.unexpected_error'.tr(), statusCode: response.statusCode);
      }
      return body['data'];
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiException) throw error;
      throw ApiException(message: 'common.unexpected_error'.tr());
    }
  }
}
