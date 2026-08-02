import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Role → WebSocket endpoint mapping, mirrors Django routing.py
const _wsEndpoints = {
  'driver': '/ws/driver/',
  'inspector': '/ws/inspector/',
  'ministry_admin': '/ws/dashboard/',
  // Passengers don't use WebSocket (REST polling is enough for them)
};

/// Manages the authenticated user's WebSocket connection.
/// Reconnects automatically on unexpected close with 3s backoff.
class WebSocketService {
  final String _wsBaseUrl; // e.g. 'ws://10.0.2.2:8000'
  final FlutterSecureStorage _storage;

  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _controller;
  bool _intentionalClose = false;

  WebSocketService({
    required String wsBaseUrl,
    FlutterSecureStorage? storage,
  })  : _wsBaseUrl = wsBaseUrl,
        _storage = storage ?? const FlutterSecureStorage();

  Stream<Map<String, dynamic>> get messages {
    _controller ??= StreamController.broadcast();
    return _controller!.stream;
  }

  Future<void> connect() async {
    _intentionalClose = false;
    final role = await _storage.read(key: 'user_role');
    final token = await _storage.read(key: 'access_token');

    final endpoint = _wsEndpoints[role];
    if (endpoint == null || token == null) return;

    final uri = Uri.parse('$_wsBaseUrl$endpoint?token=$token');
    _channel = IOWebSocketChannel.connect(uri);
    _controller ??= StreamController.broadcast();

    _channel!.stream.listen(
      (raw) {
        try {
          final data = jsonDecode(raw as String) as Map<String, dynamic>;
          _controller!.add(data);
        } catch (_) {}
      },
      onError: (_) => _reconnect(),
      onDone: () {
        if (!_intentionalClose) _reconnect();
      },
    );
  }

  /// Send a JSON message (e.g. GPS location_update from driver).
  void send(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  void disconnect() {
    _intentionalClose = true;
    _channel?.sink.close();
    _channel = null;
  }

  Future<void> _reconnect() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!_intentionalClose) await connect();
  }

  void dispose() {
    disconnect();
    _controller?.close();
  }
}
