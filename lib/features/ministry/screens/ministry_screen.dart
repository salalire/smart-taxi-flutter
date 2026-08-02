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

// DemandReport is defined in passenger_report.dart

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
  List<DemandReport> _demandReports = [];
  List<Map<String, dynamic>> _observations = [];
  Map<String, dynamic> _dashboardStats = {};

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
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
        svc.getDemandReports(),
        svc.getDashboard(),
      ]);
      if (!mounted) return;
      setState(() {
        _buses        = results[0] as List<Driver>;
        _zones        = results[1] as List<Zone>;
        _relocations  = results[2] as List<RelocationRequest>;
        _violations   = results[3] as List<RouteViolation>;
        _reports      = results[4] as List<PassengerReport>;
        _demandReports = results[5] as List<DemandReport>;
        _dashboardStats = results[6] as Map<String, dynamic>;
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

  Future<void> _loadObservations() async {
    try {
      final svc = ref.read(apiServiceProvider);
      final raw = await svc.getMinistryObservations();
      if (!mounted) return;
      setState(() => _observations = raw);
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
            const Tab(text: 'Dashboard'),
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
          _buildDashboard(),
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
      length: 3,
      child: Column(children: [
        const TabBar(
          tabs: [
            Tab(text: 'Passenger Reports'),
            Tab(text: 'Demand Reports'),
            Tab(text: 'Observations'),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            _buildPassengerReports(),
            _buildDemandReports(),
            _buildObservations(),
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

  Widget _buildDemandReports() {
    if (_demandReports.isEmpty) {
      return _emptyState('No demand reports yet.', Icons.campaign_outlined);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: _demandReports.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = _demandReports[i];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.people_outline, size: 18),
            ),
            title: Text(r.zoneName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              '${r.reportType.replaceAll('_', ' ')} · weight: ${r.weight.toStringAsFixed(2)}'
              '\n${r.createdAt.length >= 10 ? r.createdAt.substring(0, 10) : r.createdAt}',
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  Widget _buildObservations() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Text('Field Observations',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _loadObservations,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Load'),
          ),
        ]),
      ),
      if (_observations.isEmpty)
        Expanded(
          child: Center(
            child: Text('Tap "Load" to fetch inspector field observations.',
                style: TextStyle(color: Colors.grey.shade600)),
          ),
        )
      else
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            itemCount: _observations.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final o = _observations[i];
              final reviewed = o['is_reviewed'] as bool? ?? false;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: reviewed
                        ? Colors.grey.shade100
                        : Colors.blue.shade50,
                    child: Icon(Icons.remove_red_eye_outlined,
                        color: reviewed ? Colors.grey : Colors.blue,
                        size: 18),
                  ),
                  title: Text(
                    '${o['observation_type'] ?? '—'} — ${o['zone_name'] ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Inspector: ${o['inspector_badge'] ?? '—'}'
                    '${(o['plate_number'] as String?)?.isNotEmpty == true ? ' · Plate: ${o['plate_number']}' : ''}'
                    '\n${(o['description'] as String?)?.isNotEmpty == true ? o['description'] : 'No description'}',
                  ),
                  isThreeLine: true,
                  trailing: reviewed
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : TextButton(
                          onPressed: () async {
                            await ref
                                .read(apiServiceProvider)
                                .markObservationReviewed(o['id'] as int);
                            _loadObservations();
                          },
                          child: const Text('Review'),
                        ),
                ),
              );
            },
          ),
        ),
    ]);
  }

  Widget _buildDashboard() {
    final drivers = _dashboardStats['drivers'] as Map? ?? {};
    final violations = _dashboardStats['violations'] as Map? ?? {};
    final relocations = _dashboardStats['relocations'] as Map? ?? {};
    final zones = _dashboardStats['zones'] as List? ?? [];

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatCard(
            title: 'Drivers',
            icon: Icons.directions_bus_rounded,
            color: Colors.indigo,
            stats: {
              'On Route': '${drivers['on_route'] ?? 0}',
              'Off Route': '${drivers['off_route'] ?? 0}',
              'Relocating': '${drivers['relocating'] ?? 0}',
              'Offline': '${drivers['offline'] ?? 0}',
              'Total': '${drivers['total'] ?? 0}',
            },
          ),
          const SizedBox(height: 12),
          _StatCard(
            title: 'Violations',
            icon: Icons.warning_amber_rounded,
            color: Colors.orange,
            stats: {
              'Open': '${violations['open'] ?? 0}',
              'Dispatched': '${violations['dispatched'] ?? 0}',
              'Confirmed': '${violations['confirmed'] ?? 0}',
              'Dismissed': '${violations['dismissed'] ?? 0}',
              'Total': '${violations['total'] ?? 0}',
            },
          ),
          const SizedBox(height: 12),
          _StatCard(
            title: 'Relocations',
            icon: Icons.transfer_within_a_station_outlined,
            color: Colors.teal,
            stats: {
              'Pending': '${relocations['pending'] ?? 0}',
              'Approved': '${relocations['approved'] ?? 0}',
              'Rejected': '${relocations['rejected'] ?? 0}',
            },
          ),
          const SizedBox(height: 12),
          if (zones.isNotEmpty) ...[
            const Text('Zone Status Snapshot',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            ...zones.map((z) {
              final status = z['status'] as String? ?? 'OK';
              final color = _zoneColor(status);
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: Icon(_zoneIcon(status), color: color, size: 20),
                  title: Text(z['name'] as String? ?? '—'),
                  trailing: Text(
                    '${z['bus_count'] ?? 0} bus${(z['bus_count'] ?? 0) == 1 ? '' : 'es'} · $status',
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: 12),
          // Compliance report
          Row(children: [
            const Text('Compliance Report',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _loadCompliance,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Load'),
            ),
          ]),
          const SizedBox(height: 8),
          if (_compliance.isEmpty)
            Text('Tap "Load" to fetch the compliance report.',
                style: TextStyle(color: Colors.grey.shade600))
          else
            ..._compliance.map((d) {
              final score = d['compliance_score'] as int? ?? 0;
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
                  child: Text('$score',
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                ),
                title: Text(d['license_plate'] as String? ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(d['username'] as String? ?? '—'),
                trailing: Text(
                  '${d['confirmed_violations'] ?? 0} confirmed',
                  style: TextStyle(
                      color: (d['confirmed_violations'] as int? ?? 0) > 0
                          ? Colors.red
                          : Colors.grey,
                      fontSize: 12),
                ),
              );
            }),
        ],
      ),
    );
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

// ─── Stat Card Widget ─────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Map<String, String> stats;

  const _StatCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: color)),
            ]),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: stats.entries.map((e) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(e.value,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: color)),
                    Text(e.key,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600)),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
