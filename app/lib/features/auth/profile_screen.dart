import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'auth_controller.dart';
import 'models/session.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final session = auth.session;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: session == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 36,
                    backgroundColor: scheme.primaryContainer,
                    child: Text(
                      session.email.substring(0, 1).toUpperCase(),
                      style: text.headlineMedium?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(child: Text(session.email, style: text.titleMedium)),
                const SizedBox(height: 8),
                Center(
                  child: Chip(
                    key: const Key('profile-role'),
                    avatar: Icon(
                      session.isAdmin
                          ? Icons.admin_panel_settings_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    label: Text(session.role.label),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.verified_user_outlined),
                        title: const Text('What you can do'),
                        subtitle: Text(_permissions(session.role)),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.timer_outlined),
                        title: const Text('Session'),
                        subtitle: Text(
                          'Signs you out automatically at ${DateFormat.Hm().format(session.expiresAt.toLocal())}',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  key: const Key('profile-sign-out'),
                  onPressed: () => context.read<AuthController>().signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ],
            ),
    );
  }

  static String _permissions(UserRole role) => switch (role) {
    UserRole.admin => 'View live data and history, export CSV, change alert thresholds.',
    UserRole.viewer => 'View live data and history, export CSV. Thresholds are read-only.',
  };
}
