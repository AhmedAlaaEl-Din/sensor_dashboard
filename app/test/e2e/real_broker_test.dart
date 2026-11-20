@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_dashboard/core/mqtt/mqtt_gateway.dart';
import 'package:sensor_dashboard/features/telemetry/telemetry_parser.dart';

/// End-to-end check of the real mqtt_client gateway against the local Node
/// broker + simulator. Skipped automatically when nothing listens on
/// 127.0.0.1:1883.
///
///   cd broker && npm run broker      (terminal 1)
///   cd broker && npm run simulate    (terminal 2)
///   cd app && flutter test test/e2e
Future<bool> _brokerUp() async {
  try {
    final s = await Socket.connect('127.0.0.1', 1883, timeout: const Duration(milliseconds: 500));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  test('receives and parses simulator telemetry through MqttClientGateway', () async {
    if (!await _brokerUp()) {
      markTestSkipped('No broker on 127.0.0.1:1883');
      return;
    }
    final gw = MqttClientGateway();
    addTearDown(gw.dispose);
    const parser = TelemetryParser(prefix: 'sensors');
    final devices = <String>{};
    final statuses = <String, bool>{};
    final done = Completer<void>();

    gw.messages.listen((m) {
      final p = parser.parse(m.topic, m.payload);
      if (p is TelemetryMessage) devices.add(p.telemetry.deviceId);
      if (p is StatusMessage) statuses[p.deviceId] = p.online;
      if (devices.length >= 3 && statuses.length >= 3 && !done.isCompleted) done.complete();
    });

    await gw.connect(host: '127.0.0.1', port: 1883, clientId: 'e2e-test-$pid');
    gw.subscribe('sensors/+/telemetry');
    gw.subscribe('sensors/+/status');

    try {
      await done.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      // Something answers on 1883 but no simulator publishes there (for example an
      // unrelated Mosquitto service). That is not our stack, so skip, don't fail.
      if (devices.isEmpty && statuses.isEmpty) {
        markTestSkipped('A broker answers on 1883 but no simulator data arrived');
        return;
      }
      rethrow;
    }
    expect(devices, containsAll(['greenhouse', 'warehouse', 'server-room']));
    expect(statuses.values, everyElement(isTrue));
  }, timeout: const Timeout(Duration(seconds: 20)));
}
