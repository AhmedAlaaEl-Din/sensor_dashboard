import '../telemetry/models/sensor_type.dart';

/// The ranges offered on the History screen.
enum HistoryRange {
  hour(label: '1 h', duration: Duration(hours: 1), bucket: '1m', exportBucket: 'raw'),
  day(label: '24 h', duration: Duration(hours: 24), bucket: '15m', exportBucket: '1m'),
  week(label: '7 d', duration: Duration(days: 7), bucket: '1h', exportBucket: '15m');

  const HistoryRange({
    required this.label,
    required this.duration,
    required this.bucket,
    required this.exportBucket,
  });

  final String label;
  final Duration duration;

  /// Server-side downsampling for the chart (60, 96 and 168 points).
  final String bucket;

  /// Downsampling for CSV export (raw is limited to short ranges by the API).
  final String exportBucket;

  Duration get bucketDuration => switch (bucket) {
    '1m' => const Duration(minutes: 1),
    '15m' => const Duration(minutes: 15),
    '1h' => const Duration(hours: 1),
    _ => const Duration(seconds: 1),
  };

  String get bucketLabel => switch (bucket) {
    'raw' => 'every reading',
    '1m' => '1-minute averages',
    '15m' => '15-minute averages',
    '1h' => '1-hour averages',
    _ => bucket,
  };
}

/// One (possibly averaged) point.
class HistoryPoint {
  const HistoryPoint(this.time, this.values);
  final DateTime time;
  final Map<SensorType, double> values;
}

/// Min / average / max over the raw readings in the range.
class HistoryStat {
  const HistoryStat({required this.min, required this.max, required this.avg, required this.count});
  final double min;
  final double max;
  final double avg;
  final int count;
}

class HistoryData {
  const HistoryData({
    required this.deviceId,
    required this.bucket,
    required this.from,
    required this.to,
    required this.points,
    required this.stats,
  });

  final String deviceId;
  final String bucket;
  final DateTime from;
  final DateTime to;
  final List<HistoryPoint> points;
  final Map<SensorType, HistoryStat> stats;

  bool get isEmpty => points.isEmpty;

  /// Parses `GET /devices/:id/history`. Throws [FormatException] when the shape is wrong;
  /// individual bad points or values are skipped.
  factory HistoryData.fromJson(Map<String, dynamic> json) {
    final from = DateTime.tryParse('${json['from']}');
    final to = DateTime.tryParse('${json['to']}');
    final rawPoints = json['points'];
    final rawStats = json['stats'];
    if (from == null || to == null || rawPoints is! List || rawStats is! Map) {
      throw const FormatException('Malformed history response');
    }

    final points = <HistoryPoint>[];
    for (final p in rawPoints) {
      if (p is! Map) continue;
      final t = DateTime.tryParse('${p['t']}');
      if (t == null) continue;
      final values = <SensorType, double>{};
      for (final s in SensorType.values) {
        final v = p[s.key];
        if (v is num && v.isFinite) values[s] = v.toDouble();
      }
      points.add(HistoryPoint(t.toLocal(), values));
    }
    points.sort((a, b) => a.time.compareTo(b.time));

    final stats = <SensorType, HistoryStat>{};
    for (final s in SensorType.values) {
      final st = rawStats[s.key];
      if (st is! Map) continue;
      final min = st['min'], max = st['max'], avg = st['avg'], count = st['count'];
      if (min is num && max is num && avg is num && count is num) {
        stats[s] = HistoryStat(
          min: min.toDouble(),
          max: max.toDouble(),
          avg: avg.toDouble(),
          count: count.toInt(),
        );
      }
    }

    return HistoryData(
      deviceId: '${json['deviceId'] ?? ''}',
      bucket: '${json['bucket'] ?? ''}',
      from: from.toLocal(),
      to: to.toLocal(),
      points: points,
      stats: stats,
    );
  }
}
