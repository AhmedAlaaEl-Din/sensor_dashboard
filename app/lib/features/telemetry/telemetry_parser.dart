import 'dart:convert';

import 'models/sensor_type.dart';
import 'models/telemetry.dart';

/// Result of parsing one MQTT message.
sealed class ParsedMessage {
  const ParsedMessage();
}

class TelemetryMessage extends ParsedMessage {
  const TelemetryMessage(this.telemetry);
  final Telemetry telemetry;
}

class StatusMessage extends ParsedMessage {
  const StatusMessage(this.deviceId, {required this.online});
  final String deviceId;
  final bool online;
}

/// A message that could not be used. [reason] is for logs only and is never
/// shown on screen.
class InvalidMessage extends ParsedMessage {
  const InvalidMessage(this.reason);
  final String reason;
}

/// Parses `<prefix>/<deviceId>/telemetry` and `<prefix>/<deviceId>/status`.
///
/// Never throws: bad input becomes an [InvalidMessage].
class TelemetryParser {
  const TelemetryParser({required this.prefix, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final String prefix;
  final DateTime Function() _clock;

  ParsedMessage parse(String topic, String payload) {
    final cleanPrefix = normalizePrefix(prefix);
    if (!topic.startsWith('$cleanPrefix/')) {
      return InvalidMessage('topic "$topic" is outside prefix "$cleanPrefix"');
    }
    final rest = topic.substring(cleanPrefix.length + 1).split('/');
    if (rest.length != 2 || rest[0].isEmpty) {
      return InvalidMessage('unexpected topic shape "$topic"');
    }
    final deviceId = rest[0];
    if (deviceId.startsWith('_')) {
      return InvalidMessage('control topic "$topic" ignored');
    }
    return switch (rest[1]) {
      'telemetry' => _parseTelemetry(deviceId, payload),
      'status' => _parseStatus(deviceId, payload),
      _ => InvalidMessage('unknown message kind "${rest[1]}"'),
    };
  }

  ParsedMessage _parseStatus(String deviceId, String payload) {
    switch (payload.trim().toLowerCase()) {
      case 'online':
        return StatusMessage(deviceId, online: true);
      case 'offline':
        return StatusMessage(deviceId, online: false);
      default:
        return InvalidMessage('unknown status "$payload"');
    }
  }

  ParsedMessage _parseTelemetry(String deviceId, String payload) {
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return const InvalidMessage('payload is not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      return const InvalidMessage('payload is not a JSON object');
    }

    final values = <SensorType, double>{};
    for (final sensor in SensorType.values) {
      final raw = decoded[sensor.key];
      final value = _toDouble(raw);
      if (value != null) values[sensor] = value;
    }
    if (values.isEmpty) {
      return const InvalidMessage('payload has no usable sensor values');
    }

    return TelemetryMessage(
      Telemetry(
        deviceId: deviceId,
        timestamp: _parseTimestamp(decoded['timestamp']) ?? _clock(),
        values: values,
      ),
    );
  }

  static double? _toDouble(Object? raw) {
    final double? v = switch (raw) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };
    return (v != null && v.isFinite) ? v : null;
  }

  static DateTime? _parseTimestamp(Object? raw) {
    return switch (raw) {
      String s => DateTime.tryParse(s)?.toLocal(),
      int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null,
    };
  }

  /// Trims whitespace and leading/trailing slashes; empty becomes `sensors`.
  static String normalizePrefix(String prefix) {
    var p = prefix.trim();
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    while (p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p.isEmpty ? 'sensors' : p;
  }
}
