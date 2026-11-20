import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../settings/settings_screen.dart';
import 'auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final ok = await context.read<AuthController>().signIn(_email.text, _password.text);
    if (!ok && mounted) _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final message = auth.error ?? auth.notice;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.sensors, size: 56, color: scheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        'Sensor Dashboard',
                        textAlign: TextAlign.center,
                        style: text.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sign in to see live data and history',
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 28),
                      if (message != null) ...[
                        Material(
                          key: const Key('login-message'),
                          color: auth.error != null
                              ? scheme.errorContainer
                              : scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  auth.error != null ? Icons.error_outline : Icons.info_outline,
                                  color: auth.error != null
                                      ? scheme.onErrorContainer
                                      : scheme.onSecondaryContainer,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    message,
                                    style: TextStyle(
                                      color: auth.error != null
                                          ? scheme.onErrorContainer
                                          : scheme.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        key: const Key('login-email'),
                        controller: _email,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isEmpty) return 'Enter your email';
                          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
                            return 'That does not look like an email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('login-password'),
                        controller: _password,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Show password' : 'Hide password',
                            icon: Icon(
                              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('login-submit'),
                        onPressed: auth.isBusy ? null : _submit,
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        child: auth.isBusy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : const Text('Sign in'),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        key: const Key('login-server-settings'),
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                        icon: const Icon(Icons.dns_outlined),
                        label: const Text('Server settings'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
