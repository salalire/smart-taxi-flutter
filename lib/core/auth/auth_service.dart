import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api/api_client.dart';

/// Handles login, register, token storage, and JWT payload decoding.
/// The Django backend embeds `role`, `username`, `user_id` into the JWT
/// via CustomTokenObtainPairSerializer — we decode them without a library.
class AuthService {
  final ApiClient _api;
  final FlutterSecureStorage _storage;

  AuthService({
    required ApiClient api,
    FlutterSecureStorage? storage,
  })  : _api = api,
        _storage = storage ?? const FlutterSecureStorage();

  // ── State ──────────────────────────────────────────────────────────────────

  Future<bool> get isAuthenticated async {
    final token = await _storage.read(key: 'access_token');
    return token != null && token.isNotEmpty;
  }

  Future<String?> get userRole => _storage.read(key: 'user_role');
  Future<String?> get accessToken => _storage.read(key: 'access_token');
  Future<String?> get userId => _storage.read(key: 'user_id');
  Future<String?> get username => _storage.read(key: 'username');

  // ── Login ──────────────────────────────────────────────────────────────────

  /// Returns the user's role on success. Throws [DioException] on failure.
  Future<String> login(String username, String password) async {
    final response = await _api.post(
      '/api/auth/login/',
      data: {'username': username, 'password': password},
    );

    final access = response.data['access'] as String;
    final refresh = response.data['refresh'] as String;
    final role = response.data['role'] as String;
    final userId = response.data['user_id'].toString();
    final uname = response.data['username'] as String;

    await Future.wait([
      _storage.write(key: 'access_token', value: access),
      _storage.write(key: 'refresh_token', value: refresh),
      _storage.write(key: 'user_role', value: role),
      _storage.write(key: 'user_id', value: userId),
      _storage.write(key: 'username', value: uname),
    ]);

    return role;
  }

  // ── Register ───────────────────────────────────────────────────────────────

  Future<void> register({
    required String username,
    required String email,
    required String phone,
    required String role,
    required String password,
    required String password2,
    String? licensePlate,
    String? badgeNumber,
    int? assignedRoute,
    int? assignedZone,
  }) async {
    await _api.post(
      '/api/auth/register/',
      data: {
        'username': username,
        'email': email,
        'phone': phone,
        'role': role,
        'password': password,
        'password2': password2,
        if (licensePlate != null) 'license_plate': licensePlate,
        if (badgeNumber != null) 'badge_number': badgeNumber,
        if (assignedRoute != null) 'assigned_route': assignedRoute,
        if (assignedZone != null) 'assigned_zone': assignedZone,
      },
    );
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    await _storage.deleteAll();
  }

  // ── JWT decode ─────────────────────────────────────────────────────────────

  Map<String, dynamic>? decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = base64Url.decode(base64Url.normalize(parts[1]));
      return jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
