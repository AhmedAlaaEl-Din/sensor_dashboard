import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/widgets/state_views.dart';
import '../alerts/alerts_controller.dart';
import '../alerts/models/alert_models.dart';
import '../telemetry/models/sensor_type.dart';
import '../telemetry/models/telemetry.dart';
import 'csv_exporter.dart';
import 'history_controller.dart';
import 'history_models.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.deviceId});
  final String deviceId;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final HistoryController _controller;
  SensorType _sensor = SensorType.temperature;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _controller = HistoryController(deviceId: widget.deviceId, api: context.read<ApiClient>())
      ..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final exporter = context.read<CsvExporter>();
    final sharer = context.read<FileSharer>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final result = await exporter.export(widget.deviceId, _controller.range);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const Key('export-dialog'),
          icon: const Icon(Icons.task_alt),
          title: const Text('CSV ready'),
          content: Text(
            '${NumberFormat.decimalPattern().format(result.rows)} rows · last ${_controller.range.label}\n'
            '${result.fileName}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
            FilledButton.icon(
              key: const Key('export-share'),
              onPressed: () {
                Navigator.pop(ctx);
                sharer.shareFile(
                  result.file.path,
                  subject: 'Sensor data: ${displayNameFor(widget.deviceId)}',
                );
              },
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share…'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final thresholds = context.watch<AlertsController>().thresholds;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        return Scaffold(
          appBar: AppBar(
            title: Text('${displayNameFor(widget.deviceId)} history'),
            actions: [
              TextButton.icon(
                key: const Key('history-export'),
                onPressed: _exporting || c.data == null || c.data!.isEmpty ? null : _export,
                icon: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: const Text('Export CSV'),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: c.load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                SegmentedButton<HistoryRange>(
                  segments: [
                    for (final r in HistoryRange.values)
                      ButtonSegment(
                        value: r,
                        label: Text(r.label, key: Key('range-${r.name}')),
                      ),
                  ],
                  selected: {c.range},
                  onSelectionChanged: (s) => c.setRange(s.first),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in SensorType.values)
                      ChoiceChip(
                        label: Text(s.label),
                        selected: _sensor == s,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _sensor = s),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ..._body(context, c, thresholds[_sensor]),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _body(BuildContext context, HistoryController c, SensorThreshold? threshold) {
    final data = c.data;
    if (data == null && c.isLoading) {
      return const [SizedBox(height: 320, child: LoadingView(message: 'Loading history…'))];
    }
    if (data == null && c.error != null) {
      return [
        SizedBox(
          height: 360,
          child: MessageView(
            key: const Key('history-error'),
            icon: Icons.cloud_off_outlined,
            isError: true,
            title: "Couldn't load history",
            body: c.error,
            actions: [
              FilledButton.icon(
                onPressed: c.load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ];
    }
    if (data == null) return const [];
    if (data.isEmpty) {
      return [
        SizedBox(
          height: 320,
          child: MessageView(
            key: const Key('history-empty'),
            icon: Icons.history_toggle_off,
            title: 'No history for this period',
            body: 'Readings are stored while the server is running. Try a longer range or check back later.',
          ),
        ),
      ];
    }

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final stat = data.stats[_sensor];
    String f(double? v) => v == null ? '—' : _sensor.format(v);
    return [
      if (c.isLoading) const LinearProgressIndicator(minHeight: 2),
      if (c.error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(c.error!, style: text.bodySmall?.copyWith(color: scheme.error)),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 16, 8),
          child: HistoryChart(
            key: ValueKey('${c.range}-$_sensor'),
            points: data.points,
            sensor: _sensor,
            range: c.range,
            threshold: threshold,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _Stat(label: 'Min', value: f(stat?.min), keyName: 'history-min'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Stat(label: 'Average', value: f(stat?.avg), keyName: 'history-avg'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Stat(label: 'Max', value: f(stat?.max), keyName: 'history-max'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        '${NumberFormat.decimalPattern().format(stat?.count ?? 0)} readings · chart shows ${c.range.bucketLabel}. '
        'Pull down to refresh.',
        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    ];
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.keyName});
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

/// Line chart over wall-clock time (x = epoch milliseconds).
class HistoryChart extends StatelessWidget {
  const HistoryChart({
    super.key,
    required this.points,
    required this.sensor,
    required this.range,
    this.threshold,
  });

  final List<HistoryPoint> points;
  final SensorType sensor;
  final HistoryRange range;
  final SensorThreshold? threshold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final spots = [
      for (final p in points)
        if (p.values[sensor] != null)
          FlSpot(p.time.millisecondsSinceEpoch.toDouble(), p.values[sensor]!),
    ];
    if (spots.isEmpty) {
      return SizedBox(
        height: 220,
        child: Center(child: Text('No ${sensor.label.toLowerCase()} data in this period')),
      );
    }

    final ys = spots.map((s) => s.y);
    var minY = ys.reduce(math.min);
    var maxY = ys.reduce(math.max);
    final pad = math.max((maxY - minY) * 0.15, 0.5);
    minY -= pad;
    maxY += pad;

    final lines = <HorizontalLine>[
      for (final (y, label) in [(threshold?.max, 'max'), (threshold?.min, 'min')])
        if (y != null && y >= minY && y <= maxY)
          HorizontalLine(
            y: y,
            color: scheme.error.withValues(alpha: 0.8),
            strokeWidth: 1.5,
            dashArray: const [6, 4],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              style: TextStyle(color: scheme.error, fontSize: 11, fontWeight: FontWeight.w600),
              labelResolver: (_) => '$label ${y.toStringAsFixed(sensor.decimals)}',
            ),
          ),
    ];

    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final minX = now - range.duration.inMilliseconds;
    final xInterval = switch (range) {
      HistoryRange.hour => const Duration(minutes: 15),
      HistoryRange.day => const Duration(hours: 6),
      HistoryRange.week => const Duration(days: 2),
    }.inMilliseconds.toDouble();
    final xFormat = range == HistoryRange.week ? DateFormat.E() : DateFormat.Hm();

    return SizedBox(
      height: 240,
      child: Semantics(
        label: '${sensor.label} history chart, last ${range.label}, ${spots.length} points',
        child: LineChart(
          duration: Duration.zero,
          LineChartData(
            minX: minX,
            maxX: now,
            minY: minY,
            maxY: maxY,
            clipData: const FlClipData.all(),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: scheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
            ),
            extraLinesData: ExtraLinesData(horizontalLines: lines),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => scheme.inverseSurface,
                getTooltipItems: (items) => [
                  for (final i in items)
                    LineTooltipItem(
                      '${sensor.format(i.y)}\n'
                      '${DateFormat('EEE HH:mm').format(DateTime.fromMillisecondsSinceEpoch(i.x.toInt()))}',
                      TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                    ),
                ],
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 48,
                  minIncluded: false,
                  maxIncluded: false,
                  getTitlesWidget: (v, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(
                      v.toStringAsFixed(sensor == SensorType.pressure ? 0 : 1),
                      style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: xInterval,
                  reservedSize: 26,
                  minIncluded: false,
                  maxIncluded: false,
                  getTitlesWidget: (v, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(
                      xFormat.format(DateTime.fromMillisecondsSinceEpoch(v.toInt())),
                      style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.15,
                preventCurveOverShooting: true,
                color: scheme.primary,
                barWidth: 2.5,
                dotData: FlDotData(show: spots.length < 3),
                belowBarData: BarAreaData(
                  show: true,
                  color: scheme.primary.withValues(alpha: 0.10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
