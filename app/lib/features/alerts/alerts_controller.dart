import 'package:flutter/foundation.dart';

import '../telemetry/models/sensor_type.dart';
import '../telemetry/models/telemetry.dart';
import 'alert_engine.dart';
import 'models/alert_models.dart';

/// Keeps the alert history and exposes active alerts to the UI.
class AlertsController extends ChangeNotifier {
  AlertsController({Map<SensorType, SensorThreshold>? thresholds})
      : _engine = AlertEngine(thresholds: thresholds);

  static const int maxHistory = 200;

  final AlertEngine _engine;
  final List<AlertEvent> _history = [];

  /// Newest first.
  List<AlertEvent> get history => List.unmodifiable(_history);

  List<AlertEvent> get activeAlerts =>
      _history.where((a) => a.isActive).toList(growable: false);

  /// Active alerts the user has not dismissed from the banner.
  List<AlertEvent> get bannerAlerts =>
      _history.where((a) => a.isActive && !a.acknowledged).toList(growable: false);

  Map<SensorType, SensorThreshold> get thresholds => _engine.thresholds;

  void setThresholds(Map<SensorType, SensorThreshold> thresholds) {
    _engine.setThresholds(thresholds);
    notifyListeners();
  }

  void evaluate(Telemetry t) {
    final changes = _engine.evaluate(t);
    if (changes.isEmpty) return;
    for (final e in changes.triggered) {
      _history.insert(0, e);
    }
    if (_history.length > maxHistory) {
      _history.removeRange(maxHistory, _history.length);
    }
    notifyListeners();
  }

  void acknowledge(AlertEvent e) {
    e.acknowledged = true;
    notifyListeners();
  }

  void acknowledgeAll() {
    for (final e in _history) {
      e.acknowledged = true;
    }
    notifyListeners();
  }

  /// Removes resolved alerts from history. Active alerts are kept.
  void clearResolved() {
    _history.removeWhere((e) => !e.isActive);
    notifyListeners();
  }

  void reset() {
    _engine.reset();
    _history.clear();
    notifyListeners();
  }
}
