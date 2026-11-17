import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../../alerts/models/alert_models.dart';
import '../../telemetry/models/sensor_type.dart';
import '../../telemetry/models/telemetry.dart';

/// Rolling line chart of the last readings (x = seconds before the newest).
class SensorChart extends StatelessWidget {
  const SensorChart({super.key, required this.sensor, required this.history, this.threshold});

  final SensorType sensor;
  final List<Telemetry> history;
  final SensorThreshold? threshold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final points = history.where((t) => t[sensor] != null).toList();
    if (points.length < 2) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Text(
            'Collecting data for the chart…',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final newest = points.last.timestamp;
    final spots = [
      for (final t in points)
        FlSpot(-newest.difference(t.timestamp).inMilliseconds / 1000.0, t[sensor]!),
    ];

    // Y range: data plus threshold lines, with a little padding.
    final values = spots.map((s) => s.y).toList();
    var minY = values.reduce(math.min);
    var maxY = values.reduce(math.max);
    final th = threshold;
    final lines = <HorizontalLine>[
      if (th?.max != null) _thresholdLine(th!.max!, scheme.error, 'max'),
      if (th?.min != null) _thresholdLine(th!.min!, scheme.error, 'min'),
    ];
    // Only pull threshold lines into view when they are reasonably close.
    final span = math.max(maxY - minY, 1.0);
    for (final l in lines) {
      if ((l.y - maxY).abs() < span * 3 || (l.y - minY).abs() < span * 3) {
        minY = math.min(minY, l.y);
        maxY = math.max(maxY, l.y);
      }
    }
    final pad = math.max((maxY - minY) * 0.12, 0.5);
    minY -= pad;
    maxY += pad;

    final minX = math.min(-60.0, spots.first.x);

    return SizedBox(
      height: 240,
      child: Semantics(
        label: '${sensor.label} chart, last ${points.length} readings',
        child: LineChart(
          duration: Duration.zero,
          LineChartData(
            minX: minX,
            maxX: 0,
            minY: minY,
            maxY: maxY,
            clipData: const FlClipData.all(),
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: scheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            extraLinesData: ExtraLinesData(horizontalLines: lines),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => scheme.inverseSurface,
                getTooltipItems: (items) => [
                  for (final i in items)
                    LineTooltipItem(
                      '${sensor.format(i.y)}\n${(-i.x).toStringAsFixed(0)} s ago',
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
                  interval: 15,
                  reservedSize: 26,
                  getTitlesWidget: (v, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(
                      v == 0 ? 'now' : '${v.toInt()}s',
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
                curveSmoothness: 0.2,
                preventCurveOverShooting: true,
                color: scheme.primary,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
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

  HorizontalLine _thresholdLine(double y, Color color, String which) => HorizontalLine(
    y: y,
    color: color.withValues(alpha: 0.8),
    strokeWidth: 1.5,
    dashArray: const [6, 4],
    label: HorizontalLineLabel(
      show: true,
      alignment: Alignment.topRight,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      labelResolver: (_) => '$which ${y.toStringAsFixed(sensor.decimals)}',
    ),
  );
}
