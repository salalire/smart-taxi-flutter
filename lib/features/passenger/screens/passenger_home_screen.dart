import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/api/api_client.dart';

/// Passenger shell.
/// - Live map showing nearby buses (refreshed every 10 s).
/// - Coloured zone circles showing supply/demand status.
/// - Check-in button: one tap to signal "I am waiting here".
/// - Report button: submit violation report by plate number.
class PassengerHomeScreen extends ConsumerStatefulWidget {
  const PassengerHomeScreen({super.key});

  @override
  ConsumerState<PassengerHomeScreen> createState() =>
      _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends ConsumerState<PassengerHomeScreen> {
  List<Map<String, dynamic>> _buses = [];
  List<Map<String, dynamic>> _zones = [];
  LatLng _myPos = const LatLng(9.03, 38.74); // Default: Addis Ababa centre
  bool _checkedIn = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadData();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _loadData());
  }

  Future<void> _initLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _myPos = LatLng(pos.latitude, pos.longitude));
    } catch (_) {}
  }

  Future<void> _loadData() async {
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.get('/api/buses/nearby/', queryParameters: {
          'lat': _myPos.latitude,
          'lng': _myPos.longitude,
          'radius_km': 3,
        }),
        api.get('/api/zones/demand/'),
      ]);
      if (mounted) {
        setState(() {
          _buses = List<Map<String, dynamic>>.from(results[0].data);
          _zones = List<Map<String, dynamic>>.from(results[1].data);
        });
      }
    } catch (_) {}
  }

  Future<void> _checkIn() async {
    if (_zones.isEmpty) return;
    // Find closest zone
    final zone = _zones.first;
    try {
      await ref.read(apiClientProvider).post('/api/stop/checkin/', data: {
        'zone': zone['zone_id'],
        'latitude': _myPos.latitude,
        'longitude': _myPos.longitude,
      });
      if (!mounted) return;
      setState(() => _checkedIn = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Checked in! System knows you\'re waiting.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Check-in failed: $e')));
    }
  }

  Future<void> _checkOut() async {
    try {
      await ref.read(apiClientProvider).post('/api/stop/checkout/');
      setState(() => _checkedIn = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Checked out. Enjoy your ride!')));
      }
    } catch (_) {}
  }

  Color _zoneColor(String? status) {
    switch (status) {
      case 'CRITICAL_LOW':
        return Colors.red;
      case 'LOW':
        return Colors.orange;
      case 'HIGH':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Buses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.report_problem_outlined),
            tooltip: 'Report a violation',
            onPressed: _showReportSheet,
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
            options: MapOptions(
              initialCenter: _myPos,
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.smarttaxi.app',
              ),

              // Zone circles (supply/demand heatmap)
              CircleLayer(
                circles: _zones.map((z) {
                  final lat = (z['center_lat'] as num?)?.toDouble();
                  final lng = (z['center_lng'] as num?)?.toDouble();
                  if (lat == null || lng == null) {
                    return const CircleMarker(
                        point: LatLng(0, 0), radius: 0, color: Colors.transparent);
                  }
                  final color = _zoneColor(z['status'] as String?);
                  return CircleMarker(
                    point: LatLng(lat, lng),
                    radius: 90,
                    color: color.withAlpha(40),
                    borderColor: color.withAlpha(180),
                    borderStrokeWidth: 2,
                  );
                }).toList(),
              ),

              // Bus markers
              MarkerLayer(
                markers: _buses.map((b) {
                  final lat =
                      (b['current_latitude'] as num?)?.toDouble();
                  final lng =
                      (b['current_longitude'] as num?)?.toDouble();
                  if (lat == null || lng == null) return null;
                  return Marker(
                    point: LatLng(lat, lng),
                    width: 42,
                    height: 42,
                    child: const Icon(Icons.directions_bus_rounded,
                        color: Colors.indigo, size: 32),
                  );
                }).whereType<Marker>().toList(),
              ),

              // My position
              MarkerLayer(
                markers: [
                  Marker(
                    point: _myPos,
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── Bus count badge ────────────────────────────────────────────
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_buses.length} bus${_buses.length == 1 ? '' : 'es'} nearby',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),

          // ── Check-in / out button ──────────────────────────────────────
          Positioned(
            bottom: 28,
            left: 24,
            right: 24,
            child: SizedBox(
              height: 56,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _checkedIn ? Colors.orange.shade700 : null,
                ),
                icon: Icon(_checkedIn
                    ? Icons.directions_bus_rounded
                    : Icons.location_pin),
                label: Text(
                  _checkedIn
                      ? 'I boarded — Check out'
                      : 'Check in at this stop',
                  style: const TextStyle(fontSize: 15),
                ),
                onPressed: _checkedIn ? _checkOut : _checkIn,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReportSheet(apiClient: ref.read(apiClientProvider)),
    );
  }
}

// ─── Violation report sheet ──────────────────────────────────────────────────

class _ReportSheet extends StatefulWidget {
  final ApiClient apiClient;
  const _ReportSheet({required this.apiClient});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _plateCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _type = 'wrong_route';
  bool _loading = false;
  bool _done = false;

  static const _types = [
    ('wrong_route', 'Wrong Route'),
    ('overcharging', 'Overcharging'),
    ('overcrowding', 'Overcrowding'),
    ('other', 'Other'),
  ];

  Future<void> _submit() async {
    if (_plateCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await widget.apiClient.post('/api/violations/report/', data: {
        'plate_number': _plateCtrl.text.trim().toUpperCase(),
        'report_type': _type,
        'description': _descCtrl.text.trim(),
      });
      setState(() => _done = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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
      child: _done
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 56),
              const SizedBox(height: 12),
              Text('Report submitted!', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('The Ministry will review your report.',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close')),
            ])
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Report a Violation',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _plateCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Bus plate number (e.g. AA-12345)',
                    prefixIcon: Icon(Icons.directions_car_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration:
                      const InputDecoration(labelText: 'Violation type'),
                  items: _types
                      .map((t) => DropdownMenuItem(
                          value: t.$1, child: Text(t.$2)))
                      .toList(),
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
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
                        : const Text('Submit Report'),
                  ),
                ),
              ],
            ),
    );
  }
}
