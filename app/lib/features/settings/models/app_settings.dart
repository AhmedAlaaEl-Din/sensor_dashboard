import 'package:material_ui/material_ui.dart' show ThemeMode;

import '../../alerts/models/alert_models.dart';
import '../../telemetry/models/sensor_type.dart';

/// Everything the user can configure. Stored locally with shared_preferences.
class AppSettings {
  const AppSettings({
    this.host = defaultHost,
    this.port = defaultPort,
    this.topicPrefix = defaultPrefix,
    this.apiUrl = defaultApiUrl,
    this.thresholds = defaultThresholds,
    this.themeMode = ThemeMode.system,
  });

  /// 127.0.0.1 works on a USB phone because `adb reverse` forwards the ports
  /// over the cable (see README).
  static const String defaultHost = '127.0.0.1';
  static const int defaultPort = 1883;
  static const String defaultPrefix = 'sensors';
  static const String defaultApiUrl = 'http://127.0.0.1:3000';

  final String host;
  final int port;
  final String topicPrefix;

  /// Base URL of the history/login API.
  final String apiUrl;
  final Map<SensorType, SensorThreshold> thresholds;
  final ThemeMode themeMode;

  /// True when a change requires reconnecting to the broker.
  bool connectionDiffers(AppSettings other) =>
      host != other.host || port != other.port || topicPrefix != other.topicPrefix;

  AppSettings copyWith({
    String? host,
    int? port,
    String? topicPrefix,
    String? apiUrl,
    Map<SensorType, SensorThreshold>? thresholds,
    ThemeMode? themeMode,
  }) {
    return AppSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      topicPrefix: topicPrefix ?? this.topicPrefix,
      apiUrl: apiUrl ?? this.apiUrl,
      thresholds: thresholds ?? this.thresholds,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  Map<String, dynamic> thresholdsToJson() => {
    for (final e in thresholds.entries) e.key.key: e.value.toJson(),
  };

  static Map<SensorType, SensorThreshold> thresholdsFromJson(Map<String, dynamic> json) {
    final result = Map<SensorType, SensorThreshold>.of(defaultThresholds);
    for (final e in json.entries) {
      final sensor = SensorType.fromKey(e.key);
      if (sensor != null && e.value is Map<String, dynamic>) {
        result[sensor] = SensorThreshold.fromJson(e.value as Map<String, dynamic>);
      }
    }
    return result;
  }
}

/// Validation shared by the settings form and the repository.
class SettingsValidator {
  static final RegExp _hostPattern = RegExp(r'^[A-Za-z0-9.\-:]+$');

  static String? host(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter the broker host, for example 127.0.0.1';
    if (!_hostPattern.hasMatch(v)) return 'Use letters, digits, dots, dashes or colons only';
    return null;
  }

  static String? apiUrl(String? value) {
    final v = value?.trim() ?? '';
    final uri = Uri.tryParse(v);
    if (v.isEmpty ||
        uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return 'Enter an address like http://127.0.0.1:3000';
    }
    return null;
  }

  static String? port(String? value) {
    final p = int.tryParse(value?.trim() ?? '');
    if (p == null || p < 1 || p > 65535) return 'Port must be a number from 1 to 65535';
    return null;
  }

  static String? prefix(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter a topic prefix, for example sensors';
    if (v.contains('+') || v.contains('#')) return 'Wildcards (+, #) are not allowed';
    if (v.contains(' ')) return 'Spaces are not allowed';
    return null;
  }

  /// Empty text means "no limit".
  static String? number(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final n = double.tryParse(v);
    if (n == null || !n.isFinite) return 'Enter a number or leave empty';
    return null;
  }
}
