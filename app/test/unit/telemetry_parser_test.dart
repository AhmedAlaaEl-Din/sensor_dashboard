import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_dashboard/features/telemetry/models/sensor_type.dart';
import 'package:sensor_dashboard/features/telemetry/telemetry_parser.dart';

void main() {
  final fixedNow = DateTime(2026, 1, 1, 12);
  final parser = TelemetryParser(prefix: 'sensors', clock: () => fixedNow);

  group('telemetry', () {
    test('parses a full simulator payload', () {
      final r = parser.parse(
        'sensors/greenhouse/telemetry',
        '{"deviceId":"greenhouse","temperature":25.7,"humidity":70.5,'
            '"pressure":1012.2,"battery":96,"timestamp":"2026-11-17T06:14:20.705Z"}',
      );
      expect(r, isA<TelemetryMessage>());
      final t = (r as TelemetryMessage).telemetry;
      expect(t.deviceId, 'greenhouse');
      expect(t[SensorType.temperature], 25.7);
      expect(t[SensorType.humidity], 70.5);
      expect(t[SensorType.pressure], 1012.2);
      expect(t[SensorType.battery], 96.0); // int in JSON becomes double
      expect(t.timestamp.toUtc(), DateTime.utc(2026, 11, 17, 6, 14, 20, 705));
    });

    test('device id comes from the topic, not the payload', () {
      final r = parser.parse(
        'sensors/warehouse/telemetry',
        '{"deviceId":"spoofed","temperature":1}',
      );
      expect((r as TelemetryMessage).telemetry.deviceId, 'warehouse');
    });

    test('accepts partial payloads and numeric strings', () {
      final r = parser.parse('sensors/a/telemetry', '{"temperature":"21.5","humidity":null}');
      final t = (r as TelemetryMessage).telemetry;
      expect(t[SensorType.temperature], 21.5);
      expect(t[SensorType.humidity], isNull);
      expect(t.values.length, 1);
    });

    test('missing or bad timestamp falls back to receive time', () {
      final a = parser.parse('sensors/a/telemetry', '{"temperature":1}') as TelemetryMessage;
      final b = parser.parse(
        'sensors/a/telemetry',
        '{"temperature":1,"timestamp":"nope"}',
      ) as TelemetryMessage;
      expect(a.telemetry.timestamp, fixedNow);
      expect(b.telemetry.timestamp, fixedNow);
    });

    test('accepts epoch-millisecond timestamps', () {
      final r = parser.parse(
        'sensors/a/telemetry',
        '{"temperature":1,"timestamp":1700000000000}',
      ) as TelemetryMessage;
      expect(r.telemetry.timestamp.millisecondsSinceEpoch, 1700000000000);
    });

    test('rejects invalid JSON, non-objects and empty payloads', () {
      expect(parser.parse('sensors/a/telemetry', 'not json'), isA<InvalidMessage>());
      expect(parser.parse('sensors/a/telemetry', '[1,2]'), isA<InvalidMessage>());
      expect(parser.parse('sensors/a/telemetry', '{}'), isA<InvalidMessage>());
      expect(parser.parse('sensors/a/telemetry', ''), isA<InvalidMessage>());
      expect(parser.parse('sensors/a/telemetry', '{"temperature":"hot"}'), isA<InvalidMessage>());
    });

    test('rejects non-finite numbers', () {
      // jsonDecode cannot produce NaN, but strings can.
      expect(parser.parse('sensors/a/telemetry', '{"temperature":"NaN"}'), isA<InvalidMessage>());
      expect(
        parser.parse('sensors/a/telemetry', '{"temperature":"Infinity"}'),
        isA<InvalidMessage>(),
      );
    });
  });

  group('topics', () {
    test('ignores other prefixes, wrong shapes and control topics', () {
      expect(parser.parse('other/a/telemetry', '{"temperature":1}'), isA<InvalidMessage>());
      expect(parser.parse('sensors/telemetry', '{"temperature":1}'), isA<InvalidMessage>());
      expect(parser.parse('sensors/a/b/telemetry', '{"temperature":1}'), isA<InvalidMessage>());
      expect(parser.parse('sensors/_control/spike', 'all'), isA<InvalidMessage>());
      expect(parser.parse('sensors/a/unknown', '{}'), isA<InvalidMessage>());
    });

    test('supports multi-level and slash-padded prefixes', () {
      final p = TelemetryParser(prefix: '/site/a/sensors/');
      expect(p.parse('site/a/sensors/x/telemetry', '{"battery":5}'), isA<TelemetryMessage>());
    });

    test('normalizePrefix', () {
      expect(TelemetryParser.normalizePrefix(' /sensors/ '), 'sensors');
      expect(TelemetryParser.normalizePrefix(''), 'sensors');
    });
  });

  group('status', () {
    test('parses online/offline, case-insensitive', () {
      final on = parser.parse('sensors/a/status', 'online') as StatusMessage;
      final off = parser.parse('sensors/a/status', ' OFFLINE ') as StatusMessage;
      expect(on.online, isTrue);
      expect(off.online, isFalse);
      expect(off.deviceId, 'a');
    });

    test('rejects unknown status', () {
      expect(parser.parse('sensors/a/status', 'maybe'), isA<InvalidMessage>());
    });
  });
}
