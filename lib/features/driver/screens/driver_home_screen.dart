import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/websocket_service.dart';
import '../services/gps_service.dart';

/// Driver shell.
/// - Full-screen map with assigned route waypoints drawn.
/// - GPS streamed to backend via WebSocket every ~15 m.
/// - Violation / relocation alerts shown as SnackBars.
/// - Status toggle (on_route ↔ offline) in the bottom bar.
class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  final _mapCtrl = MapController();
  late final WebSocketService _ws;
  late final GpsService _gps;

  LatLng? _myPos;
  String _status = 'offline';
  List<LatLng> _routePoints = [];
  bool _loadingRoute = true;

  StreamSubscription? _gpsSub;
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    _ws = WebSocketService(wsBaseUrl: kWsBaseUrl);
    _gps = GpsService();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Load route waypoints
    _fetchRoute();
    // Connect WebSocket
    await _ws.connect();
    _wsSub = _ws.messages.listen(_handleServerMessage);
    // Start GPS
    try {
      await _gps.requestPermissions();
      _gpsSub = _gps.positionStream.listen(_onPosition);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _fetchRoute() async {
    try {
      final resp = await ref.read(apiClientProvider).get('/api/driver/route/');
      final waypoints = (resp.data['waypoints'] as List)
          .map((w) => LatLng(
                (w['latitude'] as num).toDouble(),
                (w['longitude'] as num).toDouble(),
              ))
          .toList();
      if (!mounted) return;
      setState(() => _routePoints = waypoints);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  void _onPosition(Position pos) {
    final ll = LatLng(pos.latitude, pos.longitude);
    setState(() => _myPos = ll);
    _mapCtrl.move(ll, _mapCtrl.camera.zoom);
    // Stream GPS to backend
    _ws.send({
      'type': 'location_update',
      'lat': pos.latitude,
      'lng': pos.longitude,
    });
  }

  void _handleServerMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    String? text;
    Color? color;

    switch (type) {
      case 'violation_alert':
        text = '⚠️ ${msg['message']}';
        color = Colors.red.shade700;
        break;
      case 'relocation_approved':
        text = '✅ Relocation approved → ${msg['to_zone']}\n'
            'Valid until: ${msg['valid_until']}';
        color = Colors.green.shade700;
        setState(() => _status = 'relocating');
        break;
      case 'relocation_rejected':
        text = '❌ Relocation rejected: ${msg['reason']}';
        color = Colors.orange.shade700;
        break;
      case 'relocation_recommendation':
        text = '💡 System suggests moving to: ${msg['to_zone']}';
        break;
    }

    if (text != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: color,
          duration: const Duration(seconds: 7),
        ),
      );
    }
  }

  Future<void> _toggleStatus() async {
    final next = _status == 'on_route' ? 'offline' : 'on_route';
    try {
      await ref
          .read(apiClientProvider)
          .patch('/api/driver/status/', data: {'status': next});
      if (!mounted) return;
      setState(() => _status = next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _wsSub?.cancel();
    _ws.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isOnRoute = _status == 'on_route';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isOnRoute ? '🟢  On Route' : '⚫  Offline',
          style: TextStyle(
            color: isOnRoute ? Colors.green.shade700 : cs.outline,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.transfer_within_a_station_outlined),
            tooltip: 'Request relocation',
            onPressed: _showRelocationSheet,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: 'My compliance',
            onPressed: _showComplianceSheet,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _myPos ?? const LatLng(9.03, 38.74),
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.smarttaxi.app',
              ),
              // Route polyline
              if (_routePoints.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: cs.primary,
                      strokeWidth: 4,
                    ),
                  ],
                ),
              // Route waypoint dots
              CircleLayer(
                circles: _routePoints
                    .map((p) => CircleMarker(
                          point: p,
                          radius: 6,
                          color: cs.primaryContainer,
                          borderColor: cs.primary,
                          borderStrokeWidth: 2,
                        ))
                    .toList(),
              ),
              // My GPS dot
              if (_myPos != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _myPos!,
                      width: 52,
                      height: 52,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isOnRoute ? cs.primary : cs.outline,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 3),
                        ),
                        child: Icon(Icons.directions_bus_rounded,
                            color: Colors.white, size: 26),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ── Loading overlay ────────────────────────────────────────────
          if (_loadingRoute)
            const Center(child: CircularProgressIndicator()),

          // ── Status toggle button ───────────────────────────────────────
          Positioned(
            bottom: 28,
            left: 24,
            right: 24,
            child: SizedBox(
              height: 56,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      isOnRoute ? Colors.red.shade600 : cs.primary,
                ),
                icon: Icon(
                    isOnRoute ? Icons.stop_circle_outlined : Icons.play_arrow_rounded),
                label: Text(
                  isOnRoute ? 'Go Offline' : 'Start Shift',
                  style: const TextStyle(fontSize: 16),
                ),
                onPressed: _toggleStatus,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom sheets ──────────────────────────────────────────────────────────

  void _showRelocationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RelocationSheet(apiClient: ref.read(apiClientProvider)),
    );
  }

  void _showComplianceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => _ComplianceSheet(apiClient: ref.read(apiClientProvider)),
    );
  }
}

// ─── Relocation request sheet ────────────────────────────────────────────────

class _RelocationSheet extends StatefulWidget {
  final ApiClient apiClient;
  const _RelocationSheet({required this.apiClient});

  @override
  State<_RelocationSheet> createState() => _RelocationSheetState();
}

class _RelocationSheetState extends State<_RelocationSheet> {
  List<Map<String, dynamic>> _zones = [];
  int? _selectedZone;
  final _reasonCtrl = TextEditingController();
  bool _loading = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _loadZones();
  }

  Future<void> _loadZones() async {
    try {
      final resp = await widget.apiClient.get('/api/zones/list/');
      setState(() => _zones = List<Map<String, dynamic>>.from(resp.data));
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (_selectedZone == null || _reasonCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await widget.apiClient.post('/api/driver/relocation/request/', data: {
        'to_zone': _selectedZone,
        'reason': _reasonCtrl.text.trim(),
      });
      if (!mounted) return;
      setState(() => _submitted = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: _submitted
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 60),
              const SizedBox(height: 12),
              Text('Relocation request submitted!',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('The Ministry will review and respond shortly.',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ])
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Request Relocation',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _selectedZone,
                  hint: const Text('Select target zone'),                  decoration: const InputDecoration(
                    labelText: 'Destination Zone',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  items: _zones
                      .map((z) => DropdownMenuItem<int>(
                            value: z['id'] as int,
                            child: Text(z['name'] as String),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedZone = v),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _reasonCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason for relocation',
                    prefixIcon: Icon(Icons.edit_note_outlined),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Submit Request'),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Compliance sheet ────────────────────────────────────────────────────────

class _ComplianceSheet extends StatefulWidget {
  final ApiClient apiClient;
  const _ComplianceSheet({required this.apiClient});

  @override
  State<_ComplianceSheet> createState() => _ComplianceSheetState();
}

class _ComplianceSheetState extends State<_ComplianceSheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await widget.apiClient.get('/api/driver/relocation/status/');
      setState(() => _data = resp.data as Map<String, dynamic>);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Status',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                if (_data != null)
                  ..._data!.entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 160,
                              child: Text('${e.key}:',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ),
                            Expanded(child: Text('${e.value}')),
                          ],
                        ),
                      ))
                else
                  const Text('No data available.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
    );
  }
}
