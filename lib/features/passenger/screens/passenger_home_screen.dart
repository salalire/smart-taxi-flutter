import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/api/api_service.dart';
import '../../../core/models/driver.dart';
import '../../../core/models/zone.dart';

class PassengerHomeScreen extends ConsumerStatefulWidget {
  const PassengerHomeScreen({super.key});

  @override
  ConsumerState<PassengerHomeScreen> createState() =>
      _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends ConsumerState<PassengerHomeScreen> {
  List<Driver> _buses = [];
  List<Zone> _zones = [];
  LatLng _myPos = const LatLng(9.03, 38.74);
  bool _checkedIn = false;
  bool _loading = false;
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
      if (mounted) {
        setState(() => _myPos = LatLng(pos.latitude, pos.longitude));
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final svc = ref.read(apiServiceProvider);
      final results = await Future.wait([
        svc.getNearbyBuses(_myPos.latitude, _myPos.longitude, 3.0),
        svc.getZoneDemand(),
      ]);
      if (!mounted) return;
      setState(() {
        _buses = results[0] as List<Driver>;
        _zones = results[1] as List<Zone>;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkIn(int zoneId) async {
    try {
      await ref.read(apiServiceProvider).stopCheckIn(
            zoneId: zoneId,
            lat: _myPos.latitude,
            lng: _myPos.longitude,
          );
      if (!mounted) return;
      setState(() {
        _checkedIn = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Checked in! The system sees you are waiting.'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Check-in failed: $e')));
    }
  }

  Future<void> _checkOut() async {
    try {
      await ref.read(apiServiceProvider).stopCheckOut();
      if (!mounted) return;
      setState(() {
        _checkedIn = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Checked out. Enjoy your ride!')));
    } catch (_) {}
  }

  Color _zoneColor(String status) => switch (status) {
        'CRITICAL_LOW' => Colors.red,
        'LOW' => Colors.orange,
        'HIGH' => Colors.blue,
        _ => Colors.green,
      };

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
        title: Text('${_buses.length} bus${_buses.length == 1 ? '' : 'es'} nearby'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: 'Zone demand',
            onPressed: () => _showZoneDemandSheet(),
          ),
          IconButton(
            icon: const Icon(Icons.report_problem_outlined),
            tooltip: 'Report violation',
            onPressed: () => _showViolationReportSheet(),
          ),
          IconButton(
            icon: const Icon(Icons.campaign_outlined),
            tooltip: 'Report demand',
            onPressed: () => _showDemandReportSheet(),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
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
            options: MapOptions(initialCenter: _myPos, initialZoom: 14),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.smarttaxi.app',
              ),
              // Zone demand circles
              CircleLayer(
                circles: _zones.map((z) {
                  final c = _zoneColor(z.status);
                  return CircleMarker(
                    point: LatLng(z.centerLatitude, z.centerLongitude),
                    radius: 90,
                    color: c.withAlpha(40),
                    borderColor: c.withAlpha(180),
                    borderStrokeWidth: 2,
                  );
                }).toList(),
              ),
              // Bus markers
              MarkerLayer(
                markers: _buses
                    .where((b) =>
                        b.currentLatitude != null && b.currentLongitude != null)
                    .map((b) => Marker(
                          point: LatLng(
                              b.currentLatitude!, b.currentLongitude!),
                          width: 42,
                          height: 42,
                          child: Icon(Icons.directions_bus_rounded,
                              color: b.isOnRoute
                                  ? Colors.indigo
                                  : Colors.red.shade400,
                              size: 32),
                        ))
                    .toList(),
              ),
              // My position
              MarkerLayer(markers: [
                Marker(
                  point: _myPos,
                  width: 22,
                  height: 22,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                  ),
                ),
              ]),
            ],
          ),
          // Check-in / check-out button
          Positioned(
            bottom: 28,
            left: 24,
            right: 24,
            child: SizedBox(
              height: 54,
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
                onPressed:
                    _checkedIn ? _checkOut : () => _showCheckInSheet(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sheet launchers ───────────────────────────────────────────────────────

  void _showCheckInSheet() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _CheckInSheet(
          zones: _zones,
          onCheckIn: _checkIn,
        ),
      );

  void _showZoneDemandSheet() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ZoneDemandSheet(zones: _zones),
      );

  void _showViolationReportSheet() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ViolationReportSheet(
          apiService: ref.read(apiServiceProvider),
          zones: _zones,
          myLat: _myPos.latitude,
          myLng: _myPos.longitude,
        ),
      );

  void _showDemandReportSheet() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _DemandReportSheet(
          apiService: ref.read(apiServiceProvider),
          zones: _zones,
          myLat: _myPos.latitude,
          myLng: _myPos.longitude,
        ),
      );
}

// ─── Check-in Sheet ───────────────────────────────────────────────────────────

class _CheckInSheet extends StatefulWidget {
  final List<Zone> zones;
  final Future<void> Function(int zoneId) onCheckIn;
  const _CheckInSheet({required this.zones, required this.onCheckIn});

  @override
  State<_CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<_CheckInSheet> {
  int? _selectedZoneId;
  bool _loading = false;

  Future<void> _submit() async {
    if (_selectedZoneId == null) return;
    setState(() => _loading = true);
    await widget.onCheckIn(_selectedZoneId!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Check In at a Stop',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            'Tap to signal you are waiting. This helps the system redistribute buses.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            value: _selectedZoneId,
            hint: const Text('Select your zone / stop area'),
            decoration: const InputDecoration(
              labelText: 'Zone',
              prefixIcon: Icon(Icons.location_pin),
              border: OutlineInputBorder(),
            ),
            items: widget.zones
                .map((z) => DropdownMenuItem(
                      value: z.id,
                      child: Text('${z.name}  (${z.status})'),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _selectedZoneId = v),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _loading || _selectedZoneId == null ? null : _submit,
              icon: const Icon(Icons.location_pin),
              label: _loading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Check In'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Zone Demand Sheet ────────────────────────────────────────────────────────

class _ZoneDemandSheet extends StatelessWidget {
  final List<Zone> zones;
  const _ZoneDemandSheet({required this.zones});

  Color _statusColor(String s) => switch (s) {
        'CRITICAL_LOW' => Colors.red,
        'LOW' => Colors.orange,
        'HIGH' => Colors.blue,
        _ => Colors.green,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Zone Demand Summary',
              style:
                  theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Live bus supply vs passenger demand per zone.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 14),
          ...zones.map((z) {
            final color = _statusColor(z.status);
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withAlpha(30),
                  child: Icon(Icons.location_city, color: color, size: 20),
                ),
                title: Text(z.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '${z.busCount} bus${z.busCount == 1 ? '' : 'es'} · '
                    '${z.demandCount} demand signal${z.demandCount == 1 ? '' : 's'}'),
                trailing: Chip(
                  label: Text(z.status,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                  backgroundColor: color.withAlpha(25),
                  side: BorderSide(color: color.withAlpha(80)),
                  padding: EdgeInsets.zero,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Violation Report Sheet ───────────────────────────────────────────────────

class _ViolationReportSheet extends StatefulWidget {
  final ApiService apiService;
  final List<Zone> zones;
  final double myLat;
  final double myLng;
  const _ViolationReportSheet({
    required this.apiService,
    required this.zones,
    required this.myLat,
    required this.myLng,
  });

  @override
  State<_ViolationReportSheet> createState() => _ViolationReportSheetState();
}

class _ViolationReportSheetState extends State<_ViolationReportSheet> {
  final _plateCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  int? _selectedZoneId;
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
    if (_plateCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter the bus plate number.')));
      return;
    }
    setState(() => _loading = true);
    try {
      await widget.apiService.submitPassengerReport(
        plateNumber: _plateCtrl.text.trim().toUpperCase(),
        reportType: _type,
        zoneId: _selectedZoneId,
        description: _descCtrl.text.trim(),
        reporterLat: widget.myLat,
        reporterLng: widget.myLng,
      );
      if (!mounted) return;
      setState(() => _done = true);
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
    _plateCtrl.dispose();
    _descCtrl.dispose();
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
      child: _done
          ? _SuccessView(
              title: 'Report Submitted!',
              message:
                  'The Ministry will review your report. Thank you for helping.',
              onClose: () => Navigator.pop(context),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Report a Violation',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _plateCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Bus plate number (e.g. AA-12345)',
                    prefixIcon: Icon(Icons.directions_car_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(
                    labelText: 'Violation type',
                    prefixIcon: Icon(Icons.report_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: _types
                      .map((t) =>
                          DropdownMenuItem(value: t.$1, child: Text(t.$2)))
                      .toList(),
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _selectedZoneId,
                  hint: const Text('Zone (optional)'),
                  decoration: const InputDecoration(
                    labelText: 'Zone where you saw this',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: widget.zones
                      .map((z) =>
                          DropdownMenuItem(value: z.id, child: Text(z.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedZoneId = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
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
                        : const Text('Submit Report'),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Demand Report Sheet ──────────────────────────────────────────────────────

class _DemandReportSheet extends StatefulWidget {
  final ApiService apiService;
  final List<Zone> zones;
  final double myLat;
  final double myLng;
  const _DemandReportSheet({
    required this.apiService,
    required this.zones,
    required this.myLat,
    required this.myLng,
  });

  @override
  State<_DemandReportSheet> createState() => _DemandReportSheetState();
}

class _DemandReportSheetState extends State<_DemandReportSheet> {
  int? _selectedZoneId;
  String _type = 'high_demand';
  final _descCtrl = TextEditingController();
  bool _loading = false;
  bool _done = false;

  static const _types = [
    ('high_demand', 'High Demand — Many people waiting, no buses'),
    ('long_wait', 'Long Wait — No bus for 20+ minutes'),
    ('stop_abandoned', 'Stop Abandoned — No service at all'),
    ('low_demand', 'Low Demand — Very few passengers'),
    ('oversupply', 'Oversupply — Too many empty buses'),
  ];

  Future<void> _submit() async {
    if (_selectedZoneId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a zone.')));
      return;
    }
    setState(() => _loading = true);
    try {
      await widget.apiService.submitDemandReport(
        zoneId: _selectedZoneId!,
        reportType: _type,
        lat: widget.myLat,
        lng: widget.myLng,
        description: _descCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _done = true);
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
    _descCtrl.dispose();
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
      child: _done
          ? _SuccessView(
              title: 'Demand Report Submitted!',
              message:
                  'Your signal helps the system redistribute buses faster.',
              onClose: () => Navigator.pop(context),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Report Demand Situation',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  'Tell the system about supply/demand conditions at your stop.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  value: _selectedZoneId,
                  hint: const Text('Select zone / stop area'),
                  decoration: const InputDecoration(
                    labelText: 'Zone',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: widget.zones
                      .map((z) =>
                          DropdownMenuItem(value: z.id, child: Text(z.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedZoneId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(
                    labelText: 'Situation type',
                    prefixIcon: Icon(Icons.campaign_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: _types
                      .map((t) =>
                          DropdownMenuItem(value: t.$1, child: Text(t.$2)))
                      .toList(),
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Additional details (optional)',
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
                        : const Text('Submit Report'),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Shared success view ──────────────────────────────────────────────────────

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
