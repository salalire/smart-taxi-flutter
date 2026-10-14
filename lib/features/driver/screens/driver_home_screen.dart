import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/api/api_service.dart';
import '../../../core/api/websocket_service.dart';
import '../../../core/models/relocation.dart';
import '../services/gps_service.dart';

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
  String _routeName = '';
  double _officialFare = 0;
  int? _currentZoneId;      // origin zone — excluded from relocation destinations
  int? _destinationZoneId;  // destination zone — excluded from relocation destinations
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
    _fetchRoute();
    await _ws.connect();
    _wsSub = _ws.messages.listen(_handleServerMessage);
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
      final route = await ref.read(apiServiceProvider).getMyRoute();
      if (!mounted) return;
      setState(() {
        _routeName = route.name;
        _officialFare = route.officialFare;
        _currentZoneId     = route.zoneId;
        _destinationZoneId = route.destinationZoneId;
        _routePoints = route.waypoints
            .map((w) => LatLng(w.latitude, w.longitude))
            .toList();
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  void _onPosition(Position pos) {
    final ll = LatLng(pos.latitude, pos.longitude);
    if (mounted) setState(() => _myPos = ll);
    if (_status == 'on_route' || _status == 'relocating') {
      try {
        _mapCtrl.move(ll, _mapCtrl.camera.zoom);
      } catch (_) {}
    }
    _ws.send({
      'type': 'location_update',
      'lat': pos.latitude,
      'lng': pos.longitude,
    });
  }

  void _handleServerMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final type = msg['type'] as String?;
    String? text;
    Color? color;

    switch (type) {
      case 'violation_alert':
        text = '⚠️ ${msg['message']}';
        color = Colors.red.shade700;
      case 'relocation_approved':
        text = '✅ Relocation approved → ${msg['to_zone']}\n'
            'Valid until: ${msg['valid_until']}';
        color = Colors.green.shade700;
        setState(() => _status = 'relocating');
      case 'relocation_rejected':
        text = '❌ Relocation rejected: ${msg['reason']}';
        color = Colors.orange.shade700;
      case 'relocation_recommendation':
        text = '💡 System suggests moving to: ${msg['to_zone']}';
    }

    if (text != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: color,
        duration: const Duration(seconds: 8),
      ));
    }
  }

  Future<void> _toggleStatus() async {
    final next = _status == 'on_route' ? 'offline' : 'on_route';
    try {
      await ref.read(apiServiceProvider).updateDriverStatus(next);
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
    final cs = Theme.of(context).colorScheme;
    final isOnRoute = _status == 'on_route';
    final isRelocating = _status == 'relocating';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isRelocating
                  ? '🔄  Relocating'
                  : isOnRoute
                      ? '🟢  On Route'
                      : '⚫  Offline',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isOnRoute || isRelocating
                    ? Colors.green.shade700
                    : cs.outline,
              ),
            ),
            if (_routeName.isNotEmpty)
              Text(
                _routeName,
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.transfer_within_a_station_outlined),
            tooltip: 'Request relocation',
            onPressed: () => _showRelocationSheet(),
          ),
          IconButton(
            icon: const Icon(Icons.verified_user_outlined),
            tooltip: 'My compliance & history',
            onPressed: () => _showComplianceSheet(),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'My route info',
            onPressed: () => _showRouteInfoSheet(),
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
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _myPos ?? const LatLng(9.03, 38.74),
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.smarttaxi.app',
              ),
              if (_routePoints.length > 1)
                PolylineLayer(polylines: [
                  Polyline(
                    points: _routePoints,
                    color: cs.primary,
                    strokeWidth: 4.5,
                  ),
                ]),
              CircleLayer(
                circles: _routePoints
                    .map((p) => CircleMarker(
                          point: p,
                          radius: 5,
                          color: cs.primaryContainer,
                          borderColor: cs.primary,
                          borderStrokeWidth: 1.5,
                        ))
                    .toList(),
              ),
              if (_myPos != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _myPos!,
                    width: 52,
                    height: 52,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isOnRoute || isRelocating
                            ? cs.primary
                            : cs.outline,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(Icons.directions_bus_rounded,
                          color: Colors.white, size: 26),
                    ),
                  ),
                ]),
            ],
          ),
          if (_loadingRoute) const Center(child: CircularProgressIndicator()),
          Positioned(
            bottom: 28,
            left: 24,
            right: 24,
            child: SizedBox(
              height: 56,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: isOnRoute ? Colors.red.shade600 : cs.primary,
                ),
                icon: Icon(isOnRoute
                    ? Icons.stop_circle_outlined
                    : Icons.play_arrow_rounded),
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

  // ── Sheets ────────────────────────────────────────────────────────────────

  void _showRelocationSheet() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _RelocationSheet(
          apiService: ref.read(apiServiceProvider),
          currentZoneId: _currentZoneId,
          destinationZoneId: _destinationZoneId,
        ),
      );

  void _showComplianceSheet() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) =>
            _ComplianceSheet(apiService: ref.read(apiServiceProvider)),
      );

  void _showRouteInfoSheet() => showModalBottomSheet(
        context: context,
        builder: (_) => _RouteInfoSheet(
          routeName: _routeName,
          fare: _officialFare,
          waypointCount: _routePoints.length,
        ),
      );
}

// ─── Relocation Request Sheet ─────────────────────────────────────────────────

class _RelocationSheet extends StatefulWidget {
  final ApiService apiService;
  final int? currentZoneId;     // origin zone — excluded
  final int? destinationZoneId; // destination zone — excluded
  const _RelocationSheet({
    required this.apiService,
    this.currentZoneId,
    this.destinationZoneId,
  });

  @override
  State<_RelocationSheet> createState() => _RelocationSheetState();
}

class _RelocationSheetState extends State<_RelocationSheet> {
  List<Map<String, dynamic>> _zones = [];
  int? _selectedZoneId;
  final _reasonCtrl = TextEditingController();
  bool _loading = false;
  bool _submitted = false;

  // Latest relocation request status
  RelocationRequest? _currentRequest;
  bool _loadingStatus = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        widget.apiService.getZonesList(),
        widget.apiService.getRelocationStatus(),
      ]);
      if (!mounted) return;
      setState(() {
        _zones = results[0] as List<Map<String, dynamic>>;
        _currentRequest = results[1] as RelocationRequest?;
        _loadingStatus = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedZoneId == null || _reasonCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a zone and enter a reason.')));
      return;
    }
    setState(() => _loading = true);
    try {
      await widget.apiService.requestRelocation(
        toZoneId: _selectedZoneId!,
        reason: _reasonCtrl.text.trim(),
      );
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
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: _submitted
          ? _SuccessView(
              title: 'Request Submitted!',
              message: 'The Ministry will review and notify you.',
              onClose: () => Navigator.pop(context),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Request Relocation',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),

                // Current status banner
                if (!_loadingStatus && _currentRequest != null) ...[
                  const SizedBox(height: 12),
                  _StatusBanner(request: _currentRequest!),
                ],

                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _selectedZoneId,
                  hint: const Text('Select destination zone'),
                  decoration: const InputDecoration(
                    labelText: 'Destination Zone',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: _zones
                      .where((z) =>
                          z['id'] as int != widget.currentZoneId &&
                          z['id'] as int != widget.destinationZoneId)
                      .map((z) => DropdownMenuItem<int>(
                            value: z['id'] as int,
                            child: Text(z['name'] as String),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedZoneId = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reasonCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason (e.g. low demand in current zone)',
                    prefixIcon: Icon(Icons.edit_note_outlined),
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Submit Request'),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Compliance & Violations History Sheet ─────────────────────────────────────

class _ComplianceSheet extends StatefulWidget {
  final ApiService apiService;
  const _ComplianceSheet({required this.apiService});

  @override
  State<_ComplianceSheet> createState() => _ComplianceSheetState();
}

class _ComplianceSheetState extends State<_ComplianceSheet> {
  RelocationRequest? _latestRelocation;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _latestRelocation = await widget.apiService.getRelocationStatus();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scroll) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(controller: scroll, children: [
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('My Activity',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                // Latest relocation
                if (_latestRelocation != null) ...[
                  Text('Latest Relocation Request',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _StatusBanner(request: _latestRelocation!),
                  const SizedBox(height: 16),
                ] else ...[
                  const Text('No relocation requests yet.'),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                const SizedBox(height: 16),
              ]),
      ),
    );
  }
}

// ─── Route Info Sheet ─────────────────────────────────────────────────────────

class _RouteInfoSheet extends StatelessWidget {
  final String routeName;
  final double fare;
  final int waypointCount;

  const _RouteInfoSheet({
    required this.routeName,
    required this.fare,
    required this.waypointCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Assigned Route',
              style:
                  theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _InfoRow(icon: Icons.route, label: 'Route', value: routeName.isEmpty ? 'Not assigned' : routeName),
          const SizedBox(height: 8),
          _InfoRow(icon: Icons.payments_outlined, label: 'Official Fare', value: 'ETB ${fare.toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          _InfoRow(icon: Icons.place_outlined, label: 'Waypoints', value: '$waypointCount stops'),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final RelocationRequest request;
  const _StatusBanner({required this.request});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (request.status) {
      'approved' => (Colors.green, Icons.check_circle_outline),
      'rejected' => (Colors.red, Icons.cancel_outlined),
      'expired' => (Colors.grey, Icons.timer_off_outlined),
      _ => (Colors.orange, Icons.hourglass_empty),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        border: Border.all(color: color.withAlpha(100)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${request.toZoneName ?? ''} — ${request.status.toUpperCase()}',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
            if (request.isApproved && request.validUntil != null)
              Text('Valid until: ${request.validUntil}',
                  style: const TextStyle(fontSize: 12)),
            if (request.status == 'rejected' &&
                request.rejectionReason != null)
              Text(request.rejectionReason!,
                  style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

class _SuccessView extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onClose;
  const _SuccessView(
      {required this.title, required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 64),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(message,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton(onPressed: onClose, child: const Text('Close')),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 10),
      SizedBox(
          width: 110,
          child: Text('$label:',
              style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: Text(value)),
    ]);
  }
}
