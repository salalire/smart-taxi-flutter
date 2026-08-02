import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(authProvider.notifier)
        .login(_userCtrl.text.trim(), _passCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header ────────────────────────────────────────────────
                  Icon(Icons.directions_bus_rounded, size: 80, color: cs.primary),
                  const SizedBox(height: 12),
                  Text('Smart Taxi', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Ethiopian Minibus Monitoring', style: theme.textTheme.bodyMedium?.copyWith(color: cs.outline)),
                  const SizedBox(height: 40),

                  // ── Username ──────────────────────────────────────────────
                  TextFormField(
                    controller: _userCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),

                  // ── Password ──────────────────────────────────────────────
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),

                  // ── Error ─────────────────────────────────────────────────
                  if (authState.hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(
                        _friendlyError(authState.error.toString()),
                        style: TextStyle(color: cs.error),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 16),

                  // ── Login button ──────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: authState.isLoading ? null : _submit,
                      child: authState.isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Log In', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Register link ─────────────────────────────────────────
                  TextButton(
                    onPressed: () => context.go('/register'),
                    child: const Text("Don't have an account? Register"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _friendlyError(String raw) {
    if (raw.contains('401') || raw.contains('No active account')) {
      return 'Invalid username or password.';
    }
    if (raw.contains('SocketException') || raw.contains('connection')) {
      return 'Cannot reach the server. Check your connection.';
    }
    return 'Login failed. Please try again.';
  }
}
