import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _baseUrl = 'https://proddsp.omniboard360.io';
const _tokenKey = 'auth_token';

class Omni360Client {
  static final Omni360Client _instance = Omni360Client._internal();
  factory Omni360Client() => _instance;

  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  Omni360Client._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          _rewriteAnalyticsRequestForNetlify(options);
          final token = await _storage.read(key: _tokenKey);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (error, handler) {
          // 401 will be handled by providers/screens
          return handler.next(error);
        },
      ),
    );
  }

  Dio get dio => _dio;

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<void> deleteToken() => _storage.delete(key: _tokenKey);

  static void _rewriteAnalyticsRequestForNetlify(RequestOptions options) {
    if (!kIsWeb || !_shouldUseNetlifyProxy(Uri.base.host)) {
      return;
    }

    final path = options.path;
    final isAuctionAnalyticsRequest =
        path.contains('/api/v1.0/clients/campaigns/') &&
        (path.endsWith('/filters-list') || path.endsWith('/impressions'));

    if (!isAuctionAnalyticsRequest) {
      return;
    }

    options.baseUrl = Uri.base.origin;
    options.path = '/api-proxy$path';
  }

  static bool _shouldUseNetlifyProxy(String host) {
    return host.endsWith('.netlify.app') || host.contains('netlify');
  }
}
