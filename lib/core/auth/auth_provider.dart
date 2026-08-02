import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api/api_client.dart';
import 'auth_service.dart';

// ─── Singletons ───────────────────────────────────────────────────────────────

/// Base URL — change this to your server's address.
/// For Android emulator: 'http://10.0.2.2:8000'
/// For physical device on same network: 'http://192.168.x.x:8000'
const kApiBaseUrl = 'http://10.0.2.2:8000';
const kWsBaseUrl = 'ws://10.0.2.2:8000';

final storageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: kApiBaseUrl,
    storage: ref.watch(storageProvider),
  );
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    api: ref.watch(apiClientProvider),
    storage: ref.watch(storageProvider),
  );
});

// ─── Auth State ───────────────────────────────────────────────────────────────

/// Holds the authenticated user's role string, or null when logged out.
/// The router watches this and redirects accordingly.
class AuthNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final auth = ref.watch(authServiceProvider);
    if (await auth.isAuthenticated) return auth.userRole;
    return null;
  }

  Future<void> login(String username, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authServiceProvider).login(username, password),
    );
  }

  Future<void> logout() async {
    await ref.read(authServiceProvider).logout();
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, String?>(
  AuthNotifier.new,
);
