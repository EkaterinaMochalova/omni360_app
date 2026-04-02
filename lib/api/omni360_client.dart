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
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
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
    ));
  }

  Dio get dio => _dio;

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<void> deleteToken() => _storage.delete(key: _tokenKey);
}
