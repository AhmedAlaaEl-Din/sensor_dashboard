import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_dashboard/features/telemetry/device_store.dart';
import 'package:sensor_dashboard/features/telemetry/models/sensor_type.dart';
import 'package:sensor_dashboard/features/telemetry/models/telemetry.dart';
import 'package:sensor_dashboard/features/telemetry/stats.dart';

void main() {
  group('SensorStats', () {
    test('min, max, average and count', () {
      final s = SensorStats.fromValues([3, 1, 2, 6])!;
      expect(s.min, 1);
      expect(s.max, 6);
      expect(s.average, 3);
      expect(s.count, 4);
    });

    test('single value', () {
      final s = SensorStats.fromValues([-4.5])!;
      expect([s.min, s.max, s.average], [-4.5, -4.5, -4.5]);
    });

    test('empty returns null', () {
      expect(SensorStats.fromValues(const []), isNull);
    });

    test('skips non-finite values', () {
      final s = SensorStats.fromValues([1, double.nan, 3, double.infinity])!;
      expect(s.count, 2);
      expect(s.average, 2);
    });
  });

  group('RollingBuffer', () {
    test('keeps only the newest items up to capacity', () {
      final b = RollingBuffer<int>(3);
      for (var i = 1; i <= 5; i++) {
        b.add(i);
      }
      expect(b.toList(), [3, 4, 5]);
      expect(b.length, 3);
      expect(b.last, 5);
    });
  });

  group('DeviceStore', () {
    Telemetry t(String id, int sec, double temp) => Telemetry(
      deviceId: id,
      timestamp: DateTime(2026, 1, 1, 0, 0, sec),
      values: {SensorType.temperature: temp},
    );

    test('keeps the last $historyLength readings and computes stats over them', () {
      final store = DeviceStore();
      for (var i = 0; i < historyLength + 10; i++) {
        store.addTelemetry(t('a', i % 60, i.toDouble()));
      }
      final d = store.device('a')!;
      expect(d.history.length, historyLength);
      final s = d.statsFor(SensorType.temperature)!;
      expect(s.min, 10); // first 10 dropped
      expect(s.max, historyLength + 9);
      expect(d.statsFor(SensorType.humidity), isNull);
    });

    test('latestValue falls back to the last reading that had the sensor', () {
      final store = DeviceStore();
      store.addTelemetry(t('a', 0, 20));
      store.addTelemetry(
        Telemetry(
          deviceId: 'a',
          timestamp: DateTime(2026),
          values: const {SensorType.humidity: 50},
        ),
      );
      expect(store.device('a')!.latestValue(SensorType.temperature), 20);
    });

    test('status updates and sorted devices', () {
      final store = DeviceStore();
      store.setOnline('zeta', online: false);
      store.addTelemetry(t('alpha', 0, 1));
      expect(store.devices.map((d) => d.id), ['alpha', 'zeta']);
      expect(store.device('zeta')!.online, isFalse);
      expect(store.device('alpha')!.online, isTrue);
      expect(store.device('alpha')!.displayName, 'Alpha');
    });
  });

  test('displayNameFor', () {
    expect(displayNameFor('server-room'), 'Server Room');
    expect(displayNameFor('cold_store_2'), 'Cold Store 2');
    expect(displayNameFor('---'), '---');
  });
}
