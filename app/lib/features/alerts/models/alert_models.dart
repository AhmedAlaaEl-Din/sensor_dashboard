import '../../telemetry/models/sensor_type.dart';

/// Allowed range for one sensor. A null bound means "no limit".
class SensorThreshold {
  const SensorThreshold({this.min, this.max});

  final double? min;
  final double? max;

  bool get isEmpty => min == null && max == null;

  /// True when both bounds are set and min is not below max.
  bool get isInverted => min != null && max != null && min! >= max!;

  SensorThreshold copyWith({double? min, double? max, bool clearMin = false, bool clearMax = false}) {
    return SensorThreshold(
      min: clearMin ? null : (min ?? this.min),
      max: clearMax ? null : (max ?? this.max),
    );
  }

  Map<String, dynamic> toJson() => {'min': min, 'max': max};

  static SensorThreshold fromJson(Map<String, dynamic> json) => SensorThreshold(
        min: (json['min'] as num?)?.toDouble(),
        max: (json['max'] as num?)?.toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is SensorThreshold && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}

/// Default thresholds. The simulator's normal ranges stay inside them; a
/// spike (+18 °C, +25 % humidity, -30 hPa) crosses them.
const Map<SensorType, SensorThreshold> defaultThresholds = {
  SensorType.temperature: SensorThreshold(min: 5, max: 35),
  SensorType.humidity: SensorThreshold(min: 20, max: 85),
  SensorType.pressure: SensorThreshold(min: 985, max: 1040),
  SensorType.battery: SensorThreshold(min: 20),
};

enum AlertDirection { high, low }

/// One threshold breach. [resolvedAt] is set when the value returns to range.
class AlertEvent {
  AlertEvent({
    required this.id,
    required this.deviceId,
    required this.sensor,
    required this.direction,
    required this.value,
    required this.limit,
    required this.triggeredAt,
  });

  final int id;
  final String deviceId;
  final SensorType sensor;
  final AlertDirection direction;
  final double value;
  final double limit;
  final DateTime triggeredAt;
  DateTime? resolvedAt;

  /// The user dismissed the banner for this alert (it is still in history).
  bool acknowledged = false;

  bool get isActive => resolvedAt == null;

  String get description {
    final word = direction == AlertDirection.high ? 'above' : 'below';
    return '${sensor.label} ${sensor.format(value)} is $word ${sensor.format(limit)}';
  }
}
