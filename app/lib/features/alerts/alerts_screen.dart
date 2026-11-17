import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/state_views.dart';
import '../telemetry/models/telemetry.dart';
import 'alerts_controller.dart';
import 'models/alert_models.dart';

/// Alert history, newest first.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<AlertsController>();
    final history = alerts.history;
    final hasResolved = history.any((a) => !a.isActive);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          if (hasResolved)
            TextButton(
              onPressed: alerts.clearResolved,
              child: const Text('Clear resolved'),
            ),
        ],
      ),
      body: history.isEmpty
          ? const MessageView(
              key: Key('alerts-empty'),
              icon: Icons.notifications_none_outlined,
              title: 'No alerts yet',
              body: 'You will see an alert here when a reading goes outside the '
                  'thresholds set in Settings.',
            )
          : ListView.separated(
              itemCount: history.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _AlertTile(alert: history[i]),
            ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});
  final AlertEvent alert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = DateFormat.Hms();
    final active = alert.isActive;
    return ListTile(
      leading: Icon(
        alert.direction == AlertDirection.high ? Icons.arrow_upward : Icons.arrow_downward,
        color: active ? scheme.error : scheme.onSurfaceVariant,
      ),
      title: Text('${displayNameFor(alert.deviceId)} · ${alert.sensor.label}'),
      subtitle: Text(
        '${alert.description}\n'
        'Triggered ${time.format(alert.triggeredAt)}'
        '${alert.resolvedAt != null ? ' · back to normal ${time.format(alert.resolvedAt!)}' : ''}',
      ),
      isThreeLine: true,
      trailing: Chip(
        label: Text(active ? 'Active' : 'Resolved'),
        visualDensity: VisualDensity.compact,
        backgroundColor: active ? scheme.errorContainer : null,
        labelStyle: TextStyle(color: active ? scheme.onErrorContainer : null),
        side: BorderSide.none,
      ),
    );
  }
}
