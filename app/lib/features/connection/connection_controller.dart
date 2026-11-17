import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/mqtt/mqtt_gateway.dart';
import '../settings/models/app_settings.dart';
import '../telemetry/telemetry_parser.dart';

enum ConnectionStatus {
  /// Not started yet.
  idle,

  /// First attempt after start or after settings change.
  connecting,
  connected,

  /// Connection dropped; trying again right now.
  reconnecting,

  /// Last attempt failed; waiting before the next retry.
  offline,
}

/// Owns the broker connection: connect, subscribe, auto-reconnect with
/// backoff, and parse incoming messages.
class ConnectionController extends ChangeNotifier {
  ConnectionController({
    required MqttGateway gateway,
    required void Function(ParsedMessage message) onMessage,
    Duration Function(int failedAttempts)? backoff,
    String? clientId,
  }) : _gateway = gateway, // ignore: prefer_initializing_formals
       _onMessage = onMessage, // ignore: prefer_initializing_formals
       _backoff = backoff ?? defaultBackoff,
       _clientId = clientId ?? generateClientId() {
    _messageSub = _gateway.messages.listen(_handleRaw);
    _lostSub = _gateway.connectionLost.listen((_) => _handleLost());
  }

  /// MQTT 3.1 brokers may reject client ids longer than 23 characters, so keep
  /// it short: "sdash-" + 8 hex digits = 14 characters.
  static String generateClientId([Random? random]) =>
      'sdash-${(random ?? Random()).nextInt(1 << 32).toRadixString(16).padLeft(8, '0')}';

  /// 1 s, 2 s, 4 s, 8 s, then every 10 s.
  static Duration defaultBackoff(int failedAttempts) =>
      Duration(seconds: min(10, 1 << min(failedAttempts - 1, 4)).clamp(1, 10));

  final MqttGateway _gateway;
  final void Function(ParsedMessage) _onMessage;
  final Duration Function(int) _backoff;
  final String _clientId;

  late final StreamSubscription<RawMqttMessage> _messageSub;
  late final StreamSubscription<void> _lostSub;

  AppSettings? _settings;
  TelemetryParser? _parser;
  ConnectionStatus _status = ConnectionStatus.idle;
  String? _errorMessage;
  int _failedAttempts = 0;
  DateTime? _nextRetryAt;
  Timer? _retryTimer;
  int _generation = 0; // Ignores results from attempts made with old settings.
  bool _disposed = false;
  int invalidMessageCount = 0;

  ConnectionStatus get status => _status;

  /// Friendly, user-facing reason for the last failure. Never a raw exception.
  String? get errorMessage => _errorMessage;
  int get failedAttempts => _failedAttempts;
  DateTime? get nextRetryAt => _nextRetryAt;
  AppSettings? get settings => _settings;
  bool get isConnected => _status == ConnectionStatus.connected;
  String get brokerLabel => _settings == null ? 'broker' : '${_settings!.host}:${_settings!.port}';

  /// Connect with [settings]; reconnects if already connected with different settings.
  Future<void> start(AppSettings settings) async {
    final changed = _settings == null || _settings!.connectionDiffers(settings);
    _settings = settings;
    if (!changed && _status != ConnectionStatus.idle) return;
    _parser = TelemetryParser(prefix: settings.topicPrefix);
    _generation++;
    _cancelRetry();
    _gateway.disconnect();
    _failedAttempts = 0;
    _errorMessage = null;
    await _attempt(ConnectionStatus.connecting);
  }

  /// Skip the backoff wait and try now.
  Future<void> retryNow() async {
    if (_settings == null || _status == ConnectionStatus.connected) return;
    if (_status == ConnectionStatus.connecting || _status == ConnectionStatus.reconnecting) {
      return;
    }
    _cancelRetry();
    await _attempt(ConnectionStatus.reconnecting);
  }

  Future<void> _attempt(ConnectionStatus during) async {
    final s = _settings!;
    final gen = _generation;
    _setStatus(during);
    try {
      await _gateway.connect(host: s.host, port: s.port, clientId: _clientId);
      if (_disposed || gen != _generation) return;
      final prefix = TelemetryParser.normalizePrefix(s.topicPrefix);
      _gateway.subscribe('$prefix/+/telemetry');
      _gateway.subscribe('$prefix/+/status');
      _failedAttempts = 0;
      _errorMessage = null;
      _nextRetryAt = null;
      _setStatus(ConnectionStatus.connected);
    } catch (e) {
      if (_disposed || gen != _generation) return;
      debugPrint('MQTT connect failed: $e');
      _failedAttempts++;
      _errorMessage = friendlyError(e, s);
      _scheduleRetry();
    }
  }

  void _handleLost() {
    if (_disposed || _status != ConnectionStatus.connected) return;
    _errorMessage = 'Lost connection to the broker at $brokerLabel.';
    // Try once immediately; if that fails, back off.
    _attempt(ConnectionStatus.reconnecting);
  }

  void _scheduleRetry() {
    _cancelRetry();
    final delay = _backoff(_failedAttempts);
    _nextRetryAt = DateTime.now().add(delay);
    _setStatus(ConnectionStatus.offline);
    final gen = _generation;
    _retryTimer = Timer(delay, () {
      if (_disposed || gen != _generation) return;
      _attempt(ConnectionStatus.reconnecting);
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _nextRetryAt = null;
  }

  void _handleRaw(RawMqttMessage raw) {
    final parser = _parser;
    if (parser == null) return;
    final parsed = parser.parse(raw.topic, raw.payload);
    if (parsed is InvalidMessage) {
      invalidMessageCount++;
      debugPrint('Ignored MQTT message on ${raw.topic}: ${parsed.reason}');
      return;
    }
    _onMessage(parsed);
  }

  void _setStatus(ConnectionStatus s) {
    _status = s;
    if (!_disposed) notifyListeners();
  }

  /// Maps exceptions to text a user can act on.
  static String friendlyError(Object error, AppSettings s) {
    final where = '${s.host}:${s.port}';
    if (error is SocketException) {
      return "Can't reach the broker at $where. Check that it is running and that "
          '`adb reverse tcp:${s.port} tcp:${s.port}` is active.';
    }
    if (error is TimeoutException) {
      return 'The broker at $where did not answer in time.';
    }
    if (error is MqttRefusedException) {
      return 'The broker at $where refused the connection.';
    }
    final text = error.toString().toLowerCase();
    if (text.contains('returncode') ||
        text.contains('return code') ||
        text.contains('rejected') ||
        text.contains('notauthorized')) {
      return 'The broker at $where refused the connection.';
    }
    if (text.contains('socket') || text.contains('connection')) {
      return "Can't reach the broker at $where. Check that it is running and that "
          '`adb reverse tcp:${s.port} tcp:${s.port}` is active.';
    }
    return "Couldn't connect to the broker at $where.";
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRetry();
    _messageSub.cancel();
    _lostSub.cancel();
    _gateway.dispose();
    super.dispose();
  }
}
