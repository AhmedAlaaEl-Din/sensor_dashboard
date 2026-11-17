import 'sensor_type.dart';

/// One telemetry reading from a device. Any sensor may be missing.
class Telemetry {
  const Telemetry({
    required this.deviceId,
    required this.timestamp,
    required this.values,
  });

  final String deviceId;
  final DateTime timestamp;
  final Map<SensorType, double> values;

  double? operator [](SensorType sensor) => values[sensor];

  @override
  String toString() => 'Telemetry($deviceId, $timestamp, $values)';
}

/// Turns ids like `server-room` into `Server Room` for display.
String displayNameFor(String deviceId) {
  final parts = deviceId
      .split(RegExp(r'[-_\s]+'))
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1));
  final name = parts.join(' ');
  return name.isEmpty ? deviceId : name;
}
