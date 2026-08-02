import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/auth/auth_provider.dart';

/// Ministry Admin shell — live dashboard view.
/// - Map showing all active buses.
/// - Zone status cards (OK / LOW / CRITICAL_LOW / HIGH).
/// - Pending relocations list with approve/reject.
class MinistryScreen extends ConsumerStatefulWidget {
  const MinistryScreen({super.key});

  @override
  ConsumerState<MinistryScreen> createState() => _MinistryScreenState();
}

class _MinistryScreenState extends ConsumerState<MinistryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Timer? _refreshTimer;

  List<Map<String, dynamic>> _buses = [];
  List<Map<String, dynamic>> _zones = [];
  List<Map<String, dynamic>> _relocations = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadAll();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _loadAll());
  }

  Future<void> _loadAll() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.get('/api/ministry/buses/live/'),
        api.get('/api/ministry/zones/'),
        api.get('/api/ministry/relocation/pending/'),
      ]);
      if (mounted) {
        setState(() {
          _buses = List<Map<String, dynamic>>.from(results[0].data);
          _zones = List<Map<String, dynamic>>.from(results[1].data);
          _relocations = List<Map<String, dynamic>>.from(results[2].data);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _decide(int relocationId, String action) async {
    try {
      await ref.read(apiClientProvider).post(
        '/api/ministry/relocation/$relocationId/decide/',
        data: {'action': action, 'valid_hours': 4},
      );
      _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(action == 'approve'
            ? '✅ Relocation approved.'
            : '❌ Relocation rejected.'),
        backgroundColor:
            action == 'approve' ? Colors.green : Colors.red,
      ));
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ministry Dashboard'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                  width: 20,
                  height: 20,
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
          tabs: [
            Tab(text: 'Live Map (${_buses.length})'),
            Tab(text: 'Zones (${_zones.length})'),
            Tab(text: 'Relocations (${_relocations.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildLiveMap(),
          _buildZones(theme),
          _buildRelocations(theme),
        ],
      ),
    );
  }

  // ── Tab 1: Live map ───────────────────────────────────────────────────────

  Widget _buildLiveMap() {
    return FlutterMap(
      options: const MapOptions(
        initialCenter: LatLng(9.03, 38.74), // Addis Ababa
        initialZoom: 12,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.smarttaxi.app',
        ),
        MarkerLayer(
          markers: _buses.map((b) {
            final lat = (b['current_latitude'] as num?)?.toDouble();
            final lng = (b['current_longitude'] as num?)?.toDouble();
            if (lat == null || lng == null) return null;
            final onRoute = b['status'] == 'on_route';
            return Marker(
              point: LatLng(lat, lng),
              width: 38,
              height: 38,
              child: Icon(
                Icons.directions_bus_rounded,
                color: onRoute ? Colors.green.shade700 : Colors.red.shade700,
                size: 30,
              ),
            );
          }).whereType<Marker>().toList(),
        ),
      ],
    );
  }

  // ── Tab 2: Zones ──────────────────────────────────────────────────────────

  Widget _buildZones(ThemeData theme) {
    if (_zones.isEmpty) {
      return const Center(child: Text('No zone data available.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _zones.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final z = _zones[i];
        final status = z['status'] as String? ?? 'OK';
        final busCount = z['bus_count'] ?? 0;
        final demandCount = z['demand_count'] ?? 0;

        final (color, icon) = switch (status) {
          'CRITICAL_LOW' => (Colors.red, Icons.warning_rounded),
          'LOW' => (Colors.orange, Icons.arrow_downward),
          'HIGH' => (Colors.blue, Icons.arrow_upward),
          _ => (Colors.green, Icons.check_circle_outline),
        };

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withAlpha(30),
              child: Icon(icon, color: color),
            ),
            title: Text(z['name'] as String? ?? '—',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                '$busCount bus${busCount == 1 ? '' : 'es'} · $demandCount demand signal${demandCount == 1 ? '' : 's'}'),
            trailing: Chip(
              label: Text(status,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold, fontSize: 12)),
              backgroundColor: color.withAlpha(30),
              side: BorderSide(color: color.withAlpha(100)),
            ),
          ),
        );
      },
    );
  }

  // ── Tab 3: Pending relocations ────────────────────────────────────────────

  Widget _buildRelocations(ThemeData theme) {
    if (_relocations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('No pending relocation requests.'),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _relocations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = _relocations[i];
        final id = r['id'] as int;
        final plate = r['driver_plate'] ?? '—';
        final from = r['from_zone_name'] ?? '—';
        final to = r['to_zone_name'] ?? '—';
        final reason = r['reason'] ?? '';
        final initiatedBy = r['initiated_by'] ?? '—';

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.directions_bus_rounded, size: 20),
                    const SizedBox(width: 6),
                    Text(plate,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Chip(
                      label: Text(initiatedBy == 'system' ? '🤖 System' : '👤 Driver',
                          style: const TextStyle(fontSize: 11)),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('$from → $to',
                    style: TextStyle(color: Colors.grey.shade600)),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(reason,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Reject'),
                        onPressed: () => _decide(id, 'reject'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.green),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Approve'),
                        onPressed: () => _decide(id, 'approve'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
