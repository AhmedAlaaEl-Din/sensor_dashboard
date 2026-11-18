import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../core/api/api_client.dart';
import '../core/mqtt/mqtt_gateway.dart';
import '../features/alerts/alerts_controller.dart';
import '../features/alerts/notification_service.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/token_store.dart';
import '../features/connection/connection_controller.dart';
import '../features/device_detail/device_detail_screen.dart';
import '../features/history/csv_exporter.dart';
import '../features/settings/models/app_settings.dart';
import '../features/settings/settings_controller.dart';
import '../features/settings/settings_repository.dart';
import '../features/telemetry/device_store.dart';
import '../features/telemetry/telemetry_parser.dart';

/// Creates the controllers and wires them together:
/// - MQTT -> parser -> DeviceStore + AlertsController -> notifications
/// - Auth: live data runs only while signed in; thresholds come from the server
/// - Settings -> everything
class AppServices {
  AppServices({
    required MqttGateway gateway,
    required SettingsRepository repository,
    required TokenStore tokenStore,
    http.Client? httpClient,
    NotificationService? notifications,
    FileSharer? sharer,
    Future<Directory> Function()? exportDirectory,
    AppSettings initialSettings = const AppSettings(),
    Duration Function(int)? backoff,
    DateTime Function()? clock,
  }) {
    this.notifications = notifications ?? NoopNotificationService();
    this.sharer = sharer ?? SystemFileSharer();
    settings = SettingsController(repository, initialSettings);
    devices = DeviceStore();
    alerts = AlertsController(thresholds: initialSettings.thresholds)
      ..onTriggered = (a) => this.notifications.showAlert(a);
    api = ApiClient(
      baseUrl: () => settings.settings.apiUrl,
      token: () => auth.session?.token,
      client: httpClient,
      onUnauthorized: (m) => auth.handleUnauthorized(m),
    );
    auth = AuthController(store: tokenStore, login: api.login, clock: clock);
    exporter = CsvExporter(api: api, clock: clock, directory: exportDirectory);
    connection = ConnectionController(
      gateway: gateway,
      backoff: backoff,
      onMessage: (m) {
        switch (m) {
          case TelemetryMessage(:final telemetry):
            devices.addTelemetry(telemetry);
            alerts.evaluate(telemetry);
          case StatusMessage(:final deviceId, :final online):
            devices.setOnline(deviceId, online: online);
          case InvalidMessage():
            break;
        }
      },
    );
    _applied = initialSettings;
    settings.addListener(_onSettingsChanged);
    auth.addListener(_onAuthChanged);
  }

  late final NotificationService notifications;
  late final FileSharer sharer;
  late final SettingsController settings;
  late final DeviceStore devices;
  late final AlertsController alerts;
  late final ApiClient api;
  late final AuthController auth;
  late final CsvExporter exporter;
  late final ConnectionController connection;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  late AppSettings _applied;
  bool _wasSignedIn = false;
  String? _pendingDevice;

  Future<void> start() async {
    await notifications.init(onOpenDevice: openDevice);
    await auth.restore();
  }

  /// Opens a device (for example from a notification tap). Waits for sign-in if needed.
  void openDevice(String deviceId) {
    final nav = navigatorKey.currentState;
    if (!auth.isSignedIn || nav == null) {
      _pendingDevice = deviceId;
      return;
    }
    nav.popUntil((r) => r.isFirst);
    nav.push(MaterialPageRoute<void>(builder: (_) => DeviceDetailScreen(deviceId: deviceId)));
  }

  void _onAuthChanged() {
    final signedIn = auth.isSignedIn;
    if (signedIn == _wasSignedIn) return;
    _wasSignedIn = signedIn;
    if (signedIn) {
      connection.start(settings.settings);
      notifications.requestPermission();
      _syncThresholds();
      final pending = _pendingDevice;
      _pendingDevice = null;
      if (pending != null) WidgetsBinding.instance.addPostFrameCallback((_) => openDevice(pending));
    } else {
      connection.stop();
      devices.clear();
      alerts.reset();
      navigatorKey.currentState?.popUntil((r) => r.isFirst);
    }
  }

  /// Thresholds are shared and stored on the server; fall back to the local copy offline.
  Future<void> _syncThresholds() async {
    try {
      final t = await api.getThresholds();
      if (!auth.isSignedIn) return;
      await settings.save(settings.settings.copyWith(thresholds: t));
    } on ApiException catch (e) {
      debugPrint('Using locally saved thresholds: ${e.message}');
    }
  }

  void _onSettingsChanged() {
    final next = settings.settings;
    if (!identical(next.thresholds, _applied.thresholds)) {
      alerts.setThresholds(next.thresholds);
    }
    if (next.topicPrefix != _applied.topicPrefix) {
      // Devices under the old prefix no longer apply.
      devices.clear();
      alerts.reset();
    }
    if (next.connectionDiffers(_applied) && auth.isSignedIn) {
      connection.start(next);
    }
    _applied = next;
  }

  void dispose() {
    settings.removeListener(_onSettingsChanged);
    auth.removeListener(_onAuthChanged);
    connection.dispose();
    auth.dispose();
    settings.dispose();
    devices.dispose();
    alerts.dispose();
    api.close();
  }
}
