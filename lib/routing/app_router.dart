import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_provider.dart';
import '../features/driver/screens/driver_home_screen.dart';
import '../features/passenger/screens/passenger_home_screen.dart';
import '../features/inspector/screens/inspector_home_screen.dart';
import '../features/ministry/screens/ministry_screen.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// After login the backend's JWT payload contains `role`.
/// GoRouter reads [authProvider] and redirects to the correct shell.
final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final isLoading = authState.isLoading;
      if (isLoading) return null; // Wait

      final role = authState.valueOrNull;
      final isLoggedIn = role != null;
      final loc = state.uri.toString();

      // Not logged in → force to login
      if (!isLoggedIn && loc != '/login' && loc != '/register') {
        return '/login';
      }

      // Already logged in, trying to hit login/register → redirect to shell
      if (isLoggedIn && (loc == '/login' || loc == '/register')) {
        return _roleToRoute(role);
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),

      // ── Driver shell ──────────────────────────────────────────────────────
      GoRoute(path: '/driver', builder: (_, __) => const DriverHomeScreen()),

      // ── Passenger shell ───────────────────────────────────────────────────
      GoRoute(path: '/passenger', builder: (_, __) => const PassengerHomeScreen()),

      // ── Inspector shell ───────────────────────────────────────────────────
      GoRoute(path: '/inspector', builder: (_, __) => const InspectorHomeScreen()),

      // ── Ministry shell ────────────────────────────────────────────────────
      GoRoute(path: '/ministry', builder: (_, __) => const MinistryScreen()),
    ],
  );
});

String _roleToRoute(String role) {
  switch (role) {
    case 'driver':
      return '/driver';
    case 'passenger':
      return '/passenger';
    case 'inspector':
      return '/inspector';
    case 'ministry_admin':
      return '/ministry';
    default:
      return '/login';
  }
}

/// Makes GoRouter re-evaluate redirect whenever auth state changes.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authProvider, (_, __) => notifyListeners());
  }
}
