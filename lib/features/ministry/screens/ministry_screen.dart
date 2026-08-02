import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/api/api_service.dart';
import '../../../core/models/driver.dart';
import '../../../core/models/zone.dart';
import '../../../core/models/relocation.dart';
import '../../../core/models/violation.dart';
import '../../../core/models/passenger_report.dart';

class MinistryScreen extends ConsumerStatefulWidget {
  const MinistryScreen({super.key});

  @override
  ConsumerState<MinistryScreen> createState() => _MinistryScreenState();
}

class _MinistryScreenState extends ConsumerState<MinistryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Timer? _refreshTimer;

  List<Driver> _buses = [];
  List<Zone> _zones = [];
  List<RelocationRequest> _relocations = [];
  List<RouteViolation> _violations = [];
  List<PassengerReport> _reports = [];
  List<Map<String, dynamic>> _compliance = [];

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _loadAll();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _loadAll());
  }

  Future<void> _loadAll() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final svc = ref.read(apiServiceProvider);
      final results = await Future.wait([
        svc.getLiveBuses(),
        svc.getMinistryZones(),
        svc.getPendingRelocations(),
        svc.getViolations(),
        svc.getPassengerReports(),
      ]);
      if (!mounted) return;
      setState(() {
        _buses = results[0] as List<Driver>;
        _zones = results[1] as List<Zone>;
        _relocations = results[2] as List<RelocationRequest>;
        _violations = results[3] as List<RouteViolation>;
        _reports = results[4] as List<PassengerReport>;
      });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadCompliance() async {
    try {
      final data = await ref.read(apiServiceProvider).getComplianceReport();
      if (!mounted) return;
      setState(() => _compliance = data);
    } catch (_) {}
  }

  Future<void> _decideRelocation(int id, String action) async {
    try {
      await ref.read(apiServiceProvider).decideRelocation(
            relocationId: id,
            action: action,
          );
      _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            action == 'approve' ? '✅ Approved.' : '❌ Rejected.'),
        backgroundColor: action == 'approve' ? Colors.green : Colors.red,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _dispatchInspector(int violationId) async {
    try {
      await ref.read(apiServiceProvider).dispatchInspector(violationId);
      _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inspector dispatched.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ministry Dashboard'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (mounted) context.go('/login');
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'Live Map (${_buses.length})'),
            Tab(text: 'Zones (${_zones.length})'),
            Tab(text: 'Relocations (${_relocations.length})'),
            Tab(text: 'Violations (${_violations.length})'),
            const Tab(text: 'Reports & Compliance'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildLiveMap(),
          _buildZones(),
          _buildRelocations(),
          _buildViolations(),
          _buildReportsTab(),
        ],
      ),
    );
  }

  // ── Tab 1: Live map ───────────────────────────────────────────────────────

  Widget _buildLiveMap() {
    return FlutterMap(
      options: const MapOptions(
        initialCenter: LatLng(9.03, 38.74),
        initialZoom: 12,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.smarttaxi.app',
        ),
        // Zone circles
        CircleLayer(
          circles: _zones.map((z) {
            final c = _zoneColor(z.status);
            return CircleMarker(
              point: LatLng(z.centerLatitude, z.centerLongitude),
              radius: 80,
              color: c.withAlpha(30),
              borderColor: c.withAlpha(160),
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
                    point: LatLng(b.currentLatitude!, b.currentLongitude!),
                    width: 42,
                    height: 42,
                    child: Tooltip(
                      message:
                          '${b.licensePlate} · ${b.status.replaceAll('_', ' ')}',
                      child: Icon(
                        Icons.directions_bus_rounded,
                        color: b.isOnRoute
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                        size: 30,
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  // ── Tab 2: Zones ──────────────────────────────────────────────────────────

  Widget _buildZones() {
    if (_zones.isEmpty) {
      return _emptyState('No zone data.', Icons.location_city_outlined);
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: _zones.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final z = _zones[i];
          final color = _zoneColor(z.status);
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: color.withAlpha(30),
                child: Icon(_zoneIcon(z.status), color: color, size: 20),
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
        },
      ),
    );
  }

  // ── Tab 3: Pending relocations ────────────────────────────────────────────

  Widget _buildRelocations() {
    if (_relocations.isEmpty) {
      return _emptyState(
          'No pending relocations.', Icons.transfer_within_a_station_outlined);
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: _relocations.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = _relocations[i];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.directions_bus_rounded, size: 18),
                      const SizedBox(width: 6),
                      Text(r.driverPlate,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const Spacer(),
                      Chip(
                        label: Text(
                            r.initiatedBy == 'system'
                                ? '🤖 System'
                                : '👤 Driver',
                            style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                        '${r.fromZoneName ?? '—'} → ${r.toZoneName ?? '—'}',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13)),
                    if (r.reason.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(r.reason,
                          style: const TextStyle(fontSize: 13),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Reject'),
                          onPressed: () =>
                              _showRejectDialog(r.id),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.green),
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Approve'),
                          onPressed: () =>
                              _decideRelocation(r.id, 'approve'),
                        ),
                      ),
                    ]),
                  ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showRejectDialog(int id) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Relocation'),
        content: TextFormField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Reason for rejection (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reject')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(apiServiceProvider).decideRelocation(
            relocationId: id,
            action: 'reject',
            rejectionReason: ctrl.text.trim(),
          );
      _loadAll();
    }
  }

  // ── Tab 4: Violations ─────────────────────────────────────────────────────

  Widget _buildViolations() {
    if (_violations.isEmpty) {
      return _emptyState('No violations.', Icons.verified_outlined);
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: _violations.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final v = _violations[i];
          final color = switch (v.status) {
            'confirmed' => Colors.red,
            'dismissed' => Colors.grey,
            'inspector_dispatched' => Colors.blue,
            _ => Colors.orange,
          };
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: color.withAlpha(30),
                child: Icon(Icons.warning_amber_rounded,
                    color: color, size: 20),
              ),
              title: Text(v.driverPlate,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${v.routeName ?? '—'} · ${v.shortDate}\n'
                'Status: ${v.status.replaceAll('_', ' ')}',
              ),
              isThreeLine: true,
              trailing: v.status == 'open'
                  ? TextButton(
                      onPressed: () => _dispatchInspector(v.id),
                      child: const Text('Dispatch'),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }

  // ── Tab 5: Reports & Compliance ───────────────────────────────────────────

  Widget _buildReportsTab() {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        const TabBar(
          tabs: [
            Tab(text: 'Passenger Reports'),
            Tab(text: 'Compliance'),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            _buildPassengerReports(),
            _buildComplianceReport(),
          ]),
        ),
      ]),
    );
  }

  Widget _buildPassengerReports() {
    if (_reports.isEmpty) {
      return _emptyState('No passenger reports.', Icons.inbox_outlined);
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: _reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = _reports[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: r.isReviewed
                    ? Colors.grey.shade100
                    : Colors.orange.shade100,
                child: Icon(Icons.person_outlined,
                    color: r.isReviewed ? Colors.grey : Colors.orange),
              ),
              title: Text(r.plateNumber,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                  '${r.reportType.replaceAll('_', ' ')} · ${r.passengerUsername}\n'
                  '${r.description.isNotEmpty ? r.description : 'No description'}'),
              isThreeLine: true,
              trailing: r.isReviewed
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : TextButton(
                      onPressed: () async {
                        await ref
                            .read(apiServiceProvider)
                            .markPassengerReportReviewed(r.id);
                        _loadAll();
                      },
                      child: const Text('Review'),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildComplianceReport() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Text('Driver Compliance Report',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _loadCompliance,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Load'),
          ),
        ]),
      ),
      if (_compliance.isEmpty)
        Expanded(
            child: Center(
          child: Text('Tap "Load" to fetch the compliance report.',
              style: TextStyle(color: Colors.grey.shade600)),
        ))
      else
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            itemCount: _compliance.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = _compliance[i];
              final score =
                  d['compliance_score'] as int? ?? d['score'] as int? ?? 0;
              final plate = d['license_plate'] as String? ?? '—';
              final username = d['username'] as String? ?? '—';
              final violations = d['violation_count'] as int? ??
                  (d['violations'] as List?)?.length ??
                  0;

              final color = score >= 80
                  ? Colors.green
                  : score >= 60
                      ? Colors.orange
                      : Colors.red;

              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withAlpha(30),
                  child: Text(
                    '$score',
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ),
                title: Text(plate,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(username),
                trailing: Text(
                  '$violations violation${violations == 1 ? '' : 's'}',
                  style: TextStyle(
                      color: violations > 0 ? Colors.red : Colors.grey,
                      fontSize: 12),
                ),
              );
            },
          ),
        ),
    ]);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _zoneColor(String s) => switch (s) {
        'CRITICAL_LOW' => Colors.red,
        'LOW' => Colors.orange,
        'HIGH' => Colors.blue,
        _ => Colors.green,
      };

  IconData _zoneIcon(String s) => switch (s) {
        'CRITICAL_LOW' => Icons.warning_rounded,
        'LOW' => Icons.arrow_downward,
        'HIGH' => Icons.arrow_upward,
        _ => Icons.check_circle_outline,
      };

  Widget _emptyState(String text, IconData icon) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ]),
      );
}
