import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/websocket_service.dart';

/// Inspector shell.
/// - Plate lookup bar → shows full bus info dialog.
/// - Pending dispatch list with acknowledge / complete actions.
/// - WebSocket receives real-time dispatch alerts.
class InspectorHomeScreen extends ConsumerStatefulWidget {
  const InspectorHomeScreen({super.key});

  @override
  ConsumerState<InspectorHomeScreen> createState() =>
      _InspectorHomeScreenState();
}

class _InspectorHomeScreenState extends ConsumerState<InspectorHomeScreen> {
  late final WebSocketService _ws;
  StreamSubscription? _wsSub;
  final _plateCtrl = TextEditingController();
  List<Map<String, dynamic>> _dispatches = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ws = WebSocketService(wsBaseUrl: kWsBaseUrl);
    _loadDispatches();
    _connectWs();
  }

  Future<void> _connectWs() async {
    await _ws.connect();
    _wsSub = _ws.messages.listen((msg) {
      if (msg['type'] == 'dispatch') {
        _loadDispatches();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🚨 New dispatch: bus ${msg['plate']}'),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 8),
            ),
          );
        }
      }
    });
  }

  Future<void> _loadDispatches() async {
    setState(() => _loading = true);
    try {
      final resp =
          await ref.read(apiClientProvider).get('/api/inspector/dispatches/');
      if (!mounted) return;
      setState(() =>
          _dispatches = List<Map<String, dynamic>>.from(resp.data));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _lookupPlate() async {
    final plate = _plateCtrl.text.trim().toUpperCase();
    if (plate.isEmpty) return;
    FocusScope.of(context).unfocus();
    try {
      final resp = await ref
          .read(apiClientProvider)
          .get('/api/inspector/bus/$plate/');
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => _BusInfoDialog(
          data: resp.data as Map<String, dynamic>,
          apiClient: ref.read(apiClientProvider),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Not found: $e')));
    }
  }

  Future<void> _respond(int dispatchId, String action) async {
    try {
      await ref.read(apiClientProvider).patch(
        '/api/inspector/dispatches/$dispatchId/respond/',
        data: {'action': action},
      );
      _loadDispatches();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _ws.dispose();
    _plateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspector'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadDispatches),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Plate lookup ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _plateCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Enter plate number',
                      prefixIcon: Icon(Icons.search),
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
              ],
            ),
          ),

          // ── Section header ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Pending Dispatches',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Dispatch list ──────────────────────────────────────────────
          Expanded(
            child: _dispatches.isEmpty && !_loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 64, color: Colors.green.shade300),
                        const SizedBox(height: 12),
                        const Text('No pending dispatches'),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _dispatches.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final d = _dispatches[i];
                      final id = d['id'] as int;
                      final plate =
                          d['violation']?['driver_plate'] ?? '—';
                      final route =
                          d['violation']?['route_name'] ?? '—';
                      final status = d['status'] ?? '—';
                      final autoDisp =
                          d['auto_dispatched'] as bool? ?? false;

                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.orange.shade100,
                            child: const Icon(Icons.warning_amber_rounded,
                                color: Colors.orange),
                          ),
                          title: Text('Plate: $plate',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Route: $route'),
                              Text('Status: $status'),
                              if (autoDisp)
                                const Text('🤖 Auto-dispatched',
                                    style:
                                        TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (a) => _respond(id, a),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'acknowledge',
                                  child: Row(children: [
                                    Icon(Icons.thumb_up_outlined, size: 18),
                                    SizedBox(width: 8),
                                    Text('Acknowledge'),
                                  ])),
                              PopupMenuItem(
                                  value: 'complete',
                                  child: Row(children: [
                                    Icon(Icons.check_circle_outline, size: 18),
                                    SizedBox(width: 8),
                                    Text('Complete'),
                                  ])),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Bus info dialog ─────────────────────────────────────────────────────────

class _BusInfoDialog extends StatefulWidget {
  final Map<String, dynamic> data;
  final ApiClient apiClient;
  const _BusInfoDialog({required this.data, required this.apiClient});

  @override
  State<_BusInfoDialog> createState() => _BusInfoDialogState();
}

class _BusInfoDialogState extends State<_BusInfoDialog> {
  bool _recording = false;

  Future<void> _recordViolation(String action) async {
    setState(() => _recording = true);
    try {
      await widget.apiClient.post('/api/inspector/violations/record/', data: {
        'plate_number': widget.data['license_plate'],
        'action': action,
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(action == 'confirm'
                ? '✅ Violation confirmed. Compliance score updated.'
                : '✅ Violation dismissed.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final plate = d['license_plate'] ?? '—';
    final status = d['status'] ?? '—';
    final route = d['assigned_route'] ?? 'No route';
    final score = d['compliance_score'] ?? '—';
    final relocation = d['active_relocation'] as Map<String, dynamic>?;
    final violations = d['recent_violations'] as List? ?? [];

    final scoreInt = score is int ? score : int.tryParse('$score') ?? 100;
    final scoreColor = scoreInt >= 80
        ? Colors.green
        : scoreInt >= 60
            ? Colors.orange
            : Colors.red;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.directions_bus_rounded),
          const SizedBox(width: 8),
          Text('Bus $plate'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _row('Status', status),
            _row('Route', route.toString()),
            Row(
              children: [
                const SizedBox(width: 0, child: Text('')),
                Expanded(
                  child: Row(
                    children: [
                      const Text('Compliance: ',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '$score / 100',
                        style: TextStyle(
                            color: scoreColor, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (relocation != null) ...[
              const Divider(height: 20),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('✅ Active Relocation Permit',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green)),
                    const SizedBox(height: 4),
                    _row('Zone', relocation['to_zone'].toString()),
                    _row('Valid until', relocation['valid_until'].toString()),
                  ],
                ),
              ),
            ],
            if (violations.isNotEmpty) ...[
              const Divider(height: 20),
              Text('Recent Violations (${violations.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ...violations.take(3).map((v) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                        '• ${v['status']} — ${v['detected_at']?.toString().substring(0, 10) ?? ''}',
                        style: const TextStyle(fontSize: 13)),
                  )),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        OutlinedButton.icon(
          onPressed: _recording ? null : () => _recordViolation('dismiss'),
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Dismiss'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: _recording ? null : () => _recordViolation('confirm'),
          icon: const Icon(Icons.gavel, size: 18),
          label: const Text('Confirm'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text('$label:',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}
