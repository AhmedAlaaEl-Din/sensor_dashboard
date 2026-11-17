import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// A raw message from the broker.
class RawMqttMessage {
  const RawMqttMessage(this.topic, this.payload);
  final String topic;
  final String payload;
}

/// Thin wrapper over an MQTT client so the rest of the app (and tests) do not
/// depend on mqtt_client directly.
abstract interface class MqttGateway {
  /// Throws on failure. Callers turn errors into friendly messages.
  Future<void> connect({required String host, required int port, required String clientId});

  void subscribe(String topic);

  /// Intentional disconnect. Does not emit on [connectionLost].
  void disconnect();

  Stream<RawMqttMessage> get messages;

  /// Emits when an established connection drops unexpectedly.
  Stream<void> get connectionLost;

  Future<void> dispose();
}

/// Real implementation over TCP using mqtt_client.
class MqttClientGateway implements MqttGateway {
  final _messages = StreamController<RawMqttMessage>.broadcast();
  final _lost = StreamController<void>.broadcast();
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;
  bool _intentionalDisconnect = false;

  @override
  Stream<RawMqttMessage> get messages => _messages.stream;

  @override
  Stream<void> get connectionLost => _lost.stream;

  @override
  Future<void> connect({required String host, required int port, required String clientId}) async {
    _teardownClient();
    _intentionalDisconnect = false;

    final client = MqttServerClient.withPort(host, clientId, port)
      ..logging(on: false)
      ..keepAlivePeriod = 10
      ..connectTimeoutPeriod = 4000
      ..autoReconnect =
          false // ConnectionController owns reconnect + backoff.
      ..setProtocolV311() // MQTT 3.1.1: longer client ids, wider broker support.
      ..connectionMessage = MqttConnectMessage().withClientIdentifier(clientId).startClean();

    client.onDisconnected = () {
      if (!_intentionalDisconnect && !_lost.isClosed) _lost.add(null);
    };
    _client = client;

    final status = await client.connect();
    if (status?.state != MqttConnectionState.connected) {
      _teardownClient();
      throw MqttRefusedException(status?.returnCode?.name ?? 'unknown');
    }

    _updatesSub = client.updates?.listen((batch) {
      for (final m in batch) {
        final publish = m.payload;
        if (publish is! MqttPublishMessage) continue;
        try {
          final text = utf8.decode(publish.payload.message.toList(), allowMalformed: true);
          _messages.add(RawMqttMessage(m.topic, text));
        } catch (e) {
          debugPrint('Dropping undecodable MQTT payload on ${m.topic}: $e');
        }
      }
    });
  }

  @override
  void subscribe(String topic) => _client?.subscribe(topic, MqttQos.atLeastOnce);

  @override
  void disconnect() {
    _intentionalDisconnect = true;
    _teardownClient();
  }

  void _teardownClient() {
    _updatesSub?.cancel();
    _updatesSub = null;
    final c = _client;
    _client = null;
    if (c != null) {
      c.onDisconnected = null;
      try {
        c.disconnect();
      } catch (_) {
        // Already gone.
      }
    }
  }

  @override
  Future<void> dispose() async {
    disconnect();
    await _messages.close();
    await _lost.close();
  }
}

class MqttRefusedException implements Exception {
  MqttRefusedException(this.code);
  final String code;
  @override
  String toString() => 'MqttRefusedException($code)';
}
