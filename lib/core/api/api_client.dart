import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Central HTTP client.
/// - Attaches JWT Bearer token to every request.
/// - Auto-refreshes the token on 401 using the stored refresh token.
/// - Retries the original request once after a successful refresh.
class ApiClient {
  late final Dio _dio;
  final String baseUrl;
  final FlutterSecureStorage _storage;

  ApiClient({
    required this.baseUrl,
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );

    _dio.interceptors.addAll([
      _AuthInterceptor(_storage, _dio),
      LogInterceptor(requestBody: false, responseBody: false),
    ]);
  }

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) =>
      _dio.get(path, queryParameters: queryParameters);

  Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> patch(String path, {dynamic data}) =>
      _dio.patch(path, data: data);

  Future<Response> put(String path, {dynamic data}) =>
      _dio.put(path, data: data);
}

// ─── Auth Interceptor ────────────────────────────────────────────────────────

class _AuthInterceptor extends Interceptor {
  final FlutterSecureStorage _storage;
  final Dio _dio;
  bool _isRefreshing = false;

  _AuthInterceptor(this._storage, this._dio);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.read(key: 'access_token');
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refresh = await _storage.read(key: 'refresh_token');
        if (refresh == null) {
          handler.next(err);
          return;
        }
        final refreshDio = Dio(BaseOptions(baseUrl: _dio.options.baseUrl));
        final resp = await refreshDio.post(
          '/api/auth/refresh/',
          data: {'refresh': refresh},
        );
        final newAccess = resp.data['access'] as String;
        await _storage.write(key: 'access_token', value: newAccess);

        // Retry original request with new token
        final opts = err.requestOptions
          ..headers['Authorization'] = 'Bearer $newAccess';
        final retried = await _dio.fetch(opts);
        handler.resolve(retried);
      } catch (_) {
        // Refresh failed → let it fall through so router redirects to login
        handler.next(err);
      } finally {
        _isRefreshing = false;
      }
      return;
    }
    handler.next(err);
  }
}
