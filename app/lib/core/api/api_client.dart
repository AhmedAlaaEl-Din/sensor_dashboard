import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../features/alerts/models/alert_models.dart';
import '../../features/auth/models/session.dart';
import '../../features/history/history_models.dart';
import '../../features/telemetry/models/sensor_type.dart';

enum ApiErrorKind {
  network,
  unauthorized,
  forbidden,
  rateLimited,
  invalidRequest,
  server,
  badResponse,
}

/// An API failure with a message that is safe to show on screen.
class ApiException implements Exception {
  const ApiException(this.kind, this.message);
  final ApiErrorKind kind;
  final String message;

  @override
  String toString() => 'ApiException($kind, $message)';
}

/// A downloaded CSV file.
class CsvDownload {
  const CsvDownload({required this.fileName, required this.bytes});
  final String fileName;
  final List<int> bytes;
}

/// Talks to the local API (login, history, export, thresholds).
///
/// [baseUrl] and [token] are read on every call so settings and sessions can
/// change at runtime. [onUnauthorized] fires when a signed-in call gets a 401.
class ApiClient {
  ApiClient({
    required String Function() baseUrl,
    required String? Function() token,
    http.Client? client,
    this.onUnauthorized,
    this.timeout = const Duration(seconds: 10),
  }) : _baseUrl = baseUrl,
       _token = token,
       _client = client ?? http.Client();

  final String Function() _baseUrl;
  final String? Function() _token;
  final http.Client _client;
  final Duration timeout;
  void Function(String message)? onUnauthorized;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = _baseUrl().trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    bool authed = true,
  }) async {
    http.Response res;
    try {
      res = await request().timeout(timeout);
    } on TimeoutException {
      throw const ApiException(ApiErrorKind.network, 'The server did not answer in time.');
    } on SocketException {
      throw const ApiException(
        ApiErrorKind.network,
        "Can't reach the server. Check that it is running and the phone is connected.",
      );
    } on http.ClientException {
      throw const ApiException(
        ApiErrorKind.network,
        "Can't reach the server. Check that it is running and the phone is connected.",
      );
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res;

    final serverMessage = _errorMessage(res);
    switch (res.statusCode) {
      case 401:
        final msg = serverMessage ?? 'Please sign in again.';
        if (authed) onUnauthorized?.call(msg);
        throw ApiException(ApiErrorKind.unauthorized, msg);
      case 403:
        throw ApiException(
          ApiErrorKind.forbidden,
          serverMessage ?? 'You are not allowed to do this.',
        );
      case 429:
        throw ApiException(
          ApiErrorKind.rateLimited,
          serverMessage ?? 'Too many attempts. Try again in a few minutes.',
        );
      case 400:
        throw ApiException(
          ApiErrorKind.invalidRequest,
          serverMessage ?? 'The request was not accepted.',
        );
      default:
        debugPrint('API ${res.request?.url.path} failed with ${res.statusCode}');
        throw const ApiException(
          ApiErrorKind.server,
          'The server had a problem. Try again shortly.',
        );
    }
  }

  /// Uses the server's `{"error": "..."}` text only if it is short plain text.
  static String? _errorMessage(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      final msg = body is Map ? body['error'] : null;
      if (msg is String && msg.isNotEmpty && msg.length <= 200) return msg;
    } catch (_) {}
    return null;
  }

  Map<String, String> _headers({bool json = false}) {
    final t = _token();
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (t != null) 'Authorization': 'Bearer $t',
    };
  }

  Object? _decode(http.Response res) {
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw const ApiException(ApiErrorKind.badResponse, 'The server sent an unexpected answer.');
    }
  }

  Future<Session> login(String email, String password) async {
    final res = await _send(
      () => _client.post(
        _uri('/auth/login'),
        headers: _headers(json: true),
        body: jsonEncode({'email': email.trim(), 'password': password}),
      ),
      authed: false,
    );
    try {
      return Session.fromLoginJson(_decode(res)! as Map<String, dynamic>);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(ApiErrorKind.badResponse, 'The server sent an unexpected answer.');
    }
  }

  Future<HistoryData> history(
    String deviceId, {
    required DateTime from,
    required DateTime to,
    required String bucket,
  }) async {
    final res = await _send(
      () => _client.get(
        _uri('/devices/${Uri.encodeComponent(deviceId)}/history', {
          'from': from.toUtc().toIso8601String(),
          'to': to.toUtc().toIso8601String(),
          'bucket': bucket,
        }),
        headers: _headers(),
      ),
    );
    try {
      return HistoryData.fromJson(_decode(res)! as Map<String, dynamic>);
    } on ApiException {
      rethrow;
    } catch (e) {
      debugPrint('Bad history response: $e');
      throw const ApiException(
        ApiErrorKind.badResponse,
        'The server sent unexpected history data.',
      );
    }
  }

  Future<CsvDownload> exportCsv(
    String deviceId, {
    required DateTime from,
    required DateTime to,
    required String bucket,
  }) async {
    final res = await _send(
      () => _client.get(
        _uri('/devices/${Uri.encodeComponent(deviceId)}/export.csv', {
          'from': from.toUtc().toIso8601String(),
          'to': to.toUtc().toIso8601String(),
          'bucket': bucket,
        }),
        headers: _headers()..['Accept'] = 'text/csv',
      ),
    );
    final disposition = res.headers['content-disposition'] ?? '';
    final match = RegExp(r'filename="([A-Za-z0-9_.-]+)"').firstMatch(disposition);
    final name = match?.group(1) ?? '${deviceId}_export.csv';
    return CsvDownload(fileName: name, bytes: res.bodyBytes);
  }

  Future<Map<SensorType, SensorThreshold>> getThresholds() async {
    final res = await _send(() => _client.get(_uri('/thresholds'), headers: _headers()));
    return _parseThresholds(_decode(res));
  }

  Future<Map<SensorType, SensorThreshold>> putThresholds(Map<SensorType, SensorThreshold> t) async {
    final body = {for (final e in t.entries) e.key.key: e.value.toJson()};
    final res = await _send(
      () => _client.put(_uri('/thresholds'), headers: _headers(json: true), body: jsonEncode(body)),
    );
    return _parseThresholds(_decode(res));
  }

  static Map<SensorType, SensorThreshold> _parseThresholds(Object? json) {
    final map = (json is Map ? json['thresholds'] : null);
    if (map is! Map) {
      throw const ApiException(ApiErrorKind.badResponse, 'The server sent unexpected thresholds.');
    }
    final out = Map<SensorType, SensorThreshold>.of(defaultThresholds);
    for (final e in map.entries) {
      final sensor = SensorType.fromKey('${e.key}');
      if (sensor != null && e.value is Map<String, dynamic>) {
        out[sensor] = SensorThreshold.fromJson(e.value as Map<String, dynamic>);
      }
    }
    return out;
  }

  void close() => _client.close();
}
