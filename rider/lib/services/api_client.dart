import 'package:dio/dio.dart';

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
      return body is Map<String, dynamic> ? body['data'] : body;
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiException) throw error;
      throw const ApiException(message: 'Something went wrong. Please try again.');
    }
  }
}
