import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_client.dart';
import 'history_models.dart';

/// A CSV file written to app storage, ready to share.
class CsvExport {
  const CsvExport({required this.file, required this.rows});
  final File file;

  /// Data rows (without the header).
  final int rows;

  String get fileName => file.uri.pathSegments.last;
}

/// Opens the Android share sheet. Behind an interface so tests don't need the plugin.
abstract interface class FileSharer {
  Future<void> shareFile(String path, {required String subject});
}

class SystemFileSharer implements FileSharer {
  @override
  Future<void> shareFile(String path, {required String subject}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'text/csv')],
        subject: subject,
      ),
    );
  }
}

/// Downloads a CSV for a range and saves it under the app's cache folder.
class CsvExporter {
  CsvExporter({
    required ApiClient api,
    Future<Directory> Function()? directory,
    DateTime Function()? clock,
  }) : _api = api,
       _directory = directory ?? getTemporaryDirectory,
       _clock = clock ?? DateTime.now;

  final ApiClient _api;
  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;

  /// Throws [ApiException] with a friendly message on failure.
  Future<CsvExport> export(String deviceId, HistoryRange range) async {
    final to = _clock();
    final download = await _api.exportCsv(
      deviceId,
      from: to.subtract(range.duration),
      to: to,
      bucket: range.exportBucket,
    );
    try {
      final dir = Directory('${(await _directory()).path}${Platform.pathSeparator}exports');
      await dir.create(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}${download.fileName}');
      await file.writeAsBytes(download.bytes, flush: true);
      return CsvExport(file: file, rows: countRows(download.bytes));
    } catch (e) {
      debugPrint('CSV save failed: ${e.runtimeType}');
      throw const ApiException(ApiErrorKind.server, "Couldn't save the file on this phone.");
    }
  }

  /// Number of data lines (newline-terminated, minus the header).
  static int countRows(List<int> bytes) {
    var lines = 0;
    for (final b in bytes) {
      if (b == 0x0A) lines++;
    }
    if (bytes.isNotEmpty && bytes.last != 0x0A) lines++;
    return lines > 0 ? lines - 1 : 0;
  }
}
