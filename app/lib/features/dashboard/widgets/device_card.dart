import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/relative_time_text.dart';
import '../../alerts/models/alert_models.dart';
import '../../telemetry/device_store.dart';
import '../../telemetry/models/sensor_type.dart';
import 'sensor_gauge.dart';

/// One card per device: status, last update, and a gauge per sensor.
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.device,
    required this.thresholds,
    required this.live,
    this.onTap,
  });

  final DeviceState device;
  final Map<SensorType, SensorThreshold> thresholds;

  /// False when the app is not connected; values are shown as stale.
  final bool live;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final stale = !live || device.online == false;

    final (String chipLabel, Color chipColor) = !live
        ? ('No connection', scheme.outline)
        : switch (device.online) {
            true => ('Online', scheme.ok),
            false => ('Offline', scheme.error),
            null => ('Unknown', scheme.outline),
          };

    return Card(
      key: Key('device-card-${device.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(device.displayName, style: text.titleMedium),
                        const SizedBox(height: 2),
                        RelativeTimeText(
                          device.lastUpdate,
                          prefix: 'Updated ',
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(label: chipLabel, color: chipColor),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 12),
              if (device.latest == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    device.online == false
                        ? 'Device is offline. No readings yet.'
                        : 'Waiting for the first reading…',
                    style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final perRow = constraints.maxWidth >= 400 ? 4 : 2;
                    final width = constraints.maxWidth / perRow;
                    return Wrap(
                      runSpacing: 8,
                      children: [
                        for (final s in SensorType.values)
                          SizedBox(
                            width: width,
                            child: Center(
                              child: SensorGauge(
                                sensor: s,
                                value: device.latestValue(s),
                                threshold: thresholds[s],
                                dimmed: stale,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}
