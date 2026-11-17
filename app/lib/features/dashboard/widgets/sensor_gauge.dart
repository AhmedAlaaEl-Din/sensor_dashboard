import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../alerts/models/alert_models.dart';
import '../../telemetry/models/sensor_type.dart';

/// Compact arc gauge for one sensor value.
class SensorGauge extends StatelessWidget {
  const SensorGauge({
    super.key,
    required this.sensor,
    required this.value,
    this.threshold,
    this.dimmed = false,
  });

  final SensorType sensor;
  final double? value;
  final SensorThreshold? threshold;

  /// Shown greyed out when the data is not live.
  final bool dimmed;

  bool get _breached {
    final v = value;
    final th = threshold;
    if (v == null || th == null) return false;
    return (th.max != null && v > th.max!) || (th.min != null && v < th.min!);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final v = value;
    final fraction = v == null
        ? 0.0
        : ((v - sensor.gaugeMin) / (sensor.gaugeMax - sensor.gaugeMin)).clamp(0.0, 1.0);
    final color = dimmed
        ? scheme.outline
        : _breached
            ? scheme.error
            : scheme.primary;

    final valueText = v == null ? '—' : v.toStringAsFixed(sensor.decimals);

    return Semantics(
      label: '${sensor.label} ${v == null ? 'no data' : sensor.format(v)}'
          '${_breached ? ', out of range' : ''}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 92,
            height: 62,
            child: CustomPaint(
              painter: _ArcPainter(
                fraction: fraction,
                color: color,
                track: scheme.surfaceContainerHighest,
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 22),
                child: Column(
                  children: [
                    Text(
                      valueText,
                      key: Key('gauge-${sensor.key}-value'),
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _breached && !dimmed ? scheme.error : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(sensor.unit,
                        style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_breached && !dimmed)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Icon(Icons.warning_amber_rounded, size: 14, color: scheme.error),
                ),
              Text(sensor.label, style: text.labelMedium),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.fraction, required this.color, required this.track});

  final double fraction;
  final Color color;
  final Color track;

  static const double _sweep = math.pi * 1.25; // 225° arc
  static const double _start = math.pi * 0.875;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final radius = math.min(size.width / 2, size.height * 0.85) - stroke / 2;
    final center = Offset(size.width / 2, radius + stroke / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, _start, _sweep, false, base..color = track);
    if (fraction > 0) {
      canvas.drawArc(rect, _start, _sweep * fraction, false, base..color = color);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}
