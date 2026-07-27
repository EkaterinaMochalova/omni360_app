import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? error;
  final String? email;

  const AuthState({required this.status, this.error, this.email});

  AuthState copyWith({AuthStatus? status, String? error, String? email}) =>
      AuthState(
        status: status ?? this.status,
        error: error,
        email: email ?? this.email,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final _service = AuthService();

  AuthNotifier() : super(const AuthState(status: AuthStatus.unknown)) {
    _checkToken();
  }

  Future<void> _checkToken() async {
    final loggedIn = await _service.isLoggedIn();
    final savedEmail = loggedIn ? await _service.getSavedEmail() : null;
    state = AuthState(
      status: loggedIn ? AuthStatus.authenticated : AuthStatus.unauthenticated,
      email: savedEmail,
    );
  }

  Future<void> login(String email, String password) async {
    state = const AuthState(status: AuthStatus.unknown);
    try {
      await _service.login(email, password);
      state = AuthState(status: AuthStatus.authenticated, email: email);
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
