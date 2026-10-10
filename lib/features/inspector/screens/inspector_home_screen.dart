import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/api/api_service.dart';
import '../../../core/api/websocket_service.dart';
import '../../../core/models/dispatch.dart';
import '../../../core/models/bus_lookup.dart';
import '../../../core/models/violation.dart';
import '../../../core/models/zone.dart';

class InspectorHomeScreen extends ConsumerStatefulWidget {
  const InspectorHomeScreen({super.key});

  @override
  ConsumerState<InspectorHomeScreen> createState() =>
      _InspectorHomeScreenState();
}

class _InspectorHomeScreenState extends ConsumerState<InspectorHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final WebSocketService _ws;
  StreamSubscription? _wsSub;

  final _plateCtrl = TextEditingController();
  List<InspectorDispatch> _dispatches = [];
  bool _loadingDispatches = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _ws = WebSocketService(wsBaseUrl: kWsBaseUrl);
    _loadDispatches();
    _connectWs();
  }

  Future<void> _connectWs() async {
    await _ws.connect();
    _wsSub = _ws.messages.listen((msg) {
      if (msg['type'] == 'dispatch' && mounted) {
        _loadDispatches();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🚨 New dispatch: bus ${msg['plate']}'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 8),
        ));
      }
    });
  }

  Future<void> _loadDispatches() async {
    setState(() => _loadingDispatches = true);
    try {
      final list = await ref.read(apiServiceProvider).getMyDispatches();
      if (!mounted) return;
      setState(() => _dispatches = list);
    } catch (_) {}
    if (mounted) setState(() => _loadingDispatches = false);
  }

  Future<void> _respond(int dispatchId, String action) async {
    try {
      await ref.read(apiServiceProvider).respondToDispatch(dispatchId, action);
      _loadDispatches();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _lookupPlate() async {
    final plate = _plateCtrl.text.trim().toUpperCase();
    if (plate.isEmpty) return;
    FocusScope.of(context).unfocus();
    try {
      final result = await ref.read(apiServiceProvider).busLookup(plate);
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _BusInfoSheet(
          lookup: result,
          apiService: ref.read(apiServiceProvider),
          zones: const [],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Not found: ${_friendlyError(e)}')),
      );
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('404')) return 'No bus with that plate number.';
    if (s.contains('SocketException')) return 'Cannot reach server.';
    return s;
  }

  @override
  void dispose() {
    _tabs.dispose();
    _wsSub?.cancel();
    _ws.dispose();
    _plateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspector'),
        actions: [
          IconButton(
            icon: const Icon(Icons.note_add_outlined),
            tooltip: 'Field observation',
            onPressed: () => _showObservationSheet(),
          ),
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
            Tab(
              icon: const Icon(Icons.search),
              text: 'Plate Lookup',
            ),
            Tab(
              icon: Badge(
                isLabelVisible: _dispatches.isNotEmpty,
                label: Text('${_dispatches.length}'),
                child: const Icon(Icons.notifications_active_outlined),
              ),
              text: 'Dispatches',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildLookupTab(),
          _buildDispatchesTab(),
        ],
      ),
    );
  }

  // ── Tab 1: Plate lookup ───────────────────────────────────────────────────

  Widget _buildLookupTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _plateCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Enter or scan plate number',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _lookupPlate(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _lookupPlate,
              child: const Text('Lookup'),
            ),
          ]),
          const SizedBox(height: 20),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_car_outlined,
                      size: 72,
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withAlpha(80)),
                  const SizedBox(height: 12),
                  const Text(
                    'Enter a plate number above to see\nstatus, route, compliance score\nand active relocation permits.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Dispatches ─────────────────────────────────────────────────────

  Widget _buildDispatchesTab() {
    if (_loadingDispatches) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_dispatches.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline,
              size: 64, color: Colors.green.shade300),
          const SizedBox(height: 12),
          const Text('No pending dispatches'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loadDispatches,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadDispatches,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _dispatches.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final d = _dispatches[i];
          return _DispatchCard(
            dispatch: d,
            onRespond: (action) => _respond(d.id, action),
            onLookup: () {
              final plate = d.violation?.driverPlate ?? '';
              if (plate.isEmpty) return;
              _plateCtrl.text = plate;
              _tabs.animateTo(0);
              _lookupPlate();
            },
          );
        },
      ),
    );
  }

  // ── Sheets ────────────────────────────────────────────────────────────────

  void _showObservationSheet() async {
    List<Zone> zones = [];
    try {
      final raw = await ref.read(apiServiceProvider).getZonesList();
      zones = raw
          .map((z) => Zone(
                id: z['id'] as int,
                name: z['name'] as String,
                centerLatitude: 0,
                centerLongitude: 0,
                radiusKm: 2,
              ))
          .toList();
    } catch (_) {}
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FieldObservationSheet(
        apiService: ref.read(apiServiceProvider),
        zones: zones,
      ),
    );
  }
}

// ─── Dispatch Card ────────────────────────────────────────────────────────────

class _DispatchCard extends StatelessWidget {
  final InspectorDispatch dispatch;
  final void Function(String action) onRespond;
  final VoidCallback onLookup;

  const _DispatchCard({
    required this.dispatch,
    required this.onRespond,
    required this.onLookup,
  });

  @override
  Widget build(BuildContext context) {
    final v = dispatch.violation;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: Colors.orange.shade100,
                child: const Icon(Icons.warning_amber_rounded,
                    color: Colors.orange),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v != null ? 'Plate: ${v.driverPlate}' : 'Dispatch #${dispatch.id}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      if (v != null)
                        Text(
                          'Route: ${v.routeName ?? '—'}  •  ${v.shortDate}',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.outline),
                        ),
                    ]),
              ),
              if (dispatch.autoDispatched)
                Chip(
                  label: const Text('Auto', style: TextStyle(fontSize: 10)),
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.blue.shade50,
                ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onLookup,
                  icon: const Icon(Icons.search, size: 16),
                  label: const Text('Lookup Plate'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: dispatch.status == 'sent'
                    ? FilledButton(
                        onPressed: () => onRespond('acknowledge'),
                        child: const Text('Acknowledge'),
                      )
                    : FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.green),
                        icon: const Icon(Icons.check, size: 16),
                        onPressed: () => onRespond('complete'),
                        label: const Text('Complete'),
                      ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ─── Bus Info Sheet ───────────────────────────────────────────────────────────

class _BusInfoSheet extends StatefulWidget {
  final BusLookup lookup;
  final ApiService apiService;
  final List<Zone> zones;

  const _BusInfoSheet({
    required this.lookup,
    required this.apiService,
    required this.zones,
  });

  @override
  State<_BusInfoSheet> createState() => _BusInfoSheetState();
}

class _BusInfoSheetState extends State<_BusInfoSheet> {
  bool _recording = false;
  final _notesCtrl = TextEditingController();

  Future<void> _record(String action) async {
    setState(() => _recording = true);
    try {
      await widget.apiService.recordViolation(
        plateNumber: widget.lookup.licensePlate,
        action: action,
        notes: _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(action == 'confirm'
            ? '✅ Violation confirmed. Score updated.'
            : '✅ Violation dismissed.'),
        backgroundColor:
            action == 'confirm' ? Colors.orange : Colors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.lookup;
    final theme = Theme.of(context);
    final scoreColor = b.complianceScore >= 80
        ? Colors.green
        : b.complianceScore >= 60
            ? Colors.orange
            : Colors.red;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.directions_bus_rounded, size: 28),
            const SizedBox(width: 10),
            Text(b.licensePlate,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            Chip(
              label: Text(b.status.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(fontSize: 11)),
              backgroundColor: b.status == 'on_route'
                  ? Colors.green.shade50
                  : Colors.red.shade50,
              side: BorderSide(
                  color: b.status == 'on_route'
                      ? Colors.green.shade200
                      : Colors.red.shade200),
            ),
          ]),
          const SizedBox(height: 16),
          _Row('Driver', b.username),
          _Row('Route', b.assignedRoute ?? 'No route assigned'),
          Row(children: [
            const SizedBox(
              width: 120,
              child: Text('Compliance:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(
              '${b.complianceScore} / 100',
              style: TextStyle(
                  color: scoreColor, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: b.complianceScore / 100,
              backgroundColor: Colors.grey.shade200,
              color: scoreColor,
              minHeight: 8,
            ),
          ),

          // Active relocation permit
          if (b.activeRelocation != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border.all(color: Colors.green.shade200),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('✅ Active Relocation Permit',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green)),
                    const SizedBox(height: 4),
                    _Row('Zone', b.activeRelocation!.toZone),
                    _Row('Valid until', b.activeRelocation!.validUntil),
                  ]),
            ),
          ],

          // Recent violations
          if (b.recentViolations.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Recent Violations (${b.recentViolations.length})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...b.recentViolations.take(5).map((v) => _ViolationTile(v)),
          ],

          // Record violation
          const Divider(height: 28),
          Text('Record Violation',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextFormField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style:
                    OutlinedButton.styleFrom(foregroundColor: Colors.green),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                onPressed: _recording ? null : () => _record('dismiss'),
                label: const Text('Dismiss'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade600),
                icon: const Icon(Icons.gavel, size: 18),
                onPressed: _recording ? null : () => _record('confirm'),
                label: _recording
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Confirm'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 120,
              child: Text('$label:',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ]),
      );
}

class _ViolationTile extends StatelessWidget {
  final RouteViolation v;
  const _ViolationTile(this.v);

  @override
  Widget build(BuildContext context) {
    final color = v.status == 'confirmed'
        ? Colors.red
        : v.status == 'dismissed'
            ? Colors.grey
            : Colors.orange;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(Icons.circle, color: color, size: 10),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              '${v.status.toUpperCase()} — ${v.routeName ?? '—'} — ${v.shortDate}',
              style: const TextStyle(fontSize: 13)),
        ),
      ]),
    );
  }
}

// ─── Field Observation Sheet ──────────────────────────────────────────────────

class _FieldObservationSheet extends StatefulWidget {
  final ApiService apiService;
  final List<Zone> zones;
  const _FieldObservationSheet(
      {required this.apiService, required this.zones});

  @override
  State<_FieldObservationSheet> createState() =>
      _FieldObservationSheetState();
}

class _FieldObservationSheetState extends State<_FieldObservationSheet> {
  int? _selectedZoneId;
  String _type = 'bus_not_stopping';
  final _plateCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _loading = false;
  bool _done = false;

  // Values must match InspectorFieldObservation.TYPE_CHOICES in the backend.
  static const _types = [
    ('bus_not_stopping', 'Bus on route but not stopping'),
    ('stop_abandoned',   'Bus stop abandoned'),
    ('gps_disabled',     'Driver GPS disabled'),
    ('overcrowding',     'Overcrowding at stop'),
    ('undercrowding',    'Very low demand at stop'),
    ('fare_violation',   'Fare violation observed'),
    ('other',            'Other observation'),
  ];

  Future<void> _submit() async {
    if (_selectedZoneId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a zone.')));
      return;
    }
    setState(() => _loading = true);
    try {
      await widget.apiService.submitFieldObservation(
        zoneId: _selectedZoneId!,
        observationType: _type,
        lat: 9.03,
        lng: 38.74,
        plateNumber: _plateCtrl.text.trim().toUpperCase(),
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
              title: 'Observation Filed!',
              message: 'Your field report has been sent to the Ministry.',
              onClose: () => Navigator.pop(context),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Field Observation',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  value: _selectedZoneId,
                  hint: const Text('Select zone'),
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
                    labelText: 'Observation type',
                    prefixIcon: Icon(Icons.remove_red_eye_outlined),
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
                  controller: _plateCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Plate number (if applicable)',
                    prefixIcon: Icon(Icons.directions_car_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
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
                        : const Text('Submit Observation'),
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
  Widget build(BuildContext context) => Column(
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
