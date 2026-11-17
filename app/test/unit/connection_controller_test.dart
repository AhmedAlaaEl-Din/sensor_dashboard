import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_dashboard/features/connection/connection_controller.dart';
import 'package:sensor_dashboard/features/settings/models/app_settings.dart';
import 'package:sensor_dashboard/features/telemetry/telemetry_parser.dart';

import '../helpers/fake_gateway.dart';

void main() {
  test('backoff grows 1, 2, 4, 8 then caps at 10 s', () {
    expect([1, 2, 3, 4, 5, 9].map((n) => ConnectionController.defaultBackoff(n).inSeconds), [
      1,
      2,
      4,
      8,
      10,
      10,
    ]);
  });

  test('connects, subscribes, and forwards parsed messages', () async {
    final gw = FakeGateway();
    final received = <ParsedMessage>[];
    final c = ConnectionController(gateway: gw, onMessage: received.add);
    await c.start(const AppSettings());
    expect(c.status, ConnectionStatus.connected);
    expect(gw.subscriptions, ['sensors/+/telemetry', 'sensors/+/status']);

    gw.emitTelemetry('greenhouse', {'temperature': 21});
    gw.emit('sensors/greenhouse/status', 'online');
    gw.emit('sensors/greenhouse/telemetry', 'garbage');
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(2));
    expect(c.invalidMessageCount, 1);
    c.dispose();
  });

  test('failed connect goes offline with a friendly message, then retries', () {
    fakeAsync((async) {
      final gw = FakeGateway()..failConnect = true;
      final c = ConnectionController(gateway: gw, onMessage: (_) {});
      c.start(const AppSettings());
      async.flushMicrotasks();

      expect(c.status, ConnectionStatus.offline);
      expect(c.errorMessage, contains("Can't reach the broker at 127.0.0.1:1883"));
      expect(c.errorMessage, isNot(contains('OS Error')));
      expect(c.errorMessage, isNot(contains('Exception')));
      expect(gw.connectCalls, 1);

      async.elapse(const Duration(seconds: 1));
      expect(gw.connectCalls, 2);

      gw.failConnect = false;
      async.elapse(const Duration(seconds: 2));
      expect(gw.connectCalls, 3);
      expect(c.status, ConnectionStatus.connected);
      expect(c.errorMessage, isNull);
      c.dispose();
    });
  });

  test('dropped connection reconnects automatically', () {
    fakeAsync((async) {
      final gw = FakeGateway();
      final c = ConnectionController(gateway: gw, onMessage: (_) {});
      c.start(const AppSettings());
      async.flushMicrotasks();
      expect(c.status, ConnectionStatus.connected);

      gw.failConnect = true; // broker is down
      gw.dropConnection();
      async.flushMicrotasks();
      expect(c.status, ConnectionStatus.offline);

      gw.failConnect = false; // broker is back
      async.elapse(const Duration(seconds: 1));
      expect(c.status, ConnectionStatus.connected);
      c.dispose();
    });
  });

  test('retryNow skips the wait', () {
    fakeAsync((async) {
      final gw = FakeGateway()..failConnect = true;
      final c = ConnectionController(
        gateway: gw,
        onMessage: (_) {},
        backoff: (_) => const Duration(minutes: 5),
      );
      c.start(const AppSettings());
      async.flushMicrotasks();
      gw.failConnect = false;
      c.retryNow();
      async.flushMicrotasks();
      expect(c.status, ConnectionStatus.connected);
      c.dispose();
    });
  });

  test('changing settings reconnects with the new prefix', () async {
    final gw = FakeGateway();
    final c = ConnectionController(gateway: gw, onMessage: (_) {});
    await c.start(const AppSettings());
    await c.start(const AppSettings(topicPrefix: 'lab'));
    expect(gw.connectCalls, 2);
    expect(gw.subscriptions.last, 'lab/+/status');
    // Same settings again: no reconnect.
    await c.start(const AppSettings(topicPrefix: 'lab'));
    expect(gw.connectCalls, 2);
    c.dispose();
  });

  test('client id fits the MQTT 3.1 limit of 23 characters', () {
    // Regression: "sensor-dashboard-<hex>" (25 chars) was rejected on a real phone
    // with MqttConnectReturnCode.identifierRejected.
    for (var i = 0; i < 200; i++) {
      final id = ConnectionController.generateClientId();
      expect(id.length, lessThanOrEqualTo(23));
      expect(id, matches(RegExp(r'^sdash-[0-9a-f]{8}$')));
    }
  });

  test('broker rejection is reported as refused, not unreachable', () {
    final msg = ConnectionController.friendlyError(
      Exception(
        'NoConnectionException: The return code is MqttConnectReturnCode.identifierRejected',
      ),
      const AppSettings(),
    );
    expect(msg, 'The broker at 127.0.0.1:1883 refused the connection.');
  });

  test('friendlyError never leaks exception text', () {
    const s = AppSettings();
    for (final e in [
      const SocketException('boom'),
      TimeoutException('x'),
      StateError('internal detail'),
    ]) {
      final msg = ConnectionController.friendlyError(e, s);
      expect(msg, isNot(contains('boom')));
      expect(msg, isNot(contains('internal detail')));
      expect(msg, contains('127.0.0.1:1883'));
    }
  });
}
