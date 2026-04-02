import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(authProvider.notifier)
        .login(_emailCtrl.text.trim(), _passCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isLoading = auth.status == AuthStatus.unknown;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    // Logo
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: kAccent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.bar_chart_rounded,
                            color: Colors.white, size: 36),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Center(
                      child: Text(
                        'OmniBuy',
                        style: TextStyle(
                          color: kTextPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Center(
                      child: Text(
                        'Статистика кампаний',
                        style: TextStyle(
                            color: kTextSecondary, fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 40),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(fontSize: 15),
                      decoration: _inputDecoration('Email', Icons.email_outlined),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Введите email'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      style: const TextStyle(fontSize: 15),
                      decoration:
                          _inputDecoration('Пароль', Icons.lock_outline)
                              .copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: kTextSecondary,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 4)
                          ? 'Введите пароль'
                          : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (auth.error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          auth.error!,
                          style: const TextStyle(
                              color: Color(0xFFC62828), fontSize: 13),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: isLoading ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: kAccent,
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Войти',
                              style: TextStyle(
                                  fontSize: 16, color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: kTextSecondary),
        prefixIcon: Icon(icon, color: kTextSecondary, size: 20),
        filled: true,
        fillColor: kBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      );
}
