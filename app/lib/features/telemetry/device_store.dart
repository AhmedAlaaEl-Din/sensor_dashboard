import 'package:flutter/foundation.dart';

import 'models/sensor_type.dart';
import 'models/telemetry.dart';
import 'stats.dart';

/// Number of readings kept per device for the rolling chart and stats.
const int historyLength = 60;

/// Live state of one device.
class DeviceState {
  DeviceState(this.id);

  final String id;
  final RollingBuffer<Telemetry> history = RollingBuffer(historyLength);

  /// From the retained status topic. Null until the broker tells us.
  bool? online;

  /// When this app last received telemetry (phone clock, not device clock).
  DateTime? lastUpdate;

  String get displayName => displayNameFor(id);

  Telemetry? get latest => history.isEmpty ? null : history.last;

  double? latestValue(SensorType sensor) {
    // Walk back so one missing field does not blank the gauge.
    for (final t in history.toList().reversed) {
      final v = t[sensor];
      if (v != null) return v;
    }
    return null;
  }

  SensorStats? statsFor(SensorType sensor) =>
      SensorStats.fromValues(history.map((t) => t[sensor]).whereType<double>());
}

/// Holds live state for every device seen on the broker.
class DeviceStore extends ChangeNotifier {
  DeviceStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, DeviceState> _devices = {};

  /// Devices sorted by id so cards do not jump around.
  List<DeviceState> get devices {
    final list = _devices.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  DeviceState? device(String id) => _devices[id];

  bool get isEmpty => _devices.isEmpty;

  void addTelemetry(Telemetry t) {
    final d = _devices.putIfAbsent(t.deviceId, () => DeviceState(t.deviceId));
    d.history.add(t);
    d.lastUpdate = _clock();
    // Receiving telemetry proves the device is up even if the status topic lags.
    d.online = true;
    notifyListeners();
  }

  void setOnline(String deviceId, {required bool online}) {
    final d = _devices.putIfAbsent(deviceId, () => DeviceState(deviceId));
    if (d.online == online) return;
    d.online = online;
    notifyListeners();
  }

  void clear() {
    _devices.clear();
    notifyListeners();
  }
}
