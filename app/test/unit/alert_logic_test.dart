import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_dashboard/features/alerts/alert_engine.dart';
import 'package:sensor_dashboard/features/alerts/alerts_controller.dart';
import 'package:sensor_dashboard/features/alerts/models/alert_models.dart';
import 'package:sensor_dashboard/features/telemetry/models/sensor_type.dart';
import 'package:sensor_dashboard/features/telemetry/models/telemetry.dart';

Telemetry reading(Map<SensorType, double> values, {String device = 'greenhouse', int sec = 0}) =>
    Telemetry(deviceId: device, timestamp: DateTime(2026, 1, 1, 0, 0, sec), values: values);

void main() {
  const temp = SensorType.temperature;

  group('AlertEngine', () {
    test('no alert inside thresholds', () {
      final e = AlertEngine();
      expect(e.evaluate(reading({temp: 25})).isEmpty, isTrue);
    });

    test('fires once on a high breach, not on every reading', () {
      final e = AlertEngine();
      final first = e.evaluate(reading({temp: 40}));
      expect(first.triggered, hasLength(1));
      final a = first.triggered.single;
      expect(a.direction, AlertDirection.high);
      expect(a.limit, 35);
      expect(a.value, 40);
      expect(a.description, 'Temperature 40.0 °C is above 35.0 °C');

      expect(e.evaluate(reading({temp: 41})).isEmpty, isTrue);
      expect(e.activeAlerts, hasLength(1));
    });

    test('fires on low breach', () {
      final e = AlertEngine();
      final c = e.evaluate(reading({SensorType.battery: 10}));
      expect(c.triggered.single.direction, AlertDirection.low);
      expect(c.triggered.single.limit, 20);
    });

    test('values exactly on the limit are not a breach', () {
      final e = AlertEngine();
      expect(e.evaluate(reading({temp: 35})).isEmpty, isTrue);
      expect(e.evaluate(reading({temp: 5})).isEmpty, isTrue);
    });

    test('hysteresis: clears only when back inside by the margin', () {
      final e = AlertEngine();
      e.evaluate(reading({temp: 36}));
      // 34.8 is inside the limit but within the 0.5 °C margin: still active.
      expect(e.evaluate(reading({temp: 34.8})).resolved, isEmpty);
      final c = e.evaluate(reading({temp: 34.5}, sec: 9));
      expect(c.resolved, hasLength(1));
      expect(c.resolved.single.resolvedAt, DateTime(2026, 1, 1, 0, 0, 9));
      expect(e.activeAlerts, isEmpty);
      // A new breach after clearing fires again.
      expect(e.evaluate(reading({temp: 36})).triggered, hasLength(1));
    });

    test('high to low swing resolves the old alert and fires a new one', () {
      final e = AlertEngine();
      e.evaluate(reading({temp: 40}));
      final c = e.evaluate(reading({temp: 0}));
      expect(c.resolved.single.direction, AlertDirection.high);
      expect(c.triggered.single.direction, AlertDirection.low);
    });

    test('alerts are tracked per device and per sensor', () {
      final e = AlertEngine();
      final c1 = e.evaluate(reading({temp: 40, SensorType.humidity: 95}));
      final c2 = e.evaluate(reading({temp: 40}, device: 'warehouse'));
      expect(c1.triggered, hasLength(2));
      expect(c2.triggered, hasLength(1));
      expect(e.activeAlerts, hasLength(3));
    });

    test('changing thresholds applies to the next reading', () {
      final e = AlertEngine();
      e.evaluate(reading({temp: 30}));
      e.setThresholds({...defaultThresholds, temp: const SensorThreshold(max: 28)});
      expect(e.evaluate(reading({temp: 30})).triggered, hasLength(1));
      // Removing the limit resolves the alert.
      e.setThresholds({...defaultThresholds, temp: const SensorThreshold()});
      expect(e.evaluate(reading({temp: 30})).resolved, hasLength(1));
    });

    test('missing sensors in a reading do not change their alerts', () {
      final e = AlertEngine();
      e.evaluate(reading({temp: 40}));
      final c = e.evaluate(reading({SensorType.humidity: 50}));
      expect(c.isEmpty, isTrue);
      expect(e.activeAlerts, hasLength(1));
    });
  });

  group('AlertsController', () {
    test('history is newest first, banner respects acknowledge', () {
      final c = AlertsController();
      c.evaluate(reading({temp: 40}, sec: 1));
      c.evaluate(reading({SensorType.battery: 5}, sec: 2));
      expect(c.history.map((a) => a.sensor), [SensorType.battery, temp]);
      expect(c.bannerAlerts, hasLength(2));
      c.acknowledge(c.history.first);
      expect(c.bannerAlerts, hasLength(1));
      expect(c.activeAlerts, hasLength(2));
    });

    test('clearResolved keeps active alerts', () {
      final c = AlertsController();
      c.evaluate(reading({temp: 40}));
      c.evaluate(reading({temp: 20}));
      c.evaluate(reading({SensorType.battery: 5}));
      expect(c.history, hasLength(2));
      c.clearResolved();
      expect(c.history.single.sensor, SensorType.battery);
    });

    test('notifies listeners only when something changes', () {
      final c = AlertsController();
      var n = 0;
      c.addListener(() => n++);
      c.evaluate(reading({temp: 20}));
      expect(n, 0);
      c.evaluate(reading({temp: 40}));
      expect(n, 1);
    });
  });

  group('SensorThreshold', () {
    test('json round trip and inverted detection', () {
      const th = SensorThreshold(min: 1, max: 2);
      expect(SensorThreshold.fromJson(th.toJson()), th);
      expect(const SensorThreshold(min: 3, max: 2).isInverted, isTrue);
      expect(const SensorThreshold().isEmpty, isTrue);
    });
  });
}
