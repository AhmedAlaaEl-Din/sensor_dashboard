import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sensor_dashboard/features/auth/models/session.dart';

/// In-memory stand-in for the local API (no sockets), built on http's MockClient.
class FakeApi {
  FakeApi({DateTime? now}) : now = now ?? DateTime.now();

  DateTime now;
  final List<http.Request> requests = [];

  Map<String, dynamic> thresholds = {
    'temperature': {'min': 5, 'max': 35},
    'humidity': {'min': 20, 'max': 85},
    'pressure': {'min': 985, 'max': 1040},
    'battery': {'min': 20, 'max': null},
  };

  /// Set to make every call fail like an unreachable server.
  bool offline = false;

  static const adminToken = 'admin.token.x';
  static const viewerToken = 'viewer.token.x';

  static Session session(UserRole role, {required DateTime expiresAt}) => Session(
    token: role == UserRole.admin ? adminToken : viewerToken,
    email: role == UserRole.admin ? 'admin@example.com' : 'viewer@example.com',
    role: role,
    expiresAt: expiresAt,
  );

  /// Optional override for history responses.
  Map<String, dynamic> Function(Uri uri)? historyBody;

  http.Response _json(int status, Object body, [Map<String, String> headers = const {}]) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json', ...headers},
      );

  late final http.Client client = MockClient((req) async {
    requests.add(req);
    if (offline) throw http.ClientException('Connection refused');
    final auth = req.headers['Authorization'];
    final role = switch (auth) {
      'Bearer $adminToken' => 'admin',
      'Bearer $viewerToken' => 'viewer',
      _ => null,
    };
    final path = req.url.path;

    if (path == '/auth/login' && req.method == 'POST') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final email = body['email'], pw = body['password'];
      final who = switch ((email, pw)) {
        ('admin@example.com', 'admin-pass') => 'admin',
        ('viewer@example.com', 'viewer-pass') => 'viewer',
        _ => null,
      };
      if (who == null) return _json(401, {'error': 'Wrong email or password.'});
      return _json(200, {
        'token': who == 'admin' ? adminToken : viewerToken,
        'expiresAt': now.add(const Duration(minutes: 30)).toUtc().toIso8601String(),
        'user': {'email': email, 'role': who},
      });
    }

    if (role == null) return _json(401, {'error': 'Sign in required.'});

    if (path == '/thresholds' && req.method == 'GET') return _json(200, {'thresholds': thresholds});
    if (path == '/thresholds' && req.method == 'PUT') {
      if (role != 'admin') return _json(403, {'error': 'Only an admin can do this.'});
      thresholds = {...thresholds, ...(jsonDecode(req.body) as Map<String, dynamic>)};
      return _json(200, {'thresholds': thresholds});
    }

    final history = RegExp(r'^/devices/([^/]+)/history$').firstMatch(path);
    if (history != null) {
      final body = historyBody?.call(req.url) ?? sampleHistory(history.group(1)!, req.url);
      return _json(200, body);
    }

    final export = RegExp(r'^/devices/([^/]+)/export\.csv$').firstMatch(path);
    if (export != null) {
      final id = export.group(1);
      return http.Response(
        'timestamp,device_id,temperature,humidity,pressure,battery\n'
        '2026-11-18T10:00:00.000Z,$id,21.5,50,1013,90\n'
        '2026-11-18T10:01:00.000Z,$id,21.7,50,1013,90\n',
        200,
        headers: {
          'content-type': 'text/csv; charset=utf-8',
          'content-disposition': 'attachment; filename="${id}_202611181000-202611181100.csv"',
        },
      );
    }
    return _json(404, {'error': 'Not found.'});
  });

  /// 60 one-minute points ending at [now], temperature 20.0 → 25.9.
  Map<String, dynamic> sampleHistory(String id, Uri uri) {
    final to = DateTime.parse(uri.queryParameters['to']!);
    final from = DateTime.parse(uri.queryParameters['from']!);
    return {
      'deviceId': id,
      'bucket': uri.queryParameters['bucket'],
      'from': from.toIso8601String(),
      'to': to.toIso8601String(),
      'points': [
        for (var i = 0; i < 60; i++)
          {
            't': to.subtract(Duration(minutes: 60 - i)).toIso8601String(),
            'temperature': 20 + i / 10,
            'humidity': 50,
            'pressure': 1013,
            'battery': 90,
            'count': 60,
          },
      ],
      'stats': {
        'temperature': {'min': 19.5, 'max': 26.4, 'avg': 22.9, 'count': 3600},
        'humidity': {'min': 50, 'max': 50, 'avg': 50, 'count': 3600},
        'pressure': {'min': 1013, 'max': 1013, 'avg': 1013, 'count': 3600},
        'battery': {'min': 90, 'max': 90, 'avg': 90, 'count': 3600},
      },
    };
  }
}
