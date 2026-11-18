import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import 'history_models.dart';

/// Loads history for one device and range. One instance per History screen.
class HistoryController extends ChangeNotifier {
  HistoryController({required this.deviceId, required ApiClient api, DateTime Function()? clock})
    : _api = api,
      _clock = clock ?? DateTime.now;

  final String deviceId;
  final ApiClient _api;
  final DateTime Function() _clock;

  HistoryRange _range = HistoryRange.hour;
  HistoryData? _data;
  String? _error;
  bool _loading = false;
  int _request = 0;
  bool _disposed = false;

  HistoryRange get range => _range;
  HistoryData? get data => _data;
  String? get error => _error;
  bool get isLoading => _loading;

  Future<void> setRange(HistoryRange r) async {
    if (r == _range && _data != null) return;
    _range = r;
    _data = null; // Don't show the old range's chart under the new label.
    await load();
  }

  Future<void> load() async {
    final id = ++_request;
    _loading = true;
    _error = null;
    _notify();
    final to = _clock();
    try {
      final d = await _api.history(
        deviceId,
        from: to.subtract(_range.duration),
        to: to,
        bucket: _range.bucket,
      );
      if (id != _request) return;
      _data = d;
    } on ApiException catch (e) {
      if (id != _request) return;
      _error = e.message;
    } finally {
      if (id == _request) {
        _loading = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
