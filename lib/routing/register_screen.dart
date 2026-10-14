import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_provider.dart';
import '../core/api/api_service.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _user  = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass  = TextEditingController();
  final _pass2 = TextEditingController();
  final _plate = TextEditingController(); // driver only
  final _badge = TextEditingController(); // inspector only

  String _role = 'passenger';
  bool   _loading = false;
  String? _error;

  // Driver route picker
  List<Map<String, dynamic>> _routes = [];
  int?   _selectedRouteId;
  bool   _routesLoading = false;

  // Inspector zone picker
  List<Map<String, dynamic>> _zones = [];
  int?   _selectedZoneId;
  bool   _zonesLoading = false;

  static const _roles = [
    _RoleOption('driver',    'Driver',    Icons.directions_bus_rounded),
    _RoleOption('passenger', 'Passenger', Icons.person_outlined),
    _RoleOption('inspector', 'Inspector', Icons.shield_outlined),
  ];

  @override
  void dispose() {
    for (final c in [_user, _email, _phone, _pass, _pass2, _plate, _badge]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    setState(() { _routesLoading = true; _error = null; });
    try {
      final client = ref.read(apiClientProvider);
      final resp = await client.get('/api/driver/routes/');
      final list = resp.data as List;
      setState(() => _routes = list.cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load routes: $e');
    } finally {
      if (mounted) setState(() => _routesLoading = false);
    }
  }

  Future<void> _loadZones() async {
    setState(() { _zonesLoading = true; _error = null; });
    try {
      final list = await ref.read(apiServiceProvider).getZonesList();
      setState(() => _zones = list);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load zones: $e');
    } finally {
      if (mounted) setState(() => _zonesLoading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_role == 'driver' && _selectedRouteId == null) {
      setState(() => _error = 'Please select a route.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final auth = ref.read(authServiceProvider);
      await auth.register(
        username:     _user.text.trim(),
        email:        _email.text.trim(),
        phone:        _phone.text.trim(),
        role:         _role,
        password:     _pass.text,
        password2:    _pass2.text,
        licensePlate: _role == 'driver'    ? _plate.text.trim() : null,
        badgeNumber:  _role == 'inspector' ? _badge.text.trim() : null,
        assignedRoute: _role == 'driver'    ? _selectedRouteId  : null,
        assignedZone:  _role == 'inspector' ? _selectedZoneId   : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created! Please log in.')),
        );
        context.go('/login');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(_user,  'Username', Icons.person_outline),
                const SizedBox(height: 14),
                _field(_email, 'Email',    Icons.email_outlined,
                    type: TextInputType.emailAddress),
                const SizedBox(height: 14),
                _field(_phone, 'Phone',    Icons.phone_outlined,
                    type: TextInputType.phone),
                const SizedBox(height: 14),
                _field(_pass,  'Password', Icons.lock_outline, obscure: true),
                const SizedBox(height: 14),
                _field(_pass2, 'Confirm Password', Icons.lock_outline,
                    obscure: true),
                const SizedBox(height: 20),

                // ── Role selector ────────────────────────────────────────
                Text('Select your role',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(
                  children: _roles.map((r) {
                    final selected = _role == r.value;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _role = r.value;
                            _selectedRouteId = null;
                            _selectedZoneId  = null;
                          });
                          if (r.value == 'driver' && _routes.isEmpty) {
                            _loadRoutes();
                          }
                          if (r.value == 'inspector' && _zones.isEmpty) {
                            _loadZones();
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: selected
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? theme.colorScheme.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Column(children: [
                            Icon(r.icon,
                                color: selected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline),
                            const SizedBox(height: 4),
                            Text(r.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: selected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface,
                                )),
                          ]),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                // ── Driver fields ────────────────────────────────────────
                if (_role == 'driver') ...[
                  const SizedBox(height: 14),
                  _field(_plate, 'License Plate (e.g. AA-12345)',
                      Icons.directions_car_outlined),
                  const SizedBox(height: 14),
                  _routesLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _routes.isEmpty
                          ? OutlinedButton.icon(
                              onPressed: _loadRoutes,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Load available routes'),
                            )
                          : DropdownButtonFormField<int>(
                              value: _selectedRouteId,
                              decoration: const InputDecoration(
                                labelText: 'Assign Route',
                                prefixIcon: Icon(Icons.route_outlined),
                              ),
                              items: _routes
                                  .map((r) => DropdownMenuItem<int>(
                                        value: r['id'] as int,
                                        child: Text(r['name'] as String? ?? '—'),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selectedRouteId = v),
                              validator: (_) => _selectedRouteId == null
                                  ? 'Select a route'
                                  : null,
                            ),
                ],

                // ── Inspector fields ─────────────────────────────────────
                if (_role == 'inspector') ...[
                  const SizedBox(height: 14),
                  _field(_badge, 'Badge Number', Icons.shield_outlined),
                  const SizedBox(height: 14),
                  _zonesLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _zones.isEmpty
                          ? OutlinedButton.icon(
                              onPressed: _loadZones,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Load available zones'),
                            )
                          : DropdownButtonFormField<int>(
                              value: _selectedZoneId,
                              decoration: const InputDecoration(
                                labelText: 'Assigned Zone (optional)',
                                prefixIcon:
                                    Icon(Icons.location_city_outlined),
                              ),
                              items: [
                                const DropdownMenuItem<int>(
                                  value: null,
                                  child: Text('No zone assigned'),
                                ),
                                ..._zones.map((z) => DropdownMenuItem<int>(
                                      value: z['id'] as int,
                                      child: Text(z['name'] as String? ?? '—'),
                                    )),
                              ],
                              onChanged: (v) =>
                                  setState(() => _selectedZoneId = v),
                            ),
                ],

                // ── Error ────────────────────────────────────────────────
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ),

                const SizedBox(height: 28),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Register',
                            style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Already have an account? Log In'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType? type,
    bool obscure = false,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
    );
  }
}

class _RoleOption {
  final String value;
  final String label;
  final IconData icon;
  const _RoleOption(this.value, this.label, this.icon);
}
