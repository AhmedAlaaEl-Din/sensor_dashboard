import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_dashboard/core/api/api_client.dart';
import 'package:sensor_dashboard/features/history/csv_exporter.dart';
import 'package:sensor_dashboard/features/history/history_models.dart';

import '../helpers/fake_api.dart';

void main() {
  late Directory tmp;
  late FakeApi fake;
  final now = DateTime.utc(2026, 11, 18, 11);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('csv_export_test');
    fake = FakeApi(now: now);
  });
  tearDown(() => tmp.delete(recursive: true));

  CsvExporter exporter({String token = FakeApi.viewerToken}) => CsvExporter(
    api: ApiClient(baseUrl: () => 'http://127.0.0.1:3000', token: () => token, client: fake.client),
    directory: () async => tmp,
    clock: () => now,
  );

  test(
    'downloads the CSV for the range, saves it with the server filename and counts rows',
    () async {
      final result = await exporter().export('greenhouse', HistoryRange.hour);

      final req = fake.requests.single;
      expect(req.url.path, '/devices/greenhouse/export.csv');
      expect(req.url.queryParameters['from'], '2026-11-18T10:00:00.000Z');
      expect(req.url.queryParameters['to'], '2026-11-18T11:00:00.000Z');
      expect(req.url.queryParameters['bucket'], 'raw');
      expect(req.headers['Authorization'], 'Bearer ${FakeApi.viewerToken}');

      expect(result.fileName, 'greenhouse_202611181000-202611181100.csv');
      expect(result.rows, 2);
      final lines = await result.file.readAsLines();
      expect(lines.first, 'timestamp,device_id,temperature,humidity,pressure,battery');
      expect(lines[1], '2026-11-18T10:00:00.000Z,greenhouse,21.5,50,1013,90');
      expect(result.file.parent.path, endsWith('exports'));
    },
  );

  test('longer ranges use the downsampled export buckets', () async {
    await exporter().export('greenhouse', HistoryRange.week);
    expect(fake.requests.single.url.queryParameters['bucket'], '15m');
    expect(fake.requests.single.url.queryParameters['from'], '2026-11-11T11:00:00.000Z');
  });

  test('reads the filename from Content-Disposition', () async {
    final api = ApiClient(
      baseUrl: () => 'http://x',
      token: () => FakeApi.viewerToken,
      client: fake.client,
    );
    final dl = await api.exportCsv('a', from: now, to: now, bucket: 'raw');
    expect(dl.fileName, 'a_202611181000-202611181100.csv');
  });

  test('signed-out export fails with a friendly error', () async {
    await expectLater(
      exporter(token: 'bad').export('greenhouse', HistoryRange.hour),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Sign in required.')),
    );
  });

  test('countRows', () {
    List<int> b(String s) => s.codeUnits;
    expect(CsvExporter.countRows(b('h\n')), 0);
    expect(CsvExporter.countRows(b('h\na\nb\n')), 2);
    expect(CsvExporter.countRows(b('h\na\nb')), 2);
    expect(CsvExporter.countRows(const []), 0);
  });
}
