import 'dart:async';
import 'dart:io';

import 'package:sensor_dashboard/core/mqtt/mqtt_gateway.dart';

/// In-memory MQTT gateway for tests. No sockets.
class FakeGateway implements MqttGateway {
  // sync: messages reach the app immediately, so one pump() shows them.
  final _messages = StreamController<RawMqttMessage>.broadcast(sync: true);
  final _lost = StreamController<void>.broadcast();

  /// When set, connect() waits on this completer (to test loading states).
  Completer<void>? pendingConnect;

  /// When true, connect() throws a SocketException.
  bool failConnect = false;

  int connectCalls = 0;
  final List<String> subscriptions = [];
  bool connected = false;

  @override
  Stream<RawMqttMessage> get messages => _messages.stream;

  @override
  Stream<void> get connectionLost => _lost.stream;

  @override
  Future<void> connect({required String host, required int port, required String clientId}) async {
    connectCalls++;
    if (pendingConnect != null) await pendingConnect!.future;
    if (failConnect) {
      throw const SocketException('Connection refused (OS Error: errno = 111)');
    }
    connected = true;
  }

  @override
  void subscribe(String topic) => subscriptions.add(topic);

  @override
  void disconnect() => connected = false;

  void emit(String topic, String payload) => _messages.add(RawMqttMessage(topic, payload));

  void emitTelemetry(String device, Map<String, Object?> values, {String prefix = 'sensors'}) {
    final json = values.entries
        .map((e) => '"${e.key}": ${e.value is String ? '"${e.value}"' : e.value}')
        .join(', ');
    emit('$prefix/$device/telemetry', '{$json}');
  }

  /// Simulates the broker going away.
  void dropConnection() {
    connected = false;
    _lost.add(null);
  }

  @override
  Future<void> dispose() async {
    await _messages.close();
    await _lost.close();
  }
}
