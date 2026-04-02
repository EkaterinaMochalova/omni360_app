import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? error;

  const AuthState({required this.status, this.error});

  AuthState copyWith({AuthStatus? status, String? error}) => AuthState(
        status: status ?? this.status,
        error: error,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final _service = AuthService();

  AuthNotifier() : super(const AuthState(status: AuthStatus.unknown)) {
    _checkToken();
  }

  Future<void> _checkToken() async {
    final loggedIn = await _service.isLoggedIn();
    state = AuthState(
      status: loggedIn ? AuthStatus.authenticated : AuthStatus.unauthenticated,
    );
  }

  Future<void> login(String email, String password) async {
    state = const AuthState(status: AuthStatus.unknown);
    try {
      await _service.login(email, password);
      state = const AuthState(status: AuthStatus.authenticated);
    } catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: _errorMessage(e),
      );
    }
  }

  Future<void> logout() async {
    await _service.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  String _errorMessage(Object e) {
    final msg = e.toString();
    if (msg.contains('401') || msg.contains('Unauthorized')) {
      return 'Неверный логин или пароль';
    }
    if (msg.contains('SocketException') || msg.contains('connection')) {
      return 'Нет соединения с сервером';
    }
    return 'Ошибка входа. Попробуйте ещё раз.';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (_) => AuthNotifier(),
);
