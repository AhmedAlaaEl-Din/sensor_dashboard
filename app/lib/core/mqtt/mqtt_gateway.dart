import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

    // One attempt per connect(): ConnectionController owns retries and backoff. (The default of 3
    // attempts waits connectTimeoutPeriod each time, so a dropped connection took 12 s to fail.)
    final client = MqttServerClient.withPort(host, clientId, port, maxConnectionAttempts: 1)
      ..logging(on: false)
      ..keepAlivePeriod = 10
      ..connectTimeoutPeriod = 4000
      ..autoReconnect =
          false // ConnectionController owns reconnect + backoff.
      ..setProtocolV311() // MQTT 3.1.1: longer client ids, wider broker support.
      ..connectionMessage = MqttConnectMessage().withClientIdentifier(clientId).startClean();

    final attempt = Completer<MqttClientConnectionStatus?>();
    void failAttempt(Object e, [StackTrace? s]) {
      if (!attempt.isCompleted) attempt.completeError(e, s);
    }

    client.onDisconnected = () {
      // Dropped before the broker accepted us: this attempt failed (not a "lost" connection).
      if (!attempt.isCompleted) return failAttempt(const SocketException('Connection closed'));
      if (!_intentionalDisconnect && !_lost.isClosed) _lost.add(null);
    };
    _client = client;

    // mqtt_client raises some socket errors from its own listeners instead of through the
    // connect() future. Through `adb reverse` with the broker down, the TCP connection is
    // accepted and then reset: that surfaced as an unhandled SocketException and connect()
    // hung. Catch those in a zone and turn them into a normal failed attempt.
    runZonedGuarded(
      () => client.connect().then((s) {
        if (!attempt.isCompleted) attempt.complete(s);
      }, onError: failAttempt),
      (e, s) {
        if (!attempt.isCompleted) return failAttempt(e, s);
        debugPrint('MQTT socket error after connect: $e');
        if (identical(_client, client) && !_intentionalDisconnect && !_lost.isClosed) {
          _teardownClient();
          _lost.add(null);
        }
      },
    );

    final MqttClientConnectionStatus? status;
    try {
      status = await attempt.future;
    } catch (_) {
      if (identical(_client, client)) _teardownClient();
      rethrow;
    }
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
