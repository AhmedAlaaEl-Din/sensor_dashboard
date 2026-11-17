import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../telemetry/models/telemetry.dart';
import '../alerts_controller.dart';
import '../alerts_screen.dart';

/// Shows the newest active alert. Hidden when there is nothing to show.
class AlertBanner extends StatelessWidget {
  const AlertBanner({super.key, this.deviceId});

  /// When set, only alerts for this device are shown.
  final String? deviceId;

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<AlertsController>();
    final list = alerts.bannerAlerts
        .where((a) => deviceId == null || a.deviceId == deviceId)
        .toList();

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: list.isEmpty ? const SizedBox(width: double.infinity) : _banner(context, alerts, list),
    );
  }

  Widget _banner(BuildContext context, AlertsController alerts, List list) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final newest = list.first;
    final more = list.length - 1;

    return Semantics(
      liveRegion: true,
      child: Material(
        key: const Key('alert-banner'),
        color: scheme.errorContainer,
        child: InkWell(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const AlertsScreen())),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${displayNameFor(newest.deviceId)}: ${newest.description}',
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (more > 0)
                        Text(
                          '+$more more active alert${more == 1 ? '' : 's'} · tap to view',
                          style: text.bodySmall?.copyWith(color: scheme.onErrorContainer),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  icon: Icon(Icons.close, color: scheme.onErrorContainer),
                  onPressed: () {
                    for (final a in list) {
                      alerts.acknowledge(a);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
