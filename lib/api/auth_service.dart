import 'package:dio/dio.dart';
import 'omni360_client.dart';

class AuthService {
  final _client = Omni360Client();

  /// Returns JWT token on success. Throws [DioException] on failure.
  Future<String> login(String email, String password) async {
    final response = await _client.dio.post(
      '/api/login',
      data: {'email': email, 'password': password},
    );
    // The API returns a token field — adjust the key if the actual response differs
    final token = response.data['token'] as String?
        ?? response.data['accessToken'] as String?
        ?? response.data['access_token'] as String?;
    if (token == null) {
      throw Exception('Login response did not contain a token');
    }
    await _client.saveToken(token);
    return token;
  }

  Future<void> logout() async {
    try {
      await _client.dio.post('/api/logout');
    } catch (_) {
      // Ignore errors on logout — always clear local token
    } finally {
      await _client.deleteToken();
    }
  }

  Future<bool> isLoggedIn() async {
    final token = await _client.getToken();
    return token != null && token.isNotEmpty;
  }
}
