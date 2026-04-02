import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/campaigns_screen.dart';

void main() {
  runApp(const ProviderScope(child: Omni360App()));
}

const kAccent = Color(0xFF1565C0); // OmniBuy dark blue
const kAccentLight = Color(0xFFE3F2FD);
const kBg = Color(0xFFF5F7FA);
const kSidebar = Colors.white;
const kBorder = Color(0xFFE0E0E0);
const kTextPrimary = Color(0xFF1A1A2E);
const kTextSecondary = Color(0xFF757575);

class Omni360App extends StatelessWidget {
  const Omni360App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OmniBuy DSP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: kAccent,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: kBg,
        fontFamily: 'sans-serif',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: kTextPrimary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return switch (auth.status) {
      AuthStatus.authenticated => const CampaignsScreen(),
      AuthStatus.unauthenticated => const LoginScreen(),
      AuthStatus.unknown => const Scaffold(
          body: Center(child: CircularProgressIndicator(color: kAccent)),
        ),
    };
  }
}
