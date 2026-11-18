import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_dashboard/features/history/history_models.dart';
import 'package:sensor_dashboard/features/telemetry/models/sensor_type.dart';

void main() {
  Map<String, dynamic> response({List<Object?>? points, Map<String, Object?>? stats}) => {
    'deviceId': 'greenhouse',
    'bucket': '1m',
    'from': '2026-11-18T10:00:00.000Z',
    'to': '2026-11-18T11:00:00.000Z',
    'points':
        points ??
        [
          {
            't': '2026-11-18T10:01:00.000Z',
            'temperature': 21.5,
            'humidity': 50,
            'pressure': 1013.2,
            'battery': 90,
            'count': 60,
          },
          {'t': '2026-11-18T10:00:00.000Z', 'temperature': 21, 'humidity': null, 'count': 60},
        ],
    'stats':
        stats ??
        {
          'temperature': {'min': 20.1, 'max': 22.9, 'avg': 21.25, 'count': 120},
          'humidity': null,
        },
  };

  test('parses points (sorted, local time) and stats', () {
    final d = HistoryData.fromJson(response());
    expect(d.deviceId, 'greenhouse');
    expect(d.bucket, '1m');
    expect(d.points, hasLength(2));
    expect(d.points.first.time.toUtc(), DateTime.utc(2026, 11, 18, 10));
    expect(d.points.first.time.isUtc, isFalse);
    expect(d.points.first.values[SensorType.temperature], 21.0); // int → double
    expect(d.points.first.values.containsKey(SensorType.humidity), isFalse); // null skipped
    expect(d.points.last.values[SensorType.pressure], 1013.2);
    final t = d.stats[SensorType.temperature]!;
    expect([t.min, t.max, t.avg, t.count], [20.1, 22.9, 21.25, 120]);
    expect(d.stats.containsKey(SensorType.humidity), isFalse);
  });

  test('empty history', () {
    final d = HistoryData.fromJson(response(points: [], stats: {}));
    expect(d.isEmpty, isTrue);
    expect(d.stats, isEmpty);
  });

  test('skips malformed points instead of failing', () {
    final d = HistoryData.fromJson(
      response(
        points: [
          'junk',
          {'t': 'not a date', 'temperature': 1},
          {'t': '2026-11-18T10:05:00Z', 'temperature': 'hot', 'battery': 80},
        ],
      ),
    );
    expect(d.points, hasLength(1));
    expect(d.points.single.values, {SensorType.battery: 80.0});
  });

  test('throws FormatException when the shape is wrong', () {
    expect(() => HistoryData.fromJson({'points': []}), throwsFormatException);
    expect(() => HistoryData.fromJson({...response(), 'points': 'nope'}), throwsFormatException);
  });

  test('ranges map to the API buckets', () {
    expect(HistoryRange.hour.bucket, '1m');
    expect(HistoryRange.day.bucket, '15m');
    expect(HistoryRange.week.bucket, '1h');
    expect(HistoryRange.hour.exportBucket, 'raw');
    expect(HistoryRange.values.map((r) => r.label), ['1 h', '24 h', '7 d']);
  });
}
