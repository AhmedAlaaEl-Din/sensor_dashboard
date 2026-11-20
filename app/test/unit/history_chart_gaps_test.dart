import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_dashboard/features/history/history_models.dart';
import 'package:sensor_dashboard/features/history/history_screen.dart';
import 'package:sensor_dashboard/features/telemetry/models/sensor_type.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 18, 8);
  HistoryPoint at(Duration d, double? temp) =>
      HistoryPoint(t0.add(d), {SensorType.temperature: ?temp});

  test('breaks the line where the API was not recording', () {
    final spots = chartSpots(
      [
        at(Duration.zero, 25),
        at(const Duration(minutes: 15), 25.5),
        at(const Duration(hours: 11), 26), // 10 h 45 min later
        at(const Duration(hours: 11, minutes: 15), 26.2),
      ],
      SensorType.temperature,
      maxGap: HistoryRange.day.bucketDuration * 2.5,
    );
    expect(spots.length, 5);
    expect(spots[2], FlSpot.nullSpot);
    expect(spots.where((s) => s.isNull()).length, 1);
  });

  test('no break for normal spacing; skips points without this sensor', () {
    final spots = chartSpots(
      [
        at(Duration.zero, 21),
        at(const Duration(minutes: 1), null),
        at(const Duration(minutes: 2), 22),
      ],
      SensorType.temperature,
      maxGap: HistoryRange.hour.bucketDuration * 2.5,
    );
    expect(spots.map((s) => s.y), [21, 22]);
  });

  test('bucket durations match the API buckets', () {
    expect(HistoryRange.hour.bucketDuration, const Duration(minutes: 1));
    expect(HistoryRange.day.bucketDuration, const Duration(minutes: 15));
    expect(HistoryRange.week.bucketDuration, const Duration(hours: 1));
  });
}
