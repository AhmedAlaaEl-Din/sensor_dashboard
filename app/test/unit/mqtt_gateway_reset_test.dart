import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_dashboard/core/mqtt/mqtt_gateway.dart';

/// On the phone, `adb reverse` accepts the TCP connection even when the broker on the computer is
/// down, then resets it. mqtt_client reported that reset as an *unhandled* SocketException
/// (seen in logcat on 2026-11-18). The gateway must turn it into a normal failed attempt.
void main() {
  test(
    'a connection that is accepted and then dropped fails connect() without uncaught errors',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(
        (s) => s.destroy(),
      ); // accept, then drop at once (like adb reverse, broker down)
      addTearDown(server.close);

      final uncaught = <Object>[];
      final gateway = MqttClientGateway();
      addTearDown(gateway.dispose);

      Object? thrown;
      await runZonedGuarded(() async {
        for (var i = 0; i < 3; i++) {
          try {
            await gateway
                .connect(host: '127.0.0.1', port: server.port, clientId: 'sdash-test$i')
                .timeout(const Duration(seconds: 8));
          } catch (e) {
            thrown = e;
          }
        }
        // Give stray socket errors a moment to surface.
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }, (e, _) => uncaught.add(e));

      expect(thrown, isNotNull, reason: 'connect() should fail');
      expect(thrown, isNot(isA<TimeoutException>()), reason: 'should fail fast, not hang');
      expect(uncaught, isEmpty, reason: 'socket errors must not escape as unhandled exceptions');
    },
  );
}
