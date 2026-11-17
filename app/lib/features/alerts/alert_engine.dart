import '../telemetry/models/sensor_type.dart';
import '../telemetry/models/telemetry.dart';
import 'models/alert_models.dart';

/// Change produced by evaluating one reading.
class AlertChanges {
  const AlertChanges({this.triggered = const [], this.resolved = const []});
  final List<AlertEvent> triggered;
  final List<AlertEvent> resolved;
  bool get isEmpty => triggered.isEmpty && resolved.isEmpty;
}

/// Pure threshold logic, with no Flutter dependencies.
///
/// An alert fires once when a value crosses a limit, and clears only when the
/// value is back inside by at least [SensorType.hysteresis], so a value that
/// hovers around a limit does not produce a flood of alerts.
class AlertEngine {
  AlertEngine({Map<SensorType, SensorThreshold>? thresholds})
      : _thresholds = Map.of(thresholds ?? defaultThresholds);

  Map<SensorType, SensorThreshold> _thresholds;
  final Map<(String, SensorType), AlertEvent> _active = {};
  int _nextId = 1;

  Map<SensorType, SensorThreshold> get thresholds => Map.unmodifiable(_thresholds);

  Iterable<AlertEvent> get activeAlerts => _active.values;

  void setThresholds(Map<SensorType, SensorThreshold> thresholds) {
    _thresholds = Map.of(thresholds);
  }

  AlertChanges evaluate(Telemetry t) {
    final triggered = <AlertEvent>[];
    final resolved = <AlertEvent>[];

    for (final MapEntry(key: sensor, value: value) in t.values.entries) {
      final key = (t.deviceId, sensor);
      final threshold = _thresholds[sensor] ?? const SensorThreshold();
      final active = _active[key];

      if (active != null) {
        if (_isBackInRange(value, threshold, sensor, active.direction)) {
          active.resolvedAt = t.timestamp;
          _active.remove(key);
          resolved.add(active);
        } else {
          continue; // Still breaching; do not fire again.
        }
      }

      final breach = _breach(value, threshold);
      if (breach != null) {
        final event = AlertEvent(
          id: _nextId++,
          deviceId: t.deviceId,
          sensor: sensor,
          direction: breach.$1,
          value: value,
          limit: breach.$2,
          triggeredAt: t.timestamp,
        );
        _active[key] = event;
        triggered.add(event);
      }
    }
    return AlertChanges(triggered: triggered, resolved: resolved);
  }

  /// Forget active state, for example after the topic prefix changes.
  void reset() => _active.clear();

  static (AlertDirection, double)? _breach(double value, SensorThreshold th) {
    if (th.max != null && value > th.max!) return (AlertDirection.high, th.max!);
    if (th.min != null && value < th.min!) return (AlertDirection.low, th.min!);
    return null;
  }

  static bool _isBackInRange(
    double value,
    SensorThreshold th,
    SensorType sensor,
    AlertDirection direction,
  ) {
    switch (direction) {
      case AlertDirection.high:
        // Limit removed, or value is back below it with margin.
        return th.max == null || value <= th.max! - sensor.hysteresis;
      case AlertDirection.low:
        return th.min == null || value >= th.min! + sensor.hysteresis;
    }
  }
}
