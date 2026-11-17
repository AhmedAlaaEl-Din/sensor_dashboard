import '../core/mqtt/mqtt_gateway.dart';
import '../features/alerts/alerts_controller.dart';
import '../features/connection/connection_controller.dart';
import '../features/settings/models/app_settings.dart';
import '../features/settings/settings_controller.dart';
import '../features/settings/settings_repository.dart';
import '../features/telemetry/device_store.dart';
import '../features/telemetry/telemetry_parser.dart';

/// Creates the controllers and wires them together:
/// MQTT -> parser -> DeviceStore + AlertsController; Settings -> everything.
class AppServices {
  AppServices({
    required MqttGateway gateway,
    required SettingsRepository repository,
    AppSettings initialSettings = const AppSettings(),
    Duration Function(int)? backoff,
  }) {
    settings = SettingsController(repository, initialSettings);
    devices = DeviceStore();
    alerts = AlertsController(thresholds: initialSettings.thresholds);
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
  }

  late final SettingsController settings;
  late final DeviceStore devices;
  late final AlertsController alerts;
  late final ConnectionController connection;
  late AppSettings _applied;

  Future<void> start() => connection.start(settings.settings);

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
    if (next.connectionDiffers(_applied)) {
      connection.start(next);
    }
    _applied = next;
  }

  void dispose() {
    settings.removeListener(_onSettingsChanged);
    connection.dispose();
    settings.dispose();
    devices.dispose();
    alerts.dispose();
  }
}
