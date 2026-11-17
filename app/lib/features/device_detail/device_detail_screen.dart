import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/relative_time_text.dart';
import '../../core/widgets/state_views.dart';
import '../alerts/alerts_controller.dart';
import '../alerts/widgets/alert_banner.dart';
import '../connection/widgets/connection_status_bar.dart';
import '../telemetry/device_store.dart';
import '../telemetry/models/sensor_type.dart';
import '../telemetry/models/telemetry.dart';
import '../telemetry/stats.dart';
import 'widgets/sensor_chart.dart';

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({super.key, required this.deviceId});
  final String deviceId;

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  SensorType _sensor = SensorType.temperature;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeviceStore>();
    final thresholds = context.watch<AlertsController>().thresholds;
    final device = store.device(widget.deviceId);

    return Scaffold(
      appBar: AppBar(title: Text(displayNameFor(widget.deviceId))),
      body: Column(
        children: [
          const ConnectionStatusBar(),
          AlertBanner(deviceId: widget.deviceId),
          Expanded(
            child: device == null
                ? const MessageView(
                    icon: Icons.sensors_off_outlined,
                    title: 'Device not available',
                    body:
                        'This device is no longer reporting. '
                        'It may be under a different topic prefix.',
                  )
                : device.latest == null
                ? const LoadingView(message: 'Waiting for the first reading…')
                : _content(context, device, thresholds),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, DeviceState device, Map thresholds) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final history = device.history.toList();
    final stats = device.statsFor(_sensor);
    final latest = device.latestValue(_sensor);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<SensorType>(
            showSelectedIcon: false,
            segments: [
              for (final s in SensorType.values)
                ButtonSegment(value: s, label: Text(s.label), tooltip: s.label),
            ],
            selected: {_sensor},
            onSelectionChanged: (sel) => setState(() => _sensor = sel.first),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              latest == null ? '—' : latest.toStringAsFixed(_sensor.decimals),
              key: const Key('detail-current-value'),
              style: text.displaySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_sensor.unit, style: text.titleMedium),
            ),
            const Spacer(),
            RelativeTimeText(
              device.lastUpdate,
              prefix: 'Updated ',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 16, 8),
            child: SensorChart(
              key: ValueKey(_sensor),
              sensor: _sensor,
              history: history,
              threshold: thresholds[_sensor],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _StatsRow(sensor: _sensor, stats: stats),
        const SizedBox(height: 8),
        Text(
          'Statistics cover the last ${stats?.count ?? 0} of up to $historyLength readings.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.sensor, required this.stats});
  final SensorType sensor;
  final SensorStats? stats;

  @override
  Widget build(BuildContext context) {
    String f(double? v) => v == null ? '—' : sensor.format(v);
    return Row(
      children: [
        Expanded(
          child: _StatTile(label: 'Min', value: f(stats?.min), keyName: 'stat-min'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(label: 'Average', value: f(stats?.average), keyName: 'stat-avg'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(label: 'Max', value: f(stats?.max), keyName: 'stat-max'),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.keyName});
  final String label;
  final String value;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(label, style: text.labelMedium),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                value,
                key: Key(keyName),
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
